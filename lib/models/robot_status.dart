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
    this.dialogState = '',
    this.waitPlace = '',
    this.waitLeftSec = -1,
    this.lastDestination = '',
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

  /// 미션이 알린 지금 하는 일(2026-10-29). Mission Manager 의 RobotState.dialog_state 그대로
  final String dialogState;

  /// 지금 기다리는 곳의 입구 기준 쪽('입구 왼쪽' 등). 대기 장소 없는 대기·대기 아님은 빈 문자열.
  final String waitPlace;

  /// 대기 남은 초. 대기 중이 아니거나 시간 없이 기다리면 -1.
  final int waitLeftSec;

  /// 직전에 도착한 목적지 이름. 대기 중 상태 줄의 '어디에서'입니다.
  final String lastDestination;

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
      dialogState: json['dialog_state'] as String? ?? '',
      waitPlace: json['wait_place'] as String? ?? '',
      waitLeftSec: (json['wait_left_sec'] as num?)?.toInt() ?? -1,
      lastDestination: json['last_destination'] as String? ?? '',
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
      'dialog_state': dialogState,
      'wait_place': waitPlace,
      'wait_left_sec': waitLeftSec,
      'last_destination': lastDestination,
    };
  }
}
