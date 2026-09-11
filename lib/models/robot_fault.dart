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
