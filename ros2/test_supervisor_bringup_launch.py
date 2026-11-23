"""supervisor_bringup.launch.py 가 상태 노드에 넘기는 map_yaml 인자 시험입니다."""
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
    assert _value(_status_node_argv("", tmp_path)) == ""


def test_map_path_reaches_the_node_unchanged(tmp_path):
    path = "/home/robot/vica_ros2_ws/maps/vica_map_0630.yaml"
    argv = _status_node_argv(path, tmp_path)
    assert _value(argv) == path
    assert _rcl_accepts(_ros_args(argv)).returncode == 0
