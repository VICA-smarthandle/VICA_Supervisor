import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';

/// Mission Manager 가 /vica_goal_event 로 내는 것과 같은 모양입니다.
Map<String, Object?> goalEvent(String kind) => {
      'event': kind,
      'name': '화장실',
      'reason': kind == 'goal_failed' ? 'Nav2 task failed' : '',
      'map_id': 'm1',
    };

void main() {
  late SupervisorProvider provider;

  setUp(() => provider = SupervisorProvider());
  tearDown(() => provider.dispose());

  test('실패 뒤 다시 출발하면 띄우기 전인 팝업은 아예 띄우지 않는다', () {
    provider.handleGoalEventForTest(goalEvent('goal_failed'));
    expect(provider.pendingGoalAlert, isNotNull);

    provider.handleGoalEventForTest(goalEvent('goal_sent'));

    expect(provider.pendingGoalAlert, isNull);
  });

  test('이미 띄운 팝업은 다시 출발하면 닫아야 한다고 표시한다', () {
    provider.handleGoalEventForTest(goalEvent('goal_failed'));
    final shown = provider.pendingGoalAlert!;
    provider.consumeGoalAlert();
    expect(provider.isGoalAlertResolved(shown.id), isFalse);

    provider.handleGoalEventForTest(goalEvent('goal_sent'));

    expect(provider.isGoalAlertResolved(shown.id), isTrue);
  });

  test('accepted 와 홈 복귀 출발도 같은 뜻이다', () {
    for (final restart in ['goal_accepted', 'return_home_sent']) {
      provider.handleGoalEventForTest(goalEvent('goal_failed'));
      final shown = provider.pendingGoalAlert!;
      provider.consumeGoalAlert();

      provider.handleGoalEventForTest(goalEvent(restart));

      expect(provider.isGoalAlertResolved(shown.id), isTrue, reason: restart);
    }
  });

  test('다시 출발하지 않으면 팝업은 그대로 남는다', () {
    provider.handleGoalEventForTest(goalEvent('goal_failed'));
    final shown = provider.pendingGoalAlert!;
    provider.consumeGoalAlert();

    provider.handleGoalEventForTest(goalEvent('state_idle'));

    expect(provider.isGoalAlertResolved(shown.id), isFalse);
  });

  test('새 실패 팝업은 지난 팝업의 풀림 표시에 영향받지 않는다', () {
    provider.handleGoalEventForTest(goalEvent('goal_failed'));
    final first = provider.pendingGoalAlert!;
    provider.consumeGoalAlert();
    provider.handleGoalEventForTest(goalEvent('goal_sent'));
    expect(provider.isGoalAlertResolved(first.id), isTrue);

    provider.handleGoalEventForTest(goalEvent('goal_failed'));
    final second = provider.pendingGoalAlert!;

    expect(second.id, isNot(first.id));
    expect(provider.isGoalAlertResolved(second.id), isFalse);
  });

  test('실패 사실은 알림 목록에 남는다', () {
    provider.handleGoalEventForTest(goalEvent('goal_failed'));
    provider.handleGoalEventForTest(goalEvent('goal_sent'));

    expect(
      provider.logs.map((log) => log.message),
      contains(contains('주행 실패')),
    );
  });

  test('대기 만료 팝업은 곧바로 나가는 홈 복귀에 거둬지지 않는다(2026-10-07)', () {
    provider.handleGoalEventForTest({
      'event': 'wait_expired',
      'name': '화장실',
      'wait_place': 'spot',
      'wait_minutes': 30,
      'map_id': 'm1',
    });
    final shown = provider.pendingGoalAlert!;
    provider.handleGoalEventForTest(goalEvent('return_home_sent'));
    expect(provider.pendingGoalAlert, isNotNull, reason: '띄우기 전이면 남는다');
    provider.consumeGoalAlert();
    provider.handleGoalEventForTest(goalEvent('return_home_sent'));
    expect(provider.isGoalAlertResolved(shown.id), isFalse);
  });
}
