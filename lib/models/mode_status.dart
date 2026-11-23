/// 주행 묶음이 어디쯤인지. 모드 노드의 `state` 값과 같습니다.
enum ModeState {
  idle,
  starting,
  needInitialPose,
  running,
  stopping,
  error,
  unknown;

  static ModeState parse(String? raw) => switch (raw) {
        'idle' => ModeState.idle,
        'starting' => ModeState.starting,
        'need_initial_pose' => ModeState.needInitialPose,
        'running' => ModeState.running,
        'stopping' => ModeState.stopping,
        'error' => ModeState.error,
        _ => ModeState.unknown,
      };
}

/// 음성을 무엇으로 돌릴지(사용자 11-16: 앱에서 LOCAL / 외부 API 고르기).
enum VoiceChoice {
  local(
    wire: 'offline',
    label: '로컬(LOCAL)',
    hint: '로봇 안 모델(midm2-mini) · 인터넷 없이 말마다 약 3초',
  ),
  api(
    wire: 'online',
    label: '외부 API',
    hint: '클라우드 LLM · 인터넷이 필요',
  );

  const VoiceChoice(
      {required this.wire, required this.label, required this.hint});

  final String wire;
  final String label;
  final String hint;

  /// 모르는 값이면 로컬(모드 노드도 파일이 없거나 이상하면 로컬로 띄웁니다).
  static VoiceChoice fromWire(String? raw) =>
      raw == 'online' ? VoiceChoice.api : VoiceChoice.local;
}

/// 음성 연결 알림 한 건(모드 노드가 음성 로그에서 가려 냄, 사용자 11-16).
class VoiceEvent {
  const VoiceEvent(
      {required this.id,
      required this.at,
      required this.kind,
      required this.text});

  /// 모드 노드가 뜬 뒤 1 부터 늘어나는 번호. 모드 노드가 다시 뜨면 [ModeStatus.voiceEventsEpoch] 가 바뀝니다.
  final int id;
  final DateTime at;

  /// external_ok · external_fail · external_fallback · external_back · external_auth · realtime_fail ·
  final String kind;

  /// '외부 API 연결 성공' 처럼 바로 보일 문구.
  final String text;

  bool get isSuccess =>
      kind == 'external_ok' || kind == 'local_ok' || kind == 'external_back';
  bool get isFallback => kind == 'external_fallback';

  static VoiceEvent? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final id = raw['id'];
    final at = raw['at'];
    final text = raw['text'];
    if (id is! num || at is! num || text is! String) {
      return null;
    }
    return VoiceEvent(
      id: id.toInt(),
      at: DateTime.fromMillisecondsSinceEpoch((at * 1000).round()),
      kind: raw['kind'] as String? ?? '',
      text: text,
    );
  }
}

/// 주행 지도 바꾸기 요청의 결과(모드 상태의 map_change, 사용자 11-17).
class MapChangeResult {
  const MapChangeResult({
    required this.requestId,
    required this.mapId,
    required this.from,
    required this.state,
    required this.message,
    this.restarted = const [],
    this.at,
  });

  final String requestId;
  final String mapId;

  /// 바꾸기 전 maps/CURRENT_MAP.
  final String from;

  /// applied(파일을 쓰고 필요한 유닛을 다시 띄움) · refused(거절, [message] 가 이유) · failed
  final String state;
  final String message;

  /// 다시 띄운 유닛 키(nav2·mission·llm·posecheck). 비면 파일만 바꿨다(다음 주행부터).
  final List<String> restarted;
  final DateTime? at;

  bool get applied => state == 'applied';

  static MapChangeResult? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final at = raw['at'];
    return MapChangeResult(
      requestId: '${raw['request_id'] ?? ''}',
      mapId: '${raw['map_id'] ?? ''}',
      from: '${raw['from'] ?? ''}',
      state: '${raw['state'] ?? ''}',
      message: '${raw['message'] ?? ''}',
      restarted: raw['restarted'] is List
          ? [for (final k in raw['restarted'] as List) '$k']
          : const [],
      at: at is num
          ? DateTime.fromMillisecondsSinceEpoch((at * 1000).round())
          : null,
    );
  }
}

class ModeStatus {
  const ModeStatus({
    required this.mode,
    required this.state,
    this.detail = '',
    this.nav2 = '',
    this.safety = '',
    this.resetNeeded = false,
    this.failedUnits = const [],
    this.missingNodes = const [],
    this.duplicated = const [],
    this.paneNodes,
    this.stopTimeouts = const [],
    this.stopInSec,
    this.detector = 'none',
    this.voice = 'none',
    this.micCheck = 'none',
    this.voiceChoice = VoiceChoice.local,
    this.voiceEvents = const [],
    this.voiceEventsEpoch = 0,
    this.currentMapId = '',
    this.runningMaps = const {},
    this.mapMismatch = false,
    this.mapChangeBlock = '',
    this.dialogState = '',
    this.mapChange,
  });

  /// idle · drive · mapping · unknown
  final String mode;
  final ModeState state;
  final String detail;

  /// Nav2 기동 단계: starting · waiting_pose · active · aborted · stalled · down
  final String nav2;
  final String safety;
  final bool resetNeeded;
  final List<String> failedUnits;
  final List<String> missingNodes;

  /// 두 개 이상 떠 있는 감시 프로세스 이름(comm 15자) 또는 유닛 키(명령줄로 알아보는 유닛).
  final List<String> duplicated;

  /// 유닛 밖(칸·터미널)에서 뜬 주행 노드의 감시 이름(모드 노드 pane_nodes, 2026-11-18 B안). 프로세스로 보므로
  final List<String>? paneNodes;

  /// 칸·터미널에서 띄운 Nav2 가 떠 있는가. 모르면(옛 모드 노드) null.
  bool? get paneNav2 => paneNodes?.any(_nav2Guards.contains);

  static const _nav2Guards = {
    'bt_navigator',
    'planner_server',
    'controller_serv',
    'amcl'
  };

  /// 지난 정지에서 시한을 넘겨 강제 종료된 주행 유닛. 다음에 켜면 사라집니다.
  final List<String> stopTimeouts;

  /// 기동 중 정지를 예약했을 때 늦어도 몇 초 안에 끄는지. 예약이 없으면 null.
  final int? stopInSec;

  /// ⑮ 감지기 유닛 상태(active·inactive·activating·deactivating·failed). 유닛이 없으면 none.
  final String detector;

  /// 음성 유닛 상태. 유닛이 없으면 none.
  final String voice;

  /// 마이크 점검기 유닛 상태(`mic_check.state`). 없으면 none.
  final String micCheck;

  /// 고른 음성(젯슨 voice_mode 파일).
  final VoiceChoice voiceChoice;

  /// 최근 음성 연결 알림(많아야 5건, 오래된 것부터).
  final List<VoiceEvent> voiceEvents;

  /// 모드 노드가 뜬 시각(초). 알림 번호는 이 값이 같은 동안만 이어집니다.
  final double voiceEventsEpoch;

  /// maps/CURRENT_MAP — 다음에 켜는 유닛이 읽는 주행 지도(사용자 11-17).
  final String currentMapId;

  /// 지금 떠 있는 Nav2·미션·음성이 기동 때 읽은 지도(키 nav2·mission·llm). 모르면 빠집니다.
  final Map<String, String> runningMaps;

  /// 주행 중인데 유닛이 읽은 지도가 [currentMapId] 와 다르다(터미널에서 파일만 바꾼 경우, 목업 ⑦).
  final bool mapMismatch;

  /// 지금 주행 지도를 바꿀 수 없는 이유. 비면 바꿀 수 있습니다(목업 ⑥).
  final String mapChangeBlock;

  /// 미션 상태(/vica/robot_state.dialog_state). 일시정지 중이면 확인 창이 '남은 안내 취소'를 알립니다.
  final String dialogState;

  /// 마지막 지도 바꾸기 요청의 결과.
  final MapChangeResult? mapChange;

  /// Nav2 가 지금 쓰는 지도. 모르면 [currentMapId].
  String get driveMapId => runningMaps['nav2'] ?? currentMapId;

  /// 일시정지 중(안내·손잡이 놓침·순찰).
  bool get paused =>
      const {'paused', 'paused_handle', 'patrol_paused'}.contains(dialogState);

  /// Nav2 가 다 떠서 초기 위치를 받을 수 있는가(모드 노드가 Nav2 기동 기록에서 읽은 값).
  bool get nav2Up => nav2 == 'waiting_pose' || nav2 == 'active';

  /// 감지기가 켜져 있거나 켜지는 중인가.
  bool get detectorOn => detector == 'active' || detector == 'activating';

  /// 음성 노드(유닛)가 켜져 있거나 켜지는 중인가(2026-11-20, 캔버스 104).
  bool get voiceOn => voice == 'active' || voice == 'activating';

  /// 마이크 점검기가 켜져 있거나 켜지는 중·내려가는 중인가(내려가는 중에도 칩을 되돌리는 중이라 점검 중으로 본다).
  bool get micCheckActive =>
      micCheck == 'active' ||
      micCheck == 'activating' ||
      micCheck == 'deactivating';

  /// 주행 묶음이 켜져 있거나 켜지는 중·꺼지는 중인가.
  bool get driveOn => mode == 'drive';

  /// 끄기를 예약해 둔 상태(Nav2 가 다 뜬 뒤 끕니다).
  bool get stopPending => state == ModeState.stopping && stopInSec != null;

  factory ModeStatus.fromJson(Map<String, Object?> json) {
    List<String> strings(Object? raw) =>
        raw is List ? raw.map((item) => '$item').toList() : const [];
    final stopIn = json['stop_in_sec'];
    return ModeStatus(
      mode: json['mode'] as String? ?? 'unknown',
      state: ModeState.parse(json['state'] as String?),
      detail: json['detail'] as String? ?? '',
      nav2: json['nav2'] as String? ?? '',
      safety: json['safety'] as String? ?? '',
      resetNeeded: json['reset_needed'] == true,
      failedUnits: strings(json['failed_units']),
      missingNodes: strings(json['missing_nodes']),
      duplicated: strings(json['duplicated']),
      paneNodes:
          json.containsKey('pane_nodes') ? strings(json['pane_nodes']) : null,
      stopTimeouts: strings(json['stop_timeouts']),
      stopInSec: stopIn is num ? stopIn.round() : null,
      detector: json['detector'] as String? ?? 'none',
      voice: json['voice'] as String? ?? 'none',
      micCheck: (json['mic_check'] is Map
              ? (json['mic_check'] as Map)['state']
              : null) as String? ??
          'none',
      voiceChoice: VoiceChoice.fromWire(json['voice_mode'] as String?),
      voiceEvents: [
        for (final raw in (json['voice_events'] is List
            ? json['voice_events'] as List
            : const []))
          if (VoiceEvent.fromJson(raw) case final event?) event,
      ],
      voiceEventsEpoch: (json['voice_events_epoch'] as num?)?.toDouble() ?? 0,
      currentMapId: json['current_map_id'] as String? ?? '',
      runningMaps: {
        if (json['running_maps'] case final Map maps)
          for (final entry in maps.entries) '${entry.key}': '${entry.value}',
      },
      mapMismatch: json['map_mismatch'] == true,
      mapChangeBlock: json['map_change_block'] as String? ?? '',
      dialogState: json['dialog_state'] as String? ?? '',
      mapChange: MapChangeResult.fromJson(json['map_change']),
    );
  }
}

/// 사람에게 보일 유닛 이름. 모드 노드는 칸 키(nav2·posecheck …)로 줍니다.
String modeUnitLabel(String key) => switch (key) {
      'nav2' => 'Nav2',
      'posecheck' => '위치 확인',
      'mission' => '미션',
      'handle' => '손잡이',
      'monitor' => '감시',
      _ => key,
    };
