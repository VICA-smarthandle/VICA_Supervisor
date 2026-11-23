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
    expect(await provider.setWakeDoaTurn(true),
        (false, 'ROS Bridge에 연결되지 않았습니다.'));
    expect(server.sockets, isEmpty);
  });

  test('켜기: SetBool data=true 로 부르고 노드 문구를 그대로 돌려준다', () {
    final (reply, provider, logs) =
        run(true, {'success': true, 'message': '빔포밍 회전을 켰습니다'});
    expect(reply, (true, '빔포밍 회전을 켰습니다'));
    final call = server.last.sent.lastWhere(
        (c) => c['op'] == 'call_service' && c['service'] == _service);
    expect(call['type'], 'std_srvs/srv/SetBool');
    expect(call['args'], {'data': true});
    expect(provider.wakeDoaTurnOn, isNull);
    expect(logs, isEmpty);
  });

  test('끄기: data=false 로 부른다', () {
    final (reply, _, _) =
        run(false, {'success': true, 'message': '빔포밍 회전을 껐습니다'});
    expect(reply, (true, '빔포밍 회전을 껐습니다'));
    final call = server.last.sent.lastWhere(
        (c) => c['op'] == 'call_service' && c['service'] == _service);
    expect(call['args'], {'data': false});
  });

  test('노드가 거절하면 노드 문구, 문구가 비면 기본 문구 — 둘 다 연결 기록에 남는다', () {
    final (refused, _, logs1) =
        run(true, {'success': false, 'message': '서비스 없음'});
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
      final subscribe = server.last.sent
          .where((c) => c['op'] == 'subscribe' && c['topic'] == _state);
      expect(subscribe.single['type'], 'std_msgs/Bool');
      expect(provider.wakeDoaTurnOn, isNull);

      server.last.receive({
        'op': 'publish',
        'topic': _state,
        'msg': {'data': true}
      });
      async.flushMicrotasks();
      expect(provider.wakeDoaTurnOn, isTrue);

      server.last.receive({
        'op': 'publish',
        'topic': _state,
        'msg': {'data': false}
      });
      async.flushMicrotasks();
      expect(provider.wakeDoaTurnOn, isFalse);
    });
  });

  test('끊기면 모름(null)으로 비운다 — 다시 붙으면 노드가 남긴 값으로 채워진다', () {
    fakeAsync((async) {
      final provider = SupervisorProvider(rosChannelConnector: server.connect);
      provider.connect(_settings);
      async.flushMicrotasks();
      server.last.receive({
        'op': 'publish',
        'topic': _state,
        'msg': {'data': true}
      });
      async.flushMicrotasks();
      expect(provider.wakeDoaTurnOn, isTrue);

      server.last.drop();
      async.flushMicrotasks();
      expect(provider.wakeDoaTurnOn, isNull);

      async.elapse(const Duration(seconds: 10));
      expect(server.sockets.length, greaterThan(1), reason: '다시 붙어야 한다');
      server.last.receive({
        'op': 'publish',
        'topic': _state,
        'msg': {'data': false}
      });
      async.flushMicrotasks();
      expect(provider.wakeDoaTurnOn, isFalse);
    });
  });

  test('음성 유닛이 active 가 아니게 되면 남은 값을 비우고, 새 노드가 낼 때까지 모름', () {
    final provider = SupervisorProvider(rosChannelConnector: server.connect);
    Map<String, Object?> mode(String voice) => {
          'mode': 'drive',
          'state': 'running',
          'nav2': 'active',
          'detector': 'active',
          'voice': voice
        };

    provider.setWakeDoaTurnForTest(true);
    provider.handleModeStatusForTest(mode('active'));
    expect(provider.wakeDoaTurnOn, isTrue, reason: '음성이 떠 있으면 값을 그대로 둔다');

    provider.handleModeStatusForTest(mode('deactivating'));
    expect(provider.wakeDoaTurnOn, isNull);

    provider.handleModeStatusForTest(mode('active'));
    expect(provider.wakeDoaTurnOn, isNull,
        reason: 'active 로 돌아와도 새 노드가 낼 때까지 모름');
  });
}
