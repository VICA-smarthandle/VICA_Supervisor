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
import pytest

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from test_map_fix_store import nav2_src  # noqa: E402

_NAV2 = nav2_src()
if _NAV2 is not None:
    sys.path.insert(0, str(_NAV2))

from vica_nav2.pose_score import (  # noqa: E402
    MAX_DIST, MapGrid, build_likelihood_field, filter_beams, score_pose,
)

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
         step: float = 0.005, depth: float = 0.0):
    """지도를 광선으로 훑어 360° 스캔을 만듭니다. 맞지 않은 빔은 inf 입니다.

    depth 는 맞은 거리에 더하는 값입니다. 실제 지도는 스캔 끝점이 떨어진 칸을 검은 칸으로
    칠해 만들어서 벽 면이 평균적으로 칸 가운데에 있습니다 — 자세 맞춤 시험은 depth 를 반 칸
    (RES / 2)으로 줘 그 모양을 흉내 냅니다. 0 이면 끝점이 칸의 앞 면에 떨어집니다.
    """
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
    ranges = np.where(blocked.any(axis=1), distance[first] + depth, np.inf)
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


# ---------------------------------------------------------------------------
# 자세 다시 맞춤 · 구분 검사
# ---------------------------------------------------------------------------

HALF = RES / 2.0
TRUE = (2.5, 2.0, 0.3)


def refine(saved: MapGrid, real: MapGrid, true_pose, guess, **cast_kwargs):
    cast_kwargs.setdefault("depth", HALF)
    ranges, angle_min, increment = cast(real, true_pose, LASER, **cast_kwargs)
    field = build_likelihood_field(saved)
    return scan.refine_pose(saved, field, ranges, angle_min, increment, guess, LASER)


def off(pose, dx: float, dy: float, dyaw_deg: float):
    return (pose[0] + dx, pose[1] + dy, pose[2] + math.radians(dyaw_deg))


def test_refine_recovers_a_shifted_guess_in_a_room():
    saved = room(6.0, 5.0)

    got = refine(saved, saved, TRUE, off(TRUE, 0.06, -0.04, 1.5))

    assert got.ok and got.reason == ""
    assert abs(got.x - TRUE[0]) <= 0.01 and abs(got.y - TRUE[1]) <= 0.01
    assert abs(got.yaw - TRUE[2]) <= math.radians(0.2)
    assert got.rms_m <= scan.MAX_RMS_M
    assert math.isclose(got.moved_m, math.hypot(got.x - (TRUE[0] + 0.06), got.y - (TRUE[1] - 0.04)), abs_tol=1e-9)
    assert abs(got.moved_deg - 1.5) <= 0.2
    assert got.hits.shape == (got.used_beams, 2) and got.used_beams <= 180


def test_refine_ignores_a_moved_object():
    plain = room(6.0, 5.0)
    saved = with_box(plain, 1.2, 1.8, 1.6, 2.2)   # 지도에는 상자가 로봇 왼쪽
    real = with_box(plain, 3.6, 1.8, 4.0, 2.2)    # 실제로는 오른쪽으로 옮겨졌습니다

    got = refine(saved, real, TRUE, off(TRUE, 0.04, -0.03, 1.0))

    assert got.ok
    assert math.hypot(got.x - TRUE[0], got.y - TRUE[1]) <= 0.012
    assert got.kept_beams < got.used_beams


def test_long_corridor_keeps_the_amcl_forward_and_passes():
    """앞뒤가 구분되지 않으면 그 축만 출발 자세(AMCL — 지금 주행에 쓰는 위치)를 두고 통과합니다
    (11-19 사용자 결정: 좁은 범위 스캔을 거부하는 것은 불편하다)."""
    data = np.full((80, 640), 100, dtype=np.int8)   # 32 × 4 m 판
    data[20:60, 20:620] = 0                          # 폭 2 m · 길이 30 m 복도
    corridor = MapGrid(data, RES, 0.0, 0.0)
    middle = (16.0, 2.0, 0.0)                        # 양 끝 벽이 15 m 밖(라이다 유효 11 m 밖)
    guess = off(middle, 0.03, 0.02, 0.5)

    got = refine(corridor, corridor, middle, guess, max_range=16.0)

    assert got.ok and got.reason == ""
    assert got.ambiguous == ("forward",)
    assert math.isclose(got.x, guess[0], abs_tol=0.003)                 # 앞뒤(이 복도에서는 x)는 AMCL
    assert abs(got.y - middle[1]) <= 0.012 and abs(got.yaw - middle[2]) <= math.radians(0.3)


def test_room_corner_is_not_ambiguous():
    saved = room(6.0, 5.0)
    corner = (1.3, 1.3, 0.7)

    got = refine(saved, saved, corner, off(corner, -0.03, 0.03, -1.0))

    assert got.ok and got.ambiguous == ()


def test_mostly_unmatched_scan_is_low_match():
    saved = room(6.0, 5.0)
    real = saved
    for box in ((1.3, 0.8, 1.5, 3.2), (1.3, 3.0, 3.7, 3.2), (1.3, 0.8, 3.7, 1.0)):  # 로봇을 세 면에서 가린 칸막이
        real = with_box(real, *box)

    got = refine(saved, real, TRUE, TRUE)

    assert not got.ok and got.reason == "low_match"
    assert got.kept_beams < scan.MIN_KEPT_RATIO * got.used_beams


def test_open_space_with_few_beams_is_low_match():  # Review Focus 3
    saved = room(6.0, 5.0)

    got = refine(saved, saved, TRUE, TRUE, count=40)

    assert got.used_beams == 40
    assert not got.ok and got.reason == "low_match"


def test_empty_scan_is_low_match():
    saved = room(6.0, 5.0)
    field = build_likelihood_field(saved)
    got = scan.refine_pose(saved, field, np.full(360, np.inf), -math.pi, 2 * math.pi / 360, TRUE, LASER)
    assert not got.ok and got.reason == "low_match" and got.used_beams == 0


def test_score_is_the_pose_score_percent():
    saved = room(6.0, 5.0)
    ranges, angle_min, increment = cast(saved, TRUE, LASER, depth=HALF)
    field = build_likelihood_field(saved)

    got = scan.refine_pose(saved, field, ranges, angle_min, increment, TRUE, LASER)

    beams = filter_beams(ranges, angle_min, increment)
    want = score_pose(field, saved, beams, got.x, got.y, got.yaw, sensor=LASER)
    assert math.isclose(got.score, want, abs_tol=1e-6)
    same = scan.pose_score_percent(saved, field, ranges, angle_min, increment, (got.x, got.y, got.yaw), LASER)
    assert math.isclose(same, want, abs_tol=1e-6)


def test_interp_field_is_linear_between_cell_centres():
    data = np.zeros((6, 6), dtype=np.int8)
    data[2, 2] = 100
    grid = MapGrid(data, RES, 0.0, 0.0)
    field = build_likelihood_field(grid)

    def at(col: float, row: float) -> float:  # 칸 번호(가운데 기준)로 묻습니다
        wx = np.array([(col + 0.5) * RES])
        wy = np.array([(row + 0.5) * RES])
        return float(scan.interp_field(field, grid, wx, wy, MAX_DIST)[0])

    assert math.isclose(at(2, 2), 0.0, abs_tol=1e-12)
    assert math.isclose(at(3, 2), RES, rel_tol=1e-9)
    assert math.isclose(at(2.5, 2), RES / 2, rel_tol=1e-9)       # 두 칸 가운데 사이의 절반
    assert math.isclose(at(2, 3.25), RES * 1.25, rel_tol=1e-9)
    assert at(40, 2) == MAX_DIST                                  # 지도 밖


def test_small_square_room_is_not_ambiguous():
    """3 × 3 m 방. 벽이 가까우면 2° 돌려도 끝점이 벽에서 거의 안 벗어나지만 방향은 정해집니다."""
    small = room(3.0, 3.0)
    pose = (2.0, 2.0, 0.2)

    got = refine(small, small, pose, off(pose, 0.03, -0.02, 1.0))

    assert got.ok and got.ambiguous == ()


def test_round_room_keeps_the_amcl_yaw():
    """로봇이 둥근 방 한가운데면 어느 쪽을 보는지 벽으로는 알 수 없습니다 — 방향은 AMCL 을 둡니다."""
    size = 120
    rows, cols = np.mgrid[0:size, 0:size]
    distance = np.hypot((cols + 0.5) * RES - 3.0, (rows + 0.5) * RES - 3.0)
    data = np.where(distance < 2.0, 0, 100).astype(np.int8)
    round_room = MapGrid(data, RES, 0.0, 0.0)
    centre = (3.0, 3.0, 0.4)
    guess = centre        # 방향이 전혀 안 정해지는 장면이라 출발값을 틀어 두면 탐색이 멀리 미끄러져
                          # 옮긴 양 한도(10°)에 걸립니다 — 그때는 거부가 맞습니다.

    ranges, angle_min, increment = cast(round_room, centre, NO_OFFSET, depth=HALF)
    field = build_likelihood_field(round_room)
    got = scan.refine_pose(round_room, field, ranges, angle_min, increment, guess, NO_OFFSET)

    assert got.ok and got.ambiguous == ("yaw",)
    assert math.isclose(got.yaw, guess[2], abs_tol=1e-9)               # 방향은 AMCL 그대로
    assert math.hypot(got.x - centre[0], got.y - centre[1]) <= 0.012


def test_refine_refuses_to_jump_far_from_the_guess():
    """출발 자세에서 너무 멀리 옮겨야 맞는다면 믿지 않습니다 — 초기 위치부터 다시 잡을 일입니다."""
    saved = room(6.0, 5.0)
    far_guess = off(TRUE, 0.42, 0.0, 0.0)   # 0.42 m 틀린 출발값. 거친 탐색(±0.5 m)은 참값을 찾습니다

    got = refine(saved, saved, TRUE, far_guess)

    assert not got.ok and got.reason == "low_match"
    assert got.moved_m > scan.MAX_MOVE_M


def test_refine_refuses_to_turn_far_from_the_guess():
    """방향도 같습니다 — 출발 방향에서 10° 넘게 돌려야 맞는다면 믿지 않습니다(11-19 변이 점검에서 빠져 있던 시험)."""
    saved = room(6.0, 5.0)
    turned_guess = off(TRUE, 0.0, 0.0, 15.0)   # 15° 틀린 출발값. 거친 탐색(±45°)은 참값을 찾습니다

    got = refine(saved, saved, TRUE, turned_guess)

    assert not got.ok and got.reason == "low_match"
    assert got.moved_deg > scan.MAX_MOVE_DEG
    # 같은 방에서 5° 틀린 출발값은 그대로 맞춥니다(제한이 너무 빡빡하지 않은지).
    assert refine(saved, saved, TRUE, off(TRUE, 0.0, 0.0, 5.0)).ok


def test_thick_wall_does_not_let_the_fit_sink_in():
    """벽이 두꺼워도 끝점이 벽 속으로 들어가는 자세를 좋게 보지 않습니다(겉 칸 기준)."""
    saved = room(6.0, 5.0)   # 벽 두께 0.5 m
    surface = scan.build_surface_field(saved)
    deep = np.array([0.25]), np.array([2.0])     # 왼쪽 벽 속 0.25 m (벽 면은 x 0.5)
    face = np.array([0.475]), np.array([2.0])    # 벽 겉 칸의 가운데
    assert float(scan.interp_field(surface, saved, *face, MAX_DIST)[0]) < 0.005
    assert float(scan.interp_field(surface, saved, *deep, MAX_DIST)[0]) > 0.20


def test_fit_of_about_one_cell_passes():
    """11-19 실기: 위치가 맞는데도 남긴 빔 RMS 가 3.4~3.7 cm 였다(지도 한 칸 5 cm 안에서 벽이 어디
    있느냐의 차이). 그 정도로 맞으면 통과하고, 자세도 정확해야 한다."""
    saved = room(6.0, 5.0)
    ranges, angle_min, increment = cast(saved, TRUE, LASER, depth=HALF)
    noisy = ranges + np.random.default_rng(7).normal(0.0, 0.05, ranges.shape)
    field = build_likelihood_field(saved)

    got = scan.refine_pose(saved, field, noisy, angle_min, increment, TRUE, LASER)

    assert 0.03 < got.rms_m < 0.04
    assert got.ok, got.reason
    assert math.hypot(got.x - TRUE[0], got.y - TRUE[1]) < 0.01 and abs(got.yaw - TRUE[2]) < math.radians(0.5)


def test_fit_above_the_rms_limit_is_low_match(monkeypatch):
    """남긴 빔 RMS 가 상한을 넘으면 믿지 않습니다. 상한이 0.05 m 로 오른 뒤에는(11-19) 남길 때 0.10 m 로
    걸러 RMS 가 그 위로 잘 안 오르므로, 거르는 장치 자체를 상한 0.03 m 로 확인합니다."""
    monkeypatch.setattr(scan, "MAX_RMS_M", 0.03)
    saved = room(6.0, 5.0)
    ranges, angle_min, increment = cast(saved, TRUE, LASER, depth=HALF)
    noisy = ranges + np.random.default_rng(7).normal(0.0, 0.05, ranges.shape)
    field = build_likelihood_field(saved)

    got = scan.refine_pose(saved, field, noisy, angle_min, increment, TRUE, LASER)

    assert not got.ok and got.reason == "low_match"
    assert got.rms_m > scan.MAX_RMS_M and got.kept_beams >= scan.MIN_KEPT


# ---------------------------------------------------------------------------
# 몸체 거르기 (11-19 실기: 로봇 뒤쪽 차체 0.36~0.46 m 가 지도에 장애물로 써졌다)
# ---------------------------------------------------------------------------


def test_beams_on_the_body_or_within_twenty_centimetres_are_dropped():
    """몸체(Nav2 footprint)와 그 사방 0.20 m 안에 떨어진 빔은 버립니다(11-19 사용자 결정)."""
    centre = (0.0, 0.0, 0.0)
    # 0: 앞 · π/2: 왼쪽 · π: 뒤 · 3π/2: 오른쪽
    inside = scan.mask_body(np.array([0.34, 0.42, 0.76, 0.42]), 0.0, math.pi / 2, centre)
    outside = scan.mask_body(np.array([0.36, 0.44, 0.78, 0.44]), 0.0, math.pi / 2, centre)

    assert np.isnan(inside).all()
    assert np.array_equal(outside, [0.36, 0.44, 0.78, 0.44])
    assert scan.BODY_MARGIN_M == 0.20


def test_body_mask_uses_where_the_lidar_sits():
    """라이다가 뒤를 보고 0.1 m 앞에 달렸으면, 라이다의 0° 빔 0.5 m 는 로봇 중심 뒤 0.4 m(몸체 안)입니다."""
    got = scan.mask_body(np.array([0.5, 0.5]), 0.0, math.pi, (0.1, 0.0, math.pi))

    assert np.isnan(got[0]) and got[1] == 0.5                          # 1번 빔은 앞 0.6 m — 밖


def test_hold_axes_replaces_only_the_named_axes():
    fitted = (1.00, 2.00, 0.0)
    amcl = (1.10, 2.05, math.radians(3.0))

    assert scan.hold_axes(fitted, amcl, ("forward",)) == pytest.approx((1.10, 2.00, 0.0))
    assert scan.hold_axes(fitted, amcl, ("lateral",)) == pytest.approx((1.00, 2.05, 0.0))
    assert scan.hold_axes(fitted, amcl, ("yaw",)) == pytest.approx((1.00, 2.00, math.radians(3.0)))
    # 로봇이 +y 를 보면 앞뒤는 y 축입니다
    facing_y = (1.00, 2.00, math.pi / 2)
    assert scan.hold_axes(facing_y, (1.10, 2.05, math.pi / 2), ("forward",)) == pytest.approx((1.00, 2.05, math.pi / 2))
