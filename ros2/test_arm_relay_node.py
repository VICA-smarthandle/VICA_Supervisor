"""arm_relay_node.forward 시험입니다 (2026-11-25).

    source /opt/ros/humble/setup.bash
    python3 -m pytest ros2/test_arm_relay_node.py

ROS 를 띄우지 않습니다. 77 쪽 클라이언트를 가짜로 두고 rclpy 의 Future 를 그대로 씁니다.
"""
from __future__ import annotations

import sys
import threading
import time
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

pytest.importorskip("rclpy")
from rclpy.task import Future  # noqa: E402
from std_srvs.srv import Trigger  # noqa: E402

import arm_relay_node as relay  # noqa: E402


class FakeArmClient:
    def __init__(self, ready: bool = True, future: Future | None = None) -> None:
        self.ready = ready
        self.future = future if future is not None else Future()
        self.calls = 0
        self.removed: list[Future] = []

    def wait_for_service(self, timeout_sec: float) -> bool:
        return self.ready

    def call_async(self, _request) -> Future:
        self.calls += 1
        return self.future

    def remove_pending_request(self, future: Future) -> None:
        self.removed.append(future)


def answered(success: bool, message: str) -> Future:
    future = Future()
    future.set_result(Trigger.Response(success=success, message=message))
    return future


def test_no_arm_service_answers_without_calling():
    client = FakeArmClient(ready=False)
    assert relay.forward(client, 180.0) == (False, relay.NO_SERVICE)
    assert client.calls == 0


def test_arm_answer_passes_through_unchanged():
    message = "시연 완료(down, 닿음, 불 안 켜짐) → 홈 (27초)"  # 11-25 14:32 실측 응답
    assert relay.forward(FakeArmClient(future=answered(True, message)), 180.0) == (True, message)


def test_arm_refusal_passes_through_unchanged():
    message = "거절: 비상정지 중"
    assert relay.forward(FakeArmClient(future=answered(False, message)), 180.0) == (False, message)


def test_answer_from_another_thread_is_waited_for():
    # 실제로는 77 쪽 실행기 스레드가 응답을 채웁니다.
    future = Future()

    def answer_later() -> None:
        time.sleep(0.1)
        future.set_result(Trigger.Response(success=True, message="대기 중"))

    threading.Thread(target=answer_later).start()
    assert relay.forward(FakeArmClient(future=future), 5.0) == (True, "대기 중")


def test_timeout_answers_false_and_drops_the_pending_request():
    client = FakeArmClient()
    assert relay.forward(client, 0.05) == (False, relay.timeout_message(0.05))
    assert client.removed == [client.future]


def test_call_error_answers_false():
    future = Future()
    future.set_exception(RuntimeError("context invalid"))
    success, message = relay.forward(FakeArmClient(future=future), 5.0)
    assert success is False
    assert message == "매니퓰레이터 호출 오류: context invalid"


def test_routes_match_the_arm_services():
    assert relay.ROUTES == {
        "/app/arm_demo": ("/arm/demo", 180.0),
        "/app/arm_status": ("/arm/status", 5.0),
        "/app/arm_home": ("/arm/home", 60.0),
    }
