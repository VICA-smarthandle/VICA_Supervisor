// 이 파일은 로봇이 따라 달리는 레일(Nav2 route server 의 route graph)을 표현합니다.
//
// 지하철 노선도에 빗대면 역이 노드, 역을 잇는 선로가 엣지입니다. 파일은 젯슨의
// maps/<지도>_route.geojson 이고, 형식은 nav2_route 가 읽는 GeoJSON 그대로입니다
// (Point 피처 = 노드, MultiLineString 피처 = 엣지, properties.startid/endid).
//
// A단계(2026-09-30)는 **표시만** 합니다. 앱은 이 파일을 지도 그림과 같은 HTTP
// 서버에서 받아 지도 위에 겹쳐 그릴 뿐, 고치거나 젯슨에 보내지 않습니다.
import 'dart:convert';
import 'dart:ui';

/// 레일 한 장. 노드 좌표는 ROS map 좌표(m)입니다.
class RouteGraph {
  const RouteGraph({required this.nodes, required this.edges});

  /// 노드 id → 좌표.
  final Map<int, Offset> nodes;

  /// 무방향 엣지. 파일에는 같은 선이 양방향으로 두 번 들어 있어(1→2, 2→1)
  /// 여기서는 하나로 합칩니다. 그리는 데는 방향이 필요 없습니다.
  final List<RouteEdge> edges;

  bool get isEmpty => nodes.isEmpty;

  /// 끝 역(연결 1개)과 갈림길 역(연결 3개 이상). 평소 표시에서는 이 역들만
  /// 점을 찍습니다 — 중간 역은 1 m 간격이라 전부 찍으면 축소 화면에서 선이
  /// 구슬 목걸이처럼 보입니다(2026-09-30 사용자 결정).
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

  /// GeoJSON 문자열을 읽습니다. 형식이 어긋나면 null 을 돌려주고 예외를 던지지
  /// 않습니다 — 레일은 있어도 되고 없어도 되는 겹층이라, 파일 하나가 깨졌다고
  /// 지도 화면이 죽으면 안 됩니다.
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
    // 노드가 없는 엣지는 그릴 수 없으니 버립니다.
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
  /// 버립니다 — NaN 좌표는 화면 어디에도 찍을 수 없습니다.
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
