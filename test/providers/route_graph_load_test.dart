// 레일 파일을 어디서 받아 어떻게 담아 두는지 고정합니다(2026-09-30).
//
// **이 파일이 지키는 것**: 레일 파일이 없는 지도는 오류가 아니다. 그 지도에는
// 레일을 안 그릴 뿐, 알림도 로그도 남기지 않는다(사용자 결정).
import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/core/app_settings.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';
import 'package:vica_supervisor/services/route_graph_loader.dart';

const _geojson = '{"type":"FeatureCollection","features":['
    '{"type":"Feature","properties":{"id":1,"frame":"map"},'
    '"geometry":{"type":"Point","coordinates":[1.0,2.0]}},'
    '{"type":"Feature","properties":{"id":2,"frame":"map"},'
    '"geometry":{"type":"Point","coordinates":[2.0,2.0]}},'
    '{"type":"Feature","properties":{"id":1001,"startid":1,"endid":2},'
    '"geometry":{"type":"MultiLineString","coordinates":[[[1,2],[2,2]]]}}'
    ']}';

void main() {
  const settings = AppSettings(mapHttpBaseUrl: 'http://192.168.0.31:8000/');

  test('레일 파일 주소는 지도 그림 서버의 maps/<지도>_route.geojson 이다', () {
    // 젯슨 launch 가 <지도>_route.geojson 을 찾는 규칙과 같다. 끝의 / 는 겹치지 않는다.
    expect(
      RouteGraphLoader.uriFor('http://192.168.0.31:8000/', 'vica_map_0903_d'),
      Uri.parse('http://192.168.0.31:8000/maps/vica_map_0903_d_route.geojson'),
    );
  });

  test('받은 파일을 그 지도의 레일로 담아 두고 알린다', () async {
    final requested = <Uri>[];
    final provider = SupervisorProvider(
      routeGraphLoader: RouteGraphLoader(fetch: (uri) async {
        requested.add(uri);
        return _geojson;
      }),
    );
    addTearDown(provider.dispose);
    var notified = 0;
    provider.addListener(() => notified++);

    await provider.loadRouteGraph(settings, 'vica_map_0903_d');

    expect(requested.single.path, '/maps/vica_map_0903_d_route.geojson');
    expect(provider.routeGraphFor('vica_map_0903_d')!.nodes, hasLength(2));
    expect(provider.routeGraphFor('other_map'), isNull);
    expect(notified, 1);
  });

  test('파일이 없는 지도(404)는 조용히 넘어간다', () async {
    final provider = SupervisorProvider(
      routeGraphLoader: RouteGraphLoader(fetch: (_) async => null),
    );
    addTearDown(provider.dispose);
    final logsBefore = provider.logs.length;
    var notified = 0;
    provider.addListener(() => notified++);

    await provider.loadRouteGraph(settings, 'vica_map_no_rail');

    expect(provider.routeGraphFor('vica_map_no_rail'), isNull);
    expect(provider.logs.length, logsBefore, reason: '로그를 남기지 않는다');
    expect(notified, 0, reason: '바뀐 것이 없으면 화면을 다시 그리지 않는다');
  });

  test('네트워크 예외도 화면을 죽이지 않는다', () async {
    final provider = SupervisorProvider(
      routeGraphLoader: RouteGraphLoader(
        fetch: (_) async => throw Exception('connection refused'),
      ),
    );
    addTearDown(provider.dispose);

    await provider.loadRouteGraph(settings, 'vica_map_0903_d');

    expect(provider.routeGraphFor('vica_map_0903_d'), isNull);
  });

  test('있던 레일이 사라지면 지우고 알린다', () async {
    var body = _geojson;
    final provider = SupervisorProvider(
      routeGraphLoader: RouteGraphLoader(fetch: (_) async => body),
    );
    addTearDown(provider.dispose);
    await provider.loadRouteGraph(settings, 'm');
    expect(provider.routeGraphFor('m'), isNotNull);

    body = '';
    var notified = 0;
    provider.addListener(() => notified++);
    await provider.loadRouteGraph(settings, 'm');

    expect(provider.routeGraphFor('m'), isNull);
    expect(notified, 1);
  });
}
