// 이 파일은 앱에서 레일 선을 이을 때 벽을 가로지르는지 보는 '벽 지도'입니다.
//
// 사용자 결정(2026-09-30): 선 잇기가 벽을 가로지르면 **화면에 따로 표시하지 않고**
// 선이 이어지지 않습니다. 젯슨(route_graph_node)도 저장할 때 한 번 더 막지만, 앱에서
// 먼저 막아야 관리자가 벽을 뚫은 선을 그려 놓고 저장에서야 거부당하지 않습니다.
//
// 벽 = 지도 그림의 검은 칸(점유). 회색(미탐색)은 벽이 아닙니다 — 젯슨
// route_graph_build.OCCUPIED_MAX 와 같은 기준이어야 앱과 로봇이 같은 판정을 합니다.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:http/http.dart' as http;

import '../models/vica_map.dart';

/// 이 밝기(0~255) 이하면 벽. route_graph_build.OCCUPIED_MAX 와 같아야 합니다.
const int kWallMaxLuma = 50;

class MapWallMask {
  MapWallMask({
    required this.width,
    required this.height,
    required this.resolution,
    required this.originX,
    required this.originY,
    required this.wall,
  });

  final int width;
  final int height;
  final double resolution;
  final double originX;
  final double originY;

  /// 행 우선(위→아래), 1 = 벽.
  final Uint8List wall;

  bool isWallAt(double x, double y) {
    final col = ((x - originX) / resolution).round();
    final row = (height - 1 - (y - originY) / resolution).round();
    if (col < 0 || row < 0 || col >= width || row >= height) {
      return true; // 지도 밖은 갈 수 없는 곳
    }
    return wall[row * width + col] == 1;
  }

  /// a→b 선분이 벽 칸을 지나면 true. 5 cm(해상도) 간격으로 훑습니다.
  bool crossesWall(ui.Offset a, ui.Offset b) {
    final dist = (b - a).distance;
    final steps = (dist / resolution).ceil().clamp(1, 100000);
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final p = ui.Offset.lerp(a, b, t)!;
      if (isWallAt(p.dx, p.dy)) {
        return true;
      }
    }
    return false;
  }

  /// RGBA 픽셀(지도 그림을 푼 것)에서 벽 칸을 뽑습니다.
  static MapWallMask fromRgba(
      VicaMap map, int width, int height, Uint8List rgba) {
    final wall = Uint8List(width * height);
    for (var i = 0; i < width * height; i++) {
      final r = rgba[i * 4];
      final g = rgba[i * 4 + 1];
      final b = rgba[i * 4 + 2];
      final luma = (r * 299 + g * 587 + b * 114) ~/ 1000;
      wall[i] = luma <= kWallMaxLuma ? 1 : 0;
    }
    return MapWallMask(
      width: width,
      height: height,
      resolution: map.resolution,
      originX: map.originX,
      originY: map.originY,
      wall: wall,
    );
  }

  /// 지도 그림을 받아 벽 지도를 만듭니다. 실패하면 null — 그때 앱은 벽 검사를
  /// 건너뛰고 젯슨 검사(저장 때)에 맡깁니다.
  static Future<MapWallMask?> load(String imageUrl, VicaMap map) async {
    try {
      final response = await http
          .get(Uri.parse(imageUrl))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        return null;
      }
      final codec = await ui.instantiateImageCodec(response.bodyBytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) {
        return null;
      }
      return fromRgba(
          map, image.width, image.height, data.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }
}
