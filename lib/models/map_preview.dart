import 'vica_map.dart';

class MapPreview {
  const MapPreview({
    required this.imageUrl,
    required this.seq,
    required this.width,
    required this.height,
    required this.resolution,
    required this.originX,
    required this.originY,
    required this.bytes,
    this.robotX,
    this.robotY,
    this.robotYaw,
    this.tiltDeg,
  });

  final String imageUrl;

  /// 갱신 순번. 앱이 URL 에 붙여 캐시를 피합니다. 같은 URL 이면 Flutter 가 예전
  final int seq;

  final int width;
  final int height;
  final double resolution;
  final double originX;
  final double originY;
  final int bytes;

  /// 지도 위 로봇 자세(ROS map 좌표, yaw 는 도 단위·반시계 양수).
  final double? robotX;
  final double? robotY;
  final double? robotYaw;

  /// 지금 그리는 지도의 기울기(도, 반시계 양수). 저장 팝업의 '지금 기울기' 줄이
  final double? tiltDeg;

  bool get hasRobotPose => robotX != null && robotY != null && robotYaw != null;

  /// MapCanvas 가 그대로 쓸 수 있게 저장된 지도와 같은 형태로 바꿉니다.
  VicaMap toVicaMap() {
    return VicaMap(
      mapId: 'preview',
      mapName: '작성 중인 지도',
      imageUrl: '$imageUrl?t=$seq',
      resolution: resolution,
      originX: originX,
      originY: originY,
      width: width,
      height: height,
    );
  }

  factory MapPreview.fromJson(Map<String, Object?> json) {
    return MapPreview(
      imageUrl: json['image_url'] as String? ?? '',
      seq: (json['seq'] as num?)?.toInt() ?? 0,
      width: (json['width'] as num?)?.toInt() ?? 0,
      height: (json['height'] as num?)?.toInt() ?? 0,
      resolution: (json['resolution'] as num?)?.toDouble() ?? 0.05,
      originX: (json['origin_x'] as num?)?.toDouble() ?? 0,
      originY: (json['origin_y'] as num?)?.toDouble() ?? 0,
      bytes: (json['bytes'] as num?)?.toInt() ?? 0,
      robotX: (json['robot_x'] as num?)?.toDouble(),
      robotY: (json['robot_y'] as num?)?.toDouble(),
      robotYaw: (json['robot_yaw'] as num?)?.toDouble(),
      tiltDeg: (json['tilt_deg'] as num?)?.toDouble(),
    );
  }
}
