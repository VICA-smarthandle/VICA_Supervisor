"""/robot_status 의 미션 활동 네 칸(2026-10-29) — 원격 주행 대기·접근 중 취소의 바탕."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from vica_status_app_node import MISSION_ACTIVITY_STALE_SEC, mission_activity_fields  # noqa: E402

SNAP = {"dialog_state": "waiting", "wait_place": "입구 왼쪽", "wait_left_sec": 150,
        "last_destination": "남자 화장실"}


def test_fresh_robot_state_is_passed_through():
    assert mission_activity_fields(SNAP, 10.0, 11.0) == SNAP


def test_never_received_is_empty():
    out = mission_activity_fields(None, None, 5.0)
    assert out == {"dialog_state": "", "wait_place": "", "wait_left_sec": -1, "last_destination": ""}


def test_stale_robot_state_is_empty_so_no_old_cancel_button_stays():
    out = mission_activity_fields(SNAP, 10.0, 10.0 + MISSION_ACTIVITY_STALE_SEC + 0.1)
    assert out["dialog_state"] == "" and out["wait_left_sec"] == -1


def test_values_are_normalized_types():
    out = mission_activity_fields({"dialog_state": "approaching", "wait_place": "",
                                   "wait_left_sec": -1, "last_destination": ""}, 1.0, 1.5)
    assert out["dialog_state"] == "approaching" and isinstance(out["wait_left_sec"], int)
