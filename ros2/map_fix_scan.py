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

from vica_nav2.pose_score import MIN_RANGE, OCCUPIED_THRESHOLD, MapGrid

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
        lx = x + math.cos(yaw) * sx - math.sin(yaw) * sy
        ly = y + math.sin(yaw) * sx + math.cos(yaw) * sy
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


def cell_centres(grid: MapGrid, cells: np.ndarray) -> np.ndarray:
    """격자 (행, 열) 목록을 칸 중심의 map 좌표 (x, y) 로 바꿉니다."""
    cells = np.asarray(cells, dtype=np.float64).reshape(-1, 2)
    x = grid.origin_x + (cells[:, 1] + 0.5) * grid.resolution
    y = grid.origin_y + (cells[:, 0] + 0.5) * grid.resolution
    return np.stack([x, y], axis=1)
