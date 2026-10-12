// rosbridge JSON 값 읽기 도우미의 규칙을 고정합니다. 로봇 진단·매핑 상태·노드 목록이
// 따로 들고 있던 같은 규칙을 한 곳(core/json_read.dart)으로 모았습니다.
import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/core/json_read.dart';

void main() {
  test('jsonInt: 정수·실수·숫자 문자열을 읽고 나머지는 0', () {
    expect(jsonInt(3), 3);
    expect(jsonInt(3.9), 3);
    expect(jsonInt('7'), 7);
    expect(jsonInt('x'), 0);
    expect(jsonInt(null), 0);
    expect(jsonInt(true), 0);
  });

  test('jsonString: 문자열은 그대로, 다른 값은 toString, null 은 빈 값', () {
    expect(jsonString('a'), 'a');
    expect(jsonString(12), '12');
    expect(jsonString(null), '');
  });

  test('jsonStringList: 목록 안의 문자열만', () {
    expect(jsonStringList(['a', 1, 'b', null]), ['a', 'b']);
    expect(jsonStringList('a'), isEmpty);
    expect(jsonStringList(null), isEmpty);
  });
}
