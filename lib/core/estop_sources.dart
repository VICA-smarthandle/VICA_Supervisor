const _known = <String, String>{
  'physical_f1': '물리 버튼',
  'voice': '음성',
  'stt': '음성',
  'app': '관리자 앱',
  'tipped': '넘어짐',
  'motor_can': '모터 통신 끊김',
};

const _prefixes = <String, String>{
  'motor_can': '모터 CAN',
  'physical': '물리 버튼',
  'physical_f1': '물리 버튼',
  'app': '관리자 앱',
  'voice': '음성',
  'stt': '음성',
  'imu': 'IMU',
};

/// 원인 하나의 이름. 모르는 원인은 원문 그대로 둡니다.
String estopSourceLabel(String source) {
  final known = _known[source];
  if (known != null) {
    return known;
  }
  for (final (suffix, word) in const [
    ('_stale', '신호 끊김'),
    ('_waiting', '신호 기다림')
  ]) {
    if (source.endsWith(suffix)) {
      final head = source.substring(0, source.length - suffix.length);
      return '${_prefixes[head] ?? head} $word';
    }
  }
  return source;
}
