// 경비(순찰) 모델 — 상태 값·경보·경로·기록을 읽고 화면 글자를 고르는 규칙을 고정합니다.
//
// 계약은 ~/vica_data/patrol_plan/SPEC.md 2·3절, 문구는 Patrol* 목업 14개입니다. 여기 적힌
// 글자가 바뀌면 목업과 어긋난 것입니다.
import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/models/goal_event.dart';
import 'package:vica_supervisor/models/patrol.dart';

Map<String, Object?> _alarm(
  String event,
  String alarmId, {
  String place = '화장실',
  String stamp = '2026-11-14T02:13:41',
  Map<String, Object?> extra = const {},
}) =>
    {
      'event': event,
      'map_id': 'm1',
      'name': '',
      'reason': '',
      'timestamp': stamp,
      'alarm_id': alarmId,
      'place': place,
      'robot_x': 1.5,
      'robot_y': -2.0,
      ...extra,
    };

void main() {
  final now = DateTime(2026, 11, 14, 2, 13, 41);

  group('순찰 단계(dialog_state)', () {
    test('다섯 값과 그 밖', () {
      expect(PatrolPhase.of('patrolling'), PatrolPhase.moving);
      expect(PatrolPhase.of('patrol_dwell'), PatrolPhase.dwell);
      expect(PatrolPhase.of('patrol_alarm'), PatrolPhase.alarm);
      expect(PatrolPhase.of('patrol_light'), PatrolPhase.light);
      expect(PatrolPhase.of('patrol_paused'), PatrolPhase.paused);
      for (final other in ['', 'idle', 'waiting', 'navigating', 'patrol']) {
        expect(PatrolPhase.of(other), PatrolPhase.off, reason: other);
      }
    });

    test('순찰 중·경보로 멈춤 구분', () {
      expect(PatrolPhase.moving.running, isTrue);
      expect(PatrolPhase.dwell.running, isTrue);
      expect(PatrolPhase.paused.running, isFalse);
      expect(PatrolPhase.alarm.stoppedByAlarm, isTrue);
      expect(PatrolPhase.light.stoppedByAlarm, isTrue);
      expect(PatrolPhase.paused.stoppedByAlarm, isFalse);
      expect(PatrolPhase.off.active, isFalse);
    });
  });

  group('사건 종류', () {
    test('patrol_* 는 경비 사건이고 주행 알림 팝업 줄에 끼지 않는다', () {
      const wires = [
        'patrol_started',
        'patrol_waypoint',
        'patrol_intruder',
        'patrol_sound',
        'patrol_light',
        'patrol_camera_lost',
        'patrol_acked',
        'patrol_paused',
        'patrol_resumed',
        'patrol_stopped',
      ];
      for (final wire in wires) {
        final kind = GoalEventKind.fromWire(wire);
        expect(kind, isNot(GoalEventKind.unknown), reason: wire);
        expect(kind.isPatrol, isTrue, reason: wire);
        expect(kind.needsPopup, isFalse, reason: wire);
      }
      expect(GoalEventKind.sent.isPatrol, isFalse);
      expect(GoalEventKind.paused.isPatrol, isFalse);
      expect(GoalEventKind.unknown.isPatrol, isFalse);
    });

    test('경보는 넷이다', () {
      final alarms = GoalEventKind.values.where((k) => k.isPatrolAlarm);
      expect(alarms.map((k) => k.wire), [
        'patrol_intruder',
        'patrol_sound',
        'patrol_light',
        'patrol_camera_lost',
      ]);
    });
  });

  group('경보 문구(목업 PatrolIntruder·Sound·Light·DeviceFault)', () {
    test('팝업 제목', () {
      expect(PatrolAlarmKind.intruder.popupTitle, '침입 감지');
      expect(PatrolAlarmKind.sound.popupTitle, '큰 소리 감지');
      expect(PatrolAlarmKind.light.popupTitle, '불 켜짐 확인 요청');
      expect(PatrolAlarmKind.cameraLost.popupTitle, '카메라 끊김');
    });

    test('팝업 본문은 구역 이름을 넣는다', () {
      expect(PatrolAlarmKind.intruder.popupBody('화장실'),
          '화장실에 사람이 감지되었습니다.\n확인해 주세요.');
      expect(PatrolAlarmKind.sound.popupBody('방2'),
          '방2에서 큰 소리 감지되었습니다.\n확인해 주세요.');
      expect(PatrolAlarmKind.light.popupBody('407호'),
          '407호에 불이 켜져 있습니다.\n확인해 주세요.');
      expect(
        PatrolAlarmKind.cameraLost.popupBody('작업실'),
        '카메라 신호가 끊겼습니다.\n'
        '사람 감지와 영상 저장을 할 수 없습니다.\n'
        '로봇은 대기하고 있습니다.\n'
        '확인해 주세요.',
      );
    });

    test('구역을 모르면 그 말을 뺀다', () {
      expect(PatrolAlarmKind.intruder.popupBody(''), '사람이 감지되었습니다.\n확인해 주세요.');
      expect(PatrolAlarmKind.sound.popupBody(''), '큰 소리 감지되었습니다.\n확인해 주세요.');
    });

    test('종류 칸과 기록 제목 — 큰 소리는 크기를 붙인다', () {
      expect(PatrolAlarmKind.intruder.kindLabel(null), '사람');
      expect(PatrolAlarmKind.sound.kindLabel(70.4), '큰 소리 (70 dB)');
      expect(PatrolAlarmKind.sound.kindLabel(null), '큰 소리');
      expect(PatrolAlarmKind.light.kindLabel(null), '불 켜짐');
      expect(PatrolAlarmKind.intruder.recordTitle(null), '침입 감지 · 사람');
      expect(PatrolAlarmKind.sound.recordTitle(52.2), '큰 소리 · 52 dB');
      expect(PatrolAlarmKind.light.recordTitle(null), '불 켜짐');
      expect(PatrolAlarmKind.cameraLost.recordTitle(null), '카메라 끊김');
    });

    test('확인 버튼 — 음성이 있는 종류만 (경보음 끄기)', () {
      expect(PatrolAlarmKind.intruder.ackLabel, '확인 (경보음 끄기)');
      expect(PatrolAlarmKind.sound.ackLabel, '확인 (경보음 끄기)');
      expect(PatrolAlarmKind.light.ackLabel, '확인 (경보음 끄기)');
      expect(PatrolAlarmKind.cameraLost.ackLabel, '확인');
    });

    test('확인한 뒤 한 줄(목업 PatrolPaused)', () {
      expect(PatrolAlarmKind.intruder.ackedHeadline, '침입 감지를 확인했습니다.');
      expect(PatrolAlarmKind.sound.ackedHeadline, '큰 소리 감지를 확인했습니다.');
      expect(PatrolAlarmKind.light.ackedHeadline, '불 켜짐을 확인했습니다.');
      expect(PatrolAlarmKind.cameraLost.ackedHeadline, '카메라 끊김을 확인했습니다.');
    });

    test('영상은 사람·큰 소리만, 음성은 카메라 끊김만 없다', () {
      expect(PatrolAlarmKind.intruder.hasClip, isTrue);
      expect(PatrolAlarmKind.sound.hasClip, isTrue);
      expect(PatrolAlarmKind.light.hasClip, isFalse);
      expect(PatrolAlarmKind.cameraLost.hasClip, isFalse);
      expect(PatrolAlarmKind.cameraLost.hasVoice, isFalse);
      expect(PatrolAlarmKind.light.hasVoice, isTrue);
    });
  });

  group('경보 사건 읽기', () {
    test('alarm_id·구역·좌표·시각', () {
      final alarm = PatrolAlarm.fromEvent(
        _alarm('patrol_intruder', '20261114_021341_intruder',
            extra: {'clip_id': '20261114_021341_intruder'}),
        now: now,
      )!;
      expect(alarm.kind, PatrolAlarmKind.intruder);
      expect(alarm.place, '화장실');
      expect(alarm.robotX, 1.5);
      expect(alarm.clipId, '20261114_021341_intruder');
      expect(alarm.clock, '02:13:41');
      expect(alarm.acked, isFalse);
      expect(alarm.ageAtFirstSeen, Duration.zero);
    });

    test('큰 소리의 크기, 불 켜짐의 사진', () {
      final sound = PatrolAlarm.fromEvent(
        _alarm('patrol_sound', '20261114_014012_sound',
            extra: {'level_db': 70.4}),
        now: now,
      )!;
      expect(sound.levelDb, 70.4);
      final light = PatrolAlarm.fromEvent(
        _alarm('patrol_light', '20261114_005207_light',
            extra: {'photo': '20261114_005207.jpg'}),
        now: now,
      )!;
      expect(light.photo, '20261114_005207.jpg');
      expect(light.kind, PatrolAlarmKind.light);
    });

    test('경보가 아니거나 alarm_id 가 없으면 null', () {
      expect(
          PatrolAlarm.fromEvent(_alarm('patrol_acked', 'a'), now: now), isNull);
      expect(PatrolAlarm.fromEvent(_alarm('patrol_intruder', ''), now: now),
          isNull);
      expect(
          PatrolAlarm.fromEvent(_alarm('goal_failed', 'a'), now: now), isNull);
    });

    test('재전송으로 처음 봐도 지난 시간을 안다(로봇 시계끼리의 차)', () {
      // 02:13:41 에 난 경보의 20초 뒤 재전송을 앱이 처음 받았다.
      final alarm = PatrolAlarm.fromEvent(
        _alarm('patrol_intruder', '20261114_021341_intruder',
            stamp: '2026-11-14T02:14:01', extra: {'resend': true}),
        now: now,
      )!;
      expect(alarm.ageAtFirstSeen, const Duration(seconds: 20));
      expect(alarm.elapsed(now.add(const Duration(seconds: 3))),
          const Duration(seconds: 23));
    });

    test('재전송은 새로 알게 된 영상 id 만 채우고 확인 표시는 지킨다', () {
      final first = PatrolAlarm.fromEvent(
        _alarm('patrol_intruder', '20261114_021341_intruder'),
        now: now,
      )!
          .copyWith(acked: true);
      final resent = PatrolAlarm.fromEvent(
        _alarm('patrol_intruder', '20261114_021341_intruder',
            stamp: '2026-11-14T02:13:51', extra: {'clip_id': 'c1'}),
        now: now.add(const Duration(seconds: 10)),
      )!;
      final merged = first.merged(resent);
      expect(merged.clipId, 'c1');
      expect(merged.acked, isTrue);
      expect(merged.firstSeen, now);
    });

    test('녹화 시간은 5초 전부터 세고, 가장 긴 길이를 넘기면 없다', () {
      final intruder = PatrolAlarm.fromEvent(
        _alarm('patrol_intruder', '20261114_021341_intruder'),
        now: now,
      )!;
      expect(intruder.recordingSec(now), 5);
      expect(intruder.recordingSec(now.add(const Duration(seconds: 13))), 18);
      expect(intruder.recordingSec(now.add(const Duration(seconds: 55))), 60);
      expect(
          intruder.recordingSec(now.add(const Duration(seconds: 56))), isNull);

      final sound = PatrolAlarm.fromEvent(
        _alarm('patrol_sound', '20261114_021341_sound'),
        now: now,
      )!;
      // 큰 소리는 5초 전 + 10초 뒤 = 15초.
      expect(sound.recordingSec(now.add(const Duration(seconds: 10))), 15);
      expect(sound.recordingSec(now.add(const Duration(seconds: 11))), isNull);

      final light = PatrolAlarm.fromEvent(
        _alarm('patrol_light', '20261114_021341_light'),
        now: now,
      )!;
      expect(light.recordingSec(now), isNull);
    });

    test('상태 줄 — 확인하면 경보음 꺼짐이 붙는다(카메라 끊김은 음성이 없다)', () {
      final alarm = PatrolAlarm.fromEvent(
        _alarm('patrol_intruder', '20261114_021341_intruder'),
        now: now,
      )!;
      expect(alarm.statusLine, '02:13:41 · 화장실');
      expect(alarm.copyWith(acked: true).statusLine, '02:13:41 · 화장실 · 경보음 꺼짐');
      final camera = PatrolAlarm.fromEvent(
        _alarm('patrol_camera_lost', '20261114_030255_camera_lost',
            place: '작업실'),
        now: now,
      )!
          .copyWith(acked: true);
      expect(camera.statusLine, '03:02:55 · 작업실');
    });
  });

  group('글자 도우미', () {
    test('alarm_id 의 시각', () {
      expect(patrolAlarmTime('20261114_203455_intruder'),
          DateTime(2026, 11, 14, 20, 34, 55));
      expect(patrolAlarmTime('20261114_203455_camera_lost'),
          DateTime(2026, 11, 14, 20, 34, 55));
      expect(patrolAlarmTime('abc'), isNull);
    });

    test('길이 0:42', () {
      expect(patrolDuration(42), '0:42');
      expect(patrolDuration(65.9), '1:05');
      expect(patrolDuration(5), '0:05');
      expect(patrolDuration(-3), '0:00');
    });

    test('어디로 가는 중(목업 PatrolRunning)', () {
      expect(patrolHeadingLine('작업실', '화장실'), '작업실 → 화장실로 가는 중입니다.');
      expect(patrolHeadingLine('', '입구'), '입구로 가는 중입니다.');
      expect(patrolHeadingLine('입구', '식당'), '입구 → 식당으로 가는 중입니다.');
      expect(patrolHeadingLine('입구', ''), '');
    });

    test('장소를 뺐을 때(목업 PatrolRouteRemoved)', () {
      expect(patrolRemovedNotice('작업실', shifted: true),
          '작업실을 뺐습니다.\n뒤 번호를 하나씩 당겼습니다.');
      expect(patrolRemovedNotice('407호', shifted: false), '407호를 뺐습니다.');
    });

    test('경비를 종료했을 때(목업 PatrolTexts) — 홈으로 돌아가면 두 줄', () {
      expect(
          patrolStoppedNotice(returnHome: true), '경비를 종료했습니다.\n로봇이 홈으로 돌아갑니다.');
      // 돌아간다면 응답 문구는 쓰지 않는다.
      expect(
        patrolStoppedNotice(returnHome: true, homeRefusal: '경비를 종료했습니다.'),
        '경비를 종료했습니다.\n로봇이 홈으로 돌아갑니다.',
      );
    });

    test('홈으로 못 돌아가면 그 까닭을 둘째 줄에 적는다', () {
      // 까닭은 '홈으로 복귀' 버튼의 거절과 같은 글자다(provider 가 같은 표로 옮겨 넘긴다).
      expect(
        patrolStoppedNotice(
          returnHome: false,
          homeRefusal: '홈 위치가 지정되지 않았습니다. 지도 설정 화면에서 먼저 지정하세요.',
        ),
        '경비를 종료했습니다.\n'
        '홈 위치가 지정되지 않았습니다. 지도 설정 화면에서 먼저 지정하세요.',
      );
    });

    test('미션이 종료 문장만 보냈으면(옛 미션·홈 복귀 없음) 한 줄이다', () {
      expect(patrolStoppedNotice(returnHome: false), '경비를 종료했습니다.');
      expect(
        patrolStoppedNotice(returnHome: false, homeRefusal: '경비를 종료했습니다.'),
        '경비를 종료했습니다.',
      );
    });
  });

  group('순찰 경로', () {
    test('응답에서 읽고 한 줄로 적는다(목업 PatrolHome)', () {
      final route = PatrolRoute.fromValues({
        'found': true,
        'map_id': 'm1',
        'destination_ids': ['a', 'b', 'c'],
        'names': ['입구', '안내소', '작업실'],
        'message': '',
      }, fallbackMapId: 'x');
      expect(route.mapId, 'm1');
      expect(route.ids, ['a', 'b', 'c']);
      expect(route.summary, '입구 → 안내소 → 작업실 → 다시 입구');
    });

    test('경로가 없으면 빈 경로', () {
      final route = PatrolRoute.fromValues(
        {'found': false, 'map_id': '', 'destination_ids': [], 'names': []},
        fallbackMapId: 'm1',
      );
      expect(route.isEmpty, isTrue);
      expect(route.mapId, 'm1');
      expect(route.summary, '');
    });

    test('꺼 둔 감시 항목을 읽는다 — 없으면 모두 켬, 경로가 없어도 남는다', () {
      final all = PatrolRoute.fromValues({
        'found': true,
        'destination_ids': ['a', 'b'],
        'names': ['입구', '안내소'],
      }, fallbackMapId: 'm1');
      expect(all.watchOff, isEmpty);
      expect(patrolWatchKinds.every(all.watches), isTrue);

      final some = PatrolRoute.fromValues({
        'found': true,
        'destination_ids': ['a', 'b'],
        'names': ['입구', '안내소'],
        'watch_off': ['sound', 'camera_lost', 'light', 'nonsense'],
      }, fallbackMapId: 'm1');
      // 카메라 끊김은 끌 수 있는 항목이 아니다.
      expect(some.watchOff, {PatrolAlarmKind.light, PatrolAlarmKind.sound});
      expect(some.watches(PatrolAlarmKind.intruder), isTrue);
      expect(some.watches(PatrolAlarmKind.sound), isFalse);

      final noRoute = PatrolRoute.fromValues({
        'found': false,
        'destination_ids': [],
        'names': [],
        'watch_off': ['intruder'],
      }, fallbackMapId: 'm1');
      expect(noRoute.isEmpty, isTrue);
      expect(noRoute.watchOff, {PatrolAlarmKind.intruder});
    });

    test('보낼 이름은 정해진 순서(사람·불 켜짐·큰 소리)다', () {
      expect(
        PatrolRoute.watchOffWire(
            {PatrolAlarmKind.sound, PatrolAlarmKind.intruder}),
        ['intruder', 'sound'],
      );
      expect(PatrolRoute.watchOffWire(const {}), isEmpty);
    });

    test('이름이 덜 와도 순서를 맞춘다', () {
      final route = PatrolRoute.fromValues({
        'found': true,
        'destination_ids': ['a', 'b'],
        'names': ['입구'],
      }, fallbackMapId: 'm1');
      expect(route.names, ['입구', '']);
    });
  });

  group('경로 편집(목업 PatrolRouteEdit·PatrolRouteRemoved)', () {
    const six = ['입구', '안내소', '작업실', '화장실', '방2', '407호'];

    test('누르면 맨 뒤에 번호가 붙는다', () {
      var draft = const PatrolRouteDraft([]);
      for (final id in six) {
        draft = draft.toggled(id);
      }
      expect(draft.ids, six);
      expect(draft.numberOf('작업실'), 3);
      expect(draft.numberOf('휴게실'), isNull);
      expect(draft.shiftedFrom, isEmpty);
    });

    test('중간 장소를 빼면 뒤 번호가 하나씩 당겨지고 옛 번호를 남긴다', () {
      final draft = const PatrolRouteDraft(six).toggled('작업실');
      expect(draft.ids, ['입구', '안내소', '화장실', '방2', '407호']);
      // 목업의 '4 → 3'·'5 → 4'·'6 → 5'.
      expect(draft.shiftedFrom, {'화장실': 4, '방2': 5, '407호': 6});
      expect(draft.numberOf('화장실'), 3);
    });

    test('마지막 장소를 빼면 당겨지는 번호가 없다', () {
      final draft = const PatrolRouteDraft(six).removed('407호');
      expect(draft.length, 5);
      expect(draft.shiftedFrom, isEmpty);
    });

    test('다음 조작에서 당겨짐 표시는 지워진다', () {
      final draft = const PatrolRouteDraft(six).removed('작업실').added('휴게실');
      expect(draft.shiftedFrom, isEmpty);
      expect(draft.numberOf('휴게실'), 6);
    });

    test('저장된 경로와 같은지', () {
      const draft = PatrolRouteDraft(['a', 'b']);
      expect(draft.sameAs(['a', 'b']), isTrue);
      expect(draft.sameAs(['b', 'a']), isFalse);
      expect(draft.sameAs(['a']), isFalse);
    });

    test('저장된 경로에 같은 장소가 두 번 있으면 앞의 것만 둔다', () {
      expect(PatrolRouteDraft.from(['a', 'b', 'a', 'c']).ids, ['a', 'b', 'c']);
    });
  });

  group('경비 기록(목업 PatrolLog·PatrolVideo)', () {
    PatrolRecord record(Map<String, Object?> json) =>
        PatrolRecord.fromJson(json)!;

    test('침입 — 영상 길이·범위·감지 순간', () {
      final r = record({
        'alarm_id': '20261110_021341_intruder',
        'kind': 'intruder',
        'time': '2026-11-10T02:13:41',
        'place': '화장실',
        'clip_id': '20261110_021341_intruder',
        'photo': null,
        'level_db': null,
        'clip_state': 'ready',
        'clip_sec': 42.0,
        'clip_start': '2026-11-10T02:13:36',
        'clip_end': '2026-11-10T02:14:18',
        'detect_sec': 5.0,
      });
      expect(r.title, '침입 감지 · 사람');
      expect(r.subtitle, '11-10 02:13:41 · 화장실');
      expect(r.mediaTitle, '침입 감지 · 화장실 · 02:13:41');
      expect(r.clipReady, isTrue);
      expect(r.clipLength, '0:42');
      expect(r.clipRange, '02:13:36 ~ 02:14:18');
      // 사람 영상은 안 보이고 10초 뒤에 끝난다 → 끝에서 10초 앞.
      expect(r.lastSeenSec, 32.0);
    });

    test('큰 소리·불 켜짐·카메라 끊김', () {
      final sound = record({
        'alarm_id': '20261110_014012_sound',
        'kind': 'sound',
        'time': '2026-11-10T01:40:12',
        'place': '방2',
        'clip_id': 'c2',
        'level_db': 70.2,
        'clip_state': 'recording',
        'clip_sec': 6.0,
      });
      expect(sound.title, '큰 소리 · 70 dB');
      expect(sound.clipReady, isFalse);
      expect(sound.clipRecording, isTrue);
      expect(sound.lastSeenSec, isNull);

      final light = record({
        'alarm_id': '20261110_005207_light',
        'kind': 'light',
        'time': '2026-11-10T00:52:07',
        'place': '407호',
        'photo': '20261110_005207.jpg',
      });
      expect(light.title, '불 켜짐');
      expect(light.hasPhoto, isTrue);
      expect(light.clipReady, isFalse);
      expect(light.mediaTitle, '불 켜짐 · 407호 · 00:52:07');

      final camera = record({
        'alarm_id': '20261109_030255_camera_lost',
        'kind': 'camera_lost',
        'place': '작업실',
      });
      expect(camera.title, '카메라 끊김');
      // time 이 없으면 alarm_id 에서 읽는다.
      expect(camera.subtitle, '11-09 03:02:55 · 작업실');
    });

    test('60초를 꽉 채운 영상은 마지막 감지를 알 수 없다', () {
      final r = record({
        'alarm_id': '20261110_021341_intruder',
        'kind': 'intruder',
        'clip_id': 'c',
        'clip_state': 'ready',
        'clip_sec': 60.0,
        'detect_sec': 5.0,
      });
      expect(r.lastSeenSec, isNull);
    });

    test('모르는 종류나 alarm_id 없는 줄은 버린다', () {
      expect(PatrolRecord.fromJson({'alarm_id': 'a', 'kind': 'fire'}), isNull);
      expect(PatrolRecord.fromJson({'kind': 'light'}), isNull);
      expect(PatrolRecord.fromJson('글자'), isNull);
    });
  });
}
