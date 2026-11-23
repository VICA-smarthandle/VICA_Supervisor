"""상태 노드가 map_server 에 지도 경로를 다시 묻는 규칙(2026-11-17 실기 수리)."""
import os
import sys

import pytest

sys.path.insert(0, os.path.dirname(__file__))
pytest.importorskip("rclpy")
from vica_status_app_node import MAP_PARAM_TIMEOUT_SEC, map_poll_action  # noqa: E402


def test_asks_when_map_server_is_up():
    assert map_poll_action(False, 0.0, 10.0, ready=True) == "ask"


def test_skips_without_map_server():
    assert map_poll_action(False, 0.0, 10.0, ready=False) == "skip"


def test_waits_for_a_fresh_answer():
    assert map_poll_action(True, 10.0, 10.5, ready=True) == "wait"


def test_drops_an_answer_that_never_came():
    assert map_poll_action(True, 10.0, 10.0 + MAP_PARAM_TIMEOUT_SEC, ready=True) == "drop"
    assert map_poll_action(True, 10.0, 99.0, ready=False) == "drop"
