// 이 파일은 앱 설정값과 ROS topic 이름, 지도 서버 주소 같은 기본 구성을 보관합니다.
import 'package:flutter/foundation.dart';

@immutable
class AppSettings {
  const AppSettings({
    // 기존 로컬 테스트 주소. 리눅스 데스크탑으로 동작 확인해 볼 때 사용
    this.rosBridgeUrl = 'ws://127.0.0.1:9090',
    this.mapHttpBaseUrl = 'http://127.0.0.1:8000',
    //
    // Android 기기처럼 Jetson 밖에서 접속하는 실행 환경은 Jetson host IP를 사용합니다.
    // this.rosBridgeUrl = 'ws://192.168.0.10:9090',
    // this.mapHttpBaseUrl = 'http://192.168.0.10:8000',
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
    this.deleteMapService = '/delete_map',
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
    this.missionReturnHomeService = '/vica/mission/return_home',
    this.goalEventTopic = '/vica_goal_event',
    this.robotStatusTopic = '/robot_status',
    this.emergencyActivateService = '/app_estop_activate',
    this.emergencyResetService = '/app_estop_reset',
    this.emergencyStateTopic = '/app_estop_state',
    // robot_health_monitor_node가 내는 타입 메시지 토픽입니다. JSON String이 아니라
    // vica_interfaces 커스텀 메시지를 rosbridge가 필드 map으로 직렬화해 보냅니다.
    this.robotHealthTopic = '/robot/health',
    this.robotEventsTopic = '/robot/events',
    // /robot/health 만료. 모니터가 죽으면 마지막 상태를 현재로 쓰지 않습니다.
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
  // 지도 삭제. map_list_node 가 제공합니다.
  final String deleteMapService;

  // 매핑 세션 제어. mapping_supervisor_node 가 제공합니다.
  final String mappingStatusTopic;
  final String mapPreviewTopic;
  final String mappingStartService;
  final String mappingStopService;
  final String mappingSaveService;

  // Nav2 초기 위치 잡기. pose_bootstrap_node 가 제공합니다.
  // 확인은 AMCL 을 건드리지 않고 점수만 계산하고, 확정에서만 /initialpose 를 냅니다.
  final String poseCheckService;
  final String poseCommitService;

  // 지도별 홈 위치. mission_manager_node 가 제공합니다.
  // 홈은 목적지가 아니라 로봇의 설정값이라 장소 목록과 별도 경로를 씁니다.
  final String homeGetService;
  final String homeSaveService;
  final String homeDeleteService;

  // 지도별 금지구역. keepout_map_node 가 제공합니다.
  //
  // 저장·조회는 service 입니다 — "됐다/안 됐다"가 있는 일이라 응답을 그 자리에서
  // 받아야 합니다. state topic 은 요청 없이 생긴 변화(주행이 끝나 미뤄 둔 적용이
  // 이뤄진 경우)만 알립니다. 두 경로가 겹치면 같은 일을 두 번 알리게 됩니다.
  final String keepoutGetService;
  final String keepoutSaveService;
  final String keepoutStateTopic;

  // 홈 복귀. **관리자 전용 경로입니다.**
  //
  // 목적지 요청은 UUID 로 지목하는데 홈에는 UUID 가 없고, 음성 LLM 은 토픽만
  // 발행할 뿐 서비스 클라이언트가 없습니다. 즉 권한을 검사해서 막는 것이
  // 아니라 사용자 쪽에 문이 없습니다.
  final String missionReturnHomeService;

  // Mission Manager 가 내는 goal 생명주기 이벤트입니다.
  //
  // 앱이 직접 구독합니다. /robot_status 를 거치면 실패 '사유'가 사라집니다 —
  // 그 노드는 목적지 이름만 비우고 reason 을 버리기 때문에, 관리자 눈에는
  // 주행이 조용히 사라진 것처럼 보였습니다. /robot/health 를 직접 구독하는
  // 것과 같은 이유이며 /robot_status 스키마는 그대로 둡니다.
  final String goalEventTopic;

  final String missionRequestService;
  // 진행 중인 주행 제어. 모두 vica_interfaces/srv/MissionCommand를 씁니다.
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
    String? deleteMapService,
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
    String? missionReturnHomeService,
    String? goalEventTopic,
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
      deleteMapService: deleteMapService ?? this.deleteMapService,
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
      missionReturnHomeService:
          missionReturnHomeService ?? this.missionReturnHomeService,
      goalEventTopic: goalEventTopic ?? this.goalEventTopic,
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
      'deleteMapService': deleteMapService,
      'mappingStatusTopic': mappingStatusTopic,
      'mapPreviewTopic': mapPreviewTopic,
      'mappingStartService': mappingStartService,
      'mappingStopService': mappingStopService,
      'mappingSaveService': mappingSaveService,
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
      deleteMapService:
          json['deleteMapService'] as String? ?? defaults.deleteMapService,
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
