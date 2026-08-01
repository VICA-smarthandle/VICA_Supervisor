// 이 파일은 로봇이 보낸 결함 하나(vica_interfaces/msg/RobotFault)를 표현합니다.
//
// rosbridge는 커스텀 메시지를 필드 map으로 직렬화해 보냅니다. JSON String 토픽이 아니므로
// RosBridgeClient가 raw map을 그대로 handler에 넘깁니다(ros_bridge_client.dart 참조).
//
// 문구(detail, suggestedAction)는 로봇의 fault_catalog.py가 만듭니다. 앱은 표시만 합니다.
// 앱에 문구 테이블을 두면 정본이 두 곳으로 갈라지고 문구 한 줄을 고치려고 앱을 다시
// 배포해야 합니다.
import '../core/fault_severity.dart';

class RobotFault {
  const RobotFault({
    required this.component,
    required this.faultCode,
    required this.severity,
    required this.active,
    required this.latched,
    required this.occurrenceCount,
    required this.firstSeen,
    required this.lastSeen,
    required this.detail,
    required this.suggestedAction,
  });

  /// 결함이 속한 컴포넌트. 로봇의 fault_catalog.COMPONENTS와 같은 값입니다.
  final String component;

  /// 기계 판독 코드. 예: MOTOR_CAN_TIMEOUT
  final String faultCode;

  final FaultSeverity severity;

  /// 현재 진행 중인지. false는 해소된 결함(CLEARED 이벤트)입니다.
  final bool active;

  /// 원인이 사라져도 유지되는지. 중앙 래치 상태를 반영하는 표시값입니다.
  final bool latched;

  /// 같은 (component, faultCode)가 관측된 누적 횟수.
  final int occurrenceCount;

  /// 표시용 시각입니다. 로봇의 신선도 판정에는 쓰이지 않습니다.
  final DateTime firstSeen;
  final DateTime lastSeen;

  /// 측정값을 포함한 상세 문구. 로봇이 만듭니다.
  final String detail;

  /// 관리자가 취할 조치. 로봇이 만듭니다.
  final String suggestedAction;

  /// 화면에 보여줄 컴포넌트 이름.
  String get componentLabelText => componentLabel(component);

  /// 결함이 이어진 시간. 관리자가 "방금 생긴 것"과 "계속되는 것"을 구분하는 값입니다.
  Duration get duration {
    final elapsed = lastSeen.difference(firstSeen);
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  /// rosbridge가 보낸 필드 map을 읽습니다.
  ///
  /// 필드가 없거나 타입이 다르면 예외를 던지지 않고 안전한 기본값을 씁니다. 앱이 파싱
  /// 실패로 죽으면 관리자가 아무 상태도 볼 수 없습니다.
  factory RobotFault.fromRosMsg(Map<String, Object?> msg) {
    return RobotFault(
      component: _asString(msg['component']),
      faultCode: _asString(msg['fault_code']),
      severity: FaultSeverity.fromValue(_asInt(msg['severity'])),
      active: msg['active'] == true,
      latched: msg['latched'] == true,
      occurrenceCount: _asInt(msg['occurrence_count']),
      firstSeen: rosTimeToDateTime(msg['first_seen']),
      lastSeen: rosTimeToDateTime(msg['last_seen']),
      detail: _asString(msg['detail']),
      suggestedAction: _asString(msg['suggested_action']),
    );
  }
}

/// builtin_interfaces/Time을 DateTime으로 바꿉니다.
///
/// rosbridge는 `{sec: 1785413444, nanosec: 792829720}` 형태로 보냅니다. 값이 없거나
/// 0이면 현재 시각을 씁니다 — 1970년으로 표시하면 관리자가 더 혼란스럽습니다.
DateTime rosTimeToDateTime(Object? value) {
  if (value is! Map) {
    return DateTime.now();
  }
  final sec = _asInt(value['sec']);
  final nanosec = _asInt(value['nanosec']);
  if (sec <= 0) {
    return DateTime.now();
  }
  return DateTime.fromMillisecondsSinceEpoch(
    sec * 1000 + (nanosec ~/ 1000000),
  );
}

String _asString(Object? value) {
  if (value is String) {
    return value;
  }
  return value?.toString() ?? '';
}

int _asInt(Object? value) {
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
