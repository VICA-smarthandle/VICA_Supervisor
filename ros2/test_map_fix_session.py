"""map_fix_session 시험입니다. 로봇 없이 pytest 로 돌립니다.

    python3 -m pytest -q VICA_Supervisor/ros2/test_map_fix_session.py

시각은 전부 숫자로 넣습니다(초). 장면과 합성 스캔은 test_map_fix_scan 의 것을 씁니다.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))

from test_map_fix_scan import HALF, LASER, RES, TRUE, cast, room, with_box  # noqa: E402

from vica_nav2.pose_score import MapGrid  # noqa: E402

import map_fix_scan as scan  # noqa: E402
import map_fix_session as session  # noqa: E402

BOX = (3.3, 1.8, 3.7, 2.2)          # 로봇 오른쪽 0.8 m, 반경 2 m 안
GUESS = (TRUE[0] + 0.03, TRUE[1] - 0.02, TRUE[2] + math.radians(0.8))


def changed_scene():
    saved = room(6.0, 5.0)
    return saved, cast(with_box(saved, *BOX), TRUE, LASER, depth=HALF)


def start(saved, now: float = 0.0, radius: float = 2.0):
    return session.ScanSession("s1", "test_map", saved, radius, now)


def run_to_preview(saved, one_scan):
    """맞춤 → 물러나기 → 스캔 50장(5초 내내 10 Hz) → 미리보기까지 돌립니다."""
    run = start(saved)
    run.on_scan(0.1, *one_scan, GUESS, LASER)
    run.tick(5.2)
    for index in range(50):
        run.on_scan(5.3 + index * 0.1, *one_scan, GUESS, LASER)
        run.tick(5.3 + index * 0.1)
    run.tick(10.3)
    return run


# ---------------------------------------------------------------------------
# 정상 흐름
# ---------------------------------------------------------------------------


def test_happy_path_refine_stepback_scan_preview():
    saved, one_scan = changed_scene()
    run = start(saved)
    assert run.phase == "refine"

    run.on_scan(0.1, *one_scan, GUESS, LASER)
    assert run.phase == "step_back"
    assert math.hypot(run.pose[0] - TRUE[0], run.pose[1] - TRUE[1]) <= 0.012
    # 반경 원의 중심은 로봇이 아니라 라이다 자리입니다(앞 0.185 m). 앱이 '이 원 밖으로'를 여기에
    # 그립니다(11-19 독립 검토 3).
    cx, cy = run.state(0.1)["centre"]
    lx = run.pose[0] + math.cos(run.pose[2]) * LASER[0]
    ly = run.pose[1] + math.sin(run.pose[2]) * LASER[0]
    assert math.hypot(cx - lx, cy - ly) < 0.002
    assert math.hypot(cx - run.pose[0], cy - run.pose[1]) > 0.18

    run.tick(5.0)
    assert run.phase == "step_back"      # 0.1 에 시작했으니 5.1 에 끝납니다
    run.tick(5.2)
    assert run.phase == "scanning"

    for index in range(50):
        run.on_scan(5.3 + index * 0.1, *one_scan, GUESS, LASER)
    run.tick(10.1)
    assert run.phase == "scanning"
    run.tick(10.3)
    assert run.phase == "preview"

    state = run.state(10.3)
    assert state["added"] > 0 and state["removed"] == 0
    assert state["score_after"] > state["score_before"]
    assert len(state["cells"]) == state["added"]
    # 합성 스캔은 끝점을 반 칸 깊이로 밀어 넣어서(HALF) 상자 모서리에서는 옆 칸에 떨어질 수 있습니다.
    for x, y, kind in state["cells"]:
        assert kind == 1
        assert BOX[0] - RES <= x <= BOX[2] + RES and BOX[1] - RES <= y <= BOX[3] + RES
    assert len(run.changes.added) == state["added"]


def test_state_carries_every_key_the_app_reads():
    saved, one_scan = changed_scene()
    run = start(saved)
    run.on_scan(0.1, *one_scan, GUESS, LASER)

    state = run.state(0.1)

    assert set(state) == {
        "session", "map_id", "phase", "reason", "remaining_s", "radius_m", "moved_m", "moved_deg",
        "score", "score_before", "score_after", "added", "removed", "cells", "ambiguous", "centre",
    }
    assert (state["session"], state["map_id"], state["phase"], state["radius_m"]) == ("s1", "test_map", "step_back", 2.0)
    assert state["score"] > 80 and state["cells"] == [] and state["ambiguous"] == []
    assert 0.02 < state["moved_m"] < 0.06


def test_remaining_seconds_count_down():
    saved, one_scan = changed_scene()
    run = start(saved)
    assert run.state(0.0)["remaining_s"] == 0          # 맞춤 단계에는 세지 않습니다
    run.on_scan(0.1, *one_scan, GUESS, LASER)
    assert run.state(0.1)["remaining_s"] == 5
    assert run.state(2.6)["remaining_s"] == 3
    run.tick(5.2)
    assert run.state(5.2)["remaining_s"] == 5          # 스캔 5초
    assert run.state(9.9)["remaining_s"] == 1


# ---------------------------------------------------------------------------
# 실패로 끝나는 길
# ---------------------------------------------------------------------------


def test_refine_failure_goes_to_failed_with_reason():
    data = np.full((80, 640), 100, dtype=np.int8)
    data[20:60, 20:620] = 0                              # 폭 2 m · 길이 30 m 복도
    corridor = MapGrid(data, RES, 0.0, 0.0)
    middle = (16.0, 2.0, 0.0)
    run = start(corridor)

    run.on_scan(0.1, *cast(corridor, middle, LASER, depth=HALF, max_range=16.0), middle, LASER)

    assert (run.phase, run.reason) == ("failed", "ambiguous")
    assert run.state(0.1)["ambiguous"] == ["forward"]
    run.tick(100.0)
    assert run.phase == "failed"                         # 실패한 뒤에는 아무것도 진행하지 않습니다


def test_motion_during_scan_fails_with_moved():          # Review Focus 5
    saved, one_scan = changed_scene()
    run = start(saved)
    run.on_scan(0.1, *one_scan, GUESS, LASER)
    run.tick(5.2)
    run.on_motion(0.01, 0.01)                            # 문턱 아래는 서 있는 것입니다
    assert run.phase == "scanning"

    run.on_motion(0.05, 0.0)

    assert (run.phase, run.reason) == ("failed", "moved")


def test_turning_in_place_also_counts_as_moved():
    saved, one_scan = changed_scene()
    run = start(saved)
    run.on_scan(0.1, *one_scan, GUESS, LASER)
    run.on_motion(0.0, -0.2)
    assert (run.phase, run.reason) == ("failed", "moved")


def test_lock_during_step_back_fails_with_busy_driving():   # Review Focus 5
    saved, one_scan = changed_scene()
    run = start(saved)
    run.on_scan(0.1, *one_scan, GUESS, LASER)
    run.on_lock(False)
    assert run.phase == "step_back"

    run.on_lock(True)

    assert (run.phase, run.reason) == ("failed", "busy_driving")


def test_no_scan_for_two_seconds_fails_with_no_pose():
    saved, one_scan = changed_scene()
    waiting = start(saved)
    waiting.tick(1.9)
    assert waiting.phase == "refine"
    waiting.tick(2.1)
    assert (waiting.phase, waiting.reason) == ("failed", "no_pose")

    run = start(saved)
    run.on_scan(0.1, *one_scan, GUESS, LASER)
    run.tick(5.2)                                        # 스캔 시작
    run.on_scan(5.3, *one_scan, GUESS, LASER)
    run.tick(7.2)
    assert run.phase == "scanning"
    run.tick(7.4)                                        # 마지막 스캔 뒤 2 s 넘게 끊김
    assert (run.phase, run.reason) == ("failed", "no_pose")


def test_no_change_fails_with_no_change():
    saved = room(6.0, 5.0)
    run = run_to_preview(saved, cast(saved, TRUE, LASER, depth=HALF))
    assert (run.phase, run.reason) == ("failed", "no_change")
    assert run.changes is None


# ---------------------------------------------------------------------------
# 끝내기
# ---------------------------------------------------------------------------


def test_preview_times_out_after_five_minutes():         # Review Focus 4
    run = run_to_preview(*changed_scene())
    run.on_motion(0.3, 0.0)                              # 미리보기 중 움직여도 그대로 둡니다
    run.on_lock(True)
    run.tick(10.3 + 299.0)
    assert run.phase == "preview"

    run.tick(10.3 + 301.0)

    assert (run.phase, run.reason) == ("done", "timeout")
    assert run.changes is None                           # 버린 뒤에는 적용할 것이 없습니다


def test_cancel_at_any_phase():
    saved, one_scan = changed_scene()
    for advance in (0, 1, 2):
        run = start(saved)
        if advance >= 1:
            run.on_scan(0.1, *one_scan, GUESS, LASER)
        if advance >= 2:
            run.tick(5.2)
        run.cancel()
        assert (run.phase, run.reason) == ("done", "cancelled")
        run.on_scan(6.0, *one_scan, GUESS, LASER)
        run.tick(20.0)
        assert run.phase == "done"

    preview = run_to_preview(saved, one_scan)
    preview.cancel()
    assert preview.phase == "done" and preview.changes is None


def test_cells_are_capped():
    grid = room(6.0, 5.0)
    rows, cols = np.mgrid[20:70, 20:80]                  # 3,000칸
    many = np.stack([rows.ravel(), cols.ravel()], axis=1)
    changes = scan.Changes(added=many[:2500], removed=many[2500:])

    cells = session.cells_payload(grid, changes)

    assert len(cells) == session.MAX_CELLS == 2000
    assert all(kind == 1 for _, _, kind in cells)        # 넘치면 새로 생긴 칸부터 싣습니다
    few = scan.Changes(added=many[:2], removed=many[2:3])
    assert [kind for _, _, kind in session.cells_payload(grid, few)] == [1, 1, -1]
