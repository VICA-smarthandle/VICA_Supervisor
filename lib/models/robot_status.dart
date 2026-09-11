class RobotStatus {
  const RobotStatus({
    required this.robotId,
    required this.robotName,
    required this.status,
    required this.x,
    required this.y,
    required this.yaw,
    required this.currentLocation,
    required this.currentGoal,
    required this.errorReason,
    required this.waitingReason,
    required this.mapId,
    required this.timestamp,
  });

  final String robotId;
  final String robotName;
  final String status;
  final double x;
  final double y;
  final double yaw;
  final String currentLocation;
  final String currentGoal;
  final String errorReason;
  final String waitingReason;
  final String mapId;
  final DateTime timestamp;

  bool get hasError => errorReason.trim().isNotEmpty;

  factory RobotStatus.fromJson(Map<String, Object?> json) {
    return RobotStatus(
      robotId: json['robot_id'] as String? ?? 'vica_01',
      robotName: json['robot_name'] as String? ?? 'VICA-01',
      status: json['status'] as String? ?? 'unknown',
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
      yaw: (json['yaw'] as num?)?.toDouble() ?? 0,
      currentLocation: json['current_location'] as String? ?? '',
      currentGoal: json['current_goal'] as String? ?? '',
      errorReason: json['error_reason'] as String? ?? '',
      waitingReason: json['waiting_reason'] as String? ?? '',
      mapId: json['map_id'] as String? ?? '',
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, Object> toJson() {
    return {
      'robot_id': robotId,
      'robot_name': robotName,
      'status': status,
      'x': x,
      'y': y,
      'yaw': yaw,
      'current_location': currentLocation,
      'current_goal': currentGoal,
      'error_reason': errorReason,
      'waiting_reason': waitingReason,
      'map_id': mapId,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}
