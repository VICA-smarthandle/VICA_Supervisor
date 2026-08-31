// 이 파일은 Nav2 초기 위치 후보를 채점한 결과를 표현합니다.
//
// 점수를 매기는 쪽은 젯슨의 pose_bootstrap_node 입니다. 앱은 계산하지 않습니다.
// /scan 은 10 Hz x 721 점이라 rosbridge 로 끌고 오면 낭비고, 더 큰 문제는 앱에
// 지도 PNG 그림만 있고 원본 격자값이 없다는 것입니다. 그림에서 회색 픽셀을 세는
// 것은 정확한 계산이 아닙니다. 앱은 숫자 셋을 보내고 % 하나를 받습니다.
import 'dart:math' as math;
import 'dart:ui' show Offset;

// 색과 버튼 잠금에 쓰는 경계입니다. **판정의 주인은 노드입니다** — 확정 가능
// 여부는 노드가 보낸 ok 를 그대로 씁니다. 여기 값은 화면 색을 고르는 용도라
// 노드의 min_score 파라미터와 어긋나도 안전이 깨지지 않습니다.
const double kPoseScoreGood = 70.0;
const double kPoseScoreWeak = 50.0;

// '헷갈릴 방향' 문구를 가르는 경계입니다. 노드의 min_margin 과 같은 값이지만
// 여기서도 판정하지는 않습니다 — 문구 선택 용도뿐입니다.
const double kPoseMarginSafe = 10.0;

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
  final double runnerUpScore;
  final double margin;
  final double movedM;
  final double movedDeg;

  /// 찾아낸 자세에서 본 라이다 점(ROS 좌표). 지도에 겹쳐 그립니다.
  ///
  /// **확인한 그 순간의 스캔 한 장입니다.** 실시간 구독이 아니며, 서버가
  /// 채점하면서 이미 만든 좌표를 그대로 받습니다. 점이 벽 위에 놓이면 자세가
  /// 맞은 것이고 밀려 있으면 틀린 것입니다 — RViz 가 초기 위치를 잡은 뒤
  /// 보여주는 그림과 같습니다.
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
      runnerUpScore: number('runner_up_score'),
      margin: number('margin'),
      movedM: number('moved_m'),
      movedDeg: number('moved_deg'),
      scanHits: hitsFrom(values),
    );
  }

  /// hit_x·hit_y 를 좌표 목록으로 묶습니다.
  ///
  /// PoseCommit 응답도 같은 필드 이름을 쓰므로 provider 가 직접 부릅니다.
  ///
  /// 길이가 다르면 짧은 쪽에 맞춥니다 — 한쪽만 잘려 온 응답으로 화면이
  /// 예외를 내는 것보다 덜 그리는 편이 낫습니다.
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

  // margin 은 "두 번째로 잘 맞는 방향 후보와의 점수 차"입니다. 이 숫자가 지키는
  // 것은 180도 뒤집힘입니다 — 앞뒤가 같은 복도에서 차이가 작으면 반대 방향일 수
  // 있습니다. '2등 차이 24 %p' 는 관리자가 못 알아듣는 말이라 뜻으로 풀어 씁니다.
  String get marginSummary {
    // 내림으로 맞춥니다. 반올림이면 9.9 가 "차이 10점인데 있음"으로 보입니다.
    final points = margin.floor();
    return margin >= kPoseMarginSafe
        ? '헷갈릴 방향 없음(차이 $points점)'
        : '헷갈릴 방향 있음(차이 $points점)';
  }
}
