import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';

/// app_emergency_node 가 /app_estop_state 로 내는 것과 같은 모양입니다.
Map<String, Object?> estopState({
  required bool active,
  List<String>? sources,
  String message = '비상정지가 활성화되어 있습니다.',
}) =>
    {
      'node': 'app_emergency_node',
      'active': active,
      'app_active': sources?.contains('app') ?? false,
      'emergency_active': active,
      'safety_state': active ? 'ESTOP_ACTIVE' : 'READY',
      'reset_allowed': false,
      'auto_recovered': false,
      if (sources != null) 'sources': sources,
      'message': message,
      'timestamp': '2026-08-31T21:00:00+00:00',
    };

/// Mission Manager 가 /vica_goal_event 로 내는 것과 같은 모양입니다.
Map<String, Object?> goalEvent(String kind) => {
      'event': kind,
      'name': '화장실',
      'reason': '',
      'map_id': 'm1',
    };

void main() {
  late SupervisorProvider provider;

  setUp(() => provider = SupervisorProvider());
  tearDown(() => provider.dispose());

  group('관리자 호출 문구를 언제 붙이는가', () {
    test('처음에는 붙이지 않는다', () {
      expect(provider.emergencyCalledAdmin, isFalse);
    });

    test('물리 버튼으로 걸리면 붙인다', () {
      provider.handleEmergencyStopStateForTest(
        estopState(active: true, sources: ['physical_f1']),
      );
      expect(provider.emergencyCalledAdmin, isTrue);
    });

    test('음성으로 걸려도 붙인다', () {
      provider.handleEmergencyStopStateForTest(
        estopState(active: true, sources: ['voice']),
      );
      expect(provider.emergencyCalledAdmin, isTrue);
    });

    test('관리자가 앱에서 누른 것이면 붙이지 않는다', () {
      provider.handleEmergencyStopStateForTest(
        estopState(active: true, sources: ['app']),
      );
      expect(provider.emergencyCalledAdmin, isFalse);
    });

    test('통신 원인만이면 붙이지 않는다', () {
      provider.handleEmergencyStopStateForTest(
        estopState(active: true, sources: ['motor_can', 'physical_stale']),
      );
      expect(provider.emergencyCalledAdmin, isFalse);
    });

    test('원인을 안 보내는 옛 노드와도 붙는다', () {
      provider.handleEmergencyStopStateForTest(estopState(active: true));
      expect(provider.emergencyCalledAdmin, isFalse);
    });

    test('넘어짐으로 걸려도 붙인다(2026-10-15)', () {
      provider.handleEmergencyStopStateForTest(
        estopState(active: true, sources: ['tipped']),
      );
      expect(provider.emergencyCalledAdmin, isTrue);
      expect(provider.emergencyTipped, isTrue);
    });

    test('통신으로 서 있다가 넘어지면 그때부터 넘어짐 문구다', () {
      provider.handleEmergencyStopStateForTest(
        estopState(active: true, sources: ['motor_can_stale']),
      );
      expect(provider.emergencyCalledAdmin, isFalse);
      provider.handleEmergencyStopStateForTest(
        estopState(active: true, sources: ['motor_can_stale', 'tipped']),
      );
      expect(provider.emergencyCalledAdmin, isTrue);
      expect(provider.emergencyTipped, isTrue);
    });

    test('물리 버튼만이면 넘어짐이 아니다', () {
      provider.handleEmergencyStopStateForTest(
        estopState(active: true, sources: ['physical_f1']),
      );
      expect(provider.emergencyTipped, isFalse);
    });

    test('해제되면 문구도 사라진다', () {
      provider.handleEmergencyStopStateForTest(
        estopState(active: true, sources: ['physical_f1']),
      );
      provider.handleEmergencyStopStateForTest(
        estopState(active: false, sources: const []),
      );
      expect(provider.emergencyCalledAdmin, isFalse);
    });
  });

  group('팝업 본문은 노드를 따른다(2026-10-15)', () {
    test('떠 있는 동안 노드 문장이 바뀌면 본문도 바뀐다', () {
      provider.handleEmergencyStopStateForTest(estopState(
        active: true,
        sources: ['physical_f1'],
        message: '통신이 복구되어 비상정지를 자동 해제했습니다 (원인: motor_can_waiting)',
      ));
      provider.handleEmergencyStopStateForTest(estopState(
        active: true,
        sources: ['physical_f1'],
        message: '비상정지 버튼이 눌렸습니다.',
      ));
      expect(provider.emergencyStopMessage, '비상정지 버튼이 눌렸습니다.');
    });

    test('빈 문장이 오면 지금 본문을 지우지 않는다', () {
      provider.handleEmergencyStopStateForTest(estopState(
        active: true,
        sources: ['tipped'],
        message: '넘어짐이 감지되어 비상정지되었습니다.',
      ));
      provider.handleEmergencyStopStateForTest(
        estopState(active: true, sources: ['tipped'], message: ''),
      );
      expect(provider.emergencyStopMessage, '넘어짐이 감지되어 비상정지되었습니다.');
    });
  });

  group('비상정지와 주행 알림이 겹칠 때', () {
    test('비상정지 중 취소는 팝업으로 띄우지 않는다', () {
      provider.handleEmergencyStopStateForTest(
        estopState(active: true, sources: ['physical_f1']),
      );
      provider.handleGoalEventForTest(goalEvent('goal_canceled'));

      expect(provider.pendingGoalAlert, isNull);
    });

    test('비상정지가 아닐 때의 취소는 그대로 팝업이 뜬다', () {
      provider.handleGoalEventForTest(goalEvent('goal_canceled'));
      expect(provider.pendingGoalAlert, isNotNull);
    });

    test('비상정지 중이어도 주행 실패는 팝업이 뜬다', () {
      provider.handleEmergencyStopStateForTest(
        estopState(active: true, sources: ['physical_f1']),
      );
      provider.handleGoalEventForTest(goalEvent('goal_failed'));

      expect(provider.pendingGoalAlert, isNotNull);
      expect(
        provider.pendingGoalAlert!.description,
        contains('관리자를 호출했습니다'),
      );
    });
  });
}
