import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/core/app_settings.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';
import 'package:vica_supervisor/ros/ros_bridge_client.dart';

import '../ros/fake_ros_socket.dart';

const _retryDelay = Duration(seconds: 3);

void main() {
  late FakeRosServer server;

  SupervisorProvider newProvider() =>
      SupervisorProvider(rosChannelConnector: server.connect);

  setUp(() => server = FakeRosServer());

  test('연결 실패 한 번은 재시도 한 번으로 센다', () {
    fakeAsync((async) {
      final provider = newProvider();
      provider.connect(const AppSettings(maxReconnectAttempts: 3));
      async.flushMicrotasks();
      expect(provider.connectionState, RosConnectionState.connected);

      server.refuse = true;
      server.last.drop();
      async.flushMicrotasks();
      async.elapse(_retryDelay * 20);

      expect(server.sockets, hasLength(1 + 3));
      expect(provider.connectionState, RosConnectionState.disconnected);

      provider.dispose();
      async.flushMicrotasks();
    });
  });

  test('연결에 실패한 뒤에도 연결 끊기(로그아웃 첫 단계)가 끝난다', () {
    fakeAsync((async) {
      server.refuse = true;
      final provider = newProvider();
      provider.connect(const AppSettings(maxReconnectAttempts: 0));
      async.flushMicrotasks();
      expect(provider.connectionState, isNot(RosConnectionState.connected));

      var disconnected = false;
      provider.disconnect().then((_) => disconnected = true);
      async.flushMicrotasks();
      expect(disconnected, isTrue);
      expect(provider.connectionState, RosConnectionState.disconnected);

      provider.dispose();
      async.flushMicrotasks();
    });
  });

  test('다시 붙어 버티면 재시도 횟수를 처음부터 센다', () {
    fakeAsync((async) {
      final provider = newProvider();
      provider.connect(const AppSettings(maxReconnectAttempts: 1));
      async.flushMicrotasks();

      for (var drop = 1; drop <= 4; drop += 1) {
        async.elapse(const Duration(seconds: 10));
        server.last.drop();
        async.flushMicrotasks();
        expect(provider.connectionState, RosConnectionState.disconnected);

        async.elapse(_retryDelay);
        expect(server.sockets, hasLength(1 + drop), reason: '끊김 $drop번째');
        expect(provider.connectionState, RosConnectionState.connected);
      }

      provider.dispose();
      async.flushMicrotasks();
    });
  });

  test('붙자마자 끊기는 연결은 상한에서 멈춘다', () {
    fakeAsync((async) {
      final provider = newProvider();
      provider.connect(const AppSettings(maxReconnectAttempts: 3));
      async.flushMicrotasks();

      for (var i = 0; i < 10; i += 1) {
        server.last.drop();
        async.flushMicrotasks();
        async.elapse(_retryDelay);
      }

      expect(server.sockets, hasLength(1 + 3));

      provider.dispose();
      async.flushMicrotasks();
    });
  });

  test('재연결 뒤에도 토픽을 다시 구독한다', () {
    fakeAsync((async) {
      final provider = newProvider();
      provider.connect(const AppSettings());
      async.flushMicrotasks();
      server.last.drop();
      async.flushMicrotasks();
      async.elapse(_retryDelay);

      final subscribed = server.last.sent
          .where((m) => m['op'] == 'subscribe')
          .map((m) => m['topic']);
      expect(subscribed, contains('/robot_status'));

      provider.dispose();
      async.flushMicrotasks();
    });
  });

  test('바뀐 옛 연결이 뒤늦게 낸 실패는 지금 연결에 끼어들지 않는다', () {
    fakeAsync((async) {
      server.autoOpen = false;
      final provider = newProvider();

      provider.connect(const AppSettings(rosBridgeUrl: 'ws://old:9090'));
      async.flushMicrotasks();
      provider.connect(const AppSettings(rosBridgeUrl: 'ws://new:9090'));
      async.flushMicrotasks();
      server.sockets[1].open();
      async.flushMicrotasks();
      expect(provider.connectionState, RosConnectionState.connected);

      server.sockets[0].failOpen();
      async.flushMicrotasks();

      expect(provider.connectionState, RosConnectionState.connected);
      async.elapse(_retryDelay * 5);
      expect(server.sockets, hasLength(2));
      expect(provider.connectionState, RosConnectionState.connected);

      provider.dispose();
      async.flushMicrotasks();
    });
  });

  test('연결을 끊으면 상태가 연결 해제가 되고 재연결하지 않는다', () {
    fakeAsync((async) {
      final provider = newProvider();
      provider.connect(const AppSettings());
      async.flushMicrotasks();

      provider.disconnect();
      async.flushMicrotasks();
      async.elapse(_retryDelay * 5);

      expect(provider.connectionState, RosConnectionState.disconnected);
      expect(provider.connectionDetail, 'ROS 연결 해제');
      expect(server.sockets, hasLength(1));

      provider.dispose();
      async.flushMicrotasks();
    });
  });
}
