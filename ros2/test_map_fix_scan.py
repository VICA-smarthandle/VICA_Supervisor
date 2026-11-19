"""map_fix_scan 시험입니다. 로봇 없이 pytest 로 돌립니다.

    python3 -m pytest -q VICA_Supervisor/ros2/test_map_fix_scan.py

합성 지도는 전부 막힌 판(100)에서 방을 빈칸(0)으로 파내 만듭니다(vica_nav2 의
test_pose_score.py 와 같은 방식). 합성 스캔은 그 지도를 광선으로 훑어 만듭니다 —
'실제 세상' 지도로 스캔을 만들고 '저장된 지도'에 얹어, 둘의 차이가 변경된 칸으로
나오는지 봅니다.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from test_map_fix_store import nav2_src  # noqa: E402

_NAV2 = nav2_src()
if _NAV2 is not None:
    sys.path.insert(0, str(_NAV2))

from vica_nav2.pose_score import MapGrid  # noqa: E402

import map_fix_scan as scan  # noqa: E402

RES = 0.05
NO_OFFSET = (0.0, 0.0, 0.0)
LASER = (0.185, 0.0, 0.0)  # 실제 로봇의 라이다 자리(base 기준)


def room(width_m: float = 4.0, height_m: float = 4.0, margin: float = 0.5) -> MapGrid:
    """벽 두께 margin 인 방 하나. 방 안쪽은 x, y 가 margin ~ margin + 크기입니다."""
    cols = int(round((width_m + 2 * margin) / RES))
    rows = int(round((height_m + 2 * margin) / RES))
    data = np.full((rows, cols), 100, dtype=np.int8)
    edge = int(round(margin / RES))
    data[edge:rows - edge, edge:cols - edge] = 0
    return MapGrid(data, RES, 0.0, 0.0)


def with_box(grid: MapGrid, x0: float, y0: float, x1: float, y1: float) -> MapGrid:
    """상자 하나를 놓은 새 지도. 원본은 그대로입니다."""
    data = grid.data.copy()
    data[int(round(y0 / RES)):int(round(y1 / RES)), int(round(x0 / RES)):int(round(x1 / RES))] = 100
    return MapGrid(data, RES, grid.origin_x, grid.origin_y)


def box_cells(x0: float, y0: float, x1: float, y1: float) -> set[tuple[int, int]]:
    rows = range(int(round(y0 / RES)), int(round(y1 / RES)))
    cols = range(int(round(x0 / RES)), int(round(x1 / RES)))
    return {(row, col) for row in rows for col in cols}


def cast(grid: MapGrid, pose, sensor=NO_OFFSET, count: int = 720, max_range: float = 9.0,
         step: float = 0.005):
    """지도를 광선으로 훑어 360° 스캔을 만듭니다. 맞지 않은 빔은 inf 입니다."""
    x, y, yaw = pose
    sx, sy, syaw = sensor
    lx = x + math.cos(yaw) * sx - math.sin(yaw) * sy
    ly = y + math.sin(yaw) * sx + math.cos(yaw) * sy
    angle_min = -math.pi
    increment = 2.0 * math.pi / count
    theta = yaw + syaw + angle_min + np.arange(count) * increment
    distance = np.arange(step, max_range, step)
    px = lx + np.cos(theta)[:, None] * distance[None, :]
    py = ly + np.sin(theta)[:, None] * distance[None, :]
    cols = np.floor((px - grid.origin_x) / RES).astype(int)
    rows = np.floor((py - grid.origin_y) / RES).astype(int)
    inside = (rows >= 0) & (rows < grid.height) & (cols >= 0) & (cols < grid.width)
    blocked = np.zeros(px.shape, dtype=bool)
    blocked[inside] = grid.data[rows[inside], cols[inside]] >= 65
    first = blocked.argmax(axis=1)
    ranges = np.where(blocked.any(axis=1), distance[first], np.inf)
    return ranges, angle_min, increment


def accumulate(saved: MapGrid, scans, pose, *, radius: float = 3.0, sensor=NO_OFFSET):
    acc = scan.ScanAccumulator(saved, radius)
    for ranges, angle_min, increment in scans:
        acc.add_scan(ranges, angle_min, increment, pose, sensor)
    return acc


def as_set(cells: np.ndarray) -> set[tuple[int, int]]:
    return {(int(row), int(col)) for row, col in cells}


POSE = (2.5, 2.5, 0.3)
BOX = (3.2, 2.3, 3.6, 2.7)  # 로봇 오른쪽 0.7 m 에 0.4 m 상자


# ---------------------------------------------------------------------------
# 변경 판정
# ---------------------------------------------------------------------------


def test_unchanged_room_reports_no_changes():
    saved = room()
    acc = accumulate(saved, [cast(saved, POSE)] * 20, POSE)

    changes = scan.detect_changes(saved, acc)

    assert acc.n_scans == 20
    assert len(changes.added) == 0 and len(changes.removed) == 0


def test_new_box_is_added_at_its_true_cells():
    saved = room()
    real = with_box(saved, *BOX)
    acc = accumulate(saved, [cast(real, POSE)] * 20, POSE)

    changes = scan.detect_changes(saved, acc)

    added = as_set(changes.added)
    assert len(added) >= 5
    assert added <= box_cells(*BOX)  # 상자 칸에만 생깁니다
    assert len(changes.removed) == 0


def test_removed_box_is_cleared():
    real = room()
    saved = with_box(real, *BOX)
    acc = accumulate(saved, [cast(real, POSE)] * 20, POSE)

    changes = scan.detect_changes(saved, acc)

    removed = as_set(changes.removed)
    assert removed <= box_cells(*BOX)
    assert len(removed) >= 0.8 * len(box_cells(*BOX))
    assert len(changes.added) == 0


def test_passing_person_is_filtered_out():
    saved = room()
    person = with_box(saved, 3.0, 3.0, 3.3, 3.3)
    scans = [cast(person, POSE)] * 5 + [cast(saved, POSE)] * 15  # 20장 중 5장에만

    changes = scan.detect_changes(saved, accumulate(saved, scans, POSE))

    assert len(changes.added) == 0 and len(changes.removed) == 0


def test_standing_person_is_added():
    saved = room()
    person = with_box(saved, 3.0, 3.0, 3.3, 3.3)

    changes = scan.detect_changes(saved, accumulate(saved, [cast(person, POSE)] * 20, POSE))

    assert len(changes.added) > 0


def test_wall_half_a_cell_off_is_not_redrawn():
    saved = room()
    scans = [cast(saved, POSE)] * 20
    shifted = (POSE[0] + 0.025, POSE[1], POSE[2])  # 자세가 반 칸 틀린 채로 얹습니다

    changes = scan.detect_changes(saved, accumulate(saved, scans, shifted))

    assert len(changes.added) == 0 and len(changes.removed) == 0


def test_grazing_beams_do_not_erode_a_wall():
    saved = room()
    pose = (2.5, 0.8, math.radians(5.0))  # 아래 벽에서 0.3 m, 벽과 5° 로 거의 나란히
    for offset in (0.0, 0.02, -0.02):
        slid = (pose[0], pose[1] + offset, pose[2])
        changes = scan.detect_changes(saved, accumulate(saved, [cast(saved, pose)] * 20, slid))
        assert len(changes.removed) == 0, offset
        assert len(changes.added) == 0, offset


def test_radius_limits_changes():
    saved = room(8.0, 8.0)
    pose = (4.5, 4.5, 0.0)
    near, far = (6.0, 4.4, 6.3, 4.7), (4.4, 7.3, 4.7, 7.6)  # 1.5 m, 2.8 m
    real = with_box(with_box(saved, *near), *far)
    acc = accumulate(saved, [cast(real, pose)] * 20, pose, radius=2.0)

    added = as_set(scan.detect_changes(saved, acc).added)

    assert added and added <= box_cells(*near)


def test_circle_partly_outside_the_map_is_clipped():  # Review Focus 3
    saved = room(4.0, 4.0, margin=0.1)
    pose = (0.4, 0.4, 0.0)  # 지도 모서리에서 0.4 m, 반경은 3 m
    changes = scan.detect_changes(saved, accumulate(saved, [cast(saved, pose)] * 5, pose))
    assert len(changes.added) == 0 and len(changes.removed) == 0

    # 끝점이 지도 배열 밖에 떨어지는 빔이 섞여도 죽지 않습니다.
    empty = MapGrid(np.zeros((40, 40), dtype=np.int8), RES, 0.0, 0.0)
    ring = (np.full(360, 2.0), -math.pi, 2.0 * math.pi / 360)
    acc = accumulate(empty, [ring] * 3, (0.3, 0.3, 0.0))
    added = scan.detect_changes(empty, acc).added
    assert ((added >= 0) & (added < 40)).all()


def test_cells_just_before_the_endpoint_are_not_counted_as_passed():
    """끝점 앞 BEYOND_M(0.10 m) 구간은 '지나감'이 아닙니다 — 벽 바로 앞 칸을 지우지 않으려는 규칙."""
    empty = MapGrid(np.zeros((40, 80), dtype=np.int8), RES, 0.0, 0.0)
    acc = scan.ScanAccumulator(empty, 3.0)
    # 빔 하나가 +x 로 2.02 m: 라이다 x 1.01 → 끝점 x 3.03(열 60). 지나감은 x 2.93 까지.
    acc.add_scan(np.array([2.02]), 0.0, 0.1, (1.01, 1.01, 0.0), NO_OFFSET)
    row = 20
    assert acc.hit_scans[row, 60] == 1
    assert acc.pass_scans[row, 57] == 1  # x 2.85~2.90
    assert acc.pass_scans[row, 59] == 0 and acc.pass_scans[row, 60] == 0  # 마지막 0.10 m 와 끝점 칸


def test_cell_hit_now_and_then_is_not_removed():
    """지나간 스캔이 많아도 가끔이라도 맞는 칸(N 의 10 % 초과)은 남깁니다."""
    saved = with_box(room(), 3.0, 3.0, 3.05, 3.05)  # 격자 (60, 60) 한 칸짜리 물체
    acc = scan.ScanAccumulator(saved, 3.0)
    acc.n_scans = 20
    acc.in_radius[:] = True
    acc.pass_scans[60, 60] = 18

    acc.hit_scans[60, 60] = 10  # 절반은 맞음
    assert len(scan.detect_changes(saved, acc).removed) == 0
    acc.hit_scans[60, 60] = 2   # 10 % 이하
    assert as_set(scan.detect_changes(saved, acc).removed) == {(60, 60)}
    acc.pass_scans[60, 60] = 15  # 지나간 스캔이 80 % 미만
    assert len(scan.detect_changes(saved, acc).removed) == 0


def test_bad_beams_are_dropped():
    saved = room()
    ranges, angle_min, increment = cast(saved, POSE)
    ranges = ranges.copy()
    ranges[::3] = np.inf
    ranges[1::3] = np.nan
    ranges[2::9] = 0.1  # 0.25 m 미만은 차체 반사
    acc = accumulate(saved, [(ranges, angle_min, increment)] * 10, POSE)
    changes = scan.detect_changes(saved, acc)
    assert len(changes.added) == 0 and len(changes.removed) == 0


def test_no_scans_gives_no_changes():
    saved = room()
    changes = scan.detect_changes(saved, scan.ScanAccumulator(saved, 2.0))
    assert changes.added.shape == (0, 2) and changes.removed.shape == (0, 2)


def test_sensor_offset_is_applied():
    saved = room()
    real = with_box(saved, *BOX)
    acc = accumulate(saved, [cast(real, POSE, LASER)] * 20, POSE, sensor=LASER)
    added = as_set(scan.detect_changes(saved, acc).added)
    assert added and added <= box_cells(*BOX)


# ---------------------------------------------------------------------------
# 결과 다루기
# ---------------------------------------------------------------------------


def test_patched_grid_and_cell_centres():
    saved = with_box(room(), 1.0, 1.0, 1.1, 1.1)  # 격자 (20, 20)·(20, 21)·(21, 20)·(21, 21)
    changes = scan.Changes(added=np.array([[30, 40]]), removed=np.array([[20, 20]]))

    patched = scan.patched_grid(saved, changes)

    assert patched.data[30, 40] == 100 and patched.data[20, 20] == 0
    assert saved.data[30, 40] == 0 and saved.data[20, 20] == 100  # 원본은 그대로
    assert (patched.resolution, patched.origin_x, patched.origin_y) == (RES, 0.0, 0.0)
    centres = scan.cell_centres(saved, changes.added)
    assert np.allclose(centres, [[40.5 * RES, 30.5 * RES]])  # (x, y) = 열·행 가운데
