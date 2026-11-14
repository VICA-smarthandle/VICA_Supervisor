// 경비(순찰) 모드의 앱 쪽 모델입니다(2026-11-14).
//
// 계약은 ~/vica_data/patrol_plan/SPEC.md 2·3절입니다 — 상태 값(dialog_state 다섯 개),
// /vica_goal_event 의 patrol_* 사건, 지도 서버의 /patrol/events.json. 화면 문구는
// '앱 UI 사전확인' 캔버스의 Patrol* 목업 14개 그대로입니다.
//
// 여기는 로봇이 보낸 값을 읽고 화면 글자를 고르는 일만 합니다. 통신과 상태 보관은
// SupervisorProvider 의 '경비' 칸이 합니다.
import '../core/korean_josa.dart';

/// 미션이 /robot_status 의 dialog_state 로 알리는 순찰 단계.
enum PatrolPhase {
  /// 경비가 꺼져 있다(다섯 값이 아닌 모든 상태).
  off,

  /// `patrolling` — 다음 지점으로 이동 중.
  moving,

  /// `patrol_dwell` — 지점 3초 정지. 시작 직후 감지 노드 준비를 기다리는 동안도 이 값.
  dwell,

  /// `patrol_alarm` — 사람·큰 소리·카메라 끊김으로 멈춤.
  alarm,

  /// `patrol_light` — 불 켜짐으로 멈춤.
  light,

  /// `patrol_paused` — 관리자 일시정지.
  paused;

  static PatrolPhase of(String dialogState) => switch (dialogState.trim()) {
        'patrolling' => PatrolPhase.moving,
        'patrol_dwell' => PatrolPhase.dwell,
        'patrol_alarm' => PatrolPhase.alarm,
        'patrol_light' => PatrolPhase.light,
        'patrol_paused' => PatrolPhase.paused,
        _ => PatrolPhase.off,
      };

  bool get active => this != PatrolPhase.off;

  /// 순찰이 돌고 있다(이동 중이거나 지점에서 잠깐 선 것).
  bool get running => this == PatrolPhase.moving || this == PatrolPhase.dwell;

  /// 경보로 멈춰 '순찰 재개'를 기다린다.
  bool get stoppedByAlarm =>
      this == PatrolPhase.alarm || this == PatrolPhase.light;
}

/// 경보 종류. 기록 파일의 kind, 사건 이름의 `patrol_` 뒤, alarm_id 의 끝과 같습니다.
enum PatrolAlarmKind {
  intruder('intruder'),
  sound('sound'),
  light('light'),
  cameraLost('camera_lost');

  const PatrolAlarmKind(this.wire);

  final String wire;

  static PatrolAlarmKind? fromWire(String? value) {
    for (final kind in PatrolAlarmKind.values) {
      if (kind.wire == value) {
        return kind;
      }
    }
    return null;
  }

  /// `patrol_intruder` 같은 사건 이름에서.
  static PatrolAlarmKind? fromEvent(String? event) =>
      event != null && event.startsWith('patrol_')
          ? fromWire(event.substring('patrol_'.length))
          : null;

  /// 팝업 제목(목업 PatrolIntruder·PatrolSound·PatrolLight·PatrolDeviceFault).
  String get popupTitle => switch (this) {
        PatrolAlarmKind.intruder => '침입 감지',
        PatrolAlarmKind.sound => '큰 소리 감지',
        PatrolAlarmKind.light => '불 켜짐 확인 요청',
        PatrolAlarmKind.cameraLost => '카메라 끊김',
      };

  /// 상태 줄·영상 창 머리의 짧은 이름. 침입은 목업(PatrolPaused·PatrolVideo) 그대로이고
  /// 나머지 셋은 같은 틀에 팝업·기록의 이름을 넣은 것입니다.
  String get shortTitle => switch (this) {
        PatrolAlarmKind.intruder => '침입 감지',
        PatrolAlarmKind.sound => '큰 소리 감지',
        PatrolAlarmKind.light => '불 켜짐',
        PatrolAlarmKind.cameraLost => '카메라 끊김',
      };

  /// 확인한 뒤 상태 칸의 한 줄('침입 감지를 확인했습니다.').
  String get ackedHeadline => '$shortTitle${josaEulReul(shortTitle)} 확인했습니다.';

  /// 팝업 본문. [place] 는 가장 가까운 저장 장소 이름이고, 모르면 그 말을 뺍니다.
  String popupBody(String place) {
    final at = place.isEmpty ? '' : '$place에 ';
    final from = place.isEmpty ? '' : '$place에서 ';
    return switch (this) {
      PatrolAlarmKind.intruder => '$at사람이 감지되었습니다.\n확인해 주세요.',
      PatrolAlarmKind.sound => '$from큰 소리 감지되었습니다.\n확인해 주세요.',
      PatrolAlarmKind.light => '$at불이 켜져 있습니다.\n확인해 주세요.',
      PatrolAlarmKind.cameraLost => '카메라 신호가 끊겼습니다.\n'
          '사람 감지와 영상 저장을 할 수 없습니다.\n'
          '로봇은 대기하고 있습니다.\n'
          '확인해 주세요.',
    };
  }

  /// 팝업 '종류' 칸.
  String kindLabel(double? levelDb) => switch (this) {
        PatrolAlarmKind.intruder => '사람',
        PatrolAlarmKind.sound =>
          levelDb == null ? '큰 소리' : '큰 소리 (${levelDb.round()} dB)',
        PatrolAlarmKind.light => '불 켜짐',
        PatrolAlarmKind.cameraLost => '카메라 끊김',
      };

  /// 경비 기록 한 줄의 제목(목업 PatrolLog).
  String recordTitle(double? levelDb) => switch (this) {
        PatrolAlarmKind.intruder => '침입 감지 · 사람',
        PatrolAlarmKind.sound =>
          levelDb == null ? '큰 소리' : '큰 소리 · ${levelDb.round()} dB',
        PatrolAlarmKind.light => '불 켜짐',
        PatrolAlarmKind.cameraLost => '카메라 끊김',
      };

  /// 팝업 '확인' 버튼 글자. 로봇이 말을 반복하는 종류(사람·큰 소리·불 켜짐)는 '(경보음 끄기)'가 붙습니다.
  /// 목업은 침입만 붙였지만, 2026-11-14 결정으로 큰 소리·불 켜짐도 음성이 생겼습니다.
  String get ackLabel => hasVoice ? '확인 (경보음 끄기)' : '확인';

  /// 영상을 남기는 종류(사람·큰 소리). 불 켜짐은 사진 한 장, 카메라 끊김은 없음.
  bool get hasClip =>
      this == PatrolAlarmKind.intruder || this == PatrolAlarmKind.sound;

  /// 로봇이 말을 반복하는 종류. 확인하면 꺼집니다. 카메라 끊김은 말이 없습니다.
  bool get hasVoice => this != PatrolAlarmKind.cameraLost;

  /// 영상이 가장 길 때의 길이(초). 큰 소리는 5초 전 + 10초 뒤, 사람은 최대 60초.
  int get maxClipSec => this == PatrolAlarmKind.sound ? 15 : 60;
}

/// 영상은 감지 5초 전부터 담습니다(명세 1절 4항).
const int kPatrolClipPrerollSec = 5;

/// `YYYYMMDD_HHMMSS_<kind>` 에서 경보 시각(로봇 시계)을 읽습니다. 모양이 다르면 null.
DateTime? patrolAlarmTime(String alarmId) {
  final match = RegExp(r'^(\d{4})(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})')
      .firstMatch(alarmId);
  if (match == null) {
    return null;
  }
  int part(int index) => int.parse(match.group(index)!);
  return DateTime(part(1), part(2), part(3), part(4), part(5), part(6));
}

String _two(int value) => value.toString().padLeft(2, '0');

/// '02:13:41'.
String patrolClock(DateTime time) =>
    '${_two(time.hour)}:${_two(time.minute)}:${_two(time.second)}';

/// 길이 '0:42'·'1:05'. 음수는 0 으로 봅니다.
String patrolDuration(num seconds) {
  final total = seconds < 0 ? 0 : seconds.floor();
  return '${total ~/ 60}:${_two(total % 60)}';
}

/// 지금 걸려 있는 경보 하나. 같은 alarm_id 가 10초마다 다시 와도 하나입니다.
class PatrolAlarm {
  const PatrolAlarm({
    required this.alarmId,
    required this.kind,
    required this.place,
    required this.mapId,
    required this.firstSeen,
    this.robotX,
    this.robotY,
    this.clipId = '',
    this.photo = '',
    this.levelDb,
    this.time,
    this.ageAtFirstSeen = Duration.zero,
    this.acked = false,
  });

  final String alarmId;
  final PatrolAlarmKind kind;

  /// 가장 가까운 저장 장소 이름. 모르면 빈 값.
  final String place;
  final String mapId;
  final double? robotX;
  final double? robotY;

  /// 영상 id. 처음에는 비어 오고 재전송이나 경비 기록에서 채워질 수 있습니다.
  final String clipId;

  /// 불 켜짐 사진 파일 이름.
  final String photo;

  /// 큰 소리의 크기(dB).
  final double? levelDb;

  /// 경보 순간(로봇 시계). alarm_id 에서 읽고, 못 읽으면 사건에 적힌 시각입니다.
  final DateTime? time;

  /// 이 앱이 처음 받은 때(앱 시계)와, 그때 이미 지나 있던 시간(로봇 시계끼리의 차).
  /// 재전송으로 처음 본 경보도 녹화 시간이 맞게 흐르도록 둘을 따로 둡니다.
  final DateTime firstSeen;
  final Duration ageAtFirstSeen;

  /// 관리자가 확인했다(음성 반복이 꺼짐). 로봇은 그대로 서 있습니다.
  final bool acked;

  /// 사건 JSON 에서. 경보 사건이 아니거나 alarm_id 가 없으면 null.
  static PatrolAlarm? fromEvent(
    Map<String, Object?> json, {
    required DateTime now,
  }) {
    final kind = PatrolAlarmKind.fromEvent(json['event'] as String?);
    final alarmId = (json['alarm_id'] as String?)?.trim() ?? '';
    if (kind == null || alarmId.isEmpty) {
      return null;
    }
    final stamp = DateTime.tryParse((json['timestamp'] as String?) ?? '');
    final time = patrolAlarmTime(alarmId) ?? stamp;
    var age = Duration.zero;
    if (time != null && stamp != null) {
      final diff = stamp.difference(time);
      // 재전송은 확인 전까지만 오므로 몇 분을 넘지 않습니다. 그 밖은 시계가 어긋난 것입니다.
      if (!diff.isNegative && diff < const Duration(minutes: 10)) {
        age = diff;
      }
    }
    return PatrolAlarm(
      alarmId: alarmId,
      kind: kind,
      place: (json['place'] as String?)?.trim() ?? '',
      mapId: (json['map_id'] as String?)?.trim() ?? '',
      robotX: (json['robot_x'] as num?)?.toDouble(),
      robotY: (json['robot_y'] as num?)?.toDouble(),
      clipId: (json['clip_id'] as String?)?.trim() ?? '',
      photo: (json['photo'] as String?)?.trim() ?? '',
      levelDb: (json['level_db'] as num?)?.toDouble(),
      time: time,
      firstSeen: now,
      ageAtFirstSeen: age,
    );
  }

  /// 같은 경보의 재전송을 받았습니다. 새로 알게 된 값(영상 id·사진·장소)만 채웁니다.
  PatrolAlarm merged(PatrolAlarm resent) => PatrolAlarm(
        alarmId: alarmId,
        kind: kind,
        place: resent.place.isNotEmpty ? resent.place : place,
        mapId: mapId.isNotEmpty ? mapId : resent.mapId,
        robotX: resent.robotX ?? robotX,
        robotY: resent.robotY ?? robotY,
        clipId: clipId.isNotEmpty ? clipId : resent.clipId,
        photo: photo.isNotEmpty ? photo : resent.photo,
        levelDb: levelDb ?? resent.levelDb,
        time: time ?? resent.time,
        firstSeen: firstSeen,
        ageAtFirstSeen: ageAtFirstSeen,
        acked: acked,
      );

  PatrolAlarm copyWith({bool? acked, String? clipId, String? photo}) =>
      PatrolAlarm(
        alarmId: alarmId,
        kind: kind,
        place: place,
        mapId: mapId,
        robotX: robotX,
        robotY: robotY,
        clipId: clipId ?? this.clipId,
        photo: photo ?? this.photo,
        levelDb: levelDb,
        time: time,
        firstSeen: firstSeen,
        ageAtFirstSeen: ageAtFirstSeen,
        acked: acked ?? this.acked,
      );

  /// 경보 시각 '02:13:41'. 모르면 빈 값.
  String get clock => time == null ? '' : patrolClock(time!);

  /// 경보가 난 뒤 지난 시간.
  Duration elapsed(DateTime now) => ageAtFirstSeen + now.difference(firstSeen);

  /// 지금 녹화 중이라면 그 길이(초, 5초 전부터). 가장 긴 길이를 넘겼으면 null —
  /// 그때는 녹화가 끝난 것이고, 실제 길이는 경비 기록이 알려 줍니다.
  int? recordingSec(DateTime now) {
    if (!kind.hasClip) {
      return null;
    }
    final seconds = elapsed(now).inSeconds + kPatrolClipPrerollSec;
    return seconds < 0 || seconds > kind.maxClipSec ? null : seconds;
  }

  /// 상태 칸 아래 줄 '02:13:41 · 화장실 · 경보음 꺼짐'.
  String get statusLine => [
        if (clock.isNotEmpty) clock,
        if (place.isNotEmpty) place,
        if (acked && kind.hasVoice) '경보음 꺼짐',
      ].join(' · ');
}

/// 관리자가 켜고 끄는 감시 항목(목업 PatrolHome 의 '감시 항목' 세 줄, 2026-11-14).
/// 이름은 경보 종류와 같습니다. 카메라 끊김은 끌 수 없습니다.
const patrolWatchKinds = [
  PatrolAlarmKind.intruder,
  PatrolAlarmKind.light,
  PatrolAlarmKind.sound,
];

/// 셋 다 끄려 할 때의 한 줄. 로봇(SavePatrolRoute 의 nothing_watched)도 같은 글자로 거절합니다.
const patrolWatchNeedsOne = '감시 항목은 하나 이상 켜 두어야 합니다.';

/// 저장된 순찰 경로(지도 하나에 하나)와, 같은 파일에 적힌 꺼 둔 감시 항목.
class PatrolRoute {
  const PatrolRoute({
    required this.mapId,
    this.ids = const [],
    this.names = const [],
    this.watchOff = const {},
  });

  final String mapId;

  /// 누른 순서의 장소 id 와, 같은 순서의 이름.
  final List<String> ids;
  final List<String> names;

  /// 꺼 둔 감시 항목. 비어 있으면 모두 켬입니다. 경로가 없어도 남습니다.
  final Set<PatrolAlarmKind> watchOff;

  bool get isEmpty => ids.isEmpty;
  int get length => ids.length;

  /// 이 항목을 보고 있는가.
  bool watches(PatrolAlarmKind kind) => !watchOff.contains(kind);

  /// SavePatrolRoute 의 watch_off 로 보낼 이름들.
  static List<String> watchOffWire(Set<PatrolAlarmKind> off) => [
        for (final kind in patrolWatchKinds)
          if (off.contains(kind)) kind.wire,
      ];

  /// GetPatrolRoute 응답에서. 경로가 없으면(found=false) 빈 경로입니다.
  factory PatrolRoute.fromValues(
    Map<String, Object?> values, {
    required String fallbackMapId,
  }) {
    List<String> strings(Object? raw) => raw is List
        ? raw.map((value) => value.toString()).toList(growable: false)
        : const [];
    final mapId = (values['map_id'] as String?)?.trim() ?? '';
    final resolved = mapId.isEmpty ? fallbackMapId : mapId;
    // 옛 로봇은 watch_off 를 보내지 않습니다 — 모두 켬으로 읽습니다.
    final named = strings(values['watch_off']);
    final watchOff = {
      for (final kind in patrolWatchKinds)
        if (named.contains(kind.wire)) kind,
    };
    if (values['found'] != true) {
      return PatrolRoute(mapId: resolved, watchOff: watchOff);
    }
    final ids = strings(values['destination_ids']);
    final names = strings(values['names']);
    return PatrolRoute(
      mapId: resolved,
      ids: ids,
      // 이름이 덜 오면 빈 값으로 채워 순서를 맞춥니다.
      names: [
        for (var i = 0; i < ids.length; i++) i < names.length ? names[i] : '',
      ],
      watchOff: watchOff,
    );
  }

  /// 목업 PatrolHome 의 한 줄 — '입구 → 안내소 → … → 다시 입구'.
  String get summary =>
      names.isEmpty ? '' : '${names.join(' → ')} → 다시 ${names.first}';
}

/// 경로 편집 중의 순서(목업 PatrolRouteEdit·PatrolRouteRemoved).
///
/// 장소를 누르면 맨 뒤에 붙고, 번호가 붙은 장소를 다시 누르면 빠지며 뒤 번호가 하나씩
/// 당겨집니다. 방금 당겨진 줄은 [shiftedFrom] 에 옛 번호를 남겨 화면이 '4 → 3'을 보입니다.
class PatrolRouteDraft {
  const PatrolRouteDraft(this.ids, {this.shiftedFrom = const {}});

  /// 저장된 경로에서 시작합니다. 같은 장소가 두 번 있으면 앞의 것만 둡니다 — 편집 화면은
  /// 한 장소에 번호 하나만 붙입니다.
  factory PatrolRouteDraft.from(List<String> saved) {
    final seen = <String>{};
    return PatrolRouteDraft([
      for (final id in saved)
        if (seen.add(id)) id,
    ]);
  }

  final List<String> ids;

  /// 방금 뺀 장소 때문에 번호가 당겨진 장소: id → 옛 번호(1부터). 다음 조작에서 비웁니다.
  final Map<String, int> shiftedFrom;

  int get length => ids.length;

  /// 이 장소의 번호(1부터). 경로에 없으면 null.
  int? numberOf(String id) {
    final index = ids.indexOf(id);
    return index < 0 ? null : index + 1;
  }

  PatrolRouteDraft toggled(String id) =>
      ids.contains(id) ? removed(id) : added(id);

  PatrolRouteDraft added(String id) =>
      ids.contains(id) ? this : PatrolRouteDraft([...ids, id]);

  PatrolRouteDraft removed(String id) {
    final index = ids.indexOf(id);
    if (index < 0) {
      return this;
    }
    return PatrolRouteDraft(
      [...ids]..removeAt(index),
      shiftedFrom: {
        for (var i = index + 1; i < ids.length; i++) ids[i]: i + 1,
      },
    );
  }

  bool sameAs(List<String> saved) {
    if (saved.length != ids.length) {
      return false;
    }
    for (var i = 0; i < ids.length; i++) {
      if (saved[i] != ids[i]) {
        return false;
      }
    }
    return true;
  }
}

/// 경비 기록 한 줄(지도 서버 /patrol/events.json 의 원소).
class PatrolRecord {
  const PatrolRecord({
    required this.alarmId,
    required this.kind,
    required this.place,
    this.time,
    this.clipId = '',
    this.photo = '',
    this.levelDb,
    this.clipState = 'missing',
    this.clipSec,
    this.clipStart,
    this.clipEnd,
    this.detectSec,
  });

  final String alarmId;
  final PatrolAlarmKind kind;
  final String place;
  final DateTime? time;
  final String clipId;
  final String photo;
  final double? levelDb;

  /// 영상 상태 — `ready`(볼 수 있음)·`recording`(저장 중)·`missing`(없음).
  final String clipState;

  /// 영상 길이(초)와 처음·끝 시각, 영상 안에서 감지 순간의 위치(초).
  final double? clipSec;
  final DateTime? clipStart;
  final DateTime? clipEnd;
  final double? detectSec;

  bool get clipReady => clipId.isNotEmpty && clipState == 'ready';
  bool get clipRecording => clipId.isNotEmpty && clipState == 'recording';
  bool get hasPhoto => photo.isNotEmpty;

  /// 모르는 종류나 alarm_id 가 없는 줄은 null 입니다.
  static PatrolRecord? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final alarmId = (raw['alarm_id'] as String?)?.trim() ?? '';
    final kind = PatrolAlarmKind.fromWire(raw['kind'] as String?);
    if (alarmId.isEmpty || kind == null) {
      return null;
    }
    DateTime? when(Object? value) =>
        value is String ? DateTime.tryParse(value) : null;
    String text(Object? value) => value is String ? value.trim() : '';
    return PatrolRecord(
      alarmId: alarmId,
      kind: kind,
      place: text(raw['place']),
      time: when(raw['time']) ?? patrolAlarmTime(alarmId),
      clipId: text(raw['clip_id']),
      photo: text(raw['photo']),
      levelDb: (raw['level_db'] as num?)?.toDouble(),
      clipState:
          text(raw['clip_state']).isEmpty ? 'missing' : text(raw['clip_state']),
      clipSec: (raw['clip_sec'] as num?)?.toDouble(),
      clipStart: when(raw['clip_start']),
      clipEnd: when(raw['clip_end']),
      detectSec: (raw['detect_sec'] as num?)?.toDouble(),
    );
  }

  String get title => kind.recordTitle(levelDb);

  /// 기록 줄의 둘째 줄 — '11-10 02:13:41 · 화장실'.
  String get subtitle => [
        if (time != null)
          '${_two(time!.month)}-${_two(time!.day)} ${patrolClock(time!)}',
        if (place.isNotEmpty) place,
      ].join(' · ');

  /// 영상·사진 창의 머리 — '침입 감지 · 화장실 · 02:13:41'.
  String get mediaTitle => [
        kind.shortTitle,
        if (place.isNotEmpty) place,
        if (time != null) patrolClock(time!),
      ].join(' · ');

  /// 영상 길이 '0:42'. 모르면 빈 값.
  String get clipLength => clipSec == null ? '' : patrolDuration(clipSec!);

  /// 영상 범위 '02:13:36 ~ 02:14:18'. 모르면 빈 값.
  String get clipRange => clipStart == null || clipEnd == null
      ? ''
      : '${patrolClock(clipStart!)} ~ ${patrolClock(clipEnd!)}';

  /// 마지막으로 사람이 보인 때의 영상 안 위치(초). 사람 영상은 안 보이고 10초 뒤에 끝나므로
  /// 끝에서 10초 앞입니다(명세 1절 4항의 규칙으로 계산한 값). 60초를 꽉 채운 영상은 끝이
  /// 규칙이 아니라 한도라서 알 수 없습니다.
  double? get lastSeenSec {
    final total = clipSec;
    if (kind != PatrolAlarmKind.intruder || total == null) {
      return null;
    }
    final last = total - 10;
    if (total >= PatrolAlarmKind.intruder.maxClipSec - 1 ||
        last <= (detectSec ?? 0)) {
      return null;
    }
    return last;
  }
}

/// '작업실 → 화장실로 가는 중입니다.'(목업 PatrolRunning). 출발한 곳을 모르면 가는 곳만.
String patrolHeadingLine(String from, String to) {
  if (to.isEmpty) {
    return '';
  }
  final going = '$to${josaRo(to)} 가는 중입니다.';
  return from.isEmpty ? going : '$from → $going';
}

/// '작업실을 뺐습니다.' + 뒤 번호가 당겨졌으면 둘째 줄(목업 PatrolRouteRemoved).
String patrolRemovedNotice(String name, {required bool shifted}) {
  final first = '$name${josaEulReul(name)} 뺐습니다.';
  return shifted ? '$first\n뒤 번호를 하나씩 당겼습니다.' : first;
}

/// 경비 종료 알림 띠의 두 줄(목업 PatrolTexts).
const String kPatrolStoppedText = '경비를 종료했습니다.';
const String kPatrolReturnHomeText = '로봇이 홈으로 돌아갑니다.';

/// 경비를 종료한 뒤의 알림 띠(2026-11-14 사용자 결정: 종료하면 로봇이 홈으로 돌아갑니다).
///
///   홈으로 돌아감([returnHome])   '경비를 종료했습니다.' + '로봇이 홈으로 돌아갑니다.'
///   못 돌아감(홈 없음 등)         '경비를 종료했습니다.' + [homeRefusal]
///   그 밖(옛 미션)                '경비를 종료했습니다.'
///
/// [returnHome] 은 patrol_stopped 사건의 `return_home` 입니다. [homeRefusal] 은 홈 복귀를
/// 시작하지 못한 까닭으로, patrol_stop 응답의 `message` 를 '홈으로 복귀' 버튼의 거절과 같은
/// 표로 옮긴 글자입니다(SupervisorProvider.stopPatrol) — 여기서 새로 짓지 않습니다.
String patrolStoppedNotice({
  required bool returnHome,
  String homeRefusal = '',
}) {
  if (returnHome) {
    return '$kPatrolStoppedText\n$kPatrolReturnHomeText';
  }
  final reason = homeRefusal.trim();
  // 미션이 평소처럼 종료 문장만 보냈으면 덧붙일 까닭이 없습니다.
  if (reason.isEmpty || reason == kPatrolStoppedText) {
    return kPatrolStoppedText;
  }
  return '$kPatrolStoppedText\n$reason';
}
