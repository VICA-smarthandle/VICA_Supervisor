import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/models/vica_map.dart';

void main() {
  test('is_current 를 읽고, 없으면 false 다(옛 노드 호환)', () {
    final current = VicaMap.fromJson({'map_id': 'a', 'is_current': true});
    final old = VicaMap.fromJson({'map_id': 'b'});
    expect(current.isCurrent, isTrue);
    expect(old.isCurrent, isFalse);
    expect(current.toJson()['is_current'], isTrue);
  });

  test('드롭다운 이름에 (현재) 를 붙인다', () {
    expect(VicaMap.fromJson({'map_id': 'a', 'is_current': true}).displayName,
        'a (현재)');
    expect(VicaMap.fromJson({'map_id': 'a'}).displayName, 'a');
  });

  test('지도별 준비 상태(11-17): 레일·금지구역·목적지 수·저장 시각', () {
    final map = VicaMap.fromJson({
      'map_id': 'map_a',
      'map_name': '4층',
      'has_route': true,
      'has_keepout': false,
      'destination_count': 4,
      'saved_at': '2026-11-16T20:30:26',
    });
    expect(map.hasRoute, isTrue);
    expect(map.hasKeepout, isFalse);
    expect(map.destinationCount, 4);
    expect(VicaMap.fromJson(map.toJson()).destinationCount, 4);
    final old = VicaMap.fromJson({'map_id': 'old'});
    expect(old.destinationCount, isNull);
    expect(old.savedAt, '');
  });
}
