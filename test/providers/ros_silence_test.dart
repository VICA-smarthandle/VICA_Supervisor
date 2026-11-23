import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/core/app_settings.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';
import 'package:vica_supervisor/ros/ros_bridge_client.dart';

import '../ros/fake_ros_socket.dart';

void main() {
  late FakeRosServer server;
  late DateTime clock;

  setUp(() {
    server = FakeRosServer();
    clock = DateTime(2026, 11, 17, 14, 40);
  });

  Map<String, Object?> status() => {
        'op': 'publish',
        'topic': '/robot_status',
        'msg': {'data': '{"robot_id": "vica_01"}'},
      };

  SupervisorProvider newProvider() => SupervisorProvider(
        rosChannelConnector: server.connect,
        now: () => clock,
      );

  test('5초 동안 받은 것이 없으면 응답 없음, 하나라도 오면 풀린다', () {
    fakeAsync((async) {
      final provider = newProvider();
      provider.connect(const AppSettings());
      async.flushMicrotasks();
      expect(provider.connectionState, RosConnectionState.connected);
      expect(provider.rosSilent, isFalse);

      for (var i = 0; i < 8; i++) {
        clock = clock.add(const Duration(seconds: 1));
        server.last.receive(status());
        async.flushMicrotasks();
      }
      expect(provider.rosSilent, isFalse);

      clock = clock.add(const Duration(seconds: 4));
      expect(provider.rosSilent, isFalse);
      clock = clock.add(const Duration(seconds: 1));
      expect(provider.rosSilent, isTrue);
      expect(provider.connectionState, RosConnectionState.connected);

      server.last.receive(status());
      async.flushMicrotasks();
      expect(provider.rosSilent, isFalse);

      provider.dispose();
      async.flushMicrotasks();
    });
  });

  test('붙은 순간부터 센다 — 막 붙었으면 응답 없음이 아니다', () {
    fakeAsync((async) {
      clock = clock.add(const Duration(hours: 1));
      final provider = newProvider();
      provider.connect(const AppSettings());
      async.flushMicrotasks();
      expect(provider.rosSilent, isFalse);
      provider.dispose();
      async.flushMicrotasks();
    });
  });

  test('연결이 끊겼으면 응답 없음이 아니라 오프라인이다', () {
    fakeAsync((async) {
      final provider = newProvider();
      provider.connect(const AppSettings(maxReconnectAttempts: 0));
      async.flushMicrotasks();
      clock = clock.add(const Duration(seconds: 7));
      expect(provider.rosSilent, isTrue);

      server.last.drop();
      async.flushMicrotasks();
      expect(provider.connectionState, isNot(RosConnectionState.connected));
      expect(provider.rosSilent, isFalse);

      provider.dispose();
      async.flushMicrotasks();
    });
  });
}
