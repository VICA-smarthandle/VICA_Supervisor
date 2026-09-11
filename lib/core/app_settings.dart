import 'package:flutter/foundation.dart';

@immutable
class AppSettings {
  const AppSettings({
    this.rosBridgeUrl = 'ws://127.0.0.1:9090',
    this.mapHttpBaseUrl = 'http://127.0.0.1:8000',
    this.mapListRequestTopic = '/map_list_request',
    this.mapListTopic = '/map_list',
    this.locationListRequestTopic = '/location_list_request',
    this.locationListTopic = '/location_list',
    this.saveLocationTopic = '/save_location',
    this.deleteLocationRequestTopic = '/delete_location_request',
    this.missionRequestService = '/vica/mission/request_destination',
    this.missionCancelService = '/vica/mission/cancel_destination',
    this.missionPauseService = '/vica/mission/pause_navigation',
    this.missionResumeService = '/vica/mission/resume_navigation',
    this.robotStatusTopic = '/robot_status',
    this.emergencyActivateService = '/app_estop_activate',
    this.emergencyResetService = '/app_estop_reset',
    this.emergencyStateTopic = '/app_estop_state',
    this.robotHealthTopic = '/robot/health',
    this.robotEventsTopic = '/robot/events',
    this.robotHealthTimeoutSeconds = 5,
    this.emergencyServiceTimeoutSeconds = 8,
    this.maxLogs = 200,
    this.maxReconnectAttempts = 5,
    this.autoRequestMapList = true,
    this.autoRequestLocationList = true,
    this.xOffset = 0,
    this.yOffset = 0,
    this.yawOffset = 0,
    this.savedYawOffsetDegrees = 0,
    this.mapScale = 1,
    this.flipMapY = true,
  });

  final String rosBridgeUrl;
  final String mapHttpBaseUrl;
  final String mapListRequestTopic;
  final String mapListTopic;
  final String locationListRequestTopic;
  final String locationListTopic;
  final String saveLocationTopic;
  final String deleteLocationRequestTopic;
  final String missionRequestService;
  final String missionCancelService;
  final String missionPauseService;
  final String missionResumeService;
  final String robotStatusTopic;
  final String emergencyActivateService;
  final String emergencyResetService;
  final String emergencyStateTopic;
  final String robotHealthTopic;
  final String robotEventsTopic;
  final int robotHealthTimeoutSeconds;
  final int emergencyServiceTimeoutSeconds;
  final int maxLogs;
  final int maxReconnectAttempts;
  final bool autoRequestMapList;
  final bool autoRequestLocationList;
  final double xOffset;
  final double yOffset;
  final double yawOffset;
  final double savedYawOffsetDegrees;
  final double mapScale;
  final bool flipMapY;

  AppSettings copyWith({
    String? rosBridgeUrl,
    String? mapHttpBaseUrl,
    String? mapListRequestTopic,
    String? mapListTopic,
    String? locationListRequestTopic,
    String? locationListTopic,
    String? saveLocationTopic,
    String? deleteLocationRequestTopic,
    String? missionRequestService,
    String? missionCancelService,
    String? missionPauseService,
    String? missionResumeService,
    String? robotStatusTopic,
    String? emergencyActivateService,
    String? emergencyResetService,
    String? emergencyStateTopic,
    String? robotHealthTopic,
    String? robotEventsTopic,
    int? robotHealthTimeoutSeconds,
    int? emergencyServiceTimeoutSeconds,
    int? maxLogs,
    int? maxReconnectAttempts,
    bool? autoRequestMapList,
    bool? autoRequestLocationList,
    double? xOffset,
    double? yOffset,
    double? yawOffset,
    double? savedYawOffsetDegrees,
    double? mapScale,
    bool? flipMapY,
  }) {
    return AppSettings(
      rosBridgeUrl: rosBridgeUrl ?? this.rosBridgeUrl,
      mapHttpBaseUrl: mapHttpBaseUrl ?? this.mapHttpBaseUrl,
      mapListRequestTopic: mapListRequestTopic ?? this.mapListRequestTopic,
      mapListTopic: mapListTopic ?? this.mapListTopic,
      locationListRequestTopic:
          locationListRequestTopic ?? this.locationListRequestTopic,
      locationListTopic: locationListTopic ?? this.locationListTopic,
      saveLocationTopic: saveLocationTopic ?? this.saveLocationTopic,
      deleteLocationRequestTopic:
          deleteLocationRequestTopic ?? this.deleteLocationRequestTopic,
      missionRequestService:
          missionRequestService ?? this.missionRequestService,
      missionCancelService: missionCancelService ?? this.missionCancelService,
      missionPauseService: missionPauseService ?? this.missionPauseService,
      missionResumeService: missionResumeService ?? this.missionResumeService,
      robotStatusTopic: robotStatusTopic ?? this.robotStatusTopic,
      emergencyActivateService:
          emergencyActivateService ?? this.emergencyActivateService,
      emergencyResetService:
          emergencyResetService ?? this.emergencyResetService,
      emergencyStateTopic: emergencyStateTopic ?? this.emergencyStateTopic,
      robotHealthTopic: robotHealthTopic ?? this.robotHealthTopic,
      robotEventsTopic: robotEventsTopic ?? this.robotEventsTopic,
      robotHealthTimeoutSeconds:
          robotHealthTimeoutSeconds ?? this.robotHealthTimeoutSeconds,
      emergencyServiceTimeoutSeconds:
          emergencyServiceTimeoutSeconds ?? this.emergencyServiceTimeoutSeconds,
      maxLogs: maxLogs ?? this.maxLogs,
      maxReconnectAttempts: maxReconnectAttempts ?? this.maxReconnectAttempts,
      autoRequestMapList: autoRequestMapList ?? this.autoRequestMapList,
      autoRequestLocationList:
          autoRequestLocationList ?? this.autoRequestLocationList,
      xOffset: xOffset ?? this.xOffset,
      yOffset: yOffset ?? this.yOffset,
      yawOffset: yawOffset ?? this.yawOffset,
      savedYawOffsetDegrees:
          savedYawOffsetDegrees ?? this.savedYawOffsetDegrees,
      mapScale: mapScale ?? this.mapScale,
      flipMapY: flipMapY ?? this.flipMapY,
    );
  }

  Map<String, Object> toJson() {
    return {
      'rosBridgeUrl': rosBridgeUrl,
      'mapHttpBaseUrl': mapHttpBaseUrl,
      'mapListRequestTopic': mapListRequestTopic,
      'mapListTopic': mapListTopic,
      'locationListRequestTopic': locationListRequestTopic,
      'locationListTopic': locationListTopic,
      'saveLocationTopic': saveLocationTopic,
      'deleteLocationRequestTopic': deleteLocationRequestTopic,
      'missionRequestService': missionRequestService,
      'missionCancelService': missionCancelService,
      'missionPauseService': missionPauseService,
      'missionResumeService': missionResumeService,
      'robotStatusTopic': robotStatusTopic,
      'emergencyActivateService': emergencyActivateService,
      'emergencyResetService': emergencyResetService,
      'emergencyStateTopic': emergencyStateTopic,
      'robotHealthTopic': robotHealthTopic,
      'robotEventsTopic': robotEventsTopic,
      'robotHealthTimeoutSeconds': robotHealthTimeoutSeconds,
      'emergencyServiceTimeoutSeconds': emergencyServiceTimeoutSeconds,
      'maxLogs': maxLogs,
      'maxReconnectAttempts': maxReconnectAttempts,
      'autoRequestMapList': autoRequestMapList,
      'autoRequestLocationList': autoRequestLocationList,
      'xOffset': xOffset,
      'yOffset': yOffset,
      'yawOffset': yawOffset,
      'savedYawOffsetDegrees': savedYawOffsetDegrees,
      'mapScale': mapScale,
      'flipMapY': flipMapY,
    };
  }

  factory AppSettings.fromJson(Map<String, Object?> json) {
    const defaults = AppSettings();
    return AppSettings(
      rosBridgeUrl: json['rosBridgeUrl'] as String? ?? defaults.rosBridgeUrl,
      mapHttpBaseUrl:
          json['mapHttpBaseUrl'] as String? ?? defaults.mapHttpBaseUrl,
      mapListRequestTopic: json['mapListRequestTopic'] as String? ??
          defaults.mapListRequestTopic,
      mapListTopic: json['mapListTopic'] as String? ?? defaults.mapListTopic,
      locationListRequestTopic: json['locationListRequestTopic'] as String? ??
          defaults.locationListRequestTopic,
      locationListTopic:
          json['locationListTopic'] as String? ?? defaults.locationListTopic,
      saveLocationTopic:
          json['saveLocationTopic'] as String? ?? defaults.saveLocationTopic,
      deleteLocationRequestTopic:
          json['deleteLocationRequestTopic'] as String? ??
              defaults.deleteLocationRequestTopic,
      missionRequestService: json['missionRequestService'] as String? ??
          defaults.missionRequestService,
      missionCancelService: json['missionCancelService'] as String? ??
          defaults.missionCancelService,
      missionPauseService: json['missionPauseService'] as String? ??
          defaults.missionPauseService,
      missionResumeService: json['missionResumeService'] as String? ??
          defaults.missionResumeService,
      robotStatusTopic:
          json['robotStatusTopic'] as String? ?? defaults.robotStatusTopic,
      emergencyActivateService: json['emergencyActivateService'] as String? ??
          defaults.emergencyActivateService,
      emergencyResetService: json['emergencyResetService'] as String? ??
          defaults.emergencyResetService,
      emergencyStateTopic: json['emergencyStateTopic'] as String? ??
          defaults.emergencyStateTopic,
      robotHealthTopic:
          json['robotHealthTopic'] as String? ?? defaults.robotHealthTopic,
      robotEventsTopic:
          json['robotEventsTopic'] as String? ?? defaults.robotEventsTopic,
      robotHealthTimeoutSeconds:
          (json['robotHealthTimeoutSeconds'] as num?)?.toInt() ??
              defaults.robotHealthTimeoutSeconds,
      emergencyServiceTimeoutSeconds:
          (json['emergencyServiceTimeoutSeconds'] as num?)?.toInt() ??
              defaults.emergencyServiceTimeoutSeconds,
      maxLogs: json['maxLogs'] as int? ?? defaults.maxLogs,
      maxReconnectAttempts:
          json['maxReconnectAttempts'] as int? ?? defaults.maxReconnectAttempts,
      autoRequestMapList:
          json['autoRequestMapList'] as bool? ?? defaults.autoRequestMapList,
      autoRequestLocationList: json['autoRequestLocationList'] as bool? ??
          defaults.autoRequestLocationList,
      xOffset: (json['xOffset'] as num?)?.toDouble() ?? defaults.xOffset,
      yOffset: (json['yOffset'] as num?)?.toDouble() ?? defaults.yOffset,
      yawOffset: (json['yawOffset'] as num?)?.toDouble() ?? defaults.yawOffset,
      savedYawOffsetDegrees:
          (json['savedYawOffsetDegrees'] as num?)?.toDouble() ??
              defaults.savedYawOffsetDegrees,
      mapScale: (json['mapScale'] as num?)?.toDouble() ?? defaults.mapScale,
      flipMapY: json['flipMapY'] as bool? ?? defaults.flipMapY,
    );
  }
}
