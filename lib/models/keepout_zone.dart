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
