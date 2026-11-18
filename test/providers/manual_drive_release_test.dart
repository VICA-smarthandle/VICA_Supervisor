// 수동 조종 중에 다른 곳(음성·다른 기기)에서 주행이 시작되면 provider 가 바로 멈춘다(2026-11-18 검토).
import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/core/app_settings.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';

import '../ros/fake_ros_socket.dart';

void main() {
  for (final event in ['goal_sent', 'return_home_sent', 'patrol_started']) {
    testWidgets('$event 이 오면 수동 조종을 멈춘다', (tester) async {
      final server = FakeRosServer();
      final supervisor = SupervisorProvider(rosChannelConnector: server.connect);
      addTearDown(supervisor.dispose);
      await supervisor.connect(const AppSettings());
      await tester.pump(const Duration(seconds: 11));

      supervisor.holdTeleop(
        linear: 0.5,
        angular: 0,
        maxLinear: SupervisorProvider.manualDriveMaxLinear,
      );
      expect(supervisor.teleopActive, isTrue);
      supervisor.handleGoalEventForTest({
        'event': event,
        'map_id': 'm1',
        'name': '로비',
        'reason': '',
        'timestamp': '2026-11-18T10:00:00',
      });
      expect(supervisor.teleopActive, isFalse);
      // 마지막으로 보낸 명령은 0 이다.
      final last = server.last.sent.lastWhere((m) => m['topic'] == '/cmd_vel_req');
      expect((last['msg'] as Map)['linear'], {'x': 0.0, 'y': 0.0, 'z': 0.0});
    });
  }

  testWidgets('출발은 가속 3.0 으로 완만히, 줄이기·방향 바꾸기·떼기는 바로', (tester) async {
    final server = FakeRosServer();
    final supervisor = SupervisorProvider(rosChannelConnector: server.connect);
    addTearDown(supervisor.dispose);
    await supervisor.connect(const AppSettings());
    await tester.pump(const Duration(seconds: 11));

    List<double> sentLinear() => [
          for (final m in server.last.sent)
            if (m['topic'] == '/cmd_vel_req' && m['op'] == 'publish')
              ((m['msg'] as Map)['linear'] as Map)['x'] as double,
        ];
    void hold(double v) => supervisor.holdTeleop(
          linear: v,
          angular: 0,
          maxLinear: SupervisorProvider.manualDriveMaxLinear,
          accel: SupervisorProvider.manualDriveAccel,
        );

    hold(0.7);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    // 50 ms 마다 0.15 씩: 0.15 → 0.30 → 0.45 → 0.60 → 0.70(상한) → 0.70
    expect(sentLinear().map((v) => v.toStringAsFixed(2)).toList(),
        ['0.15', '0.30', '0.45', '0.60', '0.70', '0.70']);
    expect(supervisor.isTeleopHeld(linear: 0.7, angular: 0), isTrue);

    hold(0.3); // 줄이기는 바로
    expect(sentLinear().last, closeTo(0.3, 1e-9));
    hold(-0.3); // 방향 바꾸기: 0 을 지나 반대쪽으로 한 걸음
    expect(sentLinear().last, closeTo(-0.15, 1e-9));
    supervisor.releaseTeleop(); // 떼면 바로 0
    expect(sentLinear().last, 0.0);
    expect(supervisor.teleopActive, isFalse);
  });

  testWidgets('지도 그리기 조종판(가속 인자 없음)은 예전처럼 바로', (tester) async {
    final server = FakeRosServer();
    final supervisor = SupervisorProvider(rosChannelConnector: server.connect);
    addTearDown(supervisor.dispose);
    await supervisor.connect(const AppSettings());
    await tester.pump(const Duration(seconds: 11));
    supervisor.holdTeleop(linear: 0.3, angular: 0);
    final first = server.last.sent.lastWhere((m) => m['topic'] == '/cmd_vel_req');
    expect(((first['msg'] as Map)['linear'] as Map)['x'], 0.3);
    supervisor.releaseTeleop();
  });
}

