import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';

/// Mission Manager 가 /vica_goal_event 로 내는 것과 같은 모양입니다.
Map<String, Object?> goalEvent(String kind) => {
      'event': kind,
      'name': '화장실',
      'reason': '',
      'map_id': 'm1',
    };

/// status app node 가 /robot_status 로 내는 것과 같은 모양입니다.
Map<String, Object?> robotStatus({
  String waitingReason = '',
  String currentGoal = '',
}) =>
    {
      'robot_id': 'vica-01',
      'robot_name': 'VICA',
      'map_id': 'm1',
      'x': 0.0,
      'y': 0.0,
      'yaw': 0.0,
      'status': 'waiting',
      'current_goal': currentGoal,
      'error_reason': '',
      'waiting_reason': waitingReason,
    };

void main() {
  late SupervisorProvider provider;

  setUp(() => provider = SupervisorProvider());
  tearDown(() => provider.dispose());

  group('goal 이벤트가 정본이다', () {
    test('처음에는 일시정지가 아니다', () {
      expect(provider.navigationPaused, isFalse);
    });

    test('goal_paused 를 받으면 일시정지다', () {
      provider.handleGoalEventForTest(goalEvent('goal_paused'));

      expect(provider.navigationPaused, isTrue);
    });

    test('상태 문자열이 일시정지를 말하지 않아도 이벤트를 믿는다', () {
      provider.handleGoalEventForTest(goalEvent('goal_paused'));
      provider.handleRobotStatusForTest(
        robotStatus(waitingReason: 'Nav2/AMCL 미실행', currentGoal: '화장실'),
      );

      expect(provider.navigationPaused, isTrue);
    });
  });

  group('일시정지가 풀리는 경우', () {
    setUp(() => provider.handleGoalEventForTest(goalEvent('goal_paused')));

    test('새 goal 이 나가면 풀린다', () {
      provider.handleGoalEventForTest(goalEvent('goal_sent'));

      expect(provider.navigationPaused, isFalse);
    });

    test('도착하면 풀린다', () {
      provider.handleGoalEventForTest(goalEvent('goal_succeeded'));

      expect(provider.navigationPaused, isFalse);
    });

    test('취소하면 풀린다', () {
      provider.handleGoalEventForTest(goalEvent('goal_canceled'));

      expect(provider.navigationPaused, isFalse);
    });

    test('실패해도 풀린다', () {
      provider.handleGoalEventForTest(goalEvent('goal_failed'));

      expect(provider.navigationPaused, isFalse);
    });

    test('비상정지도 푼다', () {
      provider.handleGoalEventForTest(goalEvent('emergency_stopped'));

      expect(provider.navigationPaused, isFalse);
    });

    test('모르는 이벤트는 상태를 흔들지 않는다', () {
      provider.handleGoalEventForTest(goalEvent('goal_teleported'));

      expect(provider.navigationPaused, isTrue);
    });
  });

  group('상태 문자열은 보조로 쓴다', () {
    test('이벤트를 못 받았어도 문자열로 복원한다', () {
      provider.handleRobotStatusForTest(
        robotStatus(waitingReason: '일시정지', currentGoal: '화장실'),
      );

      expect(provider.navigationPaused, isTrue);
    });

    test('앞뒤 공백이 있어도 읽는다', () {
      provider.handleRobotStatusForTest(
        robotStatus(waitingReason: '  일시정지  ', currentGoal: '화장실'),
      );

      expect(provider.navigationPaused, isTrue);
    });

    test('다른 대기 사유는 일시정지가 아니다', () {
      provider.handleRobotStatusForTest(
        robotStatus(waitingReason: '목표 없음'),
      );

      expect(provider.navigationPaused, isFalse);
    });
  });
}
