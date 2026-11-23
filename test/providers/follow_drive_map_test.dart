import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/core/app_settings.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';

import '../ros/fake_ros_socket.dart';

Map<String, Object?> _maps(String current) => {
      'maps': [
        for (final id in ['map_a', 'map_b'])
          {'map_id': id, 'map_name': id, 'is_current': id == current},
      ],
      'current_map_id': current,
    };

Map<String, Object?> _mode(String currentMap, {String? nav2Map}) => {
      'mode': 'drive',
      'state': 'running',
      'current_map_id': currentMap,
      'running_maps': {if (nav2Map != null) 'nav2': nav2Map},
    };

void main() {
  late FakeRosServer server;
  setUp(() => server = FakeRosServer());

  void withProvider(void Function(SupervisorProvider p, FakeAsync async) body) {
    fakeAsync((async) {
      final p = SupervisorProvider(rosChannelConnector: server.connect);
      p.connect(const AppSettings());
      async.flushMicrotasks();
      body(p, async);
      async.elapse(const Duration(seconds: 30));
      p.dispose();
      async.flushMicrotasks();
    });
  }

  test('주행 지도가 바뀌면 고른 지도도 그 지도로 바뀐다', () {
    withProvider((p, async) {
      p.handleMapListForTest(_maps('map_a'));
      p.handleModeStatusForTest(_mode('map_a', nav2Map: 'map_a'));
      expect(p.selectedMapId, 'map_a');

      p.handleModeStatusForTest(_mode('map_b', nav2Map: 'map_b'));
      expect(p.selectedMapId, 'map_b');
    });
  });

  test('Nav2 가 실제로 띄운 지도를 따른다(CURRENT_MAP 만 바뀐 동안은 그대로)', () {
    withProvider((p, async) {
      p.handleMapListForTest(_maps('map_a'));
      p.handleModeStatusForTest(_mode('map_a', nav2Map: 'map_a'));
      p.handleModeStatusForTest(_mode('map_b', nav2Map: 'map_a'));
      expect(p.selectedMapId, 'map_a');
      p.handleModeStatusForTest(_mode('map_b', nav2Map: 'map_b'));
      expect(p.selectedMapId, 'map_b');
    });
  });

  test('관리자가 일부러 고른 지도는 로봇 지도가 다시 바뀌기 전까지 그대로', () {
    withProvider((p, async) {
      p.handleMapListForTest(_maps('map_a'));
      p.handleModeStatusForTest(_mode('map_a', nav2Map: 'map_a'));
      p.selectMap(const AppSettings(), 'map_b');
      p.handleModeStatusForTest(_mode('map_a', nav2Map: 'map_a'));
      expect(p.selectedMapId, 'map_b');
    });
  });

  test('금지구역 편집 중이면 따라가지 않는다', () {
    withProvider((p, async) {
      p.handleMapListForTest(_maps('map_a'));
      p.handleModeStatusForTest(_mode('map_a', nav2Map: 'map_a'));
      p.enterKeepoutEdit('map_a');
      p.handleModeStatusForTest(_mode('map_b', nav2Map: 'map_b'));
      expect(p.selectedMapId, 'map_a');
    });
  });

  test('목록에 없는 지도는 고르지 않고 목록을 다시 받은 뒤 따라간다', () {
    withProvider((p, async) {
      p.handleMapListForTest(_maps('map_a'));
      p.handleModeStatusForTest(_mode('map_a', nav2Map: 'map_a'));
      p.handleModeStatusForTest(_mode('map_c', nav2Map: 'map_c'));
      expect(p.selectedMapId, 'map_a');
      p.handleMapListForTest({
        'maps': [
          {'map_id': 'map_a', 'map_name': 'map_a'},
          {'map_id': 'map_c', 'map_name': 'map_c', 'is_current': true},
        ],
        'current_map_id': 'map_c',
      });
      p.handleModeStatusForTest(_mode('map_c', nav2Map: 'map_c'));
      expect(p.selectedMapId, 'map_c');
    });
  });
}
