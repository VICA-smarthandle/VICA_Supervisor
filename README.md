# VICA_Supervisor

VICA 로봇 관리자용 Flutter 앱이다.

앱 시작 시 로컬 관리자 로그인을 거치며 로그인 상태를 저장한다. 이는 앱 화면 진입
제어이고 ROS service 호출자 인증은 아니므로 reset 접근 통제는 아직 `[GAP]`이다.

## 핵심 연결

- ROS 연결: rosbridge WebSocket
- 지도 이미지: 지도 HTTP 서버 주소 + `/map_list`의 `image_url`
- 목적지 관리: `/save_location`, `/delete_location_request`,
  `/location_list_request`, `/location_list`
- 목적지 정본: `~/vica_data/destinations/<map_id>/destinations.yaml`
- 원격 안내 요청: `/vica/mission/request_destination`
- 비상정지: `/app_estop_activate`, `/app_estop_reset`

앱은 저장 경로나 Nav2 action을 직접 소유하지 않는다. 저장 경로는
`vica_destination_manager`의 ROS 파라미터이고, Nav2 Goal은 Mission Manager만 생성한다.

## 실행

```bash
flutter pub get
flutter run
```

ROS 쪽에서는 다음 구성요소를 별도로 실행한다.

```bash
ros2 launch vica_destination_manager destination_manager.launch.py
ros2 launch vica_mission_manager mission_manager.launch.py \
  map_id:=vica_map_0630 \
  map_yaml:=/path/to/vica_map_0630.yaml
```

터미널 시험 도구는 선택한 지도의 정본 YAML에서 목적지 이름을 정확히 찾아 UUID로
변환한 뒤 Mission Manager에 요청한다. 요청 수락 뒤에는 같은 목적지의
`/vica_goal_event`를 기다리고 도착·실패·취소 결과를 출력한 뒤 종료한다. 이름에 공백이
있으면 따옴표로 감싼다.

```bash
python3 ros2/vica_goto_goal.py vica_map_0630 "별빛관 1층 화장실"
```

기본 주행 결과 대기시간은 600초다. `--navigation-timeout 0`은 제한 없이 기다린다.
CLI에서 `Ctrl+C`로 모니터링을 종료해도 진행 중인 Goal을 직접 취소하지 않는다.

`ros2/location_storage_node.py`는 기존 JSON 저장 노드의 보호용 진입점이며 더 이상
사용하지 않는다. 기존 JSON 장소는 새 YAML로 자동 이관하지 않는다.
