// 초기 위치 채점 결과를 앱이 어떻게 읽는지 고정합니다.
//
// 판정의 주인은 젯슨의 pose_bootstrap_node 입니다. 앱은 계산하지 않고 노드가
// 보낸 ok 를 그대로 씁니다. 여기서 보는 것은 "읽다가 틀리지 않는가"입니다.
import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/models/pose_check_result.dart';

void main() {
  Map<String, Object?> values({
    bool ok = true,
    double score = 82,
    double movedM = 0.12,
    double movedDeg = 8,
  }) =>
      {
        'ok': ok,
        'reason': '',
        'message': '이 위치로 확정할 수 있습니다.',
        'score': score,
        'x': 1.5,
        'y': -2.25,
        'yaw': 1.5707963,
        'used_beams': 168,
        'total_beams': 721,
        'runner_up_score': 58.0,
        'margin': 24.0,
        'moved_m': movedM,
        'moved_deg': movedDeg,
      };

  test('서비스 응답의 모든 칸을 읽는다', () {
    final result = PoseCheckResult.fromValues(values());
    expect(result.ok, isTrue);
    expect(result.score, 82);
    expect(result.usedBeams, 168);
    expect(result.totalBeams, 721);
    expect(result.margin, 24);
    expect(result.yawDegrees, closeTo(90, 0.01));
  });

  test('빠진 칸은 0 으로 읽어 죽지 않는다', () {
    // 노드가 실패로 답할 때는 숫자 칸이 기본값으로 옵니다.
    final result = PoseCheckResult.fromValues({
      'ok': false,
      'reason': 'no_map',
      'message': '지도가 없습니다.',
    });
    expect(result.ok, isFalse);
    expect(result.score, 0);
    expect(result.usedBeams, 0);
    expect(result.grade, PoseGrade.bad);
  });

  test('점수 구간이 색을 가른다', () {
    expect(PoseCheckResult.fromValues(values(score: 70)).grade, PoseGrade.good);
    expect(PoseCheckResult.fromValues(values(score: 69.9)).grade, PoseGrade.weak);
    expect(PoseCheckResult.fromValues(values(score: 50)).grade, PoseGrade.weak);
    expect(PoseCheckResult.fromValues(values(score: 49.9)).grade, PoseGrade.bad);
  });

  test('얼마나 옮겼는지를 사람 말로 만든다', () {
    expect(
      PoseCheckResult.fromValues(values(movedM: 0.12, movedDeg: 8)).movedSummary,
      '12 cm, 8° 옮겼습니다.',
    );
    expect(
      PoseCheckResult.fromValues(values(movedM: 0.07, movedDeg: 0)).movedSummary,
      '7 cm 옮겼습니다.',
    );
    expect(
      PoseCheckResult.fromValues(values(movedM: 0.001, movedDeg: 0.2))
          .movedSummary,
      '짚은 자리 그대로입니다.',
    );
  });

  test('음수 각도도 절댓값으로 보여준다', () {
    expect(
      PoseCheckResult.fromValues(values(movedM: 0.2, movedDeg: -12))
          .movedSummary,
      '20 cm, 12° 옮겼습니다.',
    );
  });
}
