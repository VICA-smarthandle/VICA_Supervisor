// 비상정지 팝업이 '관리자를 호출했다'를 언제 말하는지 고정합니다.
//
// **이 파일이 지키는 것**: 물리 버튼이나 음성으로 걸린 비상정지는 로봇이
// 이용자에게 관리자를 부르겠다고 안내하므로 관리자 화면도 그 사실을 알아야
// 합니다. 반대로 관리자가 앱에서 직접 누른 경우에는 부르는 사람과 받는 사람이
// 같아 그 문구가 필요 없습니다.
//
// 원인은 앱이 스스로 알 수 없고 app_emergency_node 가 /app_estop_state 에
// 실어 보냅니다(2026-08-31). 그 필드가 사라지거나 이름이 바뀌면 두 경우가 같은
// 문구로 보이는데, 화면만 봐서는 잘못된 것을 알아채기 어렵습니다.
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
      // 이쪽은 정지 중이면 자동 복구를 밟는 별개 경로입니다(CLAUDE.md).
      provider.handleEmergencyStopStateForTest(
        estopState(active: true, sources: ['motor_can', 'physical_stale']),
      );
      expect(provider.emergencyCalledAdmin, isFalse);
    });

    test('원인을 안 보내는 옛 노드와도 붙는다', () {
      // sources 키가 없으면 원인을 모르는 것으로 보고 문구를 붙이지 않습니다.
      // 모르면서 "관리자를 불렀다"고 말하는 쪽이 더 나쁩니다.
      provider.handleEmergencyStopStateForTest(estopState(active: true));
      expect(provider.emergencyCalledAdmin, isFalse);
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

  group('비상정지와 주행 알림이 겹칠 때', () {
    test('비상정지 중 취소는 팝업으로 띄우지 않는다', () {
      // 주행 중 물리 버튼을 누르면 비상정지와 목적지 취소가 함께 일어납니다.
      // 둘 다 팝업으로 띄우면 같은 사건을 두 번 알리는 것입니다.
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
      // 실패는 아무도 누르지 않았는데 로봇이 스스로 포기한 별개 사건입니다.
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
