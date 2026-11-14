// 경비(순찰) — 앱 쪽 상태와 서비스 호출(2026-11-14, 명세 2·3절).
//
// 순찰 단계는 /robot_status 의 dialog_state 가 정본이고 patrol_* 사건은 그 1초 사이를 메웁니다.
// 경보는 alarm_id 하나에 팝업 하나 — 미션이 10초마다 다시 보내도 하나입니다. 확인·재개·종료
// 서비스의 request_id 는 UUID 여야 합니다(미션의 MissionCommand 검사).
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/core/app_settings.dart';
import 'package:vica_supervisor/core/log_filter.dart';
import 'package:vica_supervisor/models/patrol.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';
import 'package:vica_supervisor/services/patrol_log_loader.dart';

import '../ros/fake_ros_socket.dart';

const _settings = AppSettings();
const _intruder = '20261114_021341_intruder';
final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');

Map<String, Object?> _event(
  String event, {
  String name = '',
  String reason = '',
  String stamp = '2026-11-14T02:13:41',
  Map<String, Object?> extra = const {},
}) =>
    {
      'event': event,
      'map_id': 'm1',
      'location_id': '',
      'destination_id': '',
      'name': name,
      'x': 0.0,
      'y': 0.0,
      'yaw': 0.0,
      'reason': reason,
      'timestamp': stamp,
      ...extra,
    };

Map<String, Object?> _alarm(
  String event,
  String alarmId, {
  String place = '화장실',
  Map<String, Object?> extra = const {},
}) =>
    _event(event, extra: {
      'alarm_id': alarmId,
      'place': place,
      'robot_x': 1.0,
      'robot_y': 2.0,
      ...extra,
    });

Map<String, Object?> _status(String dialogState) => {
      'robot_id': 'vica_01',
      'robot_name': 'VICA-01',
      'status': 'idle',
      'x': 0.0,
      'y': 0.0,
      'yaw': 0.0,
      'current_location': '',
      'current_goal': '',
      'error_reason': '',
      'waiting_reason': '',
      'map_id': 'm1',
      'timestamp': '2026-11-14T02:13:41',
      'dialog_state': dialogState,
    };

/// 시계를 손으로 넘기는 provider.
class _Clock {
  DateTime now = DateTime(2026, 11, 14, 2, 13, 41);
  void pass(Duration time) => now = now.add(time);
}

SupervisorProvider _provider(_Clock clock, {PatrolLogLoader? loader}) =>
    SupervisorProvider(patrolLogLoader: loader)..patrolNow = () => clock.now;

void main() {
  test('설정 기본값은 명세 3.2 의 서비스 이름이고 저장·복원을 거쳐도 남는다', () {
    expect(_settings.patrolStartService, '/vica/mission/patrol_start');
    expect(_settings.patrolStopService, '/vica/mission/patrol_stop');
    expect(_settings.patrolAckService, '/vica/mission/patrol_ack');
    expect(_settings.patrolRouteSaveService, '/vica/patrol/route/save');
    expect(_settings.patrolRouteGetService, '/vica/patrol/route/get');

    final changed = _settings.copyWith(
      patrolStartService: '/x/start',
      patrolStopService: '/x/stop',
      patrolAckService: '/x/ack',
      patrolRouteSaveService: '/x/save',
      patrolRouteGetService: '/x/get',
    );
    final restored = AppSettings.fromJson(changed.toJson());
    expect(restored.patrolStartService, '/x/start');
    expect(restored.patrolStopService, '/x/stop');
    expect(restored.patrolAckService, '/x/ack');
    expect(restored.patrolRouteSaveService, '/x/save');
    expect(restored.patrolRouteGetService, '/x/get');
    // 옛 설정에 항목이 없으면 기본값.
    final old = _settings.toJson()..remove('patrolAckService');
    expect(
        AppSettings.fromJson(old).patrolAckService, '/vica/mission/patrol_ack');
  });

  group('순찰 단계', () {
    test('상태 토픽의 dialog_state 를 따른다', () {
      final clock = _Clock();
      final provider = _provider(clock);
      expect(provider.patrolPhase, PatrolPhase.off);
      provider.handleRobotStatusForTest(_status('patrolling'));
      expect(provider.patrolPhase, PatrolPhase.moving);
      provider.handleRobotStatusForTest(_status('patrol_light'));
      expect(provider.patrolPhase, PatrolPhase.light);
      provider.handleRobotStatusForTest(_status('idle'));
      expect(provider.patrolPhase, PatrolPhase.off);
      provider.dispose();
    });

    test('사건이 먼저 오면 상태 토픽이 따라올 때까지 3초 동안 사건을 따른다', () {
      final clock = _Clock();
      final provider = _provider(clock);
      provider.handleRobotStatusForTest(_status('idle'));
      provider.handleGoalEventForTest(_event('patrol_started', extra: {
        'route': ['입구', '안내소'],
      }));
      expect(provider.patrolPhase, PatrolPhase.dwell);
      clock.pass(const Duration(seconds: 2));
      expect(provider.patrolPhase, PatrolPhase.dwell);
      // 3초가 지나도 상태 토픽이 순찰이라고 하지 않으면 그쪽을 믿는다.
      clock.pass(const Duration(seconds: 2));
      expect(provider.patrolPhase, PatrolPhase.off);
      provider.dispose();
    });

    test('종료 사건은 상태 토픽이 아직 순찰이어도 곧바로 꺼짐으로 보인다', () {
      final clock = _Clock();
      final provider = _provider(clock);
      provider.handleRobotStatusForTest(_status('patrolling'));
      provider
          .handleGoalEventForTest(_event('patrol_stopped', reason: 'admin'));
      expect(provider.patrolPhase, PatrolPhase.off);
      provider.dispose();
    });

    test('일시정지·재개 사건', () {
      final clock = _Clock();
      final provider = _provider(clock);
      provider.handleGoalEventForTest(_event('patrol_paused'));
      expect(provider.patrolPhase, PatrolPhase.paused);
      provider.handleGoalEventForTest(_event('patrol_resumed'));
      expect(provider.patrolPhase, PatrolPhase.moving);
      provider.dispose();
    });
  });

  group('지점 정보', () {
    test('시작 시각·바퀴·가는 곳과 온 곳', () {
      final clock = _Clock();
      final provider = _provider(clock);
      provider.handleGoalEventForTest(_event(
        'patrol_started',
        stamp: '2026-11-14T22:04:10',
        extra: {
          'route': ['입구', '안내소', '작업실', '화장실'],
        },
      ));
      expect(provider.patrolStartedAt, DateTime(2026, 11, 14, 22, 4, 10));
      expect(provider.patrolWaypointIndex, isNull);

      // 첫 바퀴 첫 지점은 온 곳이 지점이 아니다.
      provider.handleGoalEventForTest(_event('patrol_waypoint',
          name: '입구', extra: {'index': 0, 'lap': 1, 'count': 4}));
      expect(provider.patrolWaypointName, '입구');
      expect(provider.patrolFromName, '');
      expect(provider.patrolLap, 1);

      provider.handleGoalEventForTest(_event('patrol_waypoint',
          name: '화장실', extra: {'index': 3, 'lap': 3, 'count': 4}));
      expect(provider.patrolFromName, '작업실');
      expect(provider.patrolLap, 3);
      expect(
        patrolHeadingLine(provider.patrolFromName, provider.patrolWaypointName),
        '작업실 → 화장실로 가는 중입니다.',
      );

      // 둘째 바퀴부터 첫 지점의 온 곳은 마지막 지점이다.
      provider.handleGoalEventForTest(_event('patrol_waypoint',
          name: '입구', extra: {'index': 0, 'lap': 4, 'count': 4}));
      expect(provider.patrolFromName, '화장실');
      provider.dispose();
    });

    test('순찰 사건은 주행 알림 팝업·일시정지 표시를 건드리지 않는다', () {
      final clock = _Clock();
      final provider = _provider(clock);
      provider.handleGoalEventForTest(_event('patrol_paused'));
      provider.handleGoalEventForTest(
          _event('patrol_stopped', reason: 'nav_failed'));
      expect(provider.pendingGoalAlert, isNull);
      expect(provider.navigationPaused, isFalse);
      provider.dispose();
    });
  });

  group('경보', () {
    test('같은 alarm_id 가 다시 와도 팝업은 하나, 새로 온 영상 id 는 채운다', () {
      final clock = _Clock();
      final provider = _provider(clock);
      provider.handleGoalEventForTest(_alarm('patrol_intruder', _intruder));
      expect(provider.patrolPopupPending, isTrue);
      expect(provider.patrolPhase, PatrolPhase.alarm);
      expect(provider.patrolAlarm!.clipId, '');
      provider.markPatrolPopupShown();
      expect(provider.patrolPopupPending, isFalse);

      clock.pass(const Duration(seconds: 10));
      provider.handleGoalEventForTest(_alarm('patrol_intruder', _intruder,
          extra: {'clip_id': _intruder, 'resend': true}));
      expect(provider.patrolPopupPending, isFalse);
      expect(provider.patrolAlarm!.clipId, _intruder);
      // 알림 목록에는 한 줄만.
      final lines = provider.logs.where((l) => l.filter == LogFilter.patrol);
      expect(lines.map((l) => l.message), ['침입 감지 · 사람 · 화장실']);
      provider.dispose();
    });

    test('불 켜짐은 patrol_light 단계다', () {
      final clock = _Clock();
      final provider = _provider(clock);
      provider.handleGoalEventForTest(_alarm(
          'patrol_light', '20261114_005207_light',
          place: '407호', extra: {'photo': '20261114_005207.jpg'}));
      expect(provider.patrolPhase, PatrolPhase.light);
      expect(provider.patrolAlarm!.photo, '20261114_005207.jpg');
      provider.dispose();
    });

    test('확인 사건이 오면(다른 화면에서 눌러도) 확인됨으로 바뀌고 팝업 거리가 없어진다', () {
      final clock = _Clock();
      final provider = _provider(clock);
      provider.handleGoalEventForTest(_alarm('patrol_intruder', _intruder));
      provider.handleGoalEventForTest(
          _event('patrol_acked', extra: {'alarm_id': _intruder}));
      expect(provider.patrolAlarm!.acked, isTrue);
      expect(provider.patrolPopupPending, isFalse);
      // 로봇은 그대로 서 있다 — 경보는 재개·종료까지 남는다.
      expect(provider.patrolAlarm, isNotNull);
      provider.dispose();
    });

    test('다른 경보의 확인 사건은 무시한다', () {
      final clock = _Clock();
      final provider = _provider(clock);
      provider.handleGoalEventForTest(_alarm('patrol_intruder', _intruder));
      provider.handleGoalEventForTest(
          _event('patrol_acked', extra: {'alarm_id': '다른_경보'}));
      expect(provider.patrolAlarm!.acked, isFalse);
      provider.dispose();
    });

    for (final ending in [
      'patrol_resumed',
      'patrol_stopped',
      'patrol_started'
    ]) {
      test('$ending 이 오면 경보를 지운다', () {
        final clock = _Clock();
        final provider = _provider(clock);
        provider.handleGoalEventForTest(_alarm('patrol_intruder', _intruder));
        provider.handleGoalEventForTest(_event(ending));
        expect(provider.patrolAlarm, isNull);
        expect(provider.patrolPopupPending, isFalse);
        provider.dispose();
      });
    }

    test('새 경보가 오면 그 경보의 팝업을 다시 띄운다', () {
      final clock = _Clock();
      final provider = _provider(clock);
      provider.handleGoalEventForTest(_alarm('patrol_intruder', _intruder));
      provider.markPatrolPopupShown();
      provider.handleGoalEventForTest(_event('patrol_resumed'));
      provider.handleGoalEventForTest(_alarm(
          'patrol_sound', '20261114_021600_sound',
          extra: {'level_db': 70.2}));
      expect(provider.patrolPopupPending, isTrue);
      expect(provider.patrolAlarm!.kind, PatrolAlarmKind.sound);
      expect(provider.logs.first.message, '큰 소리 · 70 dB · 화장실');
      provider.dispose();
    });

    test('재개 사건을 놓쳐도 로봇이 더는 경보로 서 있지 않으면 경보를 지운다', () {
      final clock = _Clock();
      final provider = _provider(clock);
      provider.handleGoalEventForTest(_alarm('patrol_intruder', _intruder));
      // 사건이 상태 토픽보다 먼저 온다 — 곧바로 지우면 안 된다.
      provider.handleRobotStatusForTest(_status('patrolling'));
      expect(provider.patrolAlarm, isNotNull);
      clock.pass(const Duration(seconds: 4));
      provider.handleRobotStatusForTest(_status('patrol_alarm'));
      expect(provider.patrolAlarm, isNotNull);
      // 다른 화면에서 재개했다.
      provider.handleRobotStatusForTest(_status('patrolling'));
      expect(provider.patrolAlarm, isNull);
      provider.dispose();
    });
  });

  group('순찰이 스스로 끝남', () {
    test('지점에 못 가서 끝나면 한 줄 알림과 알림 목록', () {
      final clock = _Clock();
      final provider = _provider(clock);
      provider.handleGoalEventForTest(
          _event('patrol_stopped', reason: 'nav_failed'));
      expect(provider.pendingPatrolNotice, '순찰 지점으로 가지 못해 경비를 종료했습니다.');
      expect(provider.logs.first.message, '순찰 지점으로 가지 못해 경비를 종료했습니다.');
      provider.consumePatrolNotice();
      expect(provider.pendingPatrolNotice, isNull);
      provider.dispose();
    });

    test('감지 노드가 준비되지 않아 끝남', () {
      final clock = _Clock();
      final provider = _provider(clock);
      provider.handleGoalEventForTest(
          _event('patrol_stopped', reason: 'detector_not_ready'));
      expect(provider.pendingPatrolNotice, '사람 감지가 준비되지 않아 경비를 종료했습니다.');
      provider.dispose();
    });

    test('관리자가 끝냈거나 비상정지면 따로 알리지 않는다', () {
      final clock = _Clock();
      final provider = _provider(clock);
      for (final reason in ['admin', 'estop']) {
        provider
            .handleGoalEventForTest(_event('patrol_stopped', reason: reason));
        expect(provider.pendingPatrolNotice, isNull, reason: reason);
      }
      provider.dispose();
    });
  });

  group('서비스 호출', () {
    late FakeRosServer server;
    setUp(() => server = FakeRosServer());

    /// 연결한 provider 로 [act] 를 부르고 미션이 [values] 로 답한 결과.
    ({T result, Map<String, Object?> args, SupervisorProvider provider})
        call<T>(
      String service,
      Future<T> Function(SupervisorProvider provider) act,
      Map<String, Object?> values, {
      void Function(SupervisorProvider provider)? before,
    }) {
      late T result;
      late Map<String, Object?> args;
      late SupervisorProvider provider;
      fakeAsync((async) {
        provider = SupervisorProvider(rosChannelConnector: server.connect);
        provider.connect(_settings);
        async.flushMicrotasks();
        before?.call(provider);
        act(provider).then((value) => result = value);
        async.flushMicrotasks();
        final sent = server.last.sent.lastWhere(
            (c) => c['op'] == 'call_service' && c['service'] == service);
        args = Map<String, Object?>.from(sent['args'] as Map);
        expect(server.last.answer(service, values), isTrue);
        async.flushMicrotasks();
      });
      addTearDown(provider.dispose);
      return (result: result, args: args, provider: provider);
    }

    test('경비 시작 — request_id 는 UUID, 수락되면 목업 문구와 준비 단계', () {
      final r = call(
        '/vica/mission/patrol_start',
        (p) => p.startPatrol(_settings),
        {'accepted': true, 'message': 'patrol_start 요청을 처리했습니다.'},
      );
      expect(r.args['request_id'], matches(_uuid));
      expect(r.result, '경비를 시작했습니다.');
      expect(r.provider.patrolPhase, PatrolPhase.dwell);
    });

    // 순찰 서비스의 거절 문구는 미션이 한국어 한 줄로 정합니다(mission_logic 의
    // PATROL_REJECT_TEXT·PATROL_START_REJECT_TEXT). 앱은 글자를 바꾸지 않습니다.
    for (final message in [
      '비상정지 중에는 경비를 시작할 수 없습니다.',
      '순찰 지점이 2곳 이상이어야 경비를 시작할 수 있습니다.',
      '안내·접근 중에는 경비를 시작할 수 없습니다.',
      '로봇 위치가 아직 정해지지 않았습니다.',
    ]) {
      test('경비 시작 거절은 미션의 문구 그대로: $message', () {
        final r = call(
          '/vica/mission/patrol_start',
          (p) => p.startPatrol(_settings),
          {'accepted': false, 'message': message},
        );
        expect(r.result, message);
        expect(r.provider.patrolPhase, PatrolPhase.off);
      });
    }

    test('앱은 거절 문구 안의 글자를 다른 문장으로 바꿔 치우지 않는다', () {
      // 전에는 'estop_active' 가 들어 있으면 앱 문구로 바꿨다. 이제 미션이 문구를 정한다.
      final r = call(
        '/vica/mission/patrol_start',
        (p) => p.startPatrol(_settings),
        {'accepted': false, 'message': 'estop_active'},
      );
      expect(r.result, 'estop_active');
    });

    // 경비 종료(2026-11-14 사용자 결정: 종료하면 로봇이 홈으로 돌아간다). 홈으로 돌아가는지는
    // 종료 사건(patrol_stopped 의 return_home)이 알려 준다 — 응답보다 늦게 올 수 있다.

    /// 경비 종료를 누르고 미션이 [values] 로 답한 결과. [event] 는 종료 사건의 추가 키이고
    /// null 이면 사건이 오지 않는다. [eventFirst] 가 false 면 사건이 응답 0.3초 뒤에 온다.
    ({String result, SupervisorProvider provider}) stop(
      Map<String, Object?> values, {
      Map<String, Object?>? event,
      String reason = 'admin',
      bool eventFirst = true,
      void Function(SupervisorProvider provider)? before,
    }) {
      String? result;
      late SupervisorProvider provider;
      fakeAsync((async) {
        provider = SupervisorProvider(rosChannelConnector: server.connect);
        provider.connect(_settings);
        async.flushMicrotasks();
        before?.call(provider);
        provider.stopPatrol(_settings).then((value) => result = value);
        async.flushMicrotasks();
        void sendEvent() {
          if (event != null) {
            provider.handleGoalEventForTest(
                _event('patrol_stopped', reason: reason, extra: event));
          }
        }

        if (eventFirst) {
          sendEvent();
        }
        expect(server.last.answer('/vica/mission/patrol_stop', values), isTrue);
        async.flushMicrotasks();
        if (!eventFirst) {
          expect(result, isNull, reason: '종료 사건을 기다려야 한다');
          // 화면은 기다리지 않고 꺼짐으로 바뀌어 있다.
          expect(provider.patrolPhase, PatrolPhase.off);
          async.elapse(const Duration(milliseconds: 300));
          sendEvent();
          async.flushMicrotasks();
        }
        // 사건이 끝내 안 오면 1.5초 뒤 포기하고 알린다.
        async.elapse(const Duration(seconds: 2));
      });
      addTearDown(provider.dispose);
      return (result: result!, provider: provider);
    }

    const stopped = {'accepted': true, 'message': '경비를 종료했습니다.'};

    test('경비 종료 — 홈으로 돌아가면 목업의 두 줄, 꺼짐, 걸려 있던 경보도 지운다', () {
      final r = stop(
        stopped,
        event: {'return_home': true},
        before: (p) =>
            p.handleGoalEventForTest(_alarm('patrol_intruder', _intruder)),
      );
      expect(r.result, '경비를 종료했습니다.\n로봇이 홈으로 돌아갑니다.');
      expect(r.provider.patrolPhase, PatrolPhase.off);
      expect(r.provider.patrolAlarm, isNull);
    });

    test('종료 사건이 응답보다 늦게 와도 잠깐 기다려 같은 두 줄을 알린다', () {
      final r = stop(stopped, event: {'return_home': true}, eventFirst: false);
      expect(r.result, '경비를 종료했습니다.\n로봇이 홈으로 돌아갑니다.');
    });

    // 홈 복귀를 시작하지 못하면 미션은 종료는 받아들이고(accepted=true) 응답 message 에
    // /vica/mission/return_home 의 거절과 같은 글자를 싣는다. 앱은 '홈으로 복귀' 버튼의
    // 거절과 같은 표로 옮긴다 — 버튼을 눌렀을 때와 같은 글자가 나와야 한다.
    for (final (code, text) in [
      ('홈 복귀 거부: no_home', '홈 위치가 지정되지 않았습니다. 지도 설정 화면에서 먼저 지정하세요.'),
      ('홈 복귀 거부: nav_not_ready', 'Nav2가 준비되지 않아 주행할 수 없습니다.'),
    ]) {
      test('홈으로 못 돌아가면 홈 복귀 버튼과 같은 문구가 둘째 줄이다: $code', () {
        final r = stop(
          {'accepted': true, 'message': code},
          event: {'return_home': false},
        );
        expect(r.result, '경비를 종료했습니다.\n$text');
        expect(r.provider.patrolPhase, PatrolPhase.off);
        // 까닭은 알림 목록에도 남는다.
        expect(r.provider.logs.first.message, r.result);

        // 같은 거절을 홈 복귀 버튼(returnHome)으로 받았을 때의 글자와 같다.
        final button = call(
          '/vica/mission/return_home',
          (p) => p.returnHome(_settings),
          {'accepted': false, 'message': code},
        );
        expect(button.result, text);
      });
    }

    test('미션이 코드 없는 한국어 사유를 보내면 그대로 둘째 줄이다', () {
      final r = stop(
        {'accepted': true, 'message': '홈으로 돌아갈 수 없습니다.'},
        event: {'return_home': false},
      );
      expect(r.result, '경비를 종료했습니다.\n홈으로 돌아갈 수 없습니다.');
    });

    test('return_home 키가 없으면(옛 미션) 돌아가지 않는 것으로 본다', () {
      final r = stop(stopped, event: const {});
      expect(r.result, '경비를 종료했습니다.');
    });

    test('종료 사건이 끝내 안 오면 한 줄만 알린다', () {
      final r = stop(stopped);
      expect(r.result, '경비를 종료했습니다.');
    });

    test('관리자 종료가 아닌 사건(비상정지 등)의 return_home 은 쓰지 않는다', () {
      final r = stop(stopped, event: {'return_home': true}, reason: 'estop');
      expect(r.result, '경비를 종료했습니다.');
    });

    test('종료가 거절되면 미션의 문구 그대로이고 사건을 기다리지 않는다', () {
      final r = call(
        '/vica/mission/patrol_stop',
        (p) => p.stopPatrol(_settings),
        {'accepted': false, 'message': '순찰 중이 아닙니다.'},
      );
      expect(r.result, '순찰 중이 아닙니다.');
    });

    test('일시정지는 기존 pause_navigation 을 쓰고 수락 알림이 없다', () {
      final r = call(
        '/vica/mission/pause_navigation',
        (p) => p.pausePatrol(_settings),
        {'accepted': true, 'message': 'pause 요청을 처리했습니다.'},
      );
      expect(r.result, '');
      expect(r.provider.patrolPhase, PatrolPhase.paused);
    });

    test('순찰 재개는 기존 resume_navigation 을 쓰고 경보를 지운다', () {
      final r = call(
        '/vica/mission/resume_navigation',
        (p) => p.resumePatrol(_settings),
        {'accepted': true, 'message': ''},
        before: (p) =>
            p.handleGoalEventForTest(_alarm('patrol_intruder', _intruder)),
      );
      expect(r.result, '순찰을 재개했습니다.');
      expect(r.provider.patrolAlarm, isNull);
      expect(r.provider.patrolPhase, PatrolPhase.moving);
    });

    test('재개가 거절되면(카메라 끊김 등) 경보는 남고 사유를 보인다', () {
      final r = call(
        '/vica/mission/resume_navigation',
        (p) => p.resumePatrol(_settings),
        {'accepted': false, 'message': '카메라가 준비되지 않았습니다.'},
        before: (p) => p.handleGoalEventForTest(
            _alarm('patrol_camera_lost', '20261114_030255_camera_lost')),
      );
      expect(r.result, '카메라가 준비되지 않았습니다.');
      expect(r.provider.patrolAlarm, isNotNull);
      expect(r.provider.patrolPhase, PatrolPhase.alarm);
    });

    test('순찰이 끝난 뒤의 재개는 주행 쪽 사유가 오므로 기존 표로 옮긴다', () {
      // 일시정지·재개는 주행과 함께 쓰는 서비스다. 순찰 상태가 아니면 미션이 코드가 섞인
      // 사유를 보낸다(_handle_mission_command).
      final r = call(
        '/vica/mission/resume_navigation',
        (p) => p.resumePatrol(_settings),
        {'accepted': false, 'message': 'resume 요청 거부: not_paused'},
      );
      expect(r.result, '다시 출발할 주행이 없습니다.');
    });

    test('확인 — request_id 는 그 팝업의 alarm_id(UUID 가 아니다), 수락되면 확인됨', () {
      final r = call(
        '/vica/mission/patrol_ack',
        (p) => p.acknowledgePatrolAlarm(_settings, _intruder),
        {'accepted': true, 'message': '경보를 확인했습니다.'},
        before: (p) =>
            p.handleGoalEventForTest(_alarm('patrol_intruder', _intruder)),
      );
      // 미션은 이 모양(YYYYMMDD_HHMMSS_<kind>)이면 그 경보만 확인한다.
      expect(r.args['request_id'], _intruder);
      expect(r.result, '');
      expect(r.provider.patrolAlarm!.acked, isTrue);
      expect(r.provider.patrolPopupPending, isFalse);
    });

    test('옛 팝업의 확인을 뒤늦게 눌러도 새 경보는 확인되지 않는다', () {
      const sound = '20261114_021600_sound';
      final r = call(
        '/vica/mission/patrol_ack',
        // 팝업은 침입 경보의 것인데, 그사이 큰 소리 경보가 새로 걸렸다.
        (p) => p.acknowledgePatrolAlarm(_settings, _intruder),
        {'accepted': false, 'message': '지금 경보와 다른 경보입니다.'},
        before: (p) => p
          ..handleGoalEventForTest(_alarm('patrol_intruder', _intruder))
          ..handleGoalEventForTest(_event('patrol_resumed'))
          ..handleGoalEventForTest(_alarm('patrol_sound', sound)),
      );
      expect(r.args['request_id'], _intruder);
      expect(r.result, '지금 경보와 다른 경보입니다.');
      expect(r.provider.patrolAlarm!.alarmId, sound);
      expect(r.provider.patrolAlarm!.acked, isFalse);
    });

    test('미션이 받아도 그사이 경보가 바뀌었으면 새 경보를 확인됨으로 바꾸지 않는다', () {
      const sound = '20261114_021600_sound';
      late SupervisorProvider provider;
      final r = call(
        '/vica/mission/patrol_ack',
        (p) {
          provider = p;
          final sent = p.acknowledgePatrolAlarm(_settings, _intruder);
          // 응답이 오기 전에 새 경보가 걸렸다.
          p
            ..handleGoalEventForTest(_event('patrol_resumed'))
            ..handleGoalEventForTest(_alarm('patrol_sound', sound));
          return sent;
        },
        {'accepted': true, 'message': '경보를 확인했습니다.'},
        before: (p) =>
            p.handleGoalEventForTest(_alarm('patrol_intruder', _intruder)),
      );
      expect(r.result, '');
      expect(provider.patrolAlarm!.alarmId, sound);
      expect(provider.patrolAlarm!.acked, isFalse);
    });

    test('확인이 거절되면 경보는 그대로다', () {
      final r = call(
        '/vica/mission/patrol_ack',
        (p) => p.acknowledgePatrolAlarm(_settings, _intruder),
        {'accepted': false, 'message': ''},
        before: (p) =>
            p.handleGoalEventForTest(_alarm('patrol_intruder', _intruder)),
      );
      expect(r.result, '요청이 거부되었습니다.');
      expect(r.provider.patrolAlarm!.acked, isFalse);
    });

    test('연결이 없으면 부르지 않고 그렇게 알린다', () async {
      final provider = SupervisorProvider();
      expect(await provider.startPatrol(_settings), 'ROS Bridge에 연결되지 않았습니다.');
      provider.dispose();
    });

    test('경로 읽기 — 찾으면 순서와 이름', () {
      final r = call<void>(
        '/vica/patrol/route/get',
        (p) => p.refreshPatrolRoute(_settings, 'm1'),
        {
          'found': true,
          'map_id': 'm1',
          'destination_ids': ['a', 'b'],
          'names': ['입구', '안내소'],
          'message': '',
        },
      );
      expect(r.args, {'map_id': 'm1'});
      final route = r.provider.patrolRouteFor('m1')!;
      expect(route.ids, ['a', 'b']);
      expect(route.summary, '입구 → 안내소 → 다시 입구');
      // 다른 지도의 경로로 쓰지 않는다.
      expect(r.provider.patrolRouteFor('m2'), isNull);
    });

    test('경로가 없으면 빈 경로', () {
      final r = call<void>(
        '/vica/patrol/route/get',
        (p) => p.refreshPatrolRoute(_settings, 'm1'),
        {
          'found': false,
          'map_id': 'm1',
          'destination_ids': <String>[],
          'names': <String>[],
          'message': '',
        },
      );
      expect(r.provider.patrolRouteFor('m1')!.isEmpty, isTrue);
    });

    test('경로 저장 — 누른 순서를 보내고 수락되면 화면의 경로가 바뀐다', () {
      final r = call(
        '/vica/patrol/route/save',
        (p) => p.savePatrolRoute(_settings, 'm1', ['a', 'b', 'c'],
            names: ['입구', '안내소', '작업실']),
        {'accepted': true, 'reason': 'ok', 'message': '저장했습니다.'},
      );
      expect(r.args, {
        'map_id': 'm1',
        'destination_ids': ['a', 'b', 'c'],
        'watch_off': <String>[],
      });
      expect(r.result, (true, '순찰 경로를 저장했습니다.'));
      expect(r.provider.patrolRouteFor('m1')!.names, ['입구', '안내소', '작업실']);
    });

    test('경로를 다시 저장해도 꺼 둔 감시 항목은 그대로 보낸다', () {
      final r = call(
        '/vica/patrol/route/save',
        (p) => p
            .savePatrolRoute(_settings, 'm1', ['b', 'a'], names: ['안내소', '입구']),
        {'accepted': true, 'reason': 'ok', 'message': ''},
        before: (p) => p.setPatrolRouteForTest(const PatrolRoute(
          mapId: 'm1',
          ids: ['a', 'b'],
          names: ['입구', '안내소'],
          watchOff: {PatrolAlarmKind.light},
        )),
      );
      expect(r.args['watch_off'], ['light']);
      final route = r.provider.patrolRouteFor('m1')!;
      expect(route.ids, ['b', 'a']);
      expect(route.watchOff, {PatrolAlarmKind.light});
    });

    test('감시 항목 끄기 — 경로는 그대로 보내고 수락되면 화면의 값이 바뀐다(알림 없음)', () {
      final r = call(
        '/vica/patrol/route/save',
        (p) => p.setPatrolWatch(_settings, 'm1', PatrolAlarmKind.sound, false),
        {'accepted': true, 'reason': 'ok', 'message': '순찰 경로를 저장했습니다(장소 2곳).'},
        before: (p) => p.setPatrolRouteForTest(const PatrolRoute(
          mapId: 'm1',
          ids: ['a', 'b'],
          names: ['입구', '안내소'],
          watchOff: {PatrolAlarmKind.light},
        )),
      );
      expect(r.args, {
        'map_id': 'm1',
        'destination_ids': ['a', 'b'],
        'watch_off': ['light', 'sound'],
      });
      expect(r.result, (true, ''));
      final route = r.provider.patrolRouteFor('m1')!;
      expect(route.watchOff, {PatrolAlarmKind.light, PatrolAlarmKind.sound});
      expect(route.names, ['입구', '안내소']);
    });

    test('감시 항목 다시 켜기', () {
      final r = call(
        '/vica/patrol/route/save',
        (p) => p.setPatrolWatch(_settings, 'm1', PatrolAlarmKind.light, true),
        {'accepted': true, 'reason': 'ok', 'message': ''},
        before: (p) => p.setPatrolRouteForTest(const PatrolRoute(
          mapId: 'm1',
          ids: ['a', 'b'],
          watchOff: {PatrolAlarmKind.light},
        )),
      );
      expect(r.args['watch_off'], isEmpty);
      expect(r.provider.patrolRouteFor('m1')!.watchOff, isEmpty);
    });

    test('감시 항목 저장이 거절되면 로봇의 한 줄을 보이고 값은 그대로다', () {
      final r = call(
        '/vica/patrol/route/save',
        (p) => p.setPatrolWatch(_settings, 'm1', PatrolAlarmKind.sound, false),
        {
          'accepted': false,
          'reason': 'unknown_destination',
          'message': '저장되지 않은 장소가 경로에 있습니다.',
        },
        before: (p) => p.setPatrolRouteForTest(
            const PatrolRoute(mapId: 'm1', ids: ['a', 'b'])),
      );
      expect(r.result, (false, '저장되지 않은 장소가 경로에 있습니다.'));
      expect(r.provider.patrolRouteFor('m1')!.watchOff, isEmpty);
    });

    test('마지막 하나는 끌 수 없다 — 로봇에 보내지 않고 그 자리에서 거절한다', () {
      fakeAsync((async) {
        final provider =
            SupervisorProvider(rosChannelConnector: server.connect);
        provider.connect(_settings);
        async.flushMicrotasks();
        provider.setPatrolRouteForTest(const PatrolRoute(
          mapId: 'm1',
          ids: ['a', 'b'],
          watchOff: {PatrolAlarmKind.intruder, PatrolAlarmKind.light},
        ));
        late (bool, String) result;
        provider
            .setPatrolWatch(_settings, 'm1', PatrolAlarmKind.sound, false)
            .then((value) => result = value);
        async.flushMicrotasks();
        expect(result, (false, '감시 항목은 하나 이상 켜 두어야 합니다.'));
        expect(
          server.last.sent.where((c) =>
              c['op'] == 'call_service' &&
              c['service'] == '/vica/patrol/route/save'),
          isEmpty,
        );
        // 이미 그 값이거나 경로를 아직 못 읽은 지도면 아무것도 하지 않는다.
        provider
            .setPatrolWatch(_settings, 'm1', PatrolAlarmKind.light, false)
            .then((value) => result = value);
        async.flushMicrotasks();
        expect(result, (false, ''));
        provider
            .setPatrolWatch(_settings, 'm2', PatrolAlarmKind.light, false)
            .then((value) => result = value);
        async.flushMicrotasks();
        expect(result, (false, ''));
        provider.dispose();
      });
    });

    test('경로 저장 거절은 로봇의 한 줄을 그대로 보인다', () {
      final r = call(
        '/vica/patrol/route/save',
        (p) => p.savePatrolRoute(_settings, 'm1', ['a']),
        {
          'accepted': false,
          'reason': 'too_few',
          'message': '순찰 경로는 장소 2곳 이상이어야 합니다.',
        },
      );
      expect(r.result, (false, '순찰 경로는 장소 2곳 이상이어야 합니다.'));
      expect(r.provider.patrolRouteFor('m1'), isNull);
    });

    test('빈 순서를 저장하면 경로 삭제이고 알림 문구가 없다', () {
      final r = call(
        '/vica/patrol/route/save',
        (p) => p.savePatrolRoute(_settings, 'm1', const []),
        {'accepted': true, 'reason': 'ok', 'message': ''},
      );
      expect(r.args['destination_ids'], isEmpty);
      expect(r.result, (true, ''));
      expect(r.provider.patrolRouteFor('m1')!.isEmpty, isTrue);
    });
  });

  group('경비 기록', () {
    String body(String clipState) => jsonEncode([
          {
            'alarm_id': _intruder,
            'kind': 'intruder',
            'time': '2026-11-14T02:13:41',
            'place': '화장실',
            'clip_id': _intruder,
            'clip_state': clipState,
            'clip_sec': 42.0,
          },
        ]);

    test('받은 기록에서 걸려 있는 경보의 영상 id 를 채운다', () async {
      final clock = _Clock();
      final provider = _provider(
        clock,
        loader: PatrolLogLoader(fetch: (_) async => body('ready')),
      );
      provider.handleGoalEventForTest(_alarm('patrol_intruder', _intruder));
      expect(provider.patrolAlarm!.clipId, '');
      await provider.refreshPatrolRecords(_settings);
      expect(provider.patrolRecords, hasLength(1));
      expect(provider.patrolRecordsFailed, isFalse);
      expect(provider.patrolAlarm!.clipId, _intruder);
      expect(provider.patrolRecordFor(_intruder)!.clipReady, isTrue);
      provider.dispose();
    });

    test('못 받으면 실패로 표시하고 옛 목록을 그대로 둔다', () async {
      var fail = false;
      final provider = _provider(
        _Clock(),
        loader:
            PatrolLogLoader(fetch: (_) async => fail ? null : body('ready')),
      );
      await provider.refreshPatrolRecords(_settings);
      fail = true;
      await provider.refreshPatrolRecords(_settings);
      expect(provider.patrolRecordsFailed, isTrue);
      expect(provider.patrolRecords, hasLength(1));
      provider.dispose();
    });

    test('영상이 저장될 때까지 5초마다 다시 받고, 준비되면 멈춘다', () {
      final server = FakeRosServer();
      var fetches = 0;
      var state = 'recording';
      fakeAsync((async) {
        final provider = SupervisorProvider(
          rosChannelConnector: server.connect,
          patrolLogLoader: PatrolLogLoader(fetch: (_) async {
            fetches += 1;
            return body(state);
          }),
        );
        provider.connect(_settings);
        async.flushMicrotasks();
        provider.handleGoalEventForTest(_alarm('patrol_intruder', _intruder));
        expect(fetches, 0);
        async.elapse(const Duration(seconds: 5));
        expect(fetches, 1);
        async.elapse(const Duration(seconds: 5));
        expect(fetches, 2);
        state = 'ready';
        async.elapse(const Duration(seconds: 5));
        expect(fetches, 3);
        expect(provider.patrolRecordFor(_intruder)!.clipReady, isTrue);
        // 준비됐으니 더 받지 않는다.
        async.elapse(const Duration(seconds: 30));
        expect(fetches, 3);
        provider.dispose();
        async.flushMicrotasks();
      });
    });

    test('불 켜짐·카메라 끊김은 영상이 없어 다시 받지 않는다', () {
      final server = FakeRosServer();
      var fetches = 0;
      fakeAsync((async) {
        final provider = SupervisorProvider(
          rosChannelConnector: server.connect,
          patrolLogLoader: PatrolLogLoader(fetch: (_) async {
            fetches += 1;
            return '[]';
          }),
        );
        provider.connect(_settings);
        async.flushMicrotasks();
        provider.handleGoalEventForTest(
            _alarm('patrol_light', '20261114_005207_light'));
        async.elapse(const Duration(seconds: 30));
        expect(fetches, 0);
        provider.dispose();
        async.flushMicrotasks();
      });
    });
  });
}
