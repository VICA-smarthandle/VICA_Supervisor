#!/usr/bin/env python3
"""앱 '지도 수정'의 부분 스캔 계산입니다. ROS 를 쓰지 않습니다.

설계서: 루트 docs/superpowers/specs/2026-11-18-map-fix-erase-partial-scan-design.md 6.5

로봇이 서 있는 동안 받은 스캔 여러 장을 저장된 지도에 얹어, 지도와 달라진 칸만 골라냅니다.
SLAM 이 아닙니다 — 자세를 먼저 지도에 맞춘 뒤(자세 다시 맞춤) 그 자세로 얹기만 합니다.

칸 순서는 전부 **격자 순서**입니다(vica_nav2.pose_score.MapGrid, 0행이 origin_y 쪽).
그림 순서와 오가는 일은 map_fix_store 가 합니다.

이 모듈은 numpy·scipy·vica_nav2 를 불러옵니다. map_fix_node 는 쉬는 동안 가볍게 있으려고
이 모듈을 요청이 올 때 처음 import 합니다.
"""

from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np
from scipy import ndimage

from vica_nav2.pose_score import (
    MAX_DIST,
    MIN_RANGE,
    OCCUPIED_THRESHOLD,
    MapGrid,
    ScanBeams,
    beam_hits,
    filter_beams,
    score_pose,
    search_pose,
)

# --- 변경 판정 값 (설계서 6.5 의 시작값. 0단계 실측으로 고칩니다) ----------------
#
# N = 모은 스캔 수.
HIT_RATIO = 0.8        # 새로 생김: 그 칸에 끝점이 떨어진 스캔이 N 의 이만큼 이상
PASS_RATIO = 0.8       # 없어짐: 빔이 그 칸을 지나간 스캔이 N 의 이만큼 이상
MAX_HIT_RATIO = 0.1    # 없어짐: 그 칸에 끝점이 떨어진 스캔은 N 의 이만큼 이하
NEIGHBOR_CELLS = 1     # '주변'은 8방향 몇 칸까지인가
# 빔이 그 칸을 지나 이만큼 더 나아가야 '지나감'으로 칩니다. 끝점 바로 앞 칸까지 세면
# 벽을 비스듬히 스치는 빔이 벽 칸을 지워 버립니다.
BEYOND_M = 0.10
RAY_STEP_M = 0.025     # 빔 위를 훑는 간격(반 칸)


class ScanAccumulator:
    """스캔 여러 장의 '맞음'·'지나감'을 칸마다 셉니다.

    한 스캔에서 한 칸은 맞음·지나감을 각각 많아야 한 번 셉니다 — 빔 여러 개가 같은 칸에
    떨어져도 1 입니다. 그래야 '스캔 N 장 중 몇 장에서 보였는가'가 됩니다.
    """

    def __init__(self, grid: MapGrid, radius_m: float) -> None:
        self.grid = grid
        self.radius_m = float(radius_m)
        self.n_scans = 0
        shape = (grid.height, grid.width)
        self.hit_scans = np.zeros(shape, dtype=np.int32)
        self.pass_scans = np.zeros(shape, dtype=np.int32)
        # 반경은 첫 스캔의 라이다 자리에서 잽니다. 그 전에는 전부 거짓입니다.
        self.in_radius = np.zeros(shape, dtype=bool)
        self._centre: tuple[float, float] | None = None

    def _cells(self, wx: np.ndarray, wy: np.ndarray):
        """map 좌표를 (행, 열)과 '지도 안인가'로 바꿉니다."""
        cols = np.floor((wx - self.grid.origin_x) / self.grid.resolution).astype(np.int64)
        rows = np.floor((wy - self.grid.origin_y) / self.grid.resolution).astype(np.int64)
        inside = (rows >= 0) & (rows < self.grid.height) & (cols >= 0) & (cols < self.grid.width)
        return rows, cols, inside

    def _set_centre(self, lx: float, ly: float) -> None:
        self._centre = (lx, ly)
        resolution = self.grid.resolution
        xs = self.grid.origin_x + (np.arange(self.grid.width) + 0.5) * resolution
        ys = self.grid.origin_y + (np.arange(self.grid.height) + 0.5) * resolution
        distance_sq = (xs[None, :] - lx) ** 2 + (ys[:, None] - ly) ** 2
        self.in_radius = distance_sq <= self.radius_m ** 2

    def add_scan(self, ranges, angle_min: float, angle_increment: float,
                 pose: tuple[float, float, float], sensor: tuple[float, float, float]) -> None:
        """스캔 한 장을 얹습니다.

        pose 는 base 의 map 자세 (x, y, yaw[rad]), sensor 는 base 기준 라이다 자리
        (x, y, yaw[rad]) 입니다. inf·nan 과 MIN_RANGE 미만(차체 반사)은 버립니다.
        """
        x, y, yaw = pose
        sx, sy, syaw = sensor
        lx, ly = sensor_position(pose, sensor)
        if self._centre is None:
            self._set_centre(lx, ly)
        self.n_scans += 1

        ranges = np.asarray(ranges, dtype=np.float64)
        index = np.arange(ranges.size)
        valid = np.isfinite(ranges) & (ranges >= MIN_RANGE)
        ranges, index = ranges[valid], index[valid]
        if ranges.size == 0:
            return
        theta = yaw + syaw + angle_min + index * angle_increment
        cos_t, sin_t = np.cos(theta), np.sin(theta)

        # 맞음 — 끝점이 반경 안인 빔만.
        hit_mask = np.zeros(self.hit_scans.shape, dtype=bool)
        near = ranges <= self.radius_m
        rows, cols, inside = self._cells(lx + cos_t[near] * ranges[near], ly + sin_t[near] * ranges[near])
        hit_mask[rows[inside], cols[inside]] = True

        # 지나감 — 끝점에서 BEYOND_M 앞까지, 반경을 넘는 빔은 반경까지.
        pass_mask = np.zeros(self.pass_scans.shape, dtype=bool)
        limit = np.minimum(ranges - BEYOND_M, self.radius_m)
        steps = np.arange(0.0, self.radius_m + RAY_STEP_M, RAY_STEP_M)
        along = steps[None, :] <= limit[:, None]
        px = lx + cos_t[:, None] * steps[None, :]
        py = ly + sin_t[:, None] * steps[None, :]
        rows, cols, inside = self._cells(px[along], py[along])
        pass_mask[rows[inside], cols[inside]] = True

        self.hit_scans += hit_mask
        self.pass_scans += pass_mask


@dataclass(frozen=True)
class Changes:
    """지도와 달라진 칸. 둘 다 (K, 2) 정수 배열이고 한 줄이 격자 (행, 열)입니다."""

    added: np.ndarray
    removed: np.ndarray


def _grow(mask: np.ndarray, cells: int) -> np.ndarray:
    """8방향으로 cells 칸 넓힙니다."""
    if cells <= 0:
        return mask
    return ndimage.binary_dilation(mask, structure=np.ones((3, 3), dtype=bool), iterations=cells)


def detect_changes(grid: MapGrid, acc: ScanAccumulator) -> Changes:
    """반경 안에서 새로 생긴 칸과 없어진 칸을 고릅니다. 나머지는 건드리지 않습니다."""
    empty = np.zeros((0, 2), dtype=np.int64)
    count = acc.n_scans
    if count == 0:
        return Changes(added=empty, removed=empty.copy())

    occupied = grid.data >= OCCUPIED_THRESHOLD
    hit_strong = acc.in_radius & (acc.hit_scans >= HIT_RATIO * count)

    # 새로 생김: 검은 칸이 아닌 곳에 꾸준히 맞았고, 주변에 검은 칸이 없다.
    # 주변에 검은 칸이 있으면 같은 벽이 반 칸 어긋나 보인 것이라 그대로 둡니다.
    added = hit_strong & ~occupied & ~_grow(occupied, NEIGHBOR_CELLS)

    # 없어짐: 검은 칸인데 빔이 꾸준히 지나갔고 거의 맞지 않았으며, 주변에 꾸준히 맞은 칸이 없다.
    removed = (
        occupied
        & acc.in_radius
        & (acc.pass_scans >= PASS_RATIO * count)
        & (acc.hit_scans <= MAX_HIT_RATIO * count)
        & ~_grow(hit_strong, NEIGHBOR_CELLS)
    )
    return Changes(added=np.argwhere(added), removed=np.argwhere(removed))


def patched_grid(grid: MapGrid, changes: Changes) -> MapGrid:
    """변경을 반영한 새 격자. 원본은 그대로입니다."""
    data = grid.data.copy()
    if len(changes.added):
        data[changes.added[:, 0], changes.added[:, 1]] = 100
    if len(changes.removed):
        data[changes.removed[:, 0], changes.removed[:, 1]] = 0
    return MapGrid(data, grid.resolution, grid.origin_x, grid.origin_y)


def sensor_position(pose: tuple[float, float, float], sensor: tuple[float, float, float]) -> tuple[float, float]:
    """base 의 map 자세와 base 기준 라이다 자리로 라이다의 map 위치를 냅니다. 반경은 여기서 잽니다."""
    x, y, yaw = pose
    sx, sy = sensor[0], sensor[1]
    return x + math.cos(yaw) * sx - math.sin(yaw) * sy, y + math.sin(yaw) * sx + math.cos(yaw) * sy


def cell_centres(grid: MapGrid, cells: np.ndarray) -> np.ndarray:
    """격자 (행, 열) 목록을 칸 중심의 map 좌표 (x, y) 로 바꿉니다."""
    cells = np.asarray(cells, dtype=np.float64).reshape(-1, 2)
    x = grid.origin_x + (cells[:, 1] + 0.5) * grid.resolution
    y = grid.origin_y + (cells[:, 0] + 0.5) * grid.resolution
    return np.stack([x, y], axis=1)


# ---------------------------------------------------------------------------
# 자세 다시 맞춤 · 구분 검사
# ---------------------------------------------------------------------------
#
# AMCL 자세는 출발값으로만 씁니다. 틀린 자세로 얹으면 그 오차가 지도에 남기 때문입니다.
#
#   1회째(거친 맞춤)  pose_score.search_pose — AMCL 과 같은 잣대(sigma_hit 0.2)
#   남길 빔           1회째 자세에서 끝점이 벽 겉 칸 KEEP_DIST_M 안인 빔(안 바뀐 벽)
#   2회째(정밀 맞춤)  남긴 빔의 '벽 겉 칸까지 거리' 제곱 평균이 가장 작은 자세
#   구분 검사         자세를 밀어도 그 거리가 거의 안 늘어나는 축은 '구분되지 않는다'
#
# 통과·구분 판정에 pose_score 점수를 쓰지 않는 이유: 그 점수는 5 cm 를 밀어도 99.5 → 97.3
# 밖에 안 떨어집니다(pose_score.py 2026-09-02 실측). 출발해도 되는가를 보는 잣대라 무딥니다.
#
# 거리는 '벽 겉 칸의 가운데까지'입니다(build_surface_field).
#   - 가운데: 지도는 스캔 끝점이 떨어진 칸을 검은 칸으로 칠해 만들어서 벽 면이 평균적으로 칸
#     가운데에 있습니다. 가운데까지의 거리가 0 일 때가 맞은 자세입니다.
#   - 겉 칸만: 검은 칸 전체를 기준으로 하면 두꺼운 벽 속은 어디나 거리 0 이라, 끝점이 벽 속으로
#     파고드는 자세도 좋게 보입니다. 벽이 한두 칸 두께인 보통 지도에서는 차이가 없습니다.
#
# **구분 검사를 '남는 빔 수'로 세지 않는 이유**(2026-11-19 시험에서 확인). 처음에는 자세를 민
# 뒤에도 끝점이 벽 0.05 m 안에 남는 빔을 세었는데, 벽이 가까운 작은 방에서는 2° 를 돌려도
# 끝점이 벽을 따라 미끄러질 뿐 0.05 m 를 넘지 않아 방향이 '구분되지 않는다'로 나왔습니다.
# 거리 제곱 평균이 얼마나 늘어나는가로 보면 방 크기에 덜 매입니다.

KEEP_DIST_M = 0.10
MIN_KEPT = 60
MIN_KEPT_RATIO = 0.5
# 남긴 빔의 벽까지 거리 RMS 상한. 시작값 0.03 m 는 11-19 실기에서 위치가 맞는데도 3.4~3.7 cm 가
# 나와(라이다 잡음은 11-01 실측 2.4 mm — 대부분 지도 한 칸 5 cm 안에서 벽 자리 차이) 한 칸으로 올렸습니다.
# 남길 때 KEEP_DIST_M 0.10 m 로 거르므로 이 값은 약 0.058 m 를 넘기 어렵습니다 — 자세를 지키는 것은
# 남긴 빔 비율·옮긴 양·구분 검사입니다.
MAX_RMS_M = 0.05
FINE_XY_M = 0.05
FINE_YAW = math.radians(1.0)
# 출발 자세(AMCL)에서 이보다 멀리 옮겨야 맞는다면 믿지 않습니다. 장면이 크게 바뀌어 엉뚱한
# 벽에 붙었을 수 있고, 그 정도로 틀렸으면 초기 위치부터 다시 잡을 일입니다.
MAX_MOVE_M = 0.30
MAX_MOVE_DEG = 10.0
AMBIG_SHIFT_M = 0.10
AMBIG_YAW = math.radians(2.0)
# 그만큼 밀었을 때 RMS 거리가 이만큼은 늘어야 그 축이 정해진 것으로 봅니다.
# 0.02 m 는 빔의 약 4 % 가 0.10 m 를 고스란히 느끼는 정도입니다(0.10·√0.04).
AMBIG_MIN_RISE_M = 0.02
AMBIG_MIN_RISE_YAW_M = 0.01

# 2회째 탐색의 두 단: (xy 범위, xy 간격, yaw 범위, yaw 간격)
_FINE_STAGES = (
    (FINE_XY_M, 0.01, FINE_YAW, math.radians(0.2)),
    (0.01, 0.002, math.radians(0.2), math.radians(0.05)),
)
# 점수가 같으면 덜 옮긴 자세를 고릅니다. 긴 복도처럼 한 축으로 평평한 곳에서 탐색 범위 끝으로
# 미끄러지지 않게 하는 아주 작은 값입니다(거리 제곱 평균은 1e-4 m² 안팎).
_STAY_WEIGHT = 1e-9


@dataclass(frozen=True)
class RefineResult:
    """자세 다시 맞춤 결과. ok 가 거짓이어도 나머지 칸은 화면에 보일 값으로 채웁니다."""

    ok: bool
    reason: str                    # "" | "low_match" | "ambiguous"
    x: float
    y: float
    yaw: float
    score: float                   # pose_score 점수(유효 빔 전부) — 화면의 '위치 맞춤 %'
    used_beams: int
    kept_beams: int
    rms_m: float
    moved_m: float                 # 출발 자세에서 옮긴 거리
    moved_deg: float
    ambiguous: tuple[str, ...]     # "forward" | "lateral" | "yaw"
    hits: np.ndarray               # (K, 2) 맞춘 자세에서 본 라이다 점, map 좌표


def interp_field(field: np.ndarray, grid: MapGrid, wx: np.ndarray, wy: np.ndarray,
                 max_dist: float) -> np.ndarray:
    """거리표를 칸 가운데 사이에서 선형 보간해 읽습니다. 지도 밖은 max_dist 입니다."""
    fx = (np.asarray(wx, dtype=np.float64) - grid.origin_x) / grid.resolution - 0.5
    fy = (np.asarray(wy, dtype=np.float64) - grid.origin_y) / grid.resolution - 0.5
    col0 = np.floor(fx).astype(np.int64)
    row0 = np.floor(fy).astype(np.int64)
    tx, ty = fx - col0, fy - row0

    def read(rows: np.ndarray, cols: np.ndarray) -> np.ndarray:
        inside = (rows >= 0) & (rows < grid.height) & (cols >= 0) & (cols < grid.width)
        values = np.full(rows.shape, max_dist, dtype=np.float64)
        values[inside] = field[rows[inside], cols[inside]]
        return values

    return (
        (1 - tx) * (1 - ty) * read(row0, col0)
        + tx * (1 - ty) * read(row0, col0 + 1)
        + (1 - tx) * ty * read(row0 + 1, col0)
        + tx * ty * read(row0 + 1, col0 + 1)
    )


def _span(centre: float, radius: float, step: float) -> np.ndarray:
    count = int(round(radius / step))
    return centre + np.arange(-count, count + 1, dtype=np.float64) * step


def _distances(field, grid, beams: ScanBeams, xs: np.ndarray, ys: np.ndarray, yaw: float, sensor):
    """자세 후보 (xs × ys, yaw 하나)마다 빔 끝점의 검은 칸까지 거리. 모양 (len(xs), len(ys), 빔)."""
    hit_x, hit_y = beam_hits(beams, 0.0, 0.0, yaw, sensor=sensor)
    wx = xs[:, None, None] + hit_x[None, None, :]
    wy = ys[None, :, None] + hit_y[None, None, :]
    wx, wy = np.broadcast_arrays(wx, wy)
    return interp_field(field, grid, wx, wy, MAX_DIST)


def _fine_fit(field, grid, beams: ScanBeams, start, sensor):
    """남긴 빔으로 자세를 정밀하게 맞춥니다. (x, y, yaw, 거리 제곱 평균, 1단이 범위 끝에 걸렸는가)."""
    x, y, yaw = start
    cost, at_edge = math.inf, False
    for stage, (xy_radius, xy_step, yaw_radius, yaw_step) in enumerate(_FINE_STAGES):
        xs, ys = _span(x, xy_radius, xy_step), _span(y, xy_radius, xy_step)
        yaws = _span(yaw, yaw_radius, yaw_step)
        best = None
        for k, candidate in enumerate(yaws):
            mean_sq = (_distances(field, grid, beams, xs, ys, candidate, sensor) ** 2).mean(axis=2)
            stay = (((xs[:, None] - x) ** 2 + (ys[None, :] - y) ** 2) / xy_radius ** 2
                    + ((candidate - yaw) / yaw_radius) ** 2)
            total = mean_sq + _STAY_WEIGHT * stay
            i, j = np.unravel_index(np.argmin(total), total.shape)
            if best is None or total[i, j] < best[0]:
                best = (float(total[i, j]), float(mean_sq[i, j]), i, j, k)
        _, cost, i, j, k = best
        if stage == 0:
            at_edge = (i in (0, len(xs) - 1) or j in (0, len(ys) - 1) or k in (0, len(yaws) - 1))
        x, y, yaw = float(xs[i]), float(ys[j]), float(yaws[k])
    return x, y, yaw, cost, at_edge


def _ambiguous_axes(field, grid, beams: ScanBeams, pose, sensor) -> tuple[str, ...]:
    """자세를 밀어도 벽까지 거리가 거의 안 늘어나는 축들."""
    x, y, yaw = pose

    def rms(px: float, py: float, pyaw: float) -> float:
        distance = _distances(field, grid, beams, np.array([px]), np.array([py]), pyaw, sensor)
        return float(np.sqrt((distance ** 2).mean()))

    base = rms(x, y, yaw)
    forward = (math.cos(yaw) * AMBIG_SHIFT_M, math.sin(yaw) * AMBIG_SHIFT_M)
    lateral = (-math.sin(yaw) * AMBIG_SHIFT_M, math.cos(yaw) * AMBIG_SHIFT_M)
    moves = {
        "forward": (AMBIG_MIN_RISE_M, [(x + s * forward[0], y + s * forward[1], yaw) for s in (1, -1)]),
        "lateral": (AMBIG_MIN_RISE_M, [(x + s * lateral[0], y + s * lateral[1], yaw) for s in (1, -1)]),
        "yaw": (AMBIG_MIN_RISE_YAW_M, [(x, y, yaw + s * AMBIG_YAW) for s in (1, -1)]),
    }
    # 양쪽 가운데 덜 늘어난 쪽을 봅니다 — 한쪽으로만 정해진 것은 정해진 것이 아닙니다.
    return tuple(
        axis for axis, (need, pair) in moves.items()
        if min(rms(*moved) for moved in pair) - base < need
    )


def build_surface_field(grid: MapGrid) -> np.ndarray:
    """칸마다 가장 가까운 '벽 겉 칸'까지 거리(m). 겉 칸은 이웃(8방향)에 빈 칸이 있는 검은 칸입니다.

    지도 가장자리 밖은 검은 칸으로 칩니다 — 지도 테두리를 벽 면으로 보지 않으려는 것입니다.
    """
    occupied = grid.data >= OCCUPIED_THRESHOLD
    inner = ndimage.binary_erosion(occupied, structure=np.ones((3, 3), dtype=bool), border_value=1)
    surface = occupied & ~inner
    if not surface.any():
        return np.full(occupied.shape, MAX_DIST, dtype=np.float64)
    distance = ndimage.distance_transform_edt(~surface) * grid.resolution
    return np.minimum(distance, MAX_DIST)


def refine_pose(grid: MapGrid, field: np.ndarray, ranges, angle_min: float, angle_increment: float,
                guess: tuple[float, float, float], sensor: tuple[float, float, float],
                surface: np.ndarray | None = None,
                guess_sigma: tuple[float, float, float] | None = None) -> RefineResult:
    """스캔 한 장을 지도에 다시 맞춥니다. guess 는 출발 자세 (x, y, yaw[rad])입니다.

    field 는 pose_score.build_likelihood_field(grid)(거친 맞춤·점수용), surface 는
    build_surface_field(grid)(정밀 맞춤·구분 검사용)입니다. surface 를 안 주면 여기서 만듭니다.
    """
    beams = filter_beams(ranges, angle_min, angle_increment)
    if surface is None:
        surface = build_surface_field(grid)

    def result(ok, reason, pose, kept=0, rms=0.0, ambiguous=()):
        x, y, yaw = pose
        hit_x, hit_y = beam_hits(beams, x, y, yaw, sensor=sensor)
        turn = (yaw - guess[2] + math.pi) % (2.0 * math.pi) - math.pi
        return RefineResult(
            ok=ok, reason=reason, x=x, y=y, yaw=yaw,
            score=score_pose(field, grid, beams, x, y, yaw, sensor=sensor),
            used_beams=beams.used, kept_beams=kept, rms_m=rms,
            moved_m=math.hypot(x - guess[0], y - guess[1]), moved_deg=abs(math.degrees(turn)),
            ambiguous=tuple(ambiguous), hits=np.stack([hit_x, hit_y], axis=1),
        )

    if beams.used == 0:
        return result(False, "low_match", guess)

    # 1회째. search_pose 가 ok 를 주지 않아도 그 자세에서 계속 갑니다 — 판정은 아래 조건이 합니다.
    coarse = search_pose(field, grid, beams, guess[0], guess[1], yaw_hint=guess[2], sensor=sensor)
    first = (coarse.x, coarse.y, coarse.yaw)

    # 안 바뀐 벽에 떨어진 빔만 남깁니다.
    hit_x, hit_y = beam_hits(beams, *first, sensor=sensor)
    keep = interp_field(surface, grid, hit_x, hit_y, MAX_DIST) <= KEEP_DIST_M
    kept = int(keep.sum())
    if kept < MIN_KEPT or kept < MIN_KEPT_RATIO * beams.used:
        return result(False, "low_match", first, kept)
    kept_beams = ScanBeams(beams.ranges[keep], beams.angles[keep], beams.total)

    # 2회째.
    x, y, yaw, mean_sq, at_edge = _fine_fit(surface, grid, kept_beams, first, sensor)
    rms = math.sqrt(mean_sq)
    done = result(True, "", (x, y, yaw), kept, rms)
    if at_edge or rms > MAX_RMS_M or done.moved_m > MAX_MOVE_M or done.moved_deg > MAX_MOVE_DEG:
        return result(False, "low_match", (x, y, yaw), kept, rms)

    ambiguous = _ambiguous_axes(surface, grid, kept_beams, (x, y, yaw), sensor)
    if ambiguous:
        # 구분되지 않는 축은, AMCL 이 그 축을 HOLD_MAX_SIGMA_M 안으로 확신할 때만 출발 자세(AMCL — 지금 주행에
        # 쓰는 위치)를 두고 통과합니다(11-19 사용자 결정 '그 축만 주행 위치로'와 그 부작용 대책). 그 축의
        # AMCL 오차는 그대로 지도에 들어갑니다 — 11-19 실기에서 AMCL 은 σ 7 cm 로 봤지만 스캔과는 12~16 cm
        # 달랐습니다. 방향(yaw)은 두지 않습니다: 3.7° 틀리면 3 m 끝에서 19 cm 가 어긋납니다.
        if _can_hold(ambiguous, guess_sigma):
            x, y, yaw = hold_axes((x, y, yaw), guess, ambiguous)
            return result(True, "", (x, y, yaw), kept, rms, ambiguous)
        return result(False, "ambiguous", (x, y, yaw), kept, rms, ambiguous)
    return done


HOLD_MAX_SIGMA_M = 0.10


def _can_hold(axes, guess_sigma) -> bool:
    if guess_sigma is None or "yaw" in axes:
        return False
    index = {"forward": 0, "lateral": 1}
    return all(float(guess_sigma[index[axis]]) <= HOLD_MAX_SIGMA_M for axis in axes)


def axis_sigmas(covariance, yaw: float) -> tuple[float, float, float]:
    """AMCL 공분산(6×6, 행 우선 36개)을 로봇 기준 (앞뒤 m, 좌우 m, 방향 rad) 표준편차로."""
    xx, xy, yy, turn = float(covariance[0]), float(covariance[1]), float(covariance[7]), float(covariance[35])
    c, s = math.cos(yaw), math.sin(yaw)
    forward = c * c * xx + 2.0 * c * s * xy + s * s * yy
    lateral = s * s * xx - 2.0 * c * s * xy + c * c * yy
    return math.sqrt(max(forward, 0.0)), math.sqrt(max(lateral, 0.0)), math.sqrt(max(turn, 0.0))


def hold_axes(pose: tuple, guess: tuple, axes) -> tuple[float, float, float]:
    """pose 의 axes('forward' · 'lateral' · 'yaw')를 guess 값으로 바꿉니다. 앞뒤·좌우는 바꾼 방향 기준입니다."""
    x, y, yaw = pose
    if "yaw" in axes:
        yaw = guess[2]
    dx, dy = guess[0] - x, guess[1] - y
    for axis, (ux, uy) in (("forward", (math.cos(yaw), math.sin(yaw))),
                           ("lateral", (-math.sin(yaw), math.cos(yaw)))):
        if axis in axes:
            along = dx * ux + dy * uy
            x, y = x + along * ux, y + along * uy
    return x, y, yaw


# ---------------------------------------------------------------------------
# 몸체 거르기
# ---------------------------------------------------------------------------
#
# 11-19 실기: 로봇이 서 있으니 뒤쪽 차체(라이다 뒤 0.36~0.46 m)가 스캔마다 같은 자리에 찍혀 '새로 생김'
# 기준(N 의 80 %)을 넘었고, 지도에 장애물로 써졌습니다. 몸체와 그 사방 BODY_MARGIN_M 안에 떨어진 빔은
# 지도에도 미리보기 점에도 쓰지 않습니다(사용자 결정 '몸체 + 사방 20 cm').
#
# FOOTPRINT 는 vica_nav2/config/nav2_params.yaml 의 footprint 와 같은 값입니다(base_footprint 기준, m).
FOOTPRINT = ((0.151, 0.225), (0.151, -0.225), (-0.459, -0.225), (-0.569, -0.035), (-0.569, 0.035), (-0.459, 0.225))
BODY_MARGIN_M = 0.20


def mask_body(ranges, angle_min: float, angle_increment: float, sensor: tuple[float, float, float],
              footprint=FOOTPRINT, margin: float = BODY_MARGIN_M) -> np.ndarray:
    """몸체 안이나 몸체에서 margin 안에 떨어진 빔을 NaN 으로 바꾼 사본. sensor 는 base 기준 라이다 자리입니다."""
    out = np.asarray(ranges, dtype=np.float64).copy()
    angles = angle_min + np.arange(out.size) * angle_increment + sensor[2]
    with np.errstate(invalid="ignore"):
        px = sensor[0] + out * np.cos(angles)
        py = sensor[1] + out * np.sin(angles)
    finite = np.isfinite(px) & np.isfinite(py)
    poly = np.asarray(footprint, dtype=np.float64)
    ax, ay = poly[:, 0], poly[:, 1]
    bx, by = np.roll(ax, -1), np.roll(ay, -1)
    x, y = px[finite, None], py[finite, None]
    # 안쪽(짝홀 규칙)
    crosses = ((ay > y) != (by > y)) & (x < (bx - ax) * (y - ay) / np.where(by == ay, 1e-12, by - ay) + ax)
    inside = crosses.sum(axis=1) % 2 == 1
    # 변까지 거리
    ex, ey = bx - ax, by - ay
    t = np.clip(((x - ax) * ex + (y - ay) * ey) / (ex * ex + ey * ey), 0.0, 1.0)
    near = (np.hypot(x - (ax + t * ex), y - (ay + t * ey)).min(axis=1) <= margin)
    drop = np.zeros(out.size, dtype=bool)
    drop[finite] = inside | near
    out[drop] = np.nan
    return out


def pose_score_percent(grid: MapGrid, field: np.ndarray, ranges, angle_min: float,
                       angle_increment: float, pose: tuple[float, float, float],
                       sensor: tuple[float, float, float]) -> float:
    """화면의 '위치 맞춤 %'. 초기 위치 잡기와 같은 pose_score 점수입니다(유효 빔 전부)."""
    beams = filter_beams(ranges, angle_min, angle_increment)
    return score_pose(field, grid, beams, pose[0], pose[1], pose[2], sensor=sensor)
