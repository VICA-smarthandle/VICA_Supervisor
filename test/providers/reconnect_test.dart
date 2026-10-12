// rosbridge 자동 재연결이 몇 번 끊겨도 멈추지 않는지 고정합니다.
//
// **이 파일이 지키는 결함**: 재시도 횟수를 다시 붙어도 0 으로 되돌리지 않았고, 연결
// 실패 한 번이 '실패'·'연결 해제' 두 소식으로 와서 두 번씩 셌습니다. 그래서 상한
// 5회면 끊김이 몇 번 쌓인 뒤로 자동 재연결이 아무 말 없이 멈췄습니다. 또 이미 바뀐
// 옛 연결이 뒤늦게 낸 '실패'가 지금 연결의 상태를 덮고, 새 연결에 옛 주소로
// 재연결을 걸었습니다.
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

      // 젯슨 rosbridge 가 꺼진 채로 있습니다.
      server.refuse = true;
      server.last.drop();
      async.flushMicrotasks();
      async.elapse(_retryDelay * 20);

      // 처음 연결 1번 + 상한 3번을 모두 시도합니다(종전에는 2번 만에 멈췄습니다).
      expect(server.sockets, hasLength(1 + 3));
      expect(provider.connectionState, RosConnectionState.disconnected);

      provider.dispose();
      async.flushMicrotasks();
    });
  });

  // 진짜 web_socket_channel 은 연결에 실패한 채널의 sink.close() 가 끝나지 않는다. 그것을
  // 기다리면 로그아웃(묻기 → 연결 끊기 → 로그아웃)이 연결 끊기에서 멈췄다(10-12 검토).
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

      // 상한이 1번이어도, 붙어서 10초를 버틴 연결이 끊기면 매번 다시 붙습니다.
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

  // 붙자마자 끊는 서버(예: 기동하다 죽기를 되풀이하는 rosbridge)에는 3초마다 끝없이 붙으며
  // 지도·장소를 다시 받지 않습니다. 종전처럼 상한에서 멈춥니다(10-12 검토).
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

      // 처음 연결 1번 + 상한 3번.
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

      // 옛 주소로 연결을 거는 사이(응답 대기) 관리자가 주소를 고쳐 다시 연결합니다.
      provider.connect(const AppSettings(rosBridgeUrl: 'ws://old:9090'));
      async.flushMicrotasks();
      provider.connect(const AppSettings(rosBridgeUrl: 'ws://new:9090'));
      async.flushMicrotasks();
      server.sockets[1].open();
      async.flushMicrotasks();
      expect(provider.connectionState, RosConnectionState.connected);

      // 옛 연결 시도가 이제야 실패합니다.
      server.sockets[0].failOpen();
      async.flushMicrotasks();

      expect(provider.connectionState, RosConnectionState.connected);
      async.elapse(_retryDelay * 5);
      // 새 연결에 옛 주소로 재연결을 걸지 않았습니다.
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
