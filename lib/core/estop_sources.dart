// 비상정지 원인 이름(2026-11-17 알림 및 로그 '비상정지' 분류).
//
// /app_estop_state 의 sources 는 지금 래치를 붙들고 있는 원인이다(app_emergency_node.py):
// physical_f1(물리 버튼) · voice(음성 '멈춰') · app(관리자 앱) · tipped(넘어짐) ·
// motor_can · *_stale · *_waiting(통신 끊김). 사용자 11-17: 비상정지가 실제로 걸린 경우는
// 원인과 상관없이 모두 남긴다.

const _known = <String, String>{
  'physical_f1': '물리 버튼',
  'voice': '음성',
  'stt': '음성',
  'app': '관리자 앱',
  'tipped': '넘어짐',
  'motor_can': '모터 통신 끊김',
};

// *_stale · *_waiting 앞부분의 이름.
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
