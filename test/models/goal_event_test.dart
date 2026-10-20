import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/models/goal_event.dart';

GoalEvent event(String kind, {String name = '화장실', String reason = ''}) {
  return GoalEvent.fromJson(
    {'event': kind, 'name': name, 'reason': reason, 'map_id': 'm1'},
    id: 'test-id',
  );
}

void main() {
  group('GoalEventKind', () {
    test('로봇이 보낸 이름을 읽는다', () {
      expect(GoalEventKind.fromWire('goal_failed'), GoalEventKind.failed);
      expect(GoalEventKind.fromWire('goal_canceled'), GoalEventKind.canceled);
      expect(
        GoalEventKind.fromWire('return_home_succeeded'),
        GoalEventKind.returnHomeSucceeded,
      );
    });

    test('모르는 이름은 버리지 않고 unknown 으로 둔다', () {
      expect(GoalEventKind.fromWire('goal_teleported'), GoalEventKind.unknown);
      expect(GoalEventKind.fromWire(null), GoalEventKind.unknown);
    });
  });

  group('무엇을 알리는가', () {
    test('실패·거부·취소는 팝업으로 알린다', () {
      expect(event('goal_failed').needsPopup, isTrue);
      expect(event('goal_rejected').needsPopup, isTrue);
      expect(event('goal_canceled').needsPopup, isTrue);
    });

    test('성공은 팝업을 띄우지 않는다', () {
      expect(event('goal_succeeded').needsPopup, isFalse);
      expect(event('goal_sent').needsPopup, isFalse);
      expect(event('goal_accepted').needsPopup, isFalse);
    });

    test('일시정지는 팝업을 띄우지 않는다', () {
      expect(event('goal_paused').needsPopup, isFalse);
    });

    test('홈 복귀 실패도 팝업으로 알린다', () {
      expect(event('return_home_failed').needsPopup, isTrue);
      expect(event('return_home_succeeded').needsPopup, isFalse);
    });

    test('취소는 실패가 아니다', () {
      expect(event('goal_canceled').isFailure, isFalse);
      expect(event('goal_failed').isFailure, isTrue);
      expect(event('goal_rejected').isFailure, isTrue);
    });

    test('홈 복귀 이벤트를 구분한다', () {
      expect(event('return_home_failed').isHomeReturn, isTrue);
      expect(event('goal_failed').isHomeReturn, isFalse);
    });
  });

  group('관리자에게 보여줄 문구', () {
    test('목적지 이름은 본문이 아니라 아래 칸 라벨로 간다', () {
      final failed = event('goal_failed', name: '남자 화장실');

      expect(failed.title, '주행 실패');
      expect(failed.destinationLabel, '남자 화장실');
      expect(failed.description, isNot(contains('남자 화장실')));
    });

    test('이름이 없으면 목적지 칸 라벨이 비고 본문은 그대로다', () {
      final failed = event('goal_failed', name: '');

      expect(failed.destinationLabel, isEmpty);
      expect(failed.description, contains('목적지까지 주행에 실패했습니다.'));
    });

    test('실패 본문은 세 줄이고 다음에 할 일과 관리자 호출을 적는다', () {
      final failed = event('goal_failed');
      final lines = failed.description.split('\n');

      expect(lines, hasLength(3));
      expect(lines[0], '목적지까지 주행에 실패했습니다.');
      expect(lines[1], contains('확인해 주세요'));
      expect(lines[2], '비카가 관리자를 호출했습니다.');
    });

    test('본문은 마침표 뒤 공백이 없어 줄이 다시 합쳐지지 않는다', () {
      for (final kind in [
        'goal_failed',
        'goal_rejected',
        'goal_canceled',
        'return_home_failed',
        'return_home_canceled',
      ]) {
        final text = event(kind).description;
        expect(text, isNot(matches(RegExp(r'\.[ \t]+'))), reason: kind);
        expect(text.split('\n').length, lessThanOrEqualTo(3), reason: kind);
      }
    });

    test('사유는 본문에 섞지 않고 따로 둔다', () {
      final failed = event('goal_failed', reason: 'Nav2 task failed');

      expect(failed.reason, 'Nav2 task failed');
      expect(failed.description, isNot(contains('Nav2 task failed')));
      expect(failed.description, isNot(contains('사유:')));
    });

    test('홈 복귀는 목적지 칸에 홈이라고 적는다', () {
      expect(event('return_home_failed', name: '').destinationLabel, '홈');
      expect(event('return_home_canceled', name: '').destinationLabel, '홈');
    });

    test('홈 복귀 실패는 홈을 다시 지정하라고 안내한다', () {
      final failed = event('return_home_failed');

      expect(failed.title, '홈 복귀 실패');
      expect(failed.description, contains('홈 위치를 다시 지정'));
    });
  });

  group('locationId', () {
    test('로봇이 실어 보낸 목적지 id 를 읽는다', () {
      final parsed = GoalEvent.fromJson(
        {
          'event': 'goal_succeeded',
          'name': '305호',
          'location_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          'destination_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          'map_id': 'm1',
        },
        id: 'x',
      );
      expect(parsed.locationId, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
    });

    test('destination_id 만 있어도 읽고, 둘 다 없으면 빈 값이다', () {
      final onlyDestination = GoalEvent.fromJson(
        {'event': 'goal_succeeded', 'destination_id': 'd1'},
        id: 'x',
      );
      expect(onlyDestination.locationId, 'd1');
      expect(event('goal_succeeded').locationId, '');
    });
  });

  group('대기 알림(2026-10-07, 목업 10·11)', () {
    test('막힘 — 빨간 실패 팝업, 목적지·대기 장소·사유 칸', () {
      final e = GoalEvent.fromJson(
        {
          'event': 'wait_spot_blocked',
          'name': '화장실 입구',
          'reason': "주행(Nav2)이 '화장실 입구-대기'에 들어가지 못했습니다.",
          'wait_place': 'spot',
          'wait_minutes': 10,
        },
        id: 'x',
      );
      expect(e.kind, GoalEventKind.waitSpotBlocked);
      expect(e.needsPopup, isTrue);
      expect(e.isFailure, isTrue);
      expect(e.title, '대기 장소가 막혔습니다');
      expect(e.detailRows.map((r) => r.$1), ['목적지', '대기 장소', '사유']);
      expect(e.detailRows[1].$2, '화장실 입구-대기');
    });

    test('만료 — 정보 팝업, 목적지·기다린 곳·대기 시간(사유 칸 없음)', () {
      final e = GoalEvent.fromJson(
        {
          'event': 'wait_expired',
          'name': '화장실 입구',
          'reason': '입구 오른쪽에서 30분 기다렸습니다.',
          'wait_place': 'spot',
          'wait_minutes': 30,
        },
        id: 'x',
      );
      expect(e.kind, GoalEventKind.waitExpired);
      expect(e.needsPopup, isTrue);
      expect(e.isFailure, isFalse);
      expect(e.detailRows, [
        ('목적지', '화장실 입구'),
        ('기다린 곳', '화장실 입구-대기'),
        ('대기 시간', '30분'),
      ]);
    });

    test('목적지 앞에서 기다렸으면 기다린 곳은 "OO 앞"', () {
      final e = GoalEvent.fromJson(
        {
          'event': 'wait_expired',
          'name': '407호',
          'wait_place': 'destination',
          'wait_minutes': 5,
        },
        id: 'x',
      );
      expect(e.detailRows[1], ('기다린 곳', '407호 앞'));
    });

    test('옛 사건은 지금처럼 목적지·사유 칸', () {
      final e = GoalEvent.fromJson(
        {'event': 'goal_failed', 'name': '305호', 'reason': 'Nav2'},
        id: 'x',
      );
      expect(e.detailRows, [('목적지', '305호'), ('사유', 'Nav2')]);
    });
  });

  test('대기 장소 가보기 실패는 관리자 호출 문구 없이 따로 알린다', () {
    final e = GoalEvent.fromJson(
      {
        'event': 'goal_failed',
        'name': '화장실 입구-대기',
        'location_id': 'wait_spot:aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      },
      id: 'x',
    );
    expect(e.isWaitSpotTry, isTrue);
    expect(e.title, '대기 장소 가보기 실패');
    expect(e.description, isNot(contains('관리자를 호출')));
  });
}
