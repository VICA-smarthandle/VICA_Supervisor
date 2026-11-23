"""map_fix_scan 시험입니다. 로봇 없이 pytest 로 돌립니다."""

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
LASER = (0.185, 0.0, 0.0)


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
BOX = (3.2, 2.3, 3.6, 2.7)


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
    assert added <= box_cells(*BOX)
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
    scans = [cast(person, POSE)] * 5 + [cast(saved, POSE)] * 15

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
    shifted = (POSE[0] + 0.025, POSE[1], POSE[2])

    changes = scan.detect_changes(saved, accumulate(saved, scans, shifted))

    assert len(changes.added) == 0 and len(changes.removed) == 0


def test_grazing_beams_do_not_erode_a_wall():
    saved = room()
    pose = (2.5, 0.8, math.radians(5.0))
    for offset in (0.0, 0.02, -0.02):
        slid = (pose[0], pose[1] + offset, pose[2])
        changes = scan.detect_changes(saved, accumulate(saved, [cast(saved, pose)] * 20, slid))
        assert len(changes.removed) == 0, offset
        assert len(changes.added) == 0, offset


def test_radius_limits_changes():
    saved = room(8.0, 8.0)
    pose = (4.5, 4.5, 0.0)
    near, far = (6.0, 4.4, 6.3, 4.7), (4.4, 7.3, 4.7, 7.6)
    real = with_box(with_box(saved, *near), *far)
    acc = accumulate(saved, [cast(real, pose)] * 20, pose, radius=2.0)

    added = as_set(scan.detect_changes(saved, acc).added)

    assert added and added <= box_cells(*near)


def test_circle_partly_outside_the_map_is_clipped():
    saved = room(4.0, 4.0, margin=0.1)
    pose = (0.4, 0.4, 0.0)
    changes = scan.detect_changes(saved, accumulate(saved, [cast(saved, pose)] * 5, pose))
    assert len(changes.added) == 0 and len(changes.removed) == 0

    empty = MapGrid(np.zeros((40, 40), dtype=np.int8), RES, 0.0, 0.0)
    ring = (np.full(360, 2.0), -math.pi, 2.0 * math.pi / 360)
    acc = accumulate(empty, [ring] * 3, (0.3, 0.3, 0.0))
    added = scan.detect_changes(empty, acc).added
    assert ((added >= 0) & (added < 40)).all()


def test_cells_just_before_the_endpoint_are_not_counted_as_passed():
    """끝점 앞 BEYOND_M(0.10 m) 구간은 '지나감'이 아닙니다 — 벽 바로 앞 칸을 지우지 않으려는 규칙."""
    empty = MapGrid(np.zeros((40, 80), dtype=np.int8), RES, 0.0, 0.0)
    acc = scan.ScanAccumulator(empty, 3.0)
    acc.add_scan(np.array([2.02]), 0.0, 0.1, (1.01, 1.01, 0.0), NO_OFFSET)
    row = 20
    assert acc.hit_scans[row, 60] == 1
    assert acc.pass_scans[row, 57] == 1
    assert acc.pass_scans[row, 59] == 0 and acc.pass_scans[row, 60] == 0


def test_cell_hit_now_and_then_is_not_removed():
    """지나간 스캔이 많아도 가끔이라도 맞는 칸(N 의 10 % 초과)은 남깁니다."""
    saved = with_box(room(), 3.0, 3.0, 3.05, 3.05)
    acc = scan.ScanAccumulator(saved, 3.0)
    acc.n_scans = 20
    acc.in_radius[:] = True
    acc.pass_scans[60, 60] = 18

    acc.hit_scans[60, 60] = 10
    assert len(scan.detect_changes(saved, acc).removed) == 0
    acc.hit_scans[60, 60] = 2
    assert as_set(scan.detect_changes(saved, acc).removed) == {(60, 60)}
    acc.pass_scans[60, 60] = 15
    assert len(scan.detect_changes(saved, acc).removed) == 0


def test_bad_beams_are_dropped():
    saved = room()
    ranges, angle_min, increment = cast(saved, POSE)
    ranges = ranges.copy()
    ranges[::3] = np.inf
    ranges[1::3] = np.nan
    ranges[2::9] = 0.1
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


def test_patched_grid_and_cell_centres():
    saved = with_box(room(), 1.0, 1.0, 1.1, 1.1)
    changes = scan.Changes(added=np.array([[30, 40]]), removed=np.array([[20, 20]]))

    patched = scan.patched_grid(saved, changes)

    assert patched.data[30, 40] == 100 and patched.data[20, 20] == 0
    assert saved.data[30, 40] == 0 and saved.data[20, 20] == 100
    assert (patched.resolution, patched.origin_x, patched.origin_y) == (RES, 0.0, 0.0)
    centres = scan.cell_centres(saved, changes.added)
    assert np.allclose(centres, [[40.5 * RES, 30.5 * RES]])


HALF = RES / 2.0
TRUE = (2.5, 2.0, 0.3)


def refine(saved: MapGrid, real: MapGrid, true_pose, guess, sigma=None, **cast_kwargs):
    cast_kwargs.setdefault("depth", HALF)
    ranges, angle_min, increment = cast(real, true_pose, LASER, **cast_kwargs)
    field = build_likelihood_field(saved)
    return scan.refine_pose(saved, field, ranges, angle_min, increment, guess, LASER, guess_sigma=sigma)


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
    saved = with_box(plain, 1.2, 1.8, 1.6, 2.2)
    real = with_box(plain, 3.6, 1.8, 4.0, 2.2)

    got = refine(saved, real, TRUE, off(TRUE, 0.04, -0.03, 1.0))

    assert got.ok
    assert math.hypot(got.x - TRUE[0], got.y - TRUE[1]) <= 0.012
    assert got.kept_beams < got.used_beams


CORRIDOR_DATA = np.full((80, 640), 100, dtype=np.int8)
CORRIDOR_DATA[20:60, 20:620] = 0
MIDDLE = (16.0, 2.0, 0.0)


def test_long_corridor_keeps_the_amcl_forward_and_passes():
    """앞뒤가 구분되지 않으면 AMCL 이 그 축을 0.10 m 안으로 확신할 때만 그 축의 출발 자세(AMCL — 지금"""
    corridor = MapGrid(CORRIDOR_DATA, RES, 0.0, 0.0)
    middle = MIDDLE
    guess = off(middle, 0.03, 0.02, 0.5)

    got = refine(corridor, corridor, middle, guess, sigma=(0.05, 0.05, math.radians(1.0)), max_range=16.0)

    assert got.ok and got.reason == ""
    assert got.ambiguous == ("forward",)
    assert math.isclose(got.x, guess[0], abs_tol=0.003)
    assert abs(got.y - middle[1]) <= 0.012 and abs(got.yaw - middle[2]) <= math.radians(0.3)


def test_room_corner_is_not_ambiguous():
    saved = room(6.0, 5.0)
    corner = (1.3, 1.3, 0.7)

    got = refine(saved, saved, corner, off(corner, -0.03, 0.03, -1.0))

    assert got.ok and got.ambiguous == ()


def test_mostly_unmatched_scan_is_low_match():
    saved = room(6.0, 5.0)
    real = saved
    for box in ((1.3, 0.8, 1.5, 3.2), (1.3, 3.0, 3.7, 3.2), (1.3, 0.8, 3.7, 1.0)):
        real = with_box(real, *box)

    got = refine(saved, real, TRUE, TRUE)

    assert not got.ok and got.reason == "low_match"
    assert got.kept_beams < scan.MIN_KEPT_RATIO * got.used_beams


def test_open_space_with_few_beams_is_low_match():
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

    def at(col: float, row: float) -> float:
        wx = np.array([(col + 0.5) * RES])
        wy = np.array([(row + 0.5) * RES])
        return float(scan.interp_field(field, grid, wx, wy, MAX_DIST)[0])

    assert math.isclose(at(2, 2), 0.0, abs_tol=1e-12)
    assert math.isclose(at(3, 2), RES, rel_tol=1e-9)
    assert math.isclose(at(2.5, 2), RES / 2, rel_tol=1e-9)
    assert math.isclose(at(2, 3.25), RES * 1.25, rel_tol=1e-9)
    assert at(40, 2) == MAX_DIST


def test_small_square_room_is_not_ambiguous():
    """3 × 3 m 방. 벽이 가까우면 2° 돌려도 끝점이 벽에서 거의 안 벗어나지만 방향은 정해집니다."""
    small = room(3.0, 3.0)
    pose = (2.0, 2.0, 0.2)

    got = refine(small, small, pose, off(pose, 0.03, -0.02, 1.0))

    assert got.ok and got.ambiguous == ()


def test_round_room_is_refused_even_when_amcl_is_sure():
    """로봇이 둥근 방 한가운데면 어느 쪽을 보는지 벽으로는 알 수 없습니다."""
    size = 120
    rows, cols = np.mgrid[0:size, 0:size]
    distance = np.hypot((cols + 0.5) * RES - 3.0, (rows + 0.5) * RES - 3.0)
    data = np.where(distance < 2.0, 0, 100).astype(np.int8)
    round_room = MapGrid(data, RES, 0.0, 0.0)
    centre = (3.0, 3.0, 0.4)

    ranges, angle_min, increment = cast(round_room, centre, NO_OFFSET, depth=HALF)
    field = build_likelihood_field(round_room)
    got = scan.refine_pose(round_room, field, ranges, angle_min, increment, centre, NO_OFFSET,
                           guess_sigma=(0.05, 0.05, math.radians(1.0)))

    assert not got.ok and got.reason == "ambiguous" and got.ambiguous == ("yaw",)


def test_refine_refuses_to_jump_far_from_the_guess():
    """출발 자세에서 너무 멀리 옮겨야 맞는다면 믿지 않습니다 — 초기 위치부터 다시 잡을 일입니다."""
    saved = room(6.0, 5.0)
    far_guess = off(TRUE, 0.42, 0.0, 0.0)

    got = refine(saved, saved, TRUE, far_guess)

    assert not got.ok and got.reason == "low_match"
    assert got.moved_m > scan.MAX_MOVE_M


def test_refine_refuses_to_turn_far_from_the_guess():
    """방향도 같습니다 — 출발 방향에서 10° 넘게 돌려야 맞는다면 믿지 않습니다(11-19 변이 점검에서 빠져 있던 시험)."""
    saved = room(6.0, 5.0)
    turned_guess = off(TRUE, 0.0, 0.0, 15.0)

    got = refine(saved, saved, TRUE, turned_guess)

    assert not got.ok and got.reason == "low_match"
    assert got.moved_deg > scan.MAX_MOVE_DEG
    assert refine(saved, saved, TRUE, off(TRUE, 0.0, 0.0, 5.0)).ok


def test_thick_wall_does_not_let_the_fit_sink_in():
    """벽이 두꺼워도 끝점이 벽 속으로 들어가는 자세를 좋게 보지 않습니다(겉 칸 기준)."""
    saved = room(6.0, 5.0)
    surface = scan.build_surface_field(saved)
    deep = np.array([0.25]), np.array([2.0])
    face = np.array([0.475]), np.array([2.0])
    assert float(scan.interp_field(surface, saved, *face, MAX_DIST)[0]) < 0.005
    assert float(scan.interp_field(surface, saved, *deep, MAX_DIST)[0]) > 0.20


def test_fit_of_about_one_cell_passes():
    """11-19 실기: 위치가 맞는데도 남긴 빔 RMS 가 3.4~3.7 cm 였다(지도 한 칸 5 cm 안에서 벽이 어디"""
    saved = room(6.0, 5.0)
    ranges, angle_min, increment = cast(saved, TRUE, LASER, depth=HALF)
    noisy = ranges + np.random.default_rng(7).normal(0.0, 0.05, ranges.shape)
    field = build_likelihood_field(saved)

    got = scan.refine_pose(saved, field, noisy, angle_min, increment, TRUE, LASER)

    assert 0.03 < got.rms_m < 0.04
    assert got.ok, got.reason
    assert math.hypot(got.x - TRUE[0], got.y - TRUE[1]) < 0.01 and abs(got.yaw - TRUE[2]) < math.radians(0.5)


def test_fit_above_the_rms_limit_is_low_match(monkeypatch):
    """남긴 빔 RMS 가 상한을 넘으면 믿지 않습니다. 상한이 0.05 m 로 오른 뒤에는(11-19) 남길 때 0.10 m 로"""
    monkeypatch.setattr(scan, "MAX_RMS_M", 0.03)
    saved = room(6.0, 5.0)
    ranges, angle_min, increment = cast(saved, TRUE, LASER, depth=HALF)
    noisy = ranges + np.random.default_rng(7).normal(0.0, 0.05, ranges.shape)
    field = build_likelihood_field(saved)

    got = scan.refine_pose(saved, field, noisy, angle_min, increment, TRUE, LASER)

    assert not got.ok and got.reason == "low_match"
    assert got.rms_m > scan.MAX_RMS_M and got.kept_beams >= scan.MIN_KEPT


def test_beams_on_the_body_or_within_twenty_centimetres_are_dropped():
    """몸체(Nav2 footprint)와 그 사방 0.20 m 안에 떨어진 빔은 버립니다(11-19 사용자 결정)."""
    centre = (0.0, 0.0, 0.0)
    inside = scan.mask_body(np.array([0.34, 0.42, 0.76, 0.42]), 0.0, math.pi / 2, centre)
    outside = scan.mask_body(np.array([0.36, 0.44, 0.78, 0.44]), 0.0, math.pi / 2, centre)

    assert np.isnan(inside).all()
    assert np.array_equal(outside, [0.36, 0.44, 0.78, 0.44])
    assert scan.BODY_MARGIN_M == 0.20


def test_body_mask_uses_where_the_lidar_sits():
    """라이다가 뒤를 보고 0.1 m 앞에 달렸으면, 라이다의 0° 빔 0.5 m 는 로봇 중심 뒤 0.4 m(몸체 안)입니다."""
    got = scan.mask_body(np.array([0.5, 0.5]), 0.0, math.pi, (0.1, 0.0, math.pi))

    assert np.isnan(got[0]) and got[1] == 0.5


def test_hold_axes_replaces_only_the_named_axes():
    fitted = (1.00, 2.00, 0.0)
    amcl = (1.10, 2.05, math.radians(3.0))

    assert scan.hold_axes(fitted, amcl, ("forward",)) == pytest.approx((1.10, 2.00, 0.0))
    assert scan.hold_axes(fitted, amcl, ("lateral",)) == pytest.approx((1.00, 2.05, 0.0))
    assert scan.hold_axes(fitted, amcl, ("yaw",)) == pytest.approx((1.00, 2.00, math.radians(3.0)))
    facing_y = (1.00, 2.00, math.pi / 2)
    assert scan.hold_axes(facing_y, (1.10, 2.05, math.pi / 2), ("forward",)) == pytest.approx((1.00, 2.05, math.pi / 2))


def test_long_corridor_is_refused_when_amcl_is_unsure_along_it():
    corridor = MapGrid(CORRIDOR_DATA, RES, 0.0, 0.0)

    unsure = refine(corridor, corridor, MIDDLE, MIDDLE, sigma=(0.15, 0.05, 0.01), max_range=16.0)
    unknown = refine(corridor, corridor, MIDDLE, MIDDLE, sigma=None, max_range=16.0)

    assert (unsure.ok, unsure.reason, unsure.ambiguous) == (False, "ambiguous", ("forward",))
    assert (unknown.ok, unknown.reason) == (False, "ambiguous")
    assert scan.HOLD_MAX_SIGMA_M == 0.10


def test_axis_sigmas_turns_the_amcl_covariance_into_robot_axes():
    cov = [0.0] * 36
    cov[0], cov[7], cov[35] = 0.01, 0.0004, math.radians(2.0) ** 2

    assert scan.axis_sigmas(cov, 0.0) == pytest.approx((0.10, 0.02, math.radians(2.0)))
    assert scan.axis_sigmas(cov, math.pi / 2) == pytest.approx((0.02, 0.10, math.radians(2.0)))
