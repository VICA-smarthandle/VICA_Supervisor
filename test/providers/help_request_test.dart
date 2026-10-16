// 관리자 호출(도움 요청) — 앱 쪽 상태와 확인 서비스(설계 2026-10-15, 9.3절).
//
// 미션은 관리자가 확인할 때까지 10초마다 같은 help_id 로 help_requested 를 다시 보냅니다.
// 앱은 help_id 하나에 팝업 하나만 띄우고, 같은 id 가 다시 오면 위치만 갱신합니다.
// 팝업 화면 자체는 목업 확인 뒤에 만듭니다 — 여기는 그 화면이 쓸 상태입니다.
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/core/app_settings.dart';
import 'package:vica_supervisor/models/goal_event.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';

import '../ros/fake_ros_socket.dart';

const _settings = AppSettings();
const _idA = '6f1c2b0e-8a7d-4c1e-9b2a-3d4e5f607182';
const _idB = '0b9a8c7d-6e5f-4a3b-8c2d-1e0f9a8b7c6d';

Map<String, Object?> _event(String event, String helpId,
        {String place = '', double? x, double? y}) =>
    {
      'event': event,
      'map_id': 'm1',
      'location_id': '',
      'destination_id': '',
      'name': '',
      'x': 0.0,
      'y': 0.0,
      'yaw': 0.0,
      'reason': '',
      'timestamp': '2026-10-16T14:03:21',
      'help_id': helpId,
      if (event == 'help_requested') ...{
        'place': place,
        'robot_x': x,
        'robot_y': y,
      },
    };

void main() {
  group('이벤트 해석', () {
    test('help_requested 는 id·위치 문장·로봇 좌표를 읽는다', () {
      final event = GoalEvent.fromJson(
          _event('help_requested', _idA, place: '407호 앞', x: 12.34, y: -3.21),
          id: 'x');
      expect(event.kind, GoalEventKind.helpRequested);
      expect(event.helpId, _idA);
      expect(event.place, '407호 앞');
      expect(event.robotX, 12.34);
      expect(event.robotY, -3.21);
      expect(event.needsPopup, isFalse); // 주행 알림 팝업 줄에 끼지 않는다
    });

    test('위치를 모르면 좌표는 null 이다', () {
      final event =
          GoalEvent.fromJson(_event('help_requested', _idA), id: 'x');
      expect(event.robotX, isNull);
      expect(event.robotY, isNull);
      expect(event.place, '');
    });

    test('확인·취소 이벤트 종류', () {
      expect(GoalEventKind.fromWire('help_acknowledged'),
          GoalEventKind.helpAcknowledged);
      expect(GoalEventKind.fromWire('help_canceled'),
          GoalEventKind.helpCanceled);
    });
  });

  group('팝업 상태', () {
    test('같은 help_id 3번 → 팝업 하나, 위치는 마지막 값', () {
      final provider = SupervisorProvider();
      provider.handleGoalEventForTest(
          _event('help_requested', _idA, place: '407호 앞', x: 1, y: 1));
      expect(provider.helpPopupPending, isTrue);
      provider.markHelpPopupShown();
      provider.handleGoalEventForTest(
          _event('help_requested', _idA, place: '407호와 화장실 사이', x: 2, y: 2));
      provider.handleGoalEventForTest(
          _event('help_requested', _idA, place: '화장실 앞', x: 3, y: 4));
      expect(provider.helpPopupPending, isFalse);
      expect(provider.activeHelp!.helpId, _idA);
      expect(provider.activeHelp!.place, '화장실 앞');
      expect(provider.activeHelp!.robotX, 3);
      provider.dispose();
    });

    test('다른 help_id 가 오면 새 팝업으로 바뀐다', () {
      final provider = SupervisorProvider();
      provider.handleGoalEventForTest(_event('help_requested', _idA));
      provider.markHelpPopupShown();
      provider.handleGoalEventForTest(_event('help_requested', _idB));
      expect(provider.activeHelp!.helpId, _idB);
      expect(provider.helpPopupPending, isTrue);
      provider.dispose();
    });

    for (final ending in ['help_acknowledged', 'help_canceled']) {
      test('$ending 이 같은 id 로 오면 지워진다', () {
        final provider = SupervisorProvider();
        provider.handleGoalEventForTest(_event('help_requested', _idA));
        provider.handleGoalEventForTest(_event(ending, _idA));
        expect(provider.activeHelp, isNull);
        expect(provider.helpPopupPending, isFalse);
        provider.dispose();
      });

      test('$ending 이 다른 id 로 오면 그대로 둔다', () {
        final provider = SupervisorProvider();
        provider.handleGoalEventForTest(_event('help_requested', _idA));
        provider.handleGoalEventForTest(_event(ending, _idB));
        expect(provider.activeHelp!.helpId, _idA);
        provider.dispose();
      });
    }
  });

  group('확인 버튼', () {
    late FakeRosServer server;
    setUp(() => server = FakeRosServer());

    // 연결한 provider 에 도움 요청을 띄우고 확인을 누른 뒤, 미션이 [values] 로 답한 결과.
    ({String message, Map<String, Object?> args, GoalEvent? left}) press(
        Map<String, Object?> values) {
      late String message;
      late Map<String, Object?> args;
      GoalEvent? left;
      fakeAsync((async) {
        final provider = SupervisorProvider(rosChannelConnector: server.connect);
        provider.connect(_settings);
        async.flushMicrotasks();
        provider.handleGoalEventForTest(
            _event('help_requested', _idA, place: '407호 앞'));
        provider.acknowledgeHelp(_settings).then((value) => message = value);
        async.flushMicrotasks();
        final call = server.last.sent.lastWhere((c) =>
            c['op'] == 'call_service' &&
            c['service'] == _settings.missionHelpAckService);
        args = Map<String, Object?>.from(call['args'] as Map);
        expect(server.last.answer(_settings.missionHelpAckService, values),
            isTrue);
        async.flushMicrotasks();
        left = provider.activeHelp;
        provider.dispose();
        async.flushMicrotasks();
      });
      return (message: message, args: args, left: left);
    }

    test('request_id 는 그 도움 요청의 help_id 다', () {
      final result = press({'accepted': true, 'message': 'ok'});
      expect(result.args['request_id'], _idA);
      expect(result.message, '관리자 확인을 로봇에 보냈습니다.');
      expect(result.left, isNull);
    });

    test('이미 끝난 요청이면 그렇게 알리고 팝업 상태를 지운다', () {
      final result = press({'accepted': false, 'message': 'no_active_help'});
      expect(result.message, '이미 끝난 도움 요청입니다.');
      expect(result.left, isNull);
    });

    test('다른 요청이 걸려 있으면 그렇게 알린다', () {
      final result = press({'accepted': false, 'message': 'id_mismatch'});
      expect(result.message, '로봇에 다른 도움 요청이 걸려 있습니다.');
    });
  });

  test('설정 기본값과 저장', () {
    expect(_settings.missionHelpAckService, '/vica/mission/help_ack');
    final changed = _settings.copyWith(missionHelpAckService: '/x/help_ack');
    final restored = AppSettings.fromJson(changed.toJson());
    expect(restored.missionHelpAckService, '/x/help_ack');
  });
}
