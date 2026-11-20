// 이 파일은 ROS2 연결, 지도/장소/로봇 상태, 알림 로그를 앱 전체 상태로 관리합니다.
import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/app_settings.dart';
import '../core/estop_sources.dart';
import '../core/contact_phone.dart';
import '../core/json_read.dart';
import '../core/log_filter.dart';
import '../core/mode_contract.dart';
import '../models/delivery_job.dart';
import '../models/goal_event.dart';
import '../models/home_position.dart';
import '../models/keepout_zone.dart';
import '../models/map_fix.dart';
import '../models/location_point.dart';
import '../models/robot_event.dart';
import '../models/robot_health.dart';
import '../models/map_preview.dart';
import '../models/pose_check_result.dart';
import '../models/dock_state.dart';
import '../models/mapping_status.dart';
import '../models/mode_status.dart';
import '../models/patrol.dart';
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
import '../services/patrol_log_loader.dart';
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
  /// 그 밖은 미리보기. 시험은 호스트(리눅스)에서 돌아 자동으로 미리보기가 됩니다.
  SupervisorProvider({
    DeliveryNotifier? deliveryNotifier,
    DeliveryJobStore? deliveryJobStore,
    RouteGraphLoader? routeGraphLoader,
    RouteServiceCall? routeServiceCall,
    WallMaskLoader? wallMaskLoader,
    RosChannelConnector? rosChannelConnector,
    bool? showOtherScreenDeliveryNotices,
    PatrolLogLoader? patrolLogLoader,
    DateTime Function()? now,
  })  : _now = now ?? DateTime.now,
        _deliveryNotifier = deliveryNotifier ?? createDeliveryNotifier(),
        _showOtherScreenDeliveryNotices =
            showOtherScreenDeliveryNotices ?? kIsWeb,
        _deliveryStore =
            deliveryJobStore ?? const SharedPreferencesDeliveryJobStore(),
        _routeGraphLoader = routeGraphLoader ?? const RouteGraphLoader(),
        _routeServiceCall = routeServiceCall,
        _wallMaskLoader = wallMaskLoader ?? MapWallMask.load,
        _patrolLogLoader = patrolLogLoader ?? const PatrolLogLoader(),
        _rosChannelConnector = rosChannelConnector;

  /// rosbridge 소켓을 여는 함수. null 이면 실제 WebSocket 을 엽니다. 시험은 가짜
  /// 채널을 끼워 끊김·재연결을 젯슨 없이 재현합니다.
  final RosChannelConnector? _rosChannelConnector;

  /// 시각. 시험은 가짜 시계를 끼웁니다([rosSilent]).
  final DateTime Function() _now;

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
    'busy_approaching': '사용자에게 다가가는 중이라 지금은 홈으로 부를 수 없습니다.',
    'no_wait_spot': '이 장소에는 대기 장소가 없습니다. 목록을 새로고침하세요.',
  };

  /// 대기 장소 가보기에서만 다르게 읽는 사유. 미션은 대기 장소로 가는 길을 '안내가
  /// 없을 때(IDLE)'만 받으므로 busy_navigating 은 주행 중뿐 아니라 사용자를 기다리는
  /// 중도 뜻합니다 — 일반 문구('이미 다른 목적지로 주행 중')는 틀린 말이 됩니다.
  static const _waitSpotGateMessages = <String, String>{
    'busy_navigating': '안내 중이거나 사용자를 기다리는 중이라 지금은 가볼 수 없습니다.',
  };

  final _uuid = const Uuid();
  // 지도 목록 응답을 처리할 때도 자동 요청 설정이 필요해 연결에 쓴 설정을 보관합니다.
  AppSettings? _lastSettings;
  RosBridgeClient? _client;
  // 일부러 닫는 중인 옛 연결. 그 연결이 내는 '연결 해제'는 지금처럼 화면에 반영하되
  // 재연결은 잡지 않습니다.
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
  // 다시 붙은 연결이 이만큼 버티면 재시도 횟수를 처음부터 센다. 붙자마자 끊는 서버에
  // 3초마다 끝없이 다시 붙지 않게 한다(그때는 종전처럼 상한에서 멈춘다).
  static const _reconnectStableAfter = Duration(seconds: 10);
  Timer? _reconnectStableTimer;
  EmergencyStopState _emergencyStopState = EmergencyStopState.inactive;
  String _emergencyStopMessage = '';
  List<String> _emergencyStopSources = const [];
  // 알림 및 로그 '비상정지' 에 이미 남긴 원인과, 걸림을 남겼는지(2026-11-17).
  // 재접속해도 지우지 않습니다 — 같은 비상정지를 두 번 남기지 않게.
  final Set<String> _loggedEstopSources = {};
  bool _loggedEstopActive = false;
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

  /// 소켓은 붙었는데 이만큼 받은 것이 없으면 '응답 없음'. 평소에는 /robot_status 만으로 초당 2개가 옵니다.
  static const rosSilentAfter = Duration(seconds: 5);

  /// 소켓은 붙어 있는데 [rosSilentAfter] 넘게 받은 것이 없음 — 화면은 '온라인' 대신 '응답 없음'.
  ///
  /// 부를 때마다 시각으로 계산합니다(타이머 없음). 1초마다 다시 보는 일은 화면 위젯
  /// [RosSilenceBuilder] 가 합니다 — 화면이 닫히면 그 타이머도 함께 정리됩니다.
  bool get rosSilent {
    final at = _client?.lastReceivedAt;
    if (_connectionState != RosConnectionState.connected || at == null) {
      return false;
    }
    return _now().difference(at) >= rosSilentAfter;
  }

  String get connectionDetail => _connectionDetail;
  EmergencyStopState get emergencyStopState => _emergencyStopState;
  String get emergencyStopMessage => _emergencyStopMessage;

  /// 이번 비상정지가 **현장에서** 걸려 관리자가 와야 하는가.
  ///
  /// 물리 버튼(`physical_f1`)·음성(`voice`)·몸통 넘어짐(`tipped`, 2026-10-15)이면
  /// 참입니다. 관리자가 앱에서 직접 누른 경우(`app`)는 부르는 사람과 받는
  /// 사람이 같으니 그 문구가 필요 없습니다.
  ///
  /// 통신 원인(`motor_can`·`*_stale`)만으로 걸린 래치도 참이 아닙니다. 그쪽은
  /// 정지 중이면 자동 복구를 밟는 별개 경로입니다(CLAUDE.md).
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
  ///
  /// 세운 뒤에는 원인 목록에서 빠지지만, 노드가 래치가 걸려 있는 동안 마지막
  /// 원인을 그대로 실어 보내므로 해제 전까지 참입니다. 앱은 '넘어져 있음'과
  /// '세운 뒤'를 가리지 않습니다 — 관리자가 할 일(세우고 해제)이 같습니다.
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
  /// "이미 고른 지도인가" 는 이 값으로 판정합니다([selectMap] 과 같은 기준).
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

  // rosbridge 연결을 하나만 유지하고 필요한 topic만 구독합니다.
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
      now: _now,
    );
    _client = client;
    await client.connect(settings.rosBridgeUrl);
    if (!identical(_client, client)) {
      // 연결을 기다리는 사이 connect 가 또 불려 새 연결로 바뀌었습니다. 이 연결은
      // 아무도 닫지 않으므로 여기서 닫습니다 — 남겨 두면 토픽을 두 번씩 받습니다.
      await client.close();
      return;
    }
    if (_connectionState == RosConnectionState.connected) {
      _subscribeRequiredTopics(settings);
      _requestSyncAfterConnect(settings);
    }
  }

  // 연결 하나가 낸 상태 소식을 받습니다.
  //
  // 이미 바뀐 옛 연결의 소식은 버립니다. 그 연결이 뒤늦게 '실패'를 내면 지금 연결이
  // 멀쩡한데 화면이 실패로 바뀌고, 새 연결에 옛 주소로 재연결을 거는 일이 생깁니다.
  // 일부러 닫는 연결의 '연결 해제'만은 지금처럼 화면에 반영합니다.
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
      // 다시 붙어 버티면 재시도 횟수를 처음부터 셉니다. 안 그러면 끊김이 몇 번 쌓인
      // 뒤로는 자동 재연결이 아무 말 없이 멈춥니다.
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

  // 연결을 일부러 닫습니다. 닫는 동안 그 연결이 내는 소식은 [_handleClientState] 가
  // 화면에만 반영합니다.
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
    _reconnectStableTimer?.cancel();
    _reconnectStableTimer = null;
    _reconnectAttempts = 0;
    final client = _client;
    _client = null;
    await _closeClient(client);
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
    // 경비 단계의 귀띔도 마찬가지입니다. 걸려 있던 경보는 지나간 사실이라 남깁니다.
    _patrolHint = null;
    _patrolHintAt = null;
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
    // 지도 수정의 잠금·부분 스캔 진행도 끊긴 뒤에는 현재 사실이 아닙니다.
    _mapFixStatus = null;
    _mapFixStatusMapId = '';
    _mapFixScan = null;
    // 노드 목록도 현재 사실이 아닙니다. 남겨 두면 모드 선택 화면이 "아무것도 안
    // 떠 있다"고 잘못된 안심을 줄 수 있습니다 — 그래서 '확인 불가'로 되돌립니다.
    _stackStatus = null;
    _stackStatusError = '';
    // 모드 상태도 현재 사실이 아닙니다. 남기면 끊긴 사이 꺼진 주행을 켜져 있다고 그립니다.
    _modeStatus = null;
    _modeStatusAt = null;
    // 다시 붙은 뒤 처음 받는 음성 알림은 끊긴 사이 일이라 기록만 합니다(띄우지 않음).
    _voiceFirstAfterConnect = true;
    // 전방 초음파 상태·거리도 다시 붙으면 드라이버가 남긴 값으로 채워집니다(2026-11-18).
    _frontUltrasonicOn = null;
    _frontRange.fillRange(0, 2, null);
    _frontRangeAt.fillRange(0, 2, null);
    // 빔포밍 회전도 다시 붙으면 음성 노드가 남긴 값으로 채워집니다(2026-11-19).
    _wakeDoaTurnOn = null;
    if (_robotsById.isEmpty) {
      return;
    }
    _robotsById.clear();
  }

  // 무한 재시도를 피하기 위해 설정된 횟수까지만 재연결합니다. 횟수는 연달아
  // 실패한 횟수입니다 — 다시 붙으면 [_handleClientState] 가 0 으로 되돌립니다.
  void _scheduleReconnect(AppSettings settings) {
    // 연결 실패 한 번이 '실패'와 '연결 해제' 두 소식으로 옵니다. 이미 잡아 둔
    // 재시도가 있으면 같은 실패이므로 다시 세지 않습니다.
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
      )
      // 요청 없이 생긴 레일 변화(주행이 끝나 미뤄 둔 적용이 된 경우·실패한 경우).
      ..subscribe(
        topic: settings.routeStateTopic,
        handler: _handleRouteState,
      )
      // 다른 기기(폰 APK·다른 브라우저)에서 레일을 저장해도 이 앱의 레일 그림이 바뀌게
      // 합니다(2026-10-08). 이 알림 전에는 연결·지도 고르기·새로고침 때만 다시 받아, 이미 열린
      // 웹 앱은 옛 레일을 계속 그렸습니다.
      ..subscribe(
        topic: settings.routeSavedTopic,
        handler: _handleRouteSaved,
      )
      // 관리자 유심 폰이 대신 보낸 도착 문자의 결과(2026-10-10). 배송을 보낸 화면만 씁니다.
      ..subscribe(
        topic: settings.deliverySmsResultTopic,
        handler: _handleDeliverySmsResult,
      )
      // 다른 화면이 배송을 보내며 남긴 받는 분께 메시지(2026-11-17). 대신 보낼 때 씁니다.
      ..subscribe(
        topic: settings.deliveryNoteTopic,
        handler: _handleDeliveryNote,
      )
      // 지도 수정의 부분 스캔 진행(2026-11-19). 스캔 세션이 있을 때만 옵니다.
      ..subscribe(
        topic: mapFixStateTopic,
        handler: _handleMapFixState,
      )
      // 모드 노드(부팅 자동 기동, 2026-11-16). 없으면 아무것도 안 와서 예전처럼 동작합니다.
      ..subscribe(
        topic: kModeStatusTopic,
        handler: _handleModeStatus,
      )
      // 전방 초음파 켜기·끄기(2026-11-18 사용자: 시스템 진단 맨 아래). 손잡이 드라이버가 낸다.
      ..subscribe(
        topic: frontUltrasonicStateTopic,
        type: 'std_msgs/Bool',
        handler: _handleFrontUltrasonicState,
      )
      // 빔포밍 회전(2026-11-19 사용자: 대시보드 주행 설정). 음성 호출 노드가 낸다.
      ..subscribe(
        topic: wakeDoaTurnStateTopic,
        type: 'std_msgs/Bool',
        handler: _handleWakeDoaTurnState,
      )
      ..subscribe(
        topic: frontUltrasonicTopics[0],
        type: 'sensor_msgs/Range',
        handler: (message) => _handleFrontRange(0, message),
      )
      ..subscribe(
        topic: frontUltrasonicTopics[1],
        type: 'sensor_msgs/Range',
        handler: (message) => _handleFrontRange(1, message),
      )
      // 도킹 노드(2026-11-18). 바뀔 때만 오고 마지막 값이 보관됩니다. 없으면 도킹 버튼이 안 뜹니다.
      ..subscribe(
        topic: kDockStateTopic,
        handler: _handleDockState,
      );
  }

  // ---- 전방 초음파 켜기·끄기 (2026-11-18 사용자) ------------------------------------

  /// 손잡이 드라이버(C++ 판)가 지금 상태를 남기는 토픽(std_msgs/Bool, TRANSIENT_LOCAL).
  static const frontUltrasonicStateTopic = '/vica/ultrasonic/front_enabled';

  /// 켜기·끄기 서비스(std_srvs/SetBool). 끄면 드라이버가 '없음'을 3번 보낸 뒤 멈춥니다.
  static const frontUltrasonicService = '/vica/ultrasonic/front_enable';
  static const frontUltrasonicTopics = [
    '/ultrasonic/front_left',
    '/ultrasonic/front_right',
  ];

  /// 이보다 오래 값이 안 오면 거리는 모름으로 둡니다(앞은 315 ms 마다 한 번).
  static const frontRangeStale = Duration(seconds: 2);

  bool? _frontUltrasonicOn;
  bool _frontUltrasonicBusy = false;
  final List<double?> _frontRange = [null, null];
  final List<DateTime?> _frontRangeAt = [null, null];

  /// 거리 값이 올 때마다 울립니다. 초당 6번까지 오므로 provider 전체(notifyListeners)를 울리지
  /// 않고 진단 카드만 이것을 듣습니다 — 다른 화면까지 다시 그리지 않게.
  final ValueNotifier<int> frontRangeTick = ValueNotifier<int>(0);

  /// null = 모름(손잡이 드라이버가 안 떠 있거나 아직 상태가 안 옴).
  bool? get frontUltrasonicOn => _frontUltrasonicOn;
  bool get frontUltrasonicBusy => _frontUltrasonicBusy;

  /// 왼쪽(0)·오른쪽(1) 최근 거리(m). '없음'(에코 없음)은 double.infinity, 모르면 null.
  double? frontRange(int side) {
    final at = _frontRangeAt[side];
    if (at == null || DateTime.now().difference(at) > frontRangeStale) {
      return null;
    }
    return _frontRange[side];
  }

  void _handleFrontUltrasonicState(Map<String, Object?> message) {
    final data = message['data'];
    if (data is bool && data != _frontUltrasonicOn) {
      _frontUltrasonicOn = data;
      notifyListeners();
    }
  }

  void _handleFrontRange(int side, Map<String, Object?> message) {
    if (_disposed) {
      return;
    }
    final range = (message['range'] as num?)?.toDouble();
    final maxRange = (message['max_range'] as num?)?.toDouble();
    if (range == null) {
      return;
    }
    final clear = maxRange != null && range >= maxRange - 1e-3;
    _frontRange[side] = clear ? double.infinity : range;
    _frontRangeAt[side] = DateTime.now();
    frontRangeTick.value++;
  }

  /// 전방 초음파를 켜거나 끕니다. 실패하면 까닭을, 되면 null 을 돌려줍니다.
  ///
  /// 끌 때는 드라이버가 '없음'을 3번(약 1 s) 보내 빔 안을 지운 뒤, 빔 밖에 남은 칸까지 지우려고
  /// local·global costmap 을 한 번 비웁니다. 그 사이 라이다·깊이 칸도 다음 갱신(≤0.2 s)까지
  /// 비므로 멈춰 있을 때 쓰는 것을 전제로 합니다(사용자 11-18). Nav2 가 없으면 비우기는 건너뜁니다.
  Future<String?> setFrontUltrasonic(bool on) async {
    final client = _client;
    if (client == null || _connectionState != RosConnectionState.connected) {
      return 'ROS Bridge에 연결되지 않았습니다.';
    }
    _frontUltrasonicBusy = true;
    notifyListeners();
    try {
      final response = await client.callService(
        service: frontUltrasonicService,
        type: 'std_srvs/srv/SetBool',
        args: {'data': on},
      );
      if (!response.success) {
        final message =
            response.message.isEmpty ? '전방 초음파를 바꾸지 못했습니다.' : response.message;
        _addLog(LogFilter.connection, message);
        return message;
      }
      if (!on) {
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        for (final service in const [
          '/local_costmap/clear_entirely_local_costmap',
          '/global_costmap/clear_entirely_global_costmap',
        ]) {
          try {
            await client.callService(
              service: service,
              type: 'nav2_msgs/srv/ClearEntireCostmap',
              timeout: const Duration(seconds: 3),
            );
          } catch (_) {
            // Nav2 가 꺼져 있으면 비울 costmap 도 없습니다.
          }
        }
      }
      return null;
    } catch (error) {
      final message = '전방 초음파를 바꾸지 못했습니다: $error';
      _addLog(LogFilter.connection, message);
      return message;
    } finally {
      _frontUltrasonicBusy = false;
      notifyListeners();
    }
  }

  // ---- 빔포밍 회전 켜기·끄기 (2026-11-19 사용자, 캔버스 101번 보드) ----------------------
  //
  // 켜면 대기 중 '비카야'가 온 방향으로 로봇이 돈다(음성 VICA_WAKE_DOA_TURN). 음성을 다시 띄우면
  // .env 값으로 돌아갑니다. 표시는 노드가 남긴 상태 토픽만 따릅니다 — 응답만 보고 미리 바꾸지 않습니다.

  /// 음성 호출 노드가 지금 상태를 남기는 토픽(std_msgs/Bool, TRANSIENT_LOCAL).
  static const wakeDoaTurnStateTopic = '/vica/wake_doa_turn/enabled';

  /// 켜기·끄기 서비스(std_srvs/SetBool). 응답 문구('빔포밍 회전을 켰습니다' 등)를 그대로 띄웁니다.
  static const wakeDoaTurnService = '/vica/wake_doa_turn/enable';

  bool? _wakeDoaTurnOn;

  /// null = 모름(음성이 안 떠 있거나 아직 상태가 안 옴).
  bool? get wakeDoaTurnOn => _wakeDoaTurnOn;

  void _handleWakeDoaTurnState(Map<String, Object?> message) {
    final data = message['data'];
    if (data is bool && data != _wakeDoaTurnOn) {
      _wakeDoaTurnOn = data;
      notifyListeners();
    }
  }

  /// 빔포밍 회전을 켜거나 끕니다. (받아들였는가, 보일 문구)
  Future<(bool, String)> setWakeDoaTurn(bool on) async {
    final client = _client;
    if (client == null || _connectionState != RosConnectionState.connected) {
      return (false, 'ROS Bridge에 연결되지 않았습니다.');
    }
    const fallback = '빔포밍 회전을 바꾸지 못했습니다.';
    try {
      final response = await client.callService(
        service: wakeDoaTurnService,
        type: 'std_srvs/srv/SetBool',
        args: {'data': on},
      );
      if (!response.success) {
        final message = response.message.isEmpty ? fallback : response.message;
        _addLog(LogFilter.connection, message);
        return (false, message);
      }
      if (response.message.isEmpty) {
        return (true, on ? '빔포밍 회전을 켰습니다' : '빔포밍 회전을 껐습니다');
      }
      return (true, response.message);
    } catch (error) {
      final message = '빔포밍 회전을 바꾸지 못했습니다: $error';
      _addLog(LogFilter.connection, message);
      return (false, message);
    }
  }

  /// 음성 노드 없이 화면 규칙만 검증하기 위한 주입 지점입니다.
  @visibleForTesting
  void setWakeDoaTurnForTest(bool? on) {
    _wakeDoaTurnOn = on;
    notifyListeners();
  }

  // ---- 모드 노드 (주행 묶음 켜기·끄기, 2026-11-16) ---------------------------------

  ModeStatus? _modeStatus;
  DateTime? _modeStatusAt;

  /// 모드 노드가 보낸 최근 상태. 8 s 넘게 안 왔으면 null — 모드 노드가 없거나 끊긴 것으로
  /// 보고 화면은 예전처럼(화면만 바꾸기) 동작합니다.
  ModeStatus? get modeStatus {
    final at = _modeStatusAt;
    if (_modeStatus == null || at == null) {
      return null;
    }
    return DateTime.now().difference(at) > kModeStatusStale
        ? null
        : _modeStatus;
  }

  void _handleModeStatus(Map<String, Object?> message) {
    final decoded = _decodeJsonString(message);
    if (decoded == null) {
      return;
    }
    _modeStatus = ModeStatus.fromJson(decoded);
    _modeStatusAt = DateTime.now();
    // 음성이 다시 뜨는 동안 이전 빔포밍 값을 들고 있지 않는다 — 새 노드가 낼 때까지 모름(11-19 사용자).
    if (_modeStatus!.voice != 'active') {
      _wakeDoaTurnOn = null;
    }
    _ingestVoiceEvents(_modeStatus!);
    _settleMapRequest(_modeStatus!);
    _followDriveMap(_modeStatus!);
    notifyListeners();
  }

  // 마지막으로 따라간 로봇 지도(Nav2 가 띄운 지도, 모르면 CURRENT_MAP).
  String _followedDriveMapId = '';

  /// 로봇이 쓰는 지도가 바뀌면 지도 고르기를 그 지도로 맞춥니다(2026-11-17 사용자).
  ///
  /// 원격 주행·물류 배송·지도 설정이 같은 고른 지도를 씁니다. 종전에는 앱을 켤 때만
  /// '(현재)' 지도를 골라, 주행 지도를 바꾸면 화면이 옛 지도에 머물렀습니다.
  /// - 바뀌는 순간에만 따라갑니다. 관리자가 일부러 고른 다른 지도는 그대로 둡니다.
  /// - 레일·금지구역 편집 중이거나 장소 초안이 있으면 따라가지 않습니다(편집이 날아감) —
  ///   그때는 지도 칸 아래 빨간 안내(CurrentMapNotice)가 다름을 알립니다.
  /// - 지도 목록에 아직 없거나 '(현재)' 표시가 다르면 목록을 다시 받습니다(앱 밖에서 바꾼 경우).
  void _followDriveMap(ModeStatus status) {
    final drive = status.driveMapId.trim();
    final settings = _lastSettings;
    if (drive.isEmpty || drive == _followedDriveMapId || settings == null) {
      return;
    }
    final listed = _maps.any((map) => map.mapId == drive);
    if (!listed || _currentMapId != drive) {
      requestMapList(settings);
    }
    if (_maps.isNotEmpty && !listed) {
      // 목록에 없는 지도는 고를 수 없습니다. 목록이 오면 다음 방송(2초)에서 다시 봅니다.
      return;
    }
    _followedDriveMapId = drive;
    if (_selectedMapId == drive) {
      return;
    }
    if (_keepoutEditing || _routeEditing || _draftLocation != null) {
      return;
    }
    selectMap(settings, drive);
  }

  @visibleForTesting
  void handleModeStatusForTest(Map<String, Object?> message) =>
      _handleModeStatus(message);

  // ---- 음성 연결 알림(사용자 11-16, 목업 D·E) ------------------------------------
  //
  // 모드 노드가 상태에 최근 알림 5건을 번호와 함께 싣습니다. 번호로 이미 본 것을 거르고,
  // 새것은 '알림 및 로그 › 연결 상태'에 남기고 화면 아래 알림 띠로 띄웁니다.
  // 연결 직후 처음 받은 상태의 알림은 끊긴 사이 일이라 기록만 하고 띄우지 않습니다 — 로봇과
  // 앱 기기의 시계가 달라도 틀리지 않게 시각이 아니라 '연결 뒤 첫 상태인가'로 가립니다.

  double _voiceEpochSeen = -1;
  int _voiceIdSeen = 0;
  bool _voiceFirstAfterConnect = true;
  final List<VoiceEvent> _voiceAlerts = [];
  int _voiceAlertSeq = 0;
  VoiceEvent? _lastVoiceEvent;

  /// 띄우지 않은 알림이 생길 때마다 늘어납니다. 화면은 이 값이 바뀌면 [takeVoiceAlerts] 로 꺼냅니다.
  int get voiceAlertSeq => _voiceAlertSeq;

  /// 가장 최근 음성 연결 알림(주행 노드 카드의 음성 줄).
  VoiceEvent? get lastVoiceEvent => _lastVoiceEvent;

  /// 띄울 알림을 꺼내고 비웁니다.
  List<VoiceEvent> takeVoiceAlerts() {
    final out = List<VoiceEvent>.of(_voiceAlerts);
    _voiceAlerts.clear();
    return out;
  }

  void _ingestVoiceEvents(ModeStatus status) {
    final firstAfterConnect = _voiceFirstAfterConnect;
    _voiceFirstAfterConnect = false;
    if (status.voiceEventsEpoch != _voiceEpochSeen) {
      // 모드 노드가 다시 떴다. 번호가 1 부터 다시 시작한다.
      _voiceEpochSeen = status.voiceEventsEpoch;
      _voiceIdSeen = 0;
    }
    for (final event in status.voiceEvents) {
      if (event.id <= _voiceIdSeen) {
        continue;
      }
      _voiceIdSeen = event.id;
      _lastVoiceEvent = event;
      _addLog(LogFilter.connection, '음성: ${event.text} (${_clock(event.at)})');
      if (!firstAfterConnect) {
        _voiceAlerts.add(event);
        _voiceAlertSeq += 1;
      }
    }
  }

  static String _clock(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}:'
      '${at.second.toString().padLeft(2, '0')}';

  /// 주행 묶음 켜기. (받아들였는가, 사람에게 보일 문구)
  Future<(bool, String)> driveStart() =>
      _callModeService(kDriveStartService, '주행 켜기');

  /// 주행 묶음 끄기. Nav2 가 뜨는 중이면 모드 노드가 다 뜬 뒤로 예약합니다.
  Future<(bool, String)> driveStop() =>
      _callModeService(kDriveStopService, '주행 끄기');

  /// 로봇 끄기(주행·기본 묶음 → sync → 시스템 종료). 받아들여지면 곧 연결이 끊깁니다.
  Future<(bool, String)> robotShutdown() =>
      _callModeService(kShutdownService, '로봇 끄기');

  /// Nav2 만 다시 띄우기.
  Future<(bool, String)> nav2Restart() =>
      _callModeService(kNav2RestartService, 'Nav2 다시 시작');

  /// ⑮ 감지기만 켜고 끄기(잠시 끄기). 주행을 다시 켜면 켜진 상태로 돌아갑니다.
  Future<(bool, String)> setDetector(bool on) => on
      ? _callModeService(kDetectorOnService, '사람 감지 켜기')
      : _callModeService(kDetectorOffService, '사람 감지 끄기');

  /// 음성 노드만 켜고 끄기(2026-11-20 사용자, 캔버스 104). 움직이는 중·주행 모드가 아니면 모드 노드가 거절합니다.
  Future<(bool, String)> setVoiceNode(bool on) => on
      ? _callModeService(kVoiceNodeOnService, '음성 노드 켜기')
      : _callModeService(kVoiceNodeOffService, '음성 노드 끄기');

  /// 음성을 로컬 / 외부 API 로. 음성이 떠 있으면 젯슨이 다시 띄웁니다(말이 끊김).
  Future<(bool, String)> setVoice(VoiceChoice choice) => switch (choice) {
        VoiceChoice.local => _callModeService(kVoiceLocalService, '음성 로컬'),
        VoiceChoice.api => _callModeService(kVoiceApiService, '음성 외부 API'),
      };

  // ---- 주행 지도 바꾸기(사용자 11-17) -------------------------------------------
  //
  // Trigger 는 인자가 없어 토픽으로 보냅니다. 모드 노드는 받자마자 상태를 다시 내며, 그 안의
  // map_change 가 같은 request_id 면 결과입니다. 젯슨은 maps/CURRENT_MAP 을 쓰고, 주행이 떠
  // 있으면 Nav2·미션·음성·위치 확인을 다시 띄웁니다(약 1분) — 진행은 모드 상태로 봅니다.

  String? _mapRequestId;
  Completer<(bool, String)>? _mapRequestDone;

  /// 주행 지도를 [mapId] 로 바꾸기. (받아들였는가, 사람에게 보일 문구)
  Future<(bool, String)> requestMapChange(String mapId) async {
    final client = _client;
    if (client == null || _connectionState != RosConnectionState.connected) {
      return (false, 'ROS Bridge에 연결되지 않았습니다.');
    }
    final id = _uuid.v4();
    final done = Completer<(bool, String)>();
    _mapRequestId = id;
    _mapRequestDone = done;
    client.advertise(topic: kModeMapRequestTopic, type: 'std_msgs/String');
    void send() => client.publishJsonString(
          topic: kModeMapRequestTopic,
          payload: {'request_id': id, 'map_id': mapId},
        );
    // 토픽 한 번은 DDS 연결이 맺어지기 전이면 사라집니다(11-17 실기). 결과가 올 때까지 같은 ID 로
    // 다시 보냅니다 — 모드 노드는 처리한 ID 를 다시 처리하지 않고 결과만 다시 냅니다.
    send();
    final retry = Timer.periodic(kModeMapRequestRetry, (_) {
      if (!done.isCompleted) {
        send();
      }
    });
    try {
      return await done.future.timeout(kModeMapRequestTimeout);
    } on TimeoutException {
      return (false, '로봇이 답하지 않음 · 모드 노드 확인');
    } finally {
      retry.cancel();
      if (_mapRequestId == id) {
        _mapRequestId = null;
        _mapRequestDone = null;
      }
    }
  }

  void _settleMapRequest(ModeStatus status) {
    final change = status.mapChange;
    final done = _mapRequestDone;
    if (change == null ||
        done == null ||
        done.isCompleted ||
        change.requestId != _mapRequestId) {
      return;
    }
    done.complete((change.applied, change.message));
    if (!change.applied) {
      _addLog(LogFilter.coordinateTransfer,
          '주행 지도 ${change.from} → ${change.mapId}: ${change.message}');
    }
    // '(현재)' 표시와 지도별 준비 상태를 새로 받습니다.
    final settings = _lastSettings;
    if (change.applied && settings != null) {
      requestMapList(settings);
    }
  }

  // std_srvs/Trigger 는 accepted 가 아니라 success 로 답합니다. 그래서 _callService 를
  // 쓰지 않습니다(그 도우미는 accepted 만 봅니다).
  Future<(bool, String)> _callModeService(String service, String what) async {
    final client = _client;
    if (client == null || _connectionState != RosConnectionState.connected) {
      return (false, 'ROS Bridge에 연결되지 않았습니다.');
    }
    try {
      final response = await client.callService(service: service);
      final message =
          response.message.isEmpty ? '$what 요청을 보냈습니다.' : response.message;
      // 모드 노드 요청(주행·음성·감지)은 지도 설정이 아니다 — 실패만 '연결 상태'에(2026-11-17).
      if (!response.success) {
        _addLog(LogFilter.connection, '$what: $message');
      }
      return (response.success, message);
    } catch (error) {
      final message = '$what 실패: $error';
      _addLog(LogFilter.connection, message);
      return (false, message);
    }
  }

  /// 모드 노드 없이 화면 규칙만 검증하기 위한 주입 지점입니다.
  @visibleForTesting
  void setModeStatusForTest(ModeStatus? status) {
    _modeStatus = status;
    _modeStatusAt = status == null ? null : DateTime.now();
    notifyListeners();
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
    try {
      final response = await client.callService(
        service: settings.emergencyResetService,
        timeout: Duration(seconds: settings.emergencyServiceTimeoutSeconds),
      );
      if (response.result && response.success) {
        _setEmergencyStopState(EmergencyStopState.inactive, '');
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
  ///   - 화면의 '새로고침'(옛 '동기화') 버튼이 이름과 달리 장소만 갱신했다.
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
    unawaited(refreshDockSpot(settings, mapId));
    unawaited(requestKeepoutList(settings, mapId));
    unawaited(loadRouteGraph(settings, mapId));
    // 지난번에 지도 그림(벽 지도)을 못 받았으면 다시 받게 합니다. 실패 기록이 남아
    // 있으면 대기 장소의 벽 간격 검사가 앱을 다시 켤 때까지 꺼져 있습니다.
    if (!auto) {
      _wallMaskFailed.remove(mapId);
    }
  }

  // ---- 레일 (route graph) 표시 ----------------------------------------------
  //
  // 로봇이 따라 달리는 레일을 지도 위에 겹쳐 보입니다(A단계, 2026-09-30).
  // 지도 그림과 같은 HTTP 서버에서 <지도>_route.geojson 을 받습니다. 파일이
  // 없는 지도는 레일이 없는 것이니 아무것도 그리지 않고 알리지도 않습니다.
  // 편집·저장은 다음 단계이고, 여기서는 읽기만 합니다.

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

  /// 대기 장소로 가보기(2026-10-07, 지도 설정). [location] 은 대기 장소가 딸린
  /// 목적지입니다 — 미션이 그 목적지의 wait_spot 을 찾아 레일 없는 짧은 트리로
  /// 보냅니다. 안내 중·대기 장소 없음은 미션이 거절하고 그 사유를 돌려줍니다.
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
  /// 불러오기를 시작하고 null 을 돌려줍니다 — 다 받으면 화면이 다시 그려집니다.
  /// 받기에 실패한 지도는 다시 받지 않습니다([wallMaskFailed]). 화면이 그릴 때마다
  /// 부르므로, 실패를 기억하지 않으면 그릴 때마다 지도 그림을 또 받습니다.
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
  ///
  /// 수락 여부를 함께 돌려줍니다 — 배송은 수락됐을 때만 "배송 중"을 기억해야
  /// 하는데, 문구만 받아서는 수락인지 거부인지 가릴 수 없습니다.
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
      logAs: null, // 주행 요청 거부·실패는 팝업으로만(2026-11-17)
    );
    return (reply.accepted, reply.message);
  }

  // 진행 중인 주행 제어. 요청만 보내고 허용 여부는 Mission Manager가 판정합니다.
  // 세 요청 모두 vica_interfaces/srv/MissionCommand 형태를 씁니다.
  Future<String> cancelDestination(AppSettings settings) {
    return _sendMissionCommand(settings.missionCancelService, '주행을 취소했습니다.');
  }

  /// 대기·접근 중 취소(2026-10-29, 목업 44·45). 미션에는 같은 취소(on_app_cancel)이고 알림 글자만 다릅니다.
  /// 접근 취소면 미션이 그 사람을 60 s 다시 다가가지 않게 막습니다.
  Future<String> cancelWait(AppSettings settings) {
    return _sendMissionCommand(settings.missionCancelService, '대기를 취소했습니다.');
  }

  Future<String> cancelApproach(AppSettings settings) {
    return _sendMissionCommand(settings.missionCancelService, '접근을 취소했습니다.');
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
  /// 있어 그대로이고, 노드가 목록을 다시 보내면 드롭다운이 새 이름을 보입니다.
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
  ///
  /// "지도 한 장은 사람이 로봇을 끌고 다닌 시간"이라(vica_map_save.sh 주석) 실제
  /// 검사는 노드가 합니다 — 이름 규칙, 지금 쓰는 지도인지, 파일이 있는지.
  /// 앱은 확인을 받고 결과를 보여줄 뿐입니다.
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
          // 지운 지도를 계속 고른 채로 두면 없는 지도의 장소를 보여주게 됩니다.
          _selectedMapId = null;
          _selectedLocationId = null;
        }
      },
    );
    return reply.message;
  }

  // ---- 도킹 (2026-11-18, 목업 62~74) ----------------------------------------
  //
  // 홈과 도크는 따로입니다(11-18 사용자). 도크 위치 저장·조회·지우기는 도킹 노드에 직접,
  // 도킹 시작·나오기·중지는 미션을 거칩니다(주행은 미션이 단일 권한자).

  DockNodeState? _dockState;

  /// 도킹 노드가 돌려준 도크. **노드의 지도(주행 지도) 것**이라 조회를 요청한 지도 것이 아닐 수 있습니다.
  DockSpot? _dockSpot;

  /// 조회를 요청한(그때 보고 있던) 지도
  String _dockSpotMapId = '';

  /// 마지막 조회 응답의 map_id — 도킹 노드의 지도. 도크가 없으면 응답에 없어 빈 문자열입니다.
  String _dockNodeMapId = '';
  bool _dockBusy = false;

  DockNodeState? get dockState => _dockState;
  bool get dockBusy => _dockBusy;

  /// [mapId] 지도에 저장된 도크 위치. 없거나 다른 지도면 null.
  ///
  /// 도킹 노드는 조회에 지도 id 를 받지 않고 자기 지도(주행 지도)의 도크만 돌려줍니다. 응답의 map_id 가
  /// [mapId] 와 다르면 이 지도에는 도크가 없는 것입니다 — 다른 지도의 좌표를 이 지도에 그리지 않습니다
  /// (2026-11-19 검토).
  DockSpot? dockSpotFor(String? mapId) {
    if (mapId == null || _dockSpotMapId != mapId) {
      return null;
    }
    final spot = _dockSpot;
    if (spot != null && spot.mapId.isNotEmpty && spot.mapId != mapId) {
      return null;
    }
    return spot;
  }

  /// [mapId] 지도를 보고 있지만 도킹 노드는 다른 지도(주행 지도)에 붙어 있는가.
  ///
  /// 인식 저장·지도에서 지정·지우기·도킹해 보기가 전부 주행 지도에 가므로, 이때는 도크 위치 칸의
  /// 버튼을 잠급니다. 안내는 같은 상황에서 뜨는 주행 지도 띠(DriveMapBanner)가 합니다.
  /// 조회 응답의 map_id 로 보고, 모드 노드가 알려 준 주행 지도로도 봅니다 — 도크가 아직 없으면
  /// 응답에 map_id 가 없습니다.
  bool dockOnOtherMap(String? mapId) {
    if (mapId == null || mapId.isEmpty) {
      return false;
    }
    final status = modeStatus;
    if (status != null &&
        status.driveOn &&
        status.driveMapId.isNotEmpty &&
        status.driveMapId != mapId) {
      return true;
    }
    return _dockSpotMapId == mapId &&
        _dockNodeMapId.isNotEmpty &&
        _dockNodeMapId != mapId;
  }

  /// 지도에 그릴 도크 점(도킹했을 때 로봇 자리).
  Offset? dockPointFor(String? mapId) {
    final spot = dockSpotFor(mapId);
    return spot == null ? null : Offset(spot.dockedX, spot.dockedY);
  }

  /// 로봇이 도크에 들어가 있는가 — 미션 dialog_state 가 정본, 없으면 도킹 노드 값.
  bool get isDocked {
    final dialog = primaryRobot?.dialogState.trim() ?? '';
    if (dialog.isNotEmpty) {
      return dialog == kDialogDocked;
    }
    return _dockState?.docked ?? false;
  }

  /// 도크 안은 아니지만 '도크에서 나오기'를 이어서 할 수 있는가(2026-11-19) — 나오다 멈췄거나
  /// 도크 가까이(85 cm 안)에 서 있을 때. 미션이 다른 일(주행·도킹 중 등)을 하고 있으면 화면이 따로 막습니다.
  bool get canResumeUndock => !isDocked && (_dockState?.canResumeUndock ?? false);

  /// 나오다 멈춘 상태인가(2026-11-19) — '도킹 시작'을 숨기고 '도크에서 나오기 다시시작'만 보입니다.
  bool get undockPaused => !isDocked && (_dockState?.undockPaused ?? false);

  void _handleDockState(Map<String, Object?> message) {
    final st = DockNodeState.fromMessage(message);
    if (st == null) {
      return;
    }
    final prev = _dockState;
    _dockState = st;
    // 도킹이 끝나면 도크 위치가 바뀌어 있을 수 있습니다(2026-11-19) — 다시 읽습니다.
    //   성공  '가 본 자리'가 되고, 처음 성공이면 로봇이 라이다로 잰 값으로 고쳐 저장합니다.
    //   실패  도크가 범위 밖(out_of_range)이면 로봇이 도크 위치를 고쳐 저장합니다.
    // 직전 결과가 '나오기 성공'이어도 읽어야 합니다(종전에는 직전 결과가 성공이 아닐 때만 읽어, 도크에서
    // 나온 뒤 다시 지정한 자리의 첫 도킹을 놓쳤습니다). 같은 사유로 연달아 실패하면 last 는 그대로라
    // '도킹 중'이 끝난 것으로도 봅니다.
    final dockEnded = st.lastAction == 'dock' &&
        (st.lastResult == 'success' || st.lastResult == 'failed');
    final isNew = prev != null &&
        (prev.lastAction != st.lastAction ||
            prev.lastResult != st.lastResult ||
            prev.lastReason != st.lastReason ||
            (prev.state == 'docking' && st.state != 'docking'));
    if (dockEnded && isNew && _dockSpotMapId.isNotEmpty) {
      final settings = _lastSettings;
      if (settings != null) {
        unawaited(refreshDockSpot(settings, _dockSpotMapId));
      }
    }
    notifyListeners();
  }

  Future<(bool, String)> _callTrigger(String service, {Duration? timeout}) async {
    final client = _client;
    if (client == null || _connectionState != RosConnectionState.connected) {
      return (false, 'not_connected');
    }
    try {
      final r = await client.callService(
        service: service,
        type: 'std_srvs/srv/Trigger',
        timeout: timeout ?? RosBridgeClient.defaultServiceTimeout,
      );
      return (r.success, r.message);
    } on TimeoutException catch (error) {
      // 서비스는 있는데 답이 늦은 것입니다 — '주행이 꺼져 있습니다'(call_failed)와 가릅니다(2026-11-19).
      _addLog(LogFilter.coordinateTransfer, '$service 호출 실패: $error');
      return (false, 'timeout');
    } catch (error) {
      // rosbridge 는 서비스가 없으면(주행 꺼짐) result:false 로 답하고, 그것이 여기로 옵니다.
      // 호출 도중 웹소켓이 끊긴 것도 여기로 옵니다 — 그것은 주행 꺼짐이 아니라 연결 없음입니다.
      _addLog(LogFilter.coordinateTransfer, '$service 호출 실패: $error');
      return (false, _dockCallFailure);
    }
  }

  /// 도크 서비스 호출이 실패한 지금의 사유 — 연결이 살아 있으면 서비스 없음(call_failed),
  /// 끊겼으면 not_connected.
  String get _dockCallFailure =>
      _connectionState == RosConnectionState.connected ? 'call_failed' : 'not_connected';

  /// 젯슨에서 도크 위치를 읽습니다. 없으면 null 이며 오류가 아닙니다.
  Future<void> refreshDockSpot(AppSettings settings, String mapId) async {
    final (ok, message) = await _callTrigger(kDockGetService);
    if (message == 'not_connected' || message == 'call_failed' || message == 'timeout') {
      return;   // 조회 실패와 '없음'은 다르다 — 이전 값을 둔다(홈과 같은 규칙)
    }
    _dockSpotMapId = mapId;
    _dockSpot = ok ? DockSpot.fromTriggerMessage(message) : null;
    // 요청한 지도와 다르면 그 지도의 도크가 아닙니다([dockSpotFor]·[dockOnOtherMap] 이 가립니다).
    _dockNodeMapId = DockSpot.mapIdOfTriggerMessage(message);
    notifyListeners();
  }

  /// '도크 인식해서 저장'(목업 84·85). 로봇이 도크를 보고만 있으면 됩니다 — 라이다로 도크를 찾아
  /// 도크 앞 1 m 지점을 준비 위치로 잡습니다. 실패 사유는 [DockRegisterResult.reason] 입니다.
  Future<DockRegisterResult> registerDock(AppSettings settings, String mapId) async {
    _dockBusy = true;
    notifyListeners();
    try {
      final (ok, message) = await _callTrigger(
        kDockRegisterService, timeout: const Duration(seconds: 8));
      final result = DockRegisterResult.fromTrigger(ok, message);
      if (result.ok) {
        _addLog(LogFilter.coordinateTransfer, '도크 위치 저장: ${result.savedText}');
        await refreshDockSpot(settings, mapId);
      }
      return result;
    } finally {
      _dockBusy = false;
      notifyListeners();
    }
  }

  /// 지도에서 지정한 도크를 저장합니다(/vica/dock/set, 2026-11-19 목업 89~91).
  ///
  /// [x]·[y] 는 지도에서 누른 도크, [yawDeg] 는 로봇이 도크를 바라보는 방향(도)입니다. 준비 위치
  /// (도크 앞 1 m)는 로봇이 계산합니다. 타입은 홈 저장과 같은 SaveHome 이고 응답 message 는
  /// 조회(/vica/dock/get)와 같은 JSON, 거절이면 사유 문자열(busy · map_mismatch · write_failed)입니다.
  /// 실패 사유에는 call_failed(서비스 없음 = 주행 꺼짐) · not_connected · timeout 도 있습니다.
  Future<({bool ok, String reason})> setDockFromMap(
    AppSettings settings, {
    required String mapId,
    required double x,
    required double y,
    required double yawDeg,
  }) async {
    final client = _client;
    if (client == null || _connectionState != RosConnectionState.connected) {
      return (ok: false, reason: 'not_connected');
    }
    _dockBusy = true;
    notifyListeners();
    try {
      final response = await client.callService(
        service: kDockSetService,
        type: 'vica_interfaces/srv/SaveHome',
        args: {
          'map_id': mapId,
          'x': x,
          'y': y,
          'yaw': yawDeg,
          'source': kDockSourceMapPick,
          'score': 0.0,
          'label': '',
        },
      );
      if (!response.accepted) {
        final reason = response.message.isEmpty ? 'rejected' : response.message;
        _addLog(LogFilter.coordinateTransfer, '도크 위치 저장(지도에서 지정) 거절: $reason');
        return (ok: false, reason: reason);
      }
      await refreshDockSpot(settings, mapId);
      return (ok: true, reason: '');
    } on TimeoutException catch (error) {
      _addLog(LogFilter.coordinateTransfer, '$kDockSetService 호출 실패: $error');
      return (ok: false, reason: 'timeout');
    } catch (error) {
      _addLog(LogFilter.coordinateTransfer, '$kDockSetService 호출 실패: $error');
      return (ok: false, reason: _dockCallFailure);
    } finally {
      _dockBusy = false;
      notifyListeners();
    }
  }

  Future<String> deleteDock(AppSettings settings, String mapId) async {
    final (ok, message) = await _callTrigger(kDockDeleteService);
    await refreshDockSpot(settings, mapId);
    return ok ? '도크 위치를 지웠습니다.' : '도크 위치를 지우지 못했습니다($message).';
  }

  Future<String> startDocking(AppSettings settings) =>
      _sendMissionCommand(kMissionDockStartService, '도킹을 시작합니다.');

  Future<String> undock(AppSettings settings) =>
      _sendMissionCommand(kMissionDockUndockService, '도크에서 나옵니다.');

  Future<String> cancelDocking(AppSettings settings) =>
      _sendMissionCommand(kMissionDockCancelService, '멈췄습니다.');

  @visibleForTesting
  void setDockSpotForTest(String mapId, DockSpot? spot) {
    _dockSpotMapId = mapId;
    _dockSpot = spot;
    _dockNodeMapId = spot?.mapId ?? '';
    notifyListeners();
  }

  @visibleForTesting
  void setHomeForTest(String mapId, HomePosition? home) {
    _homeMapId = mapId;
    _home = home;
    notifyListeners();
  }

  @visibleForTesting
  void handleDockStateForTest(Map<String, Object?> message) => _handleDockState(message);

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
      // 문구가 비었을 때의 기본 문구가 '삭제'로 되어 있습니다(deleteHome 에서 옮겨 온 듯).
      // 로봇은 늘 "홈을 저장했습니다. …"를 실어 보내 화면에 거의 안 나옵니다. 저장용
      // 앱 문구가 따로 없어 바꾸지 않았습니다 — 사용자 결정 대기(검토 35bc1d0 D3).
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

  // 홈 저장·삭제를 기다리는 동안 홈 칸 버튼을 잠급니다.
  void _setHomeBusy(bool busy) {
    _homeBusy = busy;
    notifyListeners();
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
    final reply = await _callService(
      service: settings.missionReturnHomeService,
      type: 'vica_interfaces/srv/MissionCommand',
      args: {'request_id': _uuid.v4()},
      describe: (response) => response.message.isEmpty
          ? (response.accepted ? '홈으로 복귀합니다.' : '홈 복귀 요청이 거부되었습니다.')
          : _localizeGateReason(response.message),
      failurePrefix: '홈 복귀 요청 실패',
      logAs: null, // 주행 요청 거부·실패는 팝업으로만(2026-11-17)
    );
    return (reply.accepted, reply.message);
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

  /// 다른 화면(웹 등)이 보낸 배송의 도착 문자를 이 폰이 대신 보낸 도착들(2026-10-10).
  /// 같은 도착 이벤트가 두 번 와도 한 번만 보냅니다. 열쇠는 [_arrivalKey].
  final Set<String> _relaySentKeys = {};

  /// 다른 화면이 보낸 배송의 도착 문자 결과도 이 화면에 팝업으로 띄우는가(2026-10-23 사용자 결정:
  /// 폰 앱이 보낸 배송의 문자 결과를 웹에도). 기본은 웹만입니다. 시험은 생성자로 켭니다.
  final bool _showOtherScreenDeliveryNotices;

  /// 다른 화면의 배송이라 이 화면에 띄운 도착 문자 팝업들. 같은 결과가 두 번 와도 한 번만.
  final Set<String> _otherScreenNoticeKeys = {};

  /// 이 화면의 배송이 도착해 결과를 기다린 도착들. 기다림이 끝난 뒤 늦게 온 결과도 다른 화면 팝업으로
  /// 띄우지 않습니다.
  final Set<String> _ownSmsKeys = {};

  /// 관리자 유심 폰이 알려 온 도착 문자 결과와, 그것을 기다리는 이 화면의 배송.
  /// 결과가 기다림보다 먼저 와도 잃지 않게 잠시 둡니다.
  final Map<String, DeliveryNotifyResult> _relayedSmsResults = {};
  final Map<String, Completer<DeliveryNotifyResult>> _relayedSmsWaiters = {};

  /// 정리됐는가. 도착 문자 결과는 비동기로 늦게 와서(최대 30초) 화면이 닫힌 뒤일 수 있다.
  bool _disposed = false;

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
          returnNote:
              '앱이 꺼진 사이 홈 복귀가 끝났거나 멈췄습니다. 로봇 위치 확인 후 복귀를 삭제하거나 다시 보내세요.',
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
  /// [note] 는 받는 분께 남길 메시지입니다(2026-11-17). 도착 문자에 실려 45자 안으로 나갑니다.
  /// [phone] 을 주면 이번 배송만 그 번호로 보냅니다(2026-11-17 B안: 번호 없는 장소도 배송). 장소에
  /// 저장된 번호는 바꾸지 않습니다.
  Future<String> startDelivery(
    AppSettings settings,
    LocationPoint location, {
    String note = '',
    String phone = '',
  }) async {
    final typed = phone.trim().isEmpty ? '' : normalizeContactPhone(phone);
    if (typed == null) {
      return '연락처가 휴대폰 번호 모양이 아닙니다.';
    }
    if (typed.isNotEmpty && typed != location.contactPhone) {
      location = location.copyWith(contactPhone: typed);
    }
    if (!location.canReceiveDelivery) {
      return '${location.name}에 연락처가 없습니다. 연락처를 쓰세요.';
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
    final cleanNote = deliveryNoteClean(note);
    _setDelivery(DeliveryJob(
      destination: location,
      startedAt: DateTime.now(),
      note: cleanNote,
    ));
    // 비어 있어도 냅니다 — 대신 보내는 폰이 같은 장소의 지난 메시지를 다시 쓰지 않게. 번호는 바꿨을
    // 때만 싣습니다(저장된 번호는 유심 폰이 제 장소 목록에서 압니다).
    _publishDeliveryNote(settings, location, cleanNote,
        phone: typed.isNotEmpty ? location.contactPhone : '');
    _pendingDeliveryNotice = null;
    _addLog(LogFilter.delivery,
        '${location.name} 배송 출발${cleanNote.isEmpty ? '' : ' · 메시지 ${cleanNote.length}자'}');
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
      _addLog(
          LogFilter.delivery, '${job.destination.name} 배송 홈 복귀 거부: $message');
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
  /// 오면 결과가 돌아오기 전에 두 번째 발송이 나갈 수 있습니다. [sendText] 가
  /// false 면 이미 보낸 것으로 보고 복귀 시계만 겁니다('확인 필요' 처리).
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
    final text = deliveryArrivalMessage(job.destination.name, note: job.note);
    final key = arrival == null ? null : _arrivalKey(arrival);
    DeliveryNotifyResult result;
    try {
      if (await _deliveryNotifier.needsRelay()) {
        // 이 화면은 문자를 보낼 수단이 없습니다(웹·유심 없는 폰). 로봇이 배송 도착을 표시하므로
        // 관리자 유심 폰이 보내고 결과를 알려 옵니다 — 그 결과로 지금과 같은 팝업을
        // 띄웁니다(2026-10-10 사용자 결정). 화면에 '부탁' 같은 중간 표시는 없습니다.
        result = await _awaitRelayedSmsResult(key);
      } else {
        result = await _deliveryNotifier.send(
          phone: job.destination.contactPhone,
          text: text,
        );
        // 직접 보낸 결과도 알립니다. 같은 도착을 다른 화면이 제 배송으로 기다리고 있을 수
        // 있습니다(검토 2: 끝난 이벤트를 놓쳐 옛 배송을 아직 들고 있던 경우).
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
    // 로그에는 장소 이름과 결과만 남깁니다. 번호는 개인정보입니다.
    _addLog(
      LogFilter.delivery,
      '${job.destination.name} 도착 문자 ${result.sent ? '발송됨' : '미발송'}: ${result.detail}',
    );
    _pendingDeliveryNotice =
        DeliveryNotice(job: job, text: text, result: result);
    // 출발 때 낸 메시지·번호 래치를 지웁니다(대신 보낸 폰은 이미 썼고, 남기면 번호가 계속 보입니다).
    _clearDeliveryNote(job.destination.mapId, job.destination.locationId);
    notifyListeners();
  }

  /// 화면끼리 같은 도착을 맞추는 열쇠 — 장소 id 와 로봇이 적은 시각. 둘 중 하나라도
  /// 없으면 맞출 수 없어 null 입니다(옛 미션·수동 도착 처리).
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
  /// 안 간 것으로 봅니다 — 안 간 문자를 갔다고 믿는 것이 가장 나쁩니다.
  Future<DeliveryNotifyResult> _awaitRelayedSmsResult(String? key) {
    const noReply = DeliveryNotifyResult(
      sent: false,
      detail: deliverySmsNoReplyDetail,
    );
    if (key == null) {
      return Future.value(noReply);
    }
    _ownSmsKeys.add(key);
    while (_ownSmsKeys.length > 50) {
      _ownSmsKeys.remove(_ownSmsKeys.first);
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

  /// 관리자 유심 폰이 알린 결과. 기다리는 배송이 있으면 넘기고, 이 화면의 배송이면 잠시 둡니다.
  /// 다른 화면이 보낸 배송이면 웹은 팝업으로 띄웁니다(2026-10-23).
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
    // 이 화면이 그 장소로 보낸 배송이 아직 가는 중이면 그 배송의 흐름이 팝업을 띄웁니다 — 결과가 이 화면의
    // 도착 처리보다 먼저 온 경우라 아래처럼 잠시 둡니다. 이 화면이 기다렸던 결과가 늦게 온 것도 이 화면
    // 몫입니다. 그 밖은 다른 화면(폰 앱)이 보낸 배송입니다. 끝난 배송 기록(완료·중단)은 지워지지 않고
    // 남으므로 장소만 보면 폰 앱이 같은 장소로 보낸 배송의 팝업을 막았습니다(10-29 검토).
    final job = _delivery;
    final mine = _ownSmsKeys.contains(key) ||
        (job != null &&
            job.isActive &&
            job.destination.locationId == locationId);
    if (_showOtherScreenDeliveryNotices && !mine) {
      _showOtherScreenDeliveryNotice(
        mapId: (message['map_id'] as String?)?.trim() ?? '',
        locationId: locationId,
        key: key,
        result: result,
      );
      return;
    }
    _relayedSmsResults[key] = result;
    while (_relayedSmsResults.length > 20) {
      _relayedSmsResults.remove(_relayedSmsResults.keys.first);
    }
  }

  /// 다른 화면(폰 앱)이 보낸 배송의 도착 문자 결과를 이 화면에도 같은 팝업으로 띄웁니다(2026-10-23).
  /// 받는 곳·번호는 이 화면의 장소 목록에서 찾습니다. 못 찾으면(다른 지도를 보는 중) 받는 곳 없이
  /// 띄우면 잘못 읽을 수 있어 기록만 남깁니다.
  void _showOtherScreenDeliveryNotice({
    required String mapId,
    required String locationId,
    required String key,
    required DeliveryNotifyResult result,
  }) {
    if (!_otherScreenNoticeKeys.add(key)) {
      return;
    }
    while (_otherScreenNoticeKeys.length > 50) {
      _otherScreenNoticeKeys.remove(_otherScreenNoticeKeys.first);
    }
    LocationPoint? location;
    for (final candidate in locationsFor(mapId)) {
      if (candidate.locationId == locationId) {
        location = candidate;
        break;
      }
    }
    final state = result.sent ? '발송됨' : '미발송';
    if (location == null) {
      _addLog(LogFilter.delivery,
          '다른 화면에서 보낸 배송의 도착 문자 $state — 장소를 이 화면 목록에서 못 찾아 팝업 없음');
      notifyListeners();
      return;
    }
    _addLog(LogFilter.delivery,
        '${location.name} 도착 문자 $state(다른 화면에서 보낸 배송): ${result.detail}');
    final (note, typedPhone) =
        _peekDeliveryNote(location.mapId, location.locationId);
    _pendingDeliveryNotice = DeliveryNotice(
      job: DeliveryJob(
        destination: typedPhone.isEmpty
            ? location
            : location.copyWith(contactPhone: typedPhone),
        startedAt: DateTime.now(),
        phase: DeliveryPhase.arrived,
      ),
      text: deliveryArrivalMessage(location.name, note: note),
      result: result,
    );
    notifyListeners();
  }

  /// 다른 화면이 보낸 배송의 도착 문자를 이 폰이 대신 보냅니다. 문자를 못 보내는 기기
  /// (웹·태블릿·유심 없는 폰)는 끼지 않습니다. 이 폰에는 팝업을 띄우지 않고 기록만 남깁니다 —
  /// 팝업은 배송을 보낸 화면에 뜨고(2026-10-10 사용자 결정), 2026-10-23 부터 웹에도 뜹니다
  /// ([_showOtherScreenDeliveryNotice]).
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
    // 보낸 화면이 남긴 메시지·바꾼 번호(있으면). 한 번 쓰면 지웁니다 — 다음 배송에 섞이지 않게.
    final (note, typedPhone) = _takeDeliveryNote(event.mapId, event.locationId);
    final phone =
        typedPhone.isNotEmpty ? typedPhone : (location?.contactPhone ?? '');
    DeliveryNotifyResult result;
    if (phone.isEmpty) {
      result = const DeliveryNotifyResult(
        sent: false,
        detail: '배송지 연락처를 찾지 못했습니다. 직접 연락하세요.',
      );
    } else {
      try {
        result = await _deliveryNotifier.send(
          phone: phone,
          text: deliveryArrivalMessage(name, note: note),
        );
      } catch (error) {
        result = DeliveryNotifyResult(sent: false, detail: '발송 오류: $error');
      }
    }
    if (note.isNotEmpty || typedPhone.isNotEmpty) {
      _clearDeliveryNote(event.mapId, event.locationId);
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

  // ---- 받는 분께 메시지(2026-11-17 사용자 승인) --------------------------------------
  //
  // 배송을 보낸 화면이 출발 때 래치 토픽으로 메시지를 냅니다. 문자를 대신 보내는 관리자 유심 폰은
  // 지도·장소별로 기억했다가 그 장소의 도착 문자에 넣고 지웁니다. 로봇(미션)은 메시지를 모릅니다.

  /// '지도|장소' → (메시지, 바꾼 번호, 받은 시각). 번호는 이번 배송에만 쓴 것이고 비면 장소 번호.
  final Map<String, (String, String, DateTime)> _deliveryNotes = {};

  /// 이보다 오래된 메시지는 쓰지 않습니다(배송 한 건은 길어야 수십 분).
  static const Duration _deliveryNoteTtl = Duration(hours: 3);

  void _publishDeliveryNote(
    AppSettings settings,
    LocationPoint location,
    String note, {
    String phone = '',
  }) {
    final client = _client;
    if (client == null || _connectionState != RosConnectionState.connected) {
      return;
    }
    client
      ..advertise(
          topic: settings.deliveryNoteTopic,
          type: 'std_msgs/String',
          latch: true)
      ..publishJsonString(
        topic: settings.deliveryNoteTopic,
        payload: {
          'map_id': location.mapId,
          'location_id': location.locationId,
          'note': note,
          if (phone.isNotEmpty) 'phone': phone,
          'sent_at': DateTime.now().toIso8601String(),
        },
      );
  }

  /// 도착 문자를 보낸 뒤 래치에 남은 메시지·번호를 빈 값으로 덮습니다. rosbridge(9090)는 인증이 없어
  /// 래치에 남은 번호는 같은 망의 누구나 읽을 수 있습니다 — 쓴 뒤에는 남기지 않습니다(2026-11-17).
  void _clearDeliveryNote(String mapId, String locationId) {
    final settings = _lastSettings;
    final client = _client;
    if (settings == null ||
        client == null ||
        _connectionState != RosConnectionState.connected) {
      return;
    }
    client
      ..advertise(
          topic: settings.deliveryNoteTopic,
          type: 'std_msgs/String',
          latch: true)
      ..publishJsonString(
        topic: settings.deliveryNoteTopic,
        payload: {'map_id': mapId, 'location_id': locationId, 'note': ''},
      );
  }

  void _handleDeliveryNote(Map<String, Object?> message) {
    final decoded = _decodeJsonString(message);
    if (decoded == null) {
      return;
    }
    final mapId = '${decoded['map_id'] ?? ''}';
    final locationId = '${decoded['location_id'] ?? ''}';
    if (mapId.isEmpty || locationId.isEmpty) {
      return;
    }
    final note = deliveryNoteClean('${decoded['note'] ?? ''}');
    final phone = normalizeContactPhone('${decoded['phone'] ?? ''}') ?? '';
    if (note.isEmpty && phone.isEmpty) {
      _deliveryNotes.remove('$mapId|$locationId');
      return;
    }
    _deliveryNotes['$mapId|$locationId'] = (note, phone, DateTime.now());
    while (_deliveryNotes.length > 20) {
      _deliveryNotes.remove(_deliveryNotes.keys.first);
    }
  }

  @visibleForTesting
  void handleDeliveryNoteForTest(Map<String, Object?> message) =>
      _handleDeliveryNote(message);

  /// (메시지, 바꾼 번호). 없거나 오래됐으면 둘 다 빈 값.
  (String, String) _peekDeliveryNote(String mapId, String locationId) {
    final entry = _deliveryNotes['$mapId|$locationId'];
    if (entry == null ||
        DateTime.now().difference(entry.$3) > _deliveryNoteTtl) {
      return ('', '');
    }
    return (entry.$1, entry.$2);
  }

  (String, String) _takeDeliveryNote(String mapId, String locationId) {
    final taken = _peekDeliveryNote(mapId, locationId);
    _deliveryNotes.remove('$mapId|$locationId');
    return taken;
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

  // ---- 관리자 호출(도움 요청, 2026-10-15 설계) ---------------------------------
  //
  // 미션은 관리자가 확인할 때까지 10초마다 같은 help_id 로 help_requested 를 다시 보냅니다
  // (앱을 껐다 켜도 다음 재전송 때 뜨게). 주행 알림처럼 이벤트마다 팝업을 띄우면 10초마다
  // 쌓이므로 help_id 하나에 팝업 하나만 띄우고, 같은 id 가 다시 오면 위치만 갱신합니다.
  // 확인(help_acknowledged)이나 취소(help_canceled)가 같은 id 로 오면 팝업을 닫습니다 —
  // 다른 화면에서 누른 확인도 이 이벤트로 닫힙니다.

  GoalEvent? _activeHelp;
  String? _helpPopupShownFor;
  String _helpRequestedAt = '';

  /// 관리자가 확인한 도움 요청의 id. 확인 뒤 사용자가 직접 취소하면 미션이 같은 id 로
  /// help_canceled 를 보냅니다 — 오던 관리자가 알도록 한 줄로 알립니다(2026-10-16 사용자 결정).
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
          // 도움 요청은 알림 및 로그에 남기지 않습니다 — 팝업으로 알립니다(2026-11-17).
        }
      case GoalEventKind.helpAcknowledged:
        if (_activeHelp?.helpId == event.helpId) {
          _activeHelp = null;
          _acknowledgedHelpId = event.helpId;
        }
      case GoalEventKind.helpCanceled:
        if (_activeHelp?.helpId == event.helpId) {
          _activeHelp = null;
        } else if (_acknowledgedHelpId == event.helpId) {
          // 확인 뒤의 취소는 사용자가 직접 한 것뿐입니다(미션은 그 밖의 끝에는 알리지 않습니다).
          _acknowledgedHelpId = null;
          const notice = '사용자가 도움 요청을 취소했습니다.';
          _pendingHelpNotice = notice;
        }
      default:
        break;
    }
  }

  /// 도움 팝업의 "확인". 미션이 받으면 로봇이 "관리자가 오고있습니다…"를 말하고
  /// help_acknowledged 를 냅니다 — 그 이벤트가 다른 화면의 팝업도 닫습니다.
  /// 받았거나 이미 끝난 요청이면 이 화면의 팝업 상태도 바로 지웁니다.
  Future<String> acknowledgeHelp(AppSettings settings) async {
    final help = _activeHelp;
    if (help == null) {
      return '이미 끝난 도움 요청입니다.';
    }
    var alreadyEnded = false;
    final reply = await _callService(
      service: settings.missionHelpAckService,
      type: 'vica_interfaces/srv/MissionCommand',
      // 미션은 request_id 를 확인할 help_id 로 읽습니다(새 uuid 를 만들면 안 됩니다).
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
      logAs: null, // 주행 요청 거부·실패는 팝업으로만(2026-11-17)
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

  // ---- 경비(순찰, 2026-11-14) ----------------------------------------------
  //
  // 계약은 ~/vica_data/patrol_plan/SPEC.md 2·3절입니다. 순찰 단계는 /robot_status 의
  // dialog_state(patrol*)가 정본이고, patrol_* 사건은 그 1초 사이를 메우는 귀띔과 경보·지점
  // 정보를 줍니다. 경보는 도움 요청과 같은 방식입니다 — alarm_id 하나에 팝업 하나이고,
  // 미션이 확인 전까지 10초마다 같은 id 로 다시 보냅니다(앱을 껐다 켜도 뜨게).
  //
  // 앱은 요청만 합니다. 시작·종료·확인·재개·일시정지를 받을지는 미션이 정합니다.

  final PatrolLogLoader _patrolLogLoader;

  PatrolRoute? _patrolRoute;
  bool _patrolRouteLoading = false;

  PatrolAlarm? _patrolAlarm;
  String? _patrolPopupShownFor;

  /// 이번 순찰에서 사건으로 알게 된 것. 순찰 도중에 붙은 앱에서는 비어 있습니다.
  List<String> _patrolRunNames = const [];
  DateTime? _patrolStartedAt;
  int? _patrolWaypointIndex;
  String _patrolWaypointName = '';
  int _patrolLap = 0;

  /// 사건·응답으로 먼저 안 단계와 그때. 상태 토픽(1 Hz)이 따라올 때까지만 씁니다.
  PatrolPhase? _patrolHint;
  DateTime? _patrolHintAt;
  static const _patrolHintHold = Duration(seconds: 3);

  /// 경비 칸과 경비 화면이 보는 시계. 시험이 3초 귀띔·녹화 시간을 기다리지 않고 확인하게
  /// 바꿔 끼웁니다.
  DateTime Function() patrolNow = DateTime.now;

  String? _pendingPatrolNotice;

  /// 관리자가 끝낸 종료 사건(patrol_stopped, reason=admin)을 받은 횟수와, 그 사건이 알린
  /// 홈 복귀 여부(return_home). 종료를 누른 화면이 알림 띠의 둘째 줄을 고르는 데 씁니다.
  int _patrolAdminStops = 0;
  bool _patrolStopReturnsHome = false;
  Completer<void>? _patrolStopWaiter;

  /// 종료 응답을 받고 종료 사건을 기다리는 시간. 미션은 사건을 먼저 내고 응답하지만
  /// 토픽과 서비스 응답은 길이 달라 순서가 바뀔 수 있습니다.
  static const _patrolStopEventWait = Duration(milliseconds: 1500);

  List<PatrolRecord>? _patrolRecords;
  bool _patrolRecordsLoading = false;
  bool _patrolRecordsFailed = false;
  Timer? _patrolClipTimer;

  /// 관리자가 누르지 않았는데 순찰이 끝난 까닭(patrol_stopped 의 reason). 비상정지는
  /// 전체화면 알림이 이미 알리므로 여기에 없습니다.
  static const _patrolStopNotices = <String, String>{
    'nav_failed': '순찰 지점으로 가지 못해 경비를 종료했습니다.',
    'detector_not_ready': '사람 감지가 준비되지 않아 경비를 종료했습니다.',
  };

  /// 지금 순찰 단계. 화면은 이 값으로 꺼짐·순찰 중·멈춤을 고릅니다.
  PatrolPhase get patrolPhase {
    final hint = _patrolHint;
    final at = _patrolHintAt;
    if (hint != null &&
        at != null &&
        patrolNow().difference(at) < _patrolHintHold) {
      return hint;
    }
    return PatrolPhase.of(primaryRobot?.dialogState ?? '');
  }

  /// [mapId] 지도의 저장된 순찰 경로. 아직 못 읽었거나 다른 지도의 것이면 null.
  PatrolRoute? patrolRouteFor(String? mapId) {
    final route = _patrolRoute;
    return route != null && mapId != null && route.mapId == mapId
        ? route
        : null;
  }

  bool get patrolRouteLoading => _patrolRouteLoading;

  /// 지금 걸려 있는 경보(확인 전·후 모두). 순찰을 재개하거나 끝내면 비워집니다.
  PatrolAlarm? get patrolAlarm => _patrolAlarm;

  /// 아직 띄우지 않은 경보 팝업이 있는가. 셸이 띄운 뒤 [markPatrolPopupShown] 을 부릅니다.
  bool get patrolPopupPending {
    final alarm = _patrolAlarm;
    return alarm != null &&
        !alarm.acked &&
        alarm.alarmId != _patrolPopupShownFor;
  }

  void markPatrolPopupShown() {
    _patrolPopupShownFor = _patrolAlarm?.alarmId;
  }

  /// 아직 띄우지 않은 한 줄 알림(순찰이 스스로 끝난 까닭). 셸이 띄우고 비웁니다.
  String? get pendingPatrolNotice => _pendingPatrolNotice;

  void consumePatrolNotice() {
    _pendingPatrolNotice = null;
  }

  /// 이번 순찰이 시작된 때(로봇 시계). 순찰 도중에 붙은 앱은 모릅니다.
  DateTime? get patrolStartedAt => _patrolStartedAt;

  /// 지금 몇 바퀴째인가(1부터). 모르면 0.
  int get patrolLap => _patrolLap;

  /// 지금 가는(또는 방금 닿은) 지점의 순번(0부터)과 이름. 모르면 null·빈 값.
  int? get patrolWaypointIndex => _patrolWaypointIndex;
  String get patrolWaypointName => _patrolWaypointName;

  /// 그 지점으로 출발한 앞 지점의 이름. 첫 바퀴 첫 지점이거나 모르면 빈 값.
  String get patrolFromName {
    final names = _patrolRunNames.isNotEmpty
        ? _patrolRunNames
        : (_patrolRoute?.names ?? const <String>[]);
    final index = _patrolWaypointIndex;
    if (index == null ||
        names.length < 2 ||
        index < 0 ||
        index >= names.length) {
      return '';
    }
    if (index == 0 && _patrolLap <= 1) {
      return '';
    }
    return names[(index - 1 + names.length) % names.length];
  }

  /// 경비 기록(최신순). 아직 받은 적이 없으면 null.
  List<PatrolRecord>? get patrolRecords => _patrolRecords;
  bool get patrolRecordsLoading => _patrolRecordsLoading;

  /// 마지막으로 받으려다 실패했는가(서버에 닿지 못함). 옛 목록은 그대로 둡니다.
  bool get patrolRecordsFailed => _patrolRecordsFailed;

  PatrolRecord? patrolRecordFor(String alarmId) {
    for (final record in _patrolRecords ?? const <PatrolRecord>[]) {
      if (record.alarmId == alarmId) {
        return record;
      }
    }
    return null;
  }

  void _hintPatrol(PatrolPhase phase) {
    _patrolHint = phase;
    _patrolHintAt = patrolNow();
  }

  void _clearPatrolAlarm() {
    _patrolAlarm = null;
    _patrolClipTimer?.cancel();
    _patrolClipTimer = null;
  }

  void _applyPatrolEvent(GoalEvent event, Map<String, Object?> json) {
    switch (event.kind) {
      case GoalEventKind.patrolStarted:
        final route = json['route'];
        _patrolRunNames = route is List
            ? route.map((name) => name.toString()).toList(growable: false)
            : const [];
        _patrolStartedAt = DateTime.tryParse(event.robotStamp) ?? patrolNow();
        _patrolWaypointIndex = null;
        _patrolWaypointName = '';
        _patrolLap = 0;
        _clearPatrolAlarm();
        _hintPatrol(PatrolPhase.dwell);
      case GoalEventKind.patrolWaypoint:
        _patrolWaypointIndex = (json['index'] as num?)?.toInt();
        _patrolWaypointName = event.destinationName;
        _patrolLap = (json['lap'] as num?)?.toInt() ?? _patrolLap;
        _hintPatrol(PatrolPhase.moving);
      case GoalEventKind.patrolIntruder:
      case GoalEventKind.patrolSound:
      case GoalEventKind.patrolLight:
      case GoalEventKind.patrolCameraLost:
        final alarm = PatrolAlarm.fromEvent(json, now: patrolNow());
        if (alarm == null) {
          break;
        }
        final current = _patrolAlarm;
        if (current != null && current.alarmId == alarm.alarmId) {
          // 재전송. 새로 알게 된 영상 id·사진만 채웁니다.
          _patrolAlarm = current.merged(alarm);
          break;
        }
        _patrolAlarm = alarm;
        _hintPatrol(
          alarm.kind == PatrolAlarmKind.light
              ? PatrolPhase.light
              : PatrolPhase.alarm,
        );
        _addLog(
          LogFilter.patrol,
          [
            alarm.kind.recordTitle(alarm.levelDb),
            if (alarm.place.isNotEmpty) alarm.place,
          ].join(' · '),
        );
        _watchPatrolClip(alarm);
      case GoalEventKind.patrolAcked:
        final id = (json['alarm_id'] as String?)?.trim() ?? '';
        final current = _patrolAlarm;
        if (current != null && (id.isEmpty || current.alarmId == id)) {
          _patrolAlarm = current.copyWith(acked: true);
        }
      case GoalEventKind.patrolPaused:
        _hintPatrol(PatrolPhase.paused);
      case GoalEventKind.patrolResumed:
        _clearPatrolAlarm();
        _hintPatrol(PatrolPhase.moving);
      case GoalEventKind.patrolStopped:
        _clearPatrolAlarm();
        _patrolRunNames = const [];
        _patrolStartedAt = null;
        _patrolWaypointIndex = null;
        _patrolWaypointName = '';
        _patrolLap = 0;
        _hintPatrol(PatrolPhase.off);
        if (event.reason == 'admin') {
          // 키가 없으면(옛 미션) 돌아가지 않는 것으로 봅니다.
          _patrolAdminStops += 1;
          _patrolStopReturnsHome = json['return_home'] == true;
          _patrolStopWaiter?.complete();
          _patrolStopWaiter = null;
        }
        final notice = _patrolStopNotices[event.reason];
        if (notice != null) {
          _pendingPatrolNotice = notice;
          _addLog(LogFilter.patrol, notice);
        }
      default:
        break;
    }
  }

  /// 경보 사건은 상태 토픽보다 먼저 옵니다. 그 사이를 지나서도 로봇이 경보로 서 있지
  /// 않으면 그 경보는 끝난 것입니다 — 다른 화면에서 재개·종료했고 이 앱이 그 사건을
  /// 놓친 경우(잠깐 끊김)에 팝업과 멈춤 화면이 남지 않게 합니다.
  void _reconcilePatrolAlarm(RobotStatus robot) {
    final alarm = _patrolAlarm;
    if (alarm == null || PatrolPhase.of(robot.dialogState).stoppedByAlarm) {
      return;
    }
    if (patrolNow().difference(alarm.firstSeen) > _patrolHintHold) {
      _clearPatrolAlarm();
    }
  }

  /// 영상이 다 저장될 때까지 경비 기록을 5초마다 다시 받습니다. 영상 id·길이는 기록에만
  /// 있고(확인이 빠르면 재전송이 끊겨 사건으로는 못 받습니다), 서버는 기록을 내줄 때 끝난
  /// 장면을 mp4 로 바꾸기 시작합니다. 영상이 준비되거나 경보가 풀리면, 늦어도 90초 뒤에
  /// 멈춥니다(가장 긴 영상이 60초).
  void _watchPatrolClip(PatrolAlarm alarm) {
    _patrolClipTimer?.cancel();
    _patrolClipTimer = null;
    final settings = _lastSettings;
    if (!alarm.kind.hasClip || settings == null) {
      return;
    }
    var tries = 0;
    _patrolClipTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      tries += 1;
      final current = _patrolAlarm;
      final ready = patrolRecordFor(alarm.alarmId)?.clipReady ?? false;
      if (_disposed ||
          current == null ||
          current.alarmId != alarm.alarmId ||
          ready ||
          tries > 18) {
        timer.cancel();
        return;
      }
      unawaited(refreshPatrolRecords(settings));
    });
  }

  /// 지도 서버에서 경비 기록을 다시 받습니다. 실패하면 옛 목록을 그대로 둡니다.
  Future<void> refreshPatrolRecords(AppSettings settings) async {
    if (_patrolRecordsLoading) {
      return;
    }
    _patrolRecordsLoading = true;
    notifyListeners();
    final records = await _patrolLogLoader.loadRecords(settings.mapHttpBaseUrl);
    if (_disposed) {
      return;
    }
    _patrolRecordsLoading = false;
    _patrolRecordsFailed = records == null;
    if (records != null) {
      _patrolRecords = List.unmodifiable(records);
      // 걸려 있는 경보의 영상 id·사진을 기록에서 채웁니다.
      final alarm = _patrolAlarm;
      final record = alarm == null ? null : patrolRecordFor(alarm.alarmId);
      if (alarm != null && record != null) {
        _patrolAlarm = alarm.copyWith(
          clipId: alarm.clipId.isEmpty ? record.clipId : null,
          photo: alarm.photo.isEmpty ? record.photo : null,
        );
      }
    }
    notifyListeners();
  }

  /// 로봇의 경비 기록과 영상·사진을 모두 지웁니다(2026-11-16 사용자 요청).
  ///
  /// 지우는 것은 미션입니다(`patrol_records_clear`) — 경비 중이면 거절하고 그 문구를 돌려줍니다.
  /// 지워지면 목록을 바로 비웁니다. 돌려주는 글자는 알림 띠에 그대로 씁니다.
  Future<String> clearPatrolRecords(AppSettings settings) {
    return _sendPatrolCommand(
      settings.patrolRecordsClearService,
      success: kPatrolRecordsClearedText,
      onAccepted: () {
        _patrolRecords = const <PatrolRecord>[];
        _patrolRecordsFailed = false;
      },
    );
  }

  /// rosbridge 없이 경로가 있는 화면을 그리기 위한 주입 지점입니다.
  @visibleForTesting
  void setPatrolRouteForTest(PatrolRoute? route) {
    _patrolRoute = route;
    notifyListeners();
  }

  /// 저장된 순찰 경로를 읽습니다. 못 읽으면 이전 값을 그대로 둡니다.
  Future<void> refreshPatrolRoute(AppSettings settings, String mapId) async {
    final client = _client;
    if (client == null || _connectionState != RosConnectionState.connected) {
      return;
    }
    _patrolRouteLoading = true;
    notifyListeners();
    try {
      final response = await client.callService(
        service: settings.patrolRouteGetService,
        type: 'vica_interfaces/srv/GetPatrolRoute',
        args: {'map_id': mapId},
      );
      _patrolRoute =
          PatrolRoute.fromValues(response.values, fallbackMapId: mapId);
    } catch (error) {
      _addLog(LogFilter.coordinateTransfer, '순찰 경로를 읽지 못했습니다: $error');
    } finally {
      _patrolRouteLoading = false;
      notifyListeners();
    }
  }

  /// 순찰 경로를 저장합니다. [ids] 가 비면 경로를 지웁니다(명세 3.2). [names] 는 저장이
  /// 받아들여졌을 때 화면에 바로 보일 같은 순서의 이름입니다.
  ///
  /// 로봇은 경로와 꺼 둔 감시 항목을 한 파일에 두고 언제나 통째로 받습니다. [watchOff] 를
  /// 주지 않으면 지금 저장돼 있는 값을 그대로 보냅니다(경로 편집). [announce] 가 false 면
  /// 받아들여졌을 때 알림 문구가 없습니다(스위치는 화면이 곧 결과입니다).
  Future<(bool, String)> savePatrolRoute(
    AppSettings settings,
    String mapId,
    List<String> ids, {
    List<String> names = const [],
    Set<PatrolAlarmKind>? watchOff,
    bool announce = true,
  }) async {
    final off = watchOff ?? patrolRouteFor(mapId)?.watchOff ?? const {};
    final reply = await _callService(
      service: settings.patrolRouteSaveService,
      type: 'vica_interfaces/srv/SavePatrolRoute',
      args: {
        'map_id': mapId,
        'destination_ids': ids,
        'watch_off': PatrolRoute.watchOffWire(off),
      },
      // 거절 문구는 로봇이 한국어 한 줄로 보냅니다(SavePatrolRoute.message).
      describe: (response) => response.accepted
          ? (ids.isEmpty || !announce ? '' : '순찰 경로를 저장했습니다.')
          : (response.message.isEmpty ? '요청이 거부되었습니다.' : response.message),
      failurePrefix: '순찰 경로 저장 실패',
      onAccepted: (_) => _patrolRoute = PatrolRoute(
        mapId: mapId,
        ids: List.unmodifiable(ids),
        names: List.unmodifiable(names),
        watchOff: Set.unmodifiable(off),
      ),
    );
    if (reply.accepted) {
      notifyListeners();
    }
    return (reply.accepted, reply.message);
  }

  /// 감시 항목 하나를 켜거나 끕니다(2026-11-14). 다음 경비 시작부터 적용됩니다.
  /// 셋 다 끄는 것은 보내지 않고 그 자리에서 거절합니다. 경로를 아직 못 읽었으면 아무것도 하지 않습니다.
  Future<(bool, String)> setPatrolWatch(
    AppSettings settings,
    String mapId,
    PatrolAlarmKind kind,
    bool on,
  ) async {
    final route = patrolRouteFor(mapId);
    if (route == null || route.watches(kind) == on) {
      return (false, '');
    }
    final off = {...route.watchOff};
    on ? off.remove(kind) : off.add(kind);
    if (off.length >= patrolWatchKinds.length) {
      return (false, patrolWatchNeedsOne);
    }
    return savePatrolRoute(
      settings,
      mapId,
      route.ids,
      names: route.names,
      watchOff: off,
      announce: false,
    );
  }

  /// 경비 명령 하나를 보냅니다. 수락이면 [success] 문구(빈 값이면 알림 없음)와 단계 귀띔,
  /// 거절이면 미션이 보낸 한국어 한 줄을 그대로 돌려줍니다 — 순찰 서비스의 거절 문구는
  /// 미션이 정합니다(mission_logic 의 PATROL_REJECT_TEXT).
  ///
  /// [requestId] 를 안 주면 새 UUID 입니다. [sharedService] 는 주행과 함께 쓰는 서비스
  /// (일시정지·재개)입니다 — 순찰이 이미 끝난 뒤에 누르면 미션의 주행 쪽 사유('… 요청 거부:
  /// not_paused')가 오므로 그때만 기존 표로 읽기 좋게 옮깁니다.
  Future<String> _sendPatrolCommand(
    String service, {
    required String success,
    PatrolPhase? hint,
    String? requestId,
    bool sharedService = false,
    void Function()? onAccepted,
  }) async {
    final reply = await _callService(
      service: service,
      type: 'vica_interfaces/srv/MissionCommand',
      args: {'request_id': requestId ?? _uuid.v4()},
      describe: (response) {
        if (response.accepted) {
          return success;
        }
        if (response.message.isEmpty) {
          return '요청이 거부되었습니다.';
        }
        return sharedService
            ? _localizeGateReason(response.message)
            : response.message;
      },
      failurePrefix: 'Mission Manager 요청 실패',
      logAs: LogFilter.patrol,
      onAccepted: (_) {
        if (hint != null) {
          _hintPatrol(hint);
        }
        onAccepted?.call();
      },
    );
    if (reply.accepted) {
      notifyListeners();
    }
    return reply.message;
  }

  /// 저장된 경로로 순찰을 시작합니다. 감지 노드가 준비될 때까지 로봇은 제자리에 있습니다.
  Future<String> startPatrol(AppSettings settings) {
    return _sendPatrolCommand(
      settings.patrolStartService,
      success: '경비를 시작했습니다.',
      hint: PatrolPhase.dwell,
    );
  }

  /// 경비를 끝냅니다. 순찰을 멈추고 로봇이 홈으로 돌아갑니다(2026-11-14 사용자 결정).
  ///
  /// 돌려주는 알림 띠는 [patrolStoppedNotice] 가 고릅니다. 홈으로 돌아가는지는 미션이 종료
  /// 사건(patrol_stopped 의 `return_home`)으로 알리므로, 응답을 받은 뒤 그 사건이 아직
  /// 안 왔으면 잠깐 기다립니다.
  ///
  /// 홈 복귀를 시작하지 못하면(홈 없음·Nav2 미준비) 미션은 종료는 받아들이고 응답 `message`
  /// 에 홈 복귀 서비스의 거절과 같은 글자('홈 복귀 거부: no_home')를 싣습니다. 그 문구는
  /// '홈으로 복귀' 버튼의 거절과 같은 표([_localizeGateReason])로 옮겨 둘째 줄에 보입니다 —
  /// 버튼을 눌렀을 때와 같은 글자가 나옵니다.
  Future<String> stopPatrol(AppSettings settings) async {
    final stopsBefore = _patrolAdminStops;
    var missionMessage = '';
    final reply = await _callService(
      service: settings.patrolStopService,
      type: 'vica_interfaces/srv/MissionCommand',
      args: {'request_id': _uuid.v4()},
      describe: (response) {
        missionMessage = response.message.trim();
        if (response.accepted) {
          return kPatrolStoppedText;
        }
        return missionMessage.isEmpty ? '요청이 거부되었습니다.' : missionMessage;
      },
      failurePrefix: 'Mission Manager 요청 실패',
      logAs: LogFilter.patrol,
      onAccepted: (_) {
        _hintPatrol(PatrolPhase.off);
        _clearPatrolAlarm();
      },
    );
    if (!reply.accepted || _disposed) {
      return reply.message;
    }
    // 화면은 기다리지 않고 곧바로 꺼짐으로 바꿉니다.
    notifyListeners();
    if (_patrolAdminStops == stopsBefore) {
      final waiter = _patrolStopWaiter ??= Completer<void>();
      await waiter.future.timeout(_patrolStopEventWait, onTimeout: () {});
    }
    final returnHome =
        _patrolAdminStops != stopsBefore && _patrolStopReturnsHome;
    final notice = patrolStoppedNotice(
      returnHome: returnHome,
      homeRefusal: _localizeGateReason(missionMessage),
    );
    if (!returnHome && notice != kPatrolStoppedText && !_disposed) {
      // 못 돌아간 까닭은 알림 목록에도 남깁니다(종료 문장은 위에서 이미 남았습니다).
      _addLog(LogFilter.patrol, notice); // 경비 종료 사유는 경비로(2026-11-17)
    }
    return notice;
  }

  /// 순찰 일시정지. 화면이 곧바로 바뀌므로 수락 알림은 없습니다.
  Future<String> pausePatrol(AppSettings settings) {
    return _sendPatrolCommand(
      settings.missionPauseService,
      success: '',
      hint: PatrolPhase.paused,
      sharedService: true,
    );
  }

  /// 순찰 재개. 경보로 멈춘 상태에서는 확인도 함께 한 것으로 미션이 처리합니다.
  Future<String> resumePatrol(AppSettings settings) {
    return _sendPatrolCommand(
      settings.missionResumeService,
      success: '순찰을 재개했습니다.',
      hint: PatrolPhase.moving,
      sharedService: true,
      onAccepted: _clearPatrolAlarm,
    );
  }

  /// 경보 팝업의 "확인". 로봇의 음성 반복이 꺼지고, 로봇은 '순찰 재개'까지 그대로 섭니다.
  ///
  /// request_id 에 그 팝업의 [alarmId] 를 실어 보냅니다(새 UUID 가 아닙니다). 미션은 그
  /// 경보만 확인하고 지금 걸린 경보가 다르면 거절합니다 — 뒤늦게 누른 확인이 새 경보의
  /// 음성을 꺼 버리지 않게 하려는 것입니다.
  Future<String> acknowledgePatrolAlarm(AppSettings settings, String alarmId) {
    return _sendPatrolCommand(
      settings.patrolAckService,
      success: '',
      requestId: alarmId,
      onAccepted: () {
        final current = _patrolAlarm;
        if (current != null && current.alarmId == alarmId) {
          _patrolAlarm = current.copyWith(acked: true);
        }
      },
    );
  }

  // ---- 알림이 저절로 풀리는 경우 (2026-09-30) ---------------------------------
  //
  // Nav2 가 실패해도 미션 매니저는 같은 목적지로 3초 뒤 다시 출발합니다
  // (mission_logic nav_retry_limit 2). 그러면 goal_failed 뒤에 goal_sent·
  // goal_accepted 가 다시 옵니다. 로봇은 달리는데 앱에는 '주행 실패' 팝업이
  // 확인을 누를 때까지 남아 있어, 관리자가 팝업을 안 읽고 닫는 습관이 생깁니다.
  // 다시 출발하면 팝업은 저절로 닫힙니다. 실패 사실은 알림 목록에 그대로 남습니다.

  /// 가장 최근에 팝업으로 넘긴 알림의 id. 팝업이 닫혀야 하는지 판정하는 기준입니다.
  String? _lastGoalAlertId;

  /// 가장 최근 알림이 대기 알림(막힘·만료)인가. 대기 알림은 다시 출발해도 거두지
  /// 않습니다 — 대기 만료는 곧바로 홈 복귀가 나가서, 거두면 볼 틈이 없습니다
  /// (2026-10-07). 실패 뒤 재시도와 달리 '지난 소식'이 되지도 않습니다.
  bool _lastGoalAlertIsWait = false;

  /// 로봇이 다시 출발해 더 이상 유효하지 않은 알림의 id. 열려 있는 팝업이 이
  /// 값을 보고 스스로 닫힙니다.
  String? _resolvedGoalAlertId;

  /// 이 알림의 팝업이 열려 있다면 닫아야 하는가.
  bool isGoalAlertResolved(String id) => _resolvedGoalAlertId == id;

  /// 로봇이 새 주행을 시작했습니다. 떠 있거나 뜨려던 실패·취소 팝업은 낡은
  /// 소식이 되므로 거둡니다.
  void _resolveGoalAlert() {
    if (_lastGoalAlertIsWait) {
      return;
    }
    if (_pendingGoalAlert != null) {
      // 아직 띄우기 전이면 아예 띄우지 않습니다. 알림 목록에는 이미 남았습니다.
      _pendingGoalAlert = null;
    }
    if (_lastGoalAlertId != null) {
      _resolvedGoalAlertId = _lastGoalAlertId;
      _lastGoalAlertId = null;
    }
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
    var event = GoalEvent.fromJson(message, id: _uuid.v4());
    // 도킹 실패가 온 **그때** 도크 위치가 '지도에서 지정 · 아직 확인 안 됨'이면 표시해 둡니다 —
    // 팝업이 '도크 위치 다시 잡기'를 안내합니다(2026-11-19, 목업 92).
    if (event.kind == GoalEventKind.dockFailed &&
        (_dockSpot?.mapPickUnverified ?? false)) {
      event = event.asDockFirstTry();
    }

    // 음성·다른 기기로 주행·홈 복귀·경비가 시작되면 수동 조종을 그 자리에서 멈춥니다(2026-11-18 검토).
    // 화면의 막기는 /robot_status(0.5 s 주기)를 기다리므로, 그 사이 두 명령이 섞이지 않게 합니다.
    if (teleopActive &&
        (event.kind == GoalEventKind.sent ||
            event.kind == GoalEventKind.accepted ||
            event.kind == GoalEventKind.returnHomeSent ||
            event.kind.isPatrol)) {
      releaseTeleop();
    }

    // 도움 요청은 주행 사건이 아닙니다 — 일시정지 표시·주행 알림 팝업과 따로 다룹니다.
    if (event.isHelp) {
      _applyHelpEvent(event);
      notifyListeners();
      return;
    }

    // 경비(순찰) 사건도 따로 다룹니다 — 순찰 구간 이동에는 goal_* 가 오지 않습니다.
    if (event.kind.isPatrol) {
      _applyPatrolEvent(event, message);
      notifyListeners();
      return;
    }

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

    // 로봇이 (다시) 출발했습니다. 실패 뒤 자동 재시도든 관리자의 새 요청이든,
    // 지난 실패·취소 팝업은 더 이상 지금 상황이 아닙니다.
    switch (event.kind) {
      case GoalEventKind.sent:
      case GoalEventKind.accepted:
      case GoalEventKind.returnHomeSent:
        _resolveGoalAlert();
      default:
        break;
    }

    // 다른 화면(웹 등)이 보낸 배송이 도착했으면, 이 폰이 관리자 유심 폰일 때 대신 도착 문자를
    // 보냅니다(2026-10-10). 내 배송이면 아래 _applyGoalEventToDelivery 가 지금처럼 보냅니다.
    if (event.kind == GoalEventKind.succeeded &&
        event.delivery &&
        !_isMyDeliveryArrival(event)) {
      unawaited(_relayDeliverySms(event));
    }

    // 배송 중이면 이 이벤트가 그 배송의 도착·중단일 수 있습니다.
    _applyGoalEventToDelivery(event);

    // 홈 복귀가 성공하면 그 홈은 '가 본 자리'가 됩니다. 젯슨이 home.yaml 에
    // 이미 기록했지만, 앱 화면의 경고를 바로 내리기 위해 여기서도 반영합니다.
    if (event.kind == GoalEventKind.returnHomeSucceeded && _home != null) {
      _home = _home!.copyWith(visitedOk: true, note: '');
    }
    // 주행이 끝나면(성공·실패·취소, 홈 복귀든 안내든) 홈 상태를 로봇에서 다시 읽습니다
    // (2026-11-19 사용자). 로봇은 홈 30 cm 안에 한 번이라도 들어오면 '가 봄'으로, 복귀가 막혀
    // 실패하면 '접근할 수 없음'으로 적습니다 — 방향만 못 맞춰 실패·취소로 끝난 복귀도 '가 봄'이라
    // 앱이 결과 종류만 보고 정할 수 없습니다. 로봇은 사건을 내기 전에 파일을 씁니다.
    final home = _home;
    final settings = _lastSettings;
    if (home != null &&
        settings != null &&
        _homeMapId.isNotEmpty &&
        (!home.visitedOk || home.note.isNotEmpty) &&
        const {
          GoalEventKind.succeeded,
          GoalEventKind.failed,
          GoalEventKind.canceled,
          GoalEventKind.returnHomeSucceeded,
          GoalEventKind.returnHomeFailed,
          GoalEventKind.returnHomeCanceled,
        }.contains(event.kind)) {
      unawaited(refreshHome(settings, _homeMapId));
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
        _lastGoalAlertId = event.id;
        _lastGoalAlertIsWait = event.kind.isWaitAlert;
      }
      // 주행 알림(출발·도착·실패)은 알림 및 로그에 남기지 않습니다 — 팝업으로 알립니다
      // (2026-11-17 사용자: 비상정지 분류는 실제 비상정지만).
    }
    notifyListeners();
  }

  @visibleForTesting
  void handleGoalEventForTest(Map<String, Object?> message) =>
      _handleGoalEvent(message);

  // ---- 지도 수정 (2026-11-19, 목업 75~82) --------------------------------
  //
  // 지우기·부분 스캔·되돌리기는 전부 젯슨의 map_fix_node 가 합니다. 앱은 서비스
  // /vica/map_fix 하나로 요청하고, 부분 스캔의 진행은 토픽 /vica/map_fix/state 로 받습니다.
  // 수정할 수 있는지(잠금)도 노드가 정합니다 — 앱은 그 답을 보여 주기만 합니다.

  static const mapFixService = '/vica/map_fix';
  static const mapFixStateTopic = '/vica/map_fix/state';

  // 지도 파일을 쓰고 Nav2 가 다시 읽기를 기다리거나(노드 쪽 10 s), 스캔을 받아 자세를 맞추는
  // 요청입니다. 나머지는 파일을 읽기만 합니다.
  static const _mapFixSlowActions = {
    'erase',
    'undo',
    'scan_apply',
    'scan_check',
    'scan_start',
  };

  // 거절되면 '지도 설정' 기록에 남기는 요청(지도 파일을 바꾸는 것).
  static const _mapFixLoggedActions = {'erase', 'undo', 'scan_apply'};

  MapFixStatus? _mapFixStatus;
  String _mapFixStatusMapId = '';
  MapFixScanState? _mapFixScan;

  /// [mapId] 지도의 마지막 `get` 결과(잠금·최근 수정). 아직 못 받았거나 다른 지도면 null.
  MapFixStatus? mapFixStatusFor(String? mapId) =>
      (mapId != null && _mapFixStatusMapId == mapId) ? _mapFixStatus : null;

  /// 부분 스캔의 최신 진행. 세션이 없거나 연결이 끊기면 null.
  MapFixScanState? get mapFixScan => _mapFixScan;

  /// 지도 수정 요청 하나를 보냅니다([action] 은 MapFix.srv 의 목록).
  ///
  /// 연결이 없거나 노드가 답하지 않으면 예외 대신 `reason: 'offline'` 응답을 돌려줍니다.
  Future<MapFixResult> mapFix(
    String mapId,
    String action, {
    Map<String, Object?> args = const {},
    Duration? timeout,
  }) async {
    final client = _client;
    if (client == null || _connectionState != RosConnectionState.connected) {
      return MapFixResult.offline('ROS Bridge에 연결되지 않았습니다.');
    }
    MapFixResult reply;
    var detail = '';
    try {
      final response = await client.callService(
        service: mapFixService,
        type: 'vica_interfaces/srv/MapFix',
        args: {
          'map_id': mapId,
          'action': action,
          'args_json': args.isEmpty ? '' : jsonEncode(args),
        },
        timeout: timeout ??
            Duration(seconds: _mapFixSlowActions.contains(action) ? 15 : 8),
      );
      reply = MapFixResult.fromValues(response.values);
    } catch (error) {
      // 화면에는 쉬운 말만, 오류 원문(시간 초과·서비스 없음)은 기록에만 남깁니다.
      reply = MapFixResult.offline(kMapFixNoReplyText);
      detail = ' (map_fix_node: $error)';
    }
    if (!reply.accepted &&
        !_disposed &&
        _mapFixLoggedActions.contains(action)) {
      _addLog(
        LogFilter.coordinateTransfer,
        '지도 수정 실패: ${reply.message}$detail',
      );
    }
    // 지도 그림이 바뀌었으면 목록을 다시 받아 그림 버전(image_version)을 갱신합니다. 주소가 같으면
    // 앱이 옛 그림을 그대로 씁니다(11-19 실기).
    final settings = _lastSettings;
    if (reply.accepted &&
        !_disposed &&
        settings != null &&
        _mapFixChangesImage.contains(action)) {
      requestMapList(settings);
    }
    return reply;
  }

  static const _mapFixChangesImage = {'erase', 'scan_apply', 'undo'};

  /// 잠금 상태와 최근 수정 기록을 다시 받습니다. 못 받으면 비웁니다(버튼이 꺼집니다).
  Future<MapFixResult> refreshMapFix(String mapId) async {
    final reply = await mapFix(mapId, 'get');
    if (_disposed) {
      return reply;
    }
    _mapFixStatus =
        reply.accepted ? MapFixStatus.fromResult(reply.result) : null;
    _mapFixStatusMapId = reply.accepted ? mapId : '';
    notifyListeners();
    return reply;
  }

  void _handleMapFixState(Map<String, Object?> message) {
    final state = MapFixScanState.fromJson(message);
    // 끝난 세션('done')은 남기지 않습니다 — 화면이 '세션 없음'으로 돌아갑니다.
    _mapFixScan = state.phase == 'done' ? null : state;
    notifyListeners();
  }

  /// 화면이 다 본 진행(실패 알림을 닫았을 때 등)을 치웁니다.
  void clearMapFixScan() {
    if (_mapFixScan == null) {
      return;
    }
    _mapFixScan = null;
    notifyListeners();
  }

  @visibleForTesting
  void handleMapFixStateForTest(Map<String, Object?> message) =>
      _handleMapFixState(message);

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

  /// [result] 가 지금 남아 있는 채점 결과이면 그것만 지웁니다.
  ///
  /// 지도 설정의 홈 칸('여기가 맞는지 확인')도 이 채점을 빌려 씁니다. 그 칸을 접거나
  /// 화면을 떠나며 결과를 남기면, 원격 주행 화면이 그 점수와 라이다 점을 보이고
  /// 초기 위치 '확정'을 열어 둡니다. 확정 뒤 라이다 점([committedScanHits])은
  /// 건드리지 않습니다 — 그쪽은 원격 주행 화면의 일입니다.
  void discardPoseCheck(PoseCheckResult? result) {
    if (_disposed || result == null || !identical(_poseCheck, result)) {
      return;
    }
    _poseCheck = null;
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
      if (!response.accepted) {
        _addLog(LogFilter.coordinateTransfer, message);
      }
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
        // Nav2 가 꺼져 있어 적용을 미룬 경우의 문구는 앱이 정합니다. 노드
        // (ros2/keepout_map_node.py)도 같은 말을 하지만, 젯슨의 노드를 아직
        // 재시작하지 않았을 때도 화면이 같은 문구를 보여야 합니다(2026-09-15).
        if (!_keepoutMaskApplied && response.values['reason'] == 'no_nav2') {
          _keepoutMessage = '금지구역 ${zones.length}개를 저장했습니다. '
              'Nav2가 실행되면 적용됩니다.';
        }
        _selectedKeepoutZoneId = null;
        _keepoutBackup = List.of(zones);
      } else {
        _keepoutState = KeepoutSaveState.failed;
      }
      if (_keepoutState == KeepoutSaveState.failed) {
        _addLog(LogFilter.coordinateTransfer, '금지구역 저장: $_keepoutMessage');
      }
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
    if (!applied) {
      _addLog(LogFilter.coordinateTransfer, '금지구역 상태: $text');
    }
    notifyListeners();
  }

  // ---- 레일 편집 (2026-09-30, 설계서 2026-09-28-app-route-editor-design.md 2부) ----
  //
  // 앱은 스케치(노드와 선)만 만들고, 다듬기·검사·저장·적용은 젯슨
  // route_graph_node 가 합니다. 금지구역 편집과 같은 모양입니다.

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
          return; // 이미 노드가 있는 자리
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
        // 벽을 가로지르면 화면 표시 없이 잇지 않습니다(사용자 결정 2026-09-30).
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
    // 옮긴 자리에서 이어진 선이 벽을 가로지르면 그 자리로는 옮기지 않습니다.
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
        return; // 그 사이 스케치가 또 바뀌었습니다
      }
      _routePreview = decodeRoutePreview(v['preview_json']);
      _routeChecks = RouteChecks.decode(v['checks_json']);
    } catch (_) {
      // 미리보기는 없어도 편집할 수 있습니다. route_graph_node 가 아직 없으면 여기로 옵니다.
    }
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
        // 젯슨이 다듬고 검사하고(1 s 안팎) route_server 응답까지 기다립니다(노드 3 s).
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
      // 저장됨. 적용이 안 됐으면 이유별로 알린다.
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
    if (!applied) {
      _addLog(LogFilter.coordinateTransfer, '레일 상태: $text');
    }
    notifyListeners();
  }

  @visibleForTesting
  void handleRouteStateForTest(Map<String, Object?> message) =>
      _handleRouteState(message);

  /// 레일이 저장됐다는 알림. 이 지도의 레일을 본 적이 있으면 다시 받습니다. 저장한
  /// 기기 자신도 받지만, 그때는 서버가 '그대로(304)'로 답해 파일을 다시 받지 않습니다.
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
    final reply = await _callService(
      service: service,
      type: 'std_srvs/srv/Trigger',
      // 시작은 launch 를 띄우는 일이라 응답이 조금 늦을 수 있습니다.
      timeout: const Duration(seconds: 15),
      describe: (response) =>
          response.message.isEmpty ? fallback : response.message,
      failurePrefix: '매핑 요청 실패',
    );
    return reply.message;
  }

  /// 지도를 저장합니다. 이름은 사람이, 날짜는 로봇이 붙입니다.
  ///
  /// 서비스는 곧바로 응답하고 실제 저장은 젯슨에서 따로 돕니다 — vica_map_save.sh
  /// 가 최대 120초까지 걸릴 수 있어 기다리면 다른 요청이 전부 막힙니다. 결과는
  /// /vica/mapping_status 의 detail 로 옵니다.
  ///
  /// [align] 은 저장 팝업의 '정렬해서 저장'(2026-10-07)입니다. 젯슨이 벽 방향을 재서
  /// 2° 이상 기울었을 때만 지도를 바르게 돌려 저장하고, 결과는 상태의 save_align
  /// 으로 옵니다. align 칸은 정렬할 때만 싣습니다 — 젯슨의 vica_interfaces 가
  /// 옛 빌드(칸 없음)면 rosbridge 가 모르는 칸이라며 요청을 거부하는데, 그래도
  /// '정렬하지 않고 저장'만은 예전처럼 되게 하려는 것입니다.
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
      if (!response.accepted) {
        _addLog(LogFilter.coordinateTransfer, message);
      }
      return message;
    } catch (error) {
      // rosbridge 가 요청을 거부하면 StateError 로 옵니다. 정렬 요청이 거부됐다면
      // 젯슨의 vica_interfaces 가 옛 빌드(align 칸 없음)일 가능성이 커서 다른 길을
      // 알려 줍니다. 시간 초과(TimeoutException)는 젯슨이 이미 받아 저장 중일 수
      // 있으므로 다시 누르라고 하지 않습니다 — 영문 이름은 '이미 있습니다'로 거부되고
      // 한글 이름은 지도가 한 장 더 생길 수 있습니다(2026-10-07 검토).
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
  // 회전은 그 문서 기준(0.4 아래)에서 한 단계 더 내린 0.3 입니다. 직진과 같은
  // 값으로 묶어야 지도가 곱게 나온다는 운영자 관찰(2026-09-03)이 근거입니다.
  // 제자리 90도에 5.2초·한 바퀴에 20.9초로, 0.4 일 때보다 90도당 1.3초 느립니다.
  // [미검증] 같은 복도를 두 값으로 돈 bag 비교는 아직 하지 않았습니다.
  //
  // Safety 의 상한(1.0 / 2.0)은 실주행 상한의 3.8~5배라 폭주만 막고 일상 제한은
  // 못 합니다(nav2_backlog.md C8). 그래서 보내는 값 자체를 여기서 묶습니다.
  //
  // 이 두 값은 지도 그리기 화면과 홈 위치 저장 화면이 함께 씁니다. 홈 위치는
  // 자세를 정밀하게 맞추는 일이라 느린 쪽이 유리해, 하나로 묶어 둡니다.
  static const teleopMaxLinear = 0.3;
  static const teleopMaxAngular = 0.3;

  /// 원격 주행의 수동 주행 상한(2026-11-18 사용자: 속도 0.1~0.7 m/s, 회전은 속도와 같이 오르내림).
  /// 지도 그리기·홈 위치 조종판은 위 0.3 그대로입니다.
  static const manualDriveMaxLinear = 0.7;
  static const manualDriveMaxAngular = 0.7;

  /// 수동 주행 가속 상한(2026-11-18 사용자 B안: 3.0). 직진 m/s², 회전 rad/s² 같은 수.
  /// 출발만 완만히 합니다 — 줄이거나 방향을 바꾸거나 손을 떼면 바로 그 값을 보냅니다.
  /// 0 → 0.3 m/s 0.1 s, 0 → 0.7 m/s 약 0.23 s. Nav2 없이도 그대로 동작합니다(앱 안 계산).
  static const manualDriveAccel = 3.0;

  // 20 Hz. Safety 의 0.5초 시한보다 10배 촘촘해 한두 장을 놓쳐도 끊기지 않습니다.
  static const _teleopPeriod = Duration(milliseconds: 50);

  Timer? _teleopTimer;
  bool _teleopAdvertised = false;
  // 지금 보내는 값. 가속 상한이 있으면 누르고 있는 값(_teleopTarget*)까지 50 ms 마다 서서히 올라갑니다.
  double _teleopLinear = 0;
  double _teleopAngular = 0;
  double _teleopTargetLinear = 0;
  double _teleopTargetAngular = 0;
  double? _teleopAccel;

  bool get teleopActive => _teleopTimer != null;

  /// 이 명령이 지금 실제로 나가고 있는가. 조작판 버튼이 "누르는 동안" 색을
  /// 바꿀 때 씁니다(2026-09-04). 버튼 안에 눌림 상태를 따로 두지 않고 이 값을
  /// 보는 이유는, 연결이 끊겨 명령이 안 나가는데 버튼만 빛나는 거짓 신호를
  /// 막기 위해서입니다 — 데드맨 조작판에서 색은 "로봇에 명령이 가고 있다"는 뜻입니다.
  bool isTeleopHeld({required double linear, required double angular}) =>
      teleopActive &&
      _teleopTargetLinear == linear &&
      _teleopTargetAngular == angular;

  /// 누르고 있는 동안 부릅니다. 값이 바뀌면 다시 부르면 됩니다.
  /// [maxLinear]·[maxAngular]·[accel] 은 수동 주행만 넘깁니다(기본은 지도 그리기 상한 0.3, 가속 제한 없음).
  void holdTeleop({
    required double linear,
    required double angular,
    double maxLinear = teleopMaxLinear,
    double maxAngular = teleopMaxAngular,
    double? accel,
  }) {
    final client = _client;
    if (client == null || _connectionState != RosConnectionState.connected) {
      return;
    }
    _teleopTargetLinear = linear.clamp(-maxLinear, maxLinear).toDouble();
    _teleopTargetAngular = angular.clamp(-maxAngular, maxAngular).toDouble();
    _teleopAccel = accel;
    _stepTeleop();

    if (!_teleopAdvertised) {
      client.advertise(topic: teleopTopic, type: _teleopType);
      _teleopAdvertised = true;
    }
    _publishTeleop();
    _teleopTimer ??= Timer.periodic(_teleopPeriod, (_) {
      _stepTeleop();
      _publishTeleop();
    });
    notifyListeners();
  }

  /// 보내는 값을 누르고 있는 값 쪽으로 한 걸음(50 ms) 옮깁니다. 늘릴 때만 가속 상한을 지키고,
  /// 줄이거나 방향을 바꾸면 기다리지 않습니다(방향을 바꾸면 0 에서 다시 올라갑니다).
  void _stepTeleop() {
    final accel = _teleopAccel;
    if (accel == null) {
      _teleopLinear = _teleopTargetLinear;
      _teleopAngular = _teleopTargetAngular;
      return;
    }
    final step = accel * _teleopPeriod.inMicroseconds / 1e6;
    double toward(double current, double target) {
      if (current * target < 0) {
        current = 0;
      }
      if (target.abs() <= current.abs()) {
        return target;
      }
      return current + (target - current).clamp(-step, step);
    }

    _teleopLinear = toward(_teleopLinear, _teleopTargetLinear);
    _teleopAngular = toward(_teleopAngular, _teleopTargetAngular);
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
    _teleopTargetLinear = 0;
    _teleopTargetAngular = 0;
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
      // 타이머만 끄고 알리지 않으면 '이동 중' 표시와 버튼 색이 다음 갱신까지
      // 남습니다(2026-09-04).
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
      // 수락이면 앱 문구를 씁니다. 미션은 수락에도 'pause 요청을 처리했습니다.'처럼
      // 명령 이름을 그대로 실어 보내, 관리자가 읽을 말이 아닙니다
      // (mission_manager_node._handle_mission_command). 거부 사유만 옮깁니다.
      describe: (response) => response.accepted
          ? defaultSuccessMessage
          : response.message.isEmpty
              ? '요청이 거부되었습니다.'
              : _localizeGateReason(response.message),
      failurePrefix: 'Mission Manager 요청 실패',
      logAs: null, // 주행 요청 거부·실패는 팝업으로만(2026-11-17)
    );
    return reply.message;
  }

  /// 미션·지도·홈 서비스 한 번 부르기의 공통 틀입니다.
  ///
  /// 연결을 확인하고(없으면 부르지 않고 'ROS Bridge에 연결되지 않았습니다.'), 부르고,
  /// [describe] 가 응답으로 화면 문구를 고릅니다. 거부되거나 호출이 실패했을 때만 [logAs] 분류
  /// (기본 '지도 설정')에 남깁니다 — 2026-11-17 사용자: 반영 안 된 것만 기록.
  /// 호출이 실패하면(시간 초과·서비스 없음·연결 끊김) '[failurePrefix]: 오류' 입니다.
  /// 자리마다 기본 문구와 거부 사유를 읽는 법이 달라 [describe] 로 받습니다.
  ///
  /// [onAccepted] 는 수락됐을 때 기록 뒤에 한 번 불립니다(상태 바꾸기). [busy] 는 부르기
  /// 직전에 true, 끝나면(실패 포함) false 로 불립니다 — 연결이 없으면 부르지 않습니다.
  Future<({bool accepted, String message})> _callService({
    required String service,
    required String type,
    Map<String, Object?> args = const {},
    Duration timeout = RosBridgeClient.defaultServiceTimeout,
    required String Function(RosServiceResponse response) describe,
    required String failurePrefix,
    LogFilter? logAs = LogFilter.coordinateTransfer,
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
      // 2026-11-17 사용자: 거부(반영 안 됨)만 남긴다. 수락은 화면 문구로 충분하다.
      if (!response.accepted && logAs != null) {
        _addLog(logAs, message);
      }
      if (response.accepted) {
        onAccepted?.call(response);
      }
      return (accepted: response.accepted, message: message);
    } catch (error) {
      final message = '$failurePrefix: $error';
      if (logAs != null) {
        _addLog(logAs, message);
      }
      return (accepted: false, message: message);
    } finally {
      busy?.call(false);
    }
  }

  // 거부 응답은 "목적지 요청 거부: private_destination"처럼 코드가 섞여 옵니다.
  // 아는 코드면 한국어 문구로 바꾸고, 모르는 응답은 원문 그대로 보여줍니다.
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
    _reconcilePatrolAlarm(next);
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
    // 비상정지 분류는 실제 비상정지만(2026-11-17) — 오류 사유는 시스템 진단에서 봅니다.
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
    final event = RobotEvent.fromRosMsg(message);

    if (event.belongsInHistory) {
      _healthEvents.insert(0, event);
      if (_healthEvents.length > _maxHealthEvents) {
        _healthEvents.removeRange(_maxHealthEvents, _healthEvents.length);
      }
    }

    // 주행을 막는 등급만 기존 알림 목록에도 남깁니다. WARN·DEGRADED까지 넣으면
    // 결함 발생·해소는 알림 및 로그에 남기지 않습니다(2026-11-17 사용자: 비상정지 분류는 실제
    // 비상정지만). 시스템 진단 '최근 1시간' 에서 봅니다.

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
    final wasTipped = emergencyTipped;
    _emergencyStopSources = rawSources is List
        ? rawSources.map((value) => value.toString()).toList()
        : const [];
    // 서비스 호출 중이어도 기록은 방송 기준으로 남깁니다(앱으로 건 것도 sources 에 'app').
    _logEmergencyStopChange(active, _emergencyStopSources);

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
      } else if (stateMessage.isNotEmpty) {
        // 떠 있는 동안에도 본문은 노드를 따릅니다(2026-10-15). 원인이 나중에 바뀌거나
        // (통신으로 서 있다가 넘어짐), 첫 방송이 원인보다 먼저 와 옛 문장이 실렸을 때
        // 1초 뒤 방송으로 바로잡힙니다. 같은 문장이면 아무것도 바뀌지 않습니다.
        _setEmergencyStopState(EmergencyStopState.active, stateMessage);
      }
      // 원인(넘어짐 여부)만 바뀌어도 관리자 호출 칸을 다시 그립니다.
      if (wasTipped != emergencyTipped) {
        notifyListeners();
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

  // 비상정지가 실제로 걸리고 풀린 것만 '비상정지' 분류에 남깁니다(사용자 2026-11-17).
  // 원인이 새로 붙을 때마다 한 줄('비상정지: 물리 버튼'), 풀리면 '비상정지 해제'.
  // 원인이 빠져도(버튼을 놓음) 래치가 남아 있는 동안은 아무것도 남기지 않습니다.
  void _logEmergencyStopChange(bool active, List<String> sources) {
    if (!active) {
      if (_loggedEstopActive) {
        _addLog(LogFilter.emergencyStop, '비상정지 해제');
      }
      _loggedEstopActive = false;
      _loggedEstopSources.clear();
      return;
    }
    final fresh =
        sources.where((s) => !_loggedEstopSources.contains(s)).toList();
    if (fresh.isEmpty && !_loggedEstopActive) {
      // 원인을 안 보내는 옛 노드.
      _addLog(LogFilter.emergencyStop, '비상정지 (원인 모름)');
    }
    for (final source in fresh) {
      _addLog(LogFilter.emergencyStop, '비상정지: ${estopSourceLabel(source)}');
    }
    _loggedEstopSources.addAll(fresh);
    _loggedEstopActive = true;
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
    _patrolClipTimer?.cancel();
    frontRangeTick.dispose();
    unawaited(_client?.close());
    super.dispose();
  }
}
