import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

/// 목적지 이 거리 안에서는 로봇이 레일을 내려 직접 들어갑니다(BT
const double kRailHandoffMeters = 2.0;

/// 레일 한 장. 노드 좌표는 ROS map 좌표(m)입니다.
class RouteGraph {
  const RouteGraph({required this.nodes, required this.edges});

  /// 노드 id → 좌표.
  final Map<int, Offset> nodes;

  /// 무방향 엣지. 파일에는 같은 선이 양방향으로 두 번 들어 있어(1→2, 2→1)
  final List<RouteEdge> edges;

  bool get isEmpty => nodes.isEmpty;

  /// 끝 역(연결 1개)과 갈림길 역(연결 3개 이상). 평소 표시에서는 이 역들만
  Set<int> get keyNodeIds {
    final degree = <int, int>{};
    for (final edge in edges) {
      degree[edge.a] = (degree[edge.a] ?? 0) + 1;
      degree[edge.b] = (degree[edge.b] ?? 0) + 1;
    }
    return {
      for (final id in nodes.keys)
        if ((degree[id] ?? 0) == 1 || (degree[id] ?? 0) >= 3) id,
    };
  }

  /// ROS 좌표 (x, y) 에서 레일까지 가장 짧은 거리(m). 선 위 아무 곳까지를
  double? distanceTo(double x, double y) {
    if (nodes.isEmpty) {
      return null;
    }
    final p = Offset(x, y);
    var best = double.infinity;
    for (final node in nodes.values) {
      best = math.min(best, (node - p).distance);
    }
    for (final edge in edges) {
      final a = nodes[edge.a];
      final b = nodes[edge.b];
      if (a == null || b == null) {
        continue;
      }
      best = math.min(best, distanceToSegment(p, a, b));
    }
    return best;
  }

  /// GeoJSON 문자열을 읽습니다. 형식이 어긋나면 null 을 돌려주고 예외를 던지지
  static RouteGraph? tryParse(String text) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, Object?>) {
      return null;
    }
    final features = decoded['features'];
    if (features is! List) {
      return null;
    }

    final nodes = <int, Offset>{};
    final seen = <String>{};
    final edges = <RouteEdge>[];
    for (final feature in features.whereType<Map<String, Object?>>()) {
      final properties = feature['properties'];
      final geometry = feature['geometry'];
      if (properties is! Map<String, Object?> ||
          geometry is! Map<String, Object?>) {
        continue;
      }
      if (geometry['type'] == 'Point') {
        final id = _int(properties['id']);
        final point = _point(geometry['coordinates']);
        if (id != null && point != null) {
          nodes[id] = point;
        }
        continue;
      }
      final a = _int(properties['startid']);
      final b = _int(properties['endid']);
      if (a == null || b == null || a == b) {
        continue;
      }
      final low = a < b ? a : b;
      final high = a < b ? b : a;
      if (seen.add('$low-$high')) {
        edges.add(RouteEdge(low, high));
      }
    }
    final usable = edges
        .where((e) => nodes.containsKey(e.a) && nodes.containsKey(e.b))
        .toList(growable: false);
    if (nodes.isEmpty) {
      return null;
    }
    return RouteGraph(nodes: Map.unmodifiable(nodes), edges: usable);
  }

  static int? _int(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return null;
  }

  /// [x, y] 배열. NaN 이 섞여 오면(2026-09-16 smooth_corners 사고) 그 노드는
  static Offset? _point(Object? value) {
    if (value is! List || value.length < 2) {
      return null;
    }
    final x = value[0];
    final y = value[1];
    if (x is! num || y is! num) {
      return null;
    }
    final dx = x.toDouble();
    final dy = y.toDouble();
    if (!dx.isFinite || !dy.isFinite) {
      return null;
    }
    return Offset(dx, dy);
  }
}

/// 두 노드를 잇는 선. a < b 로 정리해 둡니다.
class RouteEdge {
  const RouteEdge(this.a, this.b);

  final int a;
  final int b;

  @override
  bool operator ==(Object other) =>
      other is RouteEdge && other.a == a && other.b == b;

  @override
  int get hashCode => Object.hash(a, b);

  @override
  String toString() => 'RouteEdge($a-$b)';
}

/// 점 [p] 에서 선분 [a]–[b] 까지 가장 짧은 거리. 길이 0 인 선분이면 [a] 까지 거리입니다.
double distanceToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (len2 == 0) {
    return (p - a).distance;
  }
  final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
  return (a + ab * t - p).distance;
}
