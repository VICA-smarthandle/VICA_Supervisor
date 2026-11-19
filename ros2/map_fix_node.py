#!/usr/bin/env python3
"""앱 '지도 수정' 요청을 받아 지도 파일을 고치고 Nav2 에 다시 읽히는 노드입니다.

설계서: 루트 docs/superpowers/specs/2026-11-18-map-fix-erase-partial-scan-design.md

연결 흐름:
    Flutter 앱
        -> /vica/map_fix (MapFix)            지우기 · 부분 스캔 · 되돌리기
        -> map_fix_node
        -> maps/<map_id>.{pgm,png}           (백업: maps/.fix_backup/<map_id>/)
        -> <map_server>/load_map             Nav2 재시작 없이 AMCL·costmap 이 새 지도를 받습니다
    map_fix_node -> /vica/map_fix/state      부분 스캔 진행(맞춤 → 물러나기 → 스캔 → 미리보기)

판단은 map_fix_core.py(잠금·순서)와 그 아래 순수 모듈들에 있습니다. 이 파일은 ROS 배선만
합니다 — keepout_map_node.py 와 keepout_mask.py 의 관계와 같습니다.

**쉬는 동안 가볍게 둡니다**(2026-11-19 사용자 결정으로 파이썬 유지, 대신 가볍게).
지도 수정은 가끔 하는 일입니다. 그래서
  - numpy·scipy·tf2 와 스캔 계산 모듈은 맨 위에서 불러오지 않고 요청이 올 때 처음 import 하고,
  - /robot_status 는 요청이 온 뒤 한동안만, /scan·/odom·TF 는 부분 스캔 동안만 구독합니다.
아무 요청이 없을 때 이 노드는 서비스 하나를 열어 둔 채 5초에 한 번 깨어날 뿐입니다.
"""

from __future__ import annotations

import json
import math
import threading
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Optional

import rclpy
from rclpy.callback_groups import ReentrantCallbackGroup
from rclpy.executors import ExternalShutdownException, MultiThreadedExecutor
from rclpy.node import Node
from std_msgs.msg import String

import map_fix_core as mfc

KST = timezone(timedelta(hours=9))

# /robot_status 는 0.5초마다 옵니다. 이보다 오래 안 오면 상태 노드가 멈춘 것으로 보고 잠급니다.
STATUS_STALE_SEC = 3.0
# 요청이 왔을 때 첫 상태를 기다리는 시간.
STATUS_WAIT_SEC = 1.5
# scan_check 가 스캔 한 장을 기다리는 시간.
SCAN_WAIT_SEC = 2.0
# 마지막 요청 뒤 이만큼 지나면 /robot_status 구독을 닫습니다.
IDLE_CLOSE_SEC = 120.0
HOUSEKEEPING_SEC = 5.0
SESSION_TICK_SEC = 0.5   # 세션을 0.5초마다 한 걸음 진행합니다
STATE_HEARTBEAT_SEC = 2.0   # 상태가 그대로일 때 토픽을 다시 내는 간격(늦게 연 화면용)


# ---------------------------------------------------------------------------
# ROS 와 맞닿는 작은 변환 (노드 없이 시험합니다)
# ---------------------------------------------------------------------------


def load_map_outcome(*, done: bool, error: Optional[BaseException], result_code: Optional[int],
                     timeout: float) -> tuple[bool, str, str]:
    """load_map 호출 결과를 (applied, reason, message) 로 옮깁니다."""
    if not done:
        return False, "apply_timeout", f"Nav2가 {timeout:.0f}초 안에 응답하지 않아 적용을 확인하지 못했습니다."
    if error is not None:
        return False, "apply_failed", f"Nav2가 지도를 읽지 못했습니다: {error}"
    if result_code == 0:   # nav2_msgs/srv/LoadMap.Response.RESULT_SUCCESS
        return True, "", mfc.MESSAGES["done"]
    reasons = {
        1: "지도 파일을 찾지 못했습니다.",
        2: "지도 yaml 의 값이 올바르지 않습니다.",
        3: "지도 그림을 읽지 못했습니다.",
    }
    detail = reasons.get(result_code, f"알 수 없는 실패({result_code}).")
    return False, "apply_failed", f"Nav2가 지도를 읽지 못했습니다. {detail}"


def should_publish(state: dict, last: Optional[dict], since_sec: float) -> bool:
    """진행 상태를 지금 토픽에 낼지 정합니다.

    바뀌었으면 바로 내고, 그대로면 STATE_HEARTBEAT_SEC 마다 한 번만 냅니다. 미리보기는 최대
    5분이고 상태에 변경된 칸 목록(최대 2000칸)이 실려, 0.5초마다 다시 내면 와이파이에 무겁습니다.
    """
    return last is None or state != last or since_sec >= STATE_HEARTBEAT_SEC


def fresh_status(status: Optional[dict], age_sec: float) -> Optional[dict]:
    """너무 오래된 상태는 없는 것으로 칩니다."""
    if status is None or age_sec > STATUS_STALE_SEC:
        return None
    return status


def fill_response(response: Any, answer: tuple) -> Any:
    accepted, reason, message, result = answer
    response.accepted = bool(accepted)
    response.reason = str(reason)
    response.message = str(message)
    response.result_json = json.dumps(result, ensure_ascii=False)
    return response


def yaw_of(rotation: Any) -> float:
    return math.atan2(
        2.0 * (rotation.w * rotation.z + rotation.x * rotation.y),
        1.0 - 2.0 * (rotation.y * rotation.y + rotation.z * rotation.z),
    )


def pose_of(transform: Any) -> tuple[float, float, float]:
    """geometry_msgs/Transform 을 평면 자세 (x, y, yaw) 로."""
    return transform.translation.x, transform.translation.y, yaw_of(transform.rotation)


# ---------------------------------------------------------------------------
# 노드
# ---------------------------------------------------------------------------


class MapFixNode(Node):
    """제공 service: /vica/map_fix (vica_interfaces/srv/MapFix)
    발행 topic:   /vica/map_fix/state (std_msgs/String JSON, 부분 스캔 세션이 있는 동안 2 Hz)
    필요할 때만 구독: /robot_status · /scan · /odom · TF
    호출 service: <map_load_service> (nav2_msgs/srv/LoadMap)
    """

    def __init__(self) -> None:
        super().__init__("vica_map_fix")

        workspace_root = Path(__file__).resolve().parents[2]
        self.declare_parameter("maps_root", str(workspace_root / "vica_ros2_ws" / "maps"))
        self.maps_root = Path(str(self.get_parameter("maps_root").value)).expanduser()
        # nav2_map_server::MapServer 가 여는 서비스입니다. 노드 이름이 앞에 붙습니다.
        self.declare_parameter("map_load_service", "/map_server/load_map")
        self.declare_parameter("apply_timeout_sec", 10.0)
        self.declare_parameter("robot_status_topic", "/robot_status")
        self.declare_parameter("odom_topic", "/odom")
        self.declare_parameter("scan_topic", "/scan")
        self.declare_parameter("base_frame", "base_footprint")
        self.declare_parameter("map_frame", "map")

        self._callbacks = ReentrantCallbackGroup()
        self._request_lock = threading.Lock()     # 요청은 한 번에 하나
        # 스캔 콜백·세션 타이머·요청 처리가 서로 다른 스레드에서 세션을 건드립니다. core 는 이 잠금
        # 안에서만 부릅니다. 기다리는 일(스캔 한 장·load_map 응답)의 신호는 잠금 밖에서 세웁니다.
        self._core_lock = threading.RLock()
        self._state_lock = threading.Lock()

        self._status: Optional[dict] = None
        self._status_at = 0.0
        self._status_event = threading.Event()
        self._status_sub = None
        self._last_request = time.monotonic()

        self._scan_sub = None
        self._odom_sub = None
        self._tf_buffer = None
        self._tf_listener = None
        self._scan_msg = None
        self._scan_event = threading.Event()
        self._session_timer = None
        self._last_state: Optional[dict] = None   # 마지막으로 토픽에 낸 진행 상태
        self._last_state_at = 0.0

        self.core = mfc.MapFixCore(
            self.maps_root,
            apply=self._apply,
            status=self._status_now,
            now=lambda: datetime.now(KST),
            clock=time.monotonic,
            grab_scan=self._grab_scan,
            set_sensing=self._set_sensing,
            log=lambda text: self.get_logger().warn(text),
        )

        self.state_publisher = self.create_publisher(String, "/vica/map_fix/state", 10)
        self._load_map_client = None
        self._setup_load_map_client()
        self._setup_service()
        self.create_timer(HOUSEKEEPING_SEC, self._housekeeping, callback_group=self._callbacks)
        self.get_logger().info(f"vica_map_fix 시작: maps_root={self.maps_root}")

    # ------------------------------------------------------------------
    # 기동
    # ------------------------------------------------------------------

    def _setup_service(self) -> None:
        """import 를 감싸는 이유는 keepout_map_node._setup_services 와 같습니다 —
        vica_interfaces 를 빌드하지 않은 환경에서 이 노드가 죽으면 앱 유닛 전체가 흔들립니다."""
        try:
            from vica_interfaces.srv import MapFix
        except ImportError as error:
            self.get_logger().error(
                f"vica_interfaces/MapFix import 실패: {error}. "
                "지도 수정 서비스를 열지 않습니다. colcon build 가 필요합니다."
            )
            return
        self.create_service(MapFix, "/vica/map_fix", self.handle_request, callback_group=self._callbacks)
        self.get_logger().info("/vica/map_fix 준비 완료")

    def _setup_load_map_client(self) -> None:
        try:
            from nav2_msgs.srv import LoadMap
        except ImportError as error:
            self.get_logger().warn(f"nav2_msgs/LoadMap import 실패: {error}. 저장은 되지만 Nav2 반영은 못 합니다.")
            return
        self._load_map_type = LoadMap
        self._load_map_client = self.create_client(
            LoadMap, str(self.get_parameter("map_load_service").value), callback_group=self._callbacks)

    # ------------------------------------------------------------------
    # 요청
    # ------------------------------------------------------------------

    def handle_request(self, request, response):
        with self._request_lock:
            self._last_request = time.monotonic()
            self._open_status()
            with self._core_lock:
                answer = self.core.handle(request.map_id, request.action, request.args_json)
            if not answer[0] or answer[1]:
                self.get_logger().info(
                    f"map_fix {request.action}({request.map_id}): accepted={answer[0]} reason={answer[1]}")
            return fill_response(response, answer)

    # ------------------------------------------------------------------
    # 로봇 상태 (요청이 온 뒤 한동안만 구독)
    # ------------------------------------------------------------------

    def _open_status(self) -> None:
        if self._status_sub is None:
            self._status_event.clear()
            self._status_sub = self.create_subscription(
                String, str(self.get_parameter("robot_status_topic").value),
                self._on_robot_status, 10, callback_group=self._callbacks)
        if self._status_now() is None:
            self._status_event.wait(STATUS_WAIT_SEC)   # 다른 스레드가 콜백을 돌립니다

    def _on_robot_status(self, msg: String) -> None:
        try:
            payload = json.loads(msg.data)
        except (ValueError, TypeError):
            return
        if isinstance(payload, dict):
            with self._state_lock:
                self._status, self._status_at = payload, time.monotonic()
            self._status_event.set()

    def _status_now(self) -> Optional[dict]:
        with self._state_lock:
            return fresh_status(self._status, time.monotonic() - self._status_at)

    def _housekeeping(self) -> None:
        with self._core_lock:
            self.core.retry_pending()
        idle = time.monotonic() - self._last_request
        if self._status_sub is not None and self.core.session is None and idle > IDLE_CLOSE_SEC \
                and not self.core.pending_apply:
            self.destroy_subscription(self._status_sub)
            self._status_sub = None
            with self._state_lock:
                self._status = None

    # ------------------------------------------------------------------
    # 스캔 · 속도 · TF (부분 스캔 동안만)
    # ------------------------------------------------------------------

    def _set_sensing(self, on: bool) -> None:
        if on:
            self._open_sensors()
            if self._session_timer is None:
                self._session_timer = self.create_timer(
                    SESSION_TICK_SEC, self._on_session_tick, callback_group=self._callbacks)
        else:
            self._close_sensors()

    def _open_sensors(self) -> None:
        if self._scan_sub is not None:
            return
        import tf2_ros
        from nav_msgs.msg import Odometry
        from rclpy.qos import qos_profile_sensor_data
        from sensor_msgs.msg import LaserScan

        self._tf_buffer = tf2_ros.Buffer()
        self._tf_listener = tf2_ros.TransformListener(self._tf_buffer, self)
        self._scan_event.clear()
        self._scan_msg = None
        # rplidar 는 sensor_data(BEST_EFFORT)로 냅니다. RELIABLE 로 구독하면 한 건도 안 옵니다.
        self._scan_sub = self.create_subscription(
            LaserScan, str(self.get_parameter("scan_topic").value), self._on_scan,
            qos_profile_sensor_data, callback_group=self._callbacks)
        self._odom_sub = self.create_subscription(
            Odometry, str(self.get_parameter("odom_topic").value), self._on_odom,
            qos_profile_sensor_data, callback_group=self._callbacks)

    def _close_sensors(self) -> None:
        if self._scan_sub is None:
            return
        self.destroy_subscription(self._scan_sub)
        self.destroy_subscription(self._odom_sub)
        self._scan_sub = self._odom_sub = None
        try:
            self._tf_listener.unregister()
        except AttributeError:
            pass   # tf2_ros 버전에 unregister 가 없으면 참조 해제로 충분합니다
        self._tf_listener = None
        self._tf_buffer = None
        self._scan_msg = None

    def _lookup(self, target: str, source: str) -> Optional[tuple[float, float, float]]:
        import tf2_ros

        buffer = self._tf_buffer
        if buffer is None:
            return None
        try:
            found = buffer.lookup_transform(
                target, source, rclpy.time.Time(), timeout=rclpy.duration.Duration(seconds=0.5))
        except tf2_ros.TransformException:
            return None
        return pose_of(found.transform)

    def _scan_input(self, msg) -> Optional[mfc.ScanInput]:
        """스캔 한 장에 그 순간의 자세(AMCL + 오도메트리)와 라이다 자리를 붙입니다."""
        base = str(self.get_parameter("base_frame").value)
        guess = self._lookup(str(self.get_parameter("map_frame").value), base)
        sensor = self._lookup(base, msg.header.frame_id)
        if guess is None or sensor is None:
            return None
        return mfc.ScanInput(msg.ranges, msg.angle_min, msg.angle_increment, guess, sensor)

    def _on_scan(self, msg) -> None:
        self._scan_msg = msg
        self._scan_event.set()
        if self.core.session is not None:
            taken = self._scan_input(msg)
            with self._core_lock:
                self.core.feed_scan(taken)

    def _on_odom(self, msg) -> None:
        twist = msg.twist.twist
        with self._core_lock:
            self.core.feed_motion(float(twist.linear.x), float(twist.angular.z))

    def _grab_scan(self) -> Optional[mfc.ScanInput]:
        """scan_check 용 — 센서를 잠깐 열어 스캔 한 장을 받습니다."""
        opened_here = self._scan_sub is None
        self._open_sensors()
        try:
            if not self._scan_event.wait(SCAN_WAIT_SEC) or self._scan_msg is None:
                return None
            return self._scan_input(self._scan_msg)
        finally:
            if opened_here and self.core.session is None:
                self._close_sensors()

    def _on_session_tick(self) -> None:
        with self._core_lock:
            state = self.core.tick()
            finished = self.core.session is None
        now = time.monotonic()
        if state is not None and should_publish(state, self._last_state, now - self._last_state_at):
            self.state_publisher.publish(String(data=json.dumps(state, ensure_ascii=False)))
            self._last_state, self._last_state_at = state, now
        if finished:
            self._last_state = None   # 다음 세션의 첫 상태는 바로 냅니다
        if finished and self._session_timer is not None:
            self._session_timer.cancel()
            self.destroy_timer(self._session_timer)
            self._session_timer = None
            self._close_sensors()

    # ------------------------------------------------------------------
    # Nav2 반영
    # ------------------------------------------------------------------

    def _apply(self, map_id: str) -> tuple[bool, str, str]:
        """map_server 에 load_map 을 걸어 지금 주행에 반영합니다. Nav2 재시작이 아닙니다 —
        MapServer 가 새 yaml 을 읽어 /map 을 다시 발행하고 AMCL 과 costmap 이 받아 갑니다."""
        client = self._load_map_client
        if client is None or not client.service_is_ready():
            return False, "no_nav2", "Nav2가 실행되면 적용됩니다."
        request = self._load_map_type.Request()
        request.map_url = str(self.maps_root / f"{map_id}.yaml")
        future = client.call_async(request)
        done = threading.Event()
        future.add_done_callback(lambda _: done.set())
        timeout = float(self.get_parameter("apply_timeout_sec").value)
        if not done.wait(timeout):
            return load_map_outcome(done=False, error=None, result_code=None, timeout=timeout)
        try:
            result = future.result()
        except Exception as error:  # noqa: BLE001 - 원인을 그대로 사람에게 보입니다.
            return load_map_outcome(done=True, error=error, result_code=None, timeout=timeout)
        code = None if result is None else int(result.result)
        outcome = load_map_outcome(done=True, error=None, result_code=code, timeout=timeout)
        if outcome[0]:
            self.get_logger().info(f"지도 다시 읽힘: {map_id}")
        else:
            self.get_logger().error(f"지도 다시 읽히기 실패({map_id}): {outcome[2]}")
        return outcome


def main() -> None:
    rclpy.init()
    node = MapFixNode()
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
