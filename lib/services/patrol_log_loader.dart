import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/patrol.dart';

/// URL 하나를 받아 본문 문자열을 돌려줍니다. 없거나 실패하면 null.
typedef PatrolFetch = Future<String?> Function(Uri uri);

/// URL 하나의 HTTP 상태 코드만 봅니다(본문 없이 HEAD). 닿지 못하면 null.
typedef PatrolProbe = Future<int?> Function(Uri uri);

/// 사진 넘기기의 기본 속도(초당 장수). 서버가 값을 안 주거나 이상한 값을 줄 때 씁니다.
const double kPatrolDefaultFps = 5;

/// mp4 가 없는 장면의 사진 묶음: 장마다의 주소와 넘길 속도.
class PatrolFrames {
  const PatrolFrames({required this.frames, this.fps = kPatrolDefaultFps});

  final List<Uri> frames;

  /// 초당 장수. 감지 노드가 실제로 잰 값이라 소수일 수 있습니다(예: 3.41). 이 값으로
  final double fps;
}

class PatrolLogLoader {
  const PatrolLogLoader({PatrolFetch? fetch, PatrolProbe? probe})
      : _fetch = fetch ?? _httpFetch,
        _probe = probe ?? _httpHead;

  final PatrolFetch _fetch;
  final PatrolProbe _probe;

  static String _root(String baseUrl) =>
      '${baseUrl.replaceAll(RegExp(r'/$'), '')}/patrol';

  static Uri eventsUri(String baseUrl) =>
      Uri.parse('${_root(baseUrl)}/events.json');

  static Uri clipUri(String baseUrl, String clipId) =>
      Uri.parse('${_root(baseUrl)}/clips/${Uri.encodeComponent(clipId)}.mp4');

  static Uri posterUri(String baseUrl, String clipId) =>
      Uri.parse('${_root(baseUrl)}/clips/${Uri.encodeComponent(clipId)}.jpg');

  static Uri framesUri(String baseUrl, String clipId) => Uri.parse(
      '${_root(baseUrl)}/clips/${Uri.encodeComponent(clipId)}/frames.json');

  static Uri frameUri(String baseUrl, String clipId, String name) =>
      Uri.parse('${_root(baseUrl)}/clips/${Uri.encodeComponent(clipId)}/frames/'
          '${Uri.encodeComponent(name)}');

  static Uri photoUri(String baseUrl, String name) =>
      Uri.parse('${_root(baseUrl)}/photos/${Uri.encodeComponent(name)}');

  /// 경비 기록 목록. 서버에 닿지 못했거나 모양이 다르면 null — 화면은 '없다'와
  Future<List<PatrolRecord>?> loadRecords(String baseUrl) async {
    final decoded = await _json(eventsUri(baseUrl));
    if (decoded is! List) {
      return null;
    }
    return [
      for (final item in decoded)
        if (PatrolRecord.fromJson(item) case final record?) record,
    ];
  }

  /// mp4 가 없는 장면의 사진 주소 목록과 넘길 속도(frames.json 의 fps). 없으면 null.
  Future<PatrolFrames?> loadFrames(String baseUrl, String clipId) async {
    final decoded = await _json(framesUri(baseUrl, clipId));
    if (decoded is! Map || decoded['frames'] is! List) {
      return null;
    }
    final frames = [
      for (final name in decoded['frames'] as List)
        if (name is String && name.isNotEmpty) frameUri(baseUrl, clipId, name),
    ];
    if (frames.isEmpty) {
      return null;
    }
    return PatrolFrames(frames: frames, fps: _fps(decoded['fps']));
  }

  /// mp4 가 로봇에 있는가. 있으면 true, 404 면 false, 닿지 못했거나 모르는 답이면 null.
  Future<bool?> clipExists(String baseUrl, String clipId) async {
    final int? status;
    try {
      status = await _probe(clipUri(baseUrl, clipId));
    } catch (_) {
      return null;
    }
    if (status == 200 || status == 206) {
      return true;
    }
    return status == 404 ? false : null;
  }

  /// 서버(map_http_server.clip_fps)와 같은 범위만 받습니다. 그 밖은 기본 속도.
  static double _fps(Object? raw) {
    if (raw is num && raw.isFinite && raw >= 0.5 && raw <= 30) {
      return raw.toDouble();
    }
    return kPatrolDefaultFps;
  }

  Future<Object?> _json(Uri uri) async {
    final String? text;
    try {
      text = await _fetch(uri);
    } catch (_) {
      return null;
    }
    if (text == null || text.isEmpty) {
      return null;
    }
    try {
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }

  static Future<int?> _httpHead(Uri uri) async {
    final response = await http.head(uri).timeout(const Duration(seconds: 8));
    return response.statusCode;
  }

  static Future<String?> _httpFetch(Uri uri) async {
    final response = await http.get(uri).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      return null;
    }
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }
}
