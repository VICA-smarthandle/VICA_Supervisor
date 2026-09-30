// 이 파일은 앱에서 레일(route graph)을 편집할 때 쓰는 모양들입니다(2026-09-30).
//
// 관리자는 **스케치**만 다룹니다 — 노드를 찍고 두 노드 사이를 선으로 잇는 것.
// 코너 호·1 m 마다 노드·양방향·갈림길 벌점은 젯슨(route_graph_node)이 만듭니다.
// 규칙을 로봇 한 곳에만 두어야 앱 미리보기와 로봇이 달리는 모양이 어긋나지 않습니다
// (설계서 docs/superpowers/specs/2026-09-28-app-route-editor-design.md 2.2).
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'route_graph.dart';

/// 편집 도구. 확정(2026-09-30): 노드 추가 · 선 잇기 · 지우기. 옮기기는 길게 눌러 끌기.
enum RouteEditTool { addNode, connect, erase }

/// 관리자 스케치. 좌표는 ROS map 좌표(m), 선은 무방향입니다.
class RouteSketch {
  const RouteSketch({required this.nodes, required this.edges});

  static const empty = RouteSketch(nodes: {}, edges: []);

  final Map<int, Offset> nodes;
  final List<RouteEdge> edges;

  bool get isEmpty => nodes.isEmpty;

  int get _nextId => nodes.isEmpty ? 1 : nodes.keys.reduce(math.max) + 1;

  RouteSketch addNode(Offset ros) => RouteSketch(
        nodes: {...nodes, _nextId: ros},
        edges: edges,
      );

  /// 두 노드를 잇습니다. 같은 노드거나 이미 이어져 있으면 그대로입니다.
  RouteSketch connect(int a, int b) {
    if (a == b || !nodes.containsKey(a) || !nodes.containsKey(b)) {
      return this;
    }
    final edge = RouteEdge(math.min(a, b), math.max(a, b));
    if (edges.contains(edge)) {
      return this;
    }
    return RouteSketch(nodes: nodes, edges: [...edges, edge]);
  }

  RouteSketch moveNode(int id, Offset ros) {
    if (!nodes.containsKey(id)) {
      return this;
    }
    return RouteSketch(nodes: {...nodes, id: ros}, edges: edges);
  }

  /// 노드와 그 노드에 붙은 선을 모두 지웁니다.
  RouteSketch removeNode(int id) => RouteSketch(
        nodes: Map.of(nodes)..remove(id),
        edges: edges.where((e) => e.a != id && e.b != id).toList(),
      );

  RouteSketch removeEdge(RouteEdge edge) => RouteSketch(
        nodes: nodes,
        edges: edges.where((e) => e != edge).toList(),
      );

  /// ros 에서 [radius] m 안의 가장 가까운 노드. 없으면 null.
  int? nodeNear(Offset ros, double radius) {
    int? best;
    var bestDist = radius;
    nodes.forEach((id, p) {
      final d = (p - ros).distance;
      if (d <= bestDist) {
        best = id;
        bestDist = d;
      }
    });
    return best;
  }

  /// ros 에서 [radius] m 안의 가장 가까운 선. 없으면 null.
  RouteEdge? edgeNear(Offset ros, double radius) {
    RouteEdge? best;
    var bestDist = radius;
    for (final e in edges) {
      final a = nodes[e.a];
      final b = nodes[e.b];
      if (a == null || b == null) {
        continue;
      }
      final d = distanceToSegment(ros, a, b);
      if (d <= bestDist) {
        best = e;
        bestDist = d;
      }
    }
    return best;
  }

  Map<String, Object?> toJson() => {
        'nodes': [
          for (final entry in nodes.entries)
            {'id': entry.key, 'x': entry.value.dx, 'y': entry.value.dy},
        ],
        'edges': [
          for (final e in edges) [e.a, e.b],
        ],
      };

  String encode() => jsonEncode(toJson());

  /// 로봇이 보낸 스케치 JSON. 깨졌으면 빈 스케치입니다.
  static RouteSketch decode(Object? raw) {
    Object? data = raw;
    if (raw is String) {
      if (raw.trim().isEmpty) {
        return empty;
      }
      try {
        data = jsonDecode(raw);
      } on FormatException {
        return empty;
      }
    }
    if (data is! Map) {
      return empty;
    }
    final nodes = <int, Offset>{};
    for (final item in (data['nodes'] as List? ?? const []).whereType<Map>()) {
      final id = item['id'];
      final x = item['x'];
      final y = item['y'];
      if (id is num && x is num && y is num) {
        nodes[id.toInt()] = Offset(x.toDouble(), y.toDouble());
      }
    }
    final edges = <RouteEdge>[];
    for (final item in (data['edges'] as List? ?? const []).whereType<List>()) {
      if (item.length < 2 || item[0] is! num || item[1] is! num) {
        continue;
      }
      final a = (item[0] as num).toInt();
      final b = (item[1] as num).toInt();
      if (a != b && nodes.containsKey(a) && nodes.containsKey(b)) {
        final e = RouteEdge(math.min(a, b), math.max(a, b));
        if (!edges.contains(e)) {
          edges.add(e);
        }
      }
    }
    return RouteSketch(nodes: nodes, edges: edges);
  }
}

double distanceToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (len2 == 0) {
    return (p - a).distance;
  }
  final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
  return (a + ab * t - p).distance;
}

/// 로봇 검사가 돌려준 문제 하나. 위치(x, y)는 ROS 좌표입니다.
class RouteIssue {
  const RouteIssue({
    required this.code,
    required this.x,
    required this.y,
    required this.message,
    this.value,
    this.name = '',
  });

  final String code;
  final double x;
  final double y;
  final String message;
  final num? value;
  final String name;

  static RouteIssue? fromJson(Map<String, Object?> json) {
    final x = json['x'];
    final y = json['y'];
    if (x is! num || y is! num) {
      return null;
    }
    return RouteIssue(
      code: json['code'] as String? ?? '',
      x: x.toDouble(),
      y: y.toDouble(),
      message: json['message'] as String? ?? '',
      value: json['value'] as num?,
      name: json['name'] as String? ?? '',
    );
  }
}

/// 장소 하나가 레일에서 얼마나 떨어졌는가.
class RoutePlace {
  const RoutePlace(
      {required this.name, required this.distance, required this.far});

  final String name;
  final double distance;
  final bool far;
}

class RouteSummary {
  const RouteSummary({
    this.nodeCount = 0,
    this.lengthM = 0,
    this.junctionCount = 0,
  });

  final int nodeCount;
  final double lengthM;
  final int junctionCount;
}

/// 검사 결과 묶음(checks_json).
class RouteChecks {
  const RouteChecks({
    this.errors = const [],
    this.warnings = const [],
    this.places = const [],
    this.summary = const RouteSummary(),
  });

  static const none = RouteChecks();

  final List<RouteIssue> errors;
  final List<RouteIssue> warnings;
  final List<RoutePlace> places;
  final RouteSummary summary;

  List<RouteIssue> get farPlaces =>
      warnings.where((w) => w.code == 'far_place').toList();

  static RouteChecks decode(Object? raw) {
    Object? data = raw;
    if (raw is String) {
      if (raw.trim().isEmpty) {
        return none;
      }
      try {
        data = jsonDecode(raw);
      } on FormatException {
        return none;
      }
    }
    if (data is! Map) {
      return none;
    }
    List<RouteIssue> issues(Object? list) => [
          for (final item in (list as List? ?? const []).whereType<Map>())
            if (RouteIssue.fromJson(item.cast<String, Object?>()) case final i?)
              i,
        ];
    final places = <RoutePlace>[
      for (final item in (data['places'] as List? ?? const []).whereType<Map>())
        RoutePlace(
          name: item['name'] as String? ?? '',
          distance: (item['distance'] as num? ?? 0).toDouble(),
          far: item['far'] == true,
        ),
    ];
    final s = data['summary'];
    final summary = s is Map
        ? RouteSummary(
            nodeCount: (s['node_count'] as num? ?? 0).toInt(),
            lengthM: (s['length_m'] as num? ?? 0).toDouble(),
            junctionCount: (s['junction_count'] as num? ?? 0).toInt(),
          )
        : const RouteSummary();
    return RouteChecks(
      errors: issues(data['errors']),
      warnings: issues(data['warnings']),
      places: places,
      summary: summary,
    );
  }
}

/// 로봇이 다듬은 모양(preview_json)을 지도에 그릴 수 있는 RouteGraph 로.
RouteGraph? decodeRoutePreview(Object? raw) {
  final sketch = RouteSketch.decode(raw);
  if (sketch.isEmpty) {
    return null;
  }
  return RouteGraph(nodes: sketch.nodes, edges: sketch.edges);
}
