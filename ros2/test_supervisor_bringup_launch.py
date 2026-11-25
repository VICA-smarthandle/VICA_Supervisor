"""supervisor_bringup.launch.py 가 상태 노드에 넘기는 map_yaml 인자 시험입니다.

    source /opt/ros/humble/setup.bash
    python3 -m pytest ros2/test_supervisor_bringup_launch.py

launch 설명서에는 "map_yaml 을 비우면 Nav2 map_server 에서 자동 감지합니다"라고 적혀
있는데, 비운 채 띄우면 `-p map_yaml:=` 가 넘어가 rcl 이 해석하지 못하고
vica_status_app_node 가 죽었습니다(2026-11-14 실기, launch 는 살아 있어 눈에 안 띔).

launch 를 실제로 띄우지 않습니다. 설명만 만들어 상태 노드의 명령줄을 풀어 보고,
그 인자를 rcl 이 받아들이는지는 노드 없이 rclpy.init 만 불러 확인합니다.
"""
from __future__ import annotations

import importlib.util
import subprocess
import sys
from pathlib import Path

import pytest

pytest.importorskip("launch")
pytest.importorskip("rclpy")
yaml = pytest.importorskip("yaml")

from launch import LaunchContext  # noqa: E402
from launch.actions import ExecuteProcess  # noqa: E402
from launch.utilities import perform_substitutions  # noqa: E402

LAUNCH_FILE = Path(__file__).resolve().parent / "supervisor_bringup.launch.py"


def _status_node_argv(map_yaml: str, tmp_path: Path) -> list[str]:
    """map_yaml 값을 주고 launch 가 상태 노드에 넘길 명령줄을 풉니다."""
    spec = importlib.util.spec_from_file_location("supervisor_bringup_launch", LAUNCH_FILE)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    # rosbridge·destination 패키지가 설치돼 있지 않아도 설명은 만들 수 있게 합니다.
    module.get_package_share_directory = lambda _name: str(tmp_path)

    context = LaunchContext()
    context.launch_configurations["map_yaml"] = map_yaml
    for entity in module.generate_launch_description().entities:
        if not isinstance(entity, ExecuteProcess):
            continue
        argv = [perform_substitutions(context, part) for part in entity.cmd]
        if str(module.STATUS_NODE) in argv:
            return argv
    raise AssertionError("상태 노드를 띄우는 ExecuteProcess 를 찾지 못했습니다")


def _ros_args(argv: list[str]) -> list[str]:
    return argv[argv.index("--ros-args"):]


def _rcl_accepts(ros_args: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, "-c", "import sys, rclpy; rclpy.init(args=sys.argv[1:]); rclpy.shutdown()",
         *ros_args],
        capture_output=True, text=True,
    )


def _value(argv: list[str]) -> object:
    """`-p map_yaml:=<값>` 의 값을 rcl 처럼 YAML 로 읽습니다."""
    rule = argv[argv.index("-p") + 1]
    name, _, raw = rule.partition(":=")
    assert name == "map_yaml"
    return yaml.safe_load(raw)


def test_empty_map_yaml_does_not_crash_the_status_node(tmp_path):
    proc = _rcl_accepts(_ros_args(_status_node_argv("", tmp_path)))
    assert proc.returncode == 0, proc.stderr[-300:]


def test_empty_map_yaml_reaches_the_node_as_an_empty_string(tmp_path):
    # 빈 문자열이어야 상태 노드가 map_server 자동 감지로 들어갑니다.
    assert _value(_status_node_argv("", tmp_path)) == ""


def test_arm_relay_node_is_launched_with_respawn(tmp_path):
    # 로봇팔 시연 중계(2026-11-25). 앱 기능 하나가 죽어도 유닛째 다시 켤 일이 없게 다시 뜹니다.
    spec = importlib.util.spec_from_file_location("supervisor_bringup_launch", LAUNCH_FILE)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.get_package_share_directory = lambda _name: str(tmp_path)

    context = LaunchContext()
    context.launch_configurations["map_yaml"] = ""
    relays = [
        entity
        for entity in module.generate_launch_description().entities
        if isinstance(entity, ExecuteProcess)
        and str(module.ARM_RELAY_NODE) in [perform_substitutions(context, p) for p in entity.cmd]
    ]
    assert len(relays) == 1
    assert relays[0]._ExecuteLocal__respawn is True  # Humble launch 는 공개 속성이 없습니다
    assert module.ARM_RELAY_NODE.is_file()


def test_map_path_reaches_the_node_unchanged(tmp_path):
    path = "/home/robot/vica_ros2_ws/maps/vica_map_0630.yaml"
    argv = _status_node_argv(path, tmp_path)
    assert _value(argv) == path
    assert _rcl_accepts(_ros_args(argv)).returncode == 0
