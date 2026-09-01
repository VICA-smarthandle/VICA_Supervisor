#!/usr/bin/env python3
"""VICA 앱에 필요한 로봇 상태를 /robot_status JSON topic으로 요약해 publish하는 노드입니다.

연결 흐름:
    VICA/Nav2 기존 topic/TF
        -> TF map->base_footprint, /odom, /diagnostics
        -> VicaStatusAppNode
        -> /robot_status
        -> rosbridge
        -> Flutter 앱

    vica_goto_goal
        -> /vica_goal_event
        -> VicaStatusAppNode
        -> /robot_status.current_goal
        -> Flutter 앱

앱이 /odom, TF, /diagnostics 등을 직접 구독하지 않도록, 이 노드가 앱 화면에
필요한 값만 하나의 JSON 메시지로 요약합니다.

현재 위치 표시:
    로봇 위치는 map frame 기준 TF(map -> base_footprint)를 주기적으로 조회해 얻습니다.
    /amcl_pose와 달리 TF는 AMCL 보정 사이를 odom으로 연속 보간하므로, 원하는 주기로
    매끄럽게 위치를 읽을 수 있어 앱 마커가 실시간으로 부드럽게 움직입니다.

지도 자동 감지:
    Nav2가 실행되면 map_server 노드가 map yaml 경로를 yaml_filename 파라미터로 갖습니다.
    이 노드는 그 파라미터를 조회해 map_id(파일명 stem)를 자동으로 정하므로, 실행 시
    지도 경로를 따로 넘길 필요가 없습니다. map_yaml 파라미터를 명시하면 그 값이 우선합니다.
"""

import json
import math
import time
from datetime import datetime
from pathlib import Path
from typing import Any

import rclpy
import yaml
from diagnostic_msgs.msg import DiagnosticArray
from geometry_msgs.msg import PoseWithCovarianceStamped
from nav_msgs.msg import Odometry
from rcl_interfaces.msg import ParameterType
from rcl_interfaces.srv import GetParameters
from rclpy.executors import ExternalShutdownException
from rclpy.node import Node
from rclpy.qos import DurabilityPolicy, QoSProfile, ReliabilityPolicy
from std_msgs.msg import String


# error_reason의 원천. error_source 파라미터가 고릅니다.
ERROR_SOURCE_DIAGNOSTICS = "diagnostics"
ERROR_SOURCE_HEALTH = "health"
ERROR_SOURCES = (ERROR_SOURCE_DIAGNOSTICS, ERROR_SOURCE_HEALTH)

# vica_interfaces/msg/RobotFault.msg의 SEVERITY_STOP과 같은 값입니다.
# RobotHealth를 import하지 않는 diagnostics 모드에서도 이 파일이 동작해야 하므로
# 여기에 다시 적습니다. 값이 바뀌면 함께 바꿔야 합니다.
HEALTH_SEVERITY_STOP = 3


class VicaStatusAppNode(Node):
    """VICA 내부 ROS2 상태를 앱 화면에서 쓰기 쉬운 단일 JSON 메시지로 변환합니다."""

    def __init__(self) -> None:
        super().__init__("vica_status_app_node")

        # 앱 표시값과 장소 판정 기준은 파라미터로 바꿀 수 있게 둡니다.
        self.declare_parameter("robot_id", "vica_01")
        self.declare_parameter("robot_name", "VICA-01")
        # map_yaml: 수동 오버라이드. 비워두면 map_server에서 자동 감지합니다.
        self.declare_parameter("map_yaml", "")
        self.declare_parameter("location_match_radius", 0.5)
        self.declare_parameter(
            "destination_storage_root",
            str(Path.home() / "vica_data" / "destinations"),
        )
        # 0.1(10Hz) -> 0.5(2Hz) (2026-09-01). 10Hz는 태블릿 마커의 사치였고
        # 이 노드 CPU와 rosbridge 번역량의 주범이었다. 소비자 전수조사 결과
        # (앱 마커·주행 버튼 판정·keepout 유예) 주기에 민감한 곳이 없고,
        # 위치미확보 판정 임계(nav2_data_timeout_sec 3.0)와도 여유 6배다.
        self.declare_parameter("publish_period_sec", 0.5)
        self.declare_parameter("nav2_data_timeout_sec", 3.0)
        # 구독 입력별 만료 시간. 발행이 끊긴 값을 현재 상태로 쓰지 않기 위한 기준입니다.
        self.declare_parameter("odom_timeout_sec", 3.0)
        self.declare_parameter("diagnostics_timeout_sec", 5.0)
        # goal 종료 이벤트를 놓쳐도 moving에 영원히 갇히지 않도록 하는 안전망입니다.
        # 0 이하면 만료를 쓰지 않습니다. 정상 주행이 이보다 길면 값을 늘리세요.
        self.declare_parameter("goal_event_timeout_sec", 600.0)
        # 오류 표시 떨림 억제. ERROR가 set_delay 동안 이어질 때만 오류로 확정하고,
        # 사라진 뒤에도 clear_delay 동안은 유지해 0↔1 깜빡임을 막습니다.
        self.declare_parameter("error_set_delay_sec", 1.0)
        self.declare_parameter("error_clear_delay_sec", 2.0)

        # error_reason을 어디서 만들지 고릅니다.
        #
        #   "diagnostics" (기본) : /diagnostics를 직접 읽어 판정합니다. 현재 동작입니다
        #   "health"             : vica_system_monitor의 /robot/health를 씁니다
        #
        # health 모드가 /diagnostics 판정과 다른 점:
        #   - 판정 지점이 로봇 쪽 robot_health_monitor_node 하나로 모입니다
        #   - 앱 화면과 error_reason이 같은 근거를 씁니다
        #   - 컴포넌트·등급·조치 문구를 로봇이 결정합니다
        #
        # 2026-08-02: 기본값을 "diagnostics" -> "health"로 바꿉니다. 위 주석이
        # 예고한 "Jetson에서 A/B한 뒤 별도 커밋으로 기본값을 바꾼다"를 수행합니다.
        #
        # 실측 근거(run1104, 509초, /robot_status 5083건):
        #   error_reason 이 전 구간 "No events recorded." 로 고정
        #   -> _status()가 첫 줄에서 "error"를 돌려주고 끝나 moving/waiting 에
        #      도달하지 못한다
        #   -> 앱 대시보드가 "전체 1 / 운행 중 0 / 대기 중 0 / 오류 1" 로 굳는다
        #      주행 중에도 배지가 계속 '오류'다
        #
        # 그 문자열의 정체는 robot_localization 의 죽은 진단이다. /odom 은 같은
        # 시각 24.7 Hz 로 정상 발행 중인데 FrequencyStatus 카운터가 한 번도 돌지
        # 않아 "No events recorded." 를 낸다. ekf.yaml 에 print_diagnostics: false
        # 를 넣어도 사라지지 않는다(2026-08-01 확인, 2026-08-02 재확인).
        #
        # robot_health_monitor_node 는 이 항목을 agg_parser.IGNORED_NAME_FRAGMENTS
        # 로 이미 걸러낸다. 그래서 앱의 시스템 진단 화면은 정상(결함 0)인데
        # 대시보드만 오류로 표시되는 어긋남이 생겼다. 두 화면이 같은 근거를
        # 쓰게 하면 이 어긋남이 구조적으로 사라진다.
        #
        # 되돌리려면 이 값을 "diagnostics" 로 바꾼다. health 모드는 vica_interfaces
        # 의 RobotHealth 를 필요로 하며, import 에 실패하면 아래에서 로그를 남기고
        # diagnostics 로 자동 폴백한다.
        self.declare_parameter("error_source", "health")
        # /robot/health 만료. 모니터가 죽으면 마지막 상태를 현재로 쓰지 않습니다.
        self.declare_parameter("health_timeout_sec", 5.0)
        self.declare_parameter("moving_linear_threshold", 0.03)
        self.declare_parameter("moving_angular_threshold", 0.05)
        # TF 프레임. vica_nav2 설정 기준: global=map, base=base_footprint.
        self.declare_parameter("map_frame", "map")
        self.declare_parameter("base_frame", "base_footprint")
        # map yaml 자동 감지에 쓰는 map_server 노드 이름과 조회 주기.
        self.declare_parameter("map_server_node", "/map_server")
        self.declare_parameter("map_poll_period_sec", 2.0)

        self.storage_root = Path(
            str(self.get_parameter("destination_storage_root").value)
        ).expanduser()
        self.map_frame = str(self.get_parameter("map_frame").value)
        self.base_frame = str(self.get_parameter("base_frame").value)

        # 알 수 없는 값을 조용히 기본값으로 흡수하지 않습니다. 오타를 흡수하면 왜 원천이
        # 바뀌지 않는지 찾기 어렵습니다.
        self.error_source = str(self.get_parameter("error_source").value).strip()
        if self.error_source not in ERROR_SOURCES:
            self.get_logger().error(
                f"error_source '{self.error_source}'는 허용되지 않습니다. "
                f"허용: {', '.join(ERROR_SOURCES)}. "
                f"{ERROR_SOURCE_DIAGNOSTICS}로 진행합니다."
            )
            self.error_source = ERROR_SOURCE_DIAGNOSTICS

        # 구독 입력의 나이는 모두 monotonic 기준으로 잽니다. 시스템 시계가 바뀌어도
        # 만료 판정이 흔들리지 않게 하기 위해서입니다(표시용 timestamp만 wall clock).
        # /odom은 주로 twist 속도(실제 움직임 여부)와 TF 미확보 시 fallback pose에 씁니다.
        self.latest_odom: Odometry | None = None
        self.last_odom_time: float | None = None

        # AMCL이 마지막으로 알려준 map frame 기준 pose (x, y, yaw_deg).
        # 종전에는 TF 청취기로 매 주기 조회했는데, 청취기는 /tf 방송 전체
        # (EKF 30Hz+)를 상시 수신·보관해 이 노드 CPU의 최대 고정비였다.
        # /amcl_pose 구독으로 바꿨다(2026-09-01) — mission_manager가 같은
        # 이유로 먼저 쓰던 방식이고, 2Hz 상황판에는 이 신선도면 충분하다.
        self.map_pose: tuple[float, float, float] | None = None
        self.last_map_pose_time: float | None = None

        # diagnostics는 오류/대기 사유 문자열을 만들 때만 사용합니다.
        # /diagnostics는 여러 노드가 함께 쓰는 공용 topic이고 각 메시지는 그 발행자의
        # 상태만 담습니다. 마지막 메시지 하나만 들고 있으면 ERROR를 가진 발행자와
        # 정상 발행자가 번갈아 도착할 때 오류 표시가 깜빡이므로, 항목별로 누적합니다.
        # key -> (수신 monotonic 시각, level, message)
        self._diagnostics_by_key: dict[str, tuple[float, int, str]] = {}

        # 떨림 억제를 거쳐 확정된 오류 사유와 그 전이 시각.
        self._latched_error_reason = ""
        self._error_seen_since: float | None = None
        self._error_cleared_since: float | None = None

        # Mission Manager가 목표를 보내면 /vica_goal_event로 목적지 이름이 들어옵니다.
        self.current_goal = ""
        self.navigation_active = False
        # 일시정지 여부. 목적지를 기억한 채 멈춘 상태라 그냥 대기와 구분해서 보여준다.
        self.navigation_paused = False
        self._navigation_active_since: float | None = None
        self.missing_map_yaml_warned = False

        # map_server yaml_filename 자동 감지 상태.
        self.detected_map_yaml = ""
        self._map_param_in_flight = False

        # destinations.yaml 캐시 (10Hz 발행마다 파일을 읽지 않도록).
        self._loc_cache: list[dict[str, Any]] = []
        self._loc_cache_map_id = ""
        self._loc_cache_time = 0.0

        # 지도 위치는 /amcl_pose 로 받는다. AMCL 은 transient_local(보관) +
        # 이동 시에만 발행하므로, 일반(volatile) 구독은 이 노드가 나중에 켜지면
        # 보관본을 못 받는다 — mission_manager 의 같은 구독과 동일한 함정 대응.
        amcl_qos = QoSProfile(
            depth=1,
            reliability=ReliabilityPolicy.RELIABLE,
            durability=DurabilityPolicy.TRANSIENT_LOCAL,
        )
        self.create_subscription(
            PoseWithCovarianceStamped, "/amcl_pose", self.handle_amcl_pose, amcl_qos
        )

        # map_server 파라미터 조회 클라이언트.
        map_server_node = str(self.get_parameter("map_server_node").value).rstrip("/")
        self.map_param_client = self.create_client(
            GetParameters, f"{map_server_node}/get_parameters"
        )

        # 앱은 /robot_status 하나만 구독하면 되도록 이 노드가 내부 상태를 요약합니다.
        self.publisher = self.create_publisher(String, "/robot_status", 10)

        # 주행 속도와 fallback 위치용 /odom.
        self.create_subscription(Odometry, "/odom", self.handle_odom, 10)
        # Nav2 lifecycle/diagnostic 상태에서 오류 문구 후보.
        self.create_subscription(
            DiagnosticArray, "/diagnostics", self.handle_diagnostics, 10
        )
        # 저장 좌표 주행 노드가 발행하는 goal 이벤트.
        self.create_subscription(
            String, "/vica_goal_event", self.handle_goal_event, 10
        )

        # 일시정지 여부의 정본. 이벤트 한 번이 아니라 1 Hz 상태를 본다.
        self._setup_paused_source()

        # health 모드일 때만 /robot/health를 구독합니다.
        self._setup_health_source()

        period = float(self.get_parameter("publish_period_sec").value)
        self.timer = self.create_timer(period, self.publish_status)

        # 지도 자동 감지: 수동 map_yaml이 없을 때만 map_server 파라미터를 조회합니다.
        # status 노드가 Nav2보다 먼저 떠 있을 수 있어 "받을 때까지" 재시도하고,
        # 첫 감지에 성공하면 타이머를 멈춥니다(계속 조회할 필요 없음).
        if str(self.get_parameter("map_yaml").value).strip():
            self.map_poll_timer = None
        else:
            poll_period = float(self.get_parameter("map_poll_period_sec").value)
            self.map_poll_timer = self.create_timer(poll_period, self._poll_map_yaml)

        self.get_logger().info(
            f"vica_status_app_node ready: pose=/amcl_pose ({self.map_frame} 기준), "
            f"publish {1.0 / period:.0f}Hz, map auto-detect via {map_server_node}, "
            f"error_source={self.error_source}"
        )

    # ------------------------------------------------------------------
    # 구독 콜백
    # ------------------------------------------------------------------
    def handle_odom(self, msg: Odometry) -> None:
        self.latest_odom = msg
        self.last_odom_time = time.monotonic()

    def handle_diagnostics(self, msg: DiagnosticArray) -> None:
        """발행자별 진단 항목을 누적합니다(마지막 메시지로 덮어쓰지 않습니다).

        /diagnostics는 여러 노드가 공유하는 topic이라 한 메시지에는 그 발행자의
        상태만 들어 있습니다. 항목 단위로 보관해야 서로 다른 발행자의 상태가
        번갈아 도착해도 오류 판정이 흔들리지 않습니다.
        """
        now = time.monotonic()
        for status in msg.status:
            key = status.name or status.hardware_id
            if not key:
                # 이름이 없는 항목은 서로 구분할 수 없어 누적 대상에서 제외합니다.
                continue
            self._diagnostics_by_key[key] = (
                now,
                self._diagnostic_level(status.level),
                status.message or status.name,
            )

    def handle_goal_event(self, msg: String) -> None:
        """vica_goto_goal의 목적지 이벤트를 받아 앱의 현재 목적지로 표시합니다.

        goal_sent/goal_accepted 이면 목적지명을 저장하고 navigation_active=True,
        종료/취소 이벤트면 목적지를 비우고 navigation_active=False로 둡니다. 덕분에
        주행 중 속도가 잠깐 0이 되어도 앱 상태가 waiting으로 튀지 않습니다.
        """
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
            # 일시정지는 목적지를 기억한 채 멈춘 상태다. current_goal 을 지우면
            # 앱이 재개할 목적지를 보여줄 수 없으므로 그대로 둔다.
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

    # ------------------------------------------------------------------
    # map yaml 자동 감지
    # ------------------------------------------------------------------
    def _poll_map_yaml(self) -> None:
        """map_server의 yaml_filename 파라미터를 주기적으로 조회합니다.

        수동 map_yaml 파라미터가 지정돼 있으면 자동 감지는 건너뜁니다.
        map_server가 없으면(=Nav2 미실행) 조용히 넘어갑니다.
        """
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
        except Exception as exc:  # ROS future 예외는 배포판마다 다릅니다.
            self.get_logger().warn(f"map yaml 조회 실패: {exc}")
            return
        if not response or not response.values:
            return
        value = response.values[0]
        # 비어 있지 않은 yaml_filename만 반영합니다.
        # (map_server 구성 직후 잠깐 빈 문자열이 올 수 있어 non-empty일 때만 확정)
        #
        # 첫 감지 뒤에도 조회를 계속합니다. 지도작성 후 새 지도를 올리거나 map_server가
        # 다른 지도로 재시작하면 map_id가 바뀌어야 하는데, 여기서 멈추면 예전 map_id가
        # 남아 장소 조회(destinations.yaml) 경로까지 어긋나기 때문입니다.
        if value.type == ParameterType.PARAMETER_STRING and value.string_value:
            if value.string_value != self.detected_map_yaml:
                self.detected_map_yaml = value.string_value
                self.get_logger().info(f"map yaml 감지: {self.detected_map_yaml}")

    # ------------------------------------------------------------------
    # TF 위치 조회
    # ------------------------------------------------------------------
    def handle_amcl_pose(self, msg: PoseWithCovarianceStamped) -> None:
        """AMCL이 알려주는 map 기준 pose를 저장합니다. 이동 중에만 옵니다."""
        pose = msg.pose.pose
        yaw = self._quaternion_to_yaw_degrees(
            pose.orientation.x,
            pose.orientation.y,
            pose.orientation.z,
            pose.orientation.w,
        )
        self.map_pose = (float(pose.position.x), float(pose.position.y), yaw)
        self.last_map_pose_time = time.monotonic()

    # ------------------------------------------------------------------
    # 상태 발행
    # ------------------------------------------------------------------
    def publish_status(self) -> None:
        """최신 정보를 앱용 /robot_status JSON으로 발행합니다(타이머 주기 실행)."""
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
        """(x, y, yaw_degree, linear_x, angular_z)를 돌려줍니다.

        위치는 AMCL(map frame)을 우선하고, 아직 없으면 /odom pose를 fallback으로
        씁니다. 속도는 항상 /odom.twist에서 읽습니다.
        """
        # 발행이 끊긴 /odom의 마지막 속도를 계속 쓰면 로봇이 멈춘 뒤에도 moving으로
        # 남을 수 있어, 만료된 odom은 아예 없는 것으로 취급합니다.
        odom_fresh = self._odom_fresh()
        linear_x = 0.0
        angular_z = 0.0
        if odom_fresh and self.latest_odom is not None:
            twist = self.latest_odom.twist.twist
            linear_x = float(twist.linear.x)
            angular_z = float(twist.angular.z)

        if self._nav2_pose_available() and self.map_pose is not None:
            x, y, yaw = self.map_pose
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
        """AMCL pose를 확보했는지로 Nav2 위치 추정 활성 여부를 판단합니다.

        AMCL은 이동 중에만 발행하므로 **정지 중에는 나이로 실효시키지 않는다** —
        마지막 값이 그대로 유효하다. 움직이는 중인데 갱신이 끊겼을 때만
        (AMCL 사망·위치 상실) 미확보로 본다. 초기위치를 아직 안 잡은 Nav2
        재시작 감지는 앱의 초기위치 입구 생사 확인이 맡는다(2026-08-31 수리).
        """
        if self.map_pose is None or self.last_map_pose_time is None:
            return False
        if not self._robot_moving():
            return True
        timeout_sec = float(self.get_parameter("nav2_data_timeout_sec").value)
        return (time.monotonic() - self.last_map_pose_time) <= timeout_sec

    def _robot_moving(self) -> bool:
        """odom 속도로 '지금 움직이는 중'을 판단합니다(_status와 같은 임계값)."""
        if not self._odom_fresh() or self.latest_odom is None:
            return False
        twist = self.latest_odom.twist.twist
        linear = abs(float(twist.linear.x))
        angular = abs(float(twist.angular.z))
        return (
            linear >= float(self.get_parameter("moving_linear_threshold").value)
            or angular >= float(self.get_parameter("moving_angular_threshold").value)
        )

    def _odom_fresh(self) -> bool:
        """/odom이 만료 시간 안에 갱신되고 있는지 확인합니다."""
        if self.latest_odom is None or self.last_odom_time is None:
            return False
        timeout_sec = float(self.get_parameter("odom_timeout_sec").value)
        return (time.monotonic() - self.last_odom_time) <= timeout_sec

    def _is_navigation_active(self) -> bool:
        """goal 종료 이벤트를 놓쳤을 때 moving에 갇히지 않도록 만료를 적용합니다.

        Mission Manager는 종료 이벤트를 빠짐없이 발행하지만, 메시지 유실이나 이 노드의
        재시작(기본 QoS는 VOLATILE이라 과거 이벤트를 다시 받지 못함)으로 시작 이벤트만
        관측된 채 남을 수 있어 안전망을 둡니다. 만료 뒤에도 실제로 움직이고 있으면
        속도 기준으로 moving 판정이 유지됩니다.
        """
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
        """누적된 진단 항목 중 min_level(ERROR=2) 이상인 사유를 하나 고릅니다.

        만료된 항목은 먼저 버립니다. 조건을 만족하는 항목이 여럿이면 key 사전순으로
        하나를 고정해 고릅니다 — 도착 순서에 따라 표시 문구가 바뀌지 않게 하기 위해서입니다.
        """
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

    # ------------------------------------------------------------------
    # 오류 사유 원천 (error_source 파라미터가 고릅니다)
    # ------------------------------------------------------------------
    def _setup_paused_source(self) -> None:
        """/vica/robot_state의 is_paused를 일시정지 판정의 정본으로 삼습니다.

        [2026-08-21] 종전에는 /vica_goal_event의 goal_paused 한 번만 보고 판단했습니다.
        그런데 그 이벤트를 발행하는 mission_manager_node._cancel_nav가 Nav2 취소 응답을
        기다리다 멈추면 이벤트가 아예 나가지 않아, 앱의 '다시 출발' 버튼이 뜰 때도 있고
        안 뜰 때도 있었습니다. 앱을 나중에 켠 경우에도 지나간 이벤트는 받을 수 없습니다.

        Mission Manager는 같은 사실을 RobotState.is_paused로 1 Hz 상시 발행하고
        있었습니다(mission_manager_node._publish_robot_state). 이벤트는 빠르고 상태는
        확실하므로 둘을 함께 씁니다 — 이벤트가 오면 즉시 바뀌고, 놓쳤어도 1초 뒤에
        상태가 바로잡습니다.

        RobotState에는 목적지 이름이 없으므로 current_goal은 종전대로 goal 이벤트가
        담당합니다. 이 구독은 is_paused 하나만 대체합니다.

        _setup_health_source와 같은 이유로 import를 감쌉니다. vica_interfaces를 빌드하지
        않은 환경에서 이 노드가 기동 실패하면 안 됩니다.
        """
        try:
            from vica_interfaces.msg import RobotState
        except ImportError as exc:
            self.get_logger().warn(
                f"vica_interfaces/RobotState import 실패: {exc}. "
                "일시정지 표시는 goal 이벤트에만 의존합니다."
            )
            return

        self.create_subscription(
            RobotState, "/vica/robot_state", self.handle_robot_state, 10
        )
        self.get_logger().info("/vica/robot_state 구독: is_paused 정본")

    def handle_robot_state(self, msg) -> None:
        """Mission Manager가 1 Hz로 알려주는 일시정지 여부를 반영합니다."""
        self.navigation_paused = bool(msg.is_paused)

    def _setup_health_source(self) -> None:
        """error_source가 health일 때만 /robot/health를 구독합니다.

        RobotHealth import를 이 모드에서만 하는 이유: vica_interfaces를 빌드하지 않은
        환경에서 노드가 기동 실패하면 안 됩니다. 기본값이 diagnostics이므로 기존 배포는
        영향을 받지 않습니다.

        import에 실패하면 오류를 로그로 남기고 diagnostics 모드로 되돌립니다. 감시 표시가
        조금 나빠지는 것이 노드가 죽는 것보다 낫습니다.
        """
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
        """error_source에 따라 오류 사유 원문을 만듭니다.

        지연 필터(_stable_error_reason)는 두 모드가 공유합니다. health 모드에서도 모니터가
        간헐적으로 등급을 바꿀 수 있으므로 그 방어는 유지하는 편이 안전합니다.
        """
        if self.error_source == ERROR_SOURCE_HEALTH:
            return self._health_error_reason()
        return self._diagnostic_reason(min_level=2)

    def _health_error_reason(self) -> str:
        """/robot/health에서 오류 사유를 만듭니다.

        임계를 SEVERITY_STOP 이상으로 두는 이유: _status()가 error_reason이 있으면
        "error"를 반환합니다. WARN이나 DEGRADED로 임계를 낮추면 경고 하나로 앱 상태가
        error로 뒤집힙니다. 그 등급은 앱의 시스템 진단 화면이 따로 보여줍니다.

        만료를 적용해 모니터가 죽은 뒤 마지막 상태를 현재로 쓰지 않습니다.
        """
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
        """오류 사유에 지연을 적용해 짧은 깜빡임을 걸러냅니다.

        ERROR가 set_delay 동안 이어질 때만 오류로 확정하고, 사라진 뒤에도 clear_delay
        동안은 직전 사유를 유지합니다. 진단 누적만으로 대부분의 떨림은 사라지지만,
        발행자 자신이 ERROR를 간헐적으로 낼 때를 대비한 2차 방어입니다.
        """
        raw_reason = self._raw_error_reason()
        now = time.monotonic()
        set_delay = float(self.get_parameter("error_set_delay_sec").value)
        clear_delay = float(self.get_parameter("error_clear_delay_sec").value)

        if raw_reason:
            self._error_cleared_since = None
            if self._error_seen_since is None:
                self._error_seen_since = now
            # 이미 오류로 확정된 뒤에는 최신 사유를 그대로 반영합니다.
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
        # 목적지를 기억한 채 멈춘 상태는 그냥 대기와 구분해서 알려준다.
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
        """지도별 destinations.yaml을 읽습니다(2초 캐시).

        발행 주기가 높으므로(10Hz) 매번 파일을 읽지 않도록 map_id별로 잠시 캐시합니다.
        파일이 없거나 깨져도 상태 발행은 계속되어야 하므로 예외 시 빈 목록을 씁니다.
        """
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
