"""map_fix_node 시험입니다.

    source /opt/ros/humble/setup.bash
    python3 -m pytest -q VICA_Supervisor/ros2/test_map_fix_node.py

노드를 띄우지 않습니다(rclpy.init 을 부르지 않아 로봇의 ROS 그래프에 붙지 않습니다). 요청을
어떻게 처리하는지는 test_map_fix_core.py 가 봅니다 — 여기서는 ROS 와 맞닿는 작은 변환들과
"쉬는 동안 가볍다"는 약속만 봅니다.
"""

from __future__ import annotations

import importlib.util
import json
import math
import subprocess
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

pytest.importorskip("rclpy")  # 노드 모듈이 rclpy 를 import 한다

import map_fix_node as node  # noqa: E402


def test_load_map_outcome_table():
    assert node.load_map_outcome(done=True, error=None, result_code=0, timeout=10.0)[:2] == (True, "")

    applied, reason, message = node.load_map_outcome(done=False, error=None, result_code=None, timeout=10.0)
    assert (applied, reason) == (False, "apply_timeout") and "10초" in message

    failed = node.load_map_outcome(done=True, error=RuntimeError("boom"), result_code=None, timeout=10.0)
    assert failed[:2] == (False, "apply_failed") and "boom" in failed[2]
    for code in (1, 2, 3, 9, None):
        assert node.load_map_outcome(done=True, error=None, result_code=code, timeout=10.0)[:2] == (False, "apply_failed")


def test_fresh_status_is_kept_and_stale_status_is_dropped():
    status = {"status": "waiting", "dialog_state": "idle"}
    assert node.fresh_status(status, age_sec=0.4) == status
    assert node.fresh_status(status, age_sec=node.STATUS_STALE_SEC + 0.1) is None   # 상태 노드가 멈춘 것
    assert node.fresh_status(None, age_sec=0.0) is None


def test_fill_response_writes_json():
    response = SimpleNamespace()
    node.fill_response(response, (True, "no_nav2", "Nav2가 실행되면 적용됩니다.", {"applied": False, "black": 3}))
    assert (response.accepted, response.reason, response.message) == (True, "no_nav2", "Nav2가 실행되면 적용됩니다.")
    assert json.loads(response.result_json) == {"applied": False, "black": 3}


def test_yaw_of_quaternion():
    half = 0.25
    assert math.isclose(node.yaw_of(SimpleNamespace(x=0.0, y=0.0, z=math.sin(half), w=math.cos(half))), 0.5)


def test_pose_of_transform():
    transform = SimpleNamespace(
        translation=SimpleNamespace(x=1.5, y=-2.0, z=0.0),
        rotation=SimpleNamespace(x=0.0, y=0.0, z=math.sin(0.1), w=math.cos(0.1)),
    )
    x, y, yaw = node.pose_of(transform)
    assert (x, y) == (1.5, -2.0) and math.isclose(yaw, 0.2)


def test_importing_the_node_does_not_load_numpy():
    """쉬는 동안에는 numpy·scipy 와 스캔 계산 모듈이 올라와 있지 않습니다."""
    code = (
        "import sys; sys.path.insert(0, %r); import map_fix_node; "
        "print([name for name in ('numpy', 'scipy', 'tf2_ros', 'map_fix_store', 'map_fix_scan', "
        "'map_fix_session') if name in sys.modules])" % str(HERE)
    )
    out = subprocess.run([sys.executable, "-c", code], capture_output=True, text=True, check=True)
    assert out.stdout.strip() == "[]"


def test_launch_starts_the_map_fix_node(tmp_path):
    pytest.importorskip("launch")
    from launch import LaunchContext
    from launch.actions import ExecuteProcess
    from launch.utilities import perform_substitutions

    spec = importlib.util.spec_from_file_location(
        "supervisor_bringup_launch", HERE / "supervisor_bringup.launch.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.get_package_share_directory = lambda _name: str(tmp_path)

    context = LaunchContext()
    context.launch_configurations["map_yaml"] = ""
    commands = [
        [perform_substitutions(context, part) for part in entity.cmd]
        for entity in module.generate_launch_description().entities
        if isinstance(entity, ExecuteProcess)
    ]

    assert module.MAP_FIX_NODE == HERE / "map_fix_node.py"
    assert sum(str(module.MAP_FIX_NODE) in argv for argv in commands) == 1
