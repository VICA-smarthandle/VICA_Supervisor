import 'dart:convert';

// 이 파일은 로봇의 마이크 점검기(음성 저장소 src/mic_check_session.py)가
// WebSocket(`ws://<host>:8770/ws`)으로 보내는 메시지 8종을 표현합니다.
//
// 형식의 정본은 파이썬 쪽입니다(`_publish_status`·`_live_frame`·`_publish_results`·
// `_save_preview`·`_event`·`_toast`·`_busy_note`, 준비 중 `prep`). 빠진 칸은 기본값으로 읽고,
// 숫자는 JSON 에서 int 로 올 수 있어 `(x as num).toDouble()` 로 받습니다.

double _d(Object? x, [double fallback = 0.0]) => x is num ? x.toDouble() : fallback;
double? _dn(Object? x) => x is num ? x.toDouble() : null;
int _i(Object? x) => x is num ? x.toInt() : 0;
String _s(Object? x) => x is String ? x : '';

Map<String, Object?> _map(Object? x) => x is Map ? x.cast<String, Object?>() : const {};
List<Object?> _list(Object? x) => x is List ? x.cast<Object?>() : const [];
List<String> _strings(Object? x) => [for (final e in _list(x)) e.toString()];
List<double> _doubles(Object? x) => [for (final e in _list(x)) _d(e)];

/// 지금 단계(`status.step`).
class MicCheckStep {
  const MicCheckStep({
    required this.key,
    required this.no,
    required this.of,
    required this.name,
    required this.say,
    required this.rep,
    required this.reps,
    required this.seconds,
    required this.recording,
    required this.robot,
  });

  final String key;

  /// 화면에 보이는 단계 번호와 전체 단계 수.
  final int no;
  final int of;
  final String name;

  /// 사용자에게 읽어 줄 문장.
  final String say;

  /// 이번이 몇 번째 녹음인지(녹음 없는 단계는 0)와 그 단계의 총 횟수.
  final int rep;
  final int reps;
  final double seconds;
  final bool recording;

  /// 로봇 목소리를 재생 중인지.
  final bool robot;

  factory MicCheckStep.fromJson(Map<String, Object?> json) => MicCheckStep(
        key: _s(json['key']),
        no: _i(json['no']),
        of: _i(json['of']),
        name: _s(json['name']),
        say: _s(json['say']),
        rep: _i(json['rep']),
        reps: _i(json['reps']),
        seconds: _d(json['seconds']),
        recording: json['recording'] == true,
        robot: json['robot'] == true,
      );
}

/// 점검기가 매번 다시 보내는 전체 상태(`type: status`).
class MicCheckStatus {
  const MicCheckStatus({
    this.place = '',
    this.step = const MicCheckStep(
      key: '', no: 0, of: 0, name: '', say: '', rep: 0, reps: 0,
      seconds: 0, recording: false, robot: false,
    ),
    this.steps = const [],
    this.progress = const {},
    this.values = const {},
    this.envValues = const {},
    this.ranges = const {},
    this.names = const {},
    this.envKeys = const {},
    this.agcChoices = const [],
    this.gainChoices = const [],
    this.echoChoices = const {},
    this.gainFactory = 0.0,
    this.chipOk = true,
    this.chipProblems = const [],
  });

  final String place;
  final MicCheckStep step;

  /// 필요한 녹음이 있는 단계들(`need` = 필요한 횟수).
  final List<({String key, String name, int need})> steps;

  /// 단계 key → 시도별 판정(`pass`·`warn`·`fail`).
  final Map<String, List<String>> progress;

  /// 지금 화면의 값과 `.env` 에 저장된 값. `agc_max_gain`·`approach_min_rms`·`band_min` 은 null 일 수 있고
  /// `echo` 는 이름 문자열입니다.
  final Map<String, Object?> values;
  final Map<String, Object?> envValues;

  /// 필드 → 허용 범위(최소·최대·눈금).
  final Map<String, ({double min, double max, double step})> ranges;
  final Map<String, String> names;

  /// 필드 → `.env` 키 이름.
  final Map<String, String> envKeys;
  final List<double> agcChoices;
  final List<double> gainChoices;

  /// 에코 이름 → 화면 문구.
  final Map<String, String> echoChoices;

  /// 칩 공장 증폭값(`.env` 에 줄이 없을 때 칩이 갖는 값).
  final double gainFactory;
  final bool chipOk;
  final List<String> chipProblems;

  factory MicCheckStatus.fromJson(Map<String, Object?> json) => MicCheckStatus(
        place: _s(json['place']),
        step: json['step'] is Map
            ? MicCheckStep.fromJson(_map(json['step']))
            : const MicCheckStatus().step,
        steps: [
          for (final e in _list(json['steps']))
            (key: _s(_map(e)['key']), name: _s(_map(e)['name']), need: _i(_map(e)['need'])),
        ],
        progress: {
          for (final e in _map(json['progress']).entries) e.key: _strings(e.value),
        },
        values: _map(json['values']),
        envValues: _map(json['env_values']),
        ranges: {
          for (final e in _map(json['ranges']).entries)
            if (_list(e.value).length >= 3)
              e.key: (
                min: _d(_list(e.value)[0]),
                max: _d(_list(e.value)[1]),
                step: _d(_list(e.value)[2]),
              ),
        },
        names: {for (final e in _map(json['names']).entries) e.key: e.value.toString()},
        envKeys: {for (final e in _map(json['env_keys']).entries) e.key: e.value.toString()},
        agcChoices: _doubles(json['agc_choices']),
        gainChoices: _doubles(json['gain_choices']),
        echoChoices: {for (final e in _map(json['echo_choices']).entries) e.key: e.value.toString()},
        gainFactory: _d(json['gain_factory']),
        chipOk: json['chip_ok'] != false,
        chipProblems: _strings(json['chip_problems']),
      );
}

/// 실시간 한 조각(`type: frame`).
class MicCheckFrame {
  const MicCheckFrame({
    required this.rms,
    required this.wake,
    required this.stop,
    required this.vad,
    required this.robot,
    required this.muted,
    required this.state,
    required this.noise,
    required this.recLeft,
    required this.busy,
  });

  final double rms;

  /// 호출 점수와 "멈춰" 점수.
  final double wake;
  final double stop;

  /// 말소리 감지. 모르면 null.
  final bool? vad;
  final bool robot;
  final bool muted;
  final String state;

  /// 소음 바닥(아직 없으면 null)과 녹음 남은 시간(녹음 중이 아니면 null).
  final double? noise;
  final double? recLeft;

  /// 채점 중 같은 표시 문구. 없으면 null 또는 빈 문자열.
  final String? busy;

  factory MicCheckFrame.fromJson(Map<String, Object?> json) => MicCheckFrame(
        rms: _d(json['rms']),
        wake: _d(json['wake']),
        stop: _d(json['stop']),
        vad: json['vad'] is bool ? json['vad'] as bool : null,
        robot: json['robot'] == true,
        muted: json['muted'] == true,
        state: _s(json['state']),
        noise: _dn(json['noise']),
        recLeft: _dn(json['rec_left']),
        busy: json['busy'] is String ? json['busy'] as String : null,
      );
}

/// 실시간 알림 한 건(`type: event`). [grade] 는 `pass`·`fail`·`info`.
class MicCheckEvent {
  const MicCheckEvent({required this.grade, required this.title, required this.detail, required this.time});

  final String grade;
  final String title;
  final String detail;

  /// `HH:MM:SS`.
  final String time;

  factory MicCheckEvent.fromJson(Map<String, Object?> json) => MicCheckEvent(
        grade: _s(json['grade']),
        title: _s(json['title']),
        detail: _s(json['detail']),
        time: _s(json['time']),
      );
}

/// 결과표 한 줄(파이썬 `Row`).
class MicCheckRow {
  const MicCheckRow({
    required this.key,
    required this.name,
    required this.grade,
    required this.detail,
    required this.todo,
  });

  final String key;
  final String name;
  final String grade;
  final String detail;

  /// 고칠 일. 없으면 빈 문자열.
  final String todo;

  factory MicCheckRow.fromJson(Map<String, Object?> json) => MicCheckRow(
        key: _s(json['key']),
        name: _s(json['name']),
        grade: _s(json['grade']),
        detail: _s(json['detail']),
        todo: _s(json['todo']),
      );
}

/// 판정 결과(`type: results`). [first] 는 처음 값으로 채점한 표이고 값을 안 바꿨으면 null 입니다.
class MicCheckResults {
  const MicCheckResults({
    required this.title,
    required this.overall,
    required this.rows,
    required this.first,
    required this.stale,
  });

  final String title;
  final String overall;
  final List<MicCheckRow> rows;
  final List<MicCheckRow>? first;

  /// 문턱을 바꿔서 지금 표가 낡았는지.
  final bool stale;

  static List<MicCheckRow> _rows(Object? x) => [
        for (final e in _list(x)) MicCheckRow.fromJson(_map(e)),
      ];

  factory MicCheckResults.fromJson(Map<String, Object?> json) => MicCheckResults(
        title: _s(json['title']),
        overall: _s(json['overall']),
        rows: _rows(json['rows']),
        first: json['first'] is List ? _rows(json['first']) : null,
        stale: json['stale'] == true,
      );
}

/// 저장 미리보기(`type: save_preview`).
class MicCheckSavePreview {
  const MicCheckSavePreview({required this.lines, required this.backupDir});

  final List<String> lines;
  final String backupDir;

  factory MicCheckSavePreview.fromJson(Map<String, Object?> json) => MicCheckSavePreview(
        lines: _strings(json['lines']),
        backupDir: _s(json['backup_dir']),
      );
}

/// 점검기가 보내는 메시지 한 건. 하위형은 `type` 8종에 하나씩 대응합니다.
sealed class MicCheckMessage {
  const MicCheckMessage();

  /// 모르는 `type`·JSON 이 아님·객체가 아님·`type` 없음이면 null.
  static MicCheckMessage? parse(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    final json = decoded.cast<String, Object?>();
    return switch (json['type']) {
      'prep' => MicPrep(_s(json['text'])),
      'status' => MicStatusMessage(MicCheckStatus.fromJson(json)),
      'frame' => MicFrameMessage(MicCheckFrame.fromJson(json)),
      'event' => MicEventMessage(MicCheckEvent.fromJson(json)),
      'toast' => MicToast(_s(json['text'])),
      'busy' => MicBusy(_s(json['text'])),
      'results' => MicResultsMessage(MicCheckResults.fromJson(json)),
      'save_preview' => MicSavePreviewMessage(MicCheckSavePreview.fromJson(json)),
      _ => null,
    };
  }
}

/// 점검기가 준비하는 중(`type: prep`).
class MicPrep extends MicCheckMessage {
  const MicPrep(this.text);
  final String text;
}

class MicStatusMessage extends MicCheckMessage {
  const MicStatusMessage(this.status);
  final MicCheckStatus status;
}

class MicFrameMessage extends MicCheckMessage {
  const MicFrameMessage(this.frame);
  final MicCheckFrame frame;
}

class MicEventMessage extends MicCheckMessage {
  const MicEventMessage(this.event);
  final MicCheckEvent event;
}

/// 잠깐 띄울 알림(`type: toast`).
class MicToast extends MicCheckMessage {
  const MicToast(this.text);
  final String text;
}

/// 채점 중 같은 바쁜 표시(`type: busy`). 빈 문자열이면 표시를 지웁니다.
class MicBusy extends MicCheckMessage {
  const MicBusy(this.text);
  final String text;
}

class MicResultsMessage extends MicCheckMessage {
  const MicResultsMessage(this.results);
  final MicCheckResults results;
}

class MicSavePreviewMessage extends MicCheckMessage {
  const MicSavePreviewMessage(this.preview);
  final MicCheckSavePreview preview;
}
