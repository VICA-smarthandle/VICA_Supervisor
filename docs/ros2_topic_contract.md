# ROS 2 앱 계약

앱은 rosbridge를 통해 제한된 topic과 service만 사용한다. Nav2 action, TF, motor와
CAN에는 직접 연결하지 않는다.

## 데이터 경로

- 지도 원본: `vica_ros2_ws/maps/`
- 목적지 정본: `~/vica_data/destinations/<map_id>/destinations.yaml`
- 기존 `locations.json`: 이관하지 않으며 운용 경로에서 사용하지 않음

## Topic

| 목적 | 이름 | 타입 |
|---|---|---|
| 지도 목록 요청/응답 | `/map_list_request`, `/map_list` | `std_msgs/msg/String` JSON |
| 목적지 목록 요청/응답 | `/location_list_request`, `/location_list` | `std_msgs/msg/String` JSON |
| 목적지 저장 | `/save_location` | `std_msgs/msg/String` JSON |
| 목적지 삭제 | `/delete_location_request` | `std_msgs/msg/String` JSON |
| 앱 상태 | `/robot_status` | `std_msgs/msg/String` JSON |
| 주행 이벤트 | `/vica_goal_event` | `std_msgs/msg/String` JSON |
| E-stop 상태 | `/app_estop_state` | `std_msgs/msg/String` JSON |

저장 요청 예:

```json
{
  "request_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
  "map_id": "vica_map_0630",
  "id": "11111111-1111-4111-8111-111111111111",
  "name": "별빛관 1층 화장실",
  "aliases": ["별빛관 1층 화장실", "화장실"],
  "category1": "facility",
  "category2": "restroom",
  "building": "starlight_building",
  "floor": 1,
  "owner": "",
  "authorization": "public",
  "is_approachable": true,
  "unavailable_reason": "",
  "pose": {
    "frame_id": "map",
    "x": 1.2,
    "y": -3.4,
    "yaw": 90.0
  },
  "confirm_prompt": "별빛관 1층 화장실로 안내해드릴까요?",
  "arrival_message": "별빛관 1층 화장실 앞에 도착했습니다."
}
```

`request_id`, `map_id`, `timestamp`는 전송 메타데이터이며 목적지 항목 내부에 저장하지
않는다. 저장 루트는 앱이 보내지 않고 `vica_destination_manager` 파라미터가 소유한다.

삭제 요청은 `map_id`와 `destination_id` UUID를 사용한다.

## Service

| 목적 | 이름 | 타입 |
|---|---|---|
| 목적지 안내 요청 | `/vica/mission/request_destination` | `vica_interfaces/srv/RequestDestination` |
| 앱 E-stop | `/app_estop_activate` | `std_srvs/srv/Trigger` |
| 앱 reset | `/app_estop_reset` | `std_srvs/srv/Trigger` |
| 유지보수 reset | `/safety_reset` | `std_srvs/srv/Trigger` |

목적지 안내 요청:

```text
request_id: UUID
map_id: 현재 선택 지도
destination_id: 저장된 목적지 UUID
---
accepted: Mission gate 수락 여부
message: 결과 사유
```

Mission Manager는 현재 지도 일치, UUID 존재, `authorization == public`,
`is_approachable == true`, pose·E-stop·Nav2 준비와 IDLE 상태를 다시 검사한다.

E-stop reset은 Nav2 action status의 마지막 상태가 활성 상태이면 전체 취소 후 새
terminal 상태를 확인한다. 마지막 상태가 terminal이거나 Goal 이력이 없으면 취소 또는
Goal 검사를 생략한다. 이어 중앙 latch 해제와 Safety 재승인을 확인한다.
