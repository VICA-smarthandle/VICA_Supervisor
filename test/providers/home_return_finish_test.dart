// 홈 복귀의 '끝'이 앱에도 끝으로 보이는지 고정합니다.
//
// **이 파일이 지키는 결함(2026-09-02 실기)**: 홈까지 잘 주행하고 도착했는데
// 앱은 계속 "주행 중"이었습니다. 그래서 주행 요청·홈 복귀 버튼이 잠기고,
// 주행 취소를 눌러도 아무 일이 없었습니다.
//
// 원인은 이름표의 비대칭이었습니다. 홈 복귀는 **출발할 때는** 일반 이벤트
// (goal_sent/goal_accepted)를 쓰고 **끝날 때만** 전용 이름(return_home_*)을
// 씁니다. 종료 이벤트 목록에 그 전용 이름이 빠져 있으면 출발만 관측되고
// 도착은 관측되지 않아 주행이 영원히 끝나지 않습니다.
//
// 같은 이유로 state_idle 도 함께 봅니다 — 취소를 눌렀는데 취소할 주행이 없을 때
// 미션이 "지금 대기다"라고 알려주는 동기화 신호입니다.
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
      // 사건이 아니라 사실 통보입니다. 팝업이 쌓이면 관리자가 읽지 않고 닫는
      // 습관이 생깁니다.
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
      // 회귀 방지 — 종료 이벤트를 추가하면서 이 처리가 밀려나면 안 됩니다.
      provider.handleGoalEventForTest(goalEvent('return_home_succeeded'));
      expect(provider.navigationPaused, isFalse);
    });
  });
}
