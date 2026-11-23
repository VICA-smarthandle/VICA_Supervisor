import 'dart:convert';
import 'dart:ui' show Offset;

import '../core/json_read.dart';

/// 지우기 사각형의 한 변 최솟값(m). 이보다 작은 드래그는 버립니다. 노드의 MIN_RECT_M 과 같습니다.
const double kMapFixMinRectM = 0.05;

/// 한 번에 지울 수 있는 구역 수(11-19 사용자). 노드의 MAX_RECTS 와 같습니다.
const int kMapFixMaxRects = 10;

/// 지도 수정 노드가 답하지 않을 때(연결은 됨). 오류 원문은 기록에만 남깁니다(목업 94 ⑤).
const kMapFixNoReplyText = '지도 수정 노드가 응답하지 않습니다. 잠시 뒤 다시 시도해 주세요.';

/// 부분 스캔 반경(m)의 선택지와 처음 값(2026-11-18 사용자: 1·2·3 m, 기본 2 m).
const List<double> kMapFixRadii = [1.0, 2.0, 3.0];
const double kMapFixDefaultRadius = 2.0;

double _number(Object? value) => value is num ? value.toDouble() : 0;

double? _numberOrNull(Object? value) => value is num ? value.toDouble() : null;

/// [x, y] 를 점으로 읽습니다. 모양이 다르면 null.
Offset? _point(Object? value) {
  if (value is List &&
      value.length >= 2 &&
      value[0] is num &&
      value[1] is num) {
    return Offset((value[0] as num).toDouble(), (value[1] as num).toDouble());
  }
  return null;
}

Map<String, Object?> _object(Object? value) =>
    value is Map ? value.cast<String, Object?>() : const {};

/// 서비스 /vica/map_fix 의 응답 하나.
class MapFixResult {
  const MapFixResult({
    required this.accepted,
    required this.reason,
    required this.message,
    this.result = const {},
  });

  final bool accepted;

  /// 사유 코드. 통과면 ''. 통과했지만 Nav2 에는 아직이면 'no_nav2' 등(MapFix.srv 참고).
  final String reason;
  final String message;

  /// action 별 결과(result_json 을 푼 것). 깨졌거나 없으면 빈 객체입니다.
  final Map<String, Object?> result;

  factory MapFixResult.fromValues(Map<String, Object?> values) {
    var result = const <String, Object?>{};
    final raw = values['result_json'];
    if (raw is Map) {
      result = raw.cast<String, Object?>();
    } else if (raw is String && raw.isNotEmpty) {
      try {
        result = _object(jsonDecode(raw));
      } on FormatException {}
    }
    return MapFixResult(
      accepted: values['accepted'] == true,
      reason: jsonString(values['reason']),
      message: jsonString(values['message']),
      result: result,
    );
  }

  /// 로봇에 닿지 못했을 때(연결 없음·시간 초과·노드 없음)의 응답입니다.
  factory MapFixResult.offline(String message) =>
      MapFixResult(accepted: false, reason: 'offline', message: message);

  /// Nav2 가 고친 지도를 읽었는가. false 면 파일만 바뀐 것입니다.
  bool get applied => result['applied'] == true;

  /// 미션이 켜져 있어 미션은 다시 켜질 때까지 옛 지도를 쓰는가.
  bool get missionStale => result['mission_stale'] == true;

  /// 부분 스캔을 적용했을 때의 위치 맞춤 %(같은 스캔으로 잰 수정 전·후). 없으면 null.
  double? get scoreBefore => _numberOrNull(result['score_before']);
  double? get scoreAfter => _numberOrNull(result['score_after']);
}

/// 지우기에 보내는 사각형(ROS map 좌표, m).
class MapFixRect {
  const MapFixRect({
    required this.xMin,
    required this.yMin,
    required this.xMax,
    required this.yMax,
  });

  /// 드래그의 두 끝점으로 만듭니다. 어느 쪽으로 끌었든 min·max 를 정리합니다.
  factory MapFixRect.fromCorners(Offset a, Offset b) => MapFixRect(
        xMin: a.dx < b.dx ? a.dx : b.dx,
        yMin: a.dy < b.dy ? a.dy : b.dy,
        xMax: a.dx < b.dx ? b.dx : a.dx,
        yMax: a.dy < b.dy ? b.dy : a.dy,
      );

  final double xMin;
  final double yMin;
  final double xMax;
  final double yMax;

  double get width => xMax - xMin;
  double get height => yMax - yMin;

  Map<String, Object?> toJson() => {
        'x_min': xMin,
        'y_min': yMin,
        'x_max': xMax,
        'y_max': yMax,
      };
}

/// '최근 수정' 한 줄.
class MapFixHistoryEntry {
  const MapFixHistoryEntry({
    required this.at,
    required this.kind,
    this.radiusM,
    this.added = 0,
    this.removed = 0,
    this.black = 0,
    this.gray = 0,
    this.rectCount = 0,
  });

  /// 수정한 시각(ISO, 예 2026-11-18T15:42:07).
  final String at;

  /// 'scan'(부분 스캔) 또는 'erase'(지우기).
  final String kind;
  final double? radiusM;
  final int added;
  final int removed;
  final int black;
  final int gray;
  final int rectCount;

  factory MapFixHistoryEntry.fromJson(Map<String, Object?> json) {
    final radius = json['radius_m'];
    final rects = json['rects'];
    return MapFixHistoryEntry(
      at: jsonString(json['at']),
      kind: jsonString(json['kind']),
      radiusM: radius is num ? radius.toDouble() : null,
      added: jsonInt(json['added']),
      removed: jsonInt(json['removed']),
      black: jsonInt(json['black']),
      gray: jsonInt(json['gray']),
      rectCount: rects is List ? rects.length : 0,
    );
  }

  bool get isScan => kind == 'scan';

  /// 줄 이름. '부분 스캔 · 2 m' / '지우기 · 3곳'.
  String get title {
    if (isScan) {
      final radius = radiusM;
      return radius == null ? '부분 스캔' : '부분 스캔 · ${mapFixMetres(radius)}';
    }
    return '지우기 · $rectCount곳';
  }

  /// 아랫줄. '11-18 15:42 · 새로 41칸 · 없어짐 28칸' / '… · 검은 칸 19개 · 회색 칸 3개'.
  String get detail {
    final what =
        isScan ? '새로 $added칸 · 없어짐 $removed칸' : '검은 칸 $black개 · 회색 칸 $gray개';
    final time = when;
    return time.isEmpty ? what : '$time · $what';
  }

  /// '11-18 15:42'. 시각을 못 읽으면 받은 글자 그대로입니다.
  String get when {
    final match =
        RegExp(r'^\d{4}-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})').firstMatch(at);
    if (match == null) {
      return at;
    }
    return '${match[1]}-${match[2]} ${match[3]}:${match[4]}';
  }
}

/// 반경을 '2 m' · '1.5 m' 로 적습니다.
String mapFixMetres(double metres) {
  final whole = metres.roundToDouble();
  return (metres - whole).abs() < 0.05
      ? '${whole.toInt()} m'
      : '${metres.toStringAsFixed(1)} m';
}

/// 위치 맞춤을 '84 %' 로 적습니다.
String mapFixPercent(double score) => '${score.round()} %';

/// `get` 의 결과 — 지금 수정할 수 있는지와 최근 수정 기록.
class MapFixStatus {
  const MapFixStatus({
    required this.lock,
    required this.canScan,
    this.history = const [],
  });

  /// 잠금 사유. ''(가능) · 'busy_driving'(주행·미션·움직임) · 'no_status'(로봇 상태를 못 받음).
  final String lock;

  /// 부분 스캔을 할 수 있는가(잠기지 않았고 주행 지도일 때).
  final bool canScan;

  /// 최근 수정, 새것부터.
  final List<MapFixHistoryEntry> history;

  factory MapFixStatus.fromResult(Map<String, Object?> result) {
    final history = result['history'];
    return MapFixStatus(
      lock: jsonString(result['lock']),
      canScan: result['can_scan'] == true,
      history: history is List
          ? history
              .whereType<Map>()
              .map(
                (entry) => MapFixHistoryEntry.fromJson(
                  entry.cast<String, Object?>(),
                ),
              )
              .toList(growable: false)
          : const [],
    );
  }

  bool get locked => lock.isNotEmpty;

  /// 잠기지 않았는데 부분 스캔만 안 되면 주행 지도가 아닌 지도를 보고 있는 것입니다.
  bool get isDriveMap => locked || canScan;
}

/// `erase_count` 의 사각형 하나.
typedef MapFixRectCount = ({double wM, double hM, int black, int gray});

/// `erase_count` 의 결과 — 지우면 바뀔 칸 수.
class MapFixEraseCount {
  const MapFixEraseCount({
    this.rects = const [],
    this.black = 0,
    this.gray = 0,
  });

  final List<MapFixRectCount> rects;
  final int black;
  final int gray;

  factory MapFixEraseCount.fromResult(Map<String, Object?> result) {
    final rects = result['rects'];
    return MapFixEraseCount(
      rects: rects is List
          ? rects.whereType<Map>().map<MapFixRectCount>((rect) {
              return (
                wM: _number(rect['w_m']),
                hM: _number(rect['h_m']),
                black: jsonInt(rect['black']),
                gray: jsonInt(rect['gray']),
              );
            }).toList(growable: false)
          : const [],
      black: jsonInt(result['black']),
      gray: jsonInt(result['gray']),
    );
  }
}

/// `scan_check` 의 결과 — 지금 스캔으로 자세만 다시 맞춰 본 값.
class MapFixScanCheck {
  const MapFixScanCheck({
    required this.ok,
    required this.reason,
    required this.score,
    this.ambiguous = const [],
    this.hits = const [],
    this.centre,
  });

  final bool ok;
  final String reason;

  /// 위치 맞춤 %(지도와 라이다).
  final double score;

  /// 구분되지 않는 방향. 'forward' · 'lateral' · 'yaw'.
  final List<String> ambiguous;

  /// 맞춘 자세에서 본 라이다 점(ROS 좌표).
  final List<Offset> hits;

  /// 반경 원의 중심 — 맞춘 자세의 라이다 자리(ROS 좌표). 노드는 여기서 반경을 잽니다.
  final Offset? centre;

  factory MapFixScanCheck.fromResult(Map<String, Object?> result) {
    final hits = result['hits'];
    return MapFixScanCheck(
      ok: result['ok'] == true,
      reason: jsonString(result['reason']),
      score: _number(result['score']),
      ambiguous: jsonStringList(result['ambiguous']),
      hits: hits is List
          ? hits
              .whereType<List>()
              .where((hit) => hit.length >= 2)
              .map((hit) => Offset(_number(hit[0]), _number(hit[1])))
              .toList(growable: false)
          : const [],
      centre: _point(result['centre']),
    );
  }
}

/// 부분 스캔으로 변경된 칸 하나(칸 중심의 ROS 좌표).
class MapFixCell {
  const MapFixCell({required this.x, required this.y, required this.added});

  final double x;
  final double y;

  /// true 면 새로 생긴 칸, false 면 없어진 칸.
  final bool added;
}

/// 토픽 /vica/map_fix/state — 부분 스캔 한 번의 진행.
class MapFixScanState {
  const MapFixScanState({
    required this.session,
    required this.mapId,
    required this.phase,
    this.reason = '',
    this.remainingS = 0,
    this.radiusM = 0,
    this.movedM = 0,
    this.movedDeg = 0,
    this.score = 0,
    this.scoreBefore = 0,
    this.scoreAfter = 0,
    this.added = 0,
    this.removed = 0,
    this.cells = const [],
    this.ambiguous = const [],
    this.centre,
  });

  final String session;
  final String mapId;

  /// 'refine' → 'step_back' → 'scanning' → 'preview', 또는 'failed' · 'done'.
  final String phase;
  final String reason;
  final int remainingS;
  final double radiusM;
  final double movedM;
  final double movedDeg;

  /// 자세를 다시 맞췄을 때의 위치 맞춤 %.
  final double score;
  final double scoreBefore;
  final double scoreAfter;
  final int added;
  final int removed;
  final List<MapFixCell> cells;
  final List<String> ambiguous;

  /// 반경 원의 중심 — 이 세션의 라이다 자리(ROS 좌표). 자세를 맞추기 전에는 null.
  final Offset? centre;

  factory MapFixScanState.fromJson(Map<String, Object?> json) {
    final cells = json['cells'];
    return MapFixScanState(
      session: jsonString(json['session']),
      mapId: jsonString(json['map_id']),
      phase: jsonString(json['phase']),
      reason: jsonString(json['reason']),
      remainingS: jsonInt(json['remaining_s']),
      radiusM: _number(json['radius_m']),
      movedM: _number(json['moved_m']),
      movedDeg: _number(json['moved_deg']),
      score: _number(json['score']),
      scoreBefore: _number(json['score_before']),
      scoreAfter: _number(json['score_after']),
      added: jsonInt(json['added']),
      removed: jsonInt(json['removed']),
      cells: cells is List
          ? cells
              .whereType<List>()
              .where((cell) => cell.length >= 3)
              .map(
                (cell) => MapFixCell(
                  x: _number(cell[0]),
                  y: _number(cell[1]),
                  added: _number(cell[2]) > 0,
                ),
              )
              .toList(growable: false)
          : const [],
      ambiguous: jsonStringList(json['ambiguous']),
      centre: _point(json['centre']),
    );
  }

  /// 자세 맞춤·물러나기·스캔 중인가(이 동안은 화면에서 뒤로 갈 수 없습니다).
  bool get running =>
      phase == 'refine' || phase == 'step_back' || phase == 'scanning';
  bool get isPreview => phase == 'preview';
  bool get isFailed => phase == 'failed';
}
