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
}
