"""앱 '현재 위치' 칸(2026-11-17 수리): 초기 위치 전에 '이동 중'으로 보이던 것."""
import os
import sys

import pytest

sys.path.insert(0, os.path.dirname(__file__))
pytest.importorskip("rclpy")
from vica_status_app_node import location_label  # noqa: E402


def test_unknown_position_is_not_called_moving():
    assert location_label(False, False, "", "") == "위치 모름"
    assert location_label(False, True, "", "407호 앞") == "위치 모름"


def test_near_a_place_shows_its_name():
    assert location_label(True, False, "410호", "410호 앞") == "410호"
    assert location_label(True, True, "410호", "") == "410호"


def test_moving_between_places():
    assert location_label(True, True, "", "407호와 화장실 사이") == "이동 중"


def test_standing_still_away_from_places_uses_mission_words():
    assert location_label(True, False, "", "407호와 화장실 사이") == "407호와 화장실 사이"
    assert location_label(True, False, "", "") == "장소 밖"
