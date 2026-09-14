// goal 생명주기 이벤트를 앱이 어떻게 읽고 무엇을 알리는지 고정합니다.
//
// **이 파일이 지키는 결함**: 주행이 실패해도 원격 주행 화면에 아무것도 뜨지
// 않아 목적지가 조용히 사라진 것처럼 보였습니다. 실패 사유가 /robot_status 를
// 거치며 버려졌기 때문입니다.
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
      // 로봇이 새 이벤트를 추가해도 앱이 예외를 던지지 않아야 합니다.
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
      // 도착은 로봇이 사용자에게 말로 알리고 앱 상태에도 드러납니다. 팝업까지
      // 띄우면 관리자가 팝업 닫기에 익숙해지고, 그러면 정작 중요한 실패
      // 팝업도 읽지 않고 닫습니다.
      expect(event('goal_succeeded').needsPopup, isFalse);
      expect(event('goal_sent').needsPopup, isFalse);
      expect(event('goal_accepted').needsPopup, isFalse);
    });

    test('일시정지는 팝업을 띄우지 않는다', () {
      // 화면에 '다시 출발' 버튼이 뜨므로 상태가 이미 보입니다.
      expect(event('goal_paused').needsPopup, isFalse);
    });

    test('홈 복귀 실패도 팝업으로 알린다', () {
      expect(event('return_home_failed').needsPopup, isTrue);
      expect(event('return_home_succeeded').needsPopup, isFalse);
    });

    test('취소는 실패가 아니다', () {
      // 사람이 시킨 일입니다. 아이콘과 로그 분류가 달라집니다.
      expect(event('goal_canceled').isFailure, isFalse);
      expect(event('goal_failed').isFailure, isTrue);
      expect(event('goal_rejected').isFailure, isTrue);
    });

    test('홈 복귀 이벤트를 구분한다', () {
      // 같은 이름을 쓰면 앱이 "화장실 주행이 실패했다"처럼 잘못 표시합니다.
      expect(event('return_home_failed').isHomeReturn, isTrue);
      expect(event('goal_failed').isHomeReturn, isFalse);
    });
  });

  group('관리자에게 보여줄 문구', () {
    test('목적지 이름을 문구에 넣는다', () {
      final failed = event('goal_failed', name: '남자 화장실');

      expect(failed.title, '주행 실패');
      expect(failed.description, contains('남자 화장실'));
    });

    test('이름이 없어도 문장이 깨지지 않는다', () {
      final failed = event('goal_failed', name: '');

      expect(failed.description, contains('목적지'));
    });

    test('다음에 할 일을 함께 적는다', () {
      // 사유 문자열만 보여주면 관리자가 다음 행동을 모릅니다.
      final failed = event('goal_failed');

      expect(failed.description, contains('다시 요청'));
    });

    test('로봇이 적어 보낸 사유를 붙인다', () {
      final failed = event('goal_failed', reason: 'Nav2 task failed');

      expect(failed.description, contains('Nav2 task failed'));
    });

    test('사유가 없으면 빈 줄을 만들지 않는다', () {
      final failed = event('goal_failed', reason: '');

      expect(failed.description, isNot(contains('사유:')));
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
}
