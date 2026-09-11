#!/usr/bin/env python3
"""VICA Supervisor 앱 연동 프로세스를 한 번에 실행하는 독립형 launch입니다."""

import sys
from pathlib import Path

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription, LaunchService
from launch.actions import DeclareLaunchArgument, ExecuteProcess, IncludeLaunchDescription
from launch.launch_description_sources import (
    AnyLaunchDescriptionSource,
    PythonLaunchDescriptionSource,
)
from launch.substitutions import LaunchConfiguration


SUPERVISOR_ROOT = Path(__file__).resolve().parent
WORKSPACE_ROOT = SUPERVISOR_ROOT.parent.parent
MAP_LIST_NODE = SUPERVISOR_ROOT / "map_list_node.py"
STATUS_NODE = SUPERVISOR_ROOT / "vica_status_app_node.py"


def generate_launch_description() -> LaunchDescription:
    """rosbridge, 지도 HTTP 서버, 목적지·지도·상태 노드를 실행합니다."""

    rosbridge_share = Path(get_package_share_directory("rosbridge_server"))
    destination_share = Path(
        get_package_share_directory("vica_destination_manager")
    )

    rosbridge_launch = rosbridge_share / "launch" / "rosbridge_websocket_launch.xml"
    destination_launch = destination_share / "launch" / "destination_manager.launch.py"

    map_yaml = LaunchConfiguration("map_yaml")

    return LaunchDescription(
        [
            DeclareLaunchArgument(
                "map_yaml",
                default_value="",
                description=(
                    "상태 노드가 사용할 지도 YAML. 비우면 Nav2 map_server에서 자동 감지합니다."
                ),
            ),
            IncludeLaunchDescription(
                AnyLaunchDescriptionSource(str(rosbridge_launch)),
                launch_arguments={
                    "address": "0.0.0.0",
                    "port": "9090",
                }.items(),
            ),
            ExecuteProcess(
                cmd=[
                    sys.executable,
                    "-m",
                    "http.server",
                    "8000",
                    "--bind",
                    "0.0.0.0",
                ],
                cwd=str(WORKSPACE_ROOT / "vica_ros2_ws"),
                output="screen",
            ),
            IncludeLaunchDescription(
                PythonLaunchDescriptionSource(str(destination_launch)),
            ),
            ExecuteProcess(
                cmd=[sys.executable, str(MAP_LIST_NODE)],
                output="screen",
            ),
            ExecuteProcess(
                cmd=[
                    sys.executable,
                    str(STATUS_NODE),
                    "--ros-args",
                    "-p",
                    ["map_yaml:=", map_yaml],
                ],
                output="screen",
            ),
        ]
    )


def main() -> int:
    """ROS 패키지 설치 없이 이 파일을 직접 실행할 수 있게 합니다."""

    launch_service = LaunchService(argv=sys.argv[1:])
    launch_service.include_launch_description(generate_launch_description())
    return launch_service.run()


if __name__ == "__main__":
    raise SystemExit(main())
