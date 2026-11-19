"""map_fix_core 시험입니다. 로봇 없이 pytest 로 돌립니다.

    python3 -m pytest -q VICA_Supervisor/ros2/test_map_fix_core.py

Nav2 반영(load_map)·로봇 상태·시계·스캔 입력을 전부 가짜로 넣습니다. 지도 파일은 tmp_path 에
실제로 쓰고 읽습니다.
"""

from __future__ import annotations

import json
import math
import subprocess
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from test_map_fix_scan import HALF, LASER, TRUE, cast, room, with_box  # noqa: E402
from test_map_fix_store import MAP, RECT, at, files, with_png  # noqa: E402

import map_fix_core as core  # noqa: E402
import map_fix_store as store  # noqa: E402

IDLE = {"status": "waiting", "current_goal": "", "dialog_state": "idle"}
BIG = "room_map"
BOX = (3.3, 1.8, 3.7, 2.2)
GUESS = (TRUE[0] + 0.03, TRUE[1] - 0.02, TRUE[2] + math.radians(0.8))


class Rig:
    """가짜 주변 장치를 단 MapFixCore 하나."""

    def __init__(self, root: Path, *, current: str | None = MAP, status=IDLE) -> None:
        self.root = root
        if current is not None:
            (root / "CURRENT_MAP").write_text(current + "\n", encoding="utf-8")
        self.status = dict(status) if status is not None else None
        self.apply_result = (True, "", "적용했습니다.")
        self.applied: list[str] = []
        self.time = 0.0
        self.second = 0
        self.scan_input = None
        self.sensing: list[bool] = []
        self.core = core.MapFixCore(
            root,
            apply=self._apply,
            status=lambda: self.status,
            now=self._now,
            clock=lambda: self.time,
            grab_scan=lambda: self.scan_input,
            set_sensing=self.sensing.append,
            new_session_id=lambda: "s1",
        )

    def _apply(self, map_id: str):
        self.applied.append(map_id)
        return self.apply_result

    def _now(self):
        self.second += 1
        return at(self.second)

    def call(self, action: str, args=None, map_id: str = MAP):
        text = "" if args is None else json.dumps(args)
        accepted, reason, message, result = self.core.handle(map_id, action, text)
        assert isinstance(message, str) and isinstance(result, dict)
        return accepted, reason, result


def history(rig: Rig, map_id: str = MAP) -> list[dict]:
    return rig.call("get", map_id=map_id)[2]["history"]


# ---------------------------------------------------------------------------
# 잠금
# ---------------------------------------------------------------------------


def test_lock_reason_table():
    assert core.lock_reason("waiting", "", "idle", False) == ""
    for dialog in ("", "idle", "none", "arrived", "failed", "estopped", " idle "):
        assert core.lock_reason("waiting", "", dialog, False) == "", dialog
    assert core.lock_reason("waiting", "407호", "idle", False) == "busy_driving"   # 목적지를 쥠
    assert core.lock_reason("moving", "", "idle", False) == "busy_driving"
    assert core.lock_reason("waiting", "", "idle", True) == "busy_driving"          # 움직이는 중
    for dialog in ("waiting", "seeking", "navigating", "paused", "asking_next", "approaching", "returning"):
        assert core.lock_reason("waiting", "", dialog, False) == "busy_driving", dialog


def test_mission_running():
    assert core.mission_running("idle") and core.mission_running("estopped")
    assert not core.mission_running("") and not core.mission_running("  ")


def test_locked_requests_are_refused(tmp_path):
    rig = Rig(with_png(tmp_path), status={"status": "waiting", "current_goal": "", "dialog_state": "waiting"})
    before = files(rig.root)

    for action, args in (("erase", {"rects": [RECT]}), ("undo", None), ("scan_start", {"radius_m": 2.0}), ("scan_check", None)):
        accepted, reason, _ = rig.call(action, args)
        assert (accepted, reason) == (False, "busy_driving"), action

    assert files(rig.root) == before and rig.applied == []
    assert rig.call("get")[2]["lock"] == "busy_driving"
    assert rig.call("erase_count", {"rects": [RECT]})[0] is True    # 세기만 하는 일은 잠기지 않습니다


def test_missing_robot_status_locks(tmp_path):
    rig = Rig(with_png(tmp_path), status=None)
    assert rig.call("erase", {"rects": [RECT]})[:2] == (False, "no_status")
    assert rig.call("get")[2]["lock"] == "no_status"


# ---------------------------------------------------------------------------
# get · 지우기
# ---------------------------------------------------------------------------


def test_get_returns_lock_and_history(tmp_path):
    rig = Rig(with_png(tmp_path))

    accepted, reason, result = rig.call("get")

    assert (accepted, reason) == (True, "")
    assert result == {"lock": "", "can_scan": True, "history": []}
    other = Rig(with_png(tmp_path / "other"), current="another_map")
    assert other.call("get")[2]["can_scan"] is False    # 주행 지도가 아니면 부분 스캔 불가
    assert rig.call("get", map_id="no_such_map")[:2] == (False, "no_map")


def test_erase_count_does_not_touch_files(tmp_path):
    rig = Rig(with_png(tmp_path))
    before = files(rig.root)

    accepted, reason, result = rig.call("erase_count", {"rects": [RECT]})

    assert (accepted, reason) == (True, "")
    assert (result["black"], result["gray"], len(result["rects"])) == (1, 0, 1)
    assert files(rig.root) == before and history(rig) == []


def test_erase_on_current_map_backs_up_writes_and_applies(tmp_path):
    rig = Rig(with_png(tmp_path))
    before = files(rig.root)

    accepted, reason, result = rig.call("erase", {"rects": [RECT]})

    assert (accepted, reason) == (True, "")
    assert result == {"black": 1, "gray": 0, "applied": True, "mission_stale": True}
    assert files(rig.root) != before and rig.applied == [MAP]
    assert store.load_map_image(rig.root, MAP).pixels[3, 5] == store.FREE
    entries = history(rig)
    assert len(entries) == 1
    assert (entries[0]["kind"], entries[0]["black"], entries[0]["rects"]) == ("erase", 1, [RECT])


def test_mission_stale_flag(tmp_path):
    rig = Rig(with_png(tmp_path), status={"status": "waiting", "current_goal": "", "dialog_state": ""})
    assert rig.call("erase", {"rects": [RECT]})[2]["mission_stale"] is False   # 미션이 꺼져 있으면 알림 없음


def test_erase_on_other_map_saves_only(tmp_path):
    rig = Rig(with_png(tmp_path), current="another_map")

    accepted, reason, result = rig.call("erase", {"rects": [RECT]})

    assert (accepted, reason, result["applied"]) == (True, "not_current_map", False)
    assert rig.applied == []                                       # Nav2 를 부르지 않습니다
    assert store.load_map_image(rig.root, MAP).pixels[3, 5] == store.FREE


def test_erase_when_nav2_is_off_saves_only(tmp_path):
    rig = Rig(with_png(tmp_path))
    rig.apply_result = (False, "no_nav2", "Nav2가 실행되면 적용됩니다.")

    accepted, reason, result = rig.call("erase", {"rects": [RECT]})

    assert (accepted, reason, result["applied"]) == (True, "no_nav2", False)
    assert store.load_map_image(rig.root, MAP).pixels[3, 5] == store.FREE
    assert rig.core.pending_apply == ""                            # Nav2 는 켜질 때 파일을 읽습니다


def test_apply_failed_rolls_the_file_back(tmp_path):
    rig = Rig(with_png(tmp_path))
    rig.apply_result = (False, "apply_failed", "Nav2가 지도를 읽지 못했습니다.")
    before = files(rig.root)

    accepted, reason, message, _ = rig.core.handle(MAP, "erase", json.dumps({"rects": [RECT]}))

    assert (accepted, reason) == (False, "apply_failed")
    # 파일을 되돌린 것까지 알립니다(11-19 목업 99). Nav2 의 사유는 노드 기록에만 남깁니다.
    assert message == "Nav2가 지도를 읽지 못해 수정을 취소했습니다."
    assert files(rig.root) == before and history(rig) == []


def test_apply_timeout_keeps_file_and_retries_later(tmp_path):
    rig = Rig(with_png(tmp_path))
    rig.apply_result = (False, "apply_timeout", "Nav2가 응답하지 않았습니다.")

    accepted, reason, result = rig.call("erase", {"rects": [RECT]})

    assert (accepted, reason, result["applied"]) == (True, "apply_timeout", False)
    assert store.load_map_image(rig.root, MAP).pixels[3, 5] == store.FREE
    assert rig.core.pending_apply == MAP

    rig.status["dialog_state"] = "navigating"                      # 잠긴 동안에는 다시 걸지 않습니다
    rig.core.retry_pending()
    assert rig.applied == [MAP]
    rig.status["dialog_state"] = "idle"
    rig.apply_result = (True, "", "적용했습니다.")
    rig.core.retry_pending()
    assert rig.applied == [MAP, MAP] and rig.core.pending_apply == ""


# ---------------------------------------------------------------------------
# 되돌리기
# ---------------------------------------------------------------------------


def test_undo_restores_and_reapplies(tmp_path):
    rig = Rig(with_png(tmp_path))
    before = files(rig.root)
    rig.call("erase", {"rects": [RECT]})

    accepted, reason, result = rig.call("undo")

    assert (accepted, reason) == (True, "")
    assert result == {"kind": "erase", "applied": True, "mission_stale": True}
    assert files(rig.root) == before and history(rig) == []
    assert rig.applied == [MAP, MAP]
    assert rig.call("undo")[:2] == (False, "nothing_to_undo")


def test_undo_that_nav2_refuses_changes_nothing(tmp_path):
    rig = Rig(with_png(tmp_path))
    rig.call("erase", {"rects": [RECT]})
    erased = files(rig.root)
    rig.apply_result = (False, "apply_failed", "Nav2가 지도를 읽지 못했습니다.")

    accepted, reason, _ = rig.call("undo")

    assert (accepted, reason) == (False, "apply_failed")
    assert files(rig.root) == erased and len(history(rig)) == 1    # 지운 상태와 기록이 그대로


# ---------------------------------------------------------------------------
# 요청 모양
# ---------------------------------------------------------------------------


def test_unknown_action_and_bad_json(tmp_path):
    rig = Rig(with_png(tmp_path))
    assert rig.call("explode")[:2] == (False, "bad_action")
    assert rig.core.handle(MAP, "erase", "{not json")[:2] == (False, "bad_args")
    assert rig.core.handle(MAP, "erase", "[1, 2]")[:2] == (False, "bad_args")
    assert rig.call("erase", {})[:2] == (False, "bad_rect")
    assert rig.call("get", map_id="../etc")[:2] == (False, "bad_map_id")


# ---------------------------------------------------------------------------
# 부분 스캔
# ---------------------------------------------------------------------------


def room_rig(tmp_path: Path, **kwargs):
    """6 × 5 m 방 지도 파일을 쓰고, 상자가 새로 놓인 실제 장면의 스캔을 입력으로 겁니다."""
    saved = room(6.0, 5.0)
    pixels = np.where(saved.data[::-1] >= 65, store.OCCUPIED, store.FREE).astype(np.uint8)
    tmp_path.mkdir(parents=True, exist_ok=True)
    (tmp_path / f"{BIG}.pgm").write_bytes(store.encode_pgm(pixels))
    (tmp_path / f"{BIG}.yaml").write_text(
        f"image: {BIG}.pgm\nmode: trinary\nresolution: 0.05\norigin: [0.0, 0.0, 0]\n"
        "negate: 0\noccupied_thresh: 0.65\nfree_thresh: 0.25\n", encoding="utf-8")
    store.write_map_pixels(tmp_path, BIG, pixels)
    rig = Rig(tmp_path, current=kwargs.pop("current", BIG), **kwargs)
    ranges, angle_min, increment = cast(with_box(saved, *BOX), TRUE, LASER, depth=HALF)
    rig.scan_input = core.ScanInput(ranges, angle_min, increment, GUESS, LASER)
    return rig


def run_session(rig: Rig) -> dict:
    """세션을 미리보기까지 돌리고 마지막 상태를 돌려줍니다."""
    assert rig.call("scan_start", {"radius_m": 2.0}, BIG)[:2] == (True, "")
    state = None
    for step in range(1, 106):                      # 0.1 s 간격으로 10.5 s
        rig.time = step * 0.1
        rig.core.feed_scan(rig.scan_input)
        rig.core.feed_motion(0.0, 0.0)
        state = rig.core.tick() or state
    return state


def test_scan_check_measures_without_starting_a_session(tmp_path):
    rig = room_rig(tmp_path)

    accepted, reason, result = rig.call("scan_check", None, BIG)

    assert (accepted, reason) == (True, "")
    assert result["ok"] is True and result["reason"] == "" and result["score"] > 80
    assert 0 < len(result["hits"]) <= 180 and len(result["hits"][0]) == 2
    assert math.hypot(result["x"] - TRUE[0], result["y"] - TRUE[1]) <= 0.012
    assert rig.core.session is None and rig.sensing == []
    rig.scan_input = None
    assert rig.call("scan_check", None, BIG)[:2] == (False, "no_pose")


def test_scan_start_needs_the_current_map_and_a_sane_radius(tmp_path):
    rig = room_rig(tmp_path, current="another_map")
    assert rig.call("scan_start", {"radius_m": 2.0}, BIG)[:2] == (False, "not_current_map")
    assert rig.core.handle(MAP, "scan_check", "")[2] == "현재 지도에서만 부분 스캔할 수 있습니다."
    assert rig.call("scan_check", None, BIG)[:2] == (False, "not_current_map")
    rig = room_rig(tmp_path / "b")
    for radius in (0.5, 3.5, "wide", None):
        assert rig.call("scan_start", {"radius_m": radius}, BIG)[:2] == (False, "bad_args"), radius
    assert rig.core.session is None


def test_session_runs_to_preview_and_apply_writes_the_changes(tmp_path):
    rig = room_rig(tmp_path)
    before = store.load_map_image(rig.root, BIG).pixels

    state = run_session(rig)

    assert state["phase"] == "preview" and state["added"] > 0
    assert rig.sensing == [True, False]             # 미리보기에 들어가면 센서 구독을 풉니다
    accepted, reason, result = rig.call("scan_apply", {"session": "s1"}, BIG)
    assert (accepted, reason) == (True, "")
    assert result["added"] == state["added"] and result["applied"] is True and result["mission_stale"] is True
    assert result["score_after"] > result["score_before"]
    after = store.load_map_image(rig.root, BIG).pixels
    changed = np.argwhere(after != before)
    assert len(changed) == state["added"] and (after[after != before] == store.OCCUPIED).all()
    entry = history(rig, BIG)[0]
    assert (entry["kind"], entry["radius_m"], entry["added"], entry["removed"]) == ("scan", 2.0, state["added"], 0)
    assert rig.core.session is None and rig.applied == [BIG]
    assert rig.call("undo", None, BIG)[0] is True
    assert np.array_equal(store.load_map_image(rig.root, BIG).pixels, before)


def test_second_scan_start_and_edits_during_a_session_are_busy(tmp_path):   # Review Focus 4
    rig = room_rig(tmp_path)
    assert rig.call("scan_start", {"radius_m": 2.0}, BIG)[0] is True

    assert rig.call("scan_start", {"radius_m": 1.0}, BIG)[:2] == (False, "busy_session")
    assert rig.call("erase", {"rects": [{"x_min": 1.0, "y_min": 1.0, "x_max": 1.2, "y_max": 1.2}]}, BIG)[:2] == (False, "busy_session")
    assert rig.call("undo", None, BIG)[:2] == (False, "busy_session")


def test_apply_and_cancel_need_the_right_session(tmp_path):
    rig = room_rig(tmp_path)
    assert rig.call("scan_apply", {"session": "s1"}, BIG)[:2] == (False, "no_session")
    rig.call("scan_start", {"radius_m": 2.0}, BIG)
    assert rig.call("scan_apply", {"session": "s1"}, BIG)[:2] == (False, "no_session")   # 아직 미리보기가 아님
    assert rig.call("scan_cancel", {"session": "other"}, BIG)[:2] == (False, "no_session")

    assert rig.call("scan_cancel", {"session": "s1"}, BIG)[:2] == (True, "")

    final = rig.core.tick()
    assert final["phase"] == "done" and rig.core.session is None
    assert rig.core.tick() is None and rig.sensing == [True, False]
    assert rig.call("scan_start", {"radius_m": 2.0}, BIG)[0] is True        # 끝난 뒤에는 다시 시작할 수 있습니다


def test_failed_session_reports_once_and_clears(tmp_path):
    rig = room_rig(tmp_path)
    rig.call("scan_start", {"radius_m": 2.0}, BIG)
    rig.time = 0.1
    rig.core.feed_scan(rig.scan_input)
    rig.core.feed_motion(0.3, 0.0)                  # 물러나는 동안 로봇이 밀림

    state = rig.core.tick()

    assert (state["phase"], state["reason"]) == ("failed", "moved")
    assert rig.core.session is None and rig.core.tick() is None


def test_lock_during_a_session_fails_it(tmp_path):                          # Review Focus 5
    rig = room_rig(tmp_path)
    rig.call("scan_start", {"radius_m": 2.0}, BIG)
    rig.time = 0.1
    rig.core.feed_scan(rig.scan_input)
    rig.status["current_goal"] = "407호"            # 주행 요청이 들어옴

    assert rig.core.tick()["reason"] == "busy_driving"


def test_discarding_a_preview_changes_nothing(tmp_path):
    rig = room_rig(tmp_path)
    before = files(rig.root) if False else store.load_map_image(rig.root, BIG).pixels
    run_session(rig)

    assert rig.call("scan_discard", {"session": "s1"}, BIG)[:2] == (True, "")

    assert np.array_equal(store.load_map_image(rig.root, BIG).pixels, before)
    assert history(rig, BIG) == [] and rig.applied == []


# ---------------------------------------------------------------------------
# 쉬는 동안 가볍게
# ---------------------------------------------------------------------------


def test_importing_the_core_does_not_load_numpy():
    """노드는 쉬는 동안 numpy·scipy 를 올리지 않습니다 — 요청이 올 때 처음 불러옵니다."""
    code = (
        "import sys; sys.path.insert(0, %r); import map_fix_core; "
        "heavy = [name for name in ('numpy', 'scipy', 'map_fix_store', 'map_fix_scan', 'map_fix_session') "
        "if name in sys.modules]; print(heavy)" % str(HERE)
    )
    out = subprocess.run([sys.executable, "-c", code], capture_output=True, text=True, check=True)
    assert out.stdout.strip() == "[]"
