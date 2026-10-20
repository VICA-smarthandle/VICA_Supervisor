import 'package:http/http.dart' as http;

import '../models/route_graph.dart';

/// URL 하나를 받아 본문 문자열을 돌려줍니다. 없거나 실패하면 null.
typedef RouteGraphFetch = Future<String?> Function(Uri uri);

class RouteGraphLoader {
  const RouteGraphLoader({RouteGraphFetch? fetch})
      : _fetch = fetch ?? _httpFetch;

  final RouteGraphFetch _fetch;

  /// 레일 파일 주소. 젯슨 launch 가 지도 이름(stem)에 `_route.geojson` 을 붙여
  static Uri uriFor(String baseUrl, String mapId) {
    final base = baseUrl.replaceAll(RegExp(r'/$'), '');
    return Uri.parse('$base/maps/${mapId}_route.geojson');
  }

  /// 파일을 받아 읽습니다. 없거나 깨졌으면 null — 지도 화면은 그 지도에 레일을
  Future<RouteGraph?> load(String baseUrl, String mapId) async {
    if (mapId.isEmpty) {
      return null;
    }
    final String? text;
    try {
      text = await _fetch(uriFor(baseUrl, mapId));
    } catch (_) {
      return null;
    }
    if (text == null || text.isEmpty) {
      return null;
    }
    return RouteGraph.tryParse(text);
  }

  static Future<String?> _httpFetch(Uri uri) async {
    final response = await http.get(uri).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      return null;
    }
    return response.body;
  }
}
