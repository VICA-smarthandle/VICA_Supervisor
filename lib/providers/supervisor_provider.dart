// 이 파일은 ROS2 연결, 지도/장소/로봇 상태, 알림 로그를 앱 전체 상태로 관리합니다.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/app_settings.dart';
import '../core/log_filter.dart';
import '../models/location_point.dart';
import '../models/robot_event.dart';
import '../models/robot_health.dart';
import '../models/robot_status.dart';
import '../models/supervisor_log.dart';
import '../models/vica_map.dart';
import '../ros/ros_bridge_client.dart';

enum EmergencyStopState {
  inactive,
  activating,
  active,
  releasing,
  activationFailed,
  releaseFailed,
}

class SupervisorProvider extends ChangeNotifier {
  SupervisorProvider();

  static const _nav2UnavailableReason = 'Nav2/AMCL 미실행';
  static const _nav2UnavailableMessage =
      'Nav2가 실행되지 않아 현재 위치와 주행 이벤트를 받을 수 없습니다.';
  static const _nav2AvailableMessage = 'Nav2가 실행되었습니다.';
  static const _noEventsRecordedReason = 'no events recorded';

  // Mission Manager가 돌려주는 GateReason 코드를 화면 문구로 옮깁니다.
  // 판정은 Mission Manager가 하고 앱은 결과를 읽기 좋게 보여주기만 합니다.
  static const _gateReasonMessages = <String, String>{
    'estop_active': '비상정지 상태여서 주행할 수 없습니다. 해제 후 다시 요청하세요.',
    'busy_navigating': '이미 다른 목적지로 주행 중입니다.',
    'private_destination': '비공개 장소는 주행을 요청할 수 없습니다.',
    'not_approachable': '로봇이 접근할 수 없는 장소입니다.',
    'unknown_destination': '저장되지 않은 장소입니다. 장소 목록을 새로고침하세요.',
    'pose_invalid': '장소 좌표가 지도 범위를 벗어났습니다.',
    'nav_not_ready': 'Nav2가 준비되지 않아 주행할 수 없습니다.',
    'need_confirm': '목적지 확인이 필요합니다.',
    'safety_flag': '안전 조건 때문에 주행할 수 없습니다.',
    'no_matched_id': '목적지를 찾지 못했습니다.',
    'not_navigate': '주행 요청으로 처리되지 않았습니다.',
    'not_navigating': '지금은 주행 중이 아닙니다.',
    'not_paused': '다시 출발할 주행이 없습니다.',
  };

  final _uuid = const Uuid();
  // 지도 목록 응답을 처리할 때도 자동 요청 설정이 필요해 연결에 쓴 설정을 보관합니다.
  AppSettings? _lastSettings;
  RosBridgeClient? _client;
  RosConnectionState _connectionState = RosConnectionState.disconnected;
  String _connectionDetail = '';
  List<VicaMap> _maps = const [];
  final Map<String, List<LocationPoint>> _locationsByMap = {};
  final Map<String, RobotStatus> _robotsById = {};
  final List<SupervisorLog> _logs = [];
  String? _selectedMapId;
  String? _selectedLocationId;
  LocationPoint? _draftLocation;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  EmergencyStopState _emergencyStopState = EmergencyStopState.inactive;
  String _emergencyStopMessage = '';
  bool _nav2UnavailableNotified = false;
  bool _nav2AvailableNotified = false;
  bool _nav2WasUnavailable = false;
  // 마지막으로 기록한 오류 사유. 상태 topic이 같은 사유를 계속 실어 보내므로
  // 사유가 실제로 바뀔 때만 알림을 남기기 위해 들고 있습니다.
  String _lastLoggedErrorReason = '';

  // robot_health_monitor_node가 보내는 상세 진단. /robot_status.error_reason이
  // 문자열 한 줄인 것과 달리 컴포넌트·등급·조치·발생횟수를 담습니다.
  RobotHealth? _health;
  final List<RobotEvent> _healthEvents = [];

  // 이벤트 이력 상한. _logs와 같은 값으로 둡니다.
  // 200 -> 100. 래치된 결함이 1 Hz 로 '지속 중' 이벤트를 내던 동안 200칸이
  // 3분 20초 만에 찼습니다. 로봇 쪽 재알림 간격을 늘리고(아래 참조) 화면에서
  // 같은 결함을 한 줄로 접으므로 100칸이면 몇 시간치가 들어갑니다.
  //   vica_ros2_ws/src/vica_system_monitor/config/required_components.yaml
  //   latched_reminder_interval_sec / reminder_interval_sec
  static const _maxHealthEvents = 100;
  // 알림 및 로그 화면의 상한. 진단 이벤트 이력과 같은 값으로 둡니다.
  static const _maxLogs = 100;

  RosConnectionState get connectionState => _connectionState;
  String get connectionDetail => _connectionDetail;
  EmergencyStopState get emergencyStopState => _emergencyStopState;
  String get emergencyStopMessage => _emergencyStopMessage;
  bool get emergencyOverlayVisible =>
      _emergencyStopState != EmergencyStopState.inactive;
  List<VicaMap> get maps => _maps;
  String? get selectedMapId => _selectedMapId;
  String? get selectedLocationId => _selectedLocationId;
  LocationPoint? get draftLocation => _draftLocation;
  List<SupervisorLog> get logs => List.unmodifiable(_logs);

  /// 로봇 전체 상태 요약. 아직 받지 못했으면 null입니다.
  RobotHealth? get health => _health;

  /// 결함 전이 이력. 최신이 앞입니다.
  List<RobotEvent> get healthEvents => List.unmodifiable(_healthEvents);
  List<RobotStatus> get robots => _robotsById.values.toList(growable: false);
  RobotStatus? get primaryRobot =>
      _robotsById.isEmpty ? null : _robotsById.values.first;

  VicaMap? get selectedMap {
    for (final map in _maps) {
      if (map.mapId == _selectedMapId) {
        return map;
      }
    }
    return _maps.isEmpty ? null : _maps.first;
  }

  List<LocationPoint> locationsFor(String? mapId) {
    if (mapId == null) {
      return const [];
    }
    return List.unmodifiable(_locationsByMap[mapId] ?? const []);
  }

  // rosbridge 연결을 하나만 유지하고 필요한 topic만 구독합니다.
  Future<void> connect(AppSettings settings) async {
    _lastSettings = settings;
    _reconnectTimer?.cancel();
    _reconnectAttempts = 0;
    _resetNav2NotificationState();
    final oldClient = _client;
    _client = null;
    await oldClient?.close();
    _client = RosBridgeClient(onState: (state, detail) {
      _setConnectionState(state, detail);
      if (state == RosConnectionState.disconnected ||
          state == RosConnectionState.failed) {
        _scheduleReconnect(settings);
      }
    });
    await _client!.connect(settings.rosBridgeUrl);
    if (_connectionState == RosConnectionState.connected) {
      _subscribeRequiredTopics(settings);
      _requestSyncAfterConnect(settings);
    }
  }

  // 연결이 끊긴 사이 VICA에서 지도나 장소가 바뀌었을 수 있으므로 둘 다 다시 받습니다.
  // 지도 목록만 받으면 장소는 예전 것이 남아 실제 저장 내용과 어긋납니다.
  void _requestSyncAfterConnect(AppSettings settings) {
    if (settings.autoRequestMapList) {
      requestMapList(settings);
    }
    final mapId = _selectedMapId;
    if (settings.autoRequestLocationList && mapId != null) {
      requestLocationList(settings, mapId);
    }
  }

  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
    final client = _client;
    _client = null;
    await client?.close();
    _clearRobotRuntimeState();
    notifyListeners();
  }

  // 연결이 끊기면 로봇 실시간 상태는 더 이상 현재 사실이 아니므로 비웁니다.
  // 지도와 장소는 정적 데이터라 유지해 재연결 때 다시 받지 않아도 되게 합니다.
  // E-stop 상태는 안전 표시이므로 앱이 임의로 지우지 않습니다.
  void _clearRobotRuntimeState() {
    _lastLoggedErrorReason = '';
    _resetNav2NotificationState();
    // 연결이 끊기면 진단도 현재 상태가 아닙니다. 이벤트 이력은 지나간 기록이므로
    // 남겨둡니다 — 관리자가 왜 끊겼는지 되짚을 수 있어야 합니다.
    _health = null;
    if (_robotsById.isEmpty) {
      return;
    }
    _robotsById.clear();
  }

  // 무한 재시도를 피하기 위해 설정된 횟수까지만 재연결합니다.
  void _scheduleReconnect(AppSettings settings) {
    if (_client == null ||
        _reconnectAttempts >= settings.maxReconnectAttempts) {
      return;
    }
    _reconnectTimer?.cancel();
    _reconnectAttempts += 1;
    _reconnectTimer = Timer(const Duration(seconds: 3), () async {
      await _client?.connect(settings.rosBridgeUrl);
      if (_connectionState == RosConnectionState.connected) {
        _subscribeRequiredTopics(settings);
        _requestSyncAfterConnect(settings);
      }
    });
  }

  void _subscribeRequiredTopics(AppSettings settings) {
    _client
      ?..subscribe(topic: settings.mapListTopic, handler: _handleMapList)
      ..subscribe(
        topic: settings.locationListTopic,
        handler: _handleLocationList,
      )
      ..subscribe(
        topic: settings.robotStatusTopic,
        handler: _handleRobotStatus,
      )
      ..subscribe(
        topic: settings.emergencyStateTopic,
        handler: _handleEmergencyStopState,
      )
      // 커스텀 메시지는 type을 지정해 구독합니다. RosBridgeClient가 msg['data']가
      // String이 아닌 경우 raw 필드 map을 그대로 handler에 넘깁니다.
      ..subscribe(
        topic: settings.robotHealthTopic,
        handler: _handleRobotHealth,
        type: 'vica_interfaces/msg/RobotHealth',
      )
      ..subscribe(
        topic: settings.robotEventsTopic,
        handler: _handleRobotEvent,
        type: 'vica_interfaces/msg/RobotEvent',
      );
  }

  // 앱 비상정지 버튼: app_emergency_node의 activate 서비스를 호출합니다.
  // 서비스 응답으로 성공/실패를 바로 판정하므로 request_id나 timeout 타이머가 필요없습니다.
  Future<void> activateEmergencyStop(AppSettings settings) async {
    if (_emergencyStopState == EmergencyStopState.activating ||
        _emergencyStopState == EmergencyStopState.releasing) {
      return;
    }
    final client = _client;
    if (client == null || _connectionState != RosConnectionState.connected) {
      _setEmergencyStopState(
        EmergencyStopState.activationFailed,
        'ROS Bridge에 연결되지 않아 비상정지를 활성화하지 못했습니다.',
      );
      _addLog(LogFilter.emergencyStop, '비상정지 요청 실패: ROS 연결 안 됨');
      return;
    }
    _setEmergencyStopState(
      EmergencyStopState.activating,
      'VICA에 비상정지를 요청하고 있습니다.',
    );
    _addLog(LogFilter.emergencyStop, '비상정지 요청 전송');
    try {
      final response = await client.callService(
        service: settings.emergencyActivateService,
        timeout: Duration(seconds: settings.emergencyServiceTimeoutSeconds),
      );
      if (response.result && response.success) {
        _setEmergencyStopState(
          EmergencyStopState.active,
          response.message.isEmpty
              ? '비상정지가 활성화되었습니다. 기존 목적지는 취소되었습니다.'
              : response.message,
        );
        _addLog(LogFilter.emergencyStop, '비상정지 활성화 완료');
      } else {
        _setEmergencyStopState(
          EmergencyStopState.activationFailed,
          response.message.isEmpty ? '비상정지 요청을 처리하지 못했습니다.' : response.message,
        );
        _addLog(LogFilter.emergencyStop, _emergencyStopMessage);
      }
    } catch (error) {
      _setEmergencyStopState(
        EmergencyStopState.activationFailed,
        'app_emergency_node의 비상정지 응답이 없습니다: $error',
      );
      _addLog(LogFilter.emergencyStop, _emergencyStopMessage);
    }
  }

  Future<void> retryEmergencyStop(AppSettings settings) async {
    if (_connectionState != RosConnectionState.connected) {
      await connect(settings);
    }
    if (_emergencyStopState != EmergencyStopState.activationFailed) {
      return;
    }
    await activateEmergencyStop(settings);
  }

  void dismissEmergencyStopFailure() {
    if (_emergencyStopState != EmergencyStopState.activationFailed) {
      return;
    }
    _setEmergencyStopState(EmergencyStopState.inactive, '');
    _addLog(LogFilter.emergencyStop, '비상정지 실패 알림 닫음');
  }

  // 비상정지 해제: app_emergency_node의 reset 서비스를 호출합니다.
  // 노드가 /app_emergency_stop=false 전파 → Nav2 재취소 → /estop_reset 호출까지
  // 마친 뒤 성공/실패를 돌려주므로, 성공이면 이후 정상 주행 명령이 그대로 반영됩니다.
  Future<void> resetEmergencyStop(AppSettings settings) async {
    if (_emergencyStopState == EmergencyStopState.releasing ||
        _emergencyStopState == EmergencyStopState.activating) {
      return;
    }
    final client = _client;
    if (client == null || _connectionState != RosConnectionState.connected) {
      _setEmergencyStopState(
        EmergencyStopState.releaseFailed,
        'ROS Bridge에 연결되지 않아 비상정지를 해제하지 못했습니다.',
      );
      _addLog(LogFilter.emergencyStop, '비상정지 해제 실패: ROS 연결 안 됨');
      return;
    }
    _setEmergencyStopState(
      EmergencyStopState.releasing,
      'VICA에 비상정지 해제를 요청하고 있습니다.',
    );
    _addLog(LogFilter.emergencyStop, '비상정지 해제 요청 전송');
    try {
      final response = await client.callService(
        service: settings.emergencyResetService,
        timeout: Duration(seconds: settings.emergencyServiceTimeoutSeconds),
      );
      if (response.result && response.success) {
        _setEmergencyStopState(EmergencyStopState.inactive, '');
        _addLog(LogFilter.emergencyStop, '비상정지 해제 완료');
      } else {
        _setEmergencyStopState(
          EmergencyStopState.releaseFailed,
          response.message.isEmpty ? '비상정지 해제를 처리하지 못했습니다.' : response.message,
        );
        _addLog(LogFilter.emergencyStop, _emergencyStopMessage);
      }
    } catch (error) {
      _setEmergencyStopState(
        EmergencyStopState.releaseFailed,
        'app_emergency_node의 비상정지 해제 응답이 없습니다: $error',
      );
      _addLog(LogFilter.emergencyStop, _emergencyStopMessage);
    }
  }

  Future<void> retryEmergencyStopRelease(AppSettings settings) async {
    if (_connectionState != RosConnectionState.connected) {
      await connect(settings);
    }
    await resetEmergencyStop(settings);
  }

  void requestMapList(AppSettings settings) {
    _client?.publishJsonString(
      topic: settings.mapListRequestTopic,
      payload: {
        'request_id': _uuid.v4(),
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
    _addLog(LogFilter.connection, '지도 목록 요청 전송');
  }

  void requestLocationList(AppSettings settings, String mapId) {
    _client?.publishJsonString(
      topic: settings.locationListRequestTopic,
      payload: {
        'request_id': _uuid.v4(),
        'map_id': mapId,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
    _addLog(LogFilter.coordinateTransfer, '$mapId 장소 목록 요청 전송');
  }

  void selectMap(AppSettings settings, String? mapId) {
    if (_selectedMapId == mapId) {
      return;
    }
    _selectedMapId = mapId;
    _selectedLocationId = null;
    notifyListeners();
    if (mapId != null && settings.autoRequestLocationList) {
      requestLocationList(settings, mapId);
    }
  }

  void selectLocation(String? locationId) {
    if (_selectedLocationId == locationId) {
      return;
    }
    _selectedLocationId = locationId;
    notifyListeners();
  }

  void setDraftLocation(LocationPoint? next) {
    if (jsonEncode(_draftLocation?.toJson()) == jsonEncode(next?.toJson())) {
      return;
    }
    _draftLocation = next;
    notifyListeners();
  }

  // 임시 목적지를 지도별 destinations 스키마 JSON으로 전송합니다.
  void saveDraftLocation(AppSettings settings) {
    final draft = _draftLocation;
    if (draft == null) {
      return;
    }
    final destination = draft.toJson();
    final pose = Map<String, Object>.from(
      destination['pose']! as Map<String, Object>,
    );
    pose['yaw'] = _normalizeYawDegrees(draft.yaw);
    final payload = {
      'request_id': _uuid.v4(),
      'map_id': draft.mapId,
      ...destination,
      'pose': pose,
      'timestamp': DateTime.now().toIso8601String(),
    };
    _client?.publishJsonString(
      topic: settings.saveLocationTopic,
      payload: payload,
    );
    _addLog(LogFilter.coordinateTransfer, '${draft.name} 장소 저장 요청 전송');
    _draftLocation = null;
    notifyListeners();
  }

  double _normalizeYawDegrees(double yaw) {
    final normalized = yaw % 360.0;
    return normalized < 0 ? normalized + 360.0 : normalized;
  }

  // 삭제도 UUID와 map_id만 전송하며 실제 저장 경로는 ROS 파라미터가 소유합니다.
  void deleteLocation(AppSettings settings, LocationPoint location) {
    _client?.publishJsonString(
      topic: settings.deleteLocationRequestTopic,
      payload: {
        'request_id': _uuid.v4(),
        'map_id': location.mapId,
        'destination_id': location.locationId,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
    _addLog(LogFilter.coordinateTransfer, '${location.name} 장소 삭제 요청 전송');
  }

  // 앱은 vica_goto_goal, LLM과 같은 경로로 요청만 보냅니다. 지도·접근 권한·Safety·
  // Nav2 검증과 Goal 생성은 모두 Mission Manager가 맡습니다. 앱이 가진 장소 정보는
  // 마지막으로 받아온 사본이라 최신이 아닐 수 있어, 여기서 미리 판정하지 않습니다.
  Future<String> requestDestination(
    AppSettings settings,
    LocationPoint location,
  ) async {
    final client = _client;
    if (client == null || _connectionState != RosConnectionState.connected) {
      return 'ROS Bridge에 연결되지 않았습니다.';
    }
    try {
      final response = await client.callService(
        service: settings.missionRequestService,
        type: 'vica_interfaces/srv/RequestDestination',
        args: {
          'request_id': _uuid.v4(),
          'map_id': location.mapId,
          'destination_id': location.locationId,
        },
      );
      final message = response.message.isEmpty
          ? (response.accepted ? '주행 요청을 수락했습니다.' : '주행 요청이 거부되었습니다.')
          : _localizeGateReason(response.message);
      _addLog(LogFilter.coordinateTransfer, message);
      return message;
    } catch (error) {
      final message = 'Mission Manager 목적지 요청 실패: $error';
      _addLog(LogFilter.coordinateTransfer, message);
      return message;
    }
  }

  // 진행 중인 주행 제어. 요청만 보내고 허용 여부는 Mission Manager가 판정합니다.
  // 세 요청 모두 vica_interfaces/srv/MissionCommand 형태를 씁니다.
  Future<String> cancelDestination(AppSettings settings) {
    return _sendMissionCommand(settings.missionCancelService, '주행을 취소했습니다.');
  }

  Future<String> pauseNavigation(AppSettings settings) {
    return _sendMissionCommand(settings.missionPauseService, '주행을 일시정지했습니다.');
  }

  Future<String> resumeNavigation(AppSettings settings) {
    return _sendMissionCommand(settings.missionResumeService, '다시 출발합니다.');
  }

  Future<String> _sendMissionCommand(
    String service,
    String defaultSuccessMessage,
  ) async {
    final client = _client;
    if (client == null || _connectionState != RosConnectionState.connected) {
      return 'ROS Bridge에 연결되지 않았습니다.';
    }
    try {
      final response = await client.callService(
        service: service,
        type: 'vica_interfaces/srv/MissionCommand',
        args: {'request_id': _uuid.v4()},
      );
      final message = response.message.isEmpty
          ? (response.accepted ? defaultSuccessMessage : '요청이 거부되었습니다.')
          : _localizeGateReason(response.message);
      _addLog(LogFilter.coordinateTransfer, message);
      return message;
    } catch (error) {
      final message = 'Mission Manager 요청 실패: $error';
      _addLog(LogFilter.coordinateTransfer, message);
      return message;
    }
  }

  // 거부 응답은 "목적지 요청 거부: private_destination"처럼 코드가 섞여 옵니다.
  // 아는 코드면 한국어 문구로 바꾸고, 모르는 응답은 원문 그대로 보여줍니다.
  String _localizeGateReason(String message) {
    for (final entry in _gateReasonMessages.entries) {
      if (message.contains(entry.key)) {
        return entry.value;
      }
    }
    return message;
  }

  void clearLogs(LogFilter filter) {
    if (filter == LogFilter.all) {
      _logs.clear();
    } else {
      _logs.removeWhere((log) => log.filter == filter);
    }
    notifyListeners();
  }

  void _handleMapList(Map<String, Object?> message) {
    final rawMaps = message['maps'];
    if (rawMaps is! List) {
      return;
    }
    final nextMaps = rawMaps
        .whereType<Map<String, Object?>>()
        .map(VicaMap.fromJson)
        .where((map) => map.mapId.isNotEmpty)
        .toList(growable: false);
    if (listEquals(_maps.map((e) => jsonEncode(e.toJson())).toList(),
        nextMaps.map((e) => jsonEncode(e.toJson())).toList())) {
      return;
    }
    _maps = nextMaps;
    final hadNoSelection = _selectedMapId == null;
    _selectedMapId ??= _maps.isEmpty ? null : _maps.first.mapId;
    // 첫 연결에서는 선택된 지도가 없어 장소를 함께 요청하지 못합니다.
    // 지도가 처음 정해지는 이 시점에 그 지도의 장소도 받아옵니다.
    final mapId = _selectedMapId;
    final settings = _lastSettings;
    if (hadNoSelection &&
        mapId != null &&
        settings != null &&
        settings.autoRequestLocationList) {
      requestLocationList(settings, mapId);
    }
    _addLog(LogFilter.connection, '지도 목록 ${_maps.length}개 수신');
    notifyListeners();
  }

  void _handleLocationList(Map<String, Object?> message) {
    final mapId = message['map_id'] as String?;
    final rawLocations = message['locations'];
    if (mapId == null || rawLocations is! List) {
      return;
    }
    final nextLocations = rawLocations
        .whereType<Map<String, Object?>>()
        .map((json) => LocationPoint.fromJson(json, mapId))
        .where((location) => location.locationId.isNotEmpty)
        .toList(growable: false);
    final before = jsonEncode(
      (_locationsByMap[mapId] ?? const []).map((e) => e.toJson()).toList(),
    );
    final after = jsonEncode(nextLocations.map((e) => e.toJson()).toList());
    if (before == after) {
      return;
    }
    _locationsByMap[mapId] = nextLocations;
    _addLog(
        LogFilter.coordinateTransfer, '$mapId 장소 ${nextLocations.length}개 수신');
    notifyListeners();
  }

  void _handleRobotStatus(Map<String, Object?> message) {
    final next = RobotStatus.fromJson(message);
    final before = _robotsById[next.robotId];
    if (before != null &&
        jsonEncode(before.toJson()) == jsonEncode(next.toJson())) {
      return;
    }
    _robotsById[next.robotId] = next;
    _logErrorReasonChange(next);
    _handleNav2StatusLog(next);
    notifyListeners();
  }

  // 상태 topic은 같은 오류 사유를 주기적으로 반복해서 싣고 옵니다. 매번 기록하면
  // 알림 목록이 같은 문구로 가득 차므로, 사유가 바뀔 때만 한 번 남깁니다.
  void _logErrorReasonChange(RobotStatus robot) {
    if (!robot.hasError) {
      _lastLoggedErrorReason = '';
      return;
    }
    final errorReason = robot.errorReason.trim();
    if (errorReason == _lastLoggedErrorReason) {
      return;
    }
    _lastLoggedErrorReason = errorReason;
    if (_isNoEventsRecorded(errorReason)) {
      // 진단 정보일 뿐 비상정지가 아니므로 연결 알림으로 분류합니다.
      _addLog(LogFilter.connection, errorReason);
      return;
    }
    _addLog(LogFilter.emergencyStop, '${robot.robotName}: $errorReason');
  }

  bool _isNoEventsRecorded(String message) {
    // 발행 노드가 앞뒤에 다른 문구를 붙여 보내는 경우가 있어 포함 여부로 판정합니다.
    return message.trim().toLowerCase().contains(_noEventsRecordedReason);
  }

  void _handleNav2StatusLog(RobotStatus robot) {
    final nav2Unavailable = robot.waitingReason == _nav2UnavailableReason;
    if (nav2Unavailable) {
      _nav2WasUnavailable = true;
      if (!_nav2UnavailableNotified) {
        _nav2UnavailableNotified = true;
        _nav2AvailableNotified = false;
        _addLog(LogFilter.connection, _nav2UnavailableMessage);
      }
      return;
    }

    if (_nav2WasUnavailable && !_nav2AvailableNotified) {
      _nav2AvailableNotified = true;
      _addLog(LogFilter.connection, _nav2AvailableMessage);
    }
    _nav2WasUnavailable = false;
  }

  void _resetNav2NotificationState() {
    _nav2UnavailableNotified = false;
    _nav2AvailableNotified = false;
    _nav2WasUnavailable = false;
  }

  // robot_health_monitor_node의 상태 요약입니다. 1 Hz로 상시 발행되므로 앱이
  // 재접속하면 1초 안에 화면이 복원됩니다.
  //
  // 이 값으로 로그를 남기지 않습니다. 1 Hz로 들어오는 상태 스냅샷이라 로그에 쌓으면
  // 초당 한 건씩 늘어납니다. 로그는 /robot/events가 담당합니다.
  void _handleRobotHealth(Map<String, Object?> message) {
    _health = RobotHealth.fromRosMsg(message);
    notifyListeners();
  }

  // 결함 전이 이벤트입니다.
  //
  // [중요] 여기서 같은 사유를 다시 억제하지 않습니다. 로봇의 event_deduplicator가
  // 이미 전이 시점에만 발행하므로 초당 쌓일 일이 없고, 앱에서 또 억제하면 reminder
  // 이벤트가 사라져 오래 지속되는 결함을 관리자가 놓칩니다.
  //
  // /robot_status.error_reason 경로는 다릅니다. 그쪽은 10 Hz로 상시 발행되므로
  // _logErrorReasonChange가 억제를 담당합니다. 두 경로의 억제 지점이 다릅니다.
  void _handleRobotEvent(Map<String, Object?> message) {
    final event = RobotEvent.fromRosMsg(message, id: _uuid.v4());

    if (event.belongsInHistory) {
      _healthEvents.insert(0, event);
      if (_healthEvents.length > _maxHealthEvents) {
        _healthEvents.removeRange(_maxHealthEvents, _healthEvents.length);
      }
    }

    // 주행을 막는 등급만 기존 알림 목록에도 남깁니다. WARN·DEGRADED까지 넣으면
    // 알림이 진단 화면과 중복되면서 정작 중요한 항목이 묻힙니다.
    if (event.fault.severity.blocksDriving &&
        event.transition != FaultTransition.reminder) {
      final prefix = event.transition == FaultTransition.cleared ? '해소' : '발생';
      _addLog(
        LogFilter.emergencyStop,
        '[$prefix] ${event.fault.componentLabelText}: ${event.fault.detail}',
      );
    }

    notifyListeners();
  }

  // rosbridge 없이 화면 표시 규칙을 검증하기 위한 주입 지점입니다. 핸들러를 public으로
  // 열지 않는 이유는 rosbridge 외의 호출자가 상태를 바꾸면 안 되기 때문입니다.
  @visibleForTesting
  void handleRobotHealthForTest(Map<String, Object?> message) =>
      _handleRobotHealth(message);

  @visibleForTesting
  void handleRobotEventForTest(Map<String, Object?> message) =>
      _handleRobotEvent(message);

  @visibleForTesting
  void handleMapListForTest(Map<String, Object?> message) =>
      _handleMapList(message);

  @visibleForTesting
  void handleLocationListForTest(Map<String, Object?> message) =>
      _handleLocationList(message);

  @visibleForTesting
  void handleRobotStatusForTest(Map<String, Object?> message) =>
      _handleRobotStatus(message);

  // /app_estop_state 주기 브로드캐스트로 오버레이 상태를 노드 실제 상태에 맞춥니다.
  // 앱이 비상정지 중에 재접속하면 이 토픽으로 활성 오버레이를 복구합니다.
  void _handleEmergencyStopState(Map<String, Object?> message) {
    final active = message['active'] == true;
    final stateMessage = message['message'] as String? ?? '';

    // 서비스 호출이 진행 중일 때는 그 응답이 상태를 결정하므로 브로드캐스트는 무시합니다.
    if (_emergencyStopState == EmergencyStopState.activating ||
        _emergencyStopState == EmergencyStopState.releasing) {
      return;
    }

    if (active) {
      // 노드가 활성이라고 알리면(정지가 유지되는 안전한 사실) 활성 오버레이로 맞춥니다.
      if (_emergencyStopState != EmergencyStopState.active) {
        _setEmergencyStopState(
          EmergencyStopState.active,
          stateMessage.isEmpty ? '비상정지가 활성화되어 있습니다.' : stateMessage,
        );
      }
      return;
    }

    // 노드가 비활성이라고 알릴 때: 실패 알림은 사용자가 닫기 전까지 유지합니다.
    if (_emergencyStopState == EmergencyStopState.activationFailed ||
        _emergencyStopState == EmergencyStopState.releaseFailed) {
      return;
    }
    if (_emergencyStopState != EmergencyStopState.inactive) {
      _setEmergencyStopState(EmergencyStopState.inactive, '');
    }
  }

  void _setEmergencyStopState(
    EmergencyStopState next,
    String message,
  ) {
    if (_emergencyStopState == next && _emergencyStopMessage == message) {
      return;
    }
    _emergencyStopState = next;
    _emergencyStopMessage = message;
    notifyListeners();
  }

  void _setConnectionState(RosConnectionState next, String detail) {
    if (_connectionState == next && _connectionDetail == detail) {
      return;
    }
    _connectionState = next;
    _connectionDetail = detail;
    // 끊긴 뒤에도 마지막 로봇 상태가 남아 현재 상태처럼 보이던 문제를 막습니다.
    if (next != RosConnectionState.connected) {
      _clearRobotRuntimeState();
    }
    _addLog(LogFilter.connection, detail);
    notifyListeners();
  }

  void _addLog(LogFilter filter, String message) {
    if (message.trim().isEmpty) {
      return;
    }
    _logs.insert(
      0,
      SupervisorLog(
        id: _uuid.v4(),
        filter: filter,
        message: message,
        createdAt: DateTime.now(),
      ),
    );
    if (_logs.length > _maxLogs) {
      _logs.removeRange(_maxLogs, _logs.length);
    }
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    unawaited(_client?.close());
    super.dispose();
  }
}
