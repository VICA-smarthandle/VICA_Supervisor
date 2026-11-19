#!/usr/bin/env python3
"""앱 '지도 수정'의 파일 쪽 판단입니다. ROS 를 쓰지 않습니다.

설계서: 루트 docs/superpowers/specs/2026-11-18-map-fix-erase-partial-scan-design.md

    앱 -> /vica/map_fix -> map_fix_node -> (이 파일) -> maps/<map_id>.{pgm,png}

keepout_mask.py 와 같은 이유로 판단을 노드에서 떼어 냈습니다 — 좌표와 파일 처리를
로봇 없이 시험할 수 있어야 합니다(test_map_fix_store.py).

**칸 순서가 둘입니다.** 이 파일의 pixels 는 **그림 순서**입니다 — 0행이 그림의 맨 위,
곧 y 가 큰 쪽입니다(pgm 그대로). 스캔 계산(map_fix_scan)은 vica_nav2.pose_score.MapGrid 의
**격자 순서**를 씁니다 — 0행이 origin_y 쪽입니다. 둘 사이는 `격자행 = height - 1 - 그림행`
하나로만 오갑니다(to_grid, cells_to_pixels).

**지도 값.** 검은 칸 0, 빈칸 254, 회색 칸 205 입니다. 지금 지도 yaml 은 전부
free_thresh 0.25 라 Nav2 는 205 도 빈칸으로 읽습니다(1 - 205/255 = 0.196 < 0.25).
그래서 회색 칸을 지우면 앱 그림만 바뀌고, 검은 칸을 지워야 AMCL 과 경로 계획이 바뀝니다.

지도 크기·origin·resolution 은 어디서도 바꾸지 않습니다. 목적지·레일·금지구역 좌표가
그 셋에 묶여 있기 때문입니다.
"""

from __future__ import annotations

import json
import math
import os
import shutil
import struct
import zlib
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any

import numpy as np

import keepout_mask as km

OCCUPIED = 0
FREE = 254
UNKNOWN = 205

# 한 번에 지울 수 있는 사각형 수. 앱 목록이 한 화면에 들어오는 양입니다.
MAX_RECTS = 10   # 한 번에 지울 수 있는 구역 수(11-19 사용자)
MAX_COORD_M = 1000.0   # 구역 좌표의 절댓값 상한(m)
# 이보다 작은 변은 손가락이 스친 것으로 봅니다. 지도 한 칸(0.05 m)과 같습니다.
MIN_RECT_M = 0.05

DEFAULT_FREE_THRESH = 0.25
DEFAULT_OCCUPIED_THRESH = 0.65

# 경계 위의 칸 중심이 부동소수 오차로 빠지지 않게 하는 여유입니다.
_EPS = 1e-9


class MapFixError(Exception):
    """앱에 그대로 돌려줄 수 있는 실패입니다. reason 은 분기용, message 는 사람용입니다."""

    def __init__(self, reason: str, message: str) -> None:
        super().__init__(message)
        self.reason = reason
        self.message = message


@dataclass(frozen=True)
class MapImage:
    """지도 한 장. pixels 는 (height, width) uint8, 그림 순서입니다."""

    meta: km.MapMeta
    pixels: np.ndarray
    free_thresh: float
    occupied_thresh: float


# ---------------------------------------------------------------------------
# 읽기
# ---------------------------------------------------------------------------


def _pnm_tokens(data: bytes, count: int) -> tuple[list[bytes], int]:
    """PNM 머리말에서 토큰 count 개와 그 뒤 첫 바이트 위치를 돌려줍니다. 주석(#)은 건너뜁니다."""
    tokens: list[bytes] = []
    position = 0
    while len(tokens) < count:
        while position < len(data) and data[position:position + 1].isspace():
            position += 1
        if position >= len(data):
            raise MapFixError("bad_map", "지도 그림의 머리말이 잘렸습니다.")
        if data[position:position + 1] == b"#":
            while position < len(data) and data[position:position + 1] != b"\n":
                position += 1
            continue
        start = position
        while position < len(data) and not data[position:position + 1].isspace():
            position += 1
        tokens.append(data[start:position])
    # 머리말 끝의 공백 한 글자 다음부터가 픽셀입니다.
    return tokens, position + 1


def _read_pgm(path: Path, width: int, height: int) -> np.ndarray:
    try:
        data = path.read_bytes()
    except OSError:
        raise MapFixError("no_map", f"지도 그림을 찾지 못했습니다: {path.name}") from None
    tokens, start = _pnm_tokens(data, 4)
    if tokens[0] != b"P5":
        raise MapFixError("bad_map", "지도 그림이 P5(pgm) 형식이 아닙니다.")
    try:
        file_width, file_height, maxval = (int(token) for token in tokens[1:])
    except ValueError:
        raise MapFixError("bad_map", "지도 그림의 크기를 읽지 못했습니다.") from None
    if maxval != 255:
        raise MapFixError("bad_map", "지도 그림의 밝기 단계가 255가 아닙니다.")
    if (file_width, file_height) != (width, height):
        raise MapFixError("bad_map", "지도 그림 크기가 지도 정보와 다릅니다.")
    body = data[start:start + width * height]
    if len(body) != width * height:
        raise MapFixError("bad_map", "지도 그림이 잘렸습니다.")
    return np.frombuffer(body, dtype=np.uint8).reshape(height, width).copy()


def _read_threshold(text: str, key: str, default: float) -> float:
    for line in text.splitlines():
        line = line.split("#", 1)[0]
        if ":" not in line:
            continue
        name, raw = line.split(":", 1)
        if name.strip() != key:
            continue
        try:
            value = float(raw.strip())
        except ValueError:
            return default
        return value if math.isfinite(value) else default
    return default


def load_map_image(maps_root: Path, map_id: str) -> MapImage:
    """지도 yaml 과 pgm 을 읽습니다. png 는 읽지 않습니다 — 정본은 pgm 입니다."""
    try:
        meta = km.read_map_meta(maps_root, map_id)
    except km.KeepoutError as error:
        raise MapFixError(error.reason, error.message) from None
    yaml_text = (maps_root / f"{km.validate_map_id(map_id)}.yaml").read_text(encoding="utf-8")
    pixels = _read_pgm(maps_root / meta.image_name, meta.width, meta.height)
    return MapImage(
        meta=meta,
        pixels=pixels,
        free_thresh=_read_threshold(yaml_text, "free_thresh", DEFAULT_FREE_THRESH),
        occupied_thresh=_read_threshold(yaml_text, "occupied_thresh", DEFAULT_OCCUPIED_THRESH),
    )


# ---------------------------------------------------------------------------
# 사각형 → 칸
# ---------------------------------------------------------------------------


def normalize_rects(raw: Any) -> list[dict]:
    """앱이 보낸 사각형 목록을 검사하고 x_min < x_max, y_min < y_max 로 정리합니다."""
    if not isinstance(raw, list) or not raw:
        raise MapFixError("bad_rect", "지울 구역이 없습니다.")
    if len(raw) > MAX_RECTS:
        raise MapFixError("too_many", f"한 번에 {MAX_RECTS}곳까지 지울 수 있습니다.")
    rects: list[dict] = []
    for index, item in enumerate(raw):
        try:
            x_a, x_b = float(item["x_min"]), float(item["x_max"])
            y_a, y_b = float(item["y_min"]), float(item["y_max"])
        except (KeyError, TypeError, ValueError):
            raise MapFixError("bad_rect", f"{index + 1}번 구역의 좌표가 올바르지 않습니다.") from None
        # 무한·아주 큰 값은 칸 범위 계산(math.ceil)에서 넘칩니다. 지도는 ±1 km 안입니다.
        if not all(math.isfinite(value) and abs(value) <= MAX_COORD_M for value in (x_a, x_b, y_a, y_b)):
            raise MapFixError("bad_rect", f"{index + 1}번 구역의 좌표가 올바르지 않습니다.")
        rect = {
            "x_min": min(x_a, x_b), "y_min": min(y_a, y_b),
            "x_max": max(x_a, x_b), "y_max": max(y_a, y_b),
        }
        if min(rect["x_max"] - rect["x_min"], rect["y_max"] - rect["y_min"]) < MIN_RECT_M - _EPS:
            raise MapFixError("too_small", f"{index + 1}번 구역이 너무 작습니다.")
        rects.append(rect)
    return rects


def _index_range(low: float, high: float, origin: float, resolution: float, count: int):
    """칸 중심 origin + (i + 0.5)·resolution 이 [low, high] 에 드는 i 의 범위(양 끝 포함)."""
    first = math.ceil((low - origin) / resolution - 0.5 - _EPS)
    last = math.floor((high - origin) / resolution - 0.5 + _EPS)
    first, last = max(first, 0), min(last, count - 1)
    return (first, last) if first <= last else None


def rect_cells(meta: km.MapMeta, rect: dict) -> tuple[slice, slice] | None:
    """사각형 안에 칸 중심이 드는 칸들을 (그림행, 열) slice 로 돌려줍니다. 전부 지도 밖이면 None."""
    cols = _index_range(rect["x_min"], rect["x_max"], meta.origin_x, meta.resolution, meta.width)
    rows = _index_range(rect["y_min"], rect["y_max"], meta.origin_y, meta.resolution, meta.height)
    if cols is None or rows is None:
        return None
    # 격자행(아래에서 위로) → 그림행(위에서 아래로)
    top, bottom = meta.height - 1 - rows[1], meta.height - 1 - rows[0]
    return slice(top, bottom + 1), slice(cols[0], cols[1] + 1)


# ---------------------------------------------------------------------------
# 지우기 계산
# ---------------------------------------------------------------------------


def _erase_plan(image: MapImage, rects: list[dict]) -> tuple[np.ndarray, dict]:
    rects = normalize_rects(rects)
    selected = np.zeros(image.pixels.shape, dtype=bool)
    per_rect = []
    for rect in rects:
        cells = rect_cells(image.meta, rect)
        black = gray = 0
        if cells is not None:
            part = image.pixels[cells]
            black = int((part == OCCUPIED).sum())
            gray = int((part == UNKNOWN).sum())
            selected[cells] = True
        per_rect.append({
            "w_m": round(rect["x_max"] - rect["x_min"], 2),
            "h_m": round(rect["y_max"] - rect["y_min"], 2),
            "black": black,
            "gray": gray,
        })
    if not selected.any():
        raise MapFixError("out_of_map", "구역이 지도 밖에 있습니다.")
    chosen = image.pixels[selected]
    counts = {
        "rects": per_rect,
        # 합계는 겹친 칸을 한 번만 셉니다.
        "black": int((chosen == OCCUPIED).sum()),
        "gray": int((chosen == UNKNOWN).sum()),
    }
    return selected, counts


def count_erase(image: MapImage, rects: list[dict]) -> dict:
    """지우면 바뀔 칸 수를 셉니다. 파일은 건드리지 않습니다."""
    return _erase_plan(image, rects)[1]


def apply_erase(image: MapImage, rects: list[dict]) -> tuple[np.ndarray, dict]:
    """사각형 안의 칸을 빈칸으로 바꾼 새 pixels 와 칸 수를 돌려줍니다. 원본은 그대로입니다."""
    selected, counts = _erase_plan(image, rects)
    pixels = image.pixels.copy()
    pixels[selected] = FREE
    return pixels, counts


# ---------------------------------------------------------------------------
# 쓰기
# ---------------------------------------------------------------------------


def encode_pgm(pixels: np.ndarray) -> bytes:
    height, width = pixels.shape
    return f"P5\n{width} {height}\n255\n".encode("ascii") + pixels.astype(np.uint8).tobytes()


def _png_chunk(tag: bytes, body: bytes) -> bytes:
    return struct.pack(">I", len(body)) + tag + body + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF)


def encode_png(pixels: np.ndarray) -> bytes:
    """8비트 회색 PNG 를 만듭니다. PIL 을 쓰지 않습니다 — 의존을 늘리지 않으려는 것입니다."""
    height, width = pixels.shape
    rows = np.zeros((height, width + 1), dtype=np.uint8)  # 줄마다 맨 앞에 필터 0
    rows[:, 1:] = pixels
    header = struct.pack(">IIBBBBB", width, height, 8, 0, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + _png_chunk(b"IHDR", header)
        + _png_chunk(b"IDAT", zlib.compress(rows.tobytes(), 6))
        + _png_chunk(b"IEND", b"")
    )


def map_paths(maps_root: Path, map_id: str) -> dict[str, Path]:
    """수정이 쓰는 두 파일. pgm 이름은 yaml 의 image 를 따릅니다."""
    try:
        meta = km.read_map_meta(maps_root, map_id)
    except km.KeepoutError as error:
        raise MapFixError(error.reason, error.message) from None
    return {
        "pgm": maps_root / meta.image_name,
        "png": maps_root / f"{km.validate_map_id(map_id)}.png",
    }


def _write_atomic(targets: list[tuple[Path, bytes]]) -> None:
    """km.write_all_atomic 과 같되, 이미 있던 파일의 권한을 그대로 둡니다.

    임시 파일은 600 으로 만들어져 바꾼 뒤에도 600 이 남았습니다(11-19 실기, 664 → 600).
    """
    modes = {}
    for path, _ in targets:
        try:
            modes[path] = path.stat().st_mode & 0o7777
        except OSError:
            pass
    km.write_all_atomic(targets)
    for path, mode in modes.items():
        try:
            os.chmod(path, mode)
        except OSError:
            pass   # 권한만 못 돌린 것 — 내용은 이미 바뀌었고 같은 사용자는 읽습니다


def write_map_pixels(maps_root: Path, map_id: str, pixels: np.ndarray) -> None:
    """pgm 과 png 를 임시 파일로 다 쓴 뒤 한꺼번에 바꿉니다. 크기가 다르면 쓰지 않습니다."""
    try:
        meta = km.read_map_meta(maps_root, map_id)
    except km.KeepoutError as error:
        raise MapFixError(error.reason, error.message) from None
    if pixels.shape != (meta.height, meta.width):
        raise MapFixError("bad_map", "지도 크기가 달라 쓰지 않았습니다.")
    paths = map_paths(maps_root, map_id)
    try:
        _write_atomic([
            (paths["pgm"], encode_pgm(pixels)),
            (paths["png"], encode_png(pixels)),
        ])
    except km.KeepoutError as error:
        raise MapFixError(error.reason, error.message) from None


# ---------------------------------------------------------------------------
# 그림 ↔ 격자
# ---------------------------------------------------------------------------


def to_grid(image: MapImage):
    """Nav2 가 읽는 것과 같은 점유 격자(pose_score.MapGrid, 격자 순서)를 만듭니다.

    Nav2 map_io.cpp 의 trinary 규칙 그대로입니다: occ = (255 - 픽셀)/255,
    occ > occupied_thresh 면 100, occ < free_thresh 면 0, 나머지는 -1.
    """
    from vica_nav2.pose_score import MapGrid  # 쉬는 동안 안 불러오려고 여기서 import 합니다

    occupancy = (255.0 - image.pixels.astype(np.float64)) / 255.0
    data = np.full(image.pixels.shape, -1, dtype=np.int8)
    data[occupancy < image.free_thresh] = 0
    data[occupancy > image.occupied_thresh] = 100
    return MapGrid(
        np.ascontiguousarray(data[::-1]),
        image.meta.resolution,
        image.meta.origin_x,
        image.meta.origin_y,
    )


def cells_to_pixels(cells: np.ndarray, height: int) -> np.ndarray:
    """격자 순서 (행, 열) 목록을 그림 순서 (행, 열) 로 바꿉니다."""
    flipped = np.array(cells, dtype=np.int64).reshape(-1, 2).copy()
    flipped[:, 0] = height - 1 - flipped[:, 0]
    return flipped


# ---------------------------------------------------------------------------
# 백업 · 기록 · 되돌리기
# ---------------------------------------------------------------------------
#
# 수정할 때마다 고치기 전 pgm·png 를 maps/.fix_backup/<map_id>/<시각>_<종류>/ 에 둡니다.
# 점 폴더라 앱 지도 목록(maps/*.png)에는 안 뜹니다(maps/.original 과 같은 관례).
#
# entry.json 을 **맨 마지막에** 씁니다. 그 파일이 있어야 온전한 백업으로 칩니다 —
# 복사 도중 전원이 나가 남은 반쪽 폴더는 기록에도 되돌리기에도 쓰지 않습니다.

BACKUP_DIRNAME = ".fix_backup"
KEEP_BACKUPS = 10
ENTRY_NAME = "entry.json"
ENTRY_KEYS = ("at", "kind", "radius_m", "added", "removed", "black", "gray", "rects", "pose")
_STAMP_LENGTH = len("20261119_101500")


def backup_root(maps_root: Path, map_id: str) -> Path:
    try:
        return maps_root / BACKUP_DIRNAME / km.validate_map_id(map_id)
    except km.KeepoutError as error:
        raise MapFixError(error.reason, error.message) from None


def _raw_entry(folder: Path) -> dict:
    try:
        entry = json.loads((folder / ENTRY_NAME).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return entry if isinstance(entry, dict) else {}


def _order(folder: Path) -> tuple[int, str, int]:
    """저장한 순번(entry.json 의 seq)이 먼저입니다. 벽시계는 폐쇄망·재부팅에서 뒤로 갈 수 있어
    폴더 이름의 시각은 순번이 없는 옛 백업에만 씁니다. 수정 시각(mtime)은 복사하면 바뀌어 믿지 않습니다."""
    seq = _raw_entry(folder).get("seq")
    name = folder.name
    tail = name.rsplit("_", 1)[-1]
    return (seq if isinstance(seq, int) else -1), name[:_STAMP_LENGTH], int(tail) if tail.isdigit() else 1


def _map_meta(maps_root: Path, map_id: str) -> km.MapMeta:
    try:
        return km.read_map_meta(maps_root, map_id)
    except km.KeepoutError as error:
        raise MapFixError(error.reason, error.message) from None


def _fsync(path: Path) -> None:
    """파일이나 폴더를 디스크에 내려씁니다. 전원이 나가도 '온전한' 백업에 빈 파일이 남지 않게."""
    descriptor = os.open(str(path), os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def _complete_backups(maps_root: Path, map_id: str) -> list[Path]:
    """온전한 백업 폴더들, 오래된 것부터."""
    root = backup_root(maps_root, map_id)
    if not root.is_dir():
        return []
    folders = [path for path in root.iterdir() if path.is_dir() and (path / ENTRY_NAME).is_file()]
    return sorted(folders, key=_order)


def _read_entry(folder: Path) -> dict:
    entry = _raw_entry(folder)
    return {key: entry.get(key) for key in ENTRY_KEYS}


def save_backup(maps_root: Path, map_id: str, kind: str, entry: dict, now: datetime) -> Path:
    """지금의 pgm·png 를 백업하고 그 폴더를 돌려줍니다. 끝나면 KEEP_BACKUPS 개만 남깁니다."""
    paths = map_paths(maps_root, map_id)
    meta = _map_meta(maps_root, map_id)
    root = backup_root(maps_root, map_id)
    stamp = now.strftime("%Y%m%d_%H%M%S")
    try:
        root.mkdir(parents=True, exist_ok=True)
        seqs = [_raw_entry(path).get("seq") for path in _complete_backups(maps_root, map_id)]
        seq = max([value for value in seqs if isinstance(value, int)], default=0) + 1
        same_second = [path for path in root.iterdir() if path.name.startswith(stamp)]
        suffix = f"_{len(same_second) + 1}" if same_second else ""
        folder = root / f"{stamp}_{kind}{suffix}"
        folder.mkdir()
        for path in paths.values():
            if path.is_file():
                shutil.copy2(path, folder / path.name)
                _fsync(folder / path.name)
        record = {key: entry.get(key) for key in ENTRY_KEYS}
        record["at"] = now.isoformat(timespec="seconds")
        record["kind"] = kind
        record["seq"] = seq
        # 되돌릴 때 지금 지도와 같은 지도인지 견줍니다(크기·해상도·원점).
        record["map"] = {"width": meta.width, "height": meta.height, "resolution": meta.resolution,
                         "origin_x": meta.origin_x, "origin_y": meta.origin_y}
        temp = folder / (ENTRY_NAME + ".tmp")
        temp.write_text(json.dumps(record, ensure_ascii=False), encoding="utf-8")
        _fsync(temp)
        os.replace(str(temp), str(folder / ENTRY_NAME))
        _fsync(folder)
        for old in _complete_backups(maps_root, map_id)[:-KEEP_BACKUPS]:
            shutil.rmtree(old, ignore_errors=True)
    except OSError as error:
        raise MapFixError("io_error", f"백업을 만들지 못했습니다: {error}") from error
    return folder


def list_history(maps_root: Path, map_id: str, limit: int = 3) -> list[dict]:
    """최근 수정 기록, 새것부터."""
    newest_first = reversed(_complete_backups(maps_root, map_id))
    return [_read_entry(folder) for folder in list(newest_first)[:limit]]


BACKUP_MISMATCH = "백업 지도가 지금 지도와 달라 되돌리지 않았습니다."


def restore_backup(maps_root: Path, map_id: str, backup: Path) -> None:
    """백업 폴더의 pgm·png 를 지금 자리에 원자적으로 되살립니다.

    지금 지도와 크기·해상도·원점이 다른 백업(그 사이 지도를 다시 맞춘 경우)이나 깨진 백업
    그림(전원이 나가 빈 파일)은 쓰지 않습니다 — 쓰면 지도가 어긋나거나 망가집니다.
    """
    paths = map_paths(maps_root, map_id)
    meta = _map_meta(maps_root, map_id)
    pgm_path = backup / paths["pgm"].name
    if not pgm_path.is_file():
        raise MapFixError("io_error", "백업에 지도 그림이 없어 되돌리지 못했습니다.")
    saved = _raw_entry(backup).get("map")
    if isinstance(saved, dict):
        same = (saved.get("width"), saved.get("height")) == (meta.width, meta.height) and all(
            isinstance(saved.get(key), (int, float)) and abs(float(saved[key]) - value) < 1e-9
            for key, value in (("resolution", meta.resolution), ("origin_x", meta.origin_x),
                               ("origin_y", meta.origin_y)))
        if not same:
            raise MapFixError("bad_map", BACKUP_MISMATCH)
    try:
        _read_pgm(pgm_path, meta.width, meta.height)   # 머리말·크기·잘림 검사
    except MapFixError:
        raise MapFixError("bad_map", BACKUP_MISMATCH) from None
    try:
        pgm = pgm_path.read_bytes()
        targets = [(paths["pgm"], pgm)]
        png_backup = backup / paths["png"].name
        if png_backup.is_file():
            targets.append((paths["png"], png_backup.read_bytes()))
    except OSError:
        raise MapFixError("io_error", "백업에 지도 그림이 없어 되돌리지 못했습니다.") from None
    try:
        _write_atomic(targets)
    except km.KeepoutError as error:
        raise MapFixError(error.reason, error.message) from None


def undo_last(maps_root: Path, map_id: str) -> dict:
    """가장 최근 수정을 되돌리고 그 기록을 돌려줍니다. 되돌린 백업은 지웁니다."""
    backups = _complete_backups(maps_root, map_id)
    if not backups:
        raise MapFixError("nothing_to_undo", "되돌릴 수정이 없습니다.")
    latest = backups[-1]
    entry = _read_entry(latest)
    restore_backup(maps_root, map_id, latest)
    drop_backup(latest)
    return entry


def drop_backup(backup: Path) -> None:
    """백업 폴더 하나를 지웁니다 — 수정이 실패해 필요 없어졌거나 되돌리기를 마쳤을 때."""
    shutil.rmtree(backup, ignore_errors=True)


def latest_backup(maps_root: Path, map_id: str) -> Path | None:
    """가장 최근의 온전한 백업 폴더. 없으면 None."""
    backups = _complete_backups(maps_root, map_id)
    return backups[-1] if backups else None


def read_entry(backup: Path) -> dict:
    """백업 폴더의 기록(entry.json). 없는 값은 None 입니다."""
    return _read_entry(backup)


def snapshot(maps_root: Path, map_id: str) -> list[tuple[Path, bytes]]:
    """지금의 pgm·png 를 메모리에 들어 둡니다 — 되돌리기를 Nav2 가 거부하면 도로 쓰려고."""
    paths = map_paths(maps_root, map_id)
    try:
        return [(path, path.read_bytes()) for path in paths.values() if path.is_file()]
    except OSError as error:
        raise MapFixError("io_error", f"지도 파일을 읽지 못했습니다: {error}") from error


def write_snapshot(targets: list[tuple[Path, bytes]]) -> None:
    """snapshot 으로 들어 둔 파일들을 원자적으로 도로 씁니다."""
    try:
        _write_atomic(targets)
    except km.KeepoutError as error:
        raise MapFixError(error.reason, error.message) from None
