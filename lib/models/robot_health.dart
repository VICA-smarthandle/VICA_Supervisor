import '../core/fault_severity.dart';
import 'robot_fault.dart';

class RobotHealth {
  const RobotHealth({
    required this.state,
    required this.readiness,
    required this.activeFaultCount,
    required this.highestSeverity,
    required this.primaryFaultCode,
    required this.activeFaults,
    required this.receivedAt,
  });

  final RobotHealthState state;

  /// 컴포넌트 이름 -> 준비 상태. 로봇의 required_components.yaml이 정한 순서와 무관하게
  final Map<String, ComponentReadiness> readiness;

  final int activeFaultCount;
  final FaultSeverity highestSeverity;

  /// highestSeverity에 해당하는 결함의 코드. 없으면 빈 문자열입니다.
  final String primaryFaultCode;

  /// 현재 활성 결함 전체. 로봇이 severity 내림차순으로 정렬해 보냅니다.
  final List<RobotFault> activeFaults;

  /// 앱이 이 메시지를 받은 시각. 만료 판정에 씁니다.
  final DateTime receivedAt;

  bool get hasFault => activeFaults.isNotEmpty;

  /// 대표 결함. 배너에 보여줍니다.
  RobotFault? get primaryFault {
    for (final fault in activeFaults) {
      if (fault.faultCode == primaryFaultCode) {
        return fault;
      }
    }
    return activeFaults.isEmpty ? null : activeFaults.first;
  }

  /// 관측 수단이 없는 컴포넌트 목록.
  List<String> get unobservableComponents {
    final names = readiness.entries
        .where((entry) => entry.value == ComponentReadiness.unknown)
        .map((entry) => entry.key)
        .toList();
    names.sort();
    return names;
  }

  /// 이 상태가 오래됐는지. 모니터가 죽으면 마지막 상태를 현재로 쓰지 않습니다.
  bool isStale(Duration timeout) {
    return DateTime.now().difference(receivedAt) > timeout;
  }

  /// rosbridge가 보낸 필드 map을 읽습니다.
  factory RobotHealth.fromRosMsg(Map<String, Object?> msg) {
    final rawFaults = msg['active_faults'];
    final faults = rawFaults is List
        ? rawFaults
            .whereType<Map<String, Object?>>()
            .map(RobotFault.fromRosMsg)
            .toList(growable: false)
        : const <RobotFault>[];

    return RobotHealth(
      state: RobotHealthState.fromValue(_asInt(msg['state'])),
      readiness: _readReadiness(msg),
      activeFaultCount: _asInt(msg['active_fault_count']),
      highestSeverity: FaultSeverity.fromValue(_asInt(msg['highest_severity'])),
      primaryFaultCode: _asString(msg['primary_fault_code']),
      activeFaults: faults,
      receivedAt: DateTime.now(),
    );
  }

  /// readiness 필드 9개를 컴포넌트 이름으로 매핑합니다.
  static Map<String, ComponentReadiness> _readReadiness(
    Map<String, Object?> msg,
  ) {
    const fields = {
      'motor': 'motor_readiness',
      'safety': 'safety_readiness',
      'localization': 'localization_readiness',
      'navigation': 'navigation_readiness',
      'lidar': 'lidar_readiness',
      'perception': 'perception_readiness',
      'guidance': 'guidance_readiness',
      'voice': 'voice_readiness',
      'app': 'app_readiness',
    };

    return {
      for (final entry in fields.entries)
        entry.key: ComponentReadiness.fromValue(_asInt(msg[entry.value])),
    };
  }
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
