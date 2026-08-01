// 이 파일은 결함의 상태 변화 하나(vica_interfaces/msg/RobotEvent)를 표현합니다.
//
// /robot/events는 전이 시점에만 발행됩니다. 로봇의 event_deduplicator가 초안 10.3절의
// 폭주 방지 규칙을 적용하므로, **앱에서 같은 사유를 다시 억제하면 안 됩니다.**
// 억제하면 reminder 이벤트가 사라져 오래 지속되는 결함을 관리자가 놓칩니다.
//
// /robot_status.error_reason 경로는 상황이 다릅니다. 그쪽은 10 Hz로 상시 발행되므로
// supervisor_provider의 _lastLoggedErrorReason이 억제를 담당합니다. 두 경로의 억제
// 지점이 다르다는 것이 중요합니다.
import 'robot_fault.dart';

/// 결함 상태 전이. RobotEvent.msg의 TRANSITION_* 상수와 값이 같습니다.
enum FaultTransition {
  raised(0, '발생'),
  escalated(1, '등급 상승'),
  reminder(2, '지속 중'),
  cleared(3, '해소');

  const FaultTransition(this.value, this.label);

  final int value;
  final String label;

  /// 알 수 없는 값은 raised로 봅니다. 이벤트를 버리지 않습니다.
  static FaultTransition fromValue(int value) {
    for (final transition in FaultTransition.values) {
      if (transition.value == value) {
        return transition;
      }
    }
    return FaultTransition.raised;
  }
}

class RobotEvent {
  const RobotEvent({
    required this.id,
    required this.fault,
    required this.transition,
    required this.receivedAt,
  });

  /// 앱이 만드는 로컬 식별자. 목록 위젯의 key로 씁니다.
  ///
  /// 로봇은 event_id를 보내지 않습니다. 중복 판정 키는 (component, faultCode)로 충분하고,
  /// 목록 표시용 고유 id는 앱이 만드는 편이 단순합니다.
  final String id;

  final RobotFault fault;
  final FaultTransition transition;
  final DateTime receivedAt;

  /// 이 이벤트를 이력 목록에 남겨야 하는지.
  ///
  /// reminder는 "아직 안 고쳐졌다"는 반복 알림이라 이력에 쌓으면 목록이 같은 항목으로
  /// 가득 찹니다. 현재 상태는 /robot/health의 activeFaults가 보여주므로 이력에서는
  /// 제외합니다.
  bool get belongsInHistory => transition != FaultTransition.reminder;

  factory RobotEvent.fromRosMsg(
    Map<String, Object?> msg, {
    required String id,
  }) {
    final rawFault = msg['fault'];
    return RobotEvent(
      id: id,
      fault: rawFault is Map<String, Object?>
          ? RobotFault.fromRosMsg(rawFault)
          : RobotFault.fromRosMsg(const {}),
      transition: FaultTransition.fromValue(_asInt(msg['transition'])),
      receivedAt: DateTime.now(),
    );
  }
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
