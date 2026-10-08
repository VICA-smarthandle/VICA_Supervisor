// 이 파일은 젯슨의 지도 HTTP 서버에서 레일 파일을 받아 옵니다.
//
// 지도 그림(<지도>.png)을 받는 서버(map_http_server.py, 8000번)가 같은 폴더의
// <지도>_route.geojson 도 그대로 내줍니다. 파일이 없는 지도는 404 가 오고, 그건
// 오류가 아니라 "이 지도에는 레일이 없다"는 뜻이라 조용히 null 을 돌려줍니다
// (2026-09-30 사용자 결정).
//
// 실제 HTTP 호출은 [fetch] 로 바꿔 끼울 수 있어 시험에서는 네트워크 없이 문자열을
// 바로 넣습니다.
import 'package:http/http.dart' as http;

import '../models/route_graph.dart';

/// URL 하나를 받아 본문 문자열을 돌려줍니다. 없거나 실패하면 null.
typedef RouteGraphFetch = Future<String?> Function(Uri uri);

class RouteGraphLoader {
  const RouteGraphLoader({RouteGraphFetch? fetch})
      : _fetch = fetch ?? _httpFetch;

  final RouteGraphFetch _fetch;

  /// 레일 파일 주소. 젯슨 launch 가 지도 이름(stem)에 `_route.geojson` 을 붙여
  /// 찾는 것과 같은 규칙입니다(nav2_map_test.launch.py).
  static Uri uriFor(String baseUrl, String mapId) {
    final base = baseUrl.replaceAll(RegExp(r'/$'), '');
    return Uri.parse('$base/maps/${mapId}_route.geojson');
  }

  /// 파일을 받아 읽습니다. 없거나 깨졌으면 null — 지도 화면은 그 지도에 레일을
  /// 그리지 않을 뿐 아무것도 알리지 않습니다.
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
    // 옛 레일이 다시 보이지 않게 하는 일은 지도 서버가 맡습니다(Cache-Control:
    // no-cache, 2026-10-08). 브라우저는 받을 때마다 바뀌었는지만 묻고, 그대로면
    // 서버가 본문 없이 304 로 답해 파일을 다시 받지 않습니다.
    final response = await http.get(uri).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      return null;
    }
    return response.body;
  }
}
