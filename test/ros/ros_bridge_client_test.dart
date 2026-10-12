// rosbridge 소켓이 끊기거나 연결이 실패할 때 RosBridgeClient 가 내는 소식과
// 기다리던 서비스 호출의 끝을 고정합니다.
//
// **이 파일이 지키는 결함**: 소켓이 저절로 끊겨도 채널을 그대로 들고 있어, 끊긴 뒤
// 부른 서비스는 죽은 소켓에 요청을 보내고 5초 timeout 까지 응답을 기다렸습니다.
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/ros/ros_bridge_client.dart';

import 'fake_ros_socket.dart';

void main() {
  late FakeRosServer server;
  late List<RosConnectionState> states;
  late RosBridgeClient client;

  setUp(() {
    server = FakeRosServer();
    states = [];
    client = RosBridgeClient(
      onState: (state, _) => states.add(state),
      connector: server.connect,
    );
  });

  test('연결 실패 한 번은 실패 뒤 연결 해제, 두 소식으로 온다', () async {
    // provider 가 재시도 횟수를 셀 때 이 둘을 한 번으로 봐야 하는 이유입니다.
    server.refuse = true;

    await client.connect('ws://robot:9090');

    expect(states, [
      RosConnectionState.connecting,
      RosConnectionState.failed,
      RosConnectionState.disconnected,
    ]);
    expect(client.state, RosConnectionState.disconnected);
  });

  test('소켓이 끊기면 기다리던 서비스 호출이 timeout 전에 실패한다', () {
    fakeAsync((async) {
      client.connect('ws://robot:9090');
      async.flushMicrotasks();
      expect(client.state, RosConnectionState.connected);

      Object? error;
      client.callService(service: '/vica/home/get').then<void>((_) {},
          onError: (Object e) {
        error = e;
      });
      async.flushMicrotasks();
      expect(error, isNull);

      server.last.drop();
      async.flushMicrotasks();

      // 5초 timeout 을 기다리지 않습니다.
      expect(error, isA<StateError>());
      expect((error! as StateError).message, 'ROS 연결이 종료되었습니다.');
      expect(states.last, RosConnectionState.disconnected);
      expect(server.last.sinkClosed, isTrue);
    });
  });

  test('끊긴 뒤 부른 서비스는 바로 연결 안 됨으로 실패한다', () {
    fakeAsync((async) {
      client.connect('ws://robot:9090');
      async.flushMicrotasks();
      server.last.drop();
      async.flushMicrotasks();

      Object? error;
      client.callService(service: '/vica/home/get').then<void>((_) {},
          onError: (Object e) {
        error = e;
      });
      async.flushMicrotasks();

      expect(error, isA<StateError>());
      expect((error! as StateError).message, 'ROS Bridge에 연결되지 않았습니다.');
      // 죽은 소켓에 요청을 보내지 않았습니다.
      expect(
        server.last.sent.where((m) => m['op'] == 'call_service'),
        isEmpty,
      );
    });
  });

  test('소켓 오류도 기다리던 서비스 호출을 바로 실패시킨다', () {
    fakeAsync((async) {
      client.connect('ws://robot:9090');
      async.flushMicrotasks();

      Object? error;
      client.callService(service: '/vica/home/get').then<void>((_) {},
          onError: (Object e) {
        error = e;
      });
      async.flushMicrotasks();

      server.last.fail(StateError('broken pipe'));
      async.flushMicrotasks();

      expect(error, isA<StateError>());
      expect(states.last, RosConnectionState.failed);
    });
  });

  test('연결된 동안 서비스 응답은 그대로 돌아온다', () {
    fakeAsync((async) {
      client.connect('ws://robot:9090');
      async.flushMicrotasks();

      RosServiceResponse? response;
      unawaited(
        client.callService(service: '/vica/home/get').then((r) => response = r),
      );
      async.flushMicrotasks();
      final id = server.last.sent.last['id'];
      server.last.receive({
        'op': 'service_response',
        'id': id,
        'result': true,
        'values': {'success': true, 'message': 'ok'},
      });
      async.flushMicrotasks();

      expect(response?.success, isTrue);
      expect(response?.message, 'ok');
    });
  });
}
