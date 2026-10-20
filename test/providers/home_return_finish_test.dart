import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/models/goal_event.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';

Map<String, Object?> goalEvent(String kind, {String name = '홈'}) => {
      'event': kind,
      'name': name,
      'reason': '',
      'map_id': 'm1',
    };

void main() {
  late SupervisorProvider provider;

  setUp(() => provider = SupervisorProvider());
  tearDown(() => provider.dispose());

  group('이름표가 앱에 닿는다', () {
    test('홈 복귀 종료 3종이 unknown 으로 떨어지지 않는다', () {
      expect(GoalEventKind.fromWire('return_home_succeeded'),
          GoalEventKind.returnHomeSucceeded);
      expect(GoalEventKind.fromWire('return_home_failed'),
          GoalEventKind.returnHomeFailed);
      expect(GoalEventKind.fromWire('return_home_canceled'),
          GoalEventKind.returnHomeCanceled);
    });

    test('state_idle 을 안다', () {
      expect(GoalEventKind.fromWire('state_idle'), GoalEventKind.stateIdle);
    });

    test('state_idle 은 팝업을 띄우지 않는다', () {
      expect(GoalEventKind.stateIdle.needsPopup, isFalse);
      expect(GoalEventKind.stateIdle.isFailure, isFalse);
    });
  });

  group('홈 복귀가 끝나면 일시정지 표시가 남지 않는다', () {
    test('도착', () {
      provider.handleGoalEventForTest(goalEvent('goal_paused'));
      expect(provider.navigationPaused, isTrue);

      provider.handleGoalEventForTest(goalEvent('return_home_succeeded'));

      expect(provider.navigationPaused, isFalse);
    });

    test('실패', () {
      provider.handleGoalEventForTest(goalEvent('goal_paused'));
      provider.handleGoalEventForTest(goalEvent('return_home_failed'));
      expect(provider.navigationPaused, isFalse);
    });

    test('취소', () {
      provider.handleGoalEventForTest(goalEvent('goal_paused'));
      provider.handleGoalEventForTest(goalEvent('return_home_canceled'));
      expect(provider.navigationPaused, isFalse);
    });

    test('state_idle 도 표시를 되맞춘다', () {
      provider.handleGoalEventForTest(goalEvent('goal_paused'));
      provider.handleGoalEventForTest(goalEvent('state_idle', name: ''));
      expect(provider.navigationPaused, isFalse);
    });
  });

  group('홈 복귀 성패는 visitedOk 에 그대로 남는다', () {
    test('도착하면 가 본 자리가 된다', () {
      provider.handleGoalEventForTest(goalEvent('return_home_succeeded'));
      expect(provider.navigationPaused, isFalse);
    });
  });
}
