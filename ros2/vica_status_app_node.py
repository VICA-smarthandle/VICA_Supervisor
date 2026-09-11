#!/usr/bin/env python3
"""VICA 앱에 필요한 로봇 상태를 /robot_status JSON topic으로 요약해 publish하는 노드입니다."""

import json
import math
import time
from datetime import datetime
from pathlib import Path
from typing import Any

import rclpy
import yaml
from diagnostic_msgs.msg import DiagnosticArray
from nav_msgs.msg import Odometry
from rcl_interfaces.msg import ParameterType
from rcl_interfaces.srv import GetParameters
from rclpy.executors import ExternalShutdownException
from rclpy.node import Node
from rclpy.time import Time
from std_msgs.msg import String
from tf2_ros import Buffer, TransformException, TransformListener


ERROR_SOURCE_DIAGNOSTICS = "diagnostics"
ERROR_SOURCE_HEALTH = "health"
ERROR_SOURCES = (ERROR_SOURCE_DIAGNOSTICS, ERROR_SOURCE_HEALTH)

HEALTH_SEVERITY_STOP = 3


class VicaStatusAppNode(Node):
    """VICA 내부 ROS2 상태를 앱 화면에서 쓰기 쉬운 단일 JSON 메시지로 변환합니다."""

    def __init__(self) -> None:
        super().__init__("vica_status_app_node")

        self.declare_parameter("robot_id", "vica_01")
        self.declare_parameter("robot_name", "VICA-01")
        self.declare_parameter("map_yaml", "")
        self.declare_parameter("location_match_radius", 0.5)
        self.declare_parameter(
            "destination_storage_root",
            str(Path.home() / "vica_data" / "destinations"),
        )
        self.declare_parameter("publish_period_sec", 0.1)
        self.declare_parameter("nav2_data_timeout_sec", 3.0)
        self.declare_parameter("odom_timeout_sec", 3.0)
        self.declare_parameter("diagnostics_timeout_sec", 5.0)
        self.declare_parameter("goal_event_timeout_sec", 600.0)
        self.declare_parameter("error_set_delay_sec", 1.0)
        self.declare_parameter("error_clear_delay_sec", 2.0)

        self.declare_parameter("error_source", "health")
        self.declare_parameter("health_timeout_sec", 5.0)
        self.declare_parameter("moving_linear_threshold", 0.03)
        self.declare_parameter("moving_angular_threshold", 0.05)
        self.declare_parameter("map_frame", "map")
        self.declare_parameter("base_frame", "base_footprint")
        self.declare_parameter("map_server_node", "/map_server")
        self.declare_parameter("map_poll_period_sec", 2.0)

        self.storage_root = Path(
            str(self.get_parameter("destination_storage_root").value)
        ).expanduser()
        self.map_frame = str(self.get_parameter("map_frame").value)
        self.base_frame = str(self.get_parameter("base_frame").value)

        self.error_source = str(self.get_parameter("error_source").value).strip()
        if self.error_source not in ERROR_SOURCES:
            self.get_logger().error(
                f"error_source '{self.error_source}'는 허용되지 않습니다. "
                f"허용: {', '.join(ERROR_SOURCES)}. "
                f"{ERROR_SOURCE_DIAGNOSTICS}로 진행합니다."
            )
            self.error_source = ERROR_SOURCE_DIAGNOSTICS

        self.latest_odom: Odometry | None = None
        self.last_odom_time: float | None = None

        self.tf_pose: tuple[float, float, float] | None = None
        self.last_tf_time: float | None = None

        self._diagnostics_by_key: dict[str, tuple[float, int, str]] = {}

        self._latched_error_reason = ""
        self._error_seen_since: float | None = None
        self._error_cleared_since: float | None = None

        self.current_goal = ""
        self.navigation_active = False
        self.navigation_paused = False
        self._navigation_active_since: float | None = None
        self.missing_map_yaml_warned = False

        self.detected_map_yaml = ""
        self._map_param_in_flight = False

        self._loc_cache: list[dict[str, Any]] = []
        self._loc_cache_map_id = ""
        self._loc_cache_time = 0.0

        self.tf_buffer = Buffer()
        self.tf_listener = TransformListener(self.tf_buffer, self)

        map_server_node = str(self.get_parameter("map_server_node").value).rstrip("/")
        self.map_param_client = self.create_client(
            GetParameters, f"{map_server_node}/get_parameters"
        )

        self.publisher = self.create_publisher(String, "/robot_status", 10)

        self.create_subscription(Odometry, "/odom", self.handle_odom, 10)
        self.create_subscription(
            DiagnosticArray, "/diagnostics", self.handle_diagnostics, 10
        )
        self.create_subscription(
            String, "/vica_goal_event", self.handle_goal_event, 10
        )

        self._setup_health_source()

        period = float(self.get_parameter("publish_period_sec").value)
        self.timer = self.create_timer(period, self.publish_status)

        if str(self.get_parameter("map_yaml").value).strip():
            self.map_poll_timer = None
        else:
            poll_period = float(self.get_parameter("map_poll_period_sec").value)
            self.map_poll_timer = self.create_timer(poll_period, self._poll_map_yaml)

        self.get_logger().info(
            f"vica_status_app_node ready: TF {self.map_frame}->{self.base_frame}, "
            f"publish {1.0 / period:.0f}Hz, map auto-detect via {map_server_node}, "
            f"error_source={self.error_source}"
        )

    def handle_odom(self, msg: Odometry) -> None:
        self.latest_odom = msg
        self.last_odom_time = time.monotonic()

    def handle_diagnostics(self, msg: DiagnosticArray) -> None:
        """발행자별 진단 항목을 누적합니다(마지막 메시지로 덮어쓰지 않습니다)."""
        now = time.monotonic()
        for status in msg.status:
            key = status.name or status.hardware_id
            if not key:
                continue
            self._diagnostics_by_key[key] = (
                now,
                self._diagnostic_level(status.level),
                status.message or status.name,
            )

    def handle_goal_event(self, msg: String) -> None:
        """vica_goto_goal의 목적지 이벤트를 받아 앱의 현재 목적지로 표시합니다."""
        try:
            payload = json.loads(msg.data)
        except json.JSONDecodeError:
            self.get_logger().warn("ignored invalid /vica_goal_event JSON")
            return

        event = str(payload.get("event", ""))
        if event in {"goal_sent", "goal_accepted"}:
            self.current_goal = str(
                payload.get("name") or payload.get("destination") or ""
            )
            self.navigation_active = True
            self.navigation_paused = False
            self._navigation_active_since = time.monotonic()
        elif event == "goal_paused":
            self.navigation_active = False
            self.navigation_paused = True
            self._navigation_active_since = None
        elif event in {
            "goal_succeeded",
            "goal_failed",
            "goal_rejected",
            "goal_canceled",
            "emergency_stopped",
        }:
            self.current_goal = ""
            self.navigation_active = False
            self.navigation_paused = False
            self._navigation_active_since = None

    def _poll_map_yaml(self) -> None:
        """map_server의 yaml_filename 파라미터를 주기적으로 조회합니다."""
        if str(self.get_parameter("map_yaml").value).strip():
            return
        if self._map_param_in_flight or not self.map_param_client.service_is_ready():
            return
        request = GetParameters.Request()
        request.names = ["yaml_filename"]
        self._map_param_in_flight = True
        future = self.map_param_client.call_async(request)
        future.add_done_callback(self._on_map_yaml_result)

    def _on_map_yaml_result(self, future: Any) -> None:
        self._map_param_in_flight = False
        try:
            response = future.result()
        except Exception as exc:
            self.get_logger().warn(f"map yaml 조회 실패: {exc}")
            return
        if not response or not response.values:
            return
        value = response.values[0]
        if value.type == ParameterType.PARAMETER_STRING and value.string_value:
            if value.string_value != self.detected_map_yaml:
                self.detected_map_yaml = value.string_value
                self.get_logger().info(f"map yaml 감지: {self.detected_map_yaml}")

    def _update_tf_pose(self) -> None:
        """map->base_frame TF를 조회해 현재 pose를 갱신합니다."""
        try:
            transform = self.tf_buffer.lookup_transform(
                self.map_frame, self.base_frame, Time()
            )
        except TransformException:
            return
        translation = transform.transform.translation
        rotation = transform.transform.rotation
        yaw = self._quaternion_to_yaw_degrees(
            rotation.x, rotation.y, rotation.z, rotation.w
        )
        self.tf_pose = (float(translation.x), float(translation.y), yaw)
        self.last_tf_time = time.monotonic()

    def publish_status(self) -> None:
        """최신 정보를 앱용 /robot_status JSON으로 발행합니다(타이머 주기 실행)."""
        self._update_tf_pose()

        map_id = self._current_map_id()
        x, y, yaw, linear_x, angular_z = self._read_pose_values()
        nav2_pose_available = self._nav2_pose_available()
        error_reason = self._stable_error_reason()
        waiting_reason = self._waiting_reason(
            linear_x, angular_z, error_reason, nav2_pose_available
        )
        status = self._status(linear_x, angular_z, error_reason, nav2_pose_available)

        payload: dict[str, Any] = {
            "robot_id": str(self.get_parameter("robot_id").value),
            "robot_name": str(self.get_parameter("robot_name").value),
            "status": status,
            "x": round(x, 3),
            "y": round(y, 3),
            "yaw": round(yaw, 2),
            "current_location": self._nearest_location_name(map_id, x, y),
            "current_goal": self.current_goal,
            "error_reason": error_reason,
            "waiting_reason": waiting_reason,
            "map_id": map_id,
            "timestamp": datetime.now().isoformat(timespec="seconds"),
        }

        msg = String()
        msg.data = json.dumps(payload, ensure_ascii=False)
        self.publisher.publish(msg)

    def _current_map_id(self) -> str:
        """수동 map_yaml이 있으면 그 값을, 없으면 자동 감지한 yaml을 map_id로 씁니다."""
        manual = str(self.get_parameter("map_yaml").value).strip()
        yaml_path = manual or self.detected_map_yaml
        if yaml_path:
            return Path(yaml_path).stem
        if not self.missing_map_yaml_warned:
            self.get_logger().warn(
                "map yaml을 아직 확인하지 못했습니다. Nav2(map_server) 실행 여부를 "
                "확인하거나 -p map_yaml:=/path/to/map.yaml 로 직접 지정하세요."
            )
            self.missing_map_yaml_warned = True
        return ""

    def _read_pose_values(self) -> tuple[float, float, float, float, float]:
        """(x, y, yaw_degree, linear_x, angular_z)를 돌려줍니다."""
        odom_fresh = self._odom_fresh()
        linear_x = 0.0
        angular_z = 0.0
        if odom_fresh and self.latest_odom is not None:
            twist = self.latest_odom.twist.twist
            linear_x = float(twist.linear.x)
            angular_z = float(twist.angular.z)

        if self._nav2_pose_available() and self.tf_pose is not None:
            x, y, yaw = self.tf_pose
            return x, y, yaw, linear_x, angular_z

        if not odom_fresh or self.latest_odom is None:
            return 0.0, 0.0, 0.0, 0.0, 0.0

        pose = self.latest_odom.pose.pose
        yaw = self._quaternion_to_yaw_degrees(
            pose.orientation.x,
            pose.orientation.y,
            pose.orientation.z,
            pose.orientation.w,
        )
        return (
            float(pose.position.x),
            float(pose.position.y),
            yaw,
            linear_x,
            angular_z,
        )

    def _nav2_pose_available(self) -> bool:
        """map->base TF가 최근에 확보됐는지로 Nav2 위치 추정 활성 여부를 판단합니다."""
        if self.tf_pose is None or self.last_tf_time is None:
            return False
        timeout_sec = float(self.get_parameter("nav2_data_timeout_sec").value)
        return (time.monotonic() - self.last_tf_time) <= timeout_sec

    def _odom_fresh(self) -> bool:
        """/odom이 만료 시간 안에 갱신되고 있는지 확인합니다."""
        if self.latest_odom is None or self.last_odom_time is None:
            return False
        timeout_sec = float(self.get_parameter("odom_timeout_sec").value)
        return (time.monotonic() - self.last_odom_time) <= timeout_sec

    def _is_navigation_active(self) -> bool:
        """goal 종료 이벤트를 놓쳤을 때 moving에 갇히지 않도록 만료를 적용합니다."""
        if not self.navigation_active:
            return False
        timeout_sec = float(self.get_parameter("goal_event_timeout_sec").value)
        if timeout_sec <= 0.0:
            return True
        if self._navigation_active_since is None:
            return True
        if (time.monotonic() - self._navigation_active_since) <= timeout_sec:
            return True
        self.get_logger().warn(
            f"goal 종료 이벤트를 {timeout_sec:.0f}초 동안 받지 못해 주행 상태를 해제합니다."
        )
        self.navigation_active = False
        self._navigation_active_since = None
        self.current_goal = ""
        return False

    def _quaternion_to_yaw_degrees(
        self, x: float, y: float, z: float, w: float
    ) -> float:
        """orientation quaternion에서 z축 회전(yaw)만 뽑아 0~360도로 정규화합니다."""
        siny_cosp = 2.0 * (w * z + x * y)
        cosy_cosp = 1.0 - 2.0 * (y * y + z * z)
        yaw = math.degrees(math.atan2(siny_cosp, cosy_cosp))
        return yaw % 360.0

    def _status(
        self,
        linear_x: float,
        angular_z: float,
        error_reason: str,
        nav2_pose_available: bool,
    ) -> str:
        """오류>위치미확보>목표주행>속도>대기 순으로 상태를 정합니다."""
        if error_reason:
            return "error"
        if not nav2_pose_available:
            return "waiting"
        if self._is_navigation_active():
            return "moving"
        if self._is_moving(linear_x, angular_z):
            return "moving"
        return "waiting"

    def _is_moving(self, linear_x: float, angular_z: float) -> bool:
        """작은 센서 노이즈는 정지로 보도록 임계값을 적용합니다."""
        linear_threshold = float(self.get_parameter("moving_linear_threshold").value)
        angular_threshold = float(self.get_parameter("moving_angular_threshold").value)
        return abs(linear_x) >= linear_threshold or abs(angular_z) >= angular_threshold

    def _diagnostic_reason(self, min_level: int) -> str:
        """누적된 진단 항목 중 min_level(ERROR=2) 이상인 사유를 하나 고릅니다."""
        now = time.monotonic()
        timeout_sec = float(self.get_parameter("diagnostics_timeout_sec").value)
        expired = [
            key
            for key, (seen_at, _, _) in self._diagnostics_by_key.items()
            if (now - seen_at) > timeout_sec
        ]
        for key in expired:
            del self._diagnostics_by_key[key]

        matched = sorted(
            key
            for key, (_, level, _) in self._diagnostics_by_key.items()
            if level >= min_level
        )
        if not matched:
            return ""
        return self._diagnostics_by_key[matched[0]][2]

    def _setup_health_source(self) -> None:
        """error_source가 health일 때만 /robot/health를 구독합니다."""
        self.latest_health = None
        self.last_health_time: float | None = None

        if self.error_source != ERROR_SOURCE_HEALTH:
            return

        try:
            from vica_interfaces.msg import RobotHealth
        except ImportError as exc:
            self.get_logger().error(
                f"error_source=health인데 vica_interfaces.msg.RobotHealth를 "
                f"import할 수 없습니다: {exc}. diagnostics 모드로 되돌립니다. "
                f"vica_ros2_ws에서 vica_interfaces를 빌드하고 source하세요."
            )
            self.error_source = ERROR_SOURCE_DIAGNOSTICS
            return

        self.create_subscription(RobotHealth, "/robot/health", self.handle_health, 10)
        self.get_logger().info(
            "error_source=health: /robot/health를 오류 사유의 원천으로 씁니다"
        )

    def handle_health(self, msg: Any) -> None:
        """robot_health_monitor_node의 요약을 보관합니다."""
        self.latest_health = msg
        self.last_health_time = time.monotonic()

    def _raw_error_reason(self) -> str:
        """error_source에 따라 오류 사유 원문을 만듭니다."""
        if self.error_source == ERROR_SOURCE_HEALTH:
            return self._health_error_reason()
        return self._diagnostic_reason(min_level=2)

    def _health_error_reason(self) -> str:
        """/robot/health에서 오류 사유를 만듭니다."""
        health = self.latest_health
        if health is None or self.last_health_time is None:
            return ""

        timeout = float(self.get_parameter("health_timeout_sec").value)
        if timeout > 0.0 and (time.monotonic() - self.last_health_time) > timeout:
            return ""

        if int(health.highest_severity) < HEALTH_SEVERITY_STOP:
            return ""

        primary = str(health.primary_fault_code)
        for fault in health.active_faults:
            if str(fault.fault_code) != primary:
                continue
            detail = str(fault.detail).strip()
            if detail:
                return detail
            return primary
        return primary

    def _stable_error_reason(self) -> str:
        """오류 사유에 지연을 적용해 짧은 깜빡임을 걸러냅니다."""
        raw_reason = self._raw_error_reason()
        now = time.monotonic()
        set_delay = float(self.get_parameter("error_set_delay_sec").value)
        clear_delay = float(self.get_parameter("error_clear_delay_sec").value)

        if raw_reason:
            self._error_cleared_since = None
            if self._error_seen_since is None:
                self._error_seen_since = now
            if self._latched_error_reason or (now - self._error_seen_since) >= set_delay:
                self._latched_error_reason = raw_reason
            return self._latched_error_reason

        self._error_seen_since = None
        if not self._latched_error_reason:
            return ""
        if self._error_cleared_since is None:
            self._error_cleared_since = now
        if (now - self._error_cleared_since) >= clear_delay:
            self._latched_error_reason = ""
            self._error_cleared_since = None
        return self._latched_error_reason

    def _diagnostic_level(self, level: Any) -> int:
        """diagnostic level이 int/bytes/str 중 어떤 형태로 와도 숫자로 변환합니다."""
        if isinstance(level, int):
            return level
        if isinstance(level, bytes) and level:
            return level[0]
        if isinstance(level, str) and level:
            return ord(level[0])
        return 0

    def _waiting_reason(
        self,
        linear_x: float,
        angular_z: float,
        error_reason: str,
        nav2_pose_available: bool,
    ) -> str:
        """정지 상태일 때 앱에 표시할 대기 사유를 만듭니다."""
        if error_reason:
            return ""
        if not nav2_pose_available:
            return "Nav2/AMCL 미실행"
        if not self._odom_fresh():
            return "위치 데이터 수신 대기"
        if self.navigation_paused:
            return "일시정지"
        if self._is_navigation_active():
            return ""
        if self._is_moving(linear_x, angular_z):
            return ""
        return "목표 없음"

    def _nearest_location_name(self, map_id: str, x: float, y: float) -> str:
        """저장된 장소 중 설정 반경 이내에서 가장 가까운 장소명을 찾습니다."""
        radius = float(self.get_parameter("location_match_radius").value)
        locations = self._read_locations(map_id)
        nearest_name = ""
        nearest_distance = radius

        for location in locations:
            try:
                pose = location.get("pose") or {}
                dx = x - float(pose.get("x", 0.0))
                dy = y - float(pose.get("y", 0.0))
            except (TypeError, ValueError):
                continue
            distance = math.hypot(dx, dy)
            if distance <= nearest_distance:
                nearest_distance = distance
                nearest_name = str(
                    location.get("name") or location.get("id") or ""
                )
        return nearest_name or "이동 중"

    def _read_locations(self, map_id: str) -> list[dict[str, Any]]:
        """지도별 destinations.yaml을 읽습니다(2초 캐시)."""
        now = time.monotonic()
        if (
            map_id == self._loc_cache_map_id
            and (now - self._loc_cache_time) < 2.0
        ):
            return self._loc_cache

        result: list[dict[str, Any]] = []
        path = self.storage_root / map_id / "destinations.yaml"
        if map_id and path.exists():
            try:
                data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
                destinations = data.get("destinations", [])
                if isinstance(destinations, list):
                    result = [
                        item for item in destinations if isinstance(item, dict)
                    ]
            except (yaml.YAMLError, OSError) as exc:
                self.get_logger().warn(f"failed to read destinations: {exc}")

        self._loc_cache = result
        self._loc_cache_map_id = map_id
        self._loc_cache_time = now
        return result


def main() -> None:
    rclpy.init()
    node = VicaStatusAppNode()
    try:
        rclpy.spin(node)
    except (KeyboardInterrupt, ExternalShutdownException):
        pass
    finally:
        node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == "__main__":
    main()
