class VicaMap {
  const VicaMap({
    required this.mapId,
    required this.mapName,
    required this.imageUrl,
    required this.resolution,
    required this.originX,
    required this.originY,
    required this.width,
    required this.height,
  });

  final String mapId;
  final String mapName;
  final String imageUrl;
  final double resolution;
  final double originX;
  final double originY;
  final int width;
  final int height;

  factory VicaMap.fromJson(Map<String, Object?> json) {
    return VicaMap(
      mapId: json['map_id'] as String? ?? '',
      mapName: json['map_name'] as String? ?? json['map_id'] as String? ?? '',
      imageUrl: json['image_url'] as String? ?? '',
      resolution: (json['resolution'] as num?)?.toDouble() ?? 0.05,
      originX: (json['origin_x'] as num?)?.toDouble() ?? 0,
      originY: (json['origin_y'] as num?)?.toDouble() ?? 0,
      width: (json['width'] as num?)?.toInt() ?? 1024,
      height: (json['height'] as num?)?.toInt() ?? 1024,
    );
  }

  Map<String, Object> toJson() {
    return {
      'map_id': mapId,
      'map_name': mapName,
      'image_url': imageUrl,
      'resolution': resolution,
      'origin_x': originX,
      'origin_y': originY,
      'width': width,
      'height': height,
    };
  }
}
