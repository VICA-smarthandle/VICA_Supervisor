// 이 파일은 모드 노드가 내는 /vica/mode_status 를 표현합니다.
//
// 모드 노드는 상태를 저장하지 않고 매 주기 systemd·프로세스·저널에서 다시 읽어 냅니다
// (scripts/autostart/mode_logic.py 의 derive_status). 그래서 앱도 이 값만 믿고 그립니다.

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
/// [wire] 는 모드 노드의 voice_mode 값입니다.
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

  const VoiceChoice({required this.wire, required this.label, required this.hint});

  final String wire;
  final String label;
  final String hint;

  /// 모르는 값이면 로컬(모드 노드도 파일이 없거나 이상하면 로컬로 띄웁니다).
  static VoiceChoice fromWire(String? raw) =>
      raw == 'online' ? VoiceChoice.api : VoiceChoice.local;
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
    this.stopTimeouts = const [],
    this.stopInSec,
    this.detector = 'none',
    this.voice = 'none',
    this.voiceChoice = VoiceChoice.local,
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

  /// 지난 정지에서 시한을 넘겨 강제 종료된 주행 유닛. 다음에 켜면 사라집니다.
  final List<String> stopTimeouts;

  /// 기동 중 정지를 예약했을 때 늦어도 몇 초 안에 끄는지. 예약이 없으면 null.
  final int? stopInSec;

  /// ⑮ 감지기 유닛 상태(active·inactive·activating·deactivating·failed). 유닛이 없으면 none.
  final String detector;

  /// 음성 유닛 상태. 유닛이 없으면 none.
  final String voice;

  /// 고른 음성(젯슨 voice_mode 파일).
  final VoiceChoice voiceChoice;

  /// Nav2 가 다 떠서 초기 위치를 받을 수 있는가(모드 노드가 Nav2 기동 기록에서 읽은 값).
  bool get nav2Up => nav2 == 'waiting_pose' || nav2 == 'active';

  /// 감지기가 켜져 있거나 켜지는 중인가.
  bool get detectorOn => detector == 'active' || detector == 'activating';

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
      stopTimeouts: strings(json['stop_timeouts']),
      stopInSec: stopIn is num ? stopIn.round() : null,
      detector: json['detector'] as String? ?? 'none',
      voice: json['voice'] as String? ?? 'none',
      voiceChoice: VoiceChoice.fromWire(json['voice_mode'] as String?),
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
