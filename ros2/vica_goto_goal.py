#!/usr/bin/env python3
"""목적지 이름을 UUID로 해석해 Mission Manager에 요청하는 CLI 도구.

지도별 destinations.yaml에서 이름을 찾아 UUID로 변환한다.
지도·접근 권한·Safety·Nav2 검증과 Goal 생성은 Mission Manager가 맡는다.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import time
from pathlib import Path
from uuid import UUID, uuid4

import rclpy
import yaml
from rclpy.executors import ExternalShutdownException
from rclpy.node import Node
from std_msgs.msg import String
from vica_interfaces.srv import RequestDestination

_MAP_ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$")
_TERMINAL_GOAL_EVENTS = {
    "goal_succeeded",
    "goal_failed",
    "goal_rejected",
    "goal_canceled",
    # 일시정지도 이 CLI 에게는 끝이다. 재개는 앱이나 음성으로 따로 요청하는
    # 별도 행위이므로, 여기서 기다리면 응답 없이 멈춰 있게 된다.
    "goal_paused",
}


def resolve_destination_id(
    storage_root: str | Path,
    map_id: str,
    destination_name: str,
) -> str:
    """지도별 YAML에서 정확히 일치하는 이름의 UUID를 반환한다."""
    if not _MAP_ID_PATTERN.fullmatch(map_id):
        raise ValueError("map_id 형식이 올바르지 않습니다.")

    name = destination_name.strip()
    if not name:
        raise ValueError("목적지 이름이 비어 있습니다.")

    path = Path(storage_root).expanduser() / map_id / "destinations.yaml"
    if not path.is_file():
        raise ValueError(f"목적지 파일이 없습니다: {path}")

    try:
        document = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    except (OSError, yaml.YAMLError) as exc:
        raise ValueError(f"목적지 파일을 읽을 수 없습니다: {exc}") from exc

    if not isinstance(document, dict):
        raise ValueError(f"잘못된 목적지 YAML 구조입니다: {path}")
    if document.get("map_id") != map_id:
        raise ValueError(
            f"목적지 파일의 map_id가 다릅니다: "
            f"requested={map_id}, stored={document.get('map_id')}"
        )
    destinations = document.get("destinations")
    if not isinstance(destinations, list):
        raise ValueError(
            f"destinations 목록이 없는 잘못된 파일입니다: {path}"
        )

    matches = [
        item
        for item in destinations
        if isinstance(item, dict) and str(item.get("name", "")).strip() == name
    ]
    if not matches:
        raise ValueError(
            f"'{name}' 목적지를 {map_id} 지도에서 찾을 수 없습니다."
        )
    if len(matches) > 1:
        raise ValueError(
            f"'{name}' 목적지가 {map_id} 지도에 여러 개 있습니다."
        )

    destination_id = str(matches[0].get("id", "")).strip().lower()
    try:
        parsed = UUID(destination_id)
    except ValueError as exc:
        raise ValueError(f"'{name}' 목적지 ID가 UUID가 아닙니다.") from exc
    if parsed.version != 4 or str(parsed) != destination_id:
        raise ValueError(f"'{name}' 목적지 ID가 canonical UUID v4가 아닙니다.")
    return destination_id


class VicaGotoGoal(Node):
    """Mission Manager 서비스의 테스트·유지보수용 client."""

    def __init__(self) -> None:
        super().__init__("vica_goto_goal")
        self.expected_map_id = ""
        self.expected_destination_id = ""
        self.terminal_goal_event: dict | None = None
        self.client = self.create_client(
            RequestDestination,
            "/vica/mission/request_destination",
        )
        self.create_subscription(
            String,
            "/vica_goal_event",
            self.goal_event_callback,
            10,
        )

    def goal_event_callback(self, msg: String) -> None:
        """Store a terminal event only when it belongs to this CLI request."""
        try:
            payload = json.loads(msg.data)
        except (json.JSONDecodeError, TypeError):
            self.get_logger().warn(
                "잘못된 /vica_goal_event JSON을 무시합니다."
            )
            return
        if not isinstance(payload, dict):
            return
        if payload.get("map_id") != self.expected_map_id:
            return
        destination_id = str(
            payload.get("destination_id") or payload.get("location_id") or ""
        )
        if destination_id != self.expected_destination_id:
            return
        if payload.get("event") in _TERMINAL_GOAL_EVENTS:
            self.terminal_goal_event = payload

    def request_destination(
        self,
        map_id: str,
        destination_id: str,
        timeout_sec: float,
    ) -> tuple[bool, str]:
        self.expected_map_id = map_id
        self.expected_destination_id = destination_id
        self.terminal_goal_event = None
        if not self.client.wait_for_service(timeout_sec=timeout_sec):
            return False, "Mission Manager 목적지 요청 service가 없습니다."

        request = RequestDestination.Request()
        request.request_id = str(uuid4())
        request.map_id = map_id
        request.destination_id = destination_id
        future = self.client.call_async(request)
        rclpy.spin_until_future_complete(self, future, timeout_sec=timeout_sec)
        if not future.done():
            return False, "Mission Manager 응답 시간이 초과되었습니다."
        try:
            response = future.result()
        except Exception as exc:
            return False, f"Mission Manager 서비스 호출 실패: {exc}"
        if response is None:
            return False, "Mission Manager 응답이 없습니다."
        return bool(response.accepted), str(response.message)

    def wait_for_navigation_result(
        self,
        timeout_sec: float,
    ) -> tuple[str, str]:
        """Wait for this destination's terminal Mission event."""
        deadline = (
            None if timeout_sec <= 0.0 else time.monotonic() + timeout_sec
        )
        while rclpy.ok() and self.terminal_goal_event is None:
            if deadline is None:
                spin_timeout = 0.2
            else:
                remaining = deadline - time.monotonic()
                if remaining <= 0.0:
                    return (
                        "timeout",
                        "목적지 주행 결과 대기시간이 "
                        "초과되었습니다.",
                    )
                spin_timeout = min(remaining, 0.2)
            rclpy.spin_once(self, timeout_sec=spin_timeout)

        if self.terminal_goal_event is None:
            return (
                "shutdown",
                "ROS 종료로 목적지 주행 결과 확인을 중단했습니다.",
            )
        event = str(self.terminal_goal_event.get("event", ""))
        reason = str(self.terminal_goal_event.get("reason", "") or "")
        return event, reason


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Mission Manager에 저장 목적지 주행을 요청합니다.",
    )
    parser.add_argument("map_id", help="현재 Nav2 지도 ID")
    parser.add_argument(
        "destination_name",
        nargs="+",
        help="저장된 목적지 이름",
    )
    parser.add_argument(
        "--storage-root",
        default=str(Path.home() / "vica_data" / "destinations"),
        help="지도별 destinations.yaml 저장 루트",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=5.0,
        help="서비스 제한시간(초)",
    )
    parser.add_argument(
        "--navigation-timeout",
        type=float,
        default=600.0,
        help="주행 완료 대기시간(초), 0 이하는 무제한",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        destination_name = " ".join(args.destination_name)
        destination_id = resolve_destination_id(
            args.storage_root,
            args.map_id,
            destination_name,
        )
    except ValueError as exc:
        print(f"목적지 검색 실패: {exc}", file=sys.stderr)
        return 2

    rclpy.init()
    node = VicaGotoGoal()
    try:
        accepted, message = node.request_destination(
            args.map_id,
            destination_id,
            args.timeout,
        )
        if accepted:
            node.get_logger().info(message)
            node.get_logger().info(
                f"목적지까지 주행 결과를 기다립니다: {destination_name}"
            )
            event, reason = node.wait_for_navigation_result(
                args.navigation_timeout
            )
            if event == "goal_succeeded":
                node.get_logger().info(
                    f"목적지 도착 완료: {destination_name}"
                )
                return 0
            if event == "goal_canceled":
                detail = f" reason={reason}" if reason else ""
                node.get_logger().warn(
                    f"목적지 주행 취소: {destination_name}{detail}"
                )
                return 1
            if event == "goal_paused":
                node.get_logger().warn(
                    f"목적지 주행 일시정지: {destination_name} "
                    f"(다시 출발은 앱 또는 음성으로 요청하세요)"
                )
                return 1
            if event == "goal_rejected":
                detail = f" reason={reason}" if reason else ""
                node.get_logger().error(
                    f"Nav2 Goal 거부: {destination_name}{detail}"
                )
                return 1
            if event == "goal_failed":
                detail = f" reason={reason}" if reason else ""
                node.get_logger().error(
                    f"목적지 주행 실패: {destination_name}{detail}"
                )
                return 1
            node.get_logger().error(reason)
            return 1
        node.get_logger().error(message)
        return 1
    except (KeyboardInterrupt, ExternalShutdownException):
        return 130
    finally:
        node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == "__main__":
    raise SystemExit(main())
