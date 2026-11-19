"""map_fix_node 시험입니다.

    source /opt/ros/humble/setup.bash
    python3 -m pytest -q VICA_Supervisor/ros2/test_map_fix_node.py

노드를 띄우지 않습니다(rclpy.init 을 부르지 않아 로봇의 ROS 그래프에 붙지 않습니다). 요청을
어떻게 처리하는지는 test_map_fix_core.py 가 봅니다 — 여기서는 ROS 와 맞닿는 작은 변환들과
"쉬는 동안 가볍다"는 약속만 봅니다.
"""

from __future__ import annotations

import importlib.util
import json
import math
import os
import subprocess
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

pytest.importorskip("rclpy")  # 노드 모듈이 rclpy 를 import 한다

import map_fix_node as node  # noqa: E402


def test_load_map_outcome_table():
    assert node.load_map_outcome(done=True, error=None, result_code=0, timeout=10.0)[:2] == (True, "")

    applied, reason, message = node.load_map_outcome(done=False, error=None, result_code=None, timeout=10.0)
    assert (applied, reason) == (False, "apply_timeout") and "10초" in message

    failed = node.load_map_outcome(done=True, error=RuntimeError("boom"), result_code=None, timeout=10.0)
    assert failed[:2] == (False, "apply_failed") and "boom" in failed[2]
    for code in (1, 2, 3, 9, None):
        assert node.load_map_outcome(done=True, error=None, result_code=code, timeout=10.0)[:2] == (False, "apply_failed")


def test_fresh_status_is_kept_and_stale_status_is_dropped():
    status = {"status": "waiting", "dialog_state": "idle"}
    assert node.fresh_status(status, age_sec=0.4) == status
    assert node.fresh_status(status, age_sec=node.STATUS_STALE_SEC + 0.1) is None   # 상태 노드가 멈춘 것
    assert node.fresh_status(None, age_sec=0.0) is None


def test_state_is_published_on_change_and_then_only_as_a_heartbeat():
    """미리보기 동안(최대 5분) 같은 상태를 0.5초마다 다시 보내지 않습니다 — 변경된 칸 목록이 실려 무겁습니다."""
    preview = {"session": "s1", "phase": "preview", "cells": [[1.0, 2.0, 1]]}
    assert node.should_publish(preview, None, since_sec=0.0)                    # 처음
    assert not node.should_publish(dict(preview), preview, since_sec=0.5)      # 그대로
    assert not node.should_publish(dict(preview), preview, since_sec=node.STATE_HEARTBEAT_SEC - 0.1)
    assert node.should_publish(dict(preview), preview, since_sec=node.STATE_HEARTBEAT_SEC)   # 늦게 연 화면용
    # 단계·남은 초가 바뀌면 기다리지 않고 바로 보냅니다.
    assert node.should_publish({**preview, "phase": "done"}, preview, since_sec=0.5)
    counting = {"session": "s1", "phase": "step_back", "remaining_s": 3}
    assert node.should_publish({**counting, "remaining_s": 2}, counting, since_sec=0.5)
    # 화면이 첫 진행을 기다리는 시간(앱 5초)보다 짧아야 합니다.
    assert node.STATE_HEARTBEAT_SEC <= 2.0


def test_a_request_that_ends_the_session_publishes_done_once():
    """적용·버리기·중지로 세션이 끝나면 'done' 을 한 번 냅니다. 다른 기기나 응답을 놓친 앱이
    미리보기를 쥐고 남지 않게 합니다(11-19 독립 검토 4)."""
    done = node.ended_state("s1", "vica_map_0630", "scan_apply", None)
    assert done == {"session": "s1", "map_id": "vica_map_0630", "phase": "done", "reason": "scan_apply"}
    assert node.ended_state("", "vica_map_0630", "erase", None) is None          # 세션이 없었다
    assert node.ended_state("s1", "vica_map_0630", "get", "s1") is None          # 아직 있다


def test_fresh_sensors_wait_for_discovery_then_only_briefly():
    """11-19 17:4x 실기: 새로 연 TF 구독은 첫 변환까지 6~7 s 걸렸다(DDS 발견). 그래서 0.5 s 만
    기다리던 scan_check 가 초기 위치가 잡혀 있어도 늘 no_pose 였다. 연 지 8 s 안이면 그때까지 기다린다."""
    assert node.TF_WARMUP_SEC == 8.0
    assert node.warmup_wait(age_sec=0.0, minimum=0.5) == 8.0
    assert node.warmup_wait(age_sec=6.0, minimum=0.5) == 2.0
    assert node.warmup_wait(age_sec=30.0, minimum=0.5) == 0.5
    assert node.warmup_wait(age_sec=30.0, minimum=2.0) == 2.0


def test_sensors_are_warmed_by_the_panel_requests():
    """지도 수정 칸을 펼칠 때(get) 미리 열어, 스캔 화면에 들어갈 즈음엔 이미 받고 있게 합니다."""
    assert node.WARM_ACTIONS == {"get", "scan_check", "scan_start"}


def test_fill_response_writes_json():
    response = SimpleNamespace()
    node.fill_response(response, (True, "no_nav2", "Nav2가 실행되면 적용됩니다.", {"applied": False, "black": 3}))
    assert (response.accepted, response.reason, response.message) == (True, "no_nav2", "Nav2가 실행되면 적용됩니다.")
    assert json.loads(response.result_json) == {"applied": False, "black": 3}


def test_yaw_of_quaternion():
    half = 0.25
    assert math.isclose(node.yaw_of(SimpleNamespace(x=0.0, y=0.0, z=math.sin(half), w=math.cos(half))), 0.5)


def test_pose_of_transform():
    transform = SimpleNamespace(
        translation=SimpleNamespace(x=1.5, y=-2.0, z=0.0),
        rotation=SimpleNamespace(x=0.0, y=0.0, z=math.sin(0.1), w=math.cos(0.1)),
    )
    x, y, yaw = node.pose_of(transform)
    assert (x, y) == (1.5, -2.0) and math.isclose(yaw, 0.2)


def test_compose_pose_puts_the_second_pose_on_the_first():
    x, y, yaw = node.compose_pose((1.0, 0.0, math.pi / 2), (2.0, 0.0, 0.1))
    assert math.isclose(x, 1.0, abs_tol=1e-9) and math.isclose(y, 2.0) and math.isclose(yaw, math.pi / 2 + 0.1)


def _stamped(parent, child, x, yaw, sec):
    from geometry_msgs.msg import TransformStamped

    t = TransformStamped()
    t.header.frame_id, t.child_frame_id = parent, child
    t.header.stamp.sec, t.header.stamp.nanosec = int(sec), int((sec % 1) * 1e9)
    t.transform.translation.x = x
    t.transform.rotation.z, t.transform.rotation.w = math.sin(yaw / 2), math.cos(yaw / 2)
    return t


def test_pose_is_found_while_amcl_stamps_map_to_odom_in_the_future():
    """11-19 실기: 센서를 연 뒤 첫 scan_check 가 no_pose. AMCL 은 map→odom 을 transform_tolerance
    (1.0 s) 만큼 미래 시각으로 낸다. 그 한 장뿐이면 두 변환이 다 와 있어도 map→base_footprint 를
    잇는 조회는 '미래로 늘이기'로 실패한다(로그: map→odom 1 · odom→base_footprint 1 · 이은 것 0)."""
    tf2_ros = pytest.importorskip("tf2_ros")
    buffer = tf2_ros.Buffer()
    now = 1000.0
    buffer.set_transform(_stamped("map", "odom", 1.0, math.pi / 2, now + 1.0), "amcl")
    for back in (0.5, 0.25, 0.0):
        buffer.set_transform(_stamped("odom", "base_footprint", 2.0, 0.0, now - back), "ekf")
    buffer.set_transform_static(_stamped("base_footprint", "laser_frame", 0.1, 0.0, 0.0), "urdf")

    fake = _fake_node(buffer)
    scan = SimpleNamespace(header=SimpleNamespace(frame_id="laser_frame"),
                           ranges=[1.0], angle_min=0.0, angle_increment=0.1)

    taken = fake._scan_input(scan, wait=0.0)

    assert taken is not None
    x, y, yaw = taken.guess
    assert math.isclose(x, 1.0, abs_tol=1e-6) and math.isclose(y, 2.0) and math.isclose(yaw, math.pi / 2)


def _fake_node(buffer):
    frames = {"base_frame": "base_footprint", "map_frame": "map", "odom_frame": "odom"}
    fake = node.MapFixNode.__new__(node.MapFixNode)
    fake._tf_buffer = buffer
    fake._sensors_opened_at = 0.0
    fake._body = node.parse_body(node.DEFAULT_FOOTPRINT, 0.20)
    fake.get_parameter = lambda name: SimpleNamespace(value=frames[name])
    quiet = SimpleNamespace(warn=lambda *a, **k: None, info=lambda *a, **k: None)
    fake.get_logger = lambda: quiet
    return fake


def _standing_buffer():
    tf2_ros = pytest.importorskip("tf2_ros")
    buffer = tf2_ros.Buffer()
    buffer.set_transform(_stamped("map", "odom", 0.0, 0.0, 1000.0), "amcl")
    buffer.set_transform(_stamped("odom", "base_footprint", 0.0, 0.0, 1000.0), "ekf")
    buffer.set_transform_static(_stamped("base_footprint", "laser_frame", 0.0, 0.0, 0.0), "urdf")
    return buffer


def test_scan_input_drops_beams_on_the_body():
    """11-19 실기: 로봇 뒤쪽 차체(0.36~0.46 m)가 지도에 써졌다. 몸체 + 사방 0.20 m 안의 빔은 버린다."""
    fake = _fake_node(_standing_buffer())
    scan = SimpleNamespace(header=SimpleNamespace(frame_id="laser_frame"),
                           ranges=[2.0, 0.40], angle_min=0.0, angle_increment=math.pi)   # 앞 2 m · 뒤 0.4 m

    taken = fake._scan_input(scan, wait=0.0)

    assert taken.ranges[0] == 2.0 and math.isnan(taken.ranges[1])


class _NeverAnswers:
    """요청은 받되 응답이 오지 않는 load_map 클라이언트(11-19 19:35 실기: map_server 는 7번 다 읽었는데
    노드는 앞 6번의 응답을 받지 못했다)."""

    def __init__(self):
        from rclpy.task import Future

        self.sent = []
        self._future = Future

    def service_is_ready(self):
        return True

    def call_async(self, request):
        self.sent.append(request.map_url)
        return self._future()

    def remove_pending_request(self, future):
        pass


def _apply_node(timeout_sec: float):
    import threading
    from pathlib import Path as _Path

    fake = node.MapFixNode.__new__(node.MapFixNode)
    fake._load_map_client = _NeverAnswers()
    fake._load_map_made_at = 0.0
    fake._load_map_type = SimpleNamespace(Request=lambda: SimpleNamespace(map_url=""))
    fake.maps_root = _Path("/maps")
    fake._apply_cond = threading.Condition()
    fake._map_loaded_wall = 0.0
    fake.get_parameter = lambda name: SimpleNamespace(value={"apply_timeout_sec": timeout_sec}[name])
    quiet = SimpleNamespace(warn=lambda *a, **k: None, info=lambda *a, **k: None, error=lambda *a, **k: None)
    fake.get_logger = lambda: quiet
    return fake


def _map_message(load_wall: float):
    sec = int(load_wall)
    return SimpleNamespace(info=SimpleNamespace(map_load_time=SimpleNamespace(
        sec=sec, nanosec=int((load_wall - sec) * 1e9))))


def test_apply_is_confirmed_by_the_new_map_when_the_answer_is_lost():
    """응답이 사라져도 map_server 가 다시 낸 /map(읽은 시각이 요청 뒤)으로 반영을 확인한다 —
    헛되이 시간 초과·재요청(AMCL 이 지도를 또 받음)하지 않는다."""
    import threading
    import time

    fake = _apply_node(timeout_sec=3.0)
    threading.Timer(0.2, lambda: fake._on_map(_map_message(time.time()))).start()

    start = time.monotonic()
    applied, reason, _ = fake._apply("m")

    assert (applied, reason) == (True, "") and time.monotonic() - start < 1.0
    assert fake._load_map_client.sent == ["/maps/m.yaml"]


def test_an_older_map_does_not_confirm_the_apply():
    import threading
    import time

    fake = _apply_node(timeout_sec=0.6)
    threading.Timer(0.1, lambda: fake._on_map(_map_message(time.time() - 30.0))).start()

    applied, reason, _ = fake._apply("m")

    assert (applied, reason) == (False, "apply_timeout")


def test_apply_waits_five_seconds_by_default():
    import inspect

    assert '"apply_timeout_sec", 5.0' in inspect.getsource(node.MapFixNode.__init__)


def test_retry_waits_for_nav2_outside_the_core_lock():
    """11-19 실기: 재요청이 잠금을 쥔 채 10 s 씩 6번 기다려, 그동안 앱 요청이 답을 못 받았다(call_30 시간 초과)."""
    import threading

    fake = node.MapFixNode.__new__(node.MapFixNode)
    fake._core_lock = threading.RLock()
    seen = {}

    def apply(map_id):
        free = threading.Event()

        def try_lock():
            if fake._core_lock.acquire(timeout=0.5):
                fake._core_lock.release()
                free.set()

        probe = threading.Thread(target=try_lock)
        probe.start()
        probe.join()
        seen["lock_free_while_waiting"] = free.is_set()
        return False, "apply_timeout", ""

    finished = []
    fake.core = SimpleNamespace(retry_target=lambda: "m", finish_retry=lambda *a: finished.append(a),
                                pending_apply="m")
    fake._apply = apply
    fake._retry_at = 0.0
    fake._retry_gap = node.RETRY_FIRST_SEC

    fake._retry_once()

    assert seen == {"lock_free_while_waiting": True}
    assert finished == [("m", (False, "apply_timeout", ""))]
    assert fake._retry_gap == 2 * node.RETRY_FIRST_SEC                  # 실패하면 간격을 늘린다


def test_importing_the_node_does_not_load_numpy():
    """쉬는 동안에는 numpy·scipy 와 스캔 계산 모듈이 올라와 있지 않습니다."""
    code = (
        "import sys; sys.path.insert(0, %r); import map_fix_node; "
        "print([name for name in ('numpy', 'scipy', 'tf2_ros', 'map_fix_store', 'map_fix_scan', "
        "'map_fix_session') if name in sys.modules])" % str(HERE)
    )
    out = subprocess.run([sys.executable, "-c", code], capture_output=True, text=True, check=True)
    assert out.stdout.strip() == "[]"


def test_running_node_stays_light_until_the_first_request():
    """노드를 만들어도 numpy 가 올라오지 않습니다(11-19 격리 실측: Nav2 load_map 클라이언트를 기동 때
    만들면 그 메시지 C 확장이 numpy 를 불러 쉬는 동안 56 MB 였다). 클라이언트는 첫 요청 때 만듭니다.

    노드를 실제로 만들므로 이 컴퓨터 안에서만 통하는 도메인(ROS_LOCALHOST_ONLY=1, 99)에서 띄웁니다 —
    로봇의 ROS 그래프(도메인 7)에는 붙지 않습니다.
    """
    code = (
        "import sys; sys.path.insert(0, %r)\n"
        "import rclpy, map_fix_node\n"
        "rclpy.init()\n"
        "node = map_fix_node.MapFixNode()\n"
        "from rclpy.callback_groups import MutuallyExclusiveCallbackGroup as M\n"
        "print('numpy' in sys.modules, node._load_map_client is None,"
        " isinstance(node._housekeeping_timer.callback_group, M))\n"
        "node.destroy_node(); rclpy.shutdown()\n" % str(HERE)
    )
    env = {**os.environ, "ROS_DOMAIN_ID": "99", "ROS_LOCALHOST_ONLY": "1"}
    out = subprocess.run([sys.executable, "-c", code], capture_output=True, text=True, env=env, timeout=60)
    assert out.returncode == 0, out.stderr[-800:]
    # 정리 타이머는 한 번에 하나만 돕니다 — Nav2 가 답하지 않을 때 대기 스레드가 쌓이지 않게(검토 2).
    assert out.stdout.strip().splitlines()[-1] == "False True True"


def test_closing_sensors_while_scans_pour_in_does_not_kill_the_node():
    """11-19 17:43 실기: scan_check 가 끝나며 /scan 구독을 닫는 순간 실행기가 그 구독의 메시지를
    꺼내던 중이라 rclpy(Humble)가 InvalidHandle 을 냈고, 실행 루프까지 올라와 노드가 죽었다.

    로컬 전용 도메인(ROS_LOCALHOST_ONLY=1, 98)에서 /scan 을 200 Hz 로 흘리며 센서를 40번 열고 닫는다.
    로봇의 ROS 그래프(도메인 7)에는 붙지 않는다.
    """
    code = (
        "import sys, threading, time; sys.path.insert(0, %r)\n"
        "import rclpy, map_fix_node\n"
        "from rclpy.executors import MultiThreadedExecutor\n"
        "from sensor_msgs.msg import LaserScan\n"
        "from rclpy.qos import qos_profile_sensor_data\n"
        "rclpy.init()\n"
        "node = map_fix_node.MapFixNode()\n"
        "feeder = rclpy.create_node('scan_feeder')\n"
        "pub = feeder.create_publisher(LaserScan, '/scan', qos_profile_sensor_data)\n"
        "msg = LaserScan(); msg.header.frame_id = 'laser'; msg.ranges = [1.0] * 720\n"
        "feeder.create_timer(0.005, lambda: pub.publish(msg))\n"
        "ex = MultiThreadedExecutor(); ex.add_node(node); ex.add_node(feeder)\n"
        "stop = threading.Event()\n"
        "errors = []\n"
        "def run():\n"
        "    try:\n"
        "        map_fix_node.spin_forgiving(ex, stop.is_set)\n"
        "    except Exception as e:\n"
        "        errors.append(repr(e))\n"
        "t = threading.Thread(target=run); t.start()\n"
        "for _ in range(40):\n"
        "    node._open_sensors(); time.sleep(0.03); node._close_sensors(); time.sleep(0.01)\n"
        "stop.set(); t.join(timeout=10)\n"
        "print('alive' if not errors and not t.is_alive() else 'dead %%s' %% errors)\n"
        "ex.shutdown(); node.destroy_node(); feeder.destroy_node(); rclpy.shutdown()\n" % str(HERE)
    )
    env = {**os.environ, "ROS_DOMAIN_ID": "98", "ROS_LOCALHOST_ONLY": "1"}
    out = subprocess.run([sys.executable, "-c", code], capture_output=True, text=True, env=env, timeout=120)
    assert out.stdout.strip().splitlines()[-1:] == ["alive"], (out.stdout[-400:], out.stderr[-1200:])


def test_tf_still_arrives_while_the_core_is_busy_and_odom_pours_in():
    """11-19 17:5x 실기: scan_check 가 _core_lock 을 쥔 동안 /odom(수십 Hz)이 올 때마다 같은 잠금을
    기다리며 실행 스레드를 하나씩 붙잡아, TF 를 받을 스레드가 남지 않았다 — 8 s 기다려도 'TF 없음'.

    로컬 전용 도메인(98)에서 /odom 을 200 Hz 로 흘리고 잠금을 3 s 쥔 채, 그동안 보낸 TF 가 들어오는지 본다.
    """
    code = (
        "import sys, threading, time; sys.path.insert(0, %r)\n"
        "import rclpy, map_fix_node\n"
        "from rclpy.executors import MultiThreadedExecutor\n"
        "from nav_msgs.msg import Odometry\n"
        "from geometry_msgs.msg import TransformStamped\n"
        "from tf2_ros import TransformBroadcaster\n"
        "from rclpy.qos import qos_profile_sensor_data\n"
        "rclpy.init()\n"
        "node = map_fix_node.MapFixNode()\n"
        "feeder = rclpy.create_node('odom_tf_feeder')\n"
        "pub = feeder.create_publisher(Odometry, '/odom', qos_profile_sensor_data)\n"
        "feeder.create_timer(0.005, lambda: pub.publish(Odometry()))\n"
        "tfb = TransformBroadcaster(feeder)\n"
        "def send_tf():\n"
        "    t = TransformStamped(); t.header.stamp = feeder.get_clock().now().to_msg()\n"
        "    t.header.frame_id = 'map'; t.child_frame_id = 'base_footprint'; t.transform.rotation.w = 1.0\n"
        "    tfb.sendTransform(t)\n"
        "ex = MultiThreadedExecutor(); ex.add_node(node); ex.add_node(feeder)\n"
        "stop = threading.Event()\n"
        "th = threading.Thread(target=map_fix_node.spin_forgiving, args=(ex, stop.is_set)); th.start()\n"
        "node._open_sensors(); time.sleep(1.5)\n"
        "with node._core_lock:\n"
        "    t0 = time.monotonic(); ok = False\n"
        "    while time.monotonic() - t0 < 3.0:\n"
        "        send_tf(); time.sleep(0.05)\n"
        "        if node._tf_buffer.can_transform('map', 'base_footprint', rclpy.time.Time()):\n"
        "            ok = True; break\n"
        "print('tf ok' if ok else 'tf starved')\n"
        "stop.set(); th.join(timeout=10)\n"
        "ex.shutdown(); node.destroy_node(); feeder.destroy_node(); rclpy.shutdown()\n" % str(HERE)
    )
    env = {**os.environ, "ROS_DOMAIN_ID": "98", "ROS_LOCALHOST_ONLY": "1"}
    out = subprocess.run([sys.executable, "-c", code], capture_output=True, text=True, env=env, timeout=120)
    assert out.stdout.strip().splitlines()[-1:] == ["tf ok"], (out.stdout[-400:], out.stderr[-1200:])


def test_launch_starts_the_map_fix_node(tmp_path):
    pytest.importorskip("launch")
    from launch import LaunchContext
    from launch.actions import ExecuteProcess
    from launch.utilities import perform_substitutions

    spec = importlib.util.spec_from_file_location(
        "supervisor_bringup_launch", HERE / "supervisor_bringup.launch.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.get_package_share_directory = lambda _name: str(tmp_path)

    context = LaunchContext()
    context.launch_configurations["map_yaml"] = ""
    commands = [
        [perform_substitutions(context, part) for part in entity.cmd]
        for entity in module.generate_launch_description().entities
        if isinstance(entity, ExecuteProcess)
    ]

    assert module.MAP_FIX_NODE == HERE / "map_fix_node.py"
    assert sum(str(module.MAP_FIX_NODE) in argv for argv in commands) == 1
    # 예상 밖으로 죽어도 다시 뜹니다(검토 6).
    process = next(entity for entity in module.generate_launch_description().entities
                   if isinstance(entity, ExecuteProcess)
                   and str(module.MAP_FIX_NODE) in [perform_substitutions(context, part) for part in entity.cmd])
    respawn = getattr(process, "_ExecuteLocal__respawn", getattr(process, "_ExecuteProcess__respawn", None))
    assert respawn is True
