#!/usr/bin/env python3
"""앱(도메인 7)의 로봇팔 요청을 나노 팔 서비스(도메인 77)로 넘기는 중계 노드입니다 (2026-11-25).

    앱 -rosbridge-> /app/arm_demo·/app/arm_status·/app/arm_home   (도메인 7, 이 노드)
                 -랜선-> /arm/demo·/arm/status·/arm/home            (도메인 77, 나노 arm_service.py)

rosbridge 는 도메인 7 에만 붙어 있어 77 서비스를 직접 부를 수 없습니다. 그래서 한 프로세스에
context 를 둘(7·77) 두고, 나노 응답의 success·message 를 그대로 돌려줍니다.
나노 코드는 나노에서 관리합니다. 이 노드는 부르기만 합니다.
"""
from __future__ import annotations

import threading
from typing import Any

import rclpy
from rclpy.callback_groups import ReentrantCallbackGroup
from rclpy.context import Context
from rclpy.executors import ExternalShutdownException, MultiThreadedExecutor, SingleThreadedExecutor
from rclpy.node import Node
from std_srvs.srv import Trigger

ARM_DOMAIN_ID = 77

# 앱 서비스 → (나노 서비스, 응답 대기 s). 나노가 스스로 끝내는 최대 시간보다 길게 둡니다 —
# 중계가 먼저 끊으면 팔은 계속 움직이는데 앱은 '시간 초과'만 보게 됩니다(11-25 나노 쪽 지적).
# /arm/demo: press.py DEMO_TIMEOUT 180 s + 실패 뒤 홈 최대 150 s(비상정지 저속) ≈ 330 s → 360 s
# /arm/home: 비상정지 중 저속 홈 최대 150 s(arm_service.py estop_home) → 160 s
ROUTES = {
    "/app/arm_demo": ("/arm/demo", 360.0),
    "/app/arm_status": ("/arm/status", 5.0),
    "/app/arm_home": ("/arm/home", 160.0),
}

# 노드가 막 떴을 때 77 쪽 발견을 기다리는 시간입니다. 그 뒤로는 서비스가 없으면 바로 답합니다.
READY_WAIT_SEC = 1.0

# 앱에서는 '매니퓰레이터'라고 부릅니다(2026-11-25 사용자). 이 문장들은 앱 화면에 그대로 나옵니다.
# 나노는 부팅 때 vica-arm 서비스로 팔 프로그램을 띄웁니다(11-25 나노 쪽).
NO_SERVICE = "매니퓰레이터 서비스 없음(나노 vica-arm 서비스 확인)"


def timeout_message(sec: float) -> str:
    return f"매니퓰레이터 응답 시간 초과({sec:.0f}초) — 팔이 아직 동작 중일 수 있음, 현장 확인"


def forward(client: Any, timeout_sec: float, ready_wait_sec: float = READY_WAIT_SEC) -> tuple[bool, str]:
    """77 쪽 서비스를 부르고 (success, message) 를 돌려줍니다.

    응답은 77 쪽 실행기 스레드가 채웁니다. 이 함수는 도메인 7 서비스 콜백 스레드에서 기다립니다.
    """
    if not client.wait_for_service(timeout_sec=ready_wait_sec):
        return False, NO_SERVICE
    future = client.call_async(Trigger.Request())
    done = threading.Event()
    future.add_done_callback(lambda _future: done.set())
    if not done.wait(timeout_sec):
        # 팔은 계속 움직이고 있을 수 있습니다. 늦게 오는 응답은 버립니다.
        client.remove_pending_request(future)
        return False, timeout_message(timeout_sec)
    error = future.exception()
    if error is not None:
        return False, f"매니퓰레이터 호출 오류: {error}"
    result = future.result()
    return bool(result.success), str(result.message)


class ArmRelayNode(Node):
    """도메인 7 에 /app/arm_* 를 열고, 받은 요청을 77 쪽 클라이언트로 넘깁니다."""

    def __init__(self, arm_node: Node) -> None:
        super().__init__("arm_relay")
        # 시연 응답을 기다리는(최대 180 s) 동안에도 상태 요청은 바로 처리합니다.
        group = ReentrantCallbackGroup()
        for app_name, (arm_name, timeout_sec) in ROUTES.items():
            client = arm_node.create_client(Trigger, arm_name)
            self.create_service(
                Trigger, app_name, self._handler(app_name, client, timeout_sec), callback_group=group
            )
        self.get_logger().info(
            f"로봇팔 중계 준비: {', '.join(ROUTES)} → 도메인 {ARM_DOMAIN_ID} /arm/*"
        )

    def _handler(self, app_name: str, client: Any, timeout_sec: float):
        def handle(_request: Trigger.Request, response: Trigger.Response) -> Trigger.Response:
            response.success, response.message = forward(client, timeout_sec)
            # 상태는 앱이 몇 초마다 부르므로 기록하지 않습니다.
            if app_name != "/app/arm_status":
                log = self.get_logger().info if response.success else self.get_logger().warning
                log(f"{app_name} → {response.message}")
            return response

        return handle


def main() -> None:
    rclpy.init()  # 도메인은 환경(ROS_DOMAIN_ID=7)을 따릅니다.
    arm_context = Context()
    rclpy.init(context=arm_context, domain_id=ARM_DOMAIN_ID)
    arm_node = rclpy.create_node("nx_arm_relay", context=arm_context)
    arm_executor = SingleThreadedExecutor(context=arm_context)
    arm_executor.add_node(arm_node)

    def spin_arm() -> None:
        try:
            arm_executor.spin()
        except (KeyboardInterrupt, ExternalShutdownException):
            pass

    arm_thread = threading.Thread(target=spin_arm, daemon=True)
    node = ArmRelayNode(arm_node)
    # 시연 1 + 상태·홈 요청이 동시에 와도 막히지 않을 만큼만 둡니다.
    executor = MultiThreadedExecutor(num_threads=4)
    executor.add_node(node)
    arm_thread.start()
    try:
        executor.spin()
    except (KeyboardInterrupt, ExternalShutdownException):
        pass
    finally:
        executor.shutdown()
        arm_executor.shutdown()
        node.destroy_node()
        arm_node.destroy_node()
        if arm_context.ok():
            rclpy.shutdown(context=arm_context)
        if rclpy.ok():
            rclpy.shutdown()
        arm_thread.join(timeout=2.0)


if __name__ == "__main__":
    main()
