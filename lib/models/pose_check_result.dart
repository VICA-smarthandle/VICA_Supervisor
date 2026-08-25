// 이 파일은 Nav2 초기 위치 후보를 채점한 결과를 표현합니다.
//
// 점수를 매기는 쪽은 젯슨의 pose_bootstrap_node 입니다. 앱은 계산하지 않습니다.
// /scan 은 10 Hz x 721 점이라 rosbridge 로 끌고 오면 낭비고, 더 큰 문제는 앱에
// 지도 PNG 그림만 있고 원본 격자값이 없다는 것입니다. 그림에서 회색 픽셀을 세는
// 것은 정확한 계산이 아닙니다. 앱은 숫자 셋을 보내고 % 하나를 받습니다.
import 'dart:math' as math;

// 색과 버튼 잠금에 쓰는 경계입니다. **판정의 주인은 노드입니다** — 확정 가능
// 여부는 노드가 보낸 ok 를 그대로 씁니다. 여기 값은 화면 색을 고르는 용도라
// 노드의 min_score 파라미터와 어긋나도 안전이 깨지지 않습니다.
const double kPoseScoreGood = 70.0;
const double kPoseScoreWeak = 50.0;

enum PoseGrade {
  good, // 잘 맞습니다
  weak, // 확실하지 않습니다
  bad, // 다시 짚어야 합니다
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
    required this.runnerUpScore,
    required this.margin,
    required this.movedM,
    required this.movedDeg,
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
  final double runnerUpScore;
  final double margin;
  final double movedM;
  final double movedDeg;

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
      runnerUpScore: number('runner_up_score'),
      margin: number('margin'),
      movedM: number('moved_m'),
      movedDeg: number('moved_deg'),
    );
  }

  PoseGrade get grade {
    if (score >= kPoseScoreGood) {
      return PoseGrade.good;
    }
    return score >= kPoseScoreWeak ? PoseGrade.weak : PoseGrade.bad;
  }

  double get yawDegrees => yaw * 180.0 / math.pi;

  // 사람이 짚은 자리에서 얼마나 옮겼는지를 한 줄로 보여줍니다.
  //
  // 이 표시가 은근히 중요합니다. 화살표만 툭 나오면 "왜 딴 데 갔지?" 하지만,
  // 짚은 점과 옮겨진 화살표가 둘 다 보이면 결과를 납득하게 됩니다.
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
}
