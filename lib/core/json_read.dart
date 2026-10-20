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
