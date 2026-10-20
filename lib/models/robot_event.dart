import 'robot_fault.dart';
import '../core/json_read.dart';

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
    required this.fault,
    required this.transition,
    required this.receivedAt,
  });

  final RobotFault fault;
  final FaultTransition transition;
  final DateTime receivedAt;

  /// 이 이벤트를 이력 목록에 남겨야 하는지.
  bool get belongsInHistory => transition != FaultTransition.reminder;

  factory RobotEvent.fromRosMsg(Map<String, Object?> msg) {
    final rawFault = msg['fault'];
    return RobotEvent(
      fault: rawFault is Map<String, Object?>
          ? RobotFault.fromRosMsg(rawFault)
          : RobotFault.fromRosMsg(const {}),
      transition: FaultTransition.fromValue(jsonInt(msg['transition'])),
      receivedAt: DateTime.now(),
    );
  }
}
