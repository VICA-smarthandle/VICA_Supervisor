import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/models/pose_check_result.dart';

void main() {
  _scanHitTests();
  Map<String, Object?> values({
    bool ok = true,
    double score = 82,
    double movedM = 0.12,
    double movedDeg = 8,
    double margin = 24.0,
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
        'margin': margin,
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
    expect(
        PoseCheckResult.fromValues(values(score: 69.9)).grade, PoseGrade.weak);
    expect(PoseCheckResult.fromValues(values(score: 50)).grade, PoseGrade.weak);
    expect(
        PoseCheckResult.fromValues(values(score: 49.9)).grade, PoseGrade.bad);
  });

  test('얼마나 옮겼는지를 사람 말로 만든다', () {
    expect(
      PoseCheckResult.fromValues(values(movedM: 0.12, movedDeg: 8))
          .movedSummary,
      '12 cm, 8° 옮겼습니다.',
    );
    expect(
      PoseCheckResult.fromValues(values(movedM: 0.07, movedDeg: 0))
          .movedSummary,
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

  test('2등 격차를 사람 말로 만든다', () {
    expect(
      PoseCheckResult.fromValues(values(margin: 24)).marginSummary,
      '헷갈릴 방향 없음(차이 24점)',
    );
    expect(
      PoseCheckResult.fromValues(values(margin: 9.9)).marginSummary,
      '헷갈릴 방향 있음(차이 9점)',
    );
    expect(
      PoseCheckResult.fromValues(values(margin: 10)).marginSummary,
      '헷갈릴 방향 없음(차이 10점)',
    );
  });
}

void _scanHitTests() {
  group('라이다 점', () {
    test('hit_x·hit_y 를 좌표로 묶는다', () {
      final result = PoseCheckResult.fromValues(const {
        'hit_x': [1.0, 2.0, 3.0],
        'hit_y': [4.0, 5.0, 6.0],
      });

      expect(result.scanHits.length, 3);
      expect(result.scanHits.first.dx, 1.0);
      expect(result.scanHits.first.dy, 4.0);
    });

    test('점이 없으면 빈 목록이다', () {
      expect(PoseCheckResult.fromValues(const {}).scanHits, isEmpty);
    });

    test('한쪽만 잘려 와도 예외를 던지지 않는다', () {
      final result = PoseCheckResult.fromValues(const {
        'hit_x': [1.0, 2.0, 3.0],
        'hit_y': [4.0],
      });

      expect(result.scanHits.length, 1);
    });

    test('배열이 아닌 값이 와도 버티다', () {
      final result = PoseCheckResult.fromValues(const {
        'hit_x': 'not a list',
        'hit_y': 5,
      });

      expect(result.scanHits, isEmpty);
    });

    test('확정 응답도 같은 파서로 읽는다', () {
      final hits = PoseCheckResult.hitsFrom(const {
        'hit_x': [7.0],
        'hit_y': [8.0],
      });

      expect(hits.single.dx, 7.0);
      expect(hits.single.dy, 8.0);
    });
  });
}
