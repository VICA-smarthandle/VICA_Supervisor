#!/usr/bin/env python3
"""금지구역 저장이 지금 주행 지도에만 바로 물리는지 고정한다 (2026-10-13).

2026-10-13 13:23 다른 지도(vica_map_0910)의 금지구역을 웹에서 저장하자 그 지도 마스크가
map_1002_150946 으로 서 있던 로봇의 Nav2 에 걸려 지금 지도의 금지구역 4개가 빠졌다.
앱은 지도와 상관없이 늘 apply_now=true 를 보낸다 — 거르는 일은 이 노드 몫이다.

ROS 를 띄우지 않는다. handle_save 를 가짜 self 로 부르고 Nav2 적용(_apply)은 기록만 한다.
"""
from __future__ import annotations

import sys
from pathlib import Path
from types import SimpleNamespace

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

pytest.importorskip("rclpy")  # 노드 모듈이 rclpy 를 import 한다
from keepout_map_node import KeepoutMapNode  # noqa: E402
from test_keepout_mask import NOW, make_map  # noqa: E402

ZONES = '[{"x_min": 0.0, "y_min": 0.0, "x_max": 0.2, "y_max": 0.2}]'


class _Logger:
    def info(self, _msg: str) -> None:
        pass

    def warn(self, _msg: str) -> None:
        pass


def _node(root: Path, *, current: str | None, driving: bool = False) -> SimpleNamespace:
    if current is not None:
        (root / "CURRENT_MAP").write_text(current + "\n", encoding="utf-8")
    node = SimpleNamespace(
        maps_root=root,
        _hold_apply=driving,
        _pending_apply="",
        applied_maps=[],
        get_logger=_Logger,
        _now=lambda: NOW,
    )
    node._current_map_id = lambda: KeepoutMapNode._current_map_id(node)

    def apply(map_id: str):
        node.applied_maps.append(map_id)
        return (True, "", "적용했습니다.")

    node._apply = apply
    return node


def _save(node: SimpleNamespace, map_id: str, apply_now: bool = True) -> SimpleNamespace:
    request = SimpleNamespace(map_id=map_id, zones_json=ZONES, apply_now=apply_now)
    return KeepoutMapNode.handle_save(node, request, SimpleNamespace())


def test_다른_지도는_저장만_하고_물리지_않는다(tmp_path: Path) -> None:
    root = make_map(make_map(tmp_path, "map_now"), "map_other")
    node = _node(root, current="map_now")

    response = _save(node, "map_other")

    assert response.accepted is True
    assert response.applied is False
    assert response.reason == "not_current_map"
    assert "다음에 이 지도로 주행할 때" in response.message
    assert node.applied_maps == []
    assert (root / "map_other_keepout.pgm").is_file(), "저장은 해야 합니다"


def test_주행_중_다른_지도는_미뤄_두지도_않는다(tmp_path: Path) -> None:
    # 미뤄 두면 주행이 끝나는 순간 다른 지도 마스크가 물린다 — 같은 사고가 늦게 난다.
    root = make_map(make_map(tmp_path, "map_now"), "map_other")
    node = _node(root, current="map_now", driving=True)

    response = _save(node, "map_other")

    assert response.reason == "not_current_map"
    assert node._pending_apply == ""
    assert node.applied_maps == []


def test_지금_지도는_예전처럼_바로_물린다(tmp_path: Path) -> None:
    root = make_map(tmp_path, "map_now")
    node = _node(root, current="map_now")

    response = _save(node, "map_now")

    assert response.applied is True
    assert response.reason == ""
    assert node.applied_maps == ["map_now"]


def test_지금_지도라도_주행_중이면_끝난_뒤로_미룬다(tmp_path: Path) -> None:
    root = make_map(tmp_path, "map_now")
    node = _node(root, current="map_now", driving=True)

    response = _save(node, "map_now")

    assert response.reason == "busy_driving"
    assert node._pending_apply == "map_now"
    assert node.applied_maps == []


def test_CURRENT_MAP_이_없으면_어느_지도도_바로_물리지_않는다(tmp_path: Path) -> None:
    root = make_map(tmp_path, "map_now")
    node = _node(root, current=None)

    response = _save(node, "map_now")

    assert response.reason == "not_current_map"
    assert node.applied_maps == []


def test_apply_now_가_없으면_지도와_상관없이_저장만(tmp_path: Path) -> None:
    root = make_map(make_map(tmp_path, "map_now"), "map_other")
    node = _node(root, current="map_now")

    response = _save(node, "map_other", apply_now=False)

    assert response.accepted is True
    assert response.reason == ""
    assert node.applied_maps == []


def _finish_drive(node: SimpleNamespace) -> list:
    """주행이 끝났다는 /robot_status 를 한 번 넣고, 노드가 앱에 알린 상태를 돌려준다."""
    sent = []
    node._publish_state = lambda *args: sent.append(args)
    msg = SimpleNamespace(data='{"status": "idle", "current_goal": ""}')
    KeepoutMapNode._on_robot_status(node, msg)
    return sent


def test_주행_끝난_뒤_미뤄_둔_지금_지도는_물린다(tmp_path: Path) -> None:
    root = make_map(tmp_path, "map_now")
    node = _node(root, current="map_now", driving=True)
    _save(node, "map_now")

    sent = _finish_drive(node)

    assert node.applied_maps == ["map_now"]
    assert sent and sent[0][:2] == ("map_now", True)


def test_미뤄_둔_사이_주행_지도가_바뀌면_옛_지도를_물리지_않는다(tmp_path: Path) -> None:
    # 미션이 목적지를 쥔 채 죽어 미루기가 풀리지 않은 사이 CURRENT_MAP 을 바꿔 다시 띄운 경우(10-13 검토).
    root = make_map(make_map(tmp_path, "map_a"), "map_b")
    node = _node(root, current="map_a", driving=True)
    _save(node, "map_a")
    (root / "CURRENT_MAP").write_text("map_b\n", encoding="utf-8")

    sent = _finish_drive(node)

    assert node.applied_maps == []
    assert sent == [("map_a", False, "not_current_map",
                     "지금 주행 지도가 아니라 다음에 이 지도로 주행할 때 적용됩니다.")]
    assert node._pending_apply == ""
