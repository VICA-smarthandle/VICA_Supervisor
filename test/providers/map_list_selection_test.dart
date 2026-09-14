// 앱을 켤 때 어느 지도를 고르는지 고정합니다 (2026-09-03).
//
// **이 파일이 지키는 결함**: 이름순 첫 지도를 고르면 오늘 새로 그린 지도가 앞에
// 올 때 로봇이 달리는 지도와 다른 지도를 보게 된다. 관리자가 이미 고른 지도는
// 목록이 다시 와도 바뀌면 안 된다.
import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';

Map<String, Object?> mapList({String current = ''}) => {
      'maps': [
        {'map_id': 'vica_map_00', 'is_current': current == 'vica_map_00'},
        {'map_id': 'vica_map_0630', 'is_current': current == 'vica_map_0630'},
      ],
      'current_map_id': current,
    };

void main() {
  late SupervisorProvider provider;
  setUp(() => provider = SupervisorProvider());
  tearDown(() => provider.dispose());

  test('현재 지도가 있으면 그것을 먼저 고른다', () {
    provider.handleMapListForTest(mapList(current: 'vica_map_0630'));
    expect(provider.selectedMap?.mapId, 'vica_map_0630');
    expect(provider.currentMapId, 'vica_map_0630');
  });

  test('표시가 없으면(옛 노드) 종전대로 첫 지도다', () {
    provider.handleMapListForTest(mapList());
    expect(provider.selectedMap?.mapId, 'vica_map_00');
    expect(provider.currentMapId, '');
  });

  test('관리자가 고른 지도는 목록이 다시 와도 바뀌지 않는다', () {
    provider.handleMapListForTest(mapList(current: 'vica_map_0630'));
    provider.handleMapListForTest(mapList(current: 'vica_map_00'));
    expect(provider.selectedMap?.mapId, 'vica_map_0630');
    // 로봇이 지금 쓰는 지도는 새 값으로 — 화면이 "다르다"고 알릴 근거다.
    expect(provider.currentMapId, 'vica_map_00');
  });
}
