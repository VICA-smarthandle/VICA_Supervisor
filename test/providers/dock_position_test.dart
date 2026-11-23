import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/core/app_settings.dart';
import 'package:vica_supervisor/models/dock_state.dart';
import 'package:vica_supervisor/models/mode_status.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';

import '../ros/fake_ros_socket.dart';

const _settings = AppSettings();

/// /vica/dock/get 응답 message(JSON 문자열).
String _getMessage(
        {String source = 'map_pick',
        bool visited = false,
        String mapId = 'm1'}) =>
    jsonEncode({
      'exists': true,
      'map_id': mapId,
      'staging': {'x': -5.75, 'y': 2.45, 'yaw': 3.14159},
      'docked': {'x': -6.6, 'y': 2.45, 'yaw': 3.14159},
      'saved_at': '2026-11-19T11:52:00',
      'visited_ok': visited,
      'source': source,
      'refined': false,
    });

DockSpot _spot({String source = kDockSourceMapPick, bool visited = false}) =>
    DockSpot(
      mapId: 'm1',
      dockedX: -6.6,
      dockedY: 2.45,
      dockedYaw: 3.14,
      stagingX: -5.75,
      stagingY: 2.45,
      stagingYaw: 3.14,
      savedAt: '2026-11-19T11:52:00',
      visitedOk: visited,
      source: source,
    );

void main() {
  late FakeRosServer server;

  setUp(() => server = FakeRosServer());

  SupervisorProvider connected(FakeAsync async) {
    final provider = SupervisorProvider(rosChannelConnector: server.connect);
    provider.connect(_settings);
    async.flushMicrotasks();
    return provider;
  }

  Map<String, Object?> lastCall(String service) => server.last.sent.lastWhere(
        (command) =>
            command['op'] == 'call_service' && command['service'] == service,
      );

  group('지도에서 지정한 도크 저장(/vica/dock/set)', () {
    test('SaveHome 타입으로 누른 도크·바라보는 방향(도)·map_pick 을 보내고, 수락되면 다시 읽는다', () {
      fakeAsync((async) {
        final provider = connected(async);
        ({bool ok, String reason})? result;
        provider
            .setDockFromMap(_settings,
                mapId: 'm1', x: -6.9, y: 2.45, yawDeg: 180)
            .then((value) => result = value);
        async.flushMicrotasks();
        expect(provider.dockBusy, isTrue);

        final call = lastCall(kDockSetService);
        expect(call['type'], 'vica_interfaces/srv/SaveHome');
        expect(call['args'], {
          'map_id': 'm1',
          'x': -6.9,
          'y': 2.45,
          'yaw': 180,
          'source': 'map_pick',
          'score': 0.0,
          'label': '',
        });

        expect(
          server.last.answer(kDockSetService, {
            'accepted': true,
            'message': _getMessage(),
            'visited_ok': false,
          }),
          isTrue,
        );
        async.flushMicrotasks();
        expect(lastCall(kDockGetService)['type'], 'std_srvs/srv/Trigger');
        server.last.answer(
            kDockGetService, {'success': true, 'message': _getMessage()});
        async.flushMicrotasks();

        expect(result, (ok: true, reason: ''));
        expect(provider.dockBusy, isFalse);
        final spot = provider.dockSpotFor('m1')!;
        expect(spot.mapPicked, isTrue);
        expect(spot.mapPickUnverified, isTrue);
        expect(spot.stagingX, -5.75);
        expect(provider.dockPointFor('m1')!.dx, -6.6);
      });
    });

    test('거절 사유는 문자열 그대로(busy · map_mismatch · write_failed)', () {
      for (final reason in ['busy', 'map_mismatch', 'write_failed']) {
        fakeAsync((async) {
          final provider = connected(async);
          ({bool ok, String reason})? result;
          provider
              .setDockFromMap(_settings, mapId: 'm1', x: 0, y: 0, yawDeg: 0)
              .then((value) => result = value);
          async.flushMicrotasks();
          server.last
              .answer(kDockSetService, {'accepted': false, 'message': reason});
          async.flushMicrotasks();
          expect(result, (ok: false, reason: reason));
          expect(isDockDriveOff(result!.reason), isFalse);
          expect(provider.dockBusy, isFalse);
          expect(provider.dockSpotFor('m1'), isNull);
        });
      }
    });

    test('서비스가 없으면(주행 꺼짐) call_failed', () {
      fakeAsync((async) {
        final provider = connected(async);
        ({bool ok, String reason})? result;
        provider
            .setDockFromMap(_settings, mapId: 'm1', x: 0, y: 0, yawDeg: 0)
            .then((value) => result = value);
        async.flushMicrotasks();
        server.last.answer(kDockSetService, {}, result: false);
        async.flushMicrotasks();
        expect(result!.ok, isFalse);
        expect(result!.reason, 'call_failed');
        expect(isDockDriveOff(result!.reason), isTrue);
        expect(provider.dockBusy, isFalse);
      });
    });

    test('연결이 없으면 부르지 않는다 — 주행 꺼짐이 아니라 연결 없음', () async {
      final provider = SupervisorProvider();
      final result = await provider.setDockFromMap(_settings,
          mapId: 'm1', x: 0, y: 0, yawDeg: 0);
      expect(result, (ok: false, reason: 'not_connected'));
      expect(isDockDriveOff(result.reason), isFalse);
      expect(provider.dockBusy, isFalse);
    });

    test('호출 도중 웹소켓이 끊기면 not_connected — 주행 꺼짐으로 보지 않는다', () {
      fakeAsync((async) {
        final provider = connected(async);
        ({bool ok, String reason})? result;
        provider
            .setDockFromMap(_settings, mapId: 'm1', x: 0, y: 0, yawDeg: 0)
            .then((value) => result = value);
        async.flushMicrotasks();
        expect(result, isNull);
        server.last.drop();
        async.flushMicrotasks();
        expect(result, (ok: false, reason: 'not_connected'));
        expect(isDockDriveOff(result!.reason), isFalse);
        expect(provider.dockBusy, isFalse);
      });
    });

    test('답이 늦으면 timeout — 주행 꺼짐으로 보지 않는다', () {
      fakeAsync((async) {
        final provider = connected(async);
        ({bool ok, String reason})? result;
        provider
            .setDockFromMap(_settings, mapId: 'm1', x: 0, y: 0, yawDeg: 0)
            .then((value) => result = value);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 30));
        expect(result!.reason, 'timeout');
        expect(isDockDriveOff(result!.reason), isFalse);
        expect(provider.dockBusy, isFalse);
      });
    });
  });

  group('도크 인식해서 저장(/vica/dock/register)', () {
    DockRegisterResult register(
      Map<String, Object?> values, {
      bool result = true,
      bool answerGet = false,
    }) {
      late DockRegisterResult out;
      fakeAsync((async) {
        final provider = connected(async);
        provider.registerDock(_settings, 'm1').then((value) => out = value);
        async.flushMicrotasks();
        expect(provider.dockBusy, isTrue);
        expect(server.last.answer(kDockRegisterService, values, result: result),
            isTrue);
        async.flushMicrotasks();
        if (answerGet) {
          server.last.answer(kDockGetService,
              {'success': true, 'message': _getMessage(source: 'v_detect')});
          async.flushMicrotasks();
        }
        async.elapse(const Duration(seconds: 30));
        expect(provider.dockBusy, isFalse);
      });
      return out;
    }

    test('성공 — 옮긴 거리를 읽는다', () {
      final ok = register({
        'success': true,
        'message': '{"staging":{"x":-5.88,"y":2.4,"yaw":3.1},"moved_cm":6.0,'
            '"turned_deg":2.1,"bumper_to_apex_cm":102.9}',
      }, answerGet: true);
      expect(ok.ok, isTrue);
      expect(ok.savedText, contains('서 있던 자리에서 6 cm'));
    });

    test('인식이 불안정 — 로봇에서 본 거리·방향·비스듬한 각', () {
      final u = register({
        'success': false,
        'message':
            '{"reason":"unstable","dist_m":2.6,"bearing_deg":20.0,"oblique_deg":50.0}',
      });
      expect(u.reason, 'unstable');
      expect(u.distM, 2.6);
      expect(u.bearingDeg, 20.0);
      expect(u.obliqueDeg, 50.0);
      expect(u.driveOff, isFalse);
    });

    test('서비스가 없으면 주행 꺼짐', () {
      final off = register({}, result: false);
      expect(off.ok, isFalse);
      expect(off.reason, 'call_failed');
      expect(off.driveOff, isTrue);
    });

    test('연결이 없으면 not_connected — 주행 꺼짐이 아니다', () async {
      final off = await SupervisorProvider().registerDock(_settings, 'm1');
      expect(off.reason, 'not_connected');
      expect(off.driveOff, isFalse);
    });

    test('호출 도중 웹소켓이 끊기면 not_connected — 주행 꺼짐으로 보지 않는다', () {
      fakeAsync((async) {
        final provider = connected(async);
        DockRegisterResult? out;
        provider.registerDock(_settings, 'm1').then((value) => out = value);
        async.flushMicrotasks();
        expect(out, isNull);
        server.last.drop();
        async.flushMicrotasks();
        expect(out!.reason, 'not_connected');
        expect(out!.driveOff, isFalse);
        expect(provider.dockBusy, isFalse);
      });
    });
  });

  group('보는 지도 ≠ 주행 지도 — 도킹 노드는 자기 지도의 도크만 돌려준다', () {
    ModeStatus driving(String mapId) => ModeStatus.fromJson({
          'mode': 'drive',
          'current_map_id': mapId,
          'running_maps': {'nav2': mapId},
        });

    /// [viewed] 지도를 보면서 조회하고, 도킹 노드가 [message] 로 답한 뒤의 provider.
    SupervisorProvider readAs(FakeAsync async, String viewed, String message) {
      final provider = connected(async);
      provider.refreshDockSpot(_settings, viewed);
      async.flushMicrotasks();
      expect(
          server.last
              .answer(kDockGetService, {'success': true, 'message': message}),
          isTrue);
      async.flushMicrotasks();
      return provider;
    }

    test('응답의 map_id 가 요청한 지도와 다르면 그 지도에는 도크가 없다 — 좌표를 그리지 않고 잠근다', () {
      fakeAsync((async) {
        final provider = readAs(async, 'm2', _getMessage(mapId: 'm1'));
        expect(provider.dockSpotFor('m2'), isNull);
        expect(provider.dockPointFor('m2'), isNull);
        expect(provider.dockOnOtherMap('m2'), isTrue);
        expect(provider.dockSpotFor('m1'), isNull);
        async.elapse(const Duration(seconds: 30));
      });
    });

    test('응답의 map_id 가 요청한 지도와 같으면 그대로 쓴다', () {
      fakeAsync((async) {
        final provider = readAs(async, 'm1', _getMessage(mapId: 'm1'));
        expect(provider.dockSpotFor('m1'), isNotNull);
        expect(provider.dockPointFor('m1')!.dx, -6.6);
        expect(provider.dockOnOtherMap('m1'), isFalse);
        async.elapse(const Duration(seconds: 30));
      });
    });

    test('옛 노드처럼 map_id 가 없으면 요청한 지도의 것으로 본다(종전 동작)', () {
      fakeAsync((async) {
        final message = jsonEncode(
            (jsonDecode(_getMessage()) as Map<String, Object?>)
              ..remove('map_id'));
        final provider = readAs(async, 'm2', message);
        expect(provider.dockSpotFor('m2'), isNotNull);
        expect(provider.dockOnOtherMap('m2'), isFalse);
        async.elapse(const Duration(seconds: 30));
      });
    });

    test('도크가 아직 없으면 응답에 map_id 가 없다 — 모드 노드가 알려 준 주행 지도로 잠근다', () {
      fakeAsync((async) {
        final provider = readAs(async, 'm2', '{"exists":false}');
        expect(provider.dockSpotFor('m2'), isNull);
        expect(provider.dockOnOtherMap('m2'), isFalse);
        provider.setModeStatusForTest(driving('m1'));
        expect(provider.dockOnOtherMap('m2'), isTrue);
        expect(provider.dockOnOtherMap('m1'), isFalse);
        provider.setModeStatusForTest(
            ModeStatus.fromJson({'mode': 'idle', 'current_map_id': 'm1'}));
        expect(provider.dockOnOtherMap('m2'), isFalse);
        expect(provider.dockOnOtherMap(null), isFalse);
        async.elapse(const Duration(seconds: 30));
      });
    });

    test('다른 지도를 보고 있어도 도킹 실패 팝업은 도킹 노드의 도크(주행 지도 것)로 고른다', () {
      fakeAsync((async) {
        final provider = readAs(async, 'm2', _getMessage(mapId: 'm1'));
        provider.handleGoalEventForTest(
            {'event': 'dock_failed', 'reason': 'not_found', 'map_id': 'm1'});
        expect(provider.pendingGoalAlert!.showsDockRedo, isTrue);
        async.elapse(const Duration(seconds: 30));
      });
    });
  });

  group('도킹이 끝나면(성공·실패) 도크 위치를 다시 읽는다(가 본 자리 · 고쳐 저장한 값)', () {
    Map<String, Object?> state(String state, String action, String result) => {
          'state': state,
          'near_dock': state == 'docked',
          'undock_pending': false,
          'last': {'action': action, 'result': result, 'reason': ''},
        };

    int gets() => server.last.sent
        .where(
            (c) => c['op'] == 'call_service' && c['service'] == kDockGetService)
        .length;

    test('직전 결과가 나오기 성공이어도, 도킹 성공이 오면 읽는다', () {
      fakeAsync((async) {
        final provider = connected(async);
        provider.setDockSpotForTest('m1', _spot());
        provider.handleDockStateForTest(state('idle', 'undock', 'success'));
        provider.handleDockStateForTest(state('docking', 'undock', 'success'));
        async.flushMicrotasks();
        expect(gets(), 0);

        provider.handleDockStateForTest(state('docked', 'dock', 'success'));
        async.flushMicrotasks();
        expect(gets(), 1);
        server.last.answer(kDockGetService, {
          'success': true,
          'message': jsonEncode({
            ...(jsonDecode(_getMessage(visited: true)) as Map<String, Object?>),
            'refined': true,
            'refined_from': 'map_pick',
            'refined_cm': 18.0,
            'refined_deg': 9.0,
          }),
        });
        async.flushMicrotasks();
        final spot = provider.dockSpotFor('m1')!;
        expect(spot.visitedOk, isTrue);
        expect(spot.refinedText, contains('지정한 자리에서 18 cm · 9°'));

        provider.handleDockStateForTest(state('docked', 'dock', 'success'));
        async.flushMicrotasks();
        expect(gets(), 1);
        async.elapse(const Duration(seconds: 30));
      });
    });

    test('직전 결과가 실패였다가 도킹 성공 — 종전처럼 읽는다', () {
      fakeAsync((async) {
        final provider = connected(async);
        provider.setDockSpotForTest('m1', _spot());
        provider.handleDockStateForTest(state('idle', 'dock', 'failed'));
        provider.handleDockStateForTest(state('docked', 'dock', 'success'));
        async.flushMicrotasks();
        expect(gets(), 1);
        async.elapse(const Duration(seconds: 30));
      });
    });

    test('나오기 성공에는 읽지 않고, 처음 받은 상태에도 읽지 않는다', () {
      fakeAsync((async) {
        final provider = connected(async);
        provider.setDockSpotForTest('m1', _spot());
        provider.handleDockStateForTest(state('docked', 'dock', 'success'));
        provider.handleDockStateForTest(state('idle', 'undock', 'success'));
        provider.handleDockStateForTest(state('idle', 'undock', 'failed'));
        async.flushMicrotasks();
        expect(gets(), 0);
        async.elapse(const Duration(seconds: 30));
      });
    });

    test('도킹 실패에도 읽는다 — 범위 밖이면 로봇이 도크 위치를 고쳐 저장한다', () {
      fakeAsync((async) {
        final provider = connected(async);
        provider.setDockSpotForTest('m1', _spot());
        provider.handleDockStateForTest(state('idle', 'undock', 'success'));
        provider.handleDockStateForTest(state('docking', 'undock', 'success'));
        async.flushMicrotasks();
        expect(gets(), 0);

        provider.handleDockStateForTest({
          ...state('idle', 'dock', 'failed'),
          'last': {
            'action': 'dock',
            'result': 'failed',
            'reason': 'out_of_range'
          },
        });
        async.flushMicrotasks();
        expect(gets(), 1);
        server.last.answer(kDockGetService, {
          'success': true,
          'message': jsonEncode({
            ...(jsonDecode(_getMessage(source: 'v_detect'))
                as Map<String, Object?>),
            'refined': true,
            'refined_from': 'map_pick',
          }),
        });
        async.flushMicrotasks();
        final spot = provider.dockSpotFor('m1')!;
        expect(spot.mapPicked, isFalse);
        expect(spot.refinedFrom, 'map_pick');
        expect(spot.mapPickUnverified, isTrue);
        provider.handleGoalEventForTest(
            {'event': 'dock_failed', 'reason': 'not_found', 'map_id': 'm1'});
        expect(provider.pendingGoalAlert!.showsDockRedo, isTrue);
        async.elapse(const Duration(seconds: 30));
      });
    });

    test('같은 사유로 연달아 실패해도(last 가 그대로) 도킹이 끝날 때마다 읽는다', () {
      fakeAsync((async) {
        final provider = connected(async);
        provider.setDockSpotForTest('m1', _spot());
        Map<String, Object?> failed(String st) => {
              ...state(st, 'dock', 'failed'),
              'last': {
                'action': 'dock',
                'result': 'failed',
                'reason': 'not_found'
              },
            };
        provider.handleDockStateForTest(state('idle', 'undock', 'success'));
        provider.handleDockStateForTest(failed('idle'));
        async.flushMicrotasks();
        expect(gets(), 1);
        provider.handleDockStateForTest(failed('docking'));
        async.flushMicrotasks();
        expect(gets(), 1);
        provider.handleDockStateForTest(failed('idle'));
        async.flushMicrotasks();
        expect(gets(), 2);
        provider.handleDockStateForTest(failed('idle'));
        async.flushMicrotasks();
        expect(gets(), 2);
        async.elapse(const Duration(seconds: 30));
      });
    });
  });

  group('도킹 실패가 온 그때의 도크 위치로 팝업을 고른다(목업 92)', () {
    Map<String, Object?> failed(String reason) =>
        {'event': 'dock_failed', 'reason': reason, 'map_id': 'm1'};

    test('지도에서 지정 · 아직 확인 안 됨 → 다시 잡기 안내', () {
      final provider = SupervisorProvider()..setDockSpotForTest('m1', _spot());
      provider.handleGoalEventForTest(failed('not_found'));
      final alert = provider.pendingGoalAlert!;
      expect(alert.dockFirstTry, isTrue);
      expect(alert.showsDockRedo, isTrue);
      expect(alert.description, '도크를 찾지 못했습니다.\n로봇은 도크 앞에서 기다리고 있습니다.');
    });

    test('out_of_range 도 같다', () {
      final provider = SupervisorProvider()..setDockSpotForTest('m1', _spot());
      provider.handleGoalEventForTest(failed('out_of_range'));
      expect(provider.pendingGoalAlert!.showsDockRedo, isTrue);
    });

    test('nav_failed(도크 앞까지 못 감)도 다시 잡기 안내 — 첫 줄은 기존 문구', () {
      final provider = SupervisorProvider()..setDockSpotForTest('m1', _spot());
      provider.handleGoalEventForTest(failed('nav_failed'));
      final alert = provider.pendingGoalAlert!;
      expect(alert.showsDockRedo, isTrue);
      expect(alert.description, '도크 앞까지 가지 못했습니다.\n로봇은 그 자리에 멈춰 있습니다.');
      final other = SupervisorProvider()
        ..setDockSpotForTest('m1', _spot(source: kDockSourceVDetect));
      other.handleGoalEventForTest(failed('nav_failed'));
      expect(other.pendingGoalAlert!.showsDockRedo, isFalse);
    });

    test('도크 인식으로 저장한 자리 · 가 본 자리 · 도크 위치 없음이면 기존 팝업', () {
      for (final spot in [
        _spot(source: kDockSourceVDetect),
        _spot(visited: true),
        null,
      ]) {
        final provider = SupervisorProvider()..setDockSpotForTest('m1', spot);
        provider.handleGoalEventForTest(failed('not_found'));
        final alert = provider.pendingGoalAlert!;
        expect(alert.showsDockRedo, isFalse);
        expect(alert.description, contains('구조물을 옮겼는지 확인해주세요.'));
      }
    });

    test('지도에서 지정한 자리라도 다른 사유의 실패는 기존 팝업', () {
      final provider = SupervisorProvider()..setDockSpotForTest('m1', _spot());
      provider.handleGoalEventForTest(failed('blocked'));
      final alert = provider.pendingGoalAlert!;
      expect(alert.showsDockRedo, isFalse);
      expect(alert.description.split('\n').first, '앞이 30초 넘게 막혀 들어가지 못했습니다.');
    });

    test('나오기 실패에는 표시하지 않는다', () {
      final provider = SupervisorProvider()..setDockSpotForTest('m1', _spot());
      provider.handleGoalEventForTest(
          {'event': 'undock_failed', 'reason': 'not_found', 'map_id': 'm1'});
      expect(provider.pendingGoalAlert!.dockFirstTry, isFalse);
      expect(provider.pendingGoalAlert!.showsDockRedo, isFalse);
    });
  });
}
