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
from datetime import datetime, timedelta, timezone
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
    assert store.MAX_RECTS == 10        # 11-19 사용자: 한 번에 10곳까지
    assert len(store.normalize_rects([RECT] * 10)) == 10
    assert reason_of(lambda: store.normalize_rects([RECT] * 11)) == "too_many"
    thin = {"x_min": 0.0, "y_min": 0.0, "x_max": 0.04, "y_max": 0.3}
    assert reason_of(lambda: store.normalize_rects([thin])) == "too_small"
    assert reason_of(lambda: store.normalize_rects([{"x_min": "a"}])) == "bad_rect"
    assert reason_of(lambda: store.normalize_rects([])) == "bad_rect"
    assert reason_of(lambda: store.normalize_rects("nope")) == "bad_rect"
    outside = {"x_min": 5.0, "y_min": 0.0, "x_max": 6.0, "y_max": 1.0}
    assert reason_of(lambda: store.count_erase(image, [outside])) == "out_of_map"


def message_of(call) -> str:
    with pytest.raises(store.MapFixError) as caught:
        call()
    return caught.value.message


def test_rect_messages_use_the_app_word_area(tmp_path):
    """앱 화면의 말은 '구역'·'곳'입니다(11-19 목업 95·100). 로봇 문구도 같은 말을 씁니다."""
    image = store.load_map_image(make_map(tmp_path), MAP)
    thin = {"x_min": 0.0, "y_min": 0.0, "x_max": 0.04, "y_max": 0.3}
    outside = {"x_min": 5.0, "y_min": 0.0, "x_max": 6.0, "y_max": 1.0}
    assert message_of(lambda: store.normalize_rects([RECT] * 11)) == "한 번에 10곳까지 지울 수 있습니다."
    assert message_of(lambda: store.normalize_rects([RECT, thin])) == "2번 구역이 너무 작습니다."
    assert message_of(lambda: store.normalize_rects([])) == "지울 구역이 없습니다."
    assert message_of(lambda: store.normalize_rects([{"x_min": "a"}])) == "1번 구역의 좌표가 올바르지 않습니다."
    assert message_of(lambda: store.count_erase(image, [outside])) == "구역이 지도 밖에 있습니다."
    # 아주 큰 좌표(1e308)는 칸 범위 계산에서 넘쳐 노드가 죽었습니다(11-19 독립 검토 6).
    huge = {"x_min": 0.0, "y_min": 0.0, "x_max": 1e308, "y_max": 1.0}
    assert message_of(lambda: store.normalize_rects([huge])) == "1번 구역의 좌표가 올바르지 않습니다."
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


def test_writing_keeps_the_file_permissions(tmp_path):
    """11-19 실기: 고친 지도 파일이 664 → 600 으로 바뀌었다(임시 파일 권한이 그대로 남음).
    다른 사용자·서비스가 지도를 읽지 못하게 될 수 있어, 쓰기 전 권한을 그대로 둔다."""
    root = make_map(tmp_path)
    store.write_map_pixels(root, MAP, store.load_map_image(root, MAP).pixels)   # png 를 만든다
    for name in (f"{MAP}.pgm", f"{MAP}.png"):
        os.chmod(root / name, 0o664)
    pixels = store.load_map_image(root, MAP).pixels.copy()
    pixels[2, 3] = store.OCCUPIED

    store.write_map_pixels(root, MAP, pixels)
    store.write_snapshot([(root / f"{MAP}.png", (root / f"{MAP}.png").read_bytes())])

    assert {name: (root / name).stat().st_mode & 0o777 for name in (f"{MAP}.pgm", f"{MAP}.png")} == {
        f"{MAP}.pgm": 0o664, f"{MAP}.png": 0o664}


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


# ---------------------------------------------------------------------------
# 백업 · 기록 · 되돌리기
# ---------------------------------------------------------------------------

KST = timezone(timedelta(hours=9))


def at(second: int) -> datetime:
    return datetime(2026, 11, 19, 10, 15, second, tzinfo=KST)


def with_png(tmp_path: Path) -> Path:
    """검은 칸 하나가 있고 png 까지 갖춘 가짜 지도."""
    root = make_map(tmp_path)
    put(root, {(3, 5): store.OCCUPIED})
    store.write_map_pixels(root, MAP, store.load_map_image(root, MAP).pixels)
    return root


def files(root: Path) -> dict[str, bytes]:
    return {name: (root / name).read_bytes() for name in (f"{MAP}.pgm", f"{MAP}.png")}


def erase_once(root: Path, second: int) -> Path:
    backup = store.save_backup(root, MAP, "erase", {"black": 1, "gray": 0, "rects": [RECT]}, at(second))
    pixels, _ = store.apply_erase(store.load_map_image(root, MAP), [RECT])
    store.write_map_pixels(root, MAP, pixels)
    return backup


def test_backup_then_undo_restores_bytes_exactly(tmp_path):
    root = with_png(tmp_path)
    before = files(root)
    backup = erase_once(root, 0)
    assert files(root) != before

    entry = store.undo_last(root, MAP)

    assert files(root) == before
    assert (entry["kind"], entry["black"], entry["rects"]) == ("erase", 1, [RECT])
    assert not backup.exists()


def test_history_is_newest_first_and_limited(tmp_path):
    root = with_png(tmp_path)
    for second in range(4):
        store.save_backup(root, MAP, "scan", {"radius_m": 2.0, "added": second, "removed": 0}, at(second))

    history = store.list_history(root, MAP, limit=3)

    assert [entry["added"] for entry in history] == [3, 2, 1]
    assert history[0]["at"] == "2026-11-19T10:15:03+09:00"
    # 없는 값은 None 으로 채웁니다.
    assert history[0] == {
        "at": "2026-11-19T10:15:03+09:00", "kind": "scan", "radius_m": 2.0, "added": 3,
        "removed": 0, "black": None, "gray": None, "rects": None, "pose": None,
    }


def test_only_ten_backups_are_kept(tmp_path):
    root = with_png(tmp_path)
    for second in range(12):
        store.save_backup(root, MAP, "erase", {"black": second}, at(second))

    names = sorted(path.name for path in store.backup_root(root, MAP).iterdir())

    assert len(names) == store.KEEP_BACKUPS == 10
    assert names[0] == "20261119_101502_erase"  # 가장 오래된 둘(00·01)이 지워졌습니다


def test_same_second_gets_a_suffix(tmp_path):
    root = with_png(tmp_path)
    first = store.save_backup(root, MAP, "erase", {"black": 1}, at(0))
    second = store.save_backup(root, MAP, "erase", {"black": 2}, at(0))

    assert (first.name, second.name) == ("20261119_101500_erase", "20261119_101500_erase_2")
    assert [entry["black"] for entry in store.list_history(root, MAP)] == [2, 1]


def test_nothing_to_undo(tmp_path):
    root = with_png(tmp_path)
    assert reason_of(lambda: store.undo_last(root, MAP)) == "nothing_to_undo"


def test_half_written_backup_is_ignored(tmp_path):  # Review Focus 2
    root = with_png(tmp_path)
    before = files(root)
    erase_once(root, 0)
    half = store.backup_root(root, MAP) / "20261119_101559_erase"  # 더 새것이지만 entry.json 이 없습니다
    half.mkdir()
    (half / f"{MAP}.pgm").write_bytes(b"broken")

    assert len(store.list_history(root, MAP)) == 1
    store.undo_last(root, MAP)
    assert files(root) == before


def test_restore_leaves_original_when_backup_is_broken(tmp_path):
    root = with_png(tmp_path)
    backup = erase_once(root, 0)
    (backup / f"{MAP}.pgm").unlink()
    current = files(root)

    assert reason_of(lambda: store.undo_last(root, MAP)) == "io_error"
    assert files(root) == current
    assert backup.exists()


def test_undo_refuses_a_backup_that_no_longer_fits_the_map(tmp_path):
    """지도를 다른 크기·원점으로 바꾼 뒤(예: 배율 맞춤 도구) 옛 백업을 되돌리면 지도가 어긋납니다.
    지금 지도와 크기·해상도·원점이 다르면 되돌리지 않습니다(11-19 독립 검토 1)."""
    root = with_png(tmp_path)
    erase_once(root, 0)
    yaml = root / f"{MAP}.yaml"
    yaml.write_text(yaml.read_text(encoding="utf-8").replace("origin: [-0.5, -0.4, 0]", "origin: [-0.6, -0.4, 0]"),
                    encoding="utf-8")
    current = files(root)

    error = pytest.raises(store.MapFixError, store.undo_last, root, MAP).value
    assert (error.reason, error.message) == ("bad_map", "백업 지도가 지금 지도와 달라 되돌리지 않았습니다.")
    assert files(root) == current

    # 크기가 달라져도 같습니다(그림 크기는 pgm 머리말에서 봅니다).
    root2 = with_png(tmp_path / "b")
    erase_once(root2, 0)
    (root2 / f"{MAP}.pgm").write_bytes(b"P5\n12 8\n255\n" + bytes([254]) * 96)
    (root2 / f"{MAP}.png").unlink()
    assert reason_of(lambda: store.undo_last(root2, MAP)) == "bad_map"


def test_undo_refuses_an_empty_backup_picture(tmp_path):
    """복사 도중 전원이 나가 0바이트가 된 백업 그림은 쓰지 않습니다."""
    root = with_png(tmp_path)
    backup = erase_once(root, 0)
    (backup / f"{MAP}.pgm").write_bytes(b"")
    current = files(root)

    assert reason_of(lambda: store.undo_last(root, MAP)) == "bad_map"
    assert files(root) == current and backup.exists()


def test_backup_order_follows_saving_order_not_the_clock(tmp_path):
    """시계가 뒤로 가도(폐쇄망·재부팅) 가장 나중에 만든 백업이 '최근'입니다(11-19 독립 검토 8)."""
    root = with_png(tmp_path)
    first = store.save_backup(root, MAP, "erase", {"black": 1}, at(30))
    second = store.save_backup(root, MAP, "erase", {"black": 2}, at(10))   # 시계가 20 s 뒤로
    third = store.save_backup(root, MAP, "scan", {"added": 3}, at(20))

    assert store.latest_backup(root, MAP) == third
    assert [entry["kind"] for entry in store.list_history(root, MAP)] == ["scan", "erase", "erase"]
    assert store.list_history(root, MAP)[1]["black"] == 2
    assert first.exists() and second.exists()

    # 정리할 때도 저장한 순서로 오래된 것부터 지웁니다.
    for second_ in range(9, 0, -1):
        store.save_backup(root, MAP, "erase", {"black": 100 + second_}, at(second_))
    assert not first.exists() and not second.exists() and third.exists()
    assert len(store.list_history(root, MAP, limit=20)) == store.KEEP_BACKUPS


def test_drop_backup_removes_only_that_folder(tmp_path):
    root = with_png(tmp_path)
    keep = store.save_backup(root, MAP, "erase", {}, at(0))
    drop = store.save_backup(root, MAP, "erase", {}, at(1))

    store.drop_backup(drop)

    assert keep.exists() and not drop.exists()
