#!/usr/bin/env python3
"""앱이 그린 금지구역을 파일로 만들고 Nav2에 물리는 노드입니다."""

import json
from datetime import datetime, timedelta, timezone
from pathlib import Path
from threading import Event

import rclpy
from rclpy.callback_groups import ReentrantCallbackGroup
from rclpy.executors import ExternalShutdownException, MultiThreadedExecutor
from rclpy.node import Node
from std_msgs.msg import String

import keepout_mask as km

KST = timezone(timedelta(hours=9))


class KeepoutMapNode(Node):
    """금지구역 저장·조회 서비스와 Nav2 반영을 담당합니다."""

    def __init__(self) -> None:
        super().__init__("vica_keepout_map")

        workspace_root = Path(__file__).resolve().parents[2]
        default_maps_root = workspace_root / "vica_ros2_ws" / "maps"
        self.declare_parameter("maps_root", str(default_maps_root))
        self.maps_root = Path(str(self.get_parameter("maps_root").value)).expanduser()

        self.declare_parameter(
            "mask_load_service", "/keepout_filter_mask_server/load_map"
        )
        self.declare_parameter("apply_timeout_sec", 3.0)
        self.declare_parameter("robot_status_topic", "/robot_status")
        self.declare_parameter("create_empty_mask_on_get", True)

        self._callbacks = ReentrantCallbackGroup()
        self._hold_apply = False
        self._pending_apply: str = ""

        self.state_publisher = self.create_publisher(String, "/vica/keepout/state", 10)
        self.create_subscription(
            String,
            str(self.get_parameter("robot_status_topic").value),
            self._on_robot_status,
            10,
            callback_group=self._callbacks,
        )

        self._load_map_client = None
        self._load_map_type = None
        self._setup_load_map_client()
        self._setup_services()

        self.get_logger().info(
            f"vica_keepout_map 시작: maps_root={self.maps_root}"
        )

    def _setup_services(self) -> None:
        """앱이 부르는 두 서비스를 엽니다."""
        try:
            from vica_interfaces.srv import GetKeepout, SaveKeepout
        except ImportError as error:
            self.get_logger().error(
                f"vica_interfaces/SaveKeepout import 실패: {error}. "
                "금지구역 서비스를 열지 않습니다. colcon build 가 필요합니다."
            )
            return
        self.create_service(
            SaveKeepout,
            "/vica/keepout/save",
            self.handle_save,
            callback_group=self._callbacks,
        )
        self.create_service(
            GetKeepout,
            "/vica/keepout/get",
            self.handle_get,
            callback_group=self._callbacks,
        )
        self.get_logger().info("/vica/keepout/save · /vica/keepout/get 준비 완료")

    def _setup_load_map_client(self) -> None:
        """Nav2 마스크 서버의 load_map 클라이언트를 만듭니다."""
        try:
            from nav2_msgs.srv import LoadMap
        except ImportError as error:
            self.get_logger().warn(
                f"nav2_msgs/LoadMap import 실패: {error}. "
                "저장은 되지만 Nav2 반영은 하지 못합니다."
            )
            return
        self._load_map_type = LoadMap
        self._load_map_client = self.create_client(
            LoadMap,
            str(self.get_parameter("mask_load_service").value),
            callback_group=self._callbacks,
        )

    def _on_robot_status(self, msg: String) -> None:
        """반영을 미뤄야 하는 상태인지 봅니다. 판정 기준은 keepout_mask.hold_apply."""
        try:
            payload = json.loads(msg.data)
        except (json.JSONDecodeError, TypeError):
            return
        hold = km.hold_apply(
            str(payload.get("status", "")),
            str(payload.get("current_goal", "")),
        )
        if hold == self._hold_apply:
            return
        self._hold_apply = hold
        if not hold and self._pending_apply:
            map_id = self._pending_apply
            self._pending_apply = ""
            if map_id != self._current_map_id():
                self._publish_state(
                    map_id, False, "not_current_map",
                    "지금 주행 지도가 아니라 다음에 이 지도로 주행할 때 적용됩니다.",
                )
                return
            applied, reason, message = self._apply(map_id)
            self._publish_state(map_id, applied, reason, message)

    def _publish_state(
        self, map_id: str, applied: bool, reason: str, message: str
    ) -> None:
        """요청 없이 생긴 상태 변화를 앱에 한 번 알립니다."""
        msg = String()
        msg.data = json.dumps(
            {
                "map_id": map_id,
                "applied": applied,
                "reason": reason,
                "message": message,
                "at": datetime.now(KST).isoformat(timespec="seconds"),
            },
            ensure_ascii=False,
        )
        self.state_publisher.publish(msg)

    def handle_get(self, request, response):
        """저장된 사각형 목록을 돌려줍니다. 없으면 빈 목록입니다."""
        try:
            map_id = km.validate_map_id(request.map_id)
            if bool(self.get_parameter("create_empty_mask_on_get").value):
                try:
                    if km.ensure_mask(self.maps_root, map_id, self._now()):
                        self.get_logger().info(f"빈 금지구역 마스크 생성: {map_id}")
                except km.KeepoutError as error:
                    self.get_logger().warn(f"빈 마스크 생성 건너뜀: {error.message}")
            zones = km.load_zones(self.maps_root, map_id)
        except km.KeepoutError as error:
            response.accepted = False
            response.reason = error.reason
            response.message = error.message
            response.zones_json = "[]"
            response.mask_exists = False
            return response

        response.accepted = True
        response.reason = ""
        response.message = f"금지구역 {len(zones)}개"
        response.zones_json = json.dumps(zones, ensure_ascii=False)
        response.mask_exists = km.keepout_paths(self.maps_root, map_id)["mask"].is_file()
        return response

    def handle_save(self, request, response):
        """사각형 전체 목록을 저장하고, 요청하면 Nav2에 반영합니다."""
        response.applied = False
        response.zone_count = 0

        try:
            raw_zones = json.loads(request.zones_json or "[]")
            if not isinstance(raw_zones, list):
                raise km.KeepoutError("bad_zone", "구역 목록은 배열이어야 합니다.")
            result = km.save_zones(
                self.maps_root, request.map_id, raw_zones, self._now()
            )
        except json.JSONDecodeError as error:
            response.accepted = False
            response.reason = "bad_zone"
            response.message = f"구역 목록을 읽지 못했습니다: {error}"
            return response
        except km.KeepoutError as error:
            response.accepted = False
            response.reason = error.reason
            response.message = error.message
            self.get_logger().warn(f"금지구역 저장 거부: {error.message}")
            return response

        map_id = result["map_id"]
        zone_count = len(result["zones"])
        response.accepted = True
        response.zone_count = zone_count
        self.get_logger().info(
            f"금지구역 저장 완료: map_id={map_id} 구역={zone_count}개"
        )

        if not request.apply_now:
            response.reason = ""
            response.message = f"금지구역 {zone_count}개를 저장했습니다."
            return response

        if map_id != self._current_map_id():
            response.reason = "not_current_map"
            response.message = (
                f"금지구역 {zone_count}개를 저장했습니다. 지금 주행 지도가 아니라 "
                "다음에 이 지도로 주행할 때 적용됩니다."
            )
            return response

        if self._hold_apply:
            self._pending_apply = map_id
            response.reason = "busy_driving"
            response.message = (
                f"금지구역 {zone_count}개를 저장했습니다. 로봇에 목적지가 "
                "남아 있어 주행이 끝나면 적용합니다."
            )
            return response

        applied, reason, message = self._apply(map_id)
        response.applied = applied
        response.reason = reason
        response.message = (
            f"금지구역 {zone_count}개를 저장하고 적용했습니다."
            if applied
            else f"금지구역 {zone_count}개를 저장했습니다. {message}"
        )
        return response

    def _apply(self, map_id: str) -> tuple[bool, str, str]:
        """마스크 서버에 load_map을 걸어 지금 주행에 반영합니다."""
        yaml_path = km.keepout_paths(self.maps_root, map_id)["yaml"]
        if self._load_map_client is None:
            return (
                False,
                "no_nav2",
                "Nav2가 실행되면 적용됩니다.",
            )
        if not self._load_map_client.service_is_ready():
            return (
                False,
                "no_nav2",
                "Nav2가 실행되면 적용됩니다.",
            )

        request = self._load_map_type.Request()
        request.map_url = str(yaml_path)
        future = self._load_map_client.call_async(request)

        done = Event()
        future.add_done_callback(lambda _: done.set())
        timeout = float(self.get_parameter("apply_timeout_sec").value)
        if not done.wait(timeout):
            return (
                False,
                "apply_timeout",
                f"Nav2가 {timeout:.0f}초 안에 응답하지 않아 적용을 확인하지 못했습니다.",
            )

        try:
            result = future.result()
        except Exception as error:  # noqa: BLE001 - 원인을 그대로 사람에게 보입니다.
            return (False, "apply_failed", f"적용에 실패했습니다: {error}")

        if result is None:
            return (False, "apply_failed", "Nav2가 빈 응답을 돌려주었습니다.")

        if result.result == self._load_map_type.Response.RESULT_SUCCESS:
            self.get_logger().info(f"금지구역 마스크 적용: {yaml_path.name}")
            return (True, "", "적용했습니다.")

        reasons = {
            1: "마스크 파일을 찾지 못했습니다.",
            2: "마스크 yaml의 값이 올바르지 않습니다.",
            3: "마스크 이미지를 읽지 못했습니다.",
        }
        detail = reasons.get(int(result.result), f"알 수 없는 실패({result.result}).")
        self.get_logger().error(f"금지구역 마스크 적용 실패: {detail}")
        return (False, "apply_failed", detail)

    def _current_map_id(self) -> str:
        """maps/CURRENT_MAP 의 지도 id. 없으면 빈 글자 — 어느 지도도 바로 물리지 않습니다."""
        try:
            return (self.maps_root / "CURRENT_MAP").read_text(encoding="utf-8").strip()
        except OSError:
            return ""

    @staticmethod
    def _now() -> str:
        return datetime.now(KST).isoformat(timespec="seconds")


def main() -> None:
    """서비스 안에서 다른 서비스를 기다리므로 MultiThreadedExecutor로 돕니다."""
    rclpy.init()
    node = KeepoutMapNode()
    executor = MultiThreadedExecutor()
    executor.add_node(node)
    try:
        executor.spin()
    except (KeyboardInterrupt, ExternalShutdownException):
        pass
    finally:
        executor.remove_node(node)
        node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == "__main__":
    main()
