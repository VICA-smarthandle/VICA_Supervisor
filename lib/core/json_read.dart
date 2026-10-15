// rosbridge 가 보낸 JSON 값을 화면이 쓸 타입으로 읽는 작은 도우미들입니다.
//
// 값이 없거나 타입이 달라도 예외를 내지 않고 빈 값(0·''·빈 목록)을 돌려줍니다. 메시지
// 한 칸이 어긋났다고 그 메시지 전체를 버리면 안 되는 자리에서 씁니다. 로봇 진단
// (RobotHealth·RobotFault·RobotEvent)·매핑 상태·노드 목록이 같은 규칙을 따로 들고
// 있던 것을 모았습니다(검토 35bc1d0 D4).
//
// 이 규칙이 맞지 않는 자리(숫자 문자열을 받으면 안 되는 곳)는 지금처럼
// `(value as num?)?.toInt()` 를 그 자리에 직접 씁니다.

/// 정수. 숫자면 버림, 숫자 문자열('3')도 읽고, 나머지는 0.
int jsonInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value) ?? 0;
  }
  return 0;
}

/// 문자열. 문자열이 아니면 toString(), null 이면 ''.
String jsonString(Object? value) {
  if (value is String) {
    return value;
  }
  return value?.toString() ?? '';
}

/// 문자열 목록. 목록이 아니면 빈 목록이고, 목록 안의 문자열이 아닌 것은 버립니다.
List<String> jsonStringList(Object? value) {
  if (value is! List) {
    return const [];
  }
  return value.whereType<String>().toList(growable: false);
}
