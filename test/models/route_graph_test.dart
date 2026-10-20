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

      expect(graph.keyNodeIds, {1, 2, 4, 5});
    });

    test('좌표가 숫자가 아닌 노드와 그 노드에 걸린 엣지는 버린다', () {
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
      expect(
        RouteGraph.tryParse(
            '{"features":[{"type":"Feature","properties":{"id":1},'
            '"geometry":{"type":"Point","coordinates":[NaN,1.0]}}]}'),
        isNull,
      );
      expect(RouteGraph.tryParse('{"type":"FeatureCollection"}'), isNull);
      expect(RouteGraph.tryParse('[]'), isNull);
      expect(RouteGraph.tryParse(geojson([])), isNull);
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

  group('distanceTo', () {
    const graph = RouteGraph(
      nodes: {1: Offset(0, 0), 2: Offset(4, 0), 3: Offset(9, 9)},
      edges: [RouteEdge(1, 2), RouteEdge(3, 3)],
    );

    test('선 한가운데 옆은 선까지 거리', () {
      expect(graph.distanceTo(2, 1.5), closeTo(1.5, 1e-9));
    });

    test('선 끝 너머는 끝점까지 거리', () {
      expect(graph.distanceTo(7, 4), closeTo(5, 1e-9));
    });

    test('길이 0 인 선은 그 노드까지 거리', () {
      expect(graph.distanceTo(9, 12), closeTo(3, 1e-9));
    });

    test('노드가 없으면 null', () {
      expect(const RouteGraph(nodes: {}, edges: []).distanceTo(0, 0), isNull);
    });
  });
}
