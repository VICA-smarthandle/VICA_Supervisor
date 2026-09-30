// 레일 스케치 조작과 로봇 응답 읽기를 고정합니다(2026-09-30).

import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/models/route_edit.dart';
import 'package:vica_supervisor/models/route_graph.dart';

void main() {
  test('노드 추가·잇기·옮기기·지우기', () {
    var s = RouteSketch.empty
        .addNode(const Offset(0, 0))
        .addNode(const Offset(3, 0));
    expect(s.nodes.keys, [1, 2]);
    s = s.connect(1, 2).connect(2, 1).connect(1, 1);
    expect(s.edges, [const RouteEdge(1, 2)], reason: '같은 선·자기 자신은 한 번만/안 이음');
    s = s.moveNode(2, const Offset(4, 1));
    expect(s.nodes[2], const Offset(4, 1));
    s = s.addNode(const Offset(0, 3)).connect(1, 3);
    s = s.removeNode(1);
    expect(s.edges, isEmpty, reason: '노드를 지우면 붙은 선도 지운다');
    expect(s.nodes.keys, [2, 3]);
  });

  test('가까운 노드·선 찾기', () {
    final s = RouteSketch.empty
        .addNode(const Offset(0, 0))
        .addNode(const Offset(4, 0))
        .connect(1, 2);
    expect(s.nodeNear(const Offset(0.3, 0.2), 0.6), 1);
    expect(s.nodeNear(const Offset(2, 0), 0.6), isNull);
    expect(s.edgeNear(const Offset(2, 0.2), 0.36), const RouteEdge(1, 2));
  });

  test('앱이 보내는 모양 = 로봇이 읽는 모양(route_graph_build.parse_sketch)', () {
    final s = RouteSketch.empty
        .addNode(const Offset(1, 2))
        .addNode(const Offset(3, 4))
        .connect(1, 2);
    final back = RouteSketch.decode(s.encode());
    expect(back.nodes, s.nodes);
    expect(back.edges, s.edges);
    expect(s.toJson()['edges'], [
      [1, 2],
    ]);
  });

  test('깨진 JSON 은 빈 스케치·빈 검사', () {
    expect(RouteSketch.decode('{').isEmpty, isTrue);
    expect(RouteChecks.decode('nope').errors, isEmpty);
  });

  test('검사 결과를 읽는다', () {
    final c = RouteChecks.decode(
      '{"errors":[{"code":"too_close_to_wall","x":1.5,"y":2,"value":0.52,'
      '"message":"벽"}],"warnings":[{"code":"far_place","x":0,"y":0,"value":10.3,'
      '"name":"학과사무실","message":"멀다"}],"places":[{"name":"학과사무실",'
      '"distance":10.31,"far":true}],"summary":{"node_count":59,"length_m":50.4,'
      '"junction_count":3}}',
    );
    expect(c.errors.single.value, 0.52);
    expect(c.farPlaces.single.name, '학과사무실');
    expect(c.places.single.far, isTrue);
    expect(c.summary.nodeCount, 59);
    expect(c.summary.junctionCount, 3);
  });

  test('미리보기(엣지에 벌점이 붙은 모양)도 지도용 레일로 읽는다', () {
    final g = decodeRoutePreview(
      '{"nodes":[{"id":1,"x":0,"y":0},{"id":2,"x":1,"y":0}],"edges":[[1,2,0.1]]}',
    )!;
    expect(g.edges, [const RouteEdge(1, 2)]);
  });
}
