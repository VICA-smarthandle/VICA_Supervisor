// 지도 수정 요청이 로봇과 약속한 모양(MapFix.srv)으로 나가는지, 진행 토픽이 화면 상태로
// 들어오고 끊기면 지워지는지, 그림 버전이 그림 주소를 바꾸는지 고정합니다.
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/core/app_settings.dart';
import 'package:vica_supervisor/models/map_fix.dart';
import 'package:vica_supervisor/models/vica_map.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';
import 'package:vica_supervisor/widgets/map_canvas.dart';

import '../ros/fake_ros_socket.dart';

Map<String, Object?> _lastCall(FakeRosSocket socket) => socket.sent.lastWhere(
      (command) =>
          command['op'] == 'call_service' &&
          command['service'] == SupervisorProvider.mapFixService,
    );

void main() {
  late FakeRosServer server;

  setUp(() => server = FakeRosServer());

  SupervisorProvider connected(FakeAsync async) {
    final provider = SupervisorProvider(rosChannelConnector: server.connect);
    provider.connect(const AppSettings());
    async.flushMicrotasks();
    return provider;
  }

  test('mapFix 가 map_id·action·args_json 을 보낸다', () {
    fakeAsync((async) {
      final provider = connected(async);
      MapFixResult? reply;
      provider.mapFix(
        'map_a',
        'erase',
        args: {
          'rects': [
            const MapFixRect(
              xMin: 1.2,
              yMin: 2.5,
              xMax: 1.8,
              yMax: 3.0,
            ).toJson(),
          ],
        },
      ).then((value) => reply = value);
      async.flushMicrotasks();

      final call = _lastCall(server.last);
      expect(call['type'], 'vica_interfaces/srv/MapFix');
      final args = call['args']! as Map<String, Object?>;
      expect(args['map_id'], 'map_a');
      expect(args['action'], 'erase');
      expect(jsonDecode(args['args_json']! as String), {
        'rects': [
          {'x_min': 1.2, 'y_min': 2.5, 'x_max': 1.8, 'y_max': 3.0},
        ],
      });

      server.last.answer(SupervisorProvider.mapFixService, {
        'accepted': true,
        'reason': '',
        'message': '지도를 수정했습니다.',
        'result_json':
            '{"black": 5, "gray": 1, "applied": true, "mission_stale": false}',
      });
      async.flushMicrotasks();
      expect(reply!.accepted, isTrue);
      expect(reply!.applied, isTrue);
      expect(reply!.missionStale, isFalse);

      provider.dispose();
      async.flushMicrotasks();
    });
  });

  test('인자가 없으면 args_json 은 빈 문자열이다', () {
    fakeAsync((async) {
      final provider = connected(async);
      provider.mapFix('map_a', 'get');
      async.flushMicrotasks();

      final args = _lastCall(server.last)['args']! as Map<String, Object?>;
      expect(args['args_json'], '');

      provider.dispose();
      async.flushMicrotasks();
    });
  });

  test('연결이 없으면 offline 으로 답한다', () {
    fakeAsync((async) {
      final provider = SupervisorProvider(rosChannelConnector: server.connect);
      MapFixResult? reply;
      provider.mapFix('map_a', 'get').then((value) => reply = value);
      async.flushMicrotasks();

      expect(reply!.accepted, isFalse);
      expect(reply!.reason, 'offline');
      expect(server.sockets, isEmpty);

      provider.dispose();
      async.flushMicrotasks();
    });
  });

  test('노드가 답하지 않으면 시간 초과 뒤 offline 으로 답한다', () {
    fakeAsync((async) {
      final provider = connected(async);
      MapFixResult? reply;
      provider.mapFix('map_a', 'get').then((value) => reply = value);
      async.flushMicrotasks();
      expect(reply, isNull);

      async.elapse(const Duration(seconds: 9));
      expect(reply!.accepted, isFalse);
      expect(reply!.reason, 'offline');
      // 화면에는 쉬운 말만 보입니다(목업 94 ⑤).
      expect(reply!.message, kMapFixNoReplyText);
      expect(reply!.message, isNot(contains('map_fix_node')));

      provider.dispose();
      async.flushMicrotasks();
    });
  });

  test('지도를 바꾸는 요청이 답을 못 받으면 오류 원문은 기록에만 남는다', () {
    fakeAsync((async) {
      final provider = connected(async);
      MapFixResult? reply;
      provider.mapFix('map_a', 'erase', args: {
        'rects': [
          const MapFixRect(xMin: 0, yMin: 0, xMax: 1, yMax: 1).toJson(),
        ],
      }).then((value) => reply = value);
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 16));

      expect(reply!.message, kMapFixNoReplyText);
      final last = provider.logs.first.message;
      expect(last, startsWith('지도 수정 실패: $kMapFixNoReplyText'));
      expect(last, contains('map_fix_node'));

      provider.dispose();
      async.flushMicrotasks();
    });
  });

  test('refreshMapFix 가 그 지도의 잠금·기록을 남긴다', () {
    fakeAsync((async) {
      final provider = connected(async);
      provider.refreshMapFix('map_a');
      async.flushMicrotasks();
      expect(
        (_lastCall(server.last)['args']! as Map<String, Object?>)['action'],
        'get',
      );
      server.last.answer(SupervisorProvider.mapFixService, {
        'accepted': true,
        'reason': '',
        'message': '',
        'result_json':
            '{"lock": "busy_driving", "can_scan": false, "history": []}',
      });
      async.flushMicrotasks();

      expect(provider.mapFixStatusFor('map_a')!.lock, 'busy_driving');
      // 다른 지도의 상태로 쓰이지 않습니다.
      expect(provider.mapFixStatusFor('map_b'), isNull);

      provider.dispose();
      async.flushMicrotasks();
    });
  });

  test('토픽 상태가 mapFixScan 에 들어오고 끊기면 지워진다', () {
    fakeAsync((async) {
      final provider = connected(async);
      expect(
        server.last.sent.any(
          (command) =>
              command['op'] == 'subscribe' &&
              command['topic'] == SupervisorProvider.mapFixStateTopic,
        ),
        isTrue,
      );

      server.last.receive({
        'op': 'publish',
        'topic': SupervisorProvider.mapFixStateTopic,
        'msg': {
          'data': jsonEncode({
            'session': 's1',
            'map_id': 'map_a',
            'phase': 'step_back',
            'remaining_s': 3,
            'radius_m': 2.0,
          }),
        },
      });
      async.flushMicrotasks();
      expect(provider.mapFixScan!.phase, 'step_back');
      expect(provider.mapFixScan!.remainingS, 3);

      server.last.drop();
      async.flushMicrotasks();
      expect(provider.mapFixScan, isNull);

      provider.dispose();
      async.flushMicrotasks();
    });
  });

  test('끝난 세션(done)은 남기지 않는다', () {
    final provider = SupervisorProvider();
    provider.handleMapFixStateForTest({'session': 's1', 'phase': 'preview'});
    expect(provider.mapFixScan, isNotNull);
    provider.handleMapFixStateForTest({'session': 's1', 'phase': 'done'});
    expect(provider.mapFixScan, isNull);
    provider.dispose();
  });

  test('지도 목록의 image_version 을 읽는다', () {
    final map = VicaMap.fromJson({
      'map_id': 'map_a',
      'image_url': '/maps/map_a.png',
      'image_version': 1763545327,
    });
    expect(map.imageVersion, 1763545327);
    expect(VicaMap.fromJson(map.toJson()).imageVersion, 1763545327);
    // 옛 노드는 안 실어 보냅니다.
    expect(VicaMap.fromJson({'map_id': 'map_a'}).imageVersion, 0);
  });

  testWidgets('그림 버전이 바뀌면 지도 그림 주소가 바뀐다', (tester) async {
    String urlFor(VicaMap map) {
      final image = tester.widget<Image>(find.byType(Image));
      return (image.image as NetworkImage).url;
    }

    Widget canvas(VicaMap map) => MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 300,
              child: MapCanvas(
                map: map,
                settings: const AppSettings(),
                locations: const [],
              ),
            ),
          ),
        );

    VicaMap map(int version) => VicaMap(
          mapId: 'map_a',
          mapName: '시험 지도',
          imageUrl: '/maps/map_a.png',
          resolution: 0.05,
          originX: 0,
          originY: 0,
          width: 400,
          height: 300,
          imageVersion: version,
        );

    await tester.pumpWidget(canvas(map(0)));
    final plain = urlFor(map(0));
    expect(plain, endsWith('/maps/map_a.png'));

    await tester.pumpWidget(canvas(map(7)));
    expect(urlFor(map(7)), '$plain?v=7');

    await tester.pumpWidget(canvas(map(8)));
    expect(urlFor(map(8)), '$plain?v=8');
  });

  test('지도를 바꾼 수정이 받아들여지면 지도 목록을 다시 받는다(그림 버전 갱신)', () {
    // 11-19 실기: 적용·되돌리기 뒤 앱 '새로고침'에도 옛 그림이 남았다. 목록을 다시 받아야
    // image_version 이 바뀌어 그림 주소가 달라진다.
    fakeAsync((async) {
      final provider = connected(async);
      int listRequests() => server.last.sent
          .where((c) =>
              c['op'] == 'publish' &&
              c['topic'] == const AppSettings().mapListRequestTopic)
          .length;

      for (final (action, accepted) in [
        ('get', true),
        ('erase', false),
        ('erase', true),
        ('scan_apply', true),
        ('undo', true),
      ]) {
        final before = listRequests();
        provider.mapFix('map_a', action);
        async.flushMicrotasks();
        server.last.answer(SupervisorProvider.mapFixService, {
          'accepted': accepted,
          'reason': accepted ? '' : 'busy_driving',
          'message': '',
          'result_json': '{}',
        });
        async.flushMicrotasks();
        final changed = accepted && action != 'get';
        expect(listRequests() - before, changed ? 1 : 0,
            reason: '$action accepted=$accepted');
      }
    });
  });
}
