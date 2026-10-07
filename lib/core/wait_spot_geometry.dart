// 이 파일은 대기 장소를 찍을 때 앱이 하는 계산을 모읍니다(2026-10-07). 화면이 없는
// 순수 함수라 시험으로 바로 확인합니다.
//
//   1. 입구 기준 방향 — "입구 오른쪽 / 왼쪽 / 맞은편". 로봇은 이 글자를 다시 계산하지
//      않고 멘트에 그대로 씁니다("10분 동안 입구 오른쪽에서 기다리겠습니다").
//   2. 몸 옆면과 벽 사이 간격 — 대기 장소는 회전 여유를 요구하지 않는 대신(나가는
//      쪽을 보고 서서 바로 전진 출발), 몸이 벽에 너무 붙으면 경로 계획기가 그 자리를
//      벽 속으로 봐서 들어가지도 나오지도 못합니다.
//   3. 옮긴 거리 문장 — "원래 자리에서 오른쪽으로 0.25 m".
import 'dart:math' as math;

import '../services/map_wall_mask.dart';

// ---- 차체(footprint) ---------------------------------------------------------
//
// vica_nav2/config/nav2_params.yaml 의 footprint 와 같은 값입니다. base_link 가 구동륜
// 축이라(2026-09-15 이동) 앞은 짧고 몸통은 뒤로 깁니다.
//   [[0.151, 0.225], [0.151, -0.225], [-0.459, -0.225], [-0.569, -0.035], …]

/// 기준점에서 앞면까지(m).
const double kBodyFrontM = 0.151;

/// 기준점에서 꼬리 끝까지(m).
const double kBodyRearM = 0.569;

/// 몸 반폭(m).
const double kBodyHalfWidthM = 0.225;

/// 꼬리가 좁아지기 시작하는 자리(m, 뒤쪽). 그림에만 씁니다.
const double kBodyTaperStartM = 0.459;

/// 꼬리 끝의 반폭(m). 그림에만 씁니다.
const double kBodyTailHalfWidthM = 0.035;

/// 차체 윤곽(로봇 기준, 앞=+x, 왼쪽=+y). 지도에 그릴 때 씁니다.
const List<(double, double)> kBodyOutline = [
  (kBodyFrontM, kBodyHalfWidthM),
  (kBodyFrontM, -kBodyHalfWidthM),
  (-kBodyTaperStartM, -kBodyHalfWidthM),
  (-kBodyRearM, -kBodyTailHalfWidthM),
  (-kBodyRearM, kBodyTailHalfWidthM),
  (-kBodyTaperStartM, kBodyHalfWidthM),
];

// ---- 벽 간격 기준(목업 4번, 2026-10-07 확정) ------------------------------------
//
// 옆 간격 7 cm = 기준점에서 벽까지 0.30 m. 경로 계획기가 로봇을 벽 속으로 보는 반경
// (inscribed 0.227 + padding)보다 조금 큽니다. 22 cm = 0.45 m(inflation 이 깎아 내는
// 구간)까지는 들어가도 멈칫할 수 있어 '주의'입니다.

/// 이보다 가까우면 저장할 수 없다(m, 몸 옆면에서).
const double kGapBlockM = 0.07;

/// 이보다 가까우면 주의(m, 몸 옆면에서).
const double kGapCautionM = 0.22;

/// 앞면 앞으로 이 안에 벽이 있으면 저장할 수 없다(m). 나가자마자 벽입니다.
const double kFrontBlockM = 0.30;

/// 앞면 앞으로 이 안에 벽이 있으면 주의(m). 충돌 감시 감속 영역(바퀴 축 기준
/// 0.946 m)에 걸려 출발이 느려집니다. 인수인계 문서 '앱 판정 기준' 표.
const double kFrontCautionM = 0.80;

/// 이 거리까지만 잽니다(m). 넘으면 '4 m 이상'.
const double kGapScanMaxM = 4.0;

/// 입구 기준 옆 거리 문턱(m). 입구 화살표를 바라볼 때 옆으로 이만큼 이상이면
/// 오른쪽·왼쪽, 미만이면 맞은편이고, 그 띠 안에서 입구 쪽(앞)이면 입구 안쪽이라
/// 저장을 막습니다 — 사람이 드나드는 길이라 대기 장소를 따로 두는 이유(진입로
/// 막지 않기)가 사라집니다. 인수인계 문서 '앱 판정 기준' 표의 기준입니다.
const double kDoorwayHalfWidthM = 0.5;

enum GapLevel { good, caution, blocked }

GapLevel sideGapLevel(double gapM) {
  if (gapM < kGapBlockM) {
    return GapLevel.blocked;
  }
  if (gapM < kGapCautionM) {
    return GapLevel.caution;
  }
  return GapLevel.good;
}

GapLevel frontGapLevel(double gapM) {
  if (gapM < kFrontBlockM) {
    return GapLevel.blocked;
  }
  if (gapM < kFrontCautionM) {
    return GapLevel.caution;
  }
  return GapLevel.good;
}

/// 몸 옆면·앞면과 벽 사이 간격(m). [kGapScanMaxM] 까지만 잽니다.
class WaitSpotGaps {
  const WaitSpotGaps({
    required this.left,
    required this.right,
    required this.front,
  });

  final double left;
  final double right;
  final double front;

  GapLevel get leftLevel => sideGapLevel(left);
  GapLevel get rightLevel => sideGapLevel(right);
  GapLevel get frontLevel => frontGapLevel(front);

  /// 셋 중 가장 나쁜 판정. 빨강이 하나라도 있으면 저장 버튼이 잠깁니다.
  GapLevel get worst {
    final levels = [leftLevel, rightLevel, frontLevel];
    if (levels.contains(GapLevel.blocked)) {
      return GapLevel.blocked;
    }
    if (levels.contains(GapLevel.caution)) {
      return GapLevel.caution;
    }
    return GapLevel.good;
  }

  /// 가장 가까운 옆 벽 — 목록의 '가장 가까운 벽' 줄.
  (String, double, GapLevel) get nearestSide =>
      left <= right ? ('왼쪽', left, leftLevel) : ('오른쪽', right, rightLevel);
}

/// 대기 장소 자세(x, y, 나가는 방향)에서 몸 옆면·앞면과 벽 사이 간격을 잽니다.
///
/// 지도 그림의 검은 칸만 벽입니다(레일 벽 검사와 같은 [MapWallMask]). 몸 안에 벽
/// 칸이 있으면 셋 다 0 입니다.
WaitSpotGaps measureWaitSpotGaps(
  MapWallMask mask,
  double x,
  double y,
  double yawDeg,
) {
  final yaw = yawDeg * math.pi / 180.0;
  final c = math.cos(yaw);
  final s = math.sin(yaw);
  final step = mask.resolution > 0 ? mask.resolution : 0.05;

  // 로봇 기준 (fx 앞, fy 왼쪽) → 지도 좌표.
  bool wallAt(double fx, double fy) =>
      mask.isWallAt(x + fx * c - fy * s, y + fx * s + fy * c);

  // 몸 안(꼬리 좁아짐은 무시 — 보수적)에 벽이 있으면 모두 막음. 반 칸 간격으로
  // 훑습니다 — 한 칸 간격이면 점이 칸 경계에 걸려 한 칸 두께 벽을 건너뛸 수 있습니다.
  final fine = step / 2;
  for (var fx = -kBodyRearM; fx <= kBodyFrontM + 1e-9; fx += fine) {
    for (var fy = -kBodyHalfWidthM; fy <= kBodyHalfWidthM + 1e-9; fy += fine) {
      if (wallAt(fx, fy)) {
        return const WaitSpotGaps(left: 0, right: 0, front: 0);
      }
    }
  }

  double scan(double fx0, double fy0, double dfx, double dfy) {
    // 반 칸 간격으로 나갑니다(몸 안 검사와 같은 이유). 처음 벽에 닿은 점은 벽 칸
    // 가장자리를 넘어선 지 반 걸음 안쪽이라, 반 걸음을 빼 가장자리로 봅니다.
    for (var d = fine; d <= kGapScanMaxM + 1e-9; d += fine) {
      if (wallAt(fx0 + dfx * d, fy0 + dfy * d)) {
        return math.max(0, d - fine / 2);
      }
    }
    return kGapScanMaxM;
  }

  var left = kGapScanMaxM;
  var right = kGapScanMaxM;
  for (var fx = -kBodyRearM; fx <= kBodyFrontM + 1e-9; fx += step) {
    left = math.min(left, scan(fx, kBodyHalfWidthM, 0, 1));
    right = math.min(right, scan(fx, -kBodyHalfWidthM, 0, -1));
  }
  var front = kGapScanMaxM;
  for (var fy = -kBodyHalfWidthM; fy <= kBodyHalfWidthM + 1e-9; fy += step) {
    front = math.min(front, scan(kBodyFrontM, fy, 1, 0));
  }
  return WaitSpotGaps(left: left, right: right, front: front);
}

/// 간격을 화면 글자로. 1 m 아래는 cm, 그 위는 m, 끝까지 비었으면 '4 m 이상'.
String formatGap(double meters) {
  if (meters >= kGapScanMaxM) {
    return '${kGapScanMaxM.toStringAsFixed(0)} m 이상';
  }
  if (meters < 1.0) {
    return '${(meters * 100).round()} cm';
  }
  return '${meters.toStringAsFixed(1)} m';
}

/// 간격 판정 글자. 목업 4·4′ 번과 같습니다.
String gapLevelText(GapLevel level) {
  switch (level) {
    case GapLevel.good:
      return '좋음';
    case GapLevel.caution:
      return '주의 · 벽과 가까움';
    case GapLevel.blocked:
      return '출발할 수 없음';
  }
}

// ---- 입구 기준 방향 ---------------------------------------------------------

/// 대기 장소가 입구 기준 어디인가.
///
/// [side] 는 `right`·`left`·`across` 중 하나이고, 입구 바로 앞(사람이 드나드는 띠)
/// 이면 null 입니다 — 그 자리는 저장할 수 없습니다.
class WaitSpotPlacement {
  const WaitSpotPlacement({required this.side, required this.distance});

  final String? side;

  /// 목적지 점에서 대기 장소까지(m).
  final double distance;

  bool get inDoorway => side == null;
}

/// 입구를 바라볼 때(목적지 점에서 [doorYawDeg] 쪽을 볼 때) 대기 장소의 쪽.
///
/// 오른쪽·왼쪽은 그 사람의 오른손·왼손 쪽입니다. 옆으로 [kDoorwayHalfWidthM] 이상
/// 떨어지면 오른쪽·왼쪽, 그보다 가까우면 등 뒤(맞은편)이고, 가까운데 입구 쪽(목적지
/// 점 포함)이면 입구 안쪽이라 null 입니다.
WaitSpotPlacement waitSpotPlacement({
  required double destX,
  required double destY,
  required double doorYawDeg,
  required double spotX,
  required double spotY,
}) {
  final yaw = doorYawDeg * math.pi / 180.0;
  final rx = spotX - destX;
  final ry = spotY - destY;
  final forward = rx * math.cos(yaw) + ry * math.sin(yaw);
  final leftward = -rx * math.sin(yaw) + ry * math.cos(yaw);
  final distance = math.sqrt(rx * rx + ry * ry);
  if (leftward.abs() < kDoorwayHalfWidthM) {
    return WaitSpotPlacement(
      side: forward < 0 ? 'across' : null,
      distance: distance,
    );
  }
  return WaitSpotPlacement(
    side: leftward > 0 ? 'left' : 'right',
    distance: distance,
  );
}

// ---- 화면 방향 말 ------------------------------------------------------------

/// 지도 좌표의 이동(dx, dy)을 화면 기준 말로. [upIsPlusY] 는 설정 '지도 Y축 반전'
/// (켜짐이면 화면 위 = +y). 한쪽이 다른 쪽의 0.4배를 넘으면 둘을 함께 씁니다
/// ("오른쪽 위").
String screenDirectionWord(double dx, double dy, {required bool upIsPlusY}) {
  final up = upIsPlusY ? dy : -dy;
  final horizontal = dx > 0 ? '오른쪽' : '왼쪽';
  final vertical = up > 0 ? '위' : '아래';
  final ax = dx.abs();
  final ay = up.abs();
  if (ax >= ay) {
    return ay > ax * 0.4 ? '$horizontal $vertical' : horizontal;
  }
  return ax > ay * 0.4 ? '$horizontal $vertical' : vertical;
}

/// "원래 자리에서 오른쪽으로 0.25 m". 1 cm 아래면 "원래 자리 그대로".
String movedFromOriginalText(
  double fromX,
  double fromY,
  double toX,
  double toY, {
  required bool upIsPlusY,
}) {
  final dx = toX - fromX;
  final dy = toY - fromY;
  final distance = math.sqrt(dx * dx + dy * dy);
  if (distance < 0.01) {
    return '원래 자리 그대로';
  }
  final word = screenDirectionWord(dx, dy, upIsPlusY: upIsPlusY);
  // '오른쪽·왼쪽'은 받침이 있어 '으로', '위·아래'는 '로'.
  final josa = word.endsWith('쪽') ? '으로' : '로';
  return '원래 자리에서 $word$josa ${distance.toStringAsFixed(2)} m';
}
