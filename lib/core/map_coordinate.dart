import 'dart:ui';

import '../models/vica_map.dart';

class MapCoordinate {
  const MapCoordinate._();

  static Offset rosToPixel({
    required VicaMap map,
    required double x,
    required double y,
    required bool flipY,
    required double xOffset,
    required double yOffset,
    required double scale,
  }) {
    final correctedX = (x + xOffset) * scale;
    final correctedY = (y + yOffset) * scale;
    final pixelX = (correctedX - map.originX) / map.resolution;
    final rawPixelY = (correctedY - map.originY) / map.resolution;
    return Offset(pixelX, flipY ? map.height - rawPixelY : rawPixelY);
  }

  static Offset pixelToRos({
    required VicaMap map,
    required Offset pixel,
    required bool flipY,
    required double xOffset,
    required double yOffset,
    required double scale,
  }) {
    final rawY = flipY ? map.height - pixel.dy : pixel.dy;
    final x = (pixel.dx * map.resolution + map.originX) / scale - xOffset;
    final y = (rawY * map.resolution + map.originY) / scale - yOffset;
    return Offset(x, y);
  }
}
