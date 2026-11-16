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
