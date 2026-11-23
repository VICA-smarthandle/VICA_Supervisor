#!/usr/bin/env python3
"""부분 스캔 한 번의 진행입니다. ROS 를 쓰지 않습니다."""

from __future__ import annotations

import math
from typing import Optional

from vica_nav2.pose_score import MapGrid, build_likelihood_field

import map_fix_scan as scan

STEP_BACK_SEC = 5.0
SCAN_SEC = 5.0
PREVIEW_TIMEOUT_SEC = 300.0
SCAN_SILENCE_SEC = 2.0
MAX_CELLS = 2000
MOVING_LIN = 0.02
MOVING_ANG = 0.05

_BEFORE_PREVIEW = ("refine", "step_back", "scanning")


def cells_payload(grid: MapGrid, changes: scan.Changes, limit: int = MAX_CELLS) -> list:
    """앱에 보낼 칸 목록 [[x, y, 1|-1], …]. 좌표는 칸 중심의 map 좌표(m)입니다."""
    cells = []
    for group, kind in ((changes.added, 1), (changes.removed, -1)):
        for x, y in scan.cell_centres(grid, group):
            if len(cells) >= limit:
                return cells
            cells.append([round(float(x), 3), round(float(y), 3), kind])
    return cells


class ScanSession:
    """부분 스캔 한 번. 노드가 스캔·속도·잠금·시각을 넣어 주면 단계를 넘깁니다."""

    def __init__(self, session_id: str, map_id: str, grid: MapGrid, radius_m: float, now: float) -> None:
        self.session_id = session_id
        self.map_id = map_id
        self.grid = grid
        self.radius_m = float(radius_m)
        self.phase = "refine"
        self.reason = ""
        self.pose: Optional[tuple[float, float, float]] = None
        self.centre: Optional[tuple[float, float]] = None
        self.changes: Optional[scan.Changes] = None
        self.score_before = 0.0
        self.score_after = 0.0

        self._field = build_likelihood_field(grid)
        self._surface = scan.build_surface_field(grid)
        self._phase_since = now
        self._last_scan = now
        self._refined: Optional[scan.RefineResult] = None
        self._acc: Optional[scan.ScanAccumulator] = None
        self._sample = None
        self._recheck = False
        self._recheck_due = False
        self._recheck_since = now

    def on_scan(self, now: float, ranges, angle_min: float, angle_increment: float,
                guess: tuple[float, float, float], sensor: tuple[float, float, float],
                guess_sigma: Optional[tuple[float, float, float]] = None) -> None:
        """스캔 한 장. guess 는 그 순간의 AMCL 자세(출발값), guess_sigma 는 그 로봇 기준 표준편차입니다 —"""
        if self.phase == "refine":
            self._last_scan = now
            refined = self._match(ranges, angle_min, angle_increment, guess, sensor, guess_sigma)
            if refined.ambiguous and (refined.ok or refined.reason == "ambiguous"):
                self._recheck = True
            elif not refined.ok:
                self._fail(refined.reason)
                return
            self.pose = (refined.x, refined.y, refined.yaw)
            self.centre = scan.sensor_position(self.pose, sensor)
            self._enter("step_back", now)
        elif self.phase == "step_back" and self._recheck_due:
            self._last_scan = now
            refined = self._match(ranges, angle_min, angle_increment, guess, sensor, guess_sigma)
            if not refined.ok:
                self._fail(refined.reason)
                return
            self.pose = (refined.x, refined.y, refined.yaw)
            self._recheck = self._recheck_due = False
            self._start_scanning(now)
        elif self.phase == "scanning":
            self._last_scan = now
            if self._sample is None:
                self._sample = (ranges, angle_min, angle_increment, sensor)
            self._acc.add_scan(ranges, angle_min, angle_increment, self.pose, sensor)

    def on_motion(self, linear: float, angular: float) -> None:
        """/odom 의 속도. 미리보기 전에 움직이면 그만둡니다."""
        if self.phase in _BEFORE_PREVIEW and (abs(linear) >= MOVING_LIN or abs(angular) >= MOVING_ANG):
            self._fail("moved")

    def on_lock(self, locked: bool) -> None:
        """잠금 상태(주행 요청·미션이 일을 시작함). 미리보기 전에 걸리면 그만둡니다."""
        if locked and self.phase in _BEFORE_PREVIEW:
            self._fail("busy_driving")

    def tick(self, now: float) -> None:
        """시간으로 넘어가는 단계 전환."""
        if self.phase == "refine":
            if now - self._last_scan > SCAN_SILENCE_SEC:
                self._fail("no_pose")
        elif self.phase == "step_back":
            if self._recheck_due:
                if now - self._recheck_since > SCAN_SILENCE_SEC:
                    self._fail("no_pose")
            elif now - self._phase_since >= STEP_BACK_SEC:
                if self._recheck:
                    self._recheck_due = True
                    self._recheck_since = now
                else:
                    self._start_scanning(now)
        elif self.phase == "scanning":
            if now - self._last_scan > SCAN_SILENCE_SEC:
                self._fail("no_pose")
            elif now - self._phase_since >= SCAN_SEC:
                self._finish_scan(now)
        elif self.phase == "preview":
            if now - self._phase_since >= PREVIEW_TIMEOUT_SEC:
                self._close("timeout")

    def cancel(self) -> None:
        """'중지'·'버리기'. 실패한 세션은 사유를 남겨 둡니다."""
        if self.phase not in ("failed", "done"):
            self._close("cancelled")

    def state(self, now: float) -> dict:
        """토픽 /vica/map_fix/state 에 싣는 값(설계서 6.2)."""
        remaining = 0
        if self.phase == "step_back":
            remaining = max(0, math.ceil(STEP_BACK_SEC - (now - self._phase_since)))
        elif self.phase == "scanning":
            remaining = max(0, math.ceil(SCAN_SEC - (now - self._phase_since)))
        refined = self._refined
        changes = self.changes
        return {
            "session": self.session_id,
            "map_id": self.map_id,
            "phase": self.phase,
            "reason": self.reason,
            "remaining_s": int(remaining),
            "radius_m": self.radius_m,
            "moved_m": round(refined.moved_m, 3) if refined else 0.0,
            "moved_deg": round(refined.moved_deg, 2) if refined else 0.0,
            "score": round(refined.score, 1) if refined else 0.0,
            "score_before": round(self.score_before, 1),
            "score_after": round(self.score_after, 1),
            "added": int(len(changes.added)) if changes else 0,
            "removed": int(len(changes.removed)) if changes else 0,
            "cells": cells_payload(self.grid, changes) if changes else [],
            "ambiguous": list(refined.ambiguous) if refined else [],
            "centre": [round(self.centre[0], 3), round(self.centre[1], 3)] if self.centre else [],
        }

    def _match(self, ranges, angle_min, angle_increment, guess, sensor, guess_sigma):
        refined = scan.refine_pose(
            self.grid, self._field, ranges, angle_min, angle_increment, guess, sensor,
            surface=self._surface, guess_sigma=guess_sigma,
        )
        self._refined = refined
        return refined

    def _start_scanning(self, now: float) -> None:
        self._acc = scan.ScanAccumulator(self.grid, self.radius_m)
        self._last_scan = now
        self._enter("scanning", now)

    def _enter(self, phase: str, now: float) -> None:
        self.phase = phase
        self._phase_since = now

    def _fail(self, reason: str) -> None:
        self.phase, self.reason = "failed", reason
        self.changes = None

    def _close(self, reason: str) -> None:
        self.phase, self.reason = "done", reason
        self.changes = None

    def _finish_scan(self, now: float) -> None:
        if self._acc is None or self._acc.n_scans == 0 or self._sample is None:
            self._fail("no_pose")
            return
        changes = scan.detect_changes(self.grid, self._acc)
        if len(changes.added) == 0 and len(changes.removed) == 0:
            self._fail("no_change")
            return
        ranges, angle_min, angle_increment, sensor = self._sample
        patched = scan.patched_grid(self.grid, changes)
        self.score_before = scan.pose_score_percent(
            self.grid, self._field, ranges, angle_min, angle_increment, self.pose, sensor)
        self.score_after = scan.pose_score_percent(
            patched, build_likelihood_field(patched), ranges, angle_min, angle_increment, self.pose, sensor)
        self.changes = changes
        self._enter("preview", now)
