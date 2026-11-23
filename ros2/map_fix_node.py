#!/usr/bin/env python3
"""앱 '지도 수정' 요청을 받아 지도 파일을 고치고 Nav2 에 다시 읽히는 노드입니다."""

from __future__ import annotations

import json
import math
import threading
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Optional

import rclpy
from rclpy.callback_groups import MutuallyExclusiveCallbackGroup, ReentrantCallbackGroup
from rclpy.executors import ExternalShutdownException, MultiThreadedExecutor
from rclpy.node import Node
from std_msgs.msg import String

import map_fix_core as mfc

KST = timezone(timedelta(hours=9))

STATUS_STALE_SEC = 3.0
STATUS_WAIT_SEC = 1.5
SCAN_WAIT_SEC = 2.0
TF_WARMUP_SEC = 8.0
WARM_ACTIONS = {"get", "scan_check", "scan_start"}
IDLE_CLOSE_SEC = 120.0
HOUSEKEEPING_SEC = 5.0
RETRY_FIRST_SEC = 5.0
RETRY_MAX_SEC = 60.0
MAP_CONFIRM_SLACK_SEC = 0.05
SESSION_TICK_SEC = 0.5
STATE_HEARTBEAT_SEC = 2.0


def load_map_outcome(*, done: bool, error: Optional[BaseException], result_code: Optional[int],
                     timeout: float) -> tuple[bool, str, str]:
    """load_map 호출 결과를 (applied, reason, message) 로 옮깁니다."""
    if not done:
        return False, "apply_timeout", f"Nav2가 {timeout:.0f}초 안에 응답하지 않아 적용을 확인하지 못했습니다."
    if error is not None:
        return False, "apply_failed", f"Nav2가 지도를 읽지 못했습니다: {error}"
    if result_code == 0:
        return True, "", mfc.MESSAGES["done"]
    reasons = {
        1: "지도 파일을 찾지 못했습니다.",
        2: "지도 yaml의 값이 올바르지 않습니다.",
        3: "지도 그림을 읽지 못했습니다.",
    }
    detail = reasons.get(result_code, f"알 수 없는 실패({result_code}).")
    return False, "apply_failed", f"Nav2가 지도를 읽지 못했습니다. {detail}"


def warmup_wait(age_sec: float, minimum: float) -> float:
    """연 지 age_sec 인 구독에서 메시지를 기다릴 시간. 아직 발견 중이면 TF_WARMUP_SEC 까지 기다린다."""
    return max(minimum, TF_WARMUP_SEC - age_sec)


def should_publish(state: dict, last: Optional[dict], since_sec: float) -> bool:
    """진행 상태를 지금 토픽에 낼지 정합니다."""
    return last is None or state != last or since_sec >= STATE_HEARTBEAT_SEC


def ended_state(before: str, map_id: str, action: str, after: Optional[str]) -> Optional[dict]:
    """요청 하나가 세션을 끝냈으면 토픽에 한 번 낼 'done' 상태, 아니면 None."""
    if not before or after:
        return None
    return {"session": before, "map_id": map_id, "phase": "done", "reason": action}


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


DEFAULT_FOOTPRINT = "[[0.151, 0.225], [0.151, -0.225], [-0.459, -0.225], [-0.569, -0.035], [-0.569, 0.035], [-0.459, 0.225]]"


def parse_body(footprint: str, margin: float) -> tuple[tuple, float]:
    """Nav2 형식 footprint 글자 '[[x, y], ...]' 와 여유(m)."""
    points = tuple((float(x), float(y)) for x, y in json.loads(footprint))
    if len(points) < 3:
        raise ValueError(f"footprint 는 꼭짓점이 셋 이상이어야 합니다: {footprint!r}")
    return points, float(margin)


def compose_pose(a: tuple, b: tuple) -> tuple[float, float, float]:
    """평면 자세 a 위에 b 를 얹습니다(map→odom · odom→base = map→base)."""
    c, s = math.cos(a[2]), math.sin(a[2])
    yaw = a[2] + b[2]
    return a[0] + c * b[0] - s * b[1], a[1] + s * b[0] + c * b[1], math.atan2(math.sin(yaw), math.cos(yaw))


class MapFixNode(Node):
    """제공 service: /vica/map_fix (vica_interfaces/srv/MapFix)"""

    def __init__(self) -> None:
        super().__init__("vica_map_fix")

        workspace_root = Path(__file__).resolve().parents[2]
        self.declare_parameter("maps_root", str(workspace_root / "vica_ros2_ws" / "maps"))
        self.maps_root = Path(str(self.get_parameter("maps_root").value)).expanduser()
        self.declare_parameter("map_load_service", "/map_server/load_map")
        self.declare_parameter("apply_timeout_sec", 5.0)
        self.declare_parameter("robot_status_topic", "/robot_status")
        self.declare_parameter("odom_topic", "/odom")
        self.declare_parameter("scan_topic", "/scan")
        self.declare_parameter("base_frame", "base_footprint")
        self.declare_parameter("map_frame", "map")
        self.declare_parameter("odom_frame", "odom")
        self.declare_parameter("map_topic", "/map")
        self.declare_parameter("amcl_pose_topic", "/amcl_pose")
        self.declare_parameter("robot_footprint", DEFAULT_FOOTPRINT)
        self.declare_parameter("body_margin_m", 0.20)

        self._callbacks = ReentrantCallbackGroup()
        self._request_lock = threading.Lock()
        self._core_lock = threading.RLock()
        self._body = parse_body(str(self.get_parameter("robot_footprint").value),
                                float(self.get_parameter("body_margin_m").value))
        self._state_lock = threading.Lock()

        self._status: Optional[dict] = None
        self._status_at = 0.0
        self._status_event = threading.Event()
        self._status_sub = None
        self._last_request = time.monotonic()

        self._scan_sub = None
        self._odom_sub = None
        self._sensors_opened_at = 0.0
        self._tf_buffer = None
        self._tf_listener = None
        self._scan_msg = None
        self._scan_event = threading.Event()
        self._session_timer = None
        self._last_state: Optional[dict] = None
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
        self._load_map_type = None
        self._load_map_tried = False
        self._load_map_made_at = 0.0
        self._apply_cond = threading.Condition()
        self._map_loaded_wall = 0.0
        self._map_sub = None
        self._retry_at = 0.0
        self._retry_gap = RETRY_FIRST_SEC
        self._amcl_sub = None
        self._amcl_cov = None
        self._setup_service()
        self._housekeeping_timer = self.create_timer(
            HOUSEKEEPING_SEC, self._housekeeping, callback_group=MutuallyExclusiveCallbackGroup())
        self._tick_group = MutuallyExclusiveCallbackGroup()
        self.get_logger().info(f"vica_map_fix 시작: maps_root={self.maps_root}")

    def _setup_service(self) -> None:
        """import 를 감싸는 이유는 keepout_map_node._setup_services 와 같습니다 —"""
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
        self._load_map_made_at = time.monotonic()
        from nav_msgs.msg import OccupancyGrid
        from rclpy.qos import DurabilityPolicy, QoSProfile, ReliabilityPolicy

        latched = QoSProfile(depth=1, reliability=ReliabilityPolicy.RELIABLE,
                             durability=DurabilityPolicy.TRANSIENT_LOCAL)
        self._map_sub = self.create_subscription(
            OccupancyGrid, str(self.get_parameter("map_topic").value), self._on_map, latched,
            callback_group=self._callbacks)

    def _on_map(self, msg) -> None:
        stamp = msg.info.map_load_time
        loaded = float(stamp.sec) + float(stamp.nanosec) * 1e-9
        with self._apply_cond:
            if loaded > self._map_loaded_wall:
                self._map_loaded_wall = loaded
            self._apply_cond.notify_all()

    def handle_request(self, request, response):
        with self._request_lock:
            self._last_request = time.monotonic()
            if not self._load_map_tried:
                self._load_map_tried = True
                self._setup_load_map_client()
            self._open_status()
            if request.action in WARM_ACTIONS:
                self._open_sensors()
            with self._core_lock:
                before = self.core.session.session_id if self.core.session else ""
                answer = self.core.handle(request.map_id, request.action, request.args_json)
                done = ended_state(before, request.map_id, request.action,
                                   self.core.session.session_id if self.core.session else None)
                if done is not None:
                    self._publish_state(done, force=True)
                    self._last_state = None
            if not answer[0] or answer[1]:
                self.get_logger().info(
                    f"map_fix {request.action}({request.map_id}): accepted={answer[0]} reason={answer[1]}")
            return fill_response(response, answer)

    def _open_status(self) -> None:
        if self._status_sub is None:
            self._status_event.clear()
            self._status_sub = self.create_subscription(
                String, str(self.get_parameter("robot_status_topic").value),
                self._on_robot_status, 10, callback_group=self._callbacks)
        if self._status_now() is None:
            self._status_event.wait(STATUS_WAIT_SEC)

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
        try:
            self._housekeeping_once()
        except Exception as error:  # noqa: BLE001 - 타이머 예외가 spin 까지 올라가면 노드가 끝납니다.
            self.get_logger().error(f"정리 중 예외: {error!r}")

    def _retry_once(self) -> None:
        """확인 못 한 적용을 다시 겁니다. Nav2 응답은 **잠금 밖에서** 기다립니다 — 11-19 실기에서는 잠금을"""
        if time.monotonic() < self._retry_at:
            return
        with self._core_lock:
            map_id = self.core.retry_target()
        if not map_id:
            self._retry_gap = RETRY_FIRST_SEC
            return
        outcome = self._apply(map_id)
        with self._core_lock:
            self.core.finish_retry(map_id, outcome)
            still = self.core.pending_apply == map_id
        self._retry_gap = min(self._retry_gap * 2, RETRY_MAX_SEC) if still else RETRY_FIRST_SEC
        self._retry_at = time.monotonic() + self._retry_gap

    def _housekeeping_once(self) -> None:
        self._retry_once()
        idle = time.monotonic() - self._last_request
        if self._scan_sub is not None and self.core.session is None and idle > IDLE_CLOSE_SEC:
            self._close_sensors()
        if self._status_sub is not None and self.core.session is None and idle > IDLE_CLOSE_SEC \
                and not self.core.pending_apply:
            self.destroy_subscription(self._status_sub)
            self._status_sub = None
            with self._state_lock:
                self._status = None

    def _set_sensing(self, on: bool) -> None:
        if on:
            self._open_sensors()
            if self._session_timer is None:
                self._session_timer = self.create_timer(
                    SESSION_TICK_SEC, self._on_session_tick, callback_group=self._tick_group)

    def _open_sensors(self) -> None:
        if self._scan_sub is not None:
            return
        import tf2_ros
        from nav_msgs.msg import Odometry
        from rclpy.qos import qos_profile_sensor_data
        from sensor_msgs.msg import LaserScan

        self._tf_buffer = tf2_ros.Buffer()
        self._tf_listener = tf2_ros.TransformListener(self._tf_buffer, self)
        self._sensors_opened_at = time.monotonic()
        self._scan_event.clear()
        self._scan_msg = None
        self._scan_sub = self.create_subscription(
            LaserScan, str(self.get_parameter("scan_topic").value), self._on_scan,
            qos_profile_sensor_data, callback_group=self._callbacks)
        self._odom_sub = self.create_subscription(
            Odometry, str(self.get_parameter("odom_topic").value), self._on_odom,
            qos_profile_sensor_data, callback_group=self._callbacks)
        from geometry_msgs.msg import PoseWithCovarianceStamped
        from rclpy.qos import DurabilityPolicy, QoSProfile, ReliabilityPolicy

        latched = QoSProfile(depth=1, reliability=ReliabilityPolicy.RELIABLE,
                             durability=DurabilityPolicy.TRANSIENT_LOCAL)
        self._amcl_sub = self.create_subscription(
            PoseWithCovarianceStamped, str(self.get_parameter("amcl_pose_topic").value), self._on_amcl,
            latched, callback_group=self._callbacks)

    def _close_sensors(self) -> None:
        if self._scan_sub is None:
            return
        self.destroy_subscription(self._scan_sub)
        self.destroy_subscription(self._odom_sub)
        self._scan_sub = self._odom_sub = None
        if self._amcl_sub is not None:
            self.destroy_subscription(self._amcl_sub)
            self._amcl_sub = None
        self._amcl_cov = None
        try:
            self._tf_listener.unregister()
        except AttributeError:
            pass
        self._tf_listener = None
        self._tf_buffer = None
        self._scan_msg = None

    def _lookup(self, target: str, source: str, wait: float) -> Optional[tuple[float, float, float]]:
        import tf2_ros

        buffer = self._tf_buffer
        if buffer is None:
            return None
        try:
            found = buffer.lookup_transform(
                target, source, rclpy.time.Time(), timeout=rclpy.duration.Duration(seconds=wait))
        except tf2_ros.TransformException:
            return None
        return pose_of(found.transform)

    def _scan_input(self, msg, wait: float = 0.0) -> Optional[mfc.ScanInput]:
        """스캔 한 장에 그 순간의 자세(AMCL + 오도메트리)와 라이다 자리를 붙입니다."""
        base = str(self.get_parameter("base_frame").value)
        world = str(self.get_parameter("map_frame").value)
        odom = str(self.get_parameter("odom_frame").value)
        deadline = time.monotonic() + wait

        def left() -> float:
            return max(0.0, deadline - time.monotonic())

        on_map = self._lookup(world, odom, left())
        on_odom = self._lookup(odom, base, left())
        guess = compose_pose(on_map, on_odom) if on_map is not None and on_odom is not None else None
        sensor = self._lookup(base, msg.header.frame_id, left())
        if guess is None or sensor is None:
            missing = [f"{a}→{b}" for ok, a, b in ((on_map, world, odom), (on_odom, odom, base),
                                                   (sensor, base, msg.header.frame_id)) if ok is None]
            buffer = self._tf_buffer
            if buffer is not None:
                parts = {f"{a}→{b}": buffer.can_transform(a, b, rclpy.time.Time())
                         for a, b in ((world, odom), (odom, base), (world, base))}
                frames = buffer.all_frames_as_string().count("Frame ")
                self.get_logger().warn(f"TF 진단: 구독 연 지 {time.monotonic() - self._sensors_opened_at:.1f} s · "
                                       f"프레임 {frames}개 · {parts}", throttle_duration_sec=5.0)
            self.get_logger().warn(f"자세를 못 얻음 — TF {', '.join(missing)} 없음(초기 위치·Nav2 확인)",
                                   throttle_duration_sec=5.0)
            return None
        import map_fix_scan as scan

        ranges = scan.mask_body(msg.ranges, msg.angle_min, msg.angle_increment, sensor, *self._body)
        cov = self._amcl_cov
        sigma = scan.axis_sigmas(cov, guess[2]) if cov is not None else None
        return mfc.ScanInput(ranges, msg.angle_min, msg.angle_increment, guess, sensor, sigma)

    def _on_scan(self, msg) -> None:
        self._scan_msg = msg
        self._scan_event.set()
        if self.core.session is not None:
            taken = self._scan_input(msg)
            with self._core_lock:
                self.core.feed_scan(taken)

    def _on_amcl(self, msg) -> None:
        self._amcl_cov = tuple(msg.pose.covariance)

    def _on_odom(self, msg) -> None:
        twist = msg.twist.twist
        with self._core_lock:
            self.core.feed_motion(float(twist.linear.x), float(twist.angular.z))

    def _grab_scan(self) -> Optional[mfc.ScanInput]:
        """scan_check 용 — 센서를 잠깐 열어 스캔 한 장을 받습니다."""
        self._open_sensors()
        age = time.monotonic() - self._sensors_opened_at
        scan_wait = warmup_wait(age, SCAN_WAIT_SEC)
        if not self._scan_event.wait(scan_wait) or self._scan_msg is None:
            self.get_logger().warn(f"{scan_wait:.0f}초 안에 스캔을 못 받음 — /scan 확인")
            return None
        return self._scan_input(self._scan_msg, warmup_wait(time.monotonic() - self._sensors_opened_at, 0.5))

    def _publish_state(self, state: dict, force: bool = False) -> None:
        now = time.monotonic()
        if force or should_publish(state, self._last_state, now - self._last_state_at):
            self.state_publisher.publish(String(data=json.dumps(state, ensure_ascii=False)))
            self._last_state, self._last_state_at = state, now

    def _on_session_tick(self) -> None:
        try:
            self._session_tick_once()
        except Exception as error:  # noqa: BLE001 - 타이머 예외가 spin 까지 올라가면 노드가 끝납니다.
            self.get_logger().error(f"부분 스캔 진행 중 예외: {error!r}")

    def _session_tick_once(self) -> None:
        with self._core_lock:
            state = self.core.tick()
            if state is not None:
                self._publish_state(state)
            if self.core.session is None:
                self._last_state = None
                if self._session_timer is not None:
                    self._session_timer.cancel()
                    self.destroy_timer(self._session_timer)
                    self._session_timer = None

    def _apply(self, map_id: str) -> tuple[bool, str, str]:
        """map_server 에 load_map 을 걸어 지금 주행에 반영합니다. Nav2 재시작이 아닙니다 —"""
        client = self._load_map_client
        fresh = time.monotonic() - self._load_map_made_at < 2.0
        if client is None or not (client.service_is_ready()
                                  or (fresh and client.wait_for_service(timeout_sec=1.0))):
            return False, "no_nav2", "Nav2가 실행되면 적용됩니다."
        request = self._load_map_type.Request()
        request.map_url = str(self.maps_root / f"{map_id}.yaml")
        sent_wall = time.time()
        future = client.call_async(request)

        def wake(_future) -> None:
            with self._apply_cond:
                self._apply_cond.notify_all()

        future.add_done_callback(wake)

        def by_map() -> bool:
            return self._map_loaded_wall >= sent_wall - MAP_CONFIRM_SLACK_SEC

        timeout = float(self.get_parameter("apply_timeout_sec").value)
        with self._apply_cond:
            self._apply_cond.wait_for(lambda: future.done() or by_map(), timeout)
        if not future.done():
            remover = getattr(client, "remove_pending_request", None)
            if remover is not None:
                remover(future)
            if by_map():
                self.get_logger().info(f"지도 다시 읽힘(/map 으로 확인 — 응답은 아직 없음): {map_id}")
                return load_map_outcome(done=True, error=None, result_code=0, timeout=timeout)
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


def spin_forgiving(executor, should_stop=lambda: False) -> None:
    """실행기를 돌리되, 닫힌 구독의 메시지를 꺼내다 난 InvalidHandle 은 넘깁니다."""
    from rclpy.exceptions import InvalidHandle

    while rclpy.ok() and not should_stop():
        try:
            executor.spin_once(timeout_sec=0.5)
        except InvalidHandle:
            continue


def main() -> None:
    rclpy.init()
    node = MapFixNode()
    executor = MultiThreadedExecutor()
    executor.add_node(node)
    try:
        spin_forgiving(executor)
    except (KeyboardInterrupt, ExternalShutdownException):
        pass
    finally:
        executor.remove_node(node)
        node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == "__main__":
    main()
