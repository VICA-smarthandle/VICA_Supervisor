// 지도 서버의 경비 기록 주소와 응답 읽기(2026-11-14, 명세 4.E).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/models/patrol.dart';
import 'package:vica_supervisor/services/patrol_log_loader.dart';

void main() {
  const base = 'http://10.0.0.5:8000';

  test('주소는 명세의 /patrol/ 경로다', () {
    expect(PatrolLogLoader.eventsUri(base).toString(),
        'http://10.0.0.5:8000/patrol/events.json');
    expect(PatrolLogLoader.clipUri(base, '20261114_203455_intruder').toString(),
        'http://10.0.0.5:8000/patrol/clips/20261114_203455_intruder.mp4');
    expect(PatrolLogLoader.posterUri(base, 'c1').toString(),
        'http://10.0.0.5:8000/patrol/clips/c1.jpg');
    expect(PatrolLogLoader.framesUri(base, 'c1').toString(),
        'http://10.0.0.5:8000/patrol/clips/c1/frames.json');
    expect(PatrolLogLoader.frameUri(base, 'c1', '000001.jpg').toString(),
        'http://10.0.0.5:8000/patrol/clips/c1/frames/000001.jpg');
    expect(PatrolLogLoader.photoUri(base, '20261114_005207.jpg').toString(),
        'http://10.0.0.5:8000/patrol/photos/20261114_005207.jpg');
  });

  test('주소 끝의 / 는 겹치지 않는다', () {
    expect(PatrolLogLoader.eventsUri('$base/').toString(),
        'http://10.0.0.5:8000/patrol/events.json');
  });

  test('기록 목록을 읽고 모르는 줄은 건너뛴다', () async {
    Uri? asked;
    final loader = PatrolLogLoader(fetch: (uri) async {
      asked = uri;
      return jsonEncode([
        {
          'alarm_id': '20261114_203455_intruder',
          'kind': 'intruder',
          'time': '2026-11-14T20:34:55',
          'place': '화장실',
          'clip_id': '20261114_203455_intruder',
          'clip_state': 'ready',
          'clip_sec': 42.0,
        },
        {'alarm_id': 'x', 'kind': 'unknown_kind'},
        '글자',
        {
          'alarm_id': '20261114_005207_light',
          'kind': 'light',
          'place': '407호',
          'photo': '20261114_005207.jpg',
        },
      ]);
    });
    final records = await loader.loadRecords(base);
    expect(asked, PatrolLogLoader.eventsUri(base));
    expect(records!.map((r) => r.kind),
        [PatrolAlarmKind.intruder, PatrolAlarmKind.light]);
    expect(records.first.clipLength, '0:42');
  });

  test('빈 배열은 기록 없음, 못 받으면 null', () async {
    expect(await PatrolLogLoader(fetch: (_) async => '[]').loadRecords(base),
        isEmpty);
    expect(await PatrolLogLoader(fetch: (_) async => null).loadRecords(base),
        isNull);
    expect(await PatrolLogLoader(fetch: (_) async => '{깨짐').loadRecords(base),
        isNull);
    expect(
      await PatrolLogLoader(fetch: (_) async => throw StateError('끊김'))
          .loadRecords(base),
      isNull,
    );
    // 배열이 아닌 응답도 못 받은 것으로 본다.
    expect(await PatrolLogLoader(fetch: (_) async => '{}').loadRecords(base),
        isNull);
  });

  test('사진 목록은 장마다의 주소가 된다', () async {
    final loader = PatrolLogLoader(
      fetch: (uri) async => jsonEncode({
        'id': 'c1',
        'fps': 5,
        'count': 2,
        'frames': ['000001.jpg', '000002.jpg'],
      }),
    );
    final set = await loader.loadFrames(base, 'c1');
    expect(set!.frames.map((u) => u.toString()), [
      'http://10.0.0.5:8000/patrol/clips/c1/frames/000001.jpg',
      'http://10.0.0.5:8000/patrol/clips/c1/frames/000002.jpg',
    ]);
    expect(set.fps, 5.0);
  });

  test('사진 넘길 속도는 서버가 알려 준 초당 장수다(소수 가능)', () async {
    Future<double> fpsOf(Object? fps) async {
      final loader = PatrolLogLoader(
        fetch: (_) async => jsonEncode({
          'id': 'c1',
          if (fps != null) 'fps': fps,
          'frames': ['000001.jpg'],
        }),
      );
      return (await loader.loadFrames(base, 'c1'))!.fps;
    }

    // 감지 노드가 실제로 잰 값.
    expect(await fpsOf(3.41), 3.41);
    expect(await fpsOf(10), 10.0);
    // 없거나 이상한 값이면 5.
    expect(await fpsOf(null), 5.0);
    expect(await fpsOf(0), 5.0);
    expect(await fpsOf(-2), 5.0);
    expect(await fpsOf(120), 5.0);
    expect(await fpsOf('빠르게'), 5.0);
    expect(await fpsOf(true), 5.0);
  });

  test('사진 목록이 없으면 null', () async {
    expect(
        await PatrolLogLoader(fetch: (_) async => null).loadFrames(base, 'c'),
        isNull);
    expect(
      await PatrolLogLoader(fetch: (_) async => '{"frames": []}')
          .loadFrames(base, 'c'),
      isNull,
    );
  });

  test('mp4 가 로봇에 있는지 HEAD 상태로 가른다(2026-11-17)', () async {
    Future<bool?> ask(Future<int?> Function(Uri) probe) =>
        PatrolLogLoader(fetch: (_) async => null, probe: probe)
            .clipExists('http://r:8000', 'c');
    final asked = <Uri>[];
    expect(await ask((uri) async { asked.add(uri); return 200; }), isTrue);
    expect(asked.single.toString(), 'http://r:8000/patrol/clips/c.mp4');
    expect(await ask((_) async => 206), isTrue);
    expect(await ask((_) async => 404), isFalse);
    expect(await ask((_) async => 500), isNull);
    expect(await ask((_) async => null), isNull);
    expect(await ask((_) async => throw Exception('끊김')), isNull);
  });

  test('실패 문구 — 원인 우리말, 주소는 로봇에 없을 때만 뺀다', () {
    expect(patrolClipErrorCause('MEDIA_ERR_ABORTED'), '중단됨');
    expect(patrolClipErrorCause('MEDIA_ERR_NETWORK'), '네트워크 오류');
    expect(patrolClipErrorCause('MEDIA_ERR_DECODE'), '영상 해독 실패');
    expect(patrolClipErrorCause('MEDIA_ERR_SRC_NOT_SUPPORTED'), '지원하지 않는 형식');
    expect(patrolClipErrorCause('VideoError'), '알 수 없는 오류');
    expect(kPatrolClipOpenTimeout, const Duration(seconds: 20));
    expect(
      patrolClipFailureText(const PatrolClipFailure(PatrolClipFailureKind.timeout)),
      '영상을 받지 못했습니다(20초).\n아래 주소를 브라우저 주소창에 직접 열어 보세요.',
    );
    expect(const PatrolClipFailure(PatrolClipFailureKind.timeout).showsUrl, isTrue);
    expect(const PatrolClipFailure(PatrolClipFailureKind.browser).showsUrl, isTrue);
    expect(const PatrolClipFailure(PatrolClipFailureKind.missing).showsUrl, isFalse);
  });
}
