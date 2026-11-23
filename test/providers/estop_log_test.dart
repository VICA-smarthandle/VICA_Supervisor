import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/core/log_filter.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';

void main() {
  List<String> estopLogs(SupervisorProvider p) => [
        for (final log in p.logs.reversed)
          if (log.filter == LogFilter.emergencyStop) log.message,
      ];

  Map<String, Object?> state(bool active, [List<String> sources = const []]) =>
      {'active': active, 'message': '', 'sources': sources};

  test('원인이 새로 붙을 때마다 한 줄, 풀리면 해제 한 줄', () {
    final p = SupervisorProvider();
    p.handleEmergencyStopStateForTest(state(true, ['physical_f1']));
    p.handleEmergencyStopStateForTest(state(true, ['physical_f1']));
    p.handleEmergencyStopStateForTest(state(true, ['physical_f1', 'voice']));
    p.handleEmergencyStopStateForTest(state(true, ['voice']));
    p.handleEmergencyStopStateForTest(state(false));
    p.handleEmergencyStopStateForTest(state(false));
    expect(estopLogs(p), ['비상정지: 물리 버튼', '비상정지: 음성', '비상정지 해제']);
    p.dispose();
  });

  test('관리자 앱·넘어짐·통신 끊김도 모두 남긴다', () {
    final p = SupervisorProvider();
    p.handleEmergencyStopStateForTest(state(true, ['app']));
    p.handleEmergencyStopStateForTest(state(false));
    p.handleEmergencyStopStateForTest(state(true, ['tipped']));
    p.handleEmergencyStopStateForTest(state(false));
    p.handleEmergencyStopStateForTest(state(true, ['motor_can_stale']));
    expect(estopLogs(p), [
      '비상정지: 관리자 앱',
      '비상정지 해제',
      '비상정지: 넘어짐',
      '비상정지 해제',
      '비상정지: 모터 CAN 신호 끊김',
    ]);
    p.dispose();
  });

  test('원인을 안 보내는 옛 노드는 원인 모름으로 한 번', () {
    final p = SupervisorProvider();
    p.handleEmergencyStopStateForTest(state(true));
    p.handleEmergencyStopStateForTest(state(true));
    expect(estopLogs(p), ['비상정지 (원인 모름)']);
    p.dispose();
  });

  test('풀려 있는 상태 방송만 오면 아무것도 남기지 않는다', () {
    final p = SupervisorProvider();
    p.handleEmergencyStopStateForTest(state(false));
    expect(estopLogs(p), isEmpty);
    p.dispose();
  });
}
