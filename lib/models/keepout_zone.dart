// 이 파일은 지도 위에 그린 금지구역 사각형 하나를 표현합니다.
//
// 좌표는 ROS map 좌표(m)이고 축에 평행한 사각형입니다. 회전은 없습니다 —
// Nav2 Costmap2D 가 회전한 격자를 지원하지 않아서, 회전을 허용하면 앱에 보이는
// 모양과 로봇이 지키는 모양이 달라집니다.
import 'dart:ui';

class KeepoutZone {
  const KeepoutZone({
    required this.zoneId,
    required this.name,
    required this.xMin,
    required this.yMin,
    required this.xMax,
    required this.yMax,
  });

  final String zoneId;
  final String name;
  final double xMin;
  final double yMin;
  final double xMax;
  final double yMax;

  double get width => xMax - xMin;
  double get height => yMax - yMin;

  /// 두 점으로 사각형을 만듭니다. 어느 방향으로 끌었든 min/max 로 정리합니다.
  ///
  /// 관리자가 오른쪽 아래에서 왼쪽 위로 끌면 min 이 max 보다 커집니다. 그대로
  /// 두면 ROS 쪽에서 거절당하는데, 화면에는 멀쩡한 사각형이 보이므로 왜 거절
  /// 당했는지 알 수 없습니다. 그래서 만들 때 바로잡습니다.
  factory KeepoutZone.fromDrag({
    required String zoneId,
    required Offset start,
    required Offset end,
    String name = '',
  }) {
    return KeepoutZone(
      zoneId: zoneId,
      name: name,
      xMin: start.dx <= end.dx ? start.dx : end.dx,
      yMin: start.dy <= end.dy ? start.dy : end.dy,
      xMax: start.dx <= end.dx ? end.dx : start.dx,
      yMax: start.dy <= end.dy ? end.dy : start.dy,
    );
  }

  factory KeepoutZone.fromJson(Map<String, Object?> json) {
    return KeepoutZone(
      zoneId: json['zone_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      xMin: (json['x_min'] as num?)?.toDouble() ?? 0,
      yMin: (json['y_min'] as num?)?.toDouble() ?? 0,
      xMax: (json['x_max'] as num?)?.toDouble() ?? 0,
      yMax: (json['y_max'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, Object> toJson() {
    return {
      'zone_id': zoneId,
      'name': name,
      'x_min': xMin,
      'y_min': yMin,
      'x_max': xMax,
      'y_max': yMax,
    };
  }

  KeepoutZone copyWith({String? zoneId, String? name}) {
    return KeepoutZone(
      zoneId: zoneId ?? this.zoneId,
      name: name ?? this.name,
      xMin: xMin,
      yMin: yMin,
      xMax: xMax,
      yMax: yMax,
    );
  }

  /// 화면에서 이 점이 사각형 안에 있는지. 사각형을 눌러 고를 때 씁니다.
  bool contains(Offset ros) {
    return ros.dx >= xMin && ros.dx <= xMax && ros.dy >= yMin && ros.dy <= yMax;
  }

  @override
  bool operator ==(Object other) {
    return other is KeepoutZone &&
        other.zoneId == zoneId &&
        other.name == name &&
        other.xMin == xMin &&
        other.yMin == yMin &&
        other.xMax == xMax &&
        other.yMax == yMax;
  }

  @override
  int get hashCode => Object.hash(zoneId, name, xMin, yMin, xMax, yMax);
}
