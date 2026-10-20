import 'dart:math' as math;
import 'dart:ui' show Offset;

const double kPoseScoreGood = 70.0;
const double kPoseScoreWeak = 50.0;

const double kPoseMarginSafe = 10.0;

enum PoseGrade {
  good,
  weak,
  bad,
}

class PoseCheckResult {
  const PoseCheckResult({
    required this.ok,
    required this.reason,
    required this.message,
    required this.score,
    required this.x,
    required this.y,
    required this.yaw,
    required this.usedBeams,
    required this.totalBeams,
    required this.margin,
    required this.movedM,
    required this.movedDeg,
    this.scanHits = const [],
  });

  final bool ok;
  final String reason;
  final String message;
  final double score;
  final double x;
  final double y;
  final double yaw;
  final int usedBeams;
  final int totalBeams;
  final double margin;
  final double movedM;
  final double movedDeg;

  /// 찾아낸 자세에서 본 라이다 점(ROS 좌표). 지도에 겹쳐 그립니다.
  final List<Offset> scanHits;

  factory PoseCheckResult.fromValues(Map<String, Object?> values) {
    double number(String key) => (values[key] as num?)?.toDouble() ?? 0;
    return PoseCheckResult(
      ok: values['ok'] == true,
      reason: values['reason'] as String? ?? '',
      message: values['message'] as String? ?? '',
      score: number('score'),
      x: number('x'),
      y: number('y'),
      yaw: number('yaw'),
      usedBeams: (values['used_beams'] as num?)?.toInt() ?? 0,
      totalBeams: (values['total_beams'] as num?)?.toInt() ?? 0,
      margin: number('margin'),
      movedM: number('moved_m'),
      movedDeg: number('moved_deg'),
      scanHits: hitsFrom(values),
    );
  }

  /// hit_x·hit_y 를 좌표 목록으로 묶습니다.
  static List<Offset> hitsFrom(Map<String, Object?> values) {
    final xs = values['hit_x'];
    final ys = values['hit_y'];
    if (xs is! List || ys is! List) {
      return const [];
    }
    final count = xs.length < ys.length ? xs.length : ys.length;
    return List<Offset>.generate(
      count,
      (i) => Offset(
        (xs[i] as num?)?.toDouble() ?? 0,
        (ys[i] as num?)?.toDouble() ?? 0,
      ),
      growable: false,
    );
  }

  PoseGrade get grade {
    if (score >= kPoseScoreGood) {
      return PoseGrade.good;
    }
    return score >= kPoseScoreWeak ? PoseGrade.weak : PoseGrade.bad;
  }

  double get yawDegrees => yaw * 180.0 / math.pi;

  /// 화면에 보여 줄 판정 문장입니다.
  String get displayMessage {
    final text = message
        .replaceFirst(
          '지도의 다른 자리 같습니다. 다시 짚어 보세요.',
          '다른 위치입니다.\n다시 선택해 주세요.',
        )
        .replaceFirst(
          '다른 위치입니다. 다시 선택해 주세요.',
          '다른 위치입니다.\n다시 선택해 주세요.',
        )
        .replaceFirst(
          RegExp(r'\s*고른 방향의 끝자락입니다\. 옆 방향으로도 확인해 보세요\.'),
          '',
        );
    return text.trim();
  }

  String get movedSummary {
    final centimetres = (movedM * 100).round();
    final degrees = movedDeg.abs().round();
    if (centimetres == 0 && degrees == 0) {
      return '짚은 자리 그대로입니다.';
    }
    if (degrees == 0) {
      return '$centimetres cm 옮겼습니다.';
    }
    return '$centimetres cm, $degrees° 옮겼습니다.';
  }

  String get marginSummary {
    final points = margin.floor();
    return margin >= kPoseMarginSafe
        ? '헷갈릴 방향 없음(차이 $points점)'
        : '헷갈릴 방향 있음(차이 $points점)';
  }
}
