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
    this.missionDeliveryService = '/vica/mission/request_delivery',
    this.missionWaitSpotService = '/vica/mission/request_wait_spot',
    this.missionCancelService = '/vica/mission/cancel_destination',
    this.missionPauseService = '/vica/mission/pause_navigation',
    this.missionResumeService = '/vica/mission/resume_navigation',
    this.missionHelpAckService = '/vica/mission/help_ack',
    this.deleteMapService = '/delete_map',
    this.renameMapService = '/rename_map',
    this.mappingStatusTopic = '/vica/mapping_status',
    this.mapPreviewTopic = '/vica/map_preview',
    this.mappingStartService = '/vica/mapping/start',
    this.mappingStopService = '/vica/mapping/stop',
    this.mappingSaveService = '/vica/mapping/save',
    this.poseCheckService = '/vica/pose_check',
    this.poseCommitService = '/vica/pose_commit',
    this.homeGetService = '/vica/home/get',
    this.homeSaveService = '/vica/home/save',
    this.homeDeleteService = '/vica/home/delete',
    this.keepoutGetService = '/vica/keepout/get',
    this.keepoutSaveService = '/vica/keepout/save',
    this.keepoutStateTopic = '/vica/keepout/state',
    this.routeDraftService = '/vica/route/draft',
    this.routeSaveService = '/vica/route/save',
    this.routeGetService = '/vica/route/get',
    this.routeStateTopic = '/vica/route/state',
    this.routeSavedTopic = '/vica/route/saved',
    this.deliverySmsResultTopic = '/vica/delivery/sms_result',
    this.missionReturnHomeService = '/vica/mission/return_home',
    this.goalEventTopic = '/vica_goal_event',
    this.robotStatusTopic = '/robot_status',
    this.emergencyActivateService = '/app_estop_activate',
    this.emergencyResetService = '/app_estop_reset',
    this.emergencyStateTopic = '/app_estop_state',
    this.robotHealthTopic = '/robot/health',
    this.robotEventsTopic = '/robot/events',
    this.robotHealthTimeoutSeconds = 5,
    this.emergencyServiceTimeoutSeconds = 8,
    this.maxReconnectAttempts = 5,
    this.autoRequestMapList = true,
    this.autoRequestLocationList = true,
    this.xOffset = 0,
    this.yOffset = 0,
    this.yawOffset = 0,
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
  final String deleteMapService;
  final String renameMapService;

  final String mappingStatusTopic;
  final String mapPreviewTopic;
  final String mappingStartService;
  final String mappingStopService;
  final String mappingSaveService;

  final String poseCheckService;
  final String poseCommitService;

  final String homeGetService;
  final String homeSaveService;
  final String homeDeleteService;

  final String keepoutGetService;
  final String keepoutSaveService;
  final String keepoutStateTopic;

  final String routeDraftService;
  final String routeSaveService;
  final String routeGetService;
  final String routeStateTopic;

  /// 어느 기기에서든 레일을 저장하면 오는 알림(2026-10-08). 받으면 레일 그림을 다시 받습니다.
  final String routeSavedTopic;

  /// 관리자 유심 폰이 다른 화면(웹 등)에서 보낸 배송의 도착 문자를 대신 보내고 그 결과를
  final String deliverySmsResultTopic;

  final String missionReturnHomeService;

  final String goalEventTopic;

  final String missionRequestService;
  final String missionDeliveryService;
  final String missionWaitSpotService;
  final String missionCancelService;
  final String missionPauseService;
  final String missionResumeService;
  final String missionHelpAckService;
  final String robotStatusTopic;
  final String emergencyActivateService;
  final String emergencyResetService;
  final String emergencyStateTopic;
  final String robotHealthTopic;
  final String robotEventsTopic;
  final int robotHealthTimeoutSeconds;
  final int emergencyServiceTimeoutSeconds;
  final int maxReconnectAttempts;
  final bool autoRequestMapList;
  final bool autoRequestLocationList;
  final double xOffset;
  final double yOffset;
  final double yawOffset;
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
    String? deleteMapService,
    String? renameMapService,
    String? mappingStatusTopic,
    String? mapPreviewTopic,
    String? mappingStartService,
    String? mappingStopService,
    String? mappingSaveService,
    String? poseCheckService,
    String? poseCommitService,
    String? homeGetService,
    String? homeSaveService,
    String? homeDeleteService,
    String? keepoutGetService,
    String? keepoutSaveService,
    String? keepoutStateTopic,
    String? routeDraftService,
    String? routeSaveService,
    String? routeGetService,
    String? routeStateTopic,
    String? routeSavedTopic,
    String? deliverySmsResultTopic,
    String? missionReturnHomeService,
    String? goalEventTopic,
    String? missionRequestService,
    String? missionDeliveryService,
    String? missionWaitSpotService,
    String? missionCancelService,
    String? missionPauseService,
    String? missionResumeService,
    String? missionHelpAckService,
    String? robotStatusTopic,
    String? emergencyActivateService,
    String? emergencyResetService,
    String? emergencyStateTopic,
    String? robotHealthTopic,
    String? robotEventsTopic,
    int? robotHealthTimeoutSeconds,
    int? emergencyServiceTimeoutSeconds,
    int? maxReconnectAttempts,
    bool? autoRequestMapList,
    bool? autoRequestLocationList,
    double? xOffset,
    double? yOffset,
    double? yawOffset,
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
      deleteMapService: deleteMapService ?? this.deleteMapService,
      renameMapService: renameMapService ?? this.renameMapService,
      mappingStatusTopic: mappingStatusTopic ?? this.mappingStatusTopic,
      mapPreviewTopic: mapPreviewTopic ?? this.mapPreviewTopic,
      mappingStartService: mappingStartService ?? this.mappingStartService,
      mappingStopService: mappingStopService ?? this.mappingStopService,
      mappingSaveService: mappingSaveService ?? this.mappingSaveService,
      poseCheckService: poseCheckService ?? this.poseCheckService,
      poseCommitService: poseCommitService ?? this.poseCommitService,
      homeGetService: homeGetService ?? this.homeGetService,
      homeSaveService: homeSaveService ?? this.homeSaveService,
      homeDeleteService: homeDeleteService ?? this.homeDeleteService,
      keepoutGetService: keepoutGetService ?? this.keepoutGetService,
      keepoutSaveService: keepoutSaveService ?? this.keepoutSaveService,
      keepoutStateTopic: keepoutStateTopic ?? this.keepoutStateTopic,
      routeDraftService: routeDraftService ?? this.routeDraftService,
      routeSaveService: routeSaveService ?? this.routeSaveService,
      routeGetService: routeGetService ?? this.routeGetService,
      routeStateTopic: routeStateTopic ?? this.routeStateTopic,
      routeSavedTopic: routeSavedTopic ?? this.routeSavedTopic,
      deliverySmsResultTopic:
          deliverySmsResultTopic ?? this.deliverySmsResultTopic,
      missionReturnHomeService:
          missionReturnHomeService ?? this.missionReturnHomeService,
      goalEventTopic: goalEventTopic ?? this.goalEventTopic,
      missionRequestService:
          missionRequestService ?? this.missionRequestService,
      missionDeliveryService:
          missionDeliveryService ?? this.missionDeliveryService,
      missionWaitSpotService:
          missionWaitSpotService ?? this.missionWaitSpotService,
      missionCancelService: missionCancelService ?? this.missionCancelService,
      missionPauseService: missionPauseService ?? this.missionPauseService,
      missionResumeService: missionResumeService ?? this.missionResumeService,
      missionHelpAckService:
          missionHelpAckService ?? this.missionHelpAckService,
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
      maxReconnectAttempts: maxReconnectAttempts ?? this.maxReconnectAttempts,
      autoRequestMapList: autoRequestMapList ?? this.autoRequestMapList,
      autoRequestLocationList:
          autoRequestLocationList ?? this.autoRequestLocationList,
      xOffset: xOffset ?? this.xOffset,
      yOffset: yOffset ?? this.yOffset,
      yawOffset: yawOffset ?? this.yawOffset,
      mapScale: mapScale ?? this.mapScale,
      flipMapY: flipMapY ?? this.flipMapY,
    );
  }

  /// 설정 화면에서 고칠 수 있는 값의 JSON 이름. 기기에 저장하고 되살리는 것은 이것뿐입니다
  static const editableJsonKeys = <String>{
    'rosBridgeUrl',
    'mapHttpBaseUrl',
    'xOffset',
    'yOffset',
    'yawOffset',
    'mapScale',
    'flipMapY',
    'autoRequestMapList',
    'autoRequestLocationList',
    'mapListRequestTopic',
    'mapListTopic',
    'locationListRequestTopic',
    'locationListTopic',
    'saveLocationTopic',
    'deleteLocationRequestTopic',
    'missionRequestService',
    'missionDeliveryService',
    'missionWaitSpotService',
    'robotStatusTopic',
    'emergencyActivateService',
    'emergencyResetService',
    'emergencyStateTopic',
    'emergencyServiceTimeoutSeconds',
  };

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
      'deleteMapService': deleteMapService,
      'renameMapService': renameMapService,
      'mappingStatusTopic': mappingStatusTopic,
      'mapPreviewTopic': mapPreviewTopic,
      'mappingStartService': mappingStartService,
      'mappingStopService': mappingStopService,
      'mappingSaveService': mappingSaveService,
      'missionRequestService': missionRequestService,
      'missionDeliveryService': missionDeliveryService,
      'missionWaitSpotService': missionWaitSpotService,
      'missionCancelService': missionCancelService,
      'missionPauseService': missionPauseService,
      'missionResumeService': missionResumeService,
      'missionHelpAckService': missionHelpAckService,
      'robotStatusTopic': robotStatusTopic,
      'emergencyActivateService': emergencyActivateService,
      'emergencyResetService': emergencyResetService,
      'emergencyStateTopic': emergencyStateTopic,
      'robotHealthTopic': robotHealthTopic,
      'robotEventsTopic': robotEventsTopic,
      'robotHealthTimeoutSeconds': robotHealthTimeoutSeconds,
      'emergencyServiceTimeoutSeconds': emergencyServiceTimeoutSeconds,
      'maxReconnectAttempts': maxReconnectAttempts,
      'autoRequestMapList': autoRequestMapList,
      'autoRequestLocationList': autoRequestLocationList,
      'xOffset': xOffset,
      'yOffset': yOffset,
      'yawOffset': yawOffset,
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
      deleteMapService:
          json['deleteMapService'] as String? ?? defaults.deleteMapService,
      renameMapService:
          json['renameMapService'] as String? ?? defaults.renameMapService,
      mappingStatusTopic:
          json['mappingStatusTopic'] as String? ?? defaults.mappingStatusTopic,
      mapPreviewTopic:
          json['mapPreviewTopic'] as String? ?? defaults.mapPreviewTopic,
      mappingStartService: json['mappingStartService'] as String? ??
          defaults.mappingStartService,
      mappingStopService:
          json['mappingStopService'] as String? ?? defaults.mappingStopService,
      mappingSaveService:
          json['mappingSaveService'] as String? ?? defaults.mappingSaveService,
      missionRequestService: json['missionRequestService'] as String? ??
          defaults.missionRequestService,
      missionDeliveryService: json['missionDeliveryService'] as String? ??
          defaults.missionDeliveryService,
      missionWaitSpotService: json['missionWaitSpotService'] as String? ??
          defaults.missionWaitSpotService,
      missionCancelService: json['missionCancelService'] as String? ??
          defaults.missionCancelService,
      missionPauseService: json['missionPauseService'] as String? ??
          defaults.missionPauseService,
      missionResumeService: json['missionResumeService'] as String? ??
          defaults.missionResumeService,
      missionHelpAckService: json['missionHelpAckService'] as String? ??
          defaults.missionHelpAckService,
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
      maxReconnectAttempts:
          json['maxReconnectAttempts'] as int? ?? defaults.maxReconnectAttempts,
      autoRequestMapList:
          json['autoRequestMapList'] as bool? ?? defaults.autoRequestMapList,
      autoRequestLocationList: json['autoRequestLocationList'] as bool? ??
          defaults.autoRequestLocationList,
      xOffset: (json['xOffset'] as num?)?.toDouble() ?? defaults.xOffset,
      yOffset: (json['yOffset'] as num?)?.toDouble() ?? defaults.yOffset,
      yawOffset: (json['yawOffset'] as num?)?.toDouble() ?? defaults.yawOffset,
      mapScale: (json['mapScale'] as num?)?.toDouble() ?? defaults.mapScale,
      flipMapY: json['flipMapY'] as bool? ?? defaults.flipMapY,
    );
  }
}
