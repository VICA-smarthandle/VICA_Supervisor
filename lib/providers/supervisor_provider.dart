import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/app_settings.dart';
import '../core/json_read.dart';
import '../core/log_filter.dart';
import '../models/delivery_job.dart';
import '../models/goal_event.dart';
import '../models/home_position.dart';
import '../models/keepout_zone.dart';
import '../models/location_point.dart';
import '../models/robot_event.dart';
import '../models/robot_health.dart';
import '../models/map_preview.dart';
import '../models/pose_check_result.dart';
import '../models/mapping_status.dart';
import '../models/robot_status.dart';
import '../models/route_edit.dart';
import '../models/route_graph.dart';
import '../models/stack_status.dart';
import '../models/supervisor_log.dart';
import '../models/vica_map.dart';
import '../ros/ros_bridge_client.dart';
import '../services/delivery_job_store.dart';
import '../services/delivery_notifier.dart';
import '../services/map_wall_mask.dart';
import '../services/route_graph_loader.dart';

enum EmergencyStopState {
  inactive,
  activating,
  active,
  releasing,
  activationFailed,
  releaseFailed,
}

/// 금지구역 화면의 상태입니다. 버튼 문구와 잠금이 이 값 하나로 정해집니다.
enum KeepoutSaveState {
  idle,
  loading,
  editing,
  saving,
  succeeded,
  failed,
}

/// 레일 칸의 상태입니다(2026-09-30). 버튼 잠금과 문구가 이 값으로 정해집니다.
enum RouteEditState {
  idle,
  drafting,
  editing,
  saving,
  succeeded,
  failed,
}

/// [SupervisorProvider.saveRoute] 결과. 화면이 팝업(F)을 띄울지 이것으로 정합니다.
enum RouteSaveOutcome { saved, conflict, checkFailed, failed }

/// 레일 서비스 한 번 부르기. 시험은 rosbridge 없이 이것만 바꿔 끼웁니다.
typedef RouteServiceCall = Future<Map<String, Object?>> Function(
  String service,
  String type,
  Map<String, Object?> args,
  Duration timeout,
);

/// 지도 그림에서 벽 지도를 만듭니다. 시험은 이것을 바꿔 끼웁니다.
typedef WallMaskLoader = Future<MapWallMask?> Function(
    String imageUrl, VicaMap map);

/// 레일 칸이 받아 둔 로봇 쪽 레일 정보(GetRoute).
class RouteInfo {
  const RouteInfo({
    required this.found,
    this.sketch = RouteSketch.empty,
    this.version = '',
    this.status = 'none',
    this.checks = RouteChecks.none,
  });

  final bool found;
  final RouteSketch sketch;
  final String version;

  /// applied | apply_pending | none
  final String status;
  final RouteChecks checks;
}

class SupervisorProvider extends ChangeNotifier {
  /// [deliveryNotifier] 를 안 주면 기기에 맞는 것을 고릅니다 — 안드로이드는 SMS,
  SupervisorProvider({
    DeliveryNotifier? deliveryNotifier,
    DeliveryJobStore? deliveryJobStore,
    RouteGraphLoader? routeGraphLoader,
    RouteServiceCall? routeServiceCall,
    WallMaskLoader? wallMaskLoader,
    RosChannelConnector? rosChannelConnector,
  })  : _deliveryNotifier = deliveryNotifier ?? createDeliveryNotifier(),
        _deliveryStore =
            deliveryJobStore ?? const SharedPreferencesDeliveryJobStore(),
        _routeGraphLoader = routeGraphLoader ?? const RouteGraphLoader(),
        _routeServiceCall = routeServiceCall,
        _wallMaskLoader = wallMaskLoader ?? MapWallMask.load,
        _rosChannelConnector = rosChannelConnector;

  /// rosbridge 소켓을 여는 함수. null 이면 실제 WebSocket 을 엽니다. 시험은 가짜
  final RosChannelConnector? _rosChannelConnector;

  static const _nav2UnavailableReason = 'Nav2/AMCL 미실행';
  static const _nav2UnavailableMessage =
      'Nav2가 실행되지 않아 현재 위치와 주행 이벤트를 받을 수 없습니다.';
  static const _nav2AvailableMessage = 'Nav2가 실행되었습니다.';
  static const _noEventsRecordedReason = 'no events recorded';

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
    'no_home': '홈 위치가 지정되지 않았습니다. 지도 설정 화면에서 먼저 지정하세요.',
    'already_home_bound': '이미 홈으로 돌아가는 중입니다.',
    'busy_approaching': '사용자에게 다가가는 중이라 지금은 홈으로 부를 수 없습니다.',
    'no_wait_spot': '이 장소에는 대기 장소가 없습니다. 목록을 새로고침하세요.',
  };

  /// 대기 장소 가보기에서만 다르게 읽는 사유. 미션은 대기 장소로 가는 길을 '안내가
  static const _waitSpotGateMessages = <String, String>{
    'busy_navigating': '안내 중이거나 사용자를 기다리는 중이라 지금은 가볼 수 없습니다.',
  };

  final _uuid = const Uuid();
  AppSettings? _lastSettings;
  RosBridgeClient? _client;
  RosBridgeClient? _closingClient;
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
  static const _reconnectStableAfter = Duration(seconds: 10);
  Timer? _reconnectStableTimer;
  EmergencyStopState _emergencyStopState = EmergencyStopState.inactive;
  String _emergencyStopMessage = '';
  List<String> _emergencyStopSources = const [];
  bool _nav2UnavailableNotified = false;
  bool _nav2AvailableNotified = false;
  bool _nav2WasUnavailable = false;
  String _lastLoggedErrorReason = '';

  MappingStatus? _mappingStatus;
  MapPreview? _mapPreview;

  StackStatus? _stackStatus;
  bool _stackStatusLoading = false;
  String _stackStatusError = '';

  RobotHealth? _health;
  final List<RobotEvent> _healthEvents = [];

  static const _maxHealthEvents = 100;
  static const _maxLogs = 100;

  MappingStatus? get mappingStatus => _mappingStatus;
  MapPreview? get mapPreview => _mapPreview;

  StackStatus? get stackStatus => _stackStatus;
  bool get stackStatusLoading => _stackStatusLoading;
  String get stackStatusError => _stackStatusError;

  /// 지금 연결에 실제로 쓴 rosbridge 주소. 연결한 적이 없으면 빈 문자열입니다.
  String get connectedUrl => _lastSettings?.rosBridgeUrl ?? '';

  RosConnectionState get connectionState => _connectionState;
  String get connectionDetail => _connectionDetail;
  EmergencyStopState get emergencyStopState => _emergencyStopState;
  String get emergencyStopMessage => _emergencyStopMessage;

  /// 이번 비상정지가 **현장에서** 걸려 관리자가 와야 하는가.
  bool get emergencyCalledAdmin {
    if (_emergencyStopState != EmergencyStopState.active) {
      return false;
    }
    return emergencyTipped ||
        _emergencyStopSources.any(
          (source) => source == 'physical_f1' || source == 'voice',
        );
  }

  /// 이번 비상정지 원인에 몸통 넘어짐이 있는가(2026-10-15).
  bool get emergencyTipped =>
      _emergencyStopSources.any((source) => source == 'tipped');

  bool get emergencyOverlayVisible =>
      _emergencyStopState != EmergencyStopState.inactive;
  List<VicaMap> get maps => _maps;
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

  /// 실제로 고른 지도 id. [selectedMap] 은 고른 지도가 목록에 없으면 첫 지도로 대신하므로,
  String? get selectedMapId => _selectedMapId;

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

  Future<void> connect(AppSettings settings) async {
    _lastSettings = settings;
    _reconnectTimer?.cancel();
    _reconnectStableTimer?.cancel();
    _reconnectAttempts = 0;
    _resetNav2NotificationState();
    final oldClient = _client;
    _client = null;
    await _closeClient(oldClient);
    late final RosBridgeClient client;
    client = RosBridgeClient(
      onState: (state, detail) =>
          _handleClientState(client, settings, state, detail),
      connector: _rosChannelConnector,
    );
    _client = client;
    await client.connect(settings.rosBridgeUrl);
    if (!identical(_client, client)) {
      await client.close();
      return;
    }
    if (_connectionState == RosConnectionState.connected) {
      _subscribeRequiredTopics(settings);
      _requestSyncAfterConnect(settings);
    }
  }

  void _handleClientState(
    RosBridgeClient client,
    AppSettings settings,
    RosConnectionState state,
    String detail,
  ) {
    if (_disposed) {
      return;
    }
    final current = identical(client, _client);
    if (!current && !identical(client, _closingClient)) {
      return;
    }
    _setConnectionState(state, detail);
    if (!current) {
      return;
    }
    if (state == RosConnectionState.connected) {
      _reconnectStableTimer?.cancel();
      _reconnectStableTimer =
          Timer(_reconnectStableAfter, () => _reconnectAttempts = 0);
    } else if (state == RosConnectionState.disconnected ||
        state == RosConnectionState.failed) {
      _reconnectStableTimer?.cancel();
      _reconnectStableTimer = null;
      _scheduleReconnect(settings);
    }
  }

  Future<void> _closeClient(RosBridgeClient? client) async {
    if (client == null) {
      return;
    }
    _closingClient = client;
    try {
      await client.close();
    } finally {
      if (identical(_closingClient, client)) {
        _closingClient = null;
      }
    }
  }

  void _requestSyncAfterConnect(AppSettings settings) {
    if (settings.autoRequestMapList) {
      requestMapList(settings);
    }
    final mapId = _selectedMapId;
    if (mapId != null) {
      refreshMapData(settings, mapId, auto: true);
    }
  }

  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectStableTimer?.cancel();
    _reconnectStableTimer = null;
    _reconnectAttempts = 0;
    final client = _client;
    _client = null;
    await _closeClient(client);
    _clearRobotRuntimeState();
    notifyListeners();
  }

  void _clearRobotRuntimeState() {
    _lastLoggedErrorReason = '';
    _resetNav2NotificationState();
    _health = null;
    _pausedByEvent = false;
    _teleopTimer?.cancel();
    _teleopTimer = null;
    _teleopAdvertised = false;
    _mappingStatus = null;
    _mapPreview = null;
    _poseCheck = null;
    _poseChecking = false;
    _stackStatus = null;
    _stackStatusError = '';
    if (_robotsById.isEmpty) {
      return;
    }
    _robotsById.clear();
  }

  void _scheduleReconnect(AppSettings settings) {
    if (_reconnectTimer?.isActive ?? false) {
      return;
    }
    if (_client == null ||
        _reconnectAttempts >= settings.maxReconnectAttempts) {
      return;
    }
    _reconnectAttempts += 1;
    _reconnectTimer = Timer(const Duration(seconds: 3), () async {
      final client = _client;
      if (client == null) {
        return;
      }
      await client.connect(settings.rosBridgeUrl);
      if (identical(_client, client) &&
          _connectionState == RosConnectionState.connected) {
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
      ..subscribe(
        topic: settings.mappingStatusTopic,
        handler: _handleMappingStatus,
      )
      ..subscribe(
        topic: settings.mapPreviewTopic,
        handler: _handleMapPreview,
      )
      ..subscribe(
        topic: settings.robotHealthTopic,
        handler: _handleRobotHealth,
        type: 'vica_interfaces/msg/RobotHealth',
      )
      ..subscribe(
        topic: settings.robotEventsTopic,
        handler: _handleRobotEvent,
        type: 'vica_interfaces/msg/RobotEvent',
      )
      ..subscribe(
        topic: settings.goalEventTopic,
        handler: _handleGoalEvent,
      )
      ..subscribe(
        topic: settings.keepoutStateTopic,
        handler: _handleKeepoutState,
      )
      ..subscribe(
        topic: settings.routeStateTopic,
        handler: _handleRouteState,
      )
      ..subscribe(
        topic: settings.routeSavedTopic,
        handler: _handleRouteSaved,
      )
      ..subscribe(
        topic: settings.deliverySmsResultTopic,
        handler: _handleDeliverySmsResult,
      );
  }

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

  /// 지도에 딸린 것을 **한꺼번에** 다시 받아옵니다 — 장소·홈·금지구역.
  void refreshMapData(
    AppSettings settings,
    String mapId, {
    bool auto = false,
  }) {
    if (!auto || settings.autoRequestLocationList) {
      requestLocationList(settings, mapId);
    }
    unawaited(refreshHome(settings, mapId));
    unawaited(requestKeepoutList(settings, mapId));
    unawaited(loadRouteGraph(settings, mapId));
    if (!auto) {
      _wallMaskFailed.remove(mapId);
    }
  }

  final RouteGraphLoader _routeGraphLoader;
  final Map<String, RouteGraph> _routeGraphsByMap = {};

  /// 이 지도의 레일. 없으면 null 이고 오류가 아닙니다.
  RouteGraph? routeGraphFor(String? mapId) =>
      mapId == null ? null : _routeGraphsByMap[mapId];

  /// 레일 파일을 받아 둡니다. 지도 데이터를 새로 받을 때마다 함께 부릅니다.
  Future<void> loadRouteGraph(AppSettings settings, String mapId) async {
    final graph = await _routeGraphLoader.load(settings.mapHttpBaseUrl, mapId);
    final before = _routeGraphsByMap[mapId];
    if (graph == null) {
      _routeGraphsByMap.remove(mapId);
    } else {
      _routeGraphsByMap[mapId] = graph;
    }
    if (before != null || graph != null) {
      notifyListeners();
    }
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
    _home = null;
    _homeMapId = '';
    _keepoutEditing = false;
    _keepoutDragStart = null;
    _keepoutDragCurrent = null;
    _selectedKeepoutZoneId = null;
    _keepoutState = KeepoutSaveState.idle;
    _keepoutMessage = '';
    _keepoutMaskApplied = false;
    notifyListeners();
    if (mapId != null) {
      refreshMapData(settings, mapId, auto: true);
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

  void saveDraftLocation(AppSettings settings) {
    final draft = _draftLocation;
    if (draft == null) {
      return;
    }
    _client?.publishJsonString(
      topic: settings.saveLocationTopic,
      payload: _locationPayload(draft),
    );
    _addLog(LogFilter.coordinateTransfer, '${draft.name} 장소 저장 요청 전송');
    _draftLocation = null;
    notifyListeners();
  }

  /// 저장된 장소를 고쳐 **바로** ROS 에 저장합니다(사용자 결정 2026-09-03).
  (bool, String) saveLocation(AppSettings settings, LocationPoint location) {
    final client = _client;
    if (client == null || _connectionState != RosConnectionState.connected) {
      return (false, 'rosbridge 연결이 없어 ${location.name} 을(를) 저장하지 못했습니다.');
    }
    client.publishJsonString(
      topic: settings.saveLocationTopic,
      payload: _locationPayload(location),
    );
    _addLog(LogFilter.coordinateTransfer, '${location.name} 수정 저장 요청 전송');
    notifyListeners();
    return (true, '${location.name} 수정을 저장했습니다.');
  }

  /// /save_location 에 싣는 모양. 새 저장과 수정 저장이 같은 모양을 씁니다.
  Map<String, Object?> _locationPayload(LocationPoint location) {
    final destination = location.toJson();
    final pose = Map<String, Object>.from(
      destination['pose']! as Map<String, Object>,
    );
    pose['yaw'] = _normalizeYawDegrees(location.yaw);
    return {
      'request_id': _uuid.v4(),
      'map_id': location.mapId,
      ...destination,
      'pose': pose,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  double _normalizeYawDegrees(double yaw) {
    final normalized = yaw % 360.0;
    return normalized < 0 ? normalized + 360.0 : normalized;
  }

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

  Future<String> requestDestination(
    AppSettings settings,
    LocationPoint location,
  ) async {
    final (_, message) = await _callRequestDestination(
      settings,
      location,
      service: settings.missionRequestService,
    );
    return message;
  }

  /// 대기 장소로 가보기(2026-10-07, 지도 설정). [location] 은 대기 장소가 딸린
  Future<String> requestWaitSpot(
    AppSettings settings,
    LocationPoint location,
  ) async {
    final (_, message) = await _callRequestDestination(
      settings,
      location,
      service: settings.missionWaitSpotService,
      gateMessages: _waitSpotGateMessages,
    );
    return message;
  }

  /// 벽 지도(지도 그림의 검은 칸). 대기 장소의 벽 간격을 잴 때 씁니다. 아직 없으면
  MapWallMask? wallMaskFor(AppSettings settings, VicaMap map) {
    final mask = _wallMasks[map.mapId];
    if (mask == null &&
        !_wallMaskLoading.contains(map.mapId) &&
        !_wallMaskFailed.contains(map.mapId)) {
      _wallMaskLoading.add(map.mapId);
      unawaited(_loadWallMask(settings, map).whenComplete(() {
        _wallMaskLoading.remove(map.mapId);
        if (!_wallMasks.containsKey(map.mapId)) {
          _wallMaskFailed.add(map.mapId);
        }
        notifyListeners();
      }));
    }
    return mask;
  }

  /// 이 지도의 벽 지도를 받지 못했는가. 그때 대기 장소 저장은 벽 간격 없이 됩니다.
  bool wallMaskFailed(String mapId) => _wallMaskFailed.contains(mapId);

  /// 목적지 요청 서비스 호출. 원격 주행과 물류 배송이 같은 문으로 나갑니다.
  Future<(bool, String)> _callRequestDestination(
    AppSettings settings,
    LocationPoint location, {
    required String service,
    Map<String, String> gateMessages = const {},
  }) async {
    final reply = await _callService(
      service: service,
      type: 'vica_interfaces/srv/RequestDestination',
      args: {
        'request_id': _uuid.v4(),
        'map_id': location.mapId,
        'destination_id': location.locationId,
      },
      describe: (response) => response.message.isEmpty
          ? (response.accepted ? '주행 요청을 수락했습니다.' : '주행 요청이 거부되었습니다.')
          : _localizeGateReason(response.message, gateMessages),
      failurePrefix: 'Mission Manager 목적지 요청 실패',
    );
    return (reply.accepted, reply.message);
  }

  Future<String> cancelDestination(AppSettings settings) {
    return _sendMissionCommand(settings.missionCancelService, '주행을 취소했습니다.');
  }

  Future<String> pauseNavigation(AppSettings settings) {
    return _sendMissionCommand(settings.missionPauseService, '주행을 일시정지했습니다.');
  }

  Future<String> resumeNavigation(AppSettings settings) {
    return _sendMissionCommand(settings.missionResumeService, '다시 출발합니다.');
  }

  /// 젯슨의 노드 목록을 조회해 어떤 스택이 떠 있는지 갱신합니다.
  Future<void> refreshStackStatus() async {
    final client = _client;
    if (client == null || _connectionState != RosConnectionState.connected) {
      _stackStatus = null;
      _stackStatusError = '';
      _stackStatusLoading = false;
      notifyListeners();
      return;
    }

    _stackStatusLoading = true;
    _stackStatusError = '';
    notifyListeners();

    try {
      final nodesResponse = await client.callService(
        service: '/rosapi/nodes',
        type: 'rosapi_msgs/srv/Nodes',
      );
      List<String> odomPublishers = const [];
      try {
        final publishersResponse = await client.callService(
          service: '/rosapi/publishers',
          type: 'rosapi_msgs/srv/Publishers',
          args: const {'topic': '/odom'},
        );
        odomPublishers =
            jsonStringList(publishersResponse.values['publishers']);
      } catch (_) {
        odomPublishers = const [];
      }

      _stackStatus = StackStatus(
        nodes: jsonStringList(nodesResponse.values['nodes']),
        odomPublishers: odomPublishers,
      );
      _stackStatusError = '';
    } catch (error) {
      _stackStatus = null;
      _stackStatusError = '노드 목록을 조회하지 못했습니다: $error';
    } finally {
      _stackStatusLoading = false;
      notifyListeners();
    }
  }

  /// 지도의 표시 이름(한글 가능)을 바꿉니다. 파일·URL·장소는 map_id 로 묶여
  Future<String> renameMap(
    AppSettings settings,
    String mapId,
    String displayName,
  ) async {
    final reply = await _callService(
      service: settings.renameMapService,
      type: 'vica_interfaces/srv/RenameMap',
      args: {'map_id': mapId, 'display_name': displayName},
      describe: (response) => response.message.isEmpty
          ? (response.accepted ? '이름을 바꿨습니다.' : '이름 바꾸기가 거부되었습니다.')
          : response.message,
      failurePrefix: '이름 바꾸기 요청 실패',
    );
    return reply.message;
  }

  /// 저장된 지도를 지웁니다. 되돌릴 수 없습니다.
  Future<String> deleteMap(
    AppSettings settings,
    String mapId, {
    required bool deleteDestinations,
  }) async {
    final reply = await _callService(
      service: settings.deleteMapService,
      type: 'vica_interfaces/srv/DeleteMap',
      args: {
        'map_id': mapId,
        'delete_destinations': deleteDestinations,
      },
      describe: (response) => response.message.isEmpty
          ? (response.accepted ? '지도가 삭제되었습니다.' : '삭제가 거부되었습니다.')
          : response.message,
      failurePrefix: '지도 삭제 요청 실패',
      onAccepted: (_) {
        if (_selectedMapId == mapId) {
          _selectedMapId = null;
          _selectedLocationId = null;
        }
      },
    );
    return reply.message;
  }

  HomePosition? _home;
  bool _homeBusy = false;
  String _homeMapId = '';

  HomePosition? get home => _home;
  bool get homeBusy => _homeBusy;

  /// 지금 들고 있는 홈이 [mapId] 의 것인가.
  bool homeBelongsTo(String? mapId) => mapId != null && _homeMapId == mapId;

  /// 지도에 그릴 홈 점. 지도 설정·원격 주행·물류 배송이 전부 이 하나를 씁니다.
  Offset? homePointFor(String? mapId) {
    final home = _home;
    if (home == null || !homeBelongsTo(mapId)) {
      return null;
    }
    return Offset(home.x, home.y);
  }

  /// 젯슨에서 홈을 읽어옵니다. 없으면 [home] 이 null 이 되며 오류가 아닙니다.
  Future<void> refreshHome(AppSettings settings, String mapId) async {
    final client = _client;
    if (client == null || _connectionState != RosConnectionState.connected) {
      return;
    }
    _homeBusy = true;
    notifyListeners();
    try {
      final response = await client.callService(
        service: settings.homeGetService,
        type: 'vica_interfaces/srv/GetHome',
        args: {'map_id': mapId},
      );
      _homeMapId = mapId;
      _home = response.values['exists'] == true
          ? HomePosition.fromValues(response.values)
          : null;
    } catch (error) {
      _addLog(LogFilter.coordinateTransfer, '홈 위치를 읽지 못했습니다: $error');
    } finally {
      _homeBusy = false;
      notifyListeners();
    }
  }

  /// 홈을 저장합니다. 저장 직후 [HomePosition.visitedOk] 는 항상 false 입니다.
  Future<String> saveHome(
    AppSettings settings, {
    required String mapId,
    required double x,
    required double y,
    required double yawDeg,
    required HomeSource source,
    double score = 0,
    String label = '',
  }) async {
    final reply = await _callService(
      service: settings.homeSaveService,
      type: 'vica_interfaces/srv/SaveHome',
      args: {
        'map_id': mapId,
        'x': x,
        'y': y,
        'yaw': yawDeg,
        'source': source.wire,
        'score': score,
        'label': label,
      },
      describe: (response) => response.message.isEmpty
          ? (response.accepted ? '홈 위치가 삭제되었습니다.' : '홈 위치 삭제가 거부되었습니다.')
          : response.message,
      failurePrefix: '홈 저장 실패',
      onAccepted: (_) {
        _homeMapId = mapId;
        _home = HomePosition(
          x: x,
          y: y,
          yaw: yawDeg,
          source: source,
          score: score,
          label: label,
          visitedOk: false,
          savedAt: DateTime.now().toIso8601String(),
        );
      },
      busy: _setHomeBusy,
    );
    return reply.message;
  }

  Future<String> deleteHome(AppSettings settings, String mapId) async {
    final reply = await _callService(
      service: settings.homeDeleteService,
      type: 'vica_interfaces/srv/DeleteHome',
      args: {'map_id': mapId},
      describe: (response) => response.message.isEmpty
          ? (response.accepted ? '홈 위치가 삭제되었습니다.' : '홈 위치 삭제가 거부되었습니다.')
          : response.message,
      failurePrefix: '홈 삭제 실패',
      onAccepted: (_) => _home = null,
      busy: _setHomeBusy,
    );
    return reply.message;
  }

  void _setHomeBusy(bool busy) {
    _homeBusy = busy;
    notifyListeners();
  }

  /// 로봇을 홈으로 보냅니다. **관리자만 부를 수 있는 경로입니다.**
  Future<String> returnHome(AppSettings settings) async {
    final (_, message) = await _callReturnHome(settings);
    return message;
  }

  /// 홈 복귀 서비스 호출. 관리자 버튼과 배송 자동 복귀가 같은 문으로 나갑니다.
  Future<(bool, String)> _callReturnHome(AppSettings settings) async {
    final reply = await _callService(
      service: settings.missionReturnHomeService,
      type: 'vica_interfaces/srv/MissionCommand',
      args: {'request_id': _uuid.v4()},
      describe: (response) => response.message.isEmpty
          ? (response.accepted ? '홈으로 복귀합니다.' : '홈 복귀 요청이 거부되었습니다.')
          : _localizeGateReason(response.message),
      failurePrefix: '홈 복귀 요청 실패',
    );
    return (reply.accepted, reply.message);
  }

  DeliveryJob? _delivery;
  DeliveryNotifier _deliveryNotifier;
  DeliveryNotice? _pendingDeliveryNotice;
  final DeliveryJobStore _deliveryStore;

  /// 저장소에서 되살린 배송을 아직 로봇 상태와 대조하지 못했다. 앱이 꺼진 사이의
  bool _deliveryNeedsReconcile = false;

  /// 도착 뒤 홈으로 출발시키는 시계. 배송을 새로 시작하거나 지우거나 관리자가
  Timer? _deliveryReturnTimer;

  /// 다른 화면(웹 등)이 보낸 배송의 도착 문자를 이 폰이 대신 보낸 도착들(2026-10-10).
  final Set<String> _relaySentKeys = {};

  /// 관리자 유심 폰이 알려 온 도착 문자 결과와, 그것을 기다리는 이 화면의 배송.
  final Map<String, DeliveryNotifyResult> _relayedSmsResults = {};
  final Map<String, Completer<DeliveryNotifyResult>> _relayedSmsWaiters = {};

  /// 정리됐는가. 도착 문자 결과는 비동기로 늦게 와서(최대 30초) 화면이 닫힌 뒤일 수 있다.
  bool _disposed = false;

  /// 배송 기억을 바꾸는 유일한 자리. 바꿀 때마다 기기 저장소에도 적어 앱을
  void _setDelivery(DeliveryJob? job) {
    _delivery = job;
    unawaited(_deliveryStore.save(job));
  }

  /// 젯슨이 지금 쓰는 지도(maps/CURRENT_MAP). 지도 목록 노드가 실어 보냅니다.
  String _currentMapId = '';
  String get currentMapId => _currentMapId;

  /// 앱을 켤 때 지난 배송을 기기 저장소에서 되살립니다. main 이 연결 전에 부릅니다.
  Future<void> restoreDelivery() async {
    final job = await _deliveryStore.load();
    if (job == null) {
      return;
    }
    _delivery = job;
    _deliveryNeedsReconcile = !job.phase.isFinished;
    final name = job.destination.name;
    if (job.isWaitingToReturn) {
      final left = job.returnAt!.difference(DateTime.now());
      if (left > Duration.zero) {
        _scheduleDeliveryReturn(job, delay: left);
        _addLog(
            LogFilter.delivery, '$name 배송 이어받음 — ${left.inSeconds}초 뒤 홈 복귀');
      } else {
        _setDelivery(job.copyWith(
          clearReturnAt: true,
          returnNote: '앱이 꺼진 사이 복귀 예정 시각이 지났습니다. 홈으로 복귀를 눌러 주세요.',
        ));
        _addLog(LogFilter.delivery, '$name 배송 이어받음 — 복귀 예정 시각이 지나 기다립니다');
      }
    } else {
      _addLog(LogFilter.delivery, '$name 배송 이어받음 (${job.phase.label})');
    }
    notifyListeners();
  }

  /// 되살린 배송을 로봇의 지금 상태와 맞춥니다. 첫 /robot_status 에서 한 번.
  void _reconcileRestoredDelivery(RobotStatus robot) {
    _deliveryNeedsReconcile = false;
    final job = _delivery;
    if (job == null) {
      return;
    }
    final goal = robot.currentGoal.trim();
    final name = job.destination.name;
    switch (job.phase) {
      case DeliveryPhase.driving:
        if (goal == name) {
          _addLog(LogFilter.delivery, '$name 배송 주행이 이어지고 있습니다');
          return;
        }
        _setDelivery(job.copyWith(
          phase: DeliveryPhase.unconfirmed,
          abortReason: goal.isEmpty
              ? '앱이 꺼진 사이 주행이 끝났습니다. 문자는 보내지 않았습니다.'
              : '로봇이 다른 곳($goal)으로 가고 있습니다. 문자는 보내지 않았습니다.',
        ));
        _addLog(LogFilter.delivery, '$name 배송 결과를 확인하지 못했습니다 — 관리자 확인 필요');
      case DeliveryPhase.returning:
        if (goal.isNotEmpty) {
          _addLog(LogFilter.delivery, '$name 배송 홈 복귀가 이어지고 있습니다');
          return;
        }
        _setDelivery(job.copyWith(
          phase: DeliveryPhase.arrived,
          clearReturnAt: true,
          returnNote:
              '앱이 꺼진 사이 홈 복귀가 끝났거나 멈췄습니다. 로봇 위치 확인 후 복귀를 삭제하거나 다시 보내세요.',
        ));
        _addLog(LogFilter.delivery, '$name 배송 홈 복귀 결과를 확인하지 못했습니다');
      default:
        return;
    }
  }

  /// '확인 필요' 배송을 관리자가 도착으로 처리합니다. 로봇이 문 앞에 있는 것을
  Future<String> confirmDeliveryArrival() async {
    final job = _delivery;
    if (job == null || job.phase != DeliveryPhase.unconfirmed) {
      return '도착 처리할 배송이 없습니다.';
    }
    _markDeliveryArrived(job, sendText: !job.notified);
    return '${job.destination.name} 도착으로 처리했습니다.';
  }

  /// 지금 기억하고 있는 배송. 끝난 뒤에도 관리자가 '지우기'를 누를 때까지 남아
  DeliveryJob? get delivery => _delivery;

  /// 발송 수단 이름. 화면 배지에 씁니다.
  String get deliveryNotifierLabel => _deliveryNotifier.modeLabel;

  /// 아직 화면이 보여주지 않은 도착 문자 결과. 화면이 팝업을 띄우고
  DeliveryNotice? get pendingDeliveryNotice => _pendingDeliveryNotice;

  void consumeDeliveryNotice() {
    if (_pendingDeliveryNotice == null) {
      return;
    }
    _pendingDeliveryNotice = null;
    notifyListeners();
  }

  /// 배송 출발. 주행 요청이 **수락됐을 때만** 배송을 기억합니다.
  Future<String> startDelivery(
    AppSettings settings,
    LocationPoint location,
  ) async {
    if (!location.canReceiveDelivery) {
      return '${location.name}에는 도착 문자 연락처가 없습니다. 지도 설정에서 넣어 주세요.';
    }
    final current = _delivery;
    if (current != null && !current.phase.isFinished) {
      return '${current.destination.name} 배송이 아직 끝나지 않았습니다 (${current.phase.label}).';
    }
    final (accepted, message) = await _callRequestDestination(
      settings,
      location,
      service: settings.missionDeliveryService,
    );
    if (!accepted) {
      _addLog(LogFilter.delivery, '${location.name} 배송 출발 거부: $message');
      return message;
    }
    _cancelDeliveryReturnTimer();
    _setDelivery(DeliveryJob(destination: location, startedAt: DateTime.now()));
    _pendingDeliveryNotice = null;
    _addLog(LogFilter.delivery, '${location.name} 배송 출발');
    notifyListeners();
    return '${location.name}(으)로 배송을 시작합니다.';
  }

  /// 배송 표시를 지웁니다. 로봇이 움직이는 중(배송 중·홈 복귀 중)이거나 복귀
  void clearDelivery() {
    final current = _delivery;
    if (current == null ||
        current.isActive ||
        current.phase == DeliveryPhase.returning ||
        current.isWaitingToReturn) {
      return;
    }
    _cancelDeliveryReturnTimer();
    _setDelivery(null);
    _pendingDeliveryNotice = null;
    notifyListeners();
  }

  /// 복귀 대기를 건너뛰고 지금 홈으로 보냅니다.
  Future<String> returnDeliveryNow(AppSettings settings) async {
    final job = _delivery;
    if (job == null || job.phase != DeliveryPhase.arrived) {
      return '복귀시킬 배송이 없습니다.';
    }
    _cancelDeliveryReturnTimer();
    return _returnHomeForDelivery(settings);
  }

  /// 예정된 홈 복귀를 취소합니다. 로봇은 그 자리에 남고, 관리자가 나중에
  void cancelDeliveryReturn() {
    final job = _delivery;
    if (job == null || !job.isWaitingToReturn) {
      return;
    }
    _cancelDeliveryReturnTimer();
    _setDelivery(
        job.copyWith(clearReturnAt: true, returnNote: '관리자가 복귀를 취소했습니다.'));
    _addLog(LogFilter.delivery, '${job.destination.name} 배송 홈 복귀 취소(관리자)');
    notifyListeners();
  }

  void _cancelDeliveryReturnTimer() {
    _deliveryReturnTimer?.cancel();
    _deliveryReturnTimer = null;
  }

  /// 도착 뒤 [deliveryReturnDelay] 를 재기 시작합니다. 되살린 배송은 남은
  void _scheduleDeliveryReturn(DeliveryJob job, {Duration? delay}) {
    _cancelDeliveryReturnTimer();
    _deliveryReturnTimer = Timer(delay ?? deliveryReturnDelay, () {
      _deliveryReturnTimer = null;
      unawaited(_returnHomeForDelivery(_lastSettings ?? const AppSettings()));
    });
  }

  /// 홈 복귀 서비스를 부르고, 수락됐을 때만 '홈 복귀 중'으로 옮깁니다.
  Future<String> _returnHomeForDelivery(AppSettings settings) async {
    final job = _delivery;
    if (job == null || job.phase != DeliveryPhase.arrived) {
      return '복귀시킬 배송이 없습니다.';
    }
    final (accepted, message) = await _callReturnHome(settings);
    final current = _delivery;
    if (current == null || current.phase != DeliveryPhase.arrived) {
      return message;
    }
    if (accepted) {
      _setDelivery(current.copyWith(
        phase: DeliveryPhase.returning,
        clearReturnAt: true,
        returnNote: '',
      ));
      _addLog(LogFilter.delivery, '${job.destination.name} 배송 홈 복귀 출발');
    } else {
      _setDelivery(current.copyWith(clearReturnAt: true, returnNote: message));
      _addLog(
          LogFilter.delivery, '${job.destination.name} 배송 홈 복귀 거부: $message');
    }
    notifyListeners();
    return message;
  }

  /// goal 이벤트 중 이 배송에 해당하는 것만 골라 상태를 옮깁니다.
  void _applyGoalEventToDelivery(GoalEvent event) {
    final job = _delivery;
    if (job == null) {
      return;
    }
    if (job.phase == DeliveryPhase.returning) {
      _applyReturnEventToDelivery(job, event);
      return;
    }
    if (!job.isActive) {
      return;
    }
    if (!job.matches(
        locationId: event.locationId, name: event.destinationName)) {
      return;
    }
    switch (event.kind) {
      case GoalEventKind.succeeded:
        _markDeliveryArrived(job, sendText: true, arrival: event);
      case GoalEventKind.failed:
      case GoalEventKind.rejected:
      case GoalEventKind.canceled:
      case GoalEventKind.emergencyStopped:
        _setDelivery(job.copyWith(
          phase: DeliveryPhase.aborted,
          abortReason: event.reason.isEmpty ? event.title : event.reason,
        ));
        _addLog(
          LogFilter.delivery,
          '${job.destination.name} 배송 중단 (${event.title}) — 문자를 보내지 않았습니다',
        );
      default:
        break;
    }
  }

  /// 도착. 빗장(notified)을 먼저 겁니다 — 발송은 비동기라 같은 이벤트가 연달아
  void _markDeliveryArrived(
    DeliveryJob job, {
    required bool sendText,
    GoalEvent? arrival,
  }) {
    final now = DateTime.now();
    final arrived = job.copyWith(
      phase: DeliveryPhase.arrived,
      arrivedAt: now,
      notified: true,
      returnAt: now.add(deliveryReturnDelay),
      returnNote: '',
      abortReason: '',
    );
    _setDelivery(arrived);
    _addLog(
      LogFilter.delivery,
      '${job.destination.name} 배송 도착 — ${sendText ? '문자 발송 시도' : '문자 발송 완료'}, '
      '${deliveryReturnDelay.inMinutes}분 뒤 홈 복귀',
    );
    _scheduleDeliveryReturn(arrived);
    if (sendText) {
      unawaited(_notifyDeliveryArrival(arrived, arrival: arrival));
    }
    notifyListeners();
  }

  void _applyReturnEventToDelivery(DeliveryJob job, GoalEvent event) {
    switch (event.kind) {
      case GoalEventKind.returnHomeSucceeded:
        _setDelivery(job.copyWith(phase: DeliveryPhase.completed));
        _addLog(LogFilter.delivery, '${job.destination.name} 배송 완료 — 홈 도착');
      case GoalEventKind.returnHomeFailed:
      case GoalEventKind.returnHomeCanceled:
      case GoalEventKind.failed:
      case GoalEventKind.rejected:
      case GoalEventKind.canceled:
      case GoalEventKind.emergencyStopped:
      case GoalEventKind.stateIdle:
        _setDelivery(job.copyWith(
          phase: DeliveryPhase.arrived,
          clearReturnAt: true,
          returnNote: event.reason.isEmpty ? event.title : event.reason,
        ));
        _addLog(LogFilter.delivery,
            '${job.destination.name} 배송 홈 복귀 중단 (${event.title})');
      default:
        break;
    }
  }

  Future<void> _notifyDeliveryArrival(
    DeliveryJob job, {
    GoalEvent? arrival,
  }) async {
    final text = deliveryArrivalMessage(job.destination.name);
    final key = arrival == null ? null : _arrivalKey(arrival);
    DeliveryNotifyResult result;
    try {
      if (await _deliveryNotifier.needsRelay()) {
        result = await _awaitRelayedSmsResult(key);
      } else {
        result = await _deliveryNotifier.send(
          phone: job.destination.contactPhone,
          text: text,
        );
        if (arrival != null) {
          _publishRelayedSmsResult(arrival, result);
        }
      }
    } catch (error) {
      result = DeliveryNotifyResult(sent: false, detail: '발송 오류: $error');
    }
    if (_disposed) {
      return;
    }
    _addLog(
      LogFilter.delivery,
      '${job.destination.name} 도착 문자 ${result.sent ? '발송됨' : '미발송'}: ${result.detail}',
    );
    _pendingDeliveryNotice =
        DeliveryNotice(job: job, text: text, result: result);
    notifyListeners();
  }

  /// 화면끼리 같은 도착을 맞추는 열쇠 — 장소 id 와 로봇이 적은 시각. 둘 중 하나라도
  String? _arrivalKey(GoalEvent event) {
    if (event.locationId.isEmpty || event.robotStamp.isEmpty) {
      return null;
    }
    return '${event.locationId}|${event.robotStamp}';
  }

  /// 이 도착이 이 화면이 보낸 배송의 것인가.
  bool _isMyDeliveryArrival(GoalEvent event) {
    final job = _delivery;
    return job != null &&
        job.isActive &&
        job.matches(locationId: event.locationId, name: event.destinationName);
  }

  /// 관리자 유심 폰이 알려 올 결과를 기다립니다. [deliverySmsRelayWait] 안에 안 오면
  Future<DeliveryNotifyResult> _awaitRelayedSmsResult(String? key) {
    const noReply = DeliveryNotifyResult(
      sent: false,
      detail: deliverySmsNoReplyDetail,
    );
    if (key == null) {
      return Future.value(noReply);
    }
    final ready = _relayedSmsResults.remove(key);
    if (ready != null) {
      return Future.value(ready);
    }
    final waiter = _relayedSmsWaiters.putIfAbsent(key, Completer.new);
    return waiter.future.timeout(deliverySmsRelayWait, onTimeout: () {
      _relayedSmsWaiters.remove(key);
      return noReply;
    });
  }

  /// 관리자 유심 폰이 알린 결과. 기다리는 배송이 있으면 넘기고, 없으면 잠시 둡니다.
  void _handleDeliverySmsResult(Map<String, Object?> message) {
    final locationId = (message['location_id'] as String?)?.trim() ?? '';
    final arrival = (message['arrival'] as String?)?.trim() ?? '';
    if (locationId.isEmpty || arrival.isEmpty) {
      return;
    }
    final key = '$locationId|$arrival';
    final result = DeliveryNotifyResult(
      sent: message['sent'] == true,
      detail: (message['detail'] as String?)?.trim() ?? '',
    );
    final waiter = _relayedSmsWaiters.remove(key);
    if (waiter != null && !waiter.isCompleted) {
      waiter.complete(result);
      return;
    }
    _relayedSmsResults[key] = result;
    while (_relayedSmsResults.length > 20) {
      _relayedSmsResults.remove(_relayedSmsResults.keys.first);
    }
  }

  /// 다른 화면이 보낸 배송의 도착 문자를 이 폰이 대신 보냅니다. 문자를 못 보내는 기기
  Future<void> _relayDeliverySms(GoalEvent event) async {
    final key = _arrivalKey(event);
    if (key == null || !_relaySentKeys.add(key)) {
      return;
    }
    while (_relaySentKeys.length > 50) {
      _relaySentKeys.remove(_relaySentKeys.first);
    }
    if (!await _deliveryNotifier.canSend()) {
      return;
    }
    LocationPoint? location;
    for (final candidate in locationsFor(event.mapId)) {
      if (candidate.locationId == event.locationId) {
        location = candidate;
        break;
      }
    }
    final name = location?.name ?? event.destinationName;
    DeliveryNotifyResult result;
    if (location == null || !location.canReceiveDelivery) {
      result = const DeliveryNotifyResult(
        sent: false,
        detail: '배송지 연락처를 찾지 못했습니다. 직접 연락하세요.',
      );
    } else {
      try {
        result = await _deliveryNotifier.send(
          phone: location.contactPhone,
          text: deliveryArrivalMessage(location.name),
        );
      } catch (error) {
        result = DeliveryNotifyResult(sent: false, detail: '발송 오류: $error');
      }
    }
    if (_disposed) {
      return;
    }
    _addLog(
      LogFilter.delivery,
      '$name 도착 문자 ${result.sent ? '발송됨' : '미발송'}(다른 화면에서 보낸 배송): ${result.detail}',
    );
    _publishRelayedSmsResult(event, result);
    notifyListeners();
  }

  void _publishRelayedSmsResult(GoalEvent event, DeliveryNotifyResult result) {
    final client = _client;
    final settings = _lastSettings;
    if (client == null ||
        settings == null ||
        _connectionState != RosConnectionState.connected) {
      return;
    }
    client
      ..advertise(
          topic: settings.deliverySmsResultTopic, type: 'std_msgs/String')
      ..publishJsonString(
        topic: settings.deliverySmsResultTopic,
        payload: {
          'map_id': event.mapId,
          'location_id': event.locationId,
          'arrival': event.robotStamp,
          'sent': result.sent,
          'detail': result.detail,
        },
      );
  }

  @visibleForTesting
  void handleDeliverySmsResultForTest(Map<String, Object?> message) =>
      _handleDeliverySmsResult(message);

  @visibleForTesting
  set deliveryNotifierForTest(DeliveryNotifier notifier) =>
      _deliveryNotifier = notifier;

  /// 서비스 호출 없이 "배송 중" 상태를 만들어 도착 처리만 검증하는 주입 지점입니다.
  @visibleForTesting
  void setDeliveryForTest(DeliveryJob? job) {
    _cancelDeliveryReturnTimer();
    _setDelivery(job);
    notifyListeners();
  }

  GoalEvent? _pendingGoalAlert;

  /// 아직 관리자에게 보여주지 않은 알림. 화면이 팝업을 띄우고 [consumeGoalAlert]
  GoalEvent? get pendingGoalAlert => _pendingGoalAlert;

  void consumeGoalAlert() {
    if (_pendingGoalAlert == null) {
      return;
    }
    _pendingGoalAlert = null;
    notifyListeners();
  }

  GoalEvent? _activeHelp;
  String? _helpPopupShownFor;
  String _helpRequestedAt = '';

  /// 관리자가 확인한 도움 요청의 id. 확인 뒤 사용자가 직접 취소하면 미션이 같은 id 로
  String? _acknowledgedHelpId;
  String? _pendingHelpNotice;

  /// 지금 걸려 있는 도움 요청(마지막으로 받은 위치 포함). 없으면 null.
  GoalEvent? get activeHelp => _activeHelp;

  /// 도움 요청을 처음 받은 시각(로봇 시계, 'HH:MM:SS'). 재전송마다 바뀌지 않습니다.
  String get helpRequestedAt => _helpRequestedAt;

  /// 아직 띄우지 않은 한 줄 알림(사용자가 확인된 도움 요청을 취소함). 셸이 띄우고 비웁니다.
  String? get pendingHelpNotice => _pendingHelpNotice;

  void consumeHelpNotice() {
    _pendingHelpNotice = null;
  }

  /// 아직 띄우지 않은 도움 팝업이 있는가. 셸이 띄운 뒤 [markHelpPopupShown] 을 부릅니다.
  bool get helpPopupPending =>
      _activeHelp != null && _activeHelp!.helpId != _helpPopupShownFor;

  void markHelpPopupShown() {
    _helpPopupShownFor = _activeHelp?.helpId;
  }

  void _applyHelpEvent(GoalEvent event) {
    if (event.helpId.isEmpty) {
      return;
    }
    switch (event.kind) {
      case GoalEventKind.helpRequested:
        final isNew = _activeHelp?.helpId != event.helpId;
        _activeHelp = event;
        if (isNew) {
          final stamp = event.robotStamp;
          _helpRequestedAt = stamp.contains('T')
              ? stamp.substring(stamp.indexOf('T') + 1)
              : stamp;
          final where = event.place.isEmpty ? '' : ' (${event.place})';
          _addLog(LogFilter.emergencyStop, '도움 요청$where');
        }
      case GoalEventKind.helpAcknowledged:
        if (_activeHelp?.helpId == event.helpId) {
          _activeHelp = null;
          _acknowledgedHelpId = event.helpId;
          _addLog(LogFilter.coordinateTransfer, '도움 요청을 관리자가 확인했습니다.');
        }
      case GoalEventKind.helpCanceled:
        if (_activeHelp?.helpId == event.helpId) {
          _activeHelp = null;
          _addLog(LogFilter.coordinateTransfer, '도움 요청이 끝났습니다.');
        } else if (_acknowledgedHelpId == event.helpId) {
          _acknowledgedHelpId = null;
          const notice = '사용자가 도움 요청을 취소했습니다.';
          _pendingHelpNotice = notice;
          _addLog(LogFilter.emergencyStop, notice);
        }
      default:
        break;
    }
  }

  /// 도움 팝업의 "확인". 미션이 받으면 로봇이 "관리자가 오고있습니다…"를 말하고
  Future<String> acknowledgeHelp(AppSettings settings) async {
    final help = _activeHelp;
    if (help == null) {
      return '이미 끝난 도움 요청입니다.';
    }
    var alreadyEnded = false;
    final reply = await _callService(
      service: settings.missionHelpAckService,
      type: 'vica_interfaces/srv/MissionCommand',
      args: {'request_id': help.helpId},
      describe: (response) {
        if (response.accepted) {
          return '관리자 확인을 로봇에 보냈습니다.';
        }
        switch (response.message) {
          case 'no_active_help':
            alreadyEnded = true;
            return '이미 끝난 도움 요청입니다.';
          case 'id_mismatch':
            return '로봇에 다른 도움 요청이 걸려 있습니다.';
          default:
            return response.message.isEmpty ? '요청이 거부되었습니다.' : response.message;
        }
      },
      failurePrefix: '도움 요청 확인 실패',
    );
    if (reply.accepted) {
      _acknowledgedHelpId = help.helpId;
    }
    if ((reply.accepted || alreadyEnded) &&
        _activeHelp?.helpId == help.helpId) {
      _activeHelp = null;
      notifyListeners();
    }
    return reply.message;
  }

  /// 가장 최근에 팝업으로 넘긴 알림의 id. 팝업이 닫혀야 하는지 판정하는 기준입니다.
  String? _lastGoalAlertId;

  /// 가장 최근 알림이 대기 알림(막힘·만료)인가. 대기 알림은 다시 출발해도 거두지
  bool _lastGoalAlertIsWait = false;

  /// 로봇이 다시 출발해 더 이상 유효하지 않은 알림의 id. 열려 있는 팝업이 이
  String? _resolvedGoalAlertId;

  /// 이 알림의 팝업이 열려 있다면 닫아야 하는가.
  bool isGoalAlertResolved(String id) => _resolvedGoalAlertId == id;

  /// 로봇이 새 주행을 시작했습니다. 떠 있거나 뜨려던 실패·취소 팝업은 낡은
  void _resolveGoalAlert() {
    if (_lastGoalAlertIsWait) {
      return;
    }
    if (_pendingGoalAlert != null) {
      _pendingGoalAlert = null;
    }
    if (_lastGoalAlertId != null) {
      _resolvedGoalAlertId = _lastGoalAlertId;
      _lastGoalAlertId = null;
    }
  }

  bool _pausedByEvent = false;

  /// 지금 일시정지 상태인가. 화면은 이 값으로 버튼을 고른다.
  bool get navigationPaused {
    if (_pausedByEvent) {
      return true;
    }
    final robot = primaryRobot;
    return robot != null && robot.waitingReason.trim() == '일시정지';
  }

  void _handleGoalEvent(Map<String, Object?> message) {
    final event = GoalEvent.fromJson(message, id: _uuid.v4());

    if (event.isHelp) {
      _applyHelpEvent(event);
      notifyListeners();
      return;
    }

    switch (event.kind) {
      case GoalEventKind.paused:
        _pausedByEvent = true;
      case GoalEventKind.sent:
      case GoalEventKind.accepted:
      case GoalEventKind.succeeded:
      case GoalEventKind.failed:
      case GoalEventKind.rejected:
      case GoalEventKind.canceled:
      case GoalEventKind.emergencyStopped:
      case GoalEventKind.returnHomeSucceeded:
      case GoalEventKind.returnHomeFailed:
      case GoalEventKind.returnHomeCanceled:
      case GoalEventKind.stateIdle:
        _pausedByEvent = false;
      default:
        break;
    }

    switch (event.kind) {
      case GoalEventKind.sent:
      case GoalEventKind.accepted:
      case GoalEventKind.returnHomeSent:
        _resolveGoalAlert();
      default:
        break;
    }

    if (event.kind == GoalEventKind.succeeded &&
        event.delivery &&
        !_isMyDeliveryArrival(event)) {
      unawaited(_relayDeliverySms(event));
    }

    _applyGoalEventToDelivery(event);

    if (event.kind == GoalEventKind.returnHomeSucceeded && _home != null) {
      _home = _home!.copyWith(visitedOk: true);
    } else if (event.kind == GoalEventKind.returnHomeFailed && _home != null) {
      _home = _home!.copyWith(visitedOk: false);
    }

    if (event.needsPopup) {
      final hiddenByEmergency = event.kind == GoalEventKind.canceled &&
          _emergencyStopState == EmergencyStopState.active;
      if (!hiddenByEmergency) {
        _pendingGoalAlert = event;
        _lastGoalAlertId = event.id;
        _lastGoalAlertIsWait = event.kind.isWaitAlert;
      }
      final where =
          event.destinationName.isEmpty ? '' : '${event.destinationName}: ';
      final detail = event.reason.isEmpty ? '' : ' (${event.reason})';
      _addLog(
        event.isFailure
            ? LogFilter.emergencyStop
            : LogFilter.coordinateTransfer,
        '$where${event.title}$detail',
      );
    }
    notifyListeners();
  }

  @visibleForTesting
  void handleGoalEventForTest(Map<String, Object?> message) =>
      _handleGoalEvent(message);

  PoseCheckResult? _poseCheck;
  bool _poseChecking = false;

  PoseCheckResult? get poseCheck => _poseCheck;
  bool get poseChecking => _poseChecking;

  /// 확정 뒤 AMCL 자세에서 본 라이다 점입니다.
  List<Offset> get committedScanHits => _committedScanHits;
  List<Offset> _committedScanHits = const [];

  void clearPoseCheck() {
    if (_poseCheck == null && !_poseChecking && _committedScanHits.isEmpty) {
      return;
    }
    _poseCheck = null;
    _poseChecking = false;
    _committedScanHits = const [];
    notifyListeners();
  }

  /// [result] 가 지금 남아 있는 채점 결과이면 그것만 지웁니다.
  void discardPoseCheck(PoseCheckResult? result) {
    if (_disposed || result == null || !identical(_poseCheck, result)) {
      return;
    }
    _poseCheck = null;
    notifyListeners();
  }

  /// 지도에서 짚은 자리를 채점합니다. AMCL 은 건드리지 않습니다.
  Future<String> checkInitialPose(
    AppSettings settings, {
    required double x,
    required double y,
    double? yawHint,
  }) async {
    final client = _client;
    if (client == null || _connectionState != RosConnectionState.connected) {
      return 'ROS Bridge에 연결되지 않았습니다.';
    }
    _poseChecking = true;
    notifyListeners();
    try {
      final response = await client.callService(
        service: settings.poseCheckService,
        type: 'vica_interfaces/srv/PoseCheck',
        args: {
          'x': x,
          'y': y,
          'has_yaw_hint': yawHint != null,
          'yaw_hint': yawHint ?? 0.0,
        },
        timeout: const Duration(seconds: 10),
      );
      final result = PoseCheckResult.fromValues(response.values);
      _poseCheck = result;
      return result.message;
    } catch (error) {
      _poseCheck = null;
      final message =
          '확인 실패 — 채점 노드(pose_bootstrap_node)가 젯슨에서 켜져 있는지 확인하세요. ($error)';
      _addLog(LogFilter.coordinateTransfer, message);
      return message;
    } finally {
      _poseChecking = false;
      notifyListeners();
    }
  }

  /// 확인이 끝난 자세를 AMCL 에 반영합니다.
  Future<String> commitInitialPose(
    AppSettings settings, {
    required double x,
    required double y,
    required double yaw,
  }) async {
    final client = _client;
    if (client == null || _connectionState != RosConnectionState.connected) {
      return 'ROS Bridge에 연결되지 않았습니다.';
    }
    try {
      final response = await client.callService(
        service: settings.poseCommitService,
        type: 'vica_interfaces/srv/PoseCommit',
        args: {'x': x, 'y': y, 'yaw': yaw},
        timeout: const Duration(seconds: 12),
      );
      final message = response.message.isEmpty
          ? (response.accepted ? '초기 위치를 반영했습니다.' : '반영이 거부되었습니다.')
          : response.message;
      _addLog(LogFilter.coordinateTransfer, message);
      if (response.accepted) {
        _poseCheck = null;
        _committedScanHits = PoseCheckResult.hitsFrom(response.values);
        notifyListeners();
      }
      return message;
    } catch (error) {
      final message = '초기 위치 반영 실패: $error';
      _addLog(LogFilter.coordinateTransfer, message);
      return message;
    }
  }

  final Map<String, List<KeepoutZone>> _keepoutsByMap = {};
  bool _keepoutEditing = false;
  Offset? _keepoutDragStart;
  Offset? _keepoutDragCurrent;
  String? _selectedKeepoutZoneId;
  KeepoutSaveState _keepoutState = KeepoutSaveState.idle;
  String _keepoutMessage = '';
  bool _keepoutMaskApplied = false;
  int _keepoutZoneSeq = 0;
  List<KeepoutZone> _keepoutBackup = const [];

  List<KeepoutZone> keepoutZonesFor(String? mapId) =>
      mapId == null ? const [] : (_keepoutsByMap[mapId] ?? const []);
  bool get keepoutEditing => _keepoutEditing;
  String? get selectedKeepoutZoneId => _selectedKeepoutZoneId;
  KeepoutSaveState get keepoutState => _keepoutState;
  String get keepoutMessage => _keepoutMessage;
  bool get keepoutMaskApplied => _keepoutMaskApplied;

  KeepoutZone? _pendingZone;

  bool get hasPendingKeepoutZone => _pendingZone != null;

  /// 드래그 중엔 끌고 있는 사각형을, 아니면 미확정 초안을 보여줍니다.
  KeepoutZone? get draftKeepoutZone {
    final start = _keepoutDragStart;
    final current = _keepoutDragCurrent;
    if (start == null || current == null) {
      return _pendingZone;
    }
    return KeepoutZone.fromDrag(zoneId: '_draft', start: start, end: current);
  }

  /// 젯슨에서 저장된 금지구역을 읽어옵니다. 저장된 적이 없으면 빈 목록입니다.
  Future<void> requestKeepoutList(AppSettings settings, String mapId) async {
    final client = _client;
    if (client == null || _connectionState != RosConnectionState.connected) {
      return;
    }
    _keepoutState = KeepoutSaveState.loading;
    notifyListeners();
    try {
      final response = await client.callService(
        service: settings.keepoutGetService,
        type: 'vica_interfaces/srv/GetKeepout',
        args: {'map_id': mapId},
      );
      final zones = _decodeZones(response.values['zones_json']);
      _keepoutsByMap[mapId] = zones;
      _keepoutMaskApplied = response.values['mask_exists'] == true;
      _keepoutState = KeepoutSaveState.idle;
      _keepoutMessage = '';
      _addLog(LogFilter.coordinateTransfer, '$mapId 금지구역 ${zones.length}개 조회');
    } catch (error) {
      _keepoutState = KeepoutSaveState.failed;
      _keepoutMessage = '금지구역을 불러오지 못했습니다: $error';
      _addLog(LogFilter.coordinateTransfer, _keepoutMessage);
    }
    notifyListeners();
  }

  void enterKeepoutEdit(String mapId) {
    _keepoutEditing = true;
    _keepoutBackup = List.of(keepoutZonesFor(mapId));
    _selectedKeepoutZoneId = null;
    _keepoutState = KeepoutSaveState.editing;
    _keepoutMessage = '';
    notifyListeners();
  }

  /// 편집을 버리고 시작 시점으로 되돌립니다.
  void cancelKeepoutEdit(String mapId) {
    _keepoutsByMap[mapId] = List.of(_keepoutBackup);
    _keepoutEditing = false;
    _pendingZone = null;
    _keepoutDragStart = null;
    _keepoutDragCurrent = null;
    _selectedKeepoutZoneId = null;
    _keepoutState = KeepoutSaveState.idle;
    _keepoutMessage = '';
    notifyListeners();
  }

  void startKeepoutDrag(Offset ros) {
    if (!_keepoutEditing) {
      return;
    }
    _keepoutDragStart = ros;
    _keepoutDragCurrent = ros;
    notifyListeners();
  }

  void updateKeepoutDrag(Offset ros) {
    if (!_keepoutEditing || _keepoutDragStart == null) {
      return;
    }
    _keepoutDragCurrent = ros;
    notifyListeners();
  }

  /// 손을 뗀 자리에서 사각형을 확정합니다.
  String? finishKeepoutDrag(String mapId) {
    final draft = draftKeepoutZone;
    _keepoutDragStart = null;
    _keepoutDragCurrent = null;
    if (draft == null) {
      notifyListeners();
      return null;
    }
    if (draft.width < 0.1 || draft.height < 0.1) {
      notifyListeners();
      return '구역이 너무 작습니다. 조금 더 크게 그려 주세요.';
    }
    _pendingZone = draft.copyWith(zoneId: '_pending');
    notifyListeners();
    return null;
  }

  /// 미확정 초안을 목록에 넣습니다. 그 뒤에야 다음 사각형을 그립니다.
  void confirmPendingKeepoutZone(String mapId) {
    final pending = _pendingZone;
    if (pending == null) {
      return;
    }
    _keepoutZoneSeq += 1;
    final zone = pending.copyWith(
        zoneId: 'kz_${_keepoutZoneSeq}_${_uuid.v4().substring(0, 4)}');
    _keepoutsByMap[mapId] = [...keepoutZonesFor(mapId), zone];
    _selectedKeepoutZoneId = zone.zoneId;
    _pendingZone = null;
    notifyListeners();
  }

  void selectKeepoutZone(String? zoneId) {
    _selectedKeepoutZoneId = _selectedKeepoutZoneId == zoneId ? null : zoneId;
    notifyListeners();
  }

  void deleteSelectedKeepoutZone(String mapId) {
    final zoneId = _selectedKeepoutZoneId;
    if (zoneId == null) {
      return;
    }
    _keepoutsByMap[mapId] =
        keepoutZonesFor(mapId).where((zone) => zone.zoneId != zoneId).toList();
    _selectedKeepoutZoneId = null;
    notifyListeners();
  }

  void clearKeepoutZones(String mapId) {
    _keepoutsByMap[mapId] = const [];
    _selectedKeepoutZoneId = null;
    notifyListeners();
  }

  /// 사각형 전체 목록을 젯슨에 저장하고, 가능하면 Nav2 에 바로 반영합니다.
  Future<String> saveKeepoutZones(AppSettings settings, String mapId) async {
    if (_keepoutState == KeepoutSaveState.saving) {
      return '이미 저장하고 있습니다.';
    }
    final client = _client;
    if (client == null || _connectionState != RosConnectionState.connected) {
      _keepoutState = KeepoutSaveState.failed;
      _keepoutMessage = 'ROS Bridge에 연결되지 않았습니다.';
      notifyListeners();
      return _keepoutMessage;
    }

    if (_pendingZone != null) {
      confirmPendingKeepoutZone(mapId);
    }
    final zones = keepoutZonesFor(mapId);
    _keepoutState = KeepoutSaveState.saving;
    _keepoutMessage = '금지구역 ${zones.length}개를 저장하고 있습니다.';
    notifyListeners();

    try {
      final response = await client.callService(
        service: settings.keepoutSaveService,
        type: 'vica_interfaces/srv/SaveKeepout',
        args: {
          'map_id': mapId,
          'zones_json': jsonEncode(zones.map((zone) => zone.toJson()).toList()),
          'apply_now': true,
        },
        timeout: const Duration(seconds: 8),
      );
      _keepoutMessage = response.message;
      if (response.accepted) {
        _keepoutState = KeepoutSaveState.succeeded;
        _keepoutEditing = false;
        _keepoutMaskApplied = response.values['applied'] == true;
        if (!_keepoutMaskApplied && response.values['reason'] == 'no_nav2') {
          _keepoutMessage = '금지구역 ${zones.length}개를 저장했습니다. '
              'Nav2가 실행되면 적용됩니다.';
        }
        _selectedKeepoutZoneId = null;
        _keepoutBackup = List.of(zones);
      } else {
        _keepoutState = KeepoutSaveState.failed;
      }
      _addLog(LogFilter.coordinateTransfer, '금지구역 저장: $_keepoutMessage');
    } catch (error) {
      _keepoutState = KeepoutSaveState.failed;
      _keepoutMessage = '금지구역 저장 실패: $error';
      _addLog(LogFilter.coordinateTransfer, _keepoutMessage);
    }
    notifyListeners();
    return _keepoutMessage;
  }

  List<KeepoutZone> _decodeZones(Object? rawJson) {
    if (rawJson is! String || rawJson.isEmpty) {
      return const [];
    }
    final decoded = jsonDecode(rawJson);
    if (decoded is! List) {
      return const [];
    }
    return decoded
        .whereType<Map<String, Object?>>()
        .map(KeepoutZone.fromJson)
        .toList();
  }

  /// 요청 없이 도착한 금지구역 소식입니다.
  void _handleKeepoutState(Map<String, Object?> message) {
    final mapId = message['map_id'] as String? ?? '';
    final applied = message['applied'] == true;
    final text = message['message'] as String? ?? '';
    if (mapId.isNotEmpty && mapId == _selectedMapId) {
      _keepoutMaskApplied = applied;
    }
    _keepoutMessage = text;
    _keepoutState =
        applied ? KeepoutSaveState.succeeded : KeepoutSaveState.failed;
    _addLog(LogFilter.coordinateTransfer, '금지구역 상태: $text');
    notifyListeners();
  }

  final RouteServiceCall? _routeServiceCall;
  final WallMaskLoader _wallMaskLoader;
  final Map<String, RouteInfo> _routeInfoByMap = {};
  final Map<String, MapWallMask> _wallMasks = {};
  final Set<String> _wallMaskLoading = {};
  final Set<String> _wallMaskFailed = {};

  RouteEditState _routeState = RouteEditState.idle;
  String _routeMessage = '';
  bool _routeEditing = false;
  String? _routeEditMapId;
  RouteSketch _routeSketch = RouteSketch.empty;
  String _routeBaseEncoded = '';
  String _routeBaseVersion = '';
  RouteEditTool _routeTool = RouteEditTool.addNode;
  int? _routeConnectFrom;
  int? _routeDragNode;
  RouteGraph? _routePreview;
  RouteChecks _routeChecks = RouteChecks.none;
  Timer? _routePreviewTimer;
  int _routePreviewSeq = 0;
  AppSettings? _routeSettings;

  /// 셸이 띄울 레일 적용 실패 팝업(D). 문구 그대로.
  String? _pendingRouteAlert;

  /// 셸이 띄울 짧은 알림 띠(주행이 끝나 적용됨 등).
  String? _pendingRouteToast;

  /// 노드를 고르는 손가락 반경(m).
  static const double routeHitRadiusM = 0.6;

  RouteInfo? routeInfoFor(String? mapId) =>
      mapId == null ? null : _routeInfoByMap[mapId];
  RouteEditState get routeState => _routeState;
  String get routeMessage => _routeMessage;
  bool get routeEditing => _routeEditing;
  String? get routeEditMapId => _routeEditMapId;
  RouteSketch get routeSketch => _routeSketch;
  RouteEditTool get routeTool => _routeTool;
  int? get routeConnectFrom => _routeConnectFrom;
  RouteGraph? get routePreview => _routePreview;
  RouteChecks get routeChecks => _routeChecks;
  bool get routeDirty =>
      _routeEditing && _routeSketch.encode() != _routeBaseEncoded;
  String? get pendingRouteAlert => _pendingRouteAlert;
  String? get pendingRouteToast => _pendingRouteToast;

  void consumeRouteAlert() {
    _pendingRouteAlert = null;
  }

  void consumeRouteToast() {
    _pendingRouteToast = null;
  }

  Future<Map<String, Object?>> _callRoute(
    AppSettings settings,
    String service,
    String type,
    Map<String, Object?> args, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final injected = _routeServiceCall;
    if (injected != null) {
      return injected(service, type, args, timeout);
    }
    final client = _client;
    if (client == null || _connectionState != RosConnectionState.connected) {
      throw StateError('ROS Bridge에 연결되지 않았습니다.');
    }
    final response = await client.callService(
      service: service,
      type: type,
      args: args,
      timeout: timeout,
    );
    return response.values;
  }

  bool get _routeCanCall =>
      _routeServiceCall != null ||
      (_client != null && _connectionState == RosConnectionState.connected);

  /// 로봇의 레일 요약·스케치·판을 받습니다. 레일 칸을 열 때와 저장 뒤에 부릅니다.
  Future<void> requestRouteInfo(AppSettings settings, String mapId) async {
    if (!_routeCanCall) {
      return;
    }
    try {
      final v = await _callRoute(
        settings,
        settings.routeGetService,
        'vica_interfaces/srv/GetRoute',
        {'map_id': mapId},
      );
      _routeInfoByMap[mapId] = RouteInfo(
        found: v['found'] == true,
        sketch: RouteSketch.decode(v['sketch_json']),
        version: v['version'] as String? ?? '',
        status: v['status'] as String? ?? 'none',
        checks: RouteChecks.decode(v['checks_json']),
      );
    } catch (error) {
      _addLog(LogFilter.coordinateTransfer, '레일 정보를 받지 못했습니다: $error');
    }
    notifyListeners();
  }

  /// 편집을 시작합니다. [initial] 이 없으면 로봇에 저장된 스케치에서 시작합니다.
  void enterRouteEdit(
    AppSettings settings,
    VicaMap map, {
    RouteSketch? initial,
    RouteGraph? preview,
    RouteChecks? checks,
  }) {
    final info = _routeInfoByMap[map.mapId];
    _routeSettings = settings;
    _routeEditing = true;
    _routeEditMapId = map.mapId;
    final base = info?.sketch ?? RouteSketch.empty;
    _routeBaseEncoded = base.encode();
    _routeSketch = initial ?? base;
    _routeBaseVersion = info?.version ?? '';
    _routeTool = RouteEditTool.addNode;
    _routeConnectFrom = null;
    _routeDragNode = null;
    _routePreview = preview;
    _routeChecks = checks ?? RouteChecks.none;
    _routeState = RouteEditState.editing;
    _routeMessage = '';
    notifyListeners();
    if (!_wallMasks.containsKey(map.mapId)) {
      unawaited(_loadWallMask(settings, map));
    }
    if (preview == null && !_routeSketch.isEmpty) {
      _scheduleRoutePreview();
    }
  }

  Future<void> _loadWallMask(AppSettings settings, VicaMap map) async {
    final url = map.imageUrl.startsWith('http')
        ? map.imageUrl
        : '${settings.mapHttpBaseUrl.replaceAll(RegExp(r'/$'), '')}'
            '${map.imageUrl.startsWith('/') ? '' : '/'}${map.imageUrl}';
    final mask = await _wallMaskLoader(url, map);
    if (mask != null) {
      _wallMasks[map.mapId] = mask;
    }
  }

  @visibleForTesting
  void setWallMaskForTest(String mapId, MapWallMask mask) {
    _wallMasks[mapId] = mask;
  }

  void cancelRouteEdit() {
    _routePreviewTimer?.cancel();
    _routeEditing = false;
    _routeEditMapId = null;
    _routeSketch = RouteSketch.empty;
    _routeConnectFrom = null;
    _routeDragNode = null;
    _routePreview = null;
    _routeChecks = RouteChecks.none;
    _routeState = RouteEditState.idle;
    _routeMessage = '';
    notifyListeners();
  }

  void setRouteTool(RouteEditTool tool) {
    _routeTool = tool;
    _routeConnectFrom = null;
    notifyListeners();
  }

  bool _crossesWall(Offset a, Offset b) {
    final mask = _routeEditMapId == null ? null : _wallMasks[_routeEditMapId];
    return mask != null && mask.crossesWall(a, b);
  }

  /// 편집 중 지도 한 번 누르기. 도구에 따라 노드 추가·선 잇기·지우기.
  void routeTap(Offset ros) {
    if (!_routeEditing) {
      return;
    }
    final sketch = _routeSketch;
    final hit = sketch.nodeNear(ros, routeHitRadiusM);
    switch (_routeTool) {
      case RouteEditTool.addNode:
        if (hit != null) {
          return;
        }
        _routeSketch = sketch.addNode(ros);
      case RouteEditTool.connect:
        if (hit == null) {
          _routeConnectFrom = null;
          notifyListeners();
          return;
        }
        final from = _routeConnectFrom;
        if (from == null || from == hit) {
          _routeConnectFrom = from == hit ? null : hit;
          notifyListeners();
          return;
        }
        if (_crossesWall(sketch.nodes[from]!, sketch.nodes[hit]!)) {
          return;
        }
        _routeSketch = sketch.connect(from, hit);
        _routeConnectFrom = null;
      case RouteEditTool.erase:
        if (hit != null) {
          _routeSketch = sketch.removeNode(hit);
        } else {
          final edge = sketch.edgeNear(ros, routeHitRadiusM * 0.6);
          if (edge == null) {
            return;
          }
          _routeSketch = sketch.removeEdge(edge);
        }
    }
    notifyListeners();
    _scheduleRoutePreview();
  }

  /// 노드를 길게 눌러 끌기 시작.
  void routeDragStart(Offset ros) {
    if (!_routeEditing) {
      return;
    }
    _routeDragNode = _routeSketch.nodeNear(ros, routeHitRadiusM);
  }

  void routeDragUpdate(Offset ros) {
    final id = _routeDragNode;
    if (id == null) {
      return;
    }
    for (final e in _routeSketch.edges) {
      if (e.a != id && e.b != id) {
        continue;
      }
      final other = _routeSketch.nodes[e.a == id ? e.b : e.a]!;
      if (_crossesWall(ros, other)) {
        return;
      }
    }
    _routeSketch = _routeSketch.moveNode(id, ros);
    notifyListeners();
  }

  void routeDragEnd() {
    if (_routeDragNode != null) {
      _routeDragNode = null;
      _scheduleRoutePreview();
    }
  }

  /// 편집이 멈추고 0.5초 뒤 로봇에 미리보기를 받습니다(누를 때마다 부르지 않게).
  void _scheduleRoutePreview() {
    _routePreviewTimer?.cancel();
    final settings = _routeSettings;
    final mapId = _routeEditMapId;
    if (settings == null || mapId == null) {
      return;
    }
    _routePreviewTimer = Timer(const Duration(milliseconds: 500), () {
      unawaited(requestRoutePreview(settings, mapId));
    });
  }

  /// 스케치를 로봇이 다듬은 모양과 검사 결과를 받습니다. 파일은 쓰지 않습니다.
  Future<void> requestRoutePreview(AppSettings settings, String mapId) async {
    if (!_routeEditing || !_routeCanCall) {
      return;
    }
    if (_routeSketch.edges.isEmpty) {
      _routePreview = null;
      _routeChecks = RouteChecks.none;
      notifyListeners();
      return;
    }
    final seq = ++_routePreviewSeq;
    try {
      final v = await _callRoute(
        settings,
        settings.routeSaveService,
        'vica_interfaces/srv/SaveRoute',
        {
          'map_id': mapId,
          'sketch_json': _routeSketch.encode(),
          'preview_only': true,
          'apply_now': false,
          'base_version': _routeBaseVersion,
          'overwrite': false,
        },
      );
      if (seq != _routePreviewSeq || !_routeEditing) {
        return;
      }
      _routePreview = decodeRoutePreview(v['preview_json']);
      _routeChecks = RouteChecks.decode(v['checks_json']);
    } catch (_) {}
    notifyListeners();
  }

  /// 자동 초안을 받아 편집을 시작합니다. 수 초 걸립니다(0903_d 약 6.5 s).
  Future<void> requestRouteDraft(AppSettings settings, VicaMap map) async {
    if (!_routeCanCall) {
      _routeState = RouteEditState.failed;
      _routeMessage = 'ROS Bridge에 연결되지 않았습니다.';
      notifyListeners();
      return;
    }
    _routeState = RouteEditState.drafting;
    _routeMessage = '초안을 만들고 있습니다. 10초쯤 걸립니다.';
    notifyListeners();
    try {
      final v = await _callRoute(
        settings,
        settings.routeDraftService,
        'vica_interfaces/srv/DraftRoute',
        {'map_id': map.mapId, 'shape': 'auto'},
        timeout: const Duration(seconds: 45),
      );
      if (v['accepted'] != true) {
        _routeState = RouteEditState.failed;
        _routeMessage = v['message'] as String? ?? '초안을 만들지 못했습니다.';
        notifyListeners();
        return;
      }
      if (!_routeInfoByMap.containsKey(map.mapId)) {
        await requestRouteInfo(settings, map.mapId);
      }
      enterRouteEdit(
        settings,
        map,
        initial: RouteSketch.decode(v['sketch_json']),
        preview: decodeRoutePreview(v['preview_json']),
        checks: RouteChecks.decode(v['checks_json']),
      );
      _routeMessage = v['message'] as String? ?? '';
      notifyListeners();
    } catch (error) {
      _routeState = RouteEditState.failed;
      _routeMessage = '초안을 만들지 못했습니다: $error';
      notifyListeners();
    }
  }

  /// 스케치를 저장하고 적용합니다. [overwrite] 는 팝업 F 에서 '덮어쓰기'를 골랐을 때.
  Future<RouteSaveOutcome> saveRoute(
    AppSettings settings,
    String mapId, {
    bool overwrite = false,
  }) async {
    if (_routeState == RouteEditState.saving) {
      return RouteSaveOutcome.failed;
    }
    if (!_routeCanCall) {
      _routeState = RouteEditState.failed;
      _routeMessage = 'ROS Bridge에 연결되지 않았습니다.';
      notifyListeners();
      return RouteSaveOutcome.failed;
    }
    _routeConnectFrom = null;
    _routeState = RouteEditState.saving;
    _routeMessage = '레일을 저장하고 있습니다.';
    notifyListeners();
    try {
      final v = await _callRoute(
        settings,
        settings.routeSaveService,
        'vica_interfaces/srv/SaveRoute',
        {
          'map_id': mapId,
          'sketch_json': _routeSketch.encode(),
          'preview_only': false,
          'apply_now': true,
          'base_version': _routeBaseVersion,
          'overwrite': overwrite,
        },
        timeout: const Duration(seconds: 15),
      );
      final reason = v['reason'] as String? ?? '';
      _routeMessage = v['message'] as String? ?? '';
      if (v['preview_json'] is String &&
          (v['preview_json'] as String).isNotEmpty) {
        _routePreview = decodeRoutePreview(v['preview_json']);
      }
      _routeChecks = RouteChecks.decode(v['checks_json']);
      if (v['accepted'] != true) {
        _routeState = RouteEditState.editing;
        notifyListeners();
        if (reason == 'conflict') {
          return RouteSaveOutcome.conflict;
        }
        if (reason == 'check_failed') {
          return RouteSaveOutcome.checkFailed;
        }
        _routeState = RouteEditState.failed;
        notifyListeners();
        return RouteSaveOutcome.failed;
      }
      if (reason == 'apply_failed' ||
          reason == 'apply_timeout' ||
          reason == 'no_route_server') {
        _pendingRouteAlert = _routeMessage;
      }
      _routePreviewTimer?.cancel();
      _routeEditing = false;
      _routeEditMapId = null;
      _routeSketch = RouteSketch.empty;
      _routePreview = null;
      _routeChecks = RouteChecks.none;
      _routeState = RouteEditState.succeeded;
      _addLog(LogFilter.coordinateTransfer, '레일 저장: $_routeMessage');
      notifyListeners();
      await requestRouteInfo(settings, mapId);
      await loadRouteGraph(settings, mapId);
      return RouteSaveOutcome.saved;
    } catch (error) {
      _routeState = RouteEditState.failed;
      _routeMessage = '레일 저장 실패: $error';
      notifyListeners();
      return RouteSaveOutcome.failed;
    }
  }

  /// 팝업 F '새 레일 불러오기' — 내 편집을 버리고 로봇의 최신 레일로 다시 시작.
  Future<void> reloadRouteDiscardingEdits(
      AppSettings settings, VicaMap map) async {
    await requestRouteInfo(settings, map.mapId);
    await loadRouteGraph(settings, map.mapId);
    enterRouteEdit(settings, map);
  }

  /// 요청 없이 도착한 레일 소식 — 주행이 끝나 미뤄 둔 적용이 됐거나 실패한 경우.
  void _handleRouteState(Map<String, Object?> message) {
    final mapId = message['map_id'] as String? ?? '';
    final applied = message['applied'] == true;
    final text = message['message'] as String? ?? '';
    final info = _routeInfoByMap[mapId];
    if (info != null) {
      _routeInfoByMap[mapId] = RouteInfo(
        found: info.found,
        sketch: info.sketch,
        version: info.version,
        status: applied ? 'applied' : info.status,
        checks: info.checks,
      );
    }
    if (applied) {
      _pendingRouteToast = '주행이 끝나 새 레일을 적용했습니다.';
    } else {
      _pendingRouteAlert = text.isEmpty ? '레일을 적용하지 못했습니다.' : text;
    }
    _addLog(LogFilter.coordinateTransfer, '레일 상태: $text');
    notifyListeners();
  }

  @visibleForTesting
  void handleRouteStateForTest(Map<String, Object?> message) =>
      _handleRouteState(message);

  /// 레일이 저장됐다는 알림. 이 지도의 레일을 본 적이 있으면 다시 받습니다. 저장한
  void _handleRouteSaved(Map<String, Object?> message) {
    final mapId = message['map_id'] as String? ?? '';
    if (mapId.isEmpty ||
        (mapId != _selectedMapId && !_routeGraphsByMap.containsKey(mapId))) {
      return;
    }
    unawaited(loadRouteGraph(_lastSettings ?? const AppSettings(), mapId));
  }

  @visibleForTesting
  void handleRouteSavedForTest(Map<String, Object?> message) =>
      _handleRouteSaved(message);

  Future<String> startMapping(AppSettings settings) {
    return _callMappingTrigger(settings.mappingStartService, '매핑을 시작했습니다.');
  }

  Future<String> stopMapping(AppSettings settings) {
    return _callMappingTrigger(settings.mappingStopService, '매핑을 종료했습니다.');
  }

  Future<String> _callMappingTrigger(String service, String fallback) async {
    final reply = await _callService(
      service: service,
      type: 'std_srvs/srv/Trigger',
      timeout: const Duration(seconds: 15),
      describe: (response) =>
          response.message.isEmpty ? fallback : response.message,
      failurePrefix: '매핑 요청 실패',
    );
    return reply.message;
  }

  /// 지도를 저장합니다. 이름은 사람이, 날짜는 로봇이 붙입니다.
  Future<String> saveMap(
    AppSettings settings,
    String name, {
    bool align = false,
  }) async {
    final client = _client;
    if (client == null || _connectionState != RosConnectionState.connected) {
      return 'ROS Bridge에 연결되지 않았습니다.';
    }
    try {
      final response = await client.callService(
        service: settings.mappingSaveService,
        type: 'vica_interfaces/srv/SaveMap',
        args: {'name': name, if (align) 'align': true},
      );
      final message = response.message.isEmpty
          ? (response.accepted ? '저장을 시작했습니다.' : '저장이 거부되었습니다.')
          : response.message;
      _addLog(LogFilter.coordinateTransfer, message);
      return message;
    } catch (error) {
      final String message;
      if (error is TimeoutException) {
        message = '지도 저장 요청 실패: $error\n'
            '로봇이 이미 저장하는 중일 수 있습니다. 상태가 바뀌는지 먼저 확인해 주세요.';
      } else if (align && error is StateError) {
        message = '지도 저장 요청 실패: $error\n'
            '로봇 쪽이 정렬 저장을 모르는 버전일 수 있습니다. '
            '정렬하지 않고 저장으로 다시 해 보세요.';
      } else {
        message = '지도 저장 요청 실패: $error';
      }
      _addLog(LogFilter.coordinateTransfer, message);
      return message;
    }
  }

  static const teleopTopic = '/cmd_vel_req';
  static const _teleopType = 'geometry_msgs/Twist';

  static const teleopMaxLinear = 0.3;
  static const teleopMaxAngular = 0.3;

  static const _teleopPeriod = Duration(milliseconds: 50);

  Timer? _teleopTimer;
  bool _teleopAdvertised = false;
  double _teleopLinear = 0;
  double _teleopAngular = 0;

  bool get teleopActive => _teleopTimer != null;

  /// 이 명령이 지금 실제로 나가고 있는가. 조작판 버튼이 "누르는 동안" 색을
  bool isTeleopHeld({required double linear, required double angular}) =>
      teleopActive && _teleopLinear == linear && _teleopAngular == angular;

  /// 누르고 있는 동안 부릅니다. 값이 바뀌면 다시 부르면 됩니다.
  void holdTeleop({required double linear, required double angular}) {
    final client = _client;
    if (client == null || _connectionState != RosConnectionState.connected) {
      return;
    }
    _teleopLinear = linear.clamp(-teleopMaxLinear, teleopMaxLinear).toDouble();
    _teleopAngular =
        angular.clamp(-teleopMaxAngular, teleopMaxAngular).toDouble();

    if (!_teleopAdvertised) {
      client.advertise(topic: teleopTopic, type: _teleopType);
      _teleopAdvertised = true;
    }
    _publishTeleop();
    _teleopTimer ??= Timer.periodic(_teleopPeriod, (_) => _publishTeleop());
    notifyListeners();
  }

  /// 손을 뗐을 때 부릅니다. 0을 한 번 보내고 발행을 멈춥니다.
  void releaseTeleop() {
    _teleopTimer?.cancel();
    _teleopTimer = null;
    _teleopLinear = 0;
    _teleopAngular = 0;
    if (_teleopAdvertised) {
      _publishTeleop();
    }
    notifyListeners();
  }

  void _publishTeleop() {
    final client = _client;
    if (client == null || _connectionState != RosConnectionState.connected) {
      _teleopTimer?.cancel();
      _teleopTimer = null;
      _teleopAdvertised = false;
      notifyListeners();
      return;
    }
    client.publishMessage(
      topic: teleopTopic,
      message: {
        'linear': {'x': _teleopLinear, 'y': 0.0, 'z': 0.0},
        'angular': {'x': 0.0, 'y': 0.0, 'z': _teleopAngular},
      },
    );
  }

  Future<String> _sendMissionCommand(
    String service,
    String defaultSuccessMessage,
  ) async {
    final reply = await _callService(
      service: service,
      type: 'vica_interfaces/srv/MissionCommand',
      args: {'request_id': _uuid.v4()},
      describe: (response) => response.accepted
          ? defaultSuccessMessage
          : response.message.isEmpty
              ? '요청이 거부되었습니다.'
              : _localizeGateReason(response.message),
      failurePrefix: 'Mission Manager 요청 실패',
    );
    return reply.message;
  }

  /// 미션·지도·홈 서비스 한 번 부르기의 공통 틀입니다.
  Future<({bool accepted, String message})> _callService({
    required String service,
    required String type,
    Map<String, Object?> args = const {},
    Duration timeout = RosBridgeClient.defaultServiceTimeout,
    required String Function(RosServiceResponse response) describe,
    required String failurePrefix,
    void Function(RosServiceResponse response)? onAccepted,
    void Function(bool calling)? busy,
  }) async {
    final client = _client;
    if (client == null || _connectionState != RosConnectionState.connected) {
      return (accepted: false, message: 'ROS Bridge에 연결되지 않았습니다.');
    }
    busy?.call(true);
    try {
      final response = await client.callService(
        service: service,
        type: type,
        args: args,
        timeout: timeout,
      );
      final message = describe(response);
      _addLog(LogFilter.coordinateTransfer, message);
      if (response.accepted) {
        onAccepted?.call(response);
      }
      return (accepted: response.accepted, message: message);
    } catch (error) {
      final message = '$failurePrefix: $error';
      _addLog(LogFilter.coordinateTransfer, message);
      return (accepted: false, message: message);
    } finally {
      busy?.call(false);
    }
  }

  String _localizeGateReason(
    String message, [
    Map<String, String> overrides = const {},
  ]) {
    for (final entry in overrides.entries) {
      if (message.contains(entry.key)) {
        return entry.value;
      }
    }
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

  static String? _initialMapChoice(List<VicaMap> maps) {
    for (final map in maps) {
      if (map.isCurrent) {
        return map.mapId;
      }
    }
    return maps.isEmpty ? null : maps.first.mapId;
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
    _currentMapId = (message['current_map_id'] as String?)?.trim() ?? '';
    final hadNoSelection = _selectedMapId == null;
    _selectedMapId ??= _initialMapChoice(_maps);
    final mapId = _selectedMapId;
    final settings = _lastSettings;
    if (hadNoSelection && mapId != null && settings != null) {
      refreshMapData(settings, mapId, auto: true);
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
    if (_deliveryNeedsReconcile) {
      _reconcileRestoredDelivery(next);
    }
    _logErrorReasonChange(next);
    _handleNav2StatusLog(next);
    notifyListeners();
  }

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
      _addLog(LogFilter.connection, errorReason);
      return;
    }
    _addLog(LogFilter.emergencyStop, '${robot.robotName}: $errorReason');
  }

  bool _isNoEventsRecorded(String message) {
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

  void _handleRobotHealth(Map<String, Object?> message) {
    _health = RobotHealth.fromRosMsg(message);
    notifyListeners();
  }

  void _handleMappingStatus(Map<String, Object?> message) {
    final decoded = _decodeJsonString(message);
    if (decoded == null) {
      return;
    }
    _mappingStatus = MappingStatus.fromJson(decoded);
    notifyListeners();
  }

  void _handleMapPreview(Map<String, Object?> message) {
    final decoded = _decodeJsonString(message);
    if (decoded == null) {
      return;
    }
    _mapPreview = MapPreview.fromJson(decoded);
    notifyListeners();
  }

  Map<String, Object?>? _decodeJsonString(Map<String, Object?> message) {
    final raw = message['data'];
    if (raw is! String || raw.isEmpty) {
      return message.isEmpty ? null : message;
    }
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, Object?> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  void _handleRobotEvent(Map<String, Object?> message) {
    final event = RobotEvent.fromRosMsg(message);

    if (event.belongsInHistory) {
      _healthEvents.insert(0, event);
      if (_healthEvents.length > _maxHealthEvents) {
        _healthEvents.removeRange(_maxHealthEvents, _healthEvents.length);
      }
    }

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
  void handleEmergencyStopStateForTest(Map<String, Object?> message) =>
      _handleEmergencyStopState(message);

  @visibleForTesting
  void handleMappingStatusForTest(Map<String, Object?> message) =>
      _handleMappingStatus(message);

  @visibleForTesting
  void handleMapPreviewForTest(Map<String, Object?> message) =>
      _handleMapPreview(message);

  /// rosapi 를 띄우지 않고 모드 선택 화면의 표시 규칙만 검증하기 위한 주입 지점입니다.
  @visibleForTesting
  void setStackStatusForTest(StackStatus? status) {
    _stackStatus = status;
    _stackStatusLoading = false;
    notifyListeners();
  }

  @visibleForTesting
  void handleLocationListForTest(Map<String, Object?> message) =>
      _handleLocationList(message);

  @visibleForTesting
  void handleRobotStatusForTest(Map<String, Object?> message) =>
      _handleRobotStatus(message);

  void _handleEmergencyStopState(Map<String, Object?> message) {
    final active = message['active'] == true;
    final stateMessage = message['message'] as String? ?? '';

    final rawSources = message['sources'];
    final wasTipped = emergencyTipped;
    _emergencyStopSources = rawSources is List
        ? rawSources.map((value) => value.toString()).toList()
        : const [];

    if (_emergencyStopState == EmergencyStopState.activating ||
        _emergencyStopState == EmergencyStopState.releasing) {
      return;
    }

    if (active) {
      if (_emergencyStopState != EmergencyStopState.active) {
        _setEmergencyStopState(
          EmergencyStopState.active,
          stateMessage.isEmpty ? '비상정지가 활성화되어 있습니다.' : stateMessage,
        );
      } else if (stateMessage.isNotEmpty) {
        _setEmergencyStopState(EmergencyStopState.active, stateMessage);
      }
      if (wasTipped != emergencyTipped) {
        notifyListeners();
      }
      return;
    }

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
    _disposed = true;
    _routePreviewTimer?.cancel();
    _teleopTimer?.cancel();
    _reconnectTimer?.cancel();
    _reconnectStableTimer?.cancel();
    _deliveryReturnTimer?.cancel();
    unawaited(_client?.close());
    super.dispose();
  }
}
