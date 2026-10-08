// 레일 편집 흐름(2026-09-30)을 rosbridge 없이 고정합니다. 서비스는 가짜로 끼웁니다.
//
// 지키는 것:
//   - 도구별 지도 누르기(노드 추가 · 선 잇기 · 지우기), 길게 눌러 옮기기
//   - 벽을 가로지르는 선은 표시 없이 잇지 않는다(사용자 결정)
//   - 저장 결과별 분기: 저장·검사 실패·충돌(F)·적용 실패(D)
//   - 주행 뒤 적용 소식: 성공은 알림 띠, 실패는 팝업 D
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/core/app_settings.dart';
import 'package:vica_supervisor/models/route_edit.dart';
import 'package:vica_supervisor/models/route_graph.dart';
import 'package:vica_supervisor/models/vica_map.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';
import 'package:vica_supervisor/services/map_wall_mask.dart';
import 'package:vica_supervisor/services/route_graph_loader.dart';

const _settings = AppSettings();
const _map = VicaMap(
  mapId: 'm',
  mapName: 'm',
  imageUrl: '/maps/m.png',
  resolution: 0.05,
  originX: 0,
  originY: 0,
  width: 200,
  height: 100,
);

/// 10 m x 5 m, x 5.0 m 에 세로 벽.
MapWallMask _wallAtX5() {
  final rgba = Uint8List(200 * 100 * 4);
  for (var r = 0; r < 100; r++) {
    for (var c = 0; c < 200; c++) {
      final i = (r * 200 + c) * 4;
      final v = c == 100 ? 0 : 254;
      rgba[i] = rgba[i + 1] = rgba[i + 2] = v;
      rgba[i + 3] = 255;
    }
  }
  return MapWallMask.fromRgba(_map, 200, 100, rgba);
}

class _Calls {
  final List<(String, Map<String, Object?>)> log = [];
  Map<String, Object?> Function(String service, Map<String, Object?> args)?
      answer;

  Future<Map<String, Object?>> call(String service, String type,
      Map<String, Object?> args, Duration timeout) async {
    log.add((service, args));
    return answer?.call(service, args) ?? {};
  }
}

SupervisorProvider _provider(_Calls calls) => SupervisorProvider(
      routeServiceCall: calls.call,
      wallMaskLoader: (_, __) async => null,
      routeGraphLoader: RouteGraphLoader(fetch: (_) async => null),
    );

void main() {
  test('도구별 누르기: 노드 추가 → 선 잇기 → 지우기', () {
    final p = _provider(_Calls());
    addTearDown(p.dispose);
    p.enterRouteEdit(_settings, _map);
    p.routeTap(const Offset(1, 2));
    p.routeTap(const Offset(4, 2));
    p.routeTap(const Offset(1.1, 2)); // 이미 노드가 있는 자리 — 추가 안 함
    expect(p.routeSketch.nodes, hasLength(2));

    p.setRouteTool(RouteEditTool.connect);
    p.routeTap(const Offset(1, 2));
    expect(p.routeConnectFrom, 1);
    p.routeTap(const Offset(4, 2));
    expect(p.routeSketch.edges, [const RouteEdge(1, 2)]);
    expect(p.routeConnectFrom, isNull);
    expect(p.routeDirty, isTrue);

    p.setRouteTool(RouteEditTool.erase);
    p.routeTap(const Offset(2.5, 2.05)); // 선 위
    expect(p.routeSketch.edges, isEmpty);
    p.routeTap(const Offset(4, 2));
    expect(p.routeSketch.nodes.keys, [1]);
  });

  test('벽을 가로지르는 선은 잇지 않는다(표시 없음)', () {
    final p = _provider(_Calls());
    addTearDown(p.dispose);
    p.setWallMaskForTest('m', _wallAtX5());
    p.enterRouteEdit(_settings, _map);
    p.routeTap(const Offset(2, 2));
    p.routeTap(const Offset(8, 2));
    p.setRouteTool(RouteEditTool.connect);
    p.routeTap(const Offset(2, 2));
    p.routeTap(const Offset(8, 2));
    expect(p.routeSketch.edges, isEmpty);
    expect(p.routeMessage, isEmpty, reason: '화면에 따로 알리지 않는다');
  });

  test('길게 눌러 옮기되, 이어진 선이 벽을 넘는 자리로는 안 간다', () {
    final p = _provider(_Calls());
    addTearDown(p.dispose);
    p.setWallMaskForTest('m', _wallAtX5());
    p.enterRouteEdit(_settings, _map);
    p.routeTap(const Offset(1, 2));
    p.routeTap(const Offset(3, 2));
    p.setRouteTool(RouteEditTool.connect);
    p.routeTap(const Offset(1, 2));
    p.routeTap(const Offset(3, 2));
    p.routeDragStart(const Offset(3, 2));
    p.routeDragUpdate(const Offset(4, 3));
    expect(p.routeSketch.nodes[2], const Offset(4, 3));
    p.routeDragUpdate(const Offset(7, 3)); // 벽 너머
    expect(p.routeSketch.nodes[2], const Offset(4, 3));
    p.routeDragEnd();
  });

  Future<SupervisorProvider> sketched(_Calls calls) async {
    final p = _provider(calls);
    p.enterRouteEdit(_settings, _map);
    p.routeTap(const Offset(1, 2));
    p.routeTap(const Offset(4, 2));
    p.setRouteTool(RouteEditTool.connect);
    p.routeTap(const Offset(1, 2));
    p.routeTap(const Offset(4, 2));
    return p;
  }

  test('저장 성공: 편집을 닫고 레일 정보를 다시 받는다. 보낸 스케치는 앱 모양 그대로', () async {
    final calls = _Calls()
      ..answer = (service, args) => service == _settings.routeSaveService
          ? {
              'accepted': true,
              'reason': '',
              'message': '레일을 저장했습니다.',
              'applied': true
            }
          : {
              'found': true,
              'version': 'v2',
              'status': 'applied',
              'sketch_json': '{}',
              'checks_json': '{}'
            };
    final p = await sketched(calls);
    addTearDown(p.dispose);
    final outcome = await p.saveRoute(_settings, 'm');
    expect(outcome, RouteSaveOutcome.saved);
    expect(p.routeEditing, isFalse);
    final save = calls.log.firstWhere((c) =>
        c.$1 == _settings.routeSaveService && c.$2['preview_only'] == false);
    expect(jsonDecode(save.$2['sketch_json']! as String)['edges'], [
      [1, 2],
    ]);
    expect(save.$2['apply_now'], isTrue);
    expect(calls.log.any((c) => c.$1 == _settings.routeGetService), isTrue);
    expect(p.routeInfoFor('m')!.version, 'v2');
  });

  test('검사에서 걸리면 편집을 유지하고 번호 목록이 남는다', () async {
    final calls = _Calls()
      ..answer = (service, args) => {
            'accepted': false,
            'reason': 'check_failed',
            'message': '검사에서 1건이 걸려 저장하지 않았습니다.',
            'checks_json': '{"errors":[{"code":"too_close_to_wall","x":2,"y":2,'
                '"value":0.52,"message":"벽"}]}',
          };
    final p = await sketched(calls);
    addTearDown(p.dispose);
    expect(await p.saveRoute(_settings, 'm'), RouteSaveOutcome.checkFailed);
    expect(p.routeEditing, isTrue);
    expect(p.routeChecks.errors.single.code, 'too_close_to_wall');
  });

  test('다른 곳에서 먼저 저장했으면 충돌(팝업 F), 덮어쓰기는 overwrite 로 보낸다', () async {
    var n = 0;
    final calls = _Calls()
      ..answer = (service, args) {
        if (service != _settings.routeSaveService) {
          return {'found': true};
        }
        n++;
        return n == 1
            ? {'accepted': false, 'reason': 'conflict', 'message': '바뀜'}
            : {
                'accepted': true,
                'reason': '',
                'message': '저장',
                'applied': true
              };
      };
    final p = await sketched(calls);
    addTearDown(p.dispose);
    expect(await p.saveRoute(_settings, 'm'), RouteSaveOutcome.conflict);
    expect(p.routeEditing, isTrue);
    expect(await p.saveRoute(_settings, 'm', overwrite: true),
        RouteSaveOutcome.saved);
    final saves =
        calls.log.where((c) => c.$1 == _settings.routeSaveService).toList();
    expect(saves.last.$2['overwrite'], isTrue);
  });

  test('저장됐지만 적용 실패면 팝업 D 를 셸에 넘긴다', () async {
    final calls = _Calls()
      ..answer = (service, args) => service == _settings.routeSaveService
          ? {
              'accepted': true,
              'reason': 'apply_failed',
              'message': 'route server가 새 레일 파일을 읽지 못했습니다.'
            }
          : {'found': true};
    final p = await sketched(calls);
    addTearDown(p.dispose);
    await p.saveRoute(_settings, 'm');
    expect(p.pendingRouteAlert, contains('읽지 못했습니다'));
  });

  test('주행 중이라 미뤄 둔 적용: 저장은 성공, 팝업 없음', () async {
    final calls = _Calls()
      ..answer = (service, args) => service == _settings.routeSaveService
          ? {
              'accepted': true,
              'reason': 'busy_driving',
              'message': '현재 주행 중이므로 적용이 불가합니다. 주행 완료 후 적용합니다.'
            }
          : {'found': true, 'status': 'apply_pending'};
    final p = await sketched(calls);
    addTearDown(p.dispose);
    expect(await p.saveRoute(_settings, 'm'), RouteSaveOutcome.saved);
    expect(p.pendingRouteAlert, isNull);
    expect(p.routeInfoFor('m')!.status, 'apply_pending');
  });

  test('주행 뒤 적용 소식: 성공은 알림 띠, 실패는 팝업 D', () {
    final p = _provider(_Calls());
    addTearDown(p.dispose);
    p.handleRouteStateForTest(
        {'map_id': 'm', 'applied': true, 'message': '적용했습니다.'});
    expect(p.pendingRouteToast, isNotNull);
    expect(p.pendingRouteAlert, isNull);
    p.handleRouteStateForTest({
      'map_id': 'm',
      'applied': false,
      'message': 'route server가 실행되면 적용됩니다.'
    });
    expect(p.pendingRouteAlert, 'route server가 실행되면 적용됩니다.');
  });

  test('미리보기는 파일을 쓰지 않는 요청(preview_only)이다', () async {
    final calls = _Calls()
      ..answer = (service, args) => {
            'accepted': true,
            'preview_json':
                '{"nodes":[{"id":1,"x":1,"y":2},{"id":2,"x":4,"y":2}],"edges":[[1,2,0]]}',
            'checks_json': '{}',
          };
    final p = await sketched(calls);
    addTearDown(p.dispose);
    await p.requestRoutePreview(_settings, 'm');
    expect(calls.log.last.$2['preview_only'], isTrue);
    expect(p.routePreview!.edges, hasLength(1));
  });

  test('다른 기기에서 레일 저장 알림: 본 적 있는 지도만 레일을 다시 받는다', () async {
    var fetches = <String>[];
    final p = SupervisorProvider(
      routeServiceCall: _Calls().call,
      wallMaskLoader: (_, __) async => null,
      routeGraphLoader: RouteGraphLoader(fetch: (uri) async {
        fetches.add(uri.path);
        return null;
      }),
    );
    addTearDown(p.dispose);
    p.handleRouteSavedForTest({'map_id': 'm'});
    await Future<void>.delayed(Duration.zero);
    expect(fetches, isEmpty); // 고르지도 받지도 않은 지도
    p.selectMap(_settings, 'm');
    await Future<void>.delayed(Duration.zero);
    fetches = [];
    p.handleRouteSavedForTest({'map_id': 'm'});
    await Future<void>.delayed(Duration.zero);
    expect(fetches, ['/maps/m_route.geojson']);
    p.handleRouteSavedForTest({'map_id': ''});
    p.handleRouteSavedForTest({'map_id': 'other'});
    await Future<void>.delayed(Duration.zero);
    expect(fetches, hasLength(1));
  });
}
