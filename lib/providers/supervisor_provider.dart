// 이 파일은 ROS2 연결, 지도/장소/로봇 상태, 알림 로그를 앱 전체 상태로 관리합니다.
import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/app_settings.dart';
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
import '../models/stack_status.dart';
import '../models/supervisor_log.dart';
import '../models/vica_map.dart';
import '../ros/ros_bridge_client.dart';
import '../services/delivery_job_store.dart';
import '../services/delivery_notifier.dart';

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

class SupervisorProvider extends ChangeNotifier {
  /// [deliveryNotifier] 를 안 주면 기기에 맞는 것을 고릅니다 — 안드로이드는 SMS,
  /// 그 밖은 미리보기. 시험은 호스트(리눅스)에서 돌아 자동으로 미리보기가 됩니다.
  SupervisorProvider({
    DeliveryNotifier? deliveryNotifier,
    DeliveryJobStore? deliveryJobStore,
  })  : _deliveryNotifier = deliveryNotifier ?? createDeliveryNotifier(),
        _deliveryStore =
            deliveryJobStore ?? const SharedPreferencesDeliveryJobStore();

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
    'no_home': '홈 위치가 지정되지 않았습니다. 지도 설정 화면에서 먼저 지정하세요.',
    'already_home_bound': '이미 홈으로 돌아가는 중입니다.',
    'busy_approaching': '사람에게 다가가는 중이라 지금은 홈으로 부를 수 없습니다.',
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
  List<String> _emergencyStopSources = const [];
  bool _nav2UnavailableNotified = false;
  bool _nav2AvailableNotified = false;
  bool _nav2WasUnavailable = false;
  // 마지막으로 기록한 오류 사유. 상태 topic이 같은 사유를 계속 실어 보내므로
  // 사유가 실제로 바뀔 때만 알림을 남기기 위해 들고 있습니다.
  String _lastLoggedErrorReason = '';

  // 젯슨에 지금 어떤 스택이 떠 있는지. 모드 선택 화면이 중복 실행을 막는 근거입니다.
  // 상시 구독이 아니라 요청할 때만 갱신합니다 — 노드 목록은 자주 바뀌지 않고,
  // rosapi 조회는 그래프 전체를 훑는 일이라 주기 호출로 둘 만큼 싸지 않습니다.
  // 매핑 세션 상태와 지도 미리보기. 매핑 모드에서만 의미가 있지만, 구독은 연결 시
  // 한 번만 걸고 화면이 바뀌어도 유지합니다 — 구독을 붙였다 뗐다 하면 화면 전환
  // 순간의 메시지를 놓칩니다.
  MappingStatus? _mappingStatus;
  MapPreview? _mapPreview;

  StackStatus? _stackStatus;
  bool _stackStatusLoading = false;
  String _stackStatusError = '';

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

  MappingStatus? get mappingStatus => _mappingStatus;
  MapPreview? get mapPreview => _mapPreview;

  StackStatus? get stackStatus => _stackStatus;
  bool get stackStatusLoading => _stackStatusLoading;
  String get stackStatusError => _stackStatusError;

  /// 지금 연결에 실제로 쓴 rosbridge 주소. 연결한 적이 없으면 빈 문자열입니다.
  ///
  /// 설정의 주소와 다를 수 있습니다 — 주소를 바꿔 저장해도 이미 맺은 연결은
  /// 그대로이기 때문입니다. 화면이 그 차이를 알려야 사람이 "연결됐다는데 왜
  /// 안 되지"로 헤매지 않습니다.
  String get connectedUrl => _lastSettings?.rosBridgeUrl ?? '';

  RosConnectionState get connectionState => _connectionState;
  String get connectionDetail => _connectionDetail;
  EmergencyStopState get emergencyStopState => _emergencyStopState;
  String get emergencyStopMessage => _emergencyStopMessage;

  /// 이번 비상정지가 **사람의 현장 조작**으로 걸렸는가.
  ///
  /// 물리 버튼(`physical_f1`)이나 음성(`voice`)이면 참입니다. 그때만 로봇이
  /// 이용자에게 관리자를 부른다고 안내하므로, 화면도 같은 사실을 알려야
  /// 합니다. 관리자가 앱에서 직접 누른 경우(`app`)는 부르는 사람과 받는 사람이
  /// 같으니 그 문구가 필요 없습니다.
  ///
  /// 통신 원인(`motor_can`·`*_stale`)만으로 걸린 래치도 참이 아닙니다. 그쪽은
  /// 정지 중이면 자동 복구를 밟는 별개 경로입니다(CLAUDE.md).
  bool get emergencyCalledAdmin {
    if (_emergencyStopState != EmergencyStopState.active) {
      return false;
    }
    return _emergencyStopSources.any(
      (source) => source == 'physical_f1' || source == 'voice',
    );
  }

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
    if (mapId != null) {
      refreshMapData(settings, mapId, auto: true);
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
    // 일시정지 표시도 현재 사실이 아닙니다. 끊긴 사이에 누군가 재개했을 수
    // 있으므로 이벤트로 켠 값을 비웁니다. 다시 붙으면 1 Hz 상태 문자열이
    // 진짜 일시정지를 곧바로 복원합니다.
    _pausedByEvent = false;
    // 연결이 끊기면 teleop 반복도 멈춥니다. 로봇은 0.5초 watchdog 으로 서지만,
    // 앱이 계속 보내려 시도하며 로그를 채울 이유가 없습니다.
    _teleopTimer?.cancel();
    _teleopTimer = null;
    _teleopAdvertised = false;
    // 매핑 상태와 미리보기도 현재 사실이 아닙니다.
    _mappingStatus = null;
    _mapPreview = null;
    // 초기 위치 채점 결과는 그때 그 스캔으로 잰 값입니다. 끊긴 뒤에도 남겨 두면
    // 오래된 %를 보고 확정을 누르게 됩니다.
    _poseCheck = null;
    _poseChecking = false;
    // 노드 목록도 현재 사실이 아닙니다. 남겨 두면 모드 선택 화면이 "아무것도 안
    // 떠 있다"고 잘못된 안심을 줄 수 있습니다 — 그래서 '확인 불가'로 되돌립니다.
    _stackStatus = null;
    _stackStatusError = '';
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
      // goal 생명주기. 실패·취소 사유가 여기에만 실려 있습니다 —
      // /robot_status 는 목적지 이름만 비우고 reason 을 버립니다.
      ..subscribe(
        topic: settings.goalEventTopic,
        handler: _handleGoalEvent,
      )
      // 요청 없이 생긴 금지구역 변화만 옵니다(주행이 끝나 미뤄 둔 적용이 된 경우).
      ..subscribe(
        topic: settings.keepoutStateTopic,
        handler: _handleKeepoutState,
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

  /// 지도에 딸린 것을 **한꺼번에** 다시 받아옵니다 — 장소·홈·금지구역.
  ///
  /// 셋은 모두 "이 지도의 저장물"이라 따로 갱신할 이유가 없습니다. 종전에는
  /// 장소만 다시 받는 길(requestLocationList)밖에 없어서 두 가지 구멍이
  /// 있었습니다(2026-09-02 실기).
  ///
  ///   - **앱을 껐다 켜면 홈과 금지구역이 사라져 보였다.** 젯슨에는 파일로
  ///     남아 있는데 앱이 물어보질 않았다. 첫 연결에서는 지도가 아직 안
  ///     정해져 건너뛰고, 지도가 정해지는 순간에는 장소만 요청했다.
  ///   - 화면의 '동기화'·'새로고침' 버튼이 이름과 달리 장소만 갱신했다.
  ///     홈은 앱 전체에 수동 갱신 경로가 아예 없어, 지도를 바꿨다 돌아오는
  ///     것이 유일한 방법이었다.
  ///
  /// 장소 요청은 topic 왕복이고 나머지 둘은 service 라 기다리는 방식이
  /// 다릅니다. 셋 다 실패해도 화면은 이전 값을 그대로 두므로 여기서 결과를
  /// 기다리지 않습니다.
  /// [auto] 는 사람이 누른 것이 아니라 앱이 스스로 부르는 경우입니다. 그때만
  /// 설정의 '장소 목록 자동 요청'을 존중합니다 — 관리자가 그 스위치를 껐다는
  /// 것은 "앱이 알아서 받지 마라"는 뜻이지 "새로고침 버튼도 듣지 마라"가
  /// 아닙니다. 홈·금지구역에는 그런 스위치가 없어 언제나 받습니다.
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
    // 지도가 바뀌면 홈도 다른 것입니다. 이전 지도의 홈을 그대로 보여주면
    // 관리자가 엉뚱한 좌표를 현재 홈으로 믿습니다.
    _home = null;
    _homeMapId = '';
    // 금지구역도 지도마다 다릅니다. 편집 중이었다면 그 편집은 이전 지도의
    // 것이므로 여기서 끝냅니다(화면이 지도 변경 전에 저장 여부를 먼저 묻습니다).
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

  // 임시 목적지를 지도별 destinations 스키마 JSON으로 전송합니다.
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
  ///
  /// 임시 저장 단계가 없습니다 — 이미 있는 장소를 손보는 일이라 되돌릴 대상이
  /// 젯슨에 남아 있고, 같은 id 로 보내면 저장 노드가 그 자리를 덮어씁니다.
  /// 연결이 없으면 보내지 않았다고 분명히 답합니다. 보낸 척하면 관리자는 고쳤다고
  /// 믿고 자리를 뜹니다.
  (bool, String) saveLocation(AppSettings settings, LocationPoint location) {
    final client = _client;
    if (client == null || _connectionState != RosConnectionState.connected) {
      return (false, 'rosbridge 연결이 없어 ${location.name} 을(를) 저장하지 못했습니다.');
    }
    client.publishJsonString(
      topic: settings.saveLocationTopic,
      payload: _locationPayload(location),
    );
    _addLog(LogFilter.coordinateTransfer, '${location.name} 장소 수정 저장 요청 전송');
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
    final (_, message) = await _callRequestDestination(
      settings,
      location,
      service: settings.missionRequestService,
    );
    return message;
  }

  /// 목적지 요청 서비스 호출. 원격 주행과 물류 배송이 같은 문으로 나갑니다.
  ///
  /// 수락 여부를 함께 돌려줍니다 — 배송은 수락됐을 때만 "배송 중"을 기억해야
  /// 하는데, 문구만 받아서는 수락인지 거부인지 가릴 수 없습니다.
  Future<(bool, String)> _callRequestDestination(
    AppSettings settings,
    LocationPoint location, {
    required String service,
  }) async {
    final client = _client;
    if (client == null || _connectionState != RosConnectionState.connected) {
      return (false, 'ROS Bridge에 연결되지 않았습니다.');
    }
    try {
      final response = await client.callService(
        service: service,
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
      return (response.accepted, message);
    } catch (error) {
      final message = 'Mission Manager 목적지 요청 실패: $error';
      _addLog(LogFilter.coordinateTransfer, message);
      return (false, message);
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

  /// 젯슨의 노드 목록을 조회해 어떤 스택이 떠 있는지 갱신합니다.
  ///
  /// rosapi 노드는 rosbridge 가 함께 띄웁니다
  /// (rosbridge_websocket_launch.xml 74행 `<node name="rosapi" ...>`).
  /// supervisor_bringup 을 실행했다면 이 서비스는 이미 있습니다.
  ///
  /// 연결이 없으면 조용히 비웁니다. "확인 불가"와 "아무것도 안 떠 있음"은
  /// 다른 상태이고, 둘을 섞으면 화면이 잘못된 안심을 줍니다.
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
      // /odom 발행자는 '두 벌' 판정의 두 번째 신호입니다. 조회에 실패해도
      // 노드 목록만으로 판정할 수 있으므로 여기서 전체를 실패로 만들지 않습니다.
      List<String> odomPublishers = const [];
      try {
        final publishersResponse = await client.callService(
          service: '/rosapi/publishers',
          type: 'rosapi_msgs/srv/Publishers',
          args: const {'topic': '/odom'},
        );
        odomPublishers = _asStringList(publishersResponse.values['publishers']);
      } catch (_) {
        odomPublishers = const [];
      }

      _stackStatus = StackStatus(
        nodes: _asStringList(nodesResponse.values['nodes']),
        odomPublishers: odomPublishers,
        checkedAt: DateTime.now(),
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

  static List<String> _asStringList(Object? value) {
    if (value is! List) {
      return const [];
    }
    return value.whereType<String>().toList(growable: false);
  }

  /// 저장된 지도를 지웁니다. 되돌릴 수 없습니다.
  ///
  /// "지도 한 장은 사람이 로봇을 끌고 다닌 시간"이라(vica_map_save.sh 주석) 실제
  /// 검사는 노드가 합니다 — 이름 규칙, 지금 쓰는 지도인지, 파일이 있는지.
  /// 앱은 확인을 받고 결과를 보여줄 뿐입니다.
  Future<String> deleteMap(
    AppSettings settings,
    String mapId, {
    required bool deleteDestinations,
  }) async {
    final client = _client;
    if (client == null || _connectionState != RosConnectionState.connected) {
      return 'ROS Bridge에 연결되지 않았습니다.';
    }
    try {
      final response = await client.callService(
        service: settings.deleteMapService,
        type: 'vica_interfaces/srv/DeleteMap',
        args: {
          'map_id': mapId,
          'delete_destinations': deleteDestinations,
        },
      );
      final message = response.message.isEmpty
          ? (response.accepted ? '지도를 지웠습니다.' : '삭제가 거부되었습니다.')
          : response.message;
      _addLog(LogFilter.coordinateTransfer, message);
      if (response.accepted && _selectedMapId == mapId) {
        // 지운 지도를 계속 고른 채로 두면 없는 지도의 장소를 보여주게 됩니다.
        _selectedMapId = null;
        _selectedLocationId = null;
      }
      return message;
    } catch (error) {
      final message = '지도 삭제 요청 실패: $error';
      _addLog(LogFilter.coordinateTransfer, message);
      return message;
    }
  }

  // ---- 홈 위치 ------------------------------------------------------------
  //
  // 홈은 목적지가 아니라 **로봇의 설정값**입니다. 안내가 끝나면 로봇이 스스로
  // 돌아가는 자리이고, 사용자가 고르는 장소가 아닙니다. 그래서 장소 목록과
  // 별도 경로를 쓰며, 홈으로 보내는 것도 관리자 전용 서비스입니다.

  HomePosition? _home;
  bool _homeBusy = false;
  String _homeMapId = '';

  HomePosition? get home => _home;
  bool get homeBusy => _homeBusy;

  /// 지금 들고 있는 홈이 [mapId] 의 것인가.
  ///
  /// 지도를 바꾸면 홈도 다른 것이라 이전 지도의 홈을 계속 보여주면 안 됩니다.
  bool homeBelongsTo(String? mapId) => mapId != null && _homeMapId == mapId;

  /// 지도에 그릴 홈 점. 지도 설정·원격 주행·물류 배송이 전부 이 하나를 씁니다.
  /// 화면마다 따로 계산하면 하나가 빠집니다 — 배송 화면에 홈이 없던 이유다
  /// (2026-09-03 실기).
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
      // 조회 실패와 "홈이 없다"는 다른 사실입니다. 실패했을 때 null 로 두면
      // 관리자가 홈이 지워진 줄 압니다. 이전 값을 그대로 두고 로그만 남깁니다.
      _addLog(LogFilter.coordinateTransfer, '홈 위치를 읽지 못했습니다: $error');
    } finally {
      _homeBusy = false;
      notifyListeners();
    }
  }

  /// 홈을 저장합니다. 저장 직후 [HomePosition.visitedOk] 는 항상 false 입니다.
  ///
  /// 좌표를 정한 것과 그 자리에 실제로 갈 수 있는 것은 다른 사실이고, 후자는
  /// 한 번 가 봐야만 압니다. 로봇을 세워놓고 잡았어도 마찬가지입니다.
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
    final client = _client;
    if (client == null || _connectionState != RosConnectionState.connected) {
      return 'ROS Bridge에 연결되지 않았습니다.';
    }
    _homeBusy = true;
    notifyListeners();
    try {
      final response = await client.callService(
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
      );
      final message = response.message.isEmpty
          ? (response.accepted ? '홈을 저장했습니다.' : '홈을 저장하지 못했습니다.')
          : response.message;
      _addLog(LogFilter.coordinateTransfer, message);
      if (response.accepted) {
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
      }
      return message;
    } catch (error) {
      final message = '홈 저장 실패: $error';
      _addLog(LogFilter.coordinateTransfer, message);
      return message;
    } finally {
      _homeBusy = false;
      notifyListeners();
    }
  }

  Future<String> deleteHome(AppSettings settings, String mapId) async {
    final client = _client;
    if (client == null || _connectionState != RosConnectionState.connected) {
      return 'ROS Bridge에 연결되지 않았습니다.';
    }
    _homeBusy = true;
    notifyListeners();
    try {
      final response = await client.callService(
        service: settings.homeDeleteService,
        type: 'vica_interfaces/srv/DeleteHome',
        args: {'map_id': mapId},
      );
      final message = response.message.isEmpty
          ? (response.accepted ? '홈을 지웠습니다.' : '홈을 지우지 못했습니다.')
          : response.message;
      _addLog(LogFilter.coordinateTransfer, message);
      if (response.accepted) {
        _home = null;
      }
      return message;
    } catch (error) {
      final message = '홈 삭제 실패: $error';
      _addLog(LogFilter.coordinateTransfer, message);
      return message;
    } finally {
      _homeBusy = false;
      notifyListeners();
    }
  }

  /// 로봇을 홈으로 보냅니다. **관리자만 부를 수 있는 경로입니다.**
  ///
  /// 지도 설정 화면의 '홈으로 가보기'와 원격 주행 화면의 '홈으로 복귀'가 같은
  /// 서비스를 부릅니다. 하는 일이 같기 때문이고, 다른 것은 관리자가 그 결과를
  /// 무엇으로 쓰느냐뿐입니다 — 지정 확인이냐 운영 호출이냐.
  ///
  /// 허용 여부는 Mission Manager 가 판정합니다. 안내 주행 중이면 거부되는데,
  /// 사용자가 핸들을 잡고 따라 걷는 중에 로봇이 방향을 틀면 **사용자는 자기가
  /// 어디로 끌려가는지 모르기** 때문입니다.
  Future<String> returnHome(AppSettings settings) async {
    final (_, message) = await _callReturnHome(settings);
    return message;
  }

  /// 홈 복귀 서비스 호출. 관리자 버튼과 배송 자동 복귀가 같은 문으로 나갑니다.
  /// 배송은 수락됐을 때만 '복귀 중'으로 옮겨야 해서 수락 여부를 함께 돌려줍니다.
  Future<(bool, String)> _callReturnHome(AppSettings settings) async {
    final client = _client;
    if (client == null || _connectionState != RosConnectionState.connected) {
      return (false, 'ROS Bridge에 연결되지 않았습니다.');
    }
    try {
      final response = await client.callService(
        service: settings.missionReturnHomeService,
        type: 'vica_interfaces/srv/MissionCommand',
        args: {'request_id': _uuid.v4()},
      );
      final message = response.message.isEmpty
          ? (response.accepted ? '홈으로 복귀합니다.' : '홈 복귀 요청이 거부되었습니다.')
          : _localizeGateReason(response.message);
      _addLog(LogFilter.coordinateTransfer, message);
      return (response.accepted, message);
    } catch (error) {
      final message = '홈 복귀 요청 실패: $error';
      _addLog(LogFilter.coordinateTransfer, message);
      return (false, message);
    }
  }

  // ---- 물류 배송 -----------------------------------------------------------
  //
  // 배송은 원격 주행에 "도착하면 이 번호로 문자"를 얹은 것입니다. 주행 자체는
  // 같은 서비스로 나가고(Mission·Safety 우회 없음), 앱은 **지금 배송 중인 건**
  // 하나만 기억합니다. 로봇은 배송인지 모릅니다 — goal 이벤트에 목적지 id 만
  // 실려 오므로, 그 id 가 기억해 둔 배송의 것이면 도착으로 칩니다.

  DeliveryJob? _delivery;
  DeliveryNotifier _deliveryNotifier;
  DeliveryNotice? _pendingDeliveryNotice;
  final DeliveryJobStore _deliveryStore;

  /// 저장소에서 되살린 배송을 아직 로봇 상태와 대조하지 못했다. 앱이 꺼진 사이의
  /// goal 이벤트는 못 받았으므로(VOLATILE) 첫 /robot_status 로 맞춰 본다.
  bool _deliveryNeedsReconcile = false;

  /// 도착 뒤 홈으로 출발시키는 시계. 배송을 새로 시작하거나 지우거나 관리자가
  /// 복귀를 취소하면 멈춥니다. 앱이 닫히면 시계는 사라지지만 예정 시각은
  /// 저장돼 있어, 다시 켜면 남은 시간만큼 다시 겁니다([restoreDelivery]).
  Timer? _deliveryReturnTimer;

  /// 배송 기억을 바꾸는 유일한 자리. 바꿀 때마다 기기 저장소에도 적어 앱을
  /// 껐다 켜도 이어받습니다(2026-09-03 사용자 결정).
  void _setDelivery(DeliveryJob? job) {
    _delivery = job;
    unawaited(_deliveryStore.save(job));
  }

  /// 젯슨이 지금 쓰는 지도(maps/CURRENT_MAP). 지도 목록 노드가 실어 보냅니다.
  /// 옛 노드는 안 실어 빈 값입니다.
  String _currentMapId = '';
  String get currentMapId => _currentMapId;

  /// 앱을 켤 때 지난 배송을 기기 저장소에서 되살립니다. main 이 연결 전에 부릅니다.
  ///
  /// 되살린 것을 그대로 믿지 않습니다 — 앱이 꺼진 사이 로봇이 도착했거나 섰을
  /// 수 있고 그 이벤트는 못 받았습니다. 첫 로봇 상태가 오면
  /// [_reconcileRestoredDelivery] 가 대조합니다. 복귀 예정이 남아 있으면 남은
  /// 시간만큼 시계를 다시 겁니다. 예정 시각이 이미 지났으면 **움직이지 않습니다**
  /// — 앱을 켰다고 로봇이 출발하면 안 됩니다. 관리자가 버튼을 다시 누릅니다.
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
        _addLog(LogFilter.delivery, '$name 배송 이어받음 — ${left.inSeconds}초 뒤 홈 복귀');
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
  ///
  /// 상태 노드가 주는 것은 목적지 **이름**뿐이라 이름으로 봅니다. 배송 중이었는데
  /// 로봇이 그 목적지로 가고 있지 않으면 어떻게 끝났는지 알 수 없습니다 —
  /// '확인 필요'로 두고 관리자가 로봇을 보고 고릅니다. 앱이 짐작으로 문자를
  /// 보내지는 않습니다.
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
          returnNote: '앱이 꺼진 사이 홈 복귀가 끝났거나 멈췄습니다. 로봇 위치를 보고 지우거나 다시 보내세요.',
        ));
        _addLog(LogFilter.delivery, '$name 배송 홈 복귀 결과를 확인하지 못했습니다');
      default:
        return;
    }
  }

  /// '확인 필요' 배송을 관리자가 도착으로 처리합니다. 로봇이 문 앞에 있는 것을
  /// 눈으로 본 뒤 누릅니다. 문자를 아직 안 보냈으면 보내고, 복귀 시계를 겁니다.
  Future<String> confirmDeliveryArrival() async {
    final job = _delivery;
    if (job == null || job.phase != DeliveryPhase.unconfirmed) {
      return '도착 처리할 배송이 없습니다.';
    }
    _markDeliveryArrived(job, sendText: !job.notified);
    return '${job.destination.name} 도착으로 처리했습니다.';
  }

  /// 지금 기억하고 있는 배송. 끝난 뒤에도 관리자가 '지우기'를 누를 때까지 남아
  /// 결과를 보여줍니다.
  DeliveryJob? get delivery => _delivery;

  /// 발송 수단 이름. 화면 배지에 씁니다.
  String get deliveryNotifierLabel => _deliveryNotifier.modeLabel;

  /// 아직 화면이 보여주지 않은 도착 문자 결과. 화면이 팝업을 띄우고
  /// [consumeDeliveryNotice] 로 비웁니다.
  DeliveryNotice? get pendingDeliveryNotice => _pendingDeliveryNotice;

  void consumeDeliveryNotice() {
    if (_pendingDeliveryNotice == null) {
      return;
    }
    _pendingDeliveryNotice = null;
    notifyListeners();
  }

  /// 배송 출발. 주행 요청이 **수락됐을 때만** 배송을 기억합니다.
  ///
  /// 거부된 요청을 기억해 두면 다음에 누가 그 장소로 안내 주행을 해서 도착했을
  /// 때 엉뚱하게 배송 문자가 나갑니다.
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
    // 배송 전용 서비스로 나갑니다. 요청 모양은 같고 private 목적지만 추가로
    // 허용됩니다. 나머지 검사(접근 가능·지도 안·Nav2·E-stop)는 그대로입니다.
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
  /// 예정이 살아 있으면 지우지 않습니다 — 기억만 지우면 도착·복귀 결과를 화면이
  /// 못 잇고, 예정된 복귀가 관리자 모르게 나갑니다. 먼저 취소하세요.
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
  /// '지금 복귀'나 원격 주행 화면의 홈 복귀로 부를 수 있습니다.
  void cancelDeliveryReturn() {
    final job = _delivery;
    if (job == null || !job.isWaitingToReturn) {
      return;
    }
    _cancelDeliveryReturnTimer();
    _setDelivery(job.copyWith(clearReturnAt: true, returnNote: '관리자가 복귀를 취소했습니다.'));
    _addLog(LogFilter.delivery, '${job.destination.name} 배송 홈 복귀 취소(관리자)');
    notifyListeners();
  }

  void _cancelDeliveryReturnTimer() {
    _deliveryReturnTimer?.cancel();
    _deliveryReturnTimer = null;
  }

  /// 도착 뒤 [deliveryReturnDelay] 를 재기 시작합니다. 되살린 배송은 남은
  /// 시간([delay])만 잽니다.
  void _scheduleDeliveryReturn(DeliveryJob job, {Duration? delay}) {
    _cancelDeliveryReturnTimer();
    _deliveryReturnTimer = Timer(delay ?? deliveryReturnDelay, () {
      _deliveryReturnTimer = null;
      // 시계가 울릴 때는 화면이 없을 수 있어 마지막 접속 설정을 씁니다. 접속한
      // 적이 없으면 설정도 없지만, 그때는 클라이언트도 없어 어차피 거부됩니다.
      unawaited(_returnHomeForDelivery(_lastSettings ?? const AppSettings()));
    });
  }

  /// 홈 복귀 서비스를 부르고, 수락됐을 때만 '홈 복귀 중'으로 옮깁니다.
  ///
  /// 거부·실패(홈 미지정, E-stop, 연결 끊김)면 도착 상태로 남기고 사유를 적습니다.
  /// 그러면 화면에 '다시 복귀'와 '지우기'가 다시 열립니다 — 로봇은 문 앞에 서 있고
  /// 관리자가 판단합니다.
  Future<String> _returnHomeForDelivery(AppSettings settings) async {
    final job = _delivery;
    if (job == null || job.phase != DeliveryPhase.arrived) {
      return '복귀시킬 배송이 없습니다.';
    }
    final (accepted, message) = await _callReturnHome(settings);
    final current = _delivery;
    if (current == null || current.phase != DeliveryPhase.arrived) {
      // 기다리는 사이 관리자가 지우거나 새 배송을 시작했습니다.
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
      _addLog(LogFilter.delivery, '${job.destination.name} 배송 홈 복귀 거부: $message');
    }
    notifyListeners();
    return message;
  }

  /// goal 이벤트 중 이 배송에 해당하는 것만 골라 상태를 옮깁니다.
  ///
  /// 목적지로 가는 중에는 목적지 id 로 맞추고, 홈 복귀 중에는 홈 복귀 이벤트
  /// (`return_home_*`)를 봅니다 — 홈은 카탈로그에 없어 id 가 `__home__` 이라
  /// 목적지 비교로는 잡히지 않습니다.
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
    if (!job.matches(locationId: event.locationId, name: event.destinationName)) {
      return;
    }
    switch (event.kind) {
      case GoalEventKind.succeeded:
        _markDeliveryArrived(job, sendText: true);
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
  /// 오면 결과가 돌아오기 전에 두 번째 발송이 나갈 수 있습니다. [sendText] 가
  /// false 면 이미 보낸 것으로 보고 복귀 시계만 겁니다('확인 필요' 처리).
  void _markDeliveryArrived(DeliveryJob job, {required bool sendText}) {
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
      '${job.destination.name} 배송 도착 — ${sendText ? '문자 발송 시도' : '문자는 이미 보냄'}, '
      '${deliveryReturnDelay.inMinutes}분 뒤 홈 복귀',
    );
    _scheduleDeliveryReturn(arrived);
    if (sendText) {
      unawaited(_notifyDeliveryArrival(arrived));
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
      // 앱의 '복귀 취소'·비상정지·Nav2 거부는 미션이 일반 이름(goal_canceled 등)
      // 으로 냅니다 — on_app_cancel 은 상태를 가리지 않고 같은 취소를 씁니다.
      // 홈 이름만 기다리면 카드가 '홈 복귀 중'에 영영 남고 지우기도 잠깁니다
      // (2026-09-03 검토). state_idle 은 "취소했는데 달리는 게 없었다"라 같은 뜻.
      case GoalEventKind.failed:
      case GoalEventKind.rejected:
      case GoalEventKind.canceled:
      case GoalEventKind.emergencyStopped:
      case GoalEventKind.stateIdle:
        // 로봇은 도중에 섰습니다. 도착 상태로 되돌려 관리자가 다시 보내거나
        // 지울 수 있게 합니다. 자동으로 다시 시도하지 않습니다 — 실패한 길을
        // 사람 없이 또 가는 것은 E-stop 뒤 자동 재개 금지와 같은 이유로 피합니다.
        _setDelivery(job.copyWith(
          phase: DeliveryPhase.arrived,
          clearReturnAt: true,
          returnNote: event.reason.isEmpty ? event.title : event.reason,
        ));
        _addLog(LogFilter.delivery, '${job.destination.name} 배송 홈 복귀 중단 (${event.title})');
      default:
        break;
    }
  }

  Future<void> _notifyDeliveryArrival(DeliveryJob job) async {
    final text = deliveryArrivalMessage(job.destination.name);
    DeliveryNotifyResult result;
    try {
      result = await _deliveryNotifier.send(
        phone: job.destination.contactPhone,
        text: text,
      );
    } catch (error) {
      result = DeliveryNotifyResult(sent: false, detail: '발송 오류: $error');
    }
    // 로그에는 장소 이름과 결과만 남깁니다. 번호는 개인정보입니다.
    _addLog(
      LogFilter.delivery,
      '${job.destination.name} 도착 문자 ${result.sent ? '발송됨' : '미발송'}: ${result.detail}',
    );
    _pendingDeliveryNotice = DeliveryNotice(job: job, text: text, result: result);
    notifyListeners();
  }

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

  // ---- goal 생명주기 알림 --------------------------------------------------
  //
  // 실패·취소를 관리자에게 알리는 경로입니다. 종전에는 /robot_status 를 거치며
  // 사유가 버려져 **주행이 조용히 사라진 것처럼** 보였습니다.

  GoalEvent? _pendingGoalAlert;

  /// 아직 관리자에게 보여주지 않은 알림. 화면이 팝업을 띄우고 [consumeGoalAlert]
  /// 를 불러 비웁니다.
  GoalEvent? get pendingGoalAlert => _pendingGoalAlert;

  void consumeGoalAlert() {
    if (_pendingGoalAlert == null) {
      return;
    }
    _pendingGoalAlert = null;
    notifyListeners();
  }

  // ---- 일시정지 판정 -------------------------------------------------------
  //
  // 종전에는 화면이 /robot_status 의 waiting_reason 문자열이 정확히 '일시정지'
  // 인지로만 판정했다. 그것 하나에 기대면 **재개 버튼이 아예 안 뜬다** —
  // waiting_reason 은 오류·Nav2 미실행·odom 지연을 먼저 검사하고 그중 하나라도
  // 걸리면 일시정지를 덮어쓰기 때문이다(vica_status_app_node._waiting_reason).
  // 문구를 한 글자만 바꿔도 깨지는 것은 덤이다.
  //
  // 그래서 goal 이벤트를 정본으로 삼고, 문자열은 보조로만 쓴다. 둘 중 하나라도
  // 일시정지라고 하면 일시정지다 — 재개 버튼이 안 뜨는 쪽이 잘못 뜨는 쪽보다
  // 훨씬 나쁘다. 잘못 떠도 Mission Manager 가 게이트에서 거부할 뿐이다.
  bool _pausedByEvent = false;

  /// 지금 일시정지 상태인가. 화면은 이 값으로 버튼을 고른다.
  bool get navigationPaused {
    if (_pausedByEvent) {
      return true;
    }
    // 앱이 일시정지 중에 새로 접속하면 그 사이의 이벤트를 못 받는다.
    // 1 Hz 로 계속 오는 상태 문자열이 그 구멍을 메운다.
    final robot = primaryRobot;
    return robot != null && robot.waitingReason.trim() == '일시정지';
  }

  void _handleGoalEvent(Map<String, Object?> message) {
    final event = GoalEvent.fromJson(message, id: _uuid.v4());

    // 일시정지 표시를 여기서 켜고 끕니다. 새 goal 이 나가거나 주행이 어떤
    // 식으로든 끝나면 일시정지가 아닙니다 — 재개·취소·도착·실패가 모두
    // 여기 걸립니다.
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
      // 홈 복귀의 끝도 주행의 끝입니다. 빠뜨리면 홈 복귀 앞뒤로 일시정지
      // 표시가 남아 '다시 출발' 버튼이 헛되이 뜹니다(2026-09-02).
      case GoalEventKind.returnHomeSucceeded:
      case GoalEventKind.returnHomeFailed:
      case GoalEventKind.returnHomeCanceled:
      case GoalEventKind.stateIdle:
        _pausedByEvent = false;
      default:
        break;
    }

    // 배송 중이면 이 이벤트가 그 배송의 도착·중단일 수 있습니다.
    _applyGoalEventToDelivery(event);

    // 홈 복귀가 성공하면 그 홈은 '가 본 자리'가 됩니다. 젯슨이 home.yaml 에
    // 이미 기록했지만, 앱 화면의 경고를 바로 내리기 위해 여기서도 반영합니다.
    if (event.kind == GoalEventKind.returnHomeSucceeded && _home != null) {
      _home = _home!.copyWith(visitedOk: true);
    } else if (event.kind == GoalEventKind.returnHomeFailed && _home != null) {
      _home = _home!.copyWith(visitedOk: false);
    }

    if (event.needsPopup) {
      // 비상정지가 걸려 있는 동안의 '취소'는 팝업으로 띄우지 않습니다.
      //
      // 주행 중에 물리 버튼을 누르면 두 가지가 함께 일어납니다 — 비상정지가
      // 걸리고, 가던 목적지가 취소됩니다. 그러면 전체화면 비상정지 알림 위에
      // "주행이 취소되었습니다"가 한 번 더 겹칩니다. 같은 사건을 두 번 알리는
      // 것이고, 그렇게 쌓인 팝업은 관리자가 읽지 않고 닫는 습관을 만듭니다
      // (성공을 팝업으로 알리지 않는 것과 같은 이유입니다).
      //
      // **실패는 막지 않습니다.** 주행 실패는 아무도 누르지 않았는데 로봇이
      // 스스로 포기한 별개의 사건이라 비상정지와 겹칠 일이 없습니다.
      // 취소 사실은 아래 알림 목록에 그대로 남습니다.
      final hiddenByEmergency = event.kind == GoalEventKind.canceled &&
          _emergencyStopState == EmergencyStopState.active;
      if (!hiddenByEmergency) {
        _pendingGoalAlert = event;
      }
      // 팝업과 별개로 알림 목록에도 남깁니다. 팝업은 그 자리에서 닫히지만
      // 목록은 나중에 되짚을 수 있어야 합니다.
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

  // ---- Nav2 초기 위치 잡기 ----------------------------------------------
  //
  // 확인과 확정을 나눈 이유는 /initialpose 를 발행하는 순간 되돌릴 수 없기
  // 때문입니다. 확인은 젯슨의 pose_bootstrap_node 가 점수만 계산하고 AMCL 을
  // 건드리지 않습니다. 확정에서만 반영합니다.

  PoseCheckResult? _poseCheck;
  bool _poseChecking = false;

  PoseCheckResult? get poseCheck => _poseCheck;
  bool get poseChecking => _poseChecking;

  /// 확정 뒤 AMCL 자세에서 본 라이다 점입니다.
  ///
  /// 확인 단계의 점은 [poseCheck] 안에 있고, 이것은 **반영이 끝난 뒤** 것입니다.
  /// 둘을 나눠 두는 이유는 확정하면 poseCheck 를 비우기 때문입니다 — 그때 점도
  /// 함께 사라지면 "제대로 반영됐나"를 볼 그림이 없습니다.
  List<Offset> get committedScanHits => _committedScanHits;
  List<Offset> _committedScanHits = const [];

  void clearPoseCheck() {
    if (_poseCheck == null && !_poseChecking && _committedScanHits.isEmpty) {
      return;
    }
    _poseCheck = null;
    _poseChecking = false;
    // 확정 뒤 남겨 둔 점도 함께 지웁니다. 새로 잡기 시작했는데 지난 회차의
    // 점이 지도에 남아 있으면 방금 확인한 것으로 오해합니다.
    _committedScanHits = const [];
    notifyListeners();
  }

  /// 지도에서 짚은 자리를 채점합니다. AMCL 은 건드리지 않습니다.
  ///
  /// [yawHint] 는 사람이 4방향 버튼으로 고른 값입니다. 사람 손은 각도를 10~20도
  /// 밖에 못 주므로 그대로 쓰지 않고 탐색 중심으로만 씁니다 — 정밀한 각도는 노드가
  /// 1도 간격으로 찾습니다. 힌트가 있으면 후보가 8712 -> 2299 로 줄어 2.6배
  /// 빨라지고, 대칭 복도에서 180도 뒤집힌 자세가 후보에 들어오지 않습니다.
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
        // 개발 PC 실측 8~84 ms, 젯슨 추정 100~340 ms 입니다
        // (docs/pose_bootstrap_bench.md). 10초는 노드가 없을 때를 위한 여유입니다.
        timeout: const Duration(seconds: 10),
      );
      final result = PoseCheckResult.fromValues(response.values);
      _poseCheck = result;
      // 확인은 로그에 남기지 않는다. 결과는 화면 점수 상자에 바로 보이는 탐색
      // 행위이고, 한 번 잡을 때 수십 번 눌러 목록을 채웠다(2026-08-25 실기).
      // 로그에는 되돌릴 수 없는 일만 남긴다 — 확정 성공·거부, 그리고 확인
      // '실패'(채점 노드 무응답)는 시스템 이상이므로 아래 catch 에서 남긴다.
      return result.message;
    } catch (error) {
      _poseCheck = null;
      // 가장 흔한 실패는 젯슨에서 채점 노드를 안 띄운 것이다. 원인 문자열만
      // 던지면 관리자가 다음에 할 일을 모른다.
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
  ///
  /// 노드가 /initialpose 를 내고, 0.5초 뒤 /request_nomotion_update 를 부르고,
  /// 2초 뒤 AMCL 자세를 같은 잣대로 다시 채점해서 돌려줍니다. 그래서 응답이
  /// 3초 가까이 걸립니다.
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
        // 노드가 안에서 0.5 + 2.0초를 기다립니다.
        timeout: const Duration(seconds: 12),
      );
      final message = response.message.isEmpty
          ? (response.accepted ? '초기 위치를 반영했습니다.' : '반영이 거부되었습니다.')
          : response.message;
      _addLog(LogFilter.coordinateTransfer, message);
      if (response.accepted) {
        // 반영이 끝나면 화면을 1단계로 되돌립니다. 남겨 두면 이미 반영한 값을
        // 다시 확정할 수 있게 보입니다.
        _poseCheck = null;
        // 다만 라이다 점은 남깁니다. **반영 뒤 AMCL 이 믿는 자세**에서 본
        // 것이라, 확정이 제대로 됐는지 눈으로 확인할 수 있는 마지막 그림입니다.
        // 지도를 바꾸거나 초기 위치 잡기를 다시 열면 지워집니다.
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

  // ---- 금지구역 ----------------------------------------------------------
  //
  // 앱이 그린 사각형은 로봇이 들어가지 않을 자리입니다. Nav2 는 이것을 원본
  // 지도와 별도인 마스크 파일로 읽으므로, 앱은 원본 지도를 건드리지 않습니다.
  //
  // **저장과 적용은 다른 일입니다.** 저장은 파일을 쓰는 것이고, 적용은 지금
  // 도는 Nav2 에 반영하는 것입니다. 주행 중에는 적용을 미룹니다 — 로봇이 새
  // 금지구역 안에 서 있으면 planner 가 "Starting point in lethal space" 로
  // 실패합니다. 그래서 화면에 '저장됨'과 '적용됨'을 따로 보여줘야 합니다.

  final Map<String, List<KeepoutZone>> _keepoutsByMap = {};
  bool _keepoutEditing = false;
  Offset? _keepoutDragStart;
  Offset? _keepoutDragCurrent;
  String? _selectedKeepoutZoneId;
  KeepoutSaveState _keepoutState = KeepoutSaveState.idle;
  String _keepoutMessage = '';
  bool _keepoutMaskApplied = false;
  int _keepoutZoneSeq = 0;
  // 편집을 시작할 때의 목록입니다. '취소'가 되돌릴 자리를 알아야 합니다.
  List<KeepoutZone> _keepoutBackup = const [];

  List<KeepoutZone> keepoutZonesFor(String? mapId) =>
      mapId == null ? const [] : (_keepoutsByMap[mapId] ?? const []);
  bool get keepoutEditing => _keepoutEditing;
  String? get selectedKeepoutZoneId => _selectedKeepoutZoneId;
  KeepoutSaveState get keepoutState => _keepoutState;
  String get keepoutMessage => _keepoutMessage;
  bool get keepoutMaskApplied => _keepoutMaskApplied;

  // 그려 봤지만 아직 '확정'하지 않은 사각형입니다(2026-09-01 UX 변경).
  // 종전에는 손을 뗄 때마다 목록에 새 사각형이 쌓여서, 자리를 다듬으려고
  // 다시 그리면 사각형이 늘어났습니다. 이제 다시 끌면 이 초안이 **교체**되고,
  // '확정'을 눌러야 목록에 들어갑니다.
  KeepoutZone? _pendingZone;

  bool get hasPendingKeepoutZone => _pendingZone != null;

  /// 드래그 중엔 끌고 있는 사각형을, 아니면 미확정 초안을 보여줍니다.
  /// 둘 다 목록 밖이라 캔버스에서 같은(초안) 모양으로 그려집니다.
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
  ///
  /// 너무 작으면 버립니다. 젯슨도 같은 기준으로 거절하는데(0.1 m), 거기까지
  /// 갔다 와서 거절당하면 왜 안 됐는지가 화면에 늦게 나타납니다.
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
    // 목록에 넣지 않고 초안으로만 둔다. 다시 끌면 이 초안이 교체되고,
    // confirmPendingKeepoutZone 이 눌려야 목록에 들어간다(2026-09-01).
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
  ///
  /// 실패해도 그린 사각형은 지우지 않습니다. 다시 시도할 수 있어야 합니다.
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

    // 확정을 안 누르고 저장한 초안은 확정으로 간주한다 — 그린 사각형이
    // 소리 없이 버려지는 것이 가장 나쁜 실수 방식이다.
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
        // 젯슨이 마스크를 쓰고 Nav2 응답까지 기다립니다(노드 내부 3초).
        timeout: const Duration(seconds: 8),
      );
      _keepoutMessage = response.message;
      if (response.accepted) {
        _keepoutState = KeepoutSaveState.succeeded;
        _keepoutEditing = false;
        _keepoutMaskApplied = response.values['applied'] == true;
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
  ///
  /// 지금은 하나뿐입니다 — 주행 중이라 미뤄 뒀던 적용이 주행이 끝나 이뤄진 경우.
  /// 요청의 결과는 service 응답으로 오므로 여기서 다시 알리지 않습니다.
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

  // ---- 매핑 세션 제어 ---------------------------------------------------
  //
  // 앱은 프로세스를 직접 띄우지 않습니다. 젯슨에 상주하는 mapping_supervisor_node
  // 가 자식을 소유하고, 앱은 서비스만 부릅니다. 앱이 꺼져도 고아 프로세스가 남지
  // 않게 하기 위해서입니다.

  Future<String> startMapping(AppSettings settings) {
    return _callMappingTrigger(settings.mappingStartService, '매핑을 시작했습니다.');
  }

  Future<String> stopMapping(AppSettings settings) {
    return _callMappingTrigger(settings.mappingStopService, '매핑을 종료했습니다.');
  }

  Future<String> _callMappingTrigger(String service, String fallback) async {
    final client = _client;
    if (client == null || _connectionState != RosConnectionState.connected) {
      return 'ROS Bridge에 연결되지 않았습니다.';
    }
    try {
      final response = await client.callService(
        service: service,
        type: 'std_srvs/srv/Trigger',
        // 시작은 launch 를 띄우는 일이라 응답이 조금 늦을 수 있습니다.
        timeout: const Duration(seconds: 15),
      );
      final message = response.message.isEmpty ? fallback : response.message;
      _addLog(LogFilter.coordinateTransfer, message);
      return message;
    } catch (error) {
      final message = '매핑 요청 실패: $error';
      _addLog(LogFilter.coordinateTransfer, message);
      return message;
    }
  }

  /// 지도를 저장합니다. 이름은 사람이, 날짜는 로봇이 붙입니다.
  ///
  /// 서비스는 곧바로 응답하고 실제 저장은 젯슨에서 따로 돕니다 — vica_map_save.sh
  /// 가 최대 120초까지 걸릴 수 있어 기다리면 다른 요청이 전부 막힙니다. 결과는
  /// /vica/mapping_status 의 detail 로 옵니다.
  Future<String> saveMap(AppSettings settings, String name) async {
    final client = _client;
    if (client == null || _connectionState != RosConnectionState.connected) {
      return 'ROS Bridge에 연결되지 않았습니다.';
    }
    try {
      final response = await client.callService(
        service: settings.mappingSaveService,
        type: 'vica_interfaces/srv/SaveMap',
        args: {'name': name},
      );
      final message = response.message.isEmpty
          ? (response.accepted ? '저장을 시작했습니다.' : '저장이 거부되었습니다.')
          : response.message;
      _addLog(LogFilter.coordinateTransfer, message);
      return message;
    } catch (error) {
      final message = '지도 저장 요청 실패: $error';
      _addLog(LogFilter.coordinateTransfer, message);
      return message;
    }
  }

  // ---- 매핑 teleop -----------------------------------------------------
  //
  // 젯슨 터미널의 teleop 칸과 **같은 경로**를 씁니다.
  //     ros2 run teleop_twist_keyboard ... -r /cmd_vel:=/cmd_vel_req
  // 즉 /cmd_vel_req -> Safety Supervisor -> /cmd_vel_safe -> motor 로,
  // Safety 를 우회하지 않습니다.
  //
  // **데드맨은 이미 두 겹 있습니다.** safety_supervisor_node 와
  // mdrobot_can_control 이 각각 cmd_timeout_sec 0.5 를 갖습니다. 앱이 명령을
  // 멈추면(손을 뗌·WiFi 끊김·앱 종료) 0.5초 안에 두 계층이 각각 정지시킵니다.
  // 그래서 이 코드는 **누르고 있는 동안만** 발행합니다 — 한 번 눌러 계속 가게
  // 만들면 그 안전장치가 통째로 무력해집니다.

  static const teleopTopic = '/cmd_vel_req';
  static const _teleopType = 'geometry_msgs/Twist';

  // 매핑 주행 상한. docs/cartographer_corridor_mapping.md 4절이 근거입니다 —
  // "직진 0.3 m/s, 회전 0.4 rad/s 아래. 예측 탐색 창이 0.1 m 라 0.5 m/s 면
  //  스캔 사이 이동이 10 cm 로 창 경계에 닿는다".
  //
  // Safety 의 상한(1.0 / 2.0)은 실주행 상한의 3.8~5배라 폭주만 막고 일상 제한은
  // 못 합니다(nav2_backlog.md C8). 그래서 보내는 값 자체를 여기서 묶습니다.
  static const teleopMaxLinear = 0.3;
  static const teleopMaxAngular = 0.4;

  // 20 Hz. Safety 의 0.5초 시한보다 10배 촘촘해 한두 장을 놓쳐도 끊기지 않습니다.
  static const _teleopPeriod = Duration(milliseconds: 50);

  Timer? _teleopTimer;
  bool _teleopAdvertised = false;
  double _teleopLinear = 0;
  double _teleopAngular = 0;

  bool get teleopActive => _teleopTimer != null;

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
  ///
  /// 0을 보내지 않아도 0.5초 뒤 watchdog 이 세우지만, 그동안 로봇이 굴러갑니다.
  /// 명시적인 0이 즉시 세웁니다.
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
      // 연결이 끊겼으면 더 보낼 수도 없고 보낼 필요도 없습니다. watchdog 이 세웁니다.
      _teleopTimer?.cancel();
      _teleopTimer = null;
      _teleopAdvertised = false;
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
    // 앱을 켠 직후에는 젯슨이 지금 쓰는 지도(maps/CURRENT_MAP)를 고릅니다.
    // 종전에는 목록 첫 번째(이름순)를 골라, 오늘 새로 그린 지도가 앞에 오면
    // 로봇이 달리는 지도와 다른 지도를 보고 있었습니다(2026-09-03). 관리자가
    // 이미 고른 지도는 바꾸지 않습니다.
    _selectedMapId ??= _initialMapChoice(_maps);
    // 첫 연결에서는 선택된 지도가 없어 장소를 함께 요청하지 못합니다.
    // 지도가 처음 정해지는 이 시점에 그 지도의 장소도 받아옵니다.
    final mapId = _selectedMapId;
    final settings = _lastSettings;
    if (hadNoSelection && mapId != null && settings != null) {
      // 홈·금지구역까지 함께 받는다. 종전에는 장소만 받아서, 앱을 새로 켜면
      // 젯슨에 저장돼 있는 홈과 금지구역이 화면에서 사라져 보였다
      // (2026-09-02 실기). 지도를 바꿨다 돌아와야 나타나던 이유가 이것이다.
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

  // 두 토픽 모두 std_msgs/String 의 data 에 JSON 을 담습니다. 파싱 실패는 조용히
  // 버립니다 — 깨진 한 건 때문에 화면이 죽으면 안 됩니다.
  //
  // [중요] RosBridgeClient 는 data 가 String 인 메시지를 **이미 풀어서** 내용물
  // JSON 만 handler 에 넘깁니다. 그 경우 여기 오는 message 에는 'data' 키가
  // 없습니다 — 그걸 다시 찾으면 전부 버려집니다. 2026-08-25 매핑 실기에서
  // "로봇 상태를 아직 받지 못했습니다"가 영영 안 풀린 원인이 정확히 이것입니다
  // (발행 1 Hz·rosbridge 구독까지 전부 정상인데 앱만 못 받음).
  Map<String, Object?>? _decodeJsonString(Map<String, Object?> message) {
    final raw = message['data'];
    if (raw is! String || raw.isEmpty) {
      // 이미 풀린 내용물이다. 그대로 쓴다. (mapping_status·map_preview 의 JSON
      // 에는 'data' 키가 없어 두 경우가 섞일 일이 없다.)
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
  void handleEmergencyStopStateForTest(Map<String, Object?> message) =>
      _handleEmergencyStopState(message);

  @visibleForTesting
  void handleMappingStatusForTest(Map<String, Object?> message) =>
      _handleMappingStatus(message);

  @visibleForTesting
  void handleMapPreviewForTest(Map<String, Object?> message) =>
      _handleMapPreview(message);

  /// 젯슨 없이 초기 위치 화면의 표시 규칙만 검증하기 위한 주입 지점입니다.
  @visibleForTesting
  void setPoseCheckForTest(PoseCheckResult? result) {
    _poseCheck = result;
    _poseChecking = false;
    notifyListeners();
  }

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

  // /app_estop_state 주기 브로드캐스트로 오버레이 상태를 노드 실제 상태에 맞춥니다.
  // 앱이 비상정지 중에 재접속하면 이 토픽으로 활성 오버레이를 복구합니다.
  void _handleEmergencyStopState(Map<String, Object?> message) {
    final active = message['active'] == true;
    final stateMessage = message['message'] as String? ?? '';

    // 무엇이 비상정지를 걸었는가. app_emergency_node 가 같은 메시지에 실어
    // 보냅니다(2026-08-31). 이 값이 있어야 "관리자가 앱에서 누른 것"과
    // "물리 버튼·음성으로 걸린 것"을 가릴 수 있습니다 — 앞의 것은 누른 사람이
    // 관리자 본인이라 확인을 요청할 일이 아닙니다.
    //
    // 이 필드를 안 보내는 옛 노드와도 붙습니다. 그때는 빈 목록이 되고, 화면은
    // 원인을 모르는 것으로 보아 관리자 호출 문구를 붙이지 않습니다.
    final rawSources = message['sources'];
    _emergencyStopSources = rawSources is List
        ? rawSources.map((value) => value.toString()).toList()
        : const [];

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
    _teleopTimer?.cancel();
    _reconnectTimer?.cancel();
    _deliveryReturnTimer?.cancel();
    unawaited(_client?.close());
    super.dispose();
  }
}
