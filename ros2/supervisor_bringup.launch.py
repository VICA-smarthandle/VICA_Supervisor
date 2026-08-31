#!/usr/bin/env python3
"""VICA Supervisor 앱 연동 프로세스를 한 번에 실행하는 독립형 launch입니다.

이 파일은 ROS 패키지로 설치하지 않고 Supervisor 저장소에서 직접 실행합니다.
안전·모터·localization·Nav2는 각각의 기존 launch에서 별도로 실행합니다.
"""

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
KEEPOUT_NODE = SUPERVISOR_ROOT / "keepout_map_node.py"
MAP_HTTP_SERVER = SUPERVISOR_ROOT / "map_http_server.py"


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
                    # [2026-08-21] 서비스 호출을 rosbridge 본 흐름에서 떼어낸다.
                    #
                    # rosbridge_websocket_launch.xml 의 기본값은
                    #   call_services_in_new_thread  false
                    #   default_call_service_timeout 0.0   (시한 없음)
                    # 이라, 응답하지 않는 서비스 호출 하나가 rosbridge 전체를 막았다.
                    # 그러면 앱을 재연결해도 비상정지를 눌러도 아무것도 통하지 않고
                    # 젯슨에서 rosbridge 노드를 껐다 켜야만 풀렸다.
                    #
                    # 실제로 mission_manager 의 일시정지 서비스가 Nav2 취소 응답을
                    # 기다리다 멈추면서 이 상태가 재현됐다. 그 원인은 따로 고쳤지만
                    # (mission_manager_node._cancel_nav), 다음에 어떤 서비스가 또
                    # 멈추더라도 rosbridge 까지 같이 서지 않게 하는 방벽이 필요하다.
                    #
                    # 5.0 초는 앱 쪽 기본 timeout(ros_bridge_client.callService 5초)과
                    # 같은 값이다. 앱이 이미 포기한 호출을 서버가 붙들고 있을 이유가 없다.
                    "call_services_in_new_thread": "true",
                    "default_call_service_timeout": "5.0",
                }.items(),
            ),
            # 지도 이미지 서버. python -m http.server 를 쓰다가 전용 스크립트로
            # 바꿨습니다(2026-08-31). 이유는 Access-Control-Allow-Origin 헤더
            # 한 줄입니다 — 그것이 없어서 브라우저로 띄운 앱에서 지도 그림만
            # 안 보였습니다. 자세한 사정은 map_http_server.py 맨 위에 있습니다.
            ExecuteProcess(
                cmd=[
                    sys.executable,
                    str(MAP_HTTP_SERVER),
                    "--port",
                    "8000",
                    "--bind",
                    "0.0.0.0",
                    "--directory",
                    str(WORKSPACE_ROOT / "vica_ros2_ws"),
                ],
                output="screen",
            ),
            IncludeLaunchDescription(
                PythonLaunchDescriptionSource(str(destination_launch)),
            ),
            ExecuteProcess(
                cmd=[sys.executable, str(MAP_LIST_NODE)],
                output="screen",
            ),
            # 금지구역 저장·적용. map_list_node 옆에 두는 이유는 역할이 같기
            # 때문입니다 — 앱과 maps/ 폴더 사이의 다리입니다. Nav2 쪽 배선
            # (마스크 서버 두 대)은 vica_nav2 의 launch 가 담당합니다.
            ExecuteProcess(
                cmd=[sys.executable, str(KEEPOUT_NODE)],
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
