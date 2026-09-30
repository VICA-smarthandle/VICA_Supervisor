// 레일 파일(nav2_route GeoJSON)을 앱이 어떻게 읽는지 고정합니다(2026-09-30).
//
// 파일은 젯슨의 maps/<지도>_route.geojson 이고, 같은 선이 양방향으로 두 번
// 들어 있습니다. 앱은 그리기만 하므로 하나로 합칩니다.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/models/route_graph.dart';

Map<String, Object?> node(int id, double x, double y) => {
      'type': 'Feature',
      'properties': {'id': id, 'frame': 'map'},
      'geometry': {
        'type': 'Point',
        'coordinates': [x, y],
      },
    };

Map<String, Object?> edge(int id, int a, int b) => {
      'type': 'Feature',
      'properties': {'id': id, 'startid': a, 'endid': b},
      'geometry': {
        'type': 'MultiLineString',
        'coordinates': [
          [
            [0, 0],
            [1, 1],
          ],
        ],
      },
    };

String geojson(List<Map<String, Object?>> features) =>
    jsonEncode({'type': 'FeatureCollection', 'features': features});

void main() {
  group('RouteGraph.tryParse', () {
    test('노드 좌표를 읽고 양방향 엣지를 하나로 합친다', () {
      // 실제 파일 모양: 1-2 가 1001(1→2)·1002(2→1) 두 번 들어 있다.
      final graph = RouteGraph.tryParse(geojson([
        node(1, 45.05, -0.7),
        node(2, 44.16, -0.72),
        node(3, 43.27, -0.75),
        edge(1001, 1, 2),
        edge(1002, 2, 1),
        edge(1003, 2, 3),
        edge(1004, 3, 2),
      ]))!;

      expect(graph.nodes, hasLength(3));
      expect(graph.nodes[1], const Offset(45.05, -0.7));
      expect(graph.edges, [const RouteEdge(1, 2), const RouteEdge(2, 3)]);
    });

    test('끝 역과 갈림길 역만 골라낸다', () {
      // 1-2-3 등뼈에 2-4 곁가지. 1·3·4 는 끝, 2 는 갈림길, 중간 역은 없다.
      final graph = RouteGraph.tryParse(geojson([
        node(1, 0, 0),
        node(2, 1, 0),
        node(3, 2, 0),
        node(4, 1, -1),
        node(5, 3, 0),
        edge(1, 1, 2),
        edge(2, 2, 3),
        edge(3, 2, 4),
        edge(4, 3, 5),
      ]))!;

      // 3 은 연결이 둘(2, 5)이라 중간 역이다.
      expect(graph.keyNodeIds, {1, 2, 4, 5});
    });

    test('좌표가 숫자가 아닌 노드와 그 노드에 걸린 엣지는 버린다', () {
      // 2026-09-16 smooth_corners 사고에서 실제로 NaN 이 파일에 들어갔다.
      // NaN 은 JSON 표준이 아니라 파서가 통째로 거부한다(아래 '깨진 파일' 시험).
      // 파이썬이 null 로 써 보내는 경우가 그다음 위험이라 여기서 막는다.
      final graph = RouteGraph.tryParse(geojson([
        node(1, 0, 0),
        node(2, 1, 0),
        {
          'type': 'Feature',
          'properties': {'id': 3, 'frame': 'map'},
          'geometry': {
            'type': 'Point',
            'coordinates': [null, 1.0],
          },
        },
        edge(1, 1, 2),
        edge(2, 2, 3),
      ]))!;

      expect(graph.nodes.containsKey(3), isFalse);
      expect(graph.edges, [const RouteEdge(1, 2)]);
    });

    test('깨진 파일은 null 이고 예외를 던지지 않는다', () {
      expect(RouteGraph.tryParse('not json'), isNull);
      // NaN 이 든 파일(2026-09-16 사고 모양)은 JSON 이 아니라 통째로 거부된다.
      expect(
        RouteGraph.tryParse('{"features":[{"type":"Feature","properties":{"id":1},'
            '"geometry":{"type":"Point","coordinates":[NaN,1.0]}}]}'),
        isNull,
      );
      expect(RouteGraph.tryParse('{"type":"FeatureCollection"}'), isNull);
      expect(RouteGraph.tryParse('[]'), isNull);
      expect(RouteGraph.tryParse(geojson([])), isNull);
      // 엣지만 있고 노드가 없어도 null.
      expect(RouteGraph.tryParse(geojson([edge(1, 1, 2)])), isNull);
    });

    test('노드가 없는 엣지는 버리고 나머지는 살린다', () {
      final graph = RouteGraph.tryParse(geojson([
        node(1, 0, 0),
        node(2, 1, 0),
        edge(1, 1, 2),
        edge(2, 2, 99),
      ]))!;

      expect(graph.edges, [const RouteEdge(1, 2)]);
    });
  });
}
