#!/usr/bin/env python3
"""금지구역(keepout) 마스크 파일을 만드는 순수 로직입니다.

ROS를 import하지 않습니다. 좌표 계산과 파일 쓰기는 로봇 없이 노트북에서
검증할 수 있어야 하기 때문입니다. vica_destination_manager의 storage.py와 같은
구성입니다 — 노드는 얇게, 판단은 여기에.

마스크는 원본 지도와 같은 크기의 8bit 회색 이미지이고, 쓰는 값은 둘뿐입니다.

    BLOCK 0    금지. trinary에서 occ 1.0 -> 점유(100) -> costmap 254(LETHAL)
    SKIP  128  아무 말도 하지 않음. occ 0.498 -> unknown(-1)

흰색(254, free)을 배경으로 쓰지 않는 이유가 이 파일의 핵심 결정입니다.
Humble의 keepout_filter.cpp는 이렇게 씁니다.

    if (data == NO_INFORMATION) { continue; }              # 마스크가 '모름'이면 건너뛴다
    if (data > old_data || old_data == NO_INFORMATION) {   # 그 외에는 덮어쓴다

즉 흰색은 costmap이 "여긴 모르겠다"고 둔 칸을 "비어 있다"로 덮어씁니다. 회색은
필터가 통째로 건너뛰므로, 사각형이 하나도 없는 마스크가 완전한 무동작이 됩니다.
빈 마스크가 아무 일도 하지 않는다는 성질이 있어야 launch가 항상 같은 모양일 수
있습니다(마스크 없는 지도에도 빈 마스크를 만들어 두기 때문입니다).

PNG가 아니라 PGM인 이유는 두 가지입니다.
  1. 앱 지도 목록이 maps/*.png를 훑습니다(map_list_node.publish_maps).
     _keepout.png를 만들면 지도 드롭다운에 유령 지도가 하나 더 생깁니다.
  2. P5 PGM은 헤더 한 줄 + 바이트라 표준 라이브러리만으로 씁니다. Pillow도
     ImageMagick도 필요 없습니다. nav2 map_server는 PGM/PNG/BMP를 다 읽습니다.
"""
from __future__ import annotations

import json
import math
import os
import re
import tempfile
from pathlib import Path
from typing import Any, Iterable

# 마스크 픽셀 값. 위 설명의 근거를 바꾸지 않고는 이 두 값을 바꾸지 않습니다.
BLOCK = 0
SKIP = 128

# 사각형 최소 변 길이(m). 이보다 작으면 손이 미끄러진 것으로 봅니다.
# 지도 해상도 0.05 m 기준으로 2칸입니다.
MIN_SIZE_M = 0.1

# 파일 경로로 안전한 지도 이름만 받습니다. vica_destination_manager의
# validate_map_id와 같은 규칙이어야 합니다 — 같은 map_id가 두 저장소를 오갑니다.
MAP_ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$")

# keepout 파일 접미사. 지도 삭제와 이름 재사용 검사가 이 목록을 함께 봐야 합니다.
KEEPOUT_SUFFIXES = ("_keepout.pgm", "_keepout.yaml", "_keepout.json")


class KeepoutError(Exception):
    """앱에 그대로 돌려줄 수 있는 실패입니다.

    reason은 앱이 분기에 쓰는 코드이고, message는 사람이 읽는 문장입니다.
    PoseCheck.srv가 reason/message를 나눠 둔 것과 같은 이유입니다 — 화면 문구를
    노드가 정하면 문구를 바꿀 때마다 로봇을 다시 띄워야 합니다.
    """

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

    def __repr__(self) -> str:  # 시험 실패 메시지를 읽을 수 있게 합니다.
        return (
            f"MapMeta({self.width}x{self.height} @ {self.resolution} m/px, "
            f"origin=({self.origin_x}, {self.origin_y}), image={self.image_name})"
        )


# ---------------------------------------------------------------------------
# 읽기
# ---------------------------------------------------------------------------


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
    """ROS map yaml에서 image·resolution·origin만 읽습니다.

    yaml 패키지를 쓰지 않는 것은 map_list_node._read_yaml_like_metadata와 같은
    사정입니다. 이 노드는 vica_interfaces를 빌드하지 않은 환경에서도 떠야 합니다.
    """
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
    """P5/P2 헤더에서 width, height, maxval을 읽습니다.

    PNM 헤더는 공백과 주석(#)이 자유롭게 섞일 수 있어 한 줄씩 읽으면 틀립니다.
    토큰 단위로 읽습니다.
    """
    tokens: list[int] = []
    index = 2  # 매직 넘버 다음부터
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
        # IHDR은 항상 첫 청크입니다. 8(서명) + 8(길이·타입) 다음이 width·height입니다.
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


# ---------------------------------------------------------------------------
# 좌표
# ---------------------------------------------------------------------------


def normalize_zone(raw: dict[str, Any], index: int) -> dict[str, Any]:
    """앱이 보낸 사각형 하나를 검증하고 min/max 형태로 정규화합니다.

    앱은 손가락을 어느 방향으로 끌든 시작점과 끝점을 그대로 보냅니다. 오른쪽
    아래에서 왼쪽 위로 끌면 min이 max보다 커지므로 여기서 바로잡습니다.
    """
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
    """ROS map 좌표 사각형을 이미지 픽셀 범위로 바꿉니다.

    돌려주는 값은 (left, top, right, bottom)이고 네 값 모두 포함(inclusive)입니다.

    y가 뒤집히는 이유: ROS는 y가 위로 커지고, 이미지는 행 번호가 아래로 커집니다.
    그래서 아래에서 센 행을 height-1에서 빼서 위에서 센 행으로 바꿉니다.

    칸 경계에 딱 걸린 좌표는 floor 때문에 한 칸(5 cm) 크게 잡힐 수 있습니다.
    금지구역에서는 넓게 잡히는 쪽이 안전한 방향이라 그대로 둡니다.
    """
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


# ---------------------------------------------------------------------------
# 만들기
# ---------------------------------------------------------------------------


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
    """마스크용 map yaml을 만듭니다.

    resolution·origin은 원본과 같아야 마스크가 지도 위에 정확히 겹칩니다.
    origin의 세 번째 값(yaw)은 반드시 0입니다 — Costmap2D는 회전을 지원하지 않습니다.

    임계값을 원본에서 베끼지 않고 여기 직접 적는 이유: 배경 128이 '모름'으로
    읽히려면 free_thresh < 0.498 < occupied_thresh 여야 합니다. 원본을 따라가면
    나중에 원본 임계값을 손볼 때 마스크의 뜻이 조용히 바뀝니다.
    """
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


# ---------------------------------------------------------------------------
# 파일
# ---------------------------------------------------------------------------


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
    """여러 파일을 임시로 다 쓴 뒤 한꺼번에 교체합니다.

    한 파일씩 쓰다가 중간에 실패하면 마스크는 새것인데 JSON은 옛것인 상태가
    남습니다. 그 상태는 화면에 드러나지 않으므로 조용히 틀립니다.
    """
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
    """사각형 목록을 받아 마스크·YAML·JSON 세 파일을 만듭니다.

    앱은 언제나 전체 목록을 보냅니다. 부분 수정 규약이 없으므로 삭제도 그냥
    '그 사각형이 빠진 목록'입니다.
    """
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
    """마스크가 없으면 빈 것을 만들어 둡니다. 만들었으면 True입니다.

    launch 구조를 항상 같게 하려는 것입니다. 배경이 전부 회색이라 이 마스크는
    costmap에 아무 일도 하지 않습니다(이 파일 맨 위 설명 참고).
    """
    map_id = validate_map_id(map_id)
    paths = keepout_paths(maps_root, map_id)
    if paths["mask"].is_file() and paths["yaml"].is_file():
        return False
    save_zones(maps_root, map_id, load_zones(maps_root, map_id), updated_at)
    return True
