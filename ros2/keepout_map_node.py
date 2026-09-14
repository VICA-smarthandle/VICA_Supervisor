#!/usr/bin/env python3
"""앱이 그린 금지구역을 파일로 만들고 Nav2에 물리는 노드입니다.

연결 흐름:
    Flutter 앱
        -> /vica/keepout/save (SaveKeepout)
        -> keepout_map_node
        -> maps/<map_id>_keepout.{pgm,yaml,json}
        -> /keepout_filter_mask_server/load_map
        -> Nav2 KeepoutFilter -> global costmap

판단은 전부 keepout_mask.py에 있습니다. 이 파일은 ROS 배선만 담당합니다.
그래야 좌표 계산을 로봇 없이 시험할 수 있습니다(test_keepout_mask.py).

**저장과 적용은 다른 일입니다.**
    저장 = 파일 세 개를 쓴다. 언제나 할 수 있다.
    적용 = Nav2 마스크 서버에 load_map을 걸어 지금 주행에 반영한다.

주행 중에는 적용하지 않습니다. 로봇이 새로 그린 금지구역 안에 서 있으면
planner가 "Starting point in lethal space"로 실패합니다 — devlog에 이미 기록된
실패 모드입니다. 그때는 저장만 하고, 주행이 끝나는 순간 한 번 자동으로
적용한 뒤 /vica/keepout/state로 알립니다.
"""

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

# 한국 시간. 저장 시각을 사람이 읽을 수 있는 절대시각으로 남깁니다.
KST = timezone(timedelta(hours=9))


class KeepoutMapNode(Node):
    """금지구역 저장·조회 서비스와 Nav2 반영을 담당합니다.

    제공 service:
        /vica/keepout/save : 사각형 전체 목록을 저장하고 필요하면 반영
        /vica/keepout/get  : 저장된 사각형 목록 조회

    발행 topic:
        /vica/keepout/state : 요청 없이 생긴 상태 변화만 알립니다(주행 후 자동 반영 등).
                              요청의 결과는 service 응답으로 갑니다 — 두 경로가
                              겹치면 앱이 같은 일을 두 번 알립니다.

    구독 topic:
        /robot_status : 반영을 미뤄야 하는지 봅니다. 목적지가 살아 있으면
                        (주행·일시정지·주행 중 오류) 미룹니다 —
                        keepout_mask.hold_apply 참고.
    """

    def __init__(self) -> None:
        super().__init__("vica_keepout_map")

        workspace_root = Path(__file__).resolve().parents[2]
        default_maps_root = workspace_root / "vica_ros2_ws" / "maps"
        self.declare_parameter("maps_root", str(default_maps_root))
        self.maps_root = Path(str(self.get_parameter("maps_root").value)).expanduser()

        # nav2_map_server::MapServer가 여는 서비스입니다. 노드 이름이 앞에 붙으므로
        # launch에서 노드 이름을 바꾸면 이 값도 함께 바꿔야 합니다.
        self.declare_parameter(
            "mask_load_service", "/keepout_filter_mask_server/load_map"
        )
        # 앱의 callService 기본 timeout이 5초입니다. 그보다 짧게 잡아야 앱이
        # 포기한 뒤에 응답이 도착하는 일이 생기지 않습니다.
        self.declare_parameter("apply_timeout_sec", 3.0)
        self.declare_parameter("robot_status_topic", "/robot_status")
        # 앱이 지도를 열어 보기만 해도 빈 마스크를 만들어 둘지 여부입니다.
        # 만들어 두면 Nav2 launch가 언제나 같은 모양이 됩니다. 빈 마스크는
        # 전부 회색이라 costmap에 아무 일도 하지 않습니다(keepout_mask.py 참고).
        self.declare_parameter("create_empty_mask_on_get", True)

        self._callbacks = ReentrantCallbackGroup()
        # 반영을 미뤄야 하는 상태인가(주행·일시정지·주행 중 오류 — 목적지가
        # 살아 있는 동안 전부). 판정은 keepout_mask.hold_apply 가 합니다.
        self._hold_apply = False
        # 주행이 끝나면 적용해야 할 지도입니다. 하나만 들고 있습니다 — 여러 지도의
        # 금지구역을 동시에 미뤄 둘 상황이 없고, 있다면 마지막 것이 맞습니다.
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

    # ------------------------------------------------------------------
    # 기동
    # ------------------------------------------------------------------

    def _setup_services(self) -> None:
        """앱이 부르는 두 서비스를 엽니다.

        import를 감싸는 이유는 map_list_node._setup_delete_service와 같습니다.
        vica_interfaces를 빌드하지 않은 환경에서 이 노드가 기동 실패하면
        supervisor_bringup 전체가 흔들립니다.
        """
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
        """Nav2 마스크 서버의 load_map 클라이언트를 만듭니다.

        Nav2가 꺼져 있어도 클라이언트는 만들어 둡니다. 실제 호출 시점에
        service_is_ready()로 확인하고, 없으면 '저장만 했다'로 답합니다.
        """
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

    # ------------------------------------------------------------------
    # 상태
    # ------------------------------------------------------------------

    def _on_robot_status(self, msg: String) -> None:
        """반영을 미뤄야 하는 상태인지 봅니다. 판정 기준은 keepout_mask.hold_apply.

        status == "moving" 만 보면 일시정지·주행 중 오류·순단을 놓칩니다 —
        셋 다 로봇이 목적지를 쥔 채입니다(hold_apply docstring 참고).
        """
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
            # 목적지가 막 정리됐습니다(성공·실패·취소). 미뤄 둔 반영을 한 번만
            # 시도합니다.
            map_id = self._pending_apply
            self._pending_apply = ""
            applied, reason, message = self._apply(map_id)
            self._publish_state(map_id, applied, reason, message)

    def _publish_state(
        self, map_id: str, applied: bool, reason: str, message: str
    ) -> None:
        """요청 없이 생긴 상태 변화를 앱에 한 번 알립니다.

        주기적으로 내지 않습니다. 같은 상태가 이어지는 동안 반복해서 보내면
        앱이 2초마다 팝업을 띄우게 됩니다 — 그런 상시 표시는 배너의 몫입니다.
        """
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

    # ------------------------------------------------------------------
    # 서비스
    # ------------------------------------------------------------------

    def handle_get(self, request, response):
        """저장된 사각형 목록을 돌려줍니다. 없으면 빈 목록입니다."""
        try:
            map_id = km.validate_map_id(request.map_id)
            if bool(self.get_parameter("create_empty_mask_on_get").value):
                # 앱이 이 지도를 한 번이라도 열면 그 뒤로 launch가 항상 마스크를
                # 뭅니다. 빈 마스크는 아무 일도 하지 않으므로 안전합니다.
                try:
                    if km.ensure_mask(self.maps_root, map_id, self._now()):
                        self.get_logger().info(f"빈 금지구역 마스크 생성: {map_id}")
                except km.KeepoutError as error:
                    # 조회를 실패로 만들지 않습니다. 목록은 여전히 보여줄 수 있습니다.
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

        if self._hold_apply:
            # 지금 반영하면 로봇이 금지구역 안에 갇힐 수 있습니다(일시정지 재개
            # 포함). 저장은 이미 끝났으므로 실패가 아닙니다 — 미뤘다는 사실만
            # 정확히 알립니다. reason 값은 앱 계약이라 바꾸지 않습니다.
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

    # ------------------------------------------------------------------
    # Nav2 반영
    # ------------------------------------------------------------------

    def _apply(self, map_id: str) -> tuple[bool, str, str]:
        """마스크 서버에 load_map을 걸어 지금 주행에 반영합니다.

        Nav2 재시작이 아닙니다. MapServer는 ACTIVE 상태에서 새 yaml을 읽어 같은
        토픽에 다시 발행하고, 그 토픽이 transient_local이라 KeepoutFilter가
        곧바로 받아 갑니다. AMCL과 원본 지도는 건드리지 않습니다.

        돌려주는 값은 (applied, reason, message)입니다.
        """
        yaml_path = km.keepout_paths(self.maps_root, map_id)["yaml"]
        if self._load_map_client is None:
            return (
                False,
                "no_nav2",
                "Nav2 마스크 서버에 연결할 수 없어 적용은 미뤘습니다.",
            )
        if not self._load_map_client.service_is_ready():
            return (
                False,
                "no_nav2",
                "Nav2가 실행 중이 아니라 적용은 미뤘습니다. "
                "주행 스택을 켠 뒤 다시 적용해 주세요.",
            )

        request = self._load_map_type.Request()
        request.map_url = str(yaml_path)
        future = self._load_map_client.call_async(request)

        # 서비스 콜백 안에서 기다립니다. MultiThreadedExecutor + Reentrant
        # 콜백 그룹이라 다른 스레드가 계속 spin 하므로 future가 완료됩니다.
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

        # LoadMap의 실패 코드를 사람 말로 옮깁니다. 숫자만 보여주면 다음 사람이
        # 다시 nav2_msgs를 뒤져야 합니다.
        reasons = {
            1: "마스크 파일을 찾지 못했습니다.",
            2: "마스크 yaml의 값이 올바르지 않습니다.",
            3: "마스크 이미지를 읽지 못했습니다.",
        }
        detail = reasons.get(int(result.result), f"알 수 없는 실패({result.result}).")
        self.get_logger().error(f"금지구역 마스크 적용 실패: {detail}")
        return (False, "apply_failed", detail)

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
