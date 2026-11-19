// 빔포밍 회전(호출 방향 회전) 켜고 끄기 — 2026-11-19 사용자, 캔버스 101번 보드.
// 음성 노드가 /vica/wake_doa_turn/enable(SetBool)을 열고 /vica/wake_doa_turn/enabled(latched Bool)를 냅니다.
// 앱은 서비스 응답 문구만 돌려주고, 켜짐/꺼짐 표시는 상태 토픽만 따릅니다.
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/core/app_settings.dart';
import 'package:vica_supervisor/core/log_filter.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';

import '../ros/fake_ros_socket.dart';

const _settings = AppSettings();
const _service = '/vica/wake_doa_turn/enable';
const _state = '/vica/wake_doa_turn/enabled';

void main() {
  late FakeRosServer server;

  setUp(() => server = FakeRosServer());

  List<String> connectionLogs(SupervisorProvider provider) => [
        for (final log in provider.logs)
          if (log.filter == LogFilter.connection) log.message,
      ];

  /// 연결한 provider 로 setWakeDoaTurn([on]) 을 부르고 음성 노드가 [values] 로 답한 뒤의 결과와,
  /// 그 호출 뒤 새로 생긴 연결 기록(최신 먼저). 연결 자체의 기록('ROS 연결 시도' 등)은 뺀다.
  ((bool, String), SupervisorProvider, List<String>) run(
    bool on,
    Map<String, Object?> values, {
    bool result = true,
  }) {
    late (bool, String) reply;
    late SupervisorProvider provider;
    late int before;
    fakeAsync((async) {
      provider = SupervisorProvider(rosChannelConnector: server.connect);
      provider.connect(_settings);
      async.flushMicrotasks();
      before = connectionLogs(provider).length;
      provider.setWakeDoaTurn(on).then((value) => reply = value);
      async.flushMicrotasks();
      expect(server.last.answer(_service, values, result: result), isTrue);
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 30));
    });
    final logs = connectionLogs(provider);
    return (reply, provider, logs.take(logs.length - before).toList());
  }

  test('연결이 없으면 부르지 않고 연결 안 됨이라고 답한다', () async {
    final provider = SupervisorProvider(rosChannelConnector: server.connect);
    expect(await provider.setWakeDoaTurn(true), (false, 'ROS Bridge에 연결되지 않았습니다.'));
    expect(server.sockets, isEmpty);
  });

  test('켜기: SetBool data=true 로 부르고 노드 문구를 그대로 돌려준다', () {
    final (reply, provider, logs) = run(true, {'success': true, 'message': '빔포밍 회전을 켰습니다'});
    expect(reply, (true, '빔포밍 회전을 켰습니다'));
    final call = server.last.sent.lastWhere((c) => c['op'] == 'call_service' && c['service'] == _service);
    expect(call['type'], 'std_srvs/srv/SetBool');
    expect(call['args'], {'data': true});
    // 표시는 상태 토픽이 정본이다 — 응답만으로 켜짐이라고 미리 그리지 않는다.
    expect(provider.wakeDoaTurnOn, isNull);
    // 수락은 기록하지 않는다(실패만).
    expect(logs, isEmpty);
  });

  test('끄기: data=false 로 부른다', () {
    final (reply, _, _) = run(false, {'success': true, 'message': '빔포밍 회전을 껐습니다'});
    expect(reply, (true, '빔포밍 회전을 껐습니다'));
    final call = server.last.sent.lastWhere((c) => c['op'] == 'call_service' && c['service'] == _service);
    expect(call['args'], {'data': false});
  });

  test('노드가 거절하면 노드 문구, 문구가 비면 기본 문구 — 둘 다 연결 기록에 남는다', () {
    final (refused, _, logs1) = run(true, {'success': false, 'message': '서비스 없음'});
    expect(refused, (false, '서비스 없음'));
    expect(logs1, ['서비스 없음']);

    final (blank, _, logs2) = run(true, {'success': false, 'message': ''});
    expect(blank, (false, '빔포밍 회전을 바꾸지 못했습니다.'));
    expect(logs2, ['빔포밍 회전을 바꾸지 못했습니다.']);
  });

  test('노드가 문구 없이 수락하면 켰습니다/껐습니다를 대신 띄운다', () {
    final (on, _, _) = run(true, {'success': true, 'message': ''});
    expect(on, (true, '빔포밍 회전을 켰습니다'));
    final (off, _, _) = run(false, {'success': true, 'message': ''});
    expect(off, (true, '빔포밍 회전을 껐습니다'));
  });

  test('호출 자체가 실패하면(서비스 없는 옛 음성 노드) 실패 문구에 사유를 붙여 기록한다', () {
    // rosbridge 가 result=false 로 답하면 클라이언트가 예외를 던진다(ros_bridge_client.dart).
    final (reply, _, logs) = run(true, {}, result: false);
    expect(reply.$1, isFalse);
    expect(reply.$2, startsWith('빔포밍 회전을 바꾸지 못했습니다: '));
    expect(logs, [reply.$2]);
  });

  test('상태 토픽을 Bool 로 구독하고, 받은 값을 따라간다', () {
    fakeAsync((async) {
      final provider = SupervisorProvider(rosChannelConnector: server.connect);
      provider.connect(_settings);
      async.flushMicrotasks();
      final subscribe = server.last.sent.where((c) => c['op'] == 'subscribe' && c['topic'] == _state);
      expect(subscribe.single['type'], 'std_msgs/Bool');
      expect(provider.wakeDoaTurnOn, isNull);

      server.last.receive({'op': 'publish', 'topic': _state, 'msg': {'data': true}});
      async.flushMicrotasks();
      expect(provider.wakeDoaTurnOn, isTrue);

      server.last.receive({'op': 'publish', 'topic': _state, 'msg': {'data': false}});
      async.flushMicrotasks();
      expect(provider.wakeDoaTurnOn, isFalse);
    });
  });

  test('끊기면 모름(null)으로 비운다 — 다시 붙으면 노드가 남긴 값으로 채워진다', () {
    fakeAsync((async) {
      final provider = SupervisorProvider(rosChannelConnector: server.connect);
      provider.connect(_settings);
      async.flushMicrotasks();
      server.last.receive({'op': 'publish', 'topic': _state, 'msg': {'data': true}});
      async.flushMicrotasks();
      expect(provider.wakeDoaTurnOn, isTrue);

      server.last.drop();
      async.flushMicrotasks();
      expect(provider.wakeDoaTurnOn, isNull);

      async.elapse(const Duration(seconds: 10));
      expect(server.sockets.length, greaterThan(1), reason: '다시 붙어야 한다');
      server.last.receive({'op': 'publish', 'topic': _state, 'msg': {'data': false}});
      async.flushMicrotasks();
      expect(provider.wakeDoaTurnOn, isFalse);
    });
  });
}
