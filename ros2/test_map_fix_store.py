"""map_fix_store 시험입니다. 로봇 없이 pytest 로 돌립니다.

    python3 -m pytest -q VICA_Supervisor/ros2/test_map_fix_store.py

지도는 test_keepout_mask.make_map 이 만드는 가짜 지도를 씁니다 — 가로 10칸 × 세로 8칸,
한 칸 0.1 m, origin (-0.5, -0.4), 전부 254(빈칸)입니다.
"""

from __future__ import annotations

import os
import struct
import sys
import zlib
from pathlib import Path

import numpy as np
import pytest

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))


def nav2_src() -> Path | None:
    """vica_nav2 소스 폴더를 찾습니다. 설치본이 이미 잡혀 있으면 None 입니다.

    운영 배치(VICA-smarthandle/{VICA_Supervisor,vica_ros2_ws})와 작업 폴더 배치
    (~/wt-map-fix-app, ~/wt-map-fix)를 둘 다 봅니다. 환경 변수 VICA_NAV2_SRC 가 먼저입니다.
    """
    candidates = [
        os.environ.get("VICA_NAV2_SRC", ""),
        str(HERE.parents[1] / "vica_ros2_ws" / "src" / "vica_nav2"),
        str(HERE.parents[1] / "wt-map-fix" / "src" / "vica_nav2"),
    ]
    for candidate in candidates:
        if candidate and (Path(candidate) / "vica_nav2" / "pose_score.py").is_file():
            return Path(candidate)
    return None


_NAV2 = nav2_src()
if _NAV2 is not None:
    sys.path.insert(0, str(_NAV2))

import map_fix_store as store  # noqa: E402
from test_keepout_mask import HEIGHT, WIDTH, make_map  # noqa: E402

MAP = "test_map"
# 칸 중심이 x 0.05·0.15(열 5·6), y 0.05(격자행 4 = 그림행 3)인 두 칸을 덮습니다.
RECT = {"x_min": 0.0, "y_min": 0.0, "x_max": 0.2, "y_max": 0.1}


def put(root: Path, cells: dict[tuple[int, int], int]) -> None:
    """가짜 지도의 픽셀을 바꿉니다. 좌표는 그림 순서 (행, 열)입니다."""
    path = root / f"{MAP}.pgm"
    data = bytearray(path.read_bytes())
    start = len(data) - WIDTH * HEIGHT
    for (row, col), value in cells.items():
        data[start + row * WIDTH + col] = value
    path.write_bytes(bytes(data))


def reason_of(call) -> str:
    with pytest.raises(store.MapFixError) as caught:
        call()
    return caught.value.reason


# ---------------------------------------------------------------------------
# 사각형 → 칸
# ---------------------------------------------------------------------------


def test_cell_centres_decide_membership(tmp_path):
    image = store.load_map_image(make_map(tmp_path), MAP)
    assert store.rect_cells(image.meta, RECT) == (slice(3, 4), slice(5, 7))


def test_rect_is_clipped_to_the_map_and_fully_outside_is_none(tmp_path):
    image = store.load_map_image(make_map(tmp_path), MAP)
    wide = {"x_min": -9.0, "y_min": -9.0, "x_max": 0.0, "y_max": 9.0}
    # x 가 0.0 이하인 칸 중심은 열 0~4(-0.45 ~ -0.05)입니다.
    assert store.rect_cells(image.meta, wide) == (slice(0, HEIGHT), slice(0, 5))
    outside = {"x_min": 5.0, "y_min": 0.0, "x_max": 6.0, "y_max": 1.0}
    assert store.rect_cells(image.meta, outside) is None


# ---------------------------------------------------------------------------
# 지우기 계산
# ---------------------------------------------------------------------------


def test_counts_black_and_gray_and_totals_count_overlap_once(tmp_path):
    root = make_map(tmp_path)
    put(root, {(3, 5): store.OCCUPIED, (3, 6): store.UNKNOWN})
    image = store.load_map_image(root, MAP)
    narrow = {"x_min": 0.0, "y_min": 0.0, "x_max": 0.1, "y_max": 0.1}  # 열 5 만

    counts = store.count_erase(image, [RECT, narrow])

    assert counts["rects"][0] == {"w_m": 0.2, "h_m": 0.1, "black": 1, "gray": 1}
    assert counts["rects"][1] == {"w_m": 0.1, "h_m": 0.1, "black": 1, "gray": 0}
    assert (counts["black"], counts["gray"]) == (1, 1)  # 겹친 칸은 한 번만


def test_apply_erase_sets_only_selected_cells_to_free(tmp_path):
    root = make_map(tmp_path)
    put(root, {(3, 5): store.OCCUPIED, (3, 6): store.UNKNOWN, (0, 0): store.OCCUPIED})
    image = store.load_map_image(root, MAP)
    before = image.pixels.copy()

    pixels, counts = store.apply_erase(image, [RECT])

    assert pixels[3, 5] == store.FREE and pixels[3, 6] == store.FREE
    untouched = np.ones(pixels.shape, dtype=bool)
    untouched[3, 5:7] = False
    assert np.array_equal(pixels[untouched], before[untouched])  # (0, 0) 의 검은 칸은 그대로
    assert np.array_equal(image.pixels, before)  # 원본은 안 바뀜
    assert counts == store.count_erase(image, [RECT])


def test_rect_errors(tmp_path):
    image = store.load_map_image(make_map(tmp_path), MAP)
    assert reason_of(lambda: store.normalize_rects([RECT] * 21)) == "too_many"
    thin = {"x_min": 0.0, "y_min": 0.0, "x_max": 0.04, "y_max": 0.3}
    assert reason_of(lambda: store.normalize_rects([thin])) == "too_small"
    assert reason_of(lambda: store.normalize_rects([{"x_min": "a"}])) == "bad_rect"
    assert reason_of(lambda: store.normalize_rects([])) == "bad_rect"
    assert reason_of(lambda: store.normalize_rects("nope")) == "bad_rect"
    outside = {"x_min": 5.0, "y_min": 0.0, "x_max": 6.0, "y_max": 1.0}
    assert reason_of(lambda: store.count_erase(image, [outside])) == "out_of_map"
    assert reason_of(lambda: store.apply_erase(image, [outside])) == "out_of_map"


def test_normalize_swaps_reversed_corners():
    reversed_rect = {"x_min": 0.2, "y_min": 0.1, "x_max": 0.0, "y_max": 0.0}
    assert store.normalize_rects([reversed_rect]) == [RECT]


# ---------------------------------------------------------------------------
# 쓰기
# ---------------------------------------------------------------------------


def _png_pixels(data: bytes) -> np.ndarray:
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    position, chunks = 8, {}
    while position < len(data):
        (length,) = struct.unpack(">I", data[position:position + 4])
        tag = data[position + 4:position + 8]
        body = data[position + 8:position + 8 + length]
        (crc,) = struct.unpack(">I", data[position + 8 + length:position + 12 + length])
        assert crc == zlib.crc32(tag + body) & 0xFFFFFFFF
        chunks.setdefault(tag, b"")
        chunks[tag] += body
        position += 12 + length
    width, height, depth, colour, _, _, _ = struct.unpack(">IIBBBBB", chunks[b"IHDR"])
    assert (depth, colour) == (8, 0)  # 8비트 회색
    raw = np.frombuffer(zlib.decompress(chunks[b"IDAT"]), dtype=np.uint8)
    rows = raw.reshape(height, width + 1)
    assert not rows[:, 0].any()  # 줄마다 필터 0
    return rows[:, 1:]


def test_pgm_png_roundtrip_and_files_written_atomically(tmp_path):
    root = make_map(tmp_path)
    image = store.load_map_image(root, MAP)
    pixels = image.pixels.copy()
    pixels[2, 3] = store.OCCUPIED
    pixels[7, 9] = store.UNKNOWN

    store.write_map_pixels(root, MAP, pixels)

    assert np.array_equal(store.load_map_image(root, MAP).pixels, pixels)
    assert np.array_equal(_png_pixels((root / f"{MAP}.png").read_bytes()), pixels)
    assert sorted(path.name for path in root.iterdir()) == [f"{MAP}.pgm", f"{MAP}.png", f"{MAP}.yaml"]


def test_write_rejects_a_different_size(tmp_path):
    root = make_map(tmp_path)
    wrong = np.full((HEIGHT, WIDTH + 1), store.FREE, dtype=np.uint8)
    assert reason_of(lambda: store.write_map_pixels(root, MAP, wrong)) == "bad_map"


# ---------------------------------------------------------------------------
# 그림 ↔ 격자
# ---------------------------------------------------------------------------


def test_to_grid_follows_nav2_trinary_rule(tmp_path):
    root = make_map(tmp_path)
    put(root, {(0, 0): store.OCCUPIED, (0, 1): store.UNKNOWN})

    grid = store.to_grid(store.load_map_image(root, MAP))

    assert grid.data.shape == (HEIGHT, WIDTH) and grid.data.dtype == np.int8
    # 그림 0행(위, y 큰 쪽)은 격자의 마지막 행입니다.
    assert grid.data[HEIGHT - 1, 0] == 100
    assert grid.data[HEIGHT - 1, 1] == 0  # free_thresh 0.25 에서는 205 가 빈칸
    assert int((grid.data == 0).sum()) == WIDTH * HEIGHT - 1
    assert (grid.resolution, grid.origin_x, grid.origin_y) == (0.1, -0.5, -0.4)

    yaml_path = root / f"{MAP}.yaml"
    yaml_path.write_text(
        yaml_path.read_text(encoding="utf-8").replace("free_thresh: 0.25", "free_thresh: 0.196"),
        encoding="utf-8",
    )
    grid = store.to_grid(store.load_map_image(root, MAP))
    assert grid.data[HEIGHT - 1, 1] == -1  # free_thresh 0.196 에서는 205 가 미지


def test_cells_to_pixels_flips_rows():
    cells = np.array([[0, 0], [7, 9]])
    assert store.cells_to_pixels(cells, HEIGHT).tolist() == [[7, 0], [0, 9]]
    assert cells.tolist() == [[0, 0], [7, 9]]  # 입력은 안 바뀜


# ---------------------------------------------------------------------------
# 예상과 다른 지도 파일 (Review Focus 1)
# ---------------------------------------------------------------------------


def test_bad_map_files_are_rejected_not_crashed(tmp_path):
    root = make_map(tmp_path)
    pgm = root / f"{MAP}.pgm"
    good = pgm.read_bytes()

    pgm.write_bytes(b"P2\n10 8\n255\n" + b"254 " * 80)
    assert reason_of(lambda: store.load_map_image(root, MAP)) == "bad_map"
    pgm.write_bytes(b"P5\n10 8\n65535\n" + bytes(160))
    assert reason_of(lambda: store.load_map_image(root, MAP)) == "bad_map"
    pgm.write_bytes(good[:-5])  # 잘린 파일
    assert reason_of(lambda: store.load_map_image(root, MAP)) == "bad_map"
    pgm.write_bytes(b"P5\n# comment line\n10 8\n255\n" + bytes([254]) * 80)  # 주석이 있는 정상 파일
    assert store.load_map_image(root, MAP).pixels.shape == (HEIGHT, WIDTH)

    pgm.unlink()
    assert reason_of(lambda: store.load_map_image(root, MAP)) in ("no_map", "bad_map")
    (root / f"{MAP}.yaml").unlink()
    assert reason_of(lambda: store.load_map_image(root, MAP)) == "no_map"
    assert reason_of(lambda: store.load_map_image(root, "../etc")) == "bad_map_id"
