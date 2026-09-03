// 이 파일은 ROS2에서 받은 지도 메타데이터와 지도 이미지 URL 정보를 표현합니다.
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
    this.isCurrent = false,
  });

  final String mapId;
  final String mapName;
  final String imageUrl;
  final double resolution;
  final double originX;
  final double originY;
  final int width;
  final int height;

  /// 젯슨이 지금 이 지도로 달리는가(maps/CURRENT_MAP). 앱을 켤 때 이 지도를
  /// 먼저 고르고, 드롭다운에 '(현재)'를 붙인다(2026-09-03). 옛 노드는 이 값을
  /// 안 실어 보내며 그때는 전부 false 다.
  final bool isCurrent;

  /// 드롭다운 등에 보일 이름.
  String get displayName => isCurrent ? '$mapName (현재)' : mapName;

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
      isCurrent: json['is_current'] == true,
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
      'is_current': isCurrent,
    };
  }
}
