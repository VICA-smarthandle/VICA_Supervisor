// 매핑 세션 상태의 판정 규칙을 고정합니다.
//
// 이 판정이 느슨하면 사람이 30분을 잃습니다. 그래서 "시작되는가"보다
// "언제 막히는가"를 더 촘촘히 봅니다.
import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/models/map_preview.dart';
import 'package:vica_supervisor/models/mapping_status.dart';

Map<String, Object?> statusJson({
  String state = 'idle',
  bool nav2 = false,
  bool mapping = false,
  List<String> duplicated = const [],
  List<String> missing = const [],
  String detail = '',
  String mapId = '',
}) {
  return {
    'state': state,
    'detail': detail,
    'map_id': mapId,
    'nav2_running': nav2,
    'mapping_running': mapping,
    'duplicated': duplicated,
    'prerequisites_missing': missing,
  };
}

void main() {
  group('MappingStatus', () {
    test('전부 깨끗하면 시작할 수 있다', () {
      expect(MappingStatus.fromJson(statusJson()).canStart, isTrue);
    });

    test('Nav2 가 떠 있으면 시작할 수 없다', () {
      // 둘 다 wheel_ekf 를 include 해서 /odom 발행자가 둘이 된다.
      expect(
        MappingStatus.fromJson(statusJson(nav2: true)).canStart,
        isFalse,
      );
    });

    test('노드가 두 벌이면 시작할 수 없다', () {
      expect(
        MappingStatus.fromJson(
          statusJson(duplicated: ['ekf_filter_node']),
        ).canStart,
        isFalse,
      );
    });

    test('선행 노드가 빠져 있으면 시작할 수 없다', () {
      // d455·imu 는 앱이 안 띄우지만 없으면 회차가 무효가 된다.
      expect(
        MappingStatus.fromJson(
          statusJson(missing: ['imu_base_link_adapter']),
        ).canStart,
        isFalse,
      );
    });

    test('idle 이 아니면 시작할 수 없다', () {
      for (final state in ['starting', 'mapping', 'saving', 'stopping']) {
        expect(
          MappingStatus.fromJson(statusJson(state: state)).canStart,
          isFalse,
          reason: state,
        );
      }
    });

    test('진행 중인 상태는 모두 busy 다', () {
      for (final state in ['starting', 'mapping', 'stopping', 'saving']) {
        expect(
          MappingStatus.fromJson(statusJson(state: state)).busy,
          isTrue,
          reason: state,
        );
      }
      expect(MappingStatus.fromJson(statusJson()).busy, isFalse);
    });

    test('저장은 그리는 중일 때만 된다', () {
      expect(
        MappingStatus.fromJson(statusJson(state: 'mapping')).canSave,
        isTrue,
      );
      for (final state in ['idle', 'starting', 'saving', 'error']) {
        expect(
          MappingStatus.fromJson(statusJson(state: state)).canSave,
          isFalse,
          reason: state,
        );
      }
    });

    test('모르는 상태값은 오류로 본다', () {
      // 조용히 idle 로 떨어뜨리면 시작 버튼이 열려 중복 실행을 부른다.
      expect(
        MappingStatus.fromJson(statusJson(state: 'wat')).state,
        MappingState.error,
      );
    });
  });

  group('MappingStatus 표시 이름', () {
    test('map_name 이 오면 그것을, 없으면 id 를 보여준다', () {
      // 한글 이름은 감독 노드가 표시용으로만 보낸다. 파일·URL 은 계속 id 다.
      final named = MappingStatus.fromJson({
        ...statusJson(state: 'mapping', mapId: 'map_0904_151230'),
        'map_name': '병원 2층',
      });
      expect(named.displayName, '병원 2층');
      expect(named.mapId, 'map_0904_151230');

      final legacy = MappingStatus.fromJson(
        statusJson(state: 'mapping', mapId: 'lobby_0904'),
      );
      expect(legacy.displayName, 'lobby_0904');
    });
  });

  group('MapPreview', () {
    Map<String, Object?> previewJson({int seq = 3}) => {
          'image_url': '/maps/_live/preview.png',
          'seq': seq,
          'width': 40,
          'height': 30,
          'resolution': 0.05,
          'origin_x': -1.5,
          'origin_y': -2.5,
          'bytes': 4533,
        };

    test('순번을 URL 에 붙여 캐시를 피한다', () {
      // 같은 URL 이면 Flutter 가 예전 그림을 그대로 쓴다.
      final map = MapPreview.fromJson(previewJson(seq: 7)).toVicaMap();
      expect(map.imageUrl, '/maps/_live/preview.png?t=7');
    });

    test('좌표 정보를 그대로 옮긴다', () {
      // 지도가 자라면 크기와 원점이 함께 바뀌므로 매번 같이 와야 한다.
      final map = MapPreview.fromJson(previewJson()).toVicaMap();
      expect(map.width, 40);
      expect(map.height, 30);
      expect(map.resolution, 0.05);
      expect(map.originX, -1.5);
      expect(map.originY, -2.5);
    });

    test('저장된 지도 목록과 섞이지 않게 별도 id 를 쓴다', () {
      expect(MapPreview.fromJson(previewJson()).toVicaMap().mapId, 'preview');
    });

    test('로봇 자세가 없으면 없다고 말한다', () {
      // map_preview_node 는 /tracked_pose 를 못 받았거나 끊기면 필드를 뺀다.
      final preview = MapPreview.fromJson(previewJson());
      expect(preview.hasRobotPose, isFalse);
      expect(preview.robotX, isNull);
    });

    test('로봇 자세를 도 단위 그대로 옮긴다', () {
      final preview = MapPreview.fromJson({
        ...previewJson(),
        'robot_x': 1.235,
        'robot_y': -2.346,
        'robot_yaw': 91.23,
      });
      expect(preview.hasRobotPose, isTrue);
      expect(preview.robotX, 1.235);
      expect(preview.robotY, -2.346);
      expect(preview.robotYaw, 91.23);
    });
  });
}
