#!/usr/bin/env python3
"""금지구역(keepout) 마스크 파일을 만드는 순수 로직입니다."""
from __future__ import annotations

import json
import math
import os
import re
import tempfile
from pathlib import Path
from typing import Any, Iterable

BLOCK = 0
SKIP = 128

MIN_SIZE_M = 0.1

MAP_ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$")

KEEPOUT_SUFFIXES = ("_keepout.pgm", "_keepout.yaml", "_keepout.json")


class KeepoutError(Exception):
    """앱에 그대로 돌려줄 수 있는 실패입니다."""

    def __init__(self, reason: str, message: str) -> None:
        super().__init__(message)
        self.reason = reason
        self.message = message


class MapMeta:
    """원본 지도 YAML과 이미지에서 읽어 온 값입니다."""

    def __init__(
        self,
        *,
        resolution: float,
        origin_x: float,
        origin_y: float,
        width: int,
        height: int,
        image_name: str,
    ) -> None:
        self.resolution = resolution
        self.origin_x = origin_x
        self.origin_y = origin_y
        self.width = width
        self.height = height
        self.image_name = image_name

    def __repr__(self) -> str:
        return (
            f"MapMeta({self.width}x{self.height} @ {self.resolution} m/px, "
            f"origin=({self.origin_x}, {self.origin_y}), image={self.image_name})"
        )


def validate_map_id(map_id: str) -> str:
    """경로 문자를 막아 maps/ 밖을 건드리지 못하게 합니다."""
    value = str(map_id or "").strip()
    if not MAP_ID_PATTERN.fullmatch(value):
        raise KeepoutError(
            "bad_map_id",
            "지도 이름이 올바르지 않습니다. 영문·숫자로 시작하고 밑줄(_)과 "
            "붙임표(-)만 쓸 수 있습니다.",
        )
    return value


def read_map_yaml(path: Path) -> dict[str, Any]:
    """ROS map yaml에서 image·resolution·origin만 읽습니다."""
    if not path.is_file():
        raise KeepoutError("no_map", f"지도 정보 파일을 찾지 못했습니다: {path.name}")
    values: dict[str, Any] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.split("#", 1)[0]
        if ":" not in line:
            continue
        key, raw = line.split(":", 1)
        key = key.strip()
        raw = raw.strip()
        if key == "image":
            values["image"] = raw.strip("'\"")
        elif key == "resolution":
            values["resolution"] = raw
        elif key == "origin":
            parts = [part.strip() for part in raw.strip("[]").split(",")]
            if len(parts) >= 2:
                values["origin_x"] = parts[0]
                values["origin_y"] = parts[1]
    return values


def _read_pnm_header(data: bytes) -> tuple[int, int, int]:
    """P5/P2 헤더에서 width, height, maxval을 읽습니다."""
    tokens: list[int] = []
    index = 2
    while len(tokens) < 3:
        while index < len(data) and data[index : index + 1].isspace():
            index += 1
        if index < len(data) and data[index : index + 1] == b"#":
            while index < len(data) and data[index : index + 1] not in (b"\n", b"\r"):
                index += 1
            continue
        start = index
        while index < len(data) and not data[index : index + 1].isspace():
            index += 1
        token = data[start:index]
        if not token.isdigit():
            raise KeepoutError("no_map", "지도 이미지 헤더를 읽지 못했습니다.")
        tokens.append(int(token))
    return tokens[0], tokens[1], tokens[2]


def read_image_size(path: Path) -> tuple[int, int]:
    """지도 이미지의 픽셀 크기를 읽습니다. PGM(P5/P2)과 PNG만 봅니다."""
    if not path.is_file():
        raise KeepoutError("no_map", f"지도 이미지를 찾지 못했습니다: {path.name}")
    data = path.read_bytes()
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return int.from_bytes(data[16:20], "big"), int.from_bytes(data[20:24], "big")
    if data[:2] in (b"P5", b"P2"):
        width, height, _ = _read_pnm_header(data)
        return width, height
    raise KeepoutError(
        "no_map",
        f"지도 이미지 형식을 읽지 못했습니다: {path.name} (PGM 또는 PNG만 됩니다)",
    )


def read_map_meta(maps_root: Path, map_id: str) -> MapMeta:
    """원본 지도의 YAML과 이미지를 읽어 변환에 필요한 값을 모읍니다."""
    map_id = validate_map_id(map_id)
    values = read_map_yaml(maps_root / f"{map_id}.yaml")

    try:
        resolution = float(values.get("resolution", ""))
    except (TypeError, ValueError):
        raise KeepoutError("bad_map", "지도의 resolution 값을 읽지 못했습니다.") from None
    if not math.isfinite(resolution) or resolution <= 0:
        raise KeepoutError("bad_map", "지도의 resolution이 0 이하입니다.")

    try:
        origin_x = float(values.get("origin_x", ""))
        origin_y = float(values.get("origin_y", ""))
    except (TypeError, ValueError):
        raise KeepoutError("bad_map", "지도의 origin 값을 읽지 못했습니다.") from None
    if not (math.isfinite(origin_x) and math.isfinite(origin_y)):
        raise KeepoutError("bad_map", "지도의 origin이 유한한 숫자가 아닙니다.")

    image_name = str(values.get("image", f"{map_id}.pgm"))
    image_path = maps_root / Path(image_name).name
    width, height = read_image_size(image_path)
    if width <= 0 or height <= 0:
        raise KeepoutError("bad_map", "지도 이미지 크기가 0입니다.")

    return MapMeta(
        resolution=resolution,
        origin_x=origin_x,
        origin_y=origin_y,
        width=width,
        height=height,
        image_name=image_path.name,
    )


def normalize_zone(raw: dict[str, Any], index: int) -> dict[str, Any]:
    """앱이 보낸 사각형 하나를 검증하고 min/max 형태로 정규화합니다."""
    if not isinstance(raw, dict):
        raise KeepoutError("bad_zone", f"{index + 1}번째 구역의 형식이 올바르지 않습니다.")

    try:
        x1 = float(raw["x_min"])
        y1 = float(raw["y_min"])
        x2 = float(raw["x_max"])
        y2 = float(raw["y_max"])
    except (KeyError, TypeError, ValueError):
        raise KeepoutError(
            "bad_zone",
            f"{index + 1}번째 구역에 x_min·y_min·x_max·y_max가 필요합니다.",
        ) from None

    if not all(math.isfinite(value) for value in (x1, y1, x2, y2)):
        raise KeepoutError("bad_zone", f"{index + 1}번째 구역 좌표가 숫자가 아닙니다.")

    x_min, x_max = (x1, x2) if x1 <= x2 else (x2, x1)
    y_min, y_max = (y1, y2) if y1 <= y2 else (y2, y1)

    if (x_max - x_min) < MIN_SIZE_M or (y_max - y_min) < MIN_SIZE_M:
        raise KeepoutError(
            "too_small",
            f"구역이 너무 작습니다. 가로·세로 모두 {MIN_SIZE_M:.2f} m 이상으로 "
            "그려 주세요.",
        )

    zone_id = str(raw.get("zone_id") or "").strip() or f"kz_{index + 1:02d}"
    return {
        "zone_id": zone_id,
        "name": str(raw.get("name") or "").strip(),
        "x_min": x_min,
        "y_min": y_min,
        "x_max": x_max,
        "y_max": y_max,
    }


def zone_to_pixels(zone: dict[str, Any], meta: MapMeta) -> tuple[int, int, int, int]:
    """ROS map 좌표 사각형을 이미지 픽셀 범위로 바꿉니다."""
    resolution = meta.resolution
    left = math.floor((zone["x_min"] - meta.origin_x) / resolution)
    right = math.floor((zone["x_max"] - meta.origin_x) / resolution)
    row_of_y_min = meta.height - 1 - math.floor(
        (zone["y_min"] - meta.origin_y) / resolution
    )
    row_of_y_max = meta.height - 1 - math.floor(
        (zone["y_max"] - meta.origin_y) / resolution
    )
    top, bottom = sorted((row_of_y_min, row_of_y_max))

    if right < 0 or left > meta.width - 1 or bottom < 0 or top > meta.height - 1:
        raise KeepoutError(
            "out_of_map",
            f"'{zone['zone_id']}' 구역이 지도 밖에 있습니다.",
        )

    return (
        max(0, left),
        max(0, top),
        min(meta.width - 1, right),
        min(meta.height - 1, bottom),
    )


def render_pgm(
    width: int,
    height: int,
    rects: Iterable[tuple[int, int, int, int]],
) -> bytes:
    """회색 바탕에 검은 사각형을 칠한 P5 PGM 바이트를 만듭니다."""
    header = f"P5\n{width} {height}\n255\n".encode("ascii")
    cells = bytearray([SKIP]) * (width * height)
    for left, top, right, bottom in rects:
        span = bytes([BLOCK]) * (right - left + 1)
        for row in range(top, bottom + 1):
            start = row * width + left
            cells[start : start + len(span)] = span
    return header + bytes(cells)


def keepout_yaml_text(meta: MapMeta, mask_name: str) -> str:
    """마스크용 map yaml을 만듭니다."""
    return (
        f"image: {mask_name}\n"
        "mode: trinary\n"
        f"resolution: {meta.resolution}\n"
        f"origin: [{meta.origin_x}, {meta.origin_y}, 0]\n"
        "negate: 0\n"
        "occupied_thresh: 0.65\n"
        "free_thresh: 0.25\n"
    )


def zones_json_text(map_id: str, zones: list[dict[str, Any]], updated_at: str) -> str:
    """앱이 다시 불러와 고치는 편집 원본입니다. 마스크는 여기서 다시 만들 수 있습니다."""
    payload = {"map_id": map_id, "updated_at": updated_at, "zones": zones}
    return json.dumps(payload, ensure_ascii=False, indent=2) + "\n"


def keepout_paths(maps_root: Path, map_id: str) -> dict[str, Path]:
    """지도 하나에 딸린 keepout 파일 경로 세 개입니다."""
    return {
        "mask": maps_root / f"{map_id}_keepout.pgm",
        "yaml": maps_root / f"{map_id}_keepout.yaml",
        "json": maps_root / f"{map_id}_keepout.json",
    }


def _write_temp(directory: Path, data: bytes) -> Path:
    """같은 디렉터리에 임시 파일을 만듭니다. os.replace가 같은 파일시스템을 요구합니다."""
    handle, tmp_name = tempfile.mkstemp(
        dir=str(directory), prefix=".keepout_", suffix=".tmp"
    )
    try:
        with os.fdopen(handle, "wb") as file:
            file.write(data)
            file.flush()
            os.fsync(file.fileno())
    except OSError:
        Path(tmp_name).unlink(missing_ok=True)
        raise
    return Path(tmp_name)


def write_all_atomic(targets: list[tuple[Path, bytes]]) -> None:
    """여러 파일을 임시로 다 쓴 뒤 한꺼번에 교체합니다."""
    temps: list[tuple[Path, Path]] = []
    try:
        for path, data in targets:
            temps.append((_write_temp(path.parent, data), path))
    except OSError as error:
        for tmp, _ in temps:
            tmp.unlink(missing_ok=True)
        raise KeepoutError("io_error", f"파일을 쓰지 못했습니다: {error}") from error

    for tmp, path in temps:
        try:
            os.replace(str(tmp), str(path))
        except OSError as error:
            for leftover, _ in temps:
                leftover.unlink(missing_ok=True)
            raise KeepoutError("io_error", f"파일을 바꾸지 못했습니다: {error}") from error


def save_zones(
    maps_root: Path,
    map_id: str,
    raw_zones: list[dict[str, Any]],
    updated_at: str,
) -> dict[str, Any]:
    """사각형 목록을 받아 마스크·YAML·JSON 세 파일을 만듭니다."""
    map_id = validate_map_id(map_id)
    meta = read_map_meta(maps_root, map_id)

    zones = [normalize_zone(raw, index) for index, raw in enumerate(raw_zones)]
    seen: set[str] = set()
    for zone in zones:
        if zone["zone_id"] in seen:
            raise KeepoutError("bad_zone", f"구역 id가 겹칩니다: {zone['zone_id']}")
        seen.add(zone["zone_id"])

    rects = [zone_to_pixels(zone, meta) for zone in zones]
    paths = keepout_paths(maps_root, map_id)
    write_all_atomic(
        [
            (paths["mask"], render_pgm(meta.width, meta.height, rects)),
            (paths["yaml"], keepout_yaml_text(meta, paths["mask"].name).encode("utf-8")),
            (paths["json"], zones_json_text(map_id, zones, updated_at).encode("utf-8")),
        ]
    )
    return {"map_id": map_id, "zones": zones, "paths": paths, "meta": meta}


def load_zones(maps_root: Path, map_id: str) -> list[dict[str, Any]]:
    """저장해 둔 편집 원본을 읽습니다. 없으면 빈 목록입니다."""
    map_id = validate_map_id(map_id)
    path = keepout_paths(maps_root, map_id)["json"]
    if not path.is_file():
        return []
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise KeepoutError("io_error", f"구역 파일을 읽지 못했습니다: {error}") from error
    zones = payload.get("zones", [])
    if not isinstance(zones, list):
        raise KeepoutError("io_error", "구역 파일 형식이 올바르지 않습니다.")
    return zones


def ensure_mask(maps_root: Path, map_id: str, updated_at: str) -> bool:
    """마스크가 없으면 빈 것을 만들어 둡니다. 만들었으면 True입니다."""
    map_id = validate_map_id(map_id)
    paths = keepout_paths(maps_root, map_id)
    if paths["mask"].is_file() and paths["yaml"].is_file():
        return False
    save_zones(maps_root, map_id, load_zones(maps_root, map_id), updated_at)
    return True


def hold_apply(status: str, current_goal: str) -> bool:
    """마스크 반영을 미뤄야 하는가 — '목적지가 살아 있는가'로 판정합니다."""
    if str(current_goal or "").strip():
        return True
    return str(status or "") == "moving"
