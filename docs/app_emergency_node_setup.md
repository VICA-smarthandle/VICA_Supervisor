# app_emergency_node 배포 및 연동 점검

`app_emergency_node`의 정본은 ROS workspace의
`vica_ros2_ws/src/vica_safety/vica_safety/app_emergency_node.py`다. 앱 저장소의 과거 ROS
보조 파일을 별도 node로 실행하지 않는다.

## 실행 경계

```bash
ros2 launch vica_safety safety_bringup.launch.py
```

이 launch는 `emergency_stop_node`, `safety_supervisor_node`, `app_emergency_node`를
실행하며 motor node는 포함하지 않는다. motor는 안전 계층 확인 뒤 별도 실행한다.

```bash
ros2 launch mdrobot_can_control motor_bringup.launch.py
```

## 앱 계약

| 방향 | 인터페이스 | 타입 |
| --- | --- | --- |
| 앱 → ROS | `/app_estop_activate` | `std_srvs/srv/Trigger` |
| 앱 → ROS | `/app_estop_reset` | `std_srvs/srv/Trigger` |
| ROS → 앱 | `/app_estop_state` | `std_msgs/msg/String` JSON |

`/app_estop_reset`은 Nav2 실행 여부 확인, 필요한 경우의 활성 Goal 전체 취소, 중앙 E-stop
latch 내부 reset, Supervisor 내부 reset, `READY_TO_GO` 확인을 하나의 절차로 수행한다.
마지막 action status가 terminal이면 cancel 호출을 생략하고, 활성 상태이면 전체 취소 후
요청 이후의 새 terminal 상태를 확인한다. Goal 이력이 없거나 Nav2가 미실행이면 Goal
검사를 생략한다. 앱은 내부 서비스를 직접 호출하지 않으며 터미널 유지보수용
`/safety_reset`도 같은 절차를 사용한다.

## 읽기 전용 확인

```bash
ros2 node list
ros2 node info /app_emergency_node
ros2 topic echo /app_estop_state
ros2 topic echo /emergency_stop
ros2 topic echo /safety_state
ros2 service type /app_estop_activate
ros2 service type /app_estop_reset
ros2 service type /safety_reset
ros2 action info /navigate_to_pose
```

다음을 확인한다.

1. `app_emergency_node`가 한 개만 실행 중이다.
2. 앱이 `/cmd_vel*`, Nav2 action, 내부 reset 서비스를 직접 사용하지 않는다.
3. `/app_estop_state.active`가 앱 source가 아니라 중앙 `/emergency_stop`과 일치한다.
4. 앱과 ROS의 Domain ID, rosbridge 연결, 서비스 이름이 일치한다.
5. reset 실패 응답에 `step`과 `reason`이 표시된다.
6. reset 뒤 이전 Goal이 자동 재개되지 않는다.

## 실기 시험 조건

CAN·motor·Nav2와 함께 시험하기 전에 바퀴를 띄우고 주변을 통제하며, 물리 E-stop과 즉시
전원 차단 수단을 확보한다. 물리 버튼 active, F1 stale, 비영 `/cmd_vel_req`, Nav2 취소
실패에서 reset이 거부되는지 각각 확인한다.

관리자 인증은 아직 구현되지 않았다. `/app_estop_reset`과 유지보수 `/safety_reset`의
호출자 접근 통제는 `[GAP]`이며 소프트웨어 node는 물리 비상정지 회로를 대체하지 않는다.
