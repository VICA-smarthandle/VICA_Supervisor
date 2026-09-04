// 이 파일은 map_preview_node 가 보내는 지도 미리보기 정보를 표현합니다.
//
// 이미지 자체는 이 메시지에 없습니다. HTTP 로 따로 받습니다 — 격자를 rosbridge 로
// 그대로 보내면 한 장에 703 KB(JSON)인데, PNG 로 뜨면 4.6 KB 입니다(실측,
// vica_map_0630 25만 칸). 여기 담기는 것은 그 그림을 화면에 놓는 데 필요한
// 좌표 정보뿐이고, 지도가 자라면 크기와 원점이 함께 바뀌므로 매번 같이 옵니다.
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
    required this.receivedAt,
    this.robotX,
    this.robotY,
    this.robotYaw,
  });

  final String imageUrl;

  /// 갱신 순번. 앱이 URL 에 붙여 캐시를 피합니다. 같은 URL 이면 Flutter 가 예전
  /// 그림을 그대로 씁니다.
  final int seq;

  final int width;
  final int height;
  final double resolution;
  final double originX;
  final double originY;
  final int bytes;
  final DateTime receivedAt;

  /// 지도 위 로봇 자세(ROS map 좌표, yaw 는 도 단위·반시계 양수).
  ///
  /// map_preview_node 가 Cartographer 의 /tracked_pose 를 받아 두었다가 같은
  /// 메시지에 동봉합니다(2026-09-04). 매핑 중에는 AMCL 이 없어 /robot_status 의
  /// 위치가 /odom 좌표로 대체되고 map_id 도 비기 때문에, 그쪽으로는 미리보기 위에
  /// 로봇을 그릴 수 없습니다. 아직 자세를 못 받았거나 5초 넘게 끊겼으면 null 이고,
  /// 그때 화면은 화살표 대신 "로봇 위치 없음"을 적습니다.
  final double? robotX;
  final double? robotY;
  final double? robotYaw;

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
      receivedAt: DateTime.now(),
      robotX: (json['robot_x'] as num?)?.toDouble(),
      robotY: (json['robot_y'] as num?)?.toDouble(),
      robotYaw: (json['robot_yaw'] as num?)?.toDouble(),
    );
  }
}
