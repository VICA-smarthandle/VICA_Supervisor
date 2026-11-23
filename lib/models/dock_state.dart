import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show Offset;

/// 도킹 노드의 상태 토픽(std_msgs/String JSON, 바뀔 때만·마지막 값 보관).
const String kDockStateTopic = '/vica/dock/state';
const String kDockRegisterService = '/vica/dock/register';
const String kDockGetService = '/vica/dock/get';
const String kDockDeleteService = '/vica/dock/delete';

/// 지도에서 지정한 도크를 저장하는 서비스(2026-11-19). 타입은 홈 저장과 같은
const String kDockSetService = '/vica/dock/set';

/// 도크 위치를 정한 방법(/vica/dock/get 의 source). 옛 노드는 보내지 않습니다 — 없으면 v_detect.
const String kDockSourceVDetect = 'v_detect';
const String kDockSourceMapPick = 'map_pick';

/// 지도에서 누른 도크에서 준비 위치(도크 앞 1 m)까지의 거리(m). 로봇 쪽 값과 같아야 합니다.
const double kDockStagingOffsetM = 1.151;

/// 지도에서 지정할 때 두 번째 누름이 도크에서 이만큼(m)은 떨어져야 방향으로 받습니다.
const double kDockMapPickMinGapM = 0.30;

/// 지도에서 지정해 저장한 뒤의 알림(목업 91). 줄 나눔은 사용자가 넣은 것입니다.
const String kDockMapSavedText = "지도에서 지정한 자리로 저장했습니다.\n'도킹해 보기'로 확인해 주세요.";
const String kMissionDockStartService = '/vica/mission/dock_start';
const String kMissionDockUndockService = '/vica/mission/dock_undock';
const String kMissionDockCancelService = '/vica/mission/dock_cancel';

/// 미션 dialog_state 값(도킹).
const String kDialogDocking = 'docking';
const String kDialogDocked = 'docked';
const String kDialogUndocking = 'undocking';

class DockNodeState {
  const DockNodeState({
    required this.state,
    required this.nearDock,
    required this.poseInit,
    required this.lastAction,
    required this.lastResult,
    required this.lastReason,
    this.undockPending = false,
  });

  /// idle · docking · docked · undocking
  final String state;
  final bool nearDock;

  /// 나오기가 중간에 멈춘 상태(중지·비상정지·막힘, 2026-11-19). '도크에서 나오기'를 다시 누르면
  final bool undockPending;

  /// 켜질 때 도크 위치로 AMCL 을 잡는 일: '' · pending · set · kept · timeout
  final String poseInit;
  final String lastAction;
  final String lastResult;
  final String lastReason;

  bool get docked => state == 'docked';
  bool get poseInitPending => poseInit == 'pending';

  /// 도크 안은 아닌데 '도크에서 나오기'를 받을 수 있는가 — 도크 가까이(85 cm 안)거나 나오다 멈췄을 때.
  bool get canResumeUndock => state == 'idle' && (nearDock || undockPending);

  /// 도크에서 나오다 멈춘 상태(중지·비상정지). 이때는 '도킹 시작'을 숨기고 '도크에서 나오기 다시시작'만 둡니다(11-19 사용자).
  bool get undockPaused => state == 'idle' && undockPending;

  /// rosbridge 클라이언트(RosBridgeClient)는 std_msgs/String 의 data 가 JSON 이면 **풀어서** 넘깁니다 —
  static DockNodeState? fromMessage(Map<String, Object?> message) {
    final raw = message['data'];
    try {
      final Object? j;
      if (raw is String) {
        j = jsonDecode(raw);
      } else if (message['state'] is String) {
        j = message;
      } else {
        return null;
      }
      if (j is! Map<String, Object?>) {
        return null;
      }
      final last = (j['last'] is Map)
          ? (j['last'] as Map).cast<String, Object?>()
          : const {};
      return DockNodeState(
        state: (j['state'] as String?) ?? 'idle',
        nearDock: j['near_dock'] == true,
        poseInit: (j['pose_init'] as String?) ?? '',
        lastAction: (last['action'] as String?) ?? '',
        lastResult: (last['result'] as String?) ?? '',
        lastReason: (last['reason'] as String?) ?? '',
        undockPending: j['undock_pending'] == true,
      );
    } on FormatException {
      return null;
    }
  }
}

/// 저장된 도크 위치(/vica/dock/get). 좌표는 지도(ROS) 기준.
class DockSpot {
  const DockSpot({
    required this.mapId,
    required this.dockedX,
    required this.dockedY,
    required this.dockedYaw,
    required this.stagingX,
    required this.stagingY,
    required this.stagingYaw,
    required this.savedAt,
    required this.visitedOk,
    this.source = kDockSourceVDetect,
    this.refined = false,
    this.refinedFrom = '',
    this.refinedCm = 0,
    this.refinedDeg = 0,
  });

  final String mapId;

  /// 도킹했을 때 로봇 자리(지도에 '도크'로 그린다)
  final double dockedX;
  final double dockedY;
  final double dockedYaw;

  /// 준비 위치(도크 앞 1 m)
  final double stagingX;
  final double stagingY;
  final double stagingYaw;
  final String savedAt;

  /// 한 번이라도 도킹에 성공했는가
  final bool visitedOk;

  /// 정한 방법: [kDockSourceVDetect](도크 인식) · [kDockSourceMapPick](지도에서 지정)
  final String source;

  /// 처음 도킹에 성공해 라이다로 잰 값으로 고쳐 저장했는가(한 번만 고칩니다).
  final bool refined;

  /// 고치기 전에 정한 방법(v_detect · map_pick). 옛 값이면 빈 문자열.
  final String refinedFrom;

  /// 고치면서 옮긴 거리(cm)·돌린 각도(도).
  final double refinedCm;
  final double refinedDeg;

  double get yawDeg => stagingYaw * 180.0 / 3.141592653589793;

  bool get mapPicked => source == kDockSourceMapPick;

  /// 지도에서 지정한 뒤 아직 도킹에 성공해 보지 않은 자리인가 — 처음 도킹에서 도크를 못 찾으면
  bool get mapPickUnverified =>
      !visitedOk && (mapPicked || refinedFrom == kDockSourceMapPick);

  /// 저장 시각을 '11-19 11:40' 처럼 짧게(목업 85·91). 읽지 못하면 원문입니다.
  String get savedAtLabel {
    final parsed = DateTime.tryParse(savedAt);
    if (parsed == null) {
      return savedAt.replaceFirst('T', ' ');
    }
    final t = parsed.isUtc ? parsed.toLocal() : parsed;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  /// 요약 칸 둘째 줄(목업 85·91).
  String get statusLine {
    if (visitedOk) {
      return '$savedAtLabel · 라이다로 맞춘 자리 · 가 본 자리';
    }
    if (mapPicked) {
      return '$savedAtLabel · 지도에서 지정한 자리 · 아직 확인 안 됨';
    }
    return '$savedAtLabel · 아직 확인 안 됨';
  }

  /// 처음 도킹에 성공해 도크 위치를 고쳐 저장했다는 안내(목업 91). 고치지 않았으면 null.
  String? get refinedText {
    if (!visitedOk || !refined) {
      return null;
    }
    final from =
        (refinedFrom.isEmpty ? source : refinedFrom) == kDockSourceVDetect
            ? '저장한 자리'
            : '지정한 자리';
    return '도킹했습니다. 라이다로 잰 값으로 도크 위치를 고쳐 저장했습니다'
        '($from에서 ${refinedCm.round()} cm · ${refinedDeg.abs().round()}°).';
  }

  /// 조회 응답이 어느 지도의 것인지(map_id). 도킹 노드는 자기 지도(주행 지도)의 도크만 돌려줍니다.
  static String mapIdOfTriggerMessage(String message) {
    try {
      final j = jsonDecode(message);
      return j is Map<String, Object?> ? ((j['map_id'] as String?) ?? '') : '';
    } on FormatException {
      return '';
    }
  }

  static DockSpot? fromTriggerMessage(String message) {
    try {
      final j = jsonDecode(message);
      if (j is! Map<String, Object?> || j['exists'] != true) {
        return null;
      }
      final st = (j['staging'] as Map).cast<String, Object?>();
      final dk = (j['docked'] as Map).cast<String, Object?>();
      double d(Map<String, Object?> m, String k) =>
          (m[k] as num?)?.toDouble() ?? 0.0;
      return DockSpot(
        mapId: (j['map_id'] as String?) ?? '',
        dockedX: d(dk, 'x'),
        dockedY: d(dk, 'y'),
        dockedYaw: d(dk, 'yaw'),
        stagingX: d(st, 'x'),
        stagingY: d(st, 'y'),
        stagingYaw: d(st, 'yaw'),
        savedAt: (j['saved_at'] as String?) ?? '',
        visitedOk: j['visited_ok'] == true,
        source: j['source'] == kDockSourceMapPick
            ? kDockSourceMapPick
            : kDockSourceVDetect,
        refined: j['refined'] == true,
        refinedFrom: (j['refined_from'] as String?) ?? '',
        refinedCm: (j['refined_cm'] as num?)?.toDouble() ?? 0,
        refinedDeg: (j['refined_deg'] as num?)?.toDouble() ?? 0,
      );
    } on Object {
      return null;
    }
  }
}

/// '도크 인식해서 저장' 결과(/vica/dock/register 응답 message JSON, 목업 85~88).
class DockRegisterResult {
  const DockRegisterResult({
    required this.ok,
    required this.reason,
    this.movedCm = 0,
    this.turnedDeg = 0,
    this.bumperToApexCm = 0,
    this.distM,
    this.bearingDeg,
    this.obliqueDeg,
  });

  final bool ok;

  /// 실패 사유: not_found · unstable · no_amcl · write_failed · busy ·
  final String reason;
  final double movedCm;
  final double turnedDeg;
  final double bumperToApexCm;

  /// unstable 일 때 로봇에서 본 도크: 거리(m) · 방향(도, 왼쪽 +) · 도크를 비스듬히 보는 각(도).
  final double? distM;
  final double? bearingDeg;
  final double? obliqueDeg;

  /// 도크 서비스가 없음 — 주행이 꺼져 있습니다(목업 88 아래).
  bool get driveOff => isDockDriveOff(reason);

  static DockRegisterResult fromTrigger(bool success, String message) {
    Map<String, Object?> j = const {};
    try {
      final decoded = jsonDecode(message);
      if (decoded is Map<String, Object?>) {
        j = decoded;
      }
    } on FormatException {
      return DockRegisterResult(
          ok: false, reason: message.isEmpty ? 'call_failed' : message);
    }
    double? d(String k) => (j[k] as num?)?.toDouble();
    return DockRegisterResult(
      ok: success,
      reason: (j['reason'] as String?) ?? (success ? '' : message),
      movedCm: d('moved_cm') ?? 0,
      turnedDeg: d('turned_deg') ?? 0,
      bumperToApexCm: d('bumper_to_apex_cm') ?? 0,
      distM: d('dist_m'),
      bearingDeg: d('bearing_deg'),
      obliqueDeg: d('oblique_deg'),
    );
  }

  /// 저장 성공 알림(목업 85).
  String get savedText => '도크를 찾아 저장했습니다. 도크 앞 1 m 지점을 준비 위치로 잡았습니다'
      '(서 있던 자리에서 ${movedCm.round()} cm).';
}

/// 도크 서비스가 없는(주행 꺼짐) 실패인가. rosbridge 연결이 없는 것(not_connected)은 주행 꺼짐이
bool isDockDriveOff(String reason) => reason == 'call_failed';

/// rosbridge 에 연결되지 않아 도크 서비스를 부르지 못했을 때의 짧은 알림(다른 서비스와 같은 문구).
const String kDockNotConnectedText = 'ROS Bridge에 연결되지 않았습니다.';

/// 로봇에서 본 방향(도, 정면 0 · 왼쪽 +)을 8방 말로 바꿉니다.
String dockSideWord(double bearingDeg) {
  const words = ['앞', '왼쪽 앞', '왼쪽', '왼쪽 뒤', '뒤', '오른쪽 뒤', '오른쪽', '오른쪽 앞'];
  final turn = (bearingDeg % 360 + 360) % 360;
  return words[(turn / 45).round() % 8];
}

/// 저장된 도크가 로봇에서 어느 쪽 몇 m 인지(목업 86 회색 칸). 로봇 방향 [robotYawDeg] 는 도입니다.
String savedDockHint({
  required double dockX,
  required double dockY,
  required double robotX,
  required double robotY,
  required double robotYawDeg,
}) {
  final dx = dockX - robotX;
  final dy = dockY - robotY;
  final bearing = math.atan2(dy, dx) * 180.0 / math.pi - robotYawDeg;
  final dist = math.sqrt(dx * dx + dy * dy);
  return '저장된 도크는 로봇의 ${dockSideWord(bearing)} 약 ${dist.toStringAsFixed(1)} m에 있습니다.';
}

/// '지금 로봇에서 본 도크'의 굵은 줄(목업 87). [bearingDeg] 는 왼쪽이 +.
String dockSeenText(double distM, double bearingDeg) {
  final dist = '약 ${distM.toStringAsFixed(1)} m 앞';
  if (bearingDeg.abs() < 5) {
    return '$dist · 정면';
  }
  return '$dist · ${bearingDeg > 0 ? '왼쪽' : '오른쪽'}으로 ${bearingDeg.abs().round()}°';
}

/// 인식이 불안정할 때의 안내 한 줄(목업 87 — 경우에 따라 굵은 줄만 바뀝니다).
String dockUnstableAdvice({double? distM, double? obliqueDeg}) {
  if ((distM ?? 0) > 2.0) {
    return '도크 쪽으로 1 m쯤까지 가까이 옮긴 뒤\n다시 눌러 주세요.';
  }
  if ((obliqueDeg ?? 0).abs() > 45) {
    return '도크를 옆에서 보고 있습니다. 도크 정면 쪽으로 옮긴 뒤 다시 눌러 주세요.';
  }
  return '로봇과 도크 사이에 물건이 있는지 확인한 뒤 다시 눌러 주세요.';
}

/// 지도에서 지정한 두 점(목업 89·90). 좌표는 지도(ROS) 기준입니다.
class DockMapPick {
  const DockMapPick({required this.dock, required this.front});

  /// 먼저 누른 도크 구조물
  final Offset dock;

  /// 두 번째로 누른 도크 앞쪽(로봇이 들어올 쪽)
  final Offset front;

  /// 두 번째 누름을 방향으로 받을 만큼 떨어져 있는가.
  static bool farEnough(Offset dock, Offset front) =>
      (dock - front).distance >= kDockMapPickMinGapM;

  /// 로봇이 도크를 바라보는 방향(rad) — 앞쪽에서 도크로.
  double get fwd => math.atan2(dock.dy - front.dy, dock.dx - front.dx);

  double get fwdDeg => fwd * 180.0 / math.pi;

  /// 준비 위치(도크 앞 1 m). 화면 미리보기용이고, 저장하는 값은 로봇이 다시 계산합니다.
  Offset get staging => Offset(
        dock.dx - kDockStagingOffsetM * math.cos(fwd),
        dock.dy - kDockStagingOffsetM * math.sin(fwd),
      );
}

/// 도킹·나오기 실패 알림의 첫 줄(목업 69·73). 사유는 도킹 노드·미션이 보낸 값.
String dockFailFirstLine(String reason, {required bool undock}) {
  switch (reason) {
    case 'not_found':
      return undock ? 'V자를 찾지 못해 나오지 않았습니다.' : '도크 앞에서 V자를 찾지 못했습니다.';
    case 'out_of_range':
    case 'too_close':
      return '도크 정면에서 너무 벗어나 있습니다.';
    case 'lost':
      return '들어가는 중에 V자를 놓쳤습니다.';
    case 'obstacle':
      return '범퍼 앞에 V자가 아닌 물체가 있습니다.';
    case 'no_motion':
      return '명령을 냈지만 바퀴가 움직이지 않았습니다.';
    case 'timeout':
      return undock ? '120초 안에 끝내지 못했습니다.' : '60초 안에 끝내지 못했습니다.';
    case 'estop':
      return '비상정지로 멈췄습니다. 해제한 뒤 다시 누르세요.';
    case 'blocked':
      return undock
          ? '뒤가 30초 넘게 막혀 도크에서 나오지 못했습니다.'
          : '앞이 30초 넘게 막혀 들어가지 못했습니다.';
    case 'misaligned':
      return '도크에 들어갔지만 자리가 어긋났습니다.';
    case 'nav_failed':
      return '도크 앞까지 가지 못했습니다.';
    case 'sensor':
      return '센서 값이 들어오지 않았습니다.';
    case 'conflict':
      return '다른 주행 명령과 겹쳐 멈췄습니다.';
    case 'dock_node_down':
      return '도킹 노드가 응답하지 않습니다.';
    default:
      return reason.isEmpty ? '알 수 없는 이유로 멈췄습니다.' : reason;
  }
}
