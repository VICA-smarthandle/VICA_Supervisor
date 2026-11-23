import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/models/map_fix.dart';

void main() {
  test('result_json 이 깨져도 죽지 않는다', () {
    final result = MapFixResult.fromValues({
      'accepted': true,
      'reason': '',
      'message': '',
      'result_json': '{"black": 3',
    });
    expect(result.accepted, isTrue);
    expect(result.result, isEmpty);
    expect(result.applied, isFalse);
  });

  test('applied·mission_stale 을 읽는다', () {
    final result = MapFixResult.fromValues({
      'accepted': true,
      'reason': '',
      'message': '지도를 수정했습니다.',
      'result_json':
          '{"black": 19, "gray": 3, "applied": true, "mission_stale": true}',
    });
    expect(result.applied, isTrue);
    expect(result.missionStale, isTrue);
    expect(result.result['black'], 19);
  });

  test('연결 없음 응답은 offline 이다', () {
    final result = MapFixResult.offline('ROS Bridge에 연결되지 않았습니다.');
    expect(result.accepted, isFalse);
    expect(result.reason, 'offline');
    expect(result.applied, isFalse);
  });

  test('사각형은 어느 쪽으로 끌어도 min·max 가 정리된다', () {
    final rect = MapFixRect.fromCorners(
      const Offset(2.0, 1.0),
      const Offset(0.5, 3.0),
    );
    expect(rect.toJson(), {
      'x_min': 0.5,
      'y_min': 1.0,
      'x_max': 2.0,
      'y_max': 3.0,
    });
    expect(rect.width, 1.5);
    expect(rect.height, 2.0);
  });

  test('get 결과에서 잠금·기록을 읽는다', () {
    final status = MapFixStatus.fromResult({
      'lock': '',
      'can_scan': true,
      'history': [
        {
          'at': '2026-11-18T15:42:07',
          'kind': 'scan',
          'radius_m': 2.0,
          'added': 41,
          'removed': 28,
        },
        {
          'at': '2026-11-18T15:31:00',
          'kind': 'erase',
          'black': 19,
          'gray': 3,
          'rects': [
            {'x_min': 0, 'y_min': 0, 'x_max': 1, 'y_max': 1},
            {'x_min': 2, 'y_min': 0, 'x_max': 3, 'y_max': 1},
            {'x_min': 4, 'y_min': 0, 'x_max': 5, 'y_max': 1},
          ],
        },
      ],
    });
    expect(status.locked, isFalse);
    expect(status.canScan, isTrue);
    expect(status.history, hasLength(2));
    expect(status.history[0].title, '부분 스캔 · 2 m');
    expect(status.history[0].detail, '11-18 15:42 · 새로 41칸 · 없어짐 28칸');
    expect(status.history[1].title, '지우기 · 3곳');
    expect(status.history[1].detail, '11-18 15:31 · 검은 칸 19개 · 회색 칸 3개');
  });

  test('기록 시각은 로봇이 적은 시각 그대로다(시간대가 붙어 와도)', () {
    const entry = MapFixHistoryEntry(
      at: '2026-11-19T15:37:14+09:00',
      kind: 'erase',
      black: 3,
      gray: 0,
      rectCount: 1,
    );
    expect(entry.when, '11-19 15:37');
    expect(entry.detail, '11-19 15:37 · 검은 칸 3개 · 회색 칸 0개');
    expect(
      const MapFixHistoryEntry(at: 'nonsense', kind: 'scan').when,
      'nonsense',
    );
  });

  test('잠기지 않았는데 부분 스캔만 안 되면 주행 지도가 아니다', () {
    expect(
      MapFixStatus.fromResult({'lock': '', 'can_scan': false}).isDriveMap,
      isFalse,
    );
    expect(
      MapFixStatus.fromResult({'lock': '', 'can_scan': true}).isDriveMap,
      isTrue,
    );
    expect(
      MapFixStatus.fromResult({
        'lock': 'busy_driving',
        'can_scan': false,
      }).isDriveMap,
      isTrue,
    );
  });

  test('erase_count 결과에서 사각형별 칸 수와 합계를 읽는다', () {
    final count = MapFixEraseCount.fromResult({
      'rects': [
        {'w_m': 1.1, 'h_m': 1.1, 'black': 14, 'gray': 1},
        {'w_m': 0.7, 'h_m': 0.7, 'black': 0, 'gray': 2},
      ],
      'black': 14,
      'gray': 3,
    });
    expect(count.rects, hasLength(2));
    expect(count.rects[0].wM, 1.1);
    expect(count.rects[1].gray, 2);
    expect(count.black, 14);
    expect(count.gray, 3);
  });

  test('scan_check 결과에서 위치 맞춤과 라이다 점을 읽는다', () {
    final check = MapFixScanCheck.fromResult({
      'ok': true,
      'reason': '',
      'score': 84.2,
      'ambiguous': <Object?>[],
      'hits': [
        [1.0, 2.0],
        [3.5, -1.25],
        [9.0],
      ],
    });
    expect(check.ok, isTrue);
    expect(mapFixPercent(check.score), '84 %');
    expect(check.hits, const [Offset(1.0, 2.0), Offset(3.5, -1.25)]);
  });

  test('scan state 의 cells 를 [[x,y,1|-1]] 에서 읽는다', () {
    final state = MapFixScanState.fromJson({
      'session': 's1',
      'map_id': 'vica_map_0630',
      'phase': 'preview',
      'reason': '',
      'remaining_s': 0,
      'radius_m': 2.0,
      'moved_m': 0.03,
      'moved_deg': 0.4,
      'score': 88.0,
      'score_before': 62.0,
      'score_after': 91.0,
      'added': 2,
      'removed': 1,
      'cells': [
        [1.025, 2.075, 1],
        [1.075, 2.075, 1],
        [0.525, 1.025, -1],
      ],
      'ambiguous': ['forward'],
    });
    expect(state.isPreview, isTrue);
    expect(state.running, isFalse);
    expect(state.cells, hasLength(3));
    expect(state.cells[0].added, isTrue);
    expect(state.cells[2].added, isFalse);
    expect(state.cells[2].x, 0.525);
    expect(state.ambiguous, ['forward']);
    expect(mapFixPercent(state.scoreBefore), '62 %');
    expect(mapFixPercent(state.scoreAfter), '91 %');
  });

  test('반경 원의 중심(라이다 자리)을 읽는다 — 없으면 null', () {
    expect(
      MapFixScanState.fromJson({
        'phase': 'step_back',
        'centre': [1.185, 2.0],
      }).centre,
      const Offset(1.185, 2.0),
    );
    expect(MapFixScanState.fromJson({'phase': 'refine', 'centre': []}).centre,
        isNull);
    expect(
      MapFixScanCheck.fromResult({
        'ok': true,
        'score': 80.0,
        'centre': [3.0, -1.5],
      }).centre,
      const Offset(3.0, -1.5),
    );
    expect(MapFixScanCheck.fromResult({'ok': false}).centre, isNull);
  });

  test('refine·step_back·scanning 은 진행 중이다', () {
    for (final phase in ['refine', 'step_back', 'scanning']) {
      expect(
        MapFixScanState.fromJson({'phase': phase}).running,
        isTrue,
        reason: phase,
      );
    }
    expect(MapFixScanState.fromJson({'phase': 'failed'}).isFailed, isTrue);
    expect(MapFixScanState.fromJson({'phase': 'done'}).running, isFalse);
  });

  test('반경은 2 m · 1.5 m 로 적는다', () {
    expect(mapFixMetres(2.0), '2 m');
    expect(mapFixMetres(1.5), '1.5 m');
  });
}
