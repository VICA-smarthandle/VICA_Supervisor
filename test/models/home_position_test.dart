// 홈 위치 모델이 로봇이 보낸 값을 어떻게 읽는지 고정합니다.
//
// 가장 중요한 계약은 **점수를 언제 보여주는가** 입니다. 지도에서 찍은 홈에는
// 점수가 없는데 0% 로 표시하면 "나쁜 홈"으로 읽힙니다. 사실은 잰 적이 없는
// 것이라 뜻이 완전히 다릅니다.
import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/models/home_position.dart';

void main() {
  group('HomeSource', () {
    test('로봇이 보낸 문자열을 읽는다', () {
      expect(HomeSource.fromWire('robot_standing'), HomeSource.robotStanding);
      expect(HomeSource.fromWire('map_pick'), HomeSource.mapPick);
    });

    test('모르는 값은 점수가 없는 쪽으로 본다', () {
      // 있지도 않은 점수를 믿게 하는 것보다 안전합니다.
      expect(HomeSource.fromWire('guessed'), HomeSource.mapPick);
      expect(HomeSource.fromWire(null), HomeSource.mapPick);
    });
  });

  group('HomePosition', () {
    test('서비스 응답을 그대로 읽는다', () {
      final home = HomePosition.fromValues(const {
        'x': -5.83,
        'y': -0.04,
        'yaw': 90.0,
        'source': 'robot_standing',
        'score': 84.2,
        'label': '충전 스테이션 앞',
        'visited_ok': true,
        'saved_at': '2026-08-26T14:03:00',
      });

      expect(home.x, closeTo(-5.83, 0.001));
      expect(home.yaw, closeTo(90.0, 0.001));
      expect(home.source, HomeSource.robotStanding);
      expect(home.score, closeTo(84.2, 0.001));
      expect(home.label, '충전 스테이션 앞');
      expect(home.visitedOk, isTrue);
    });

    test('빈 응답에도 예외를 던지지 않는다', () {
      final home = HomePosition.fromValues(const {});

      expect(home.x, 0);
      expect(home.visitedOk, isFalse);
      expect(home.source, HomeSource.mapPick);
    });

    test('지도에서 찍은 홈은 점수를 보여주지 않는다', () {
      final home = HomePosition.fromValues(const {
        'source': 'map_pick',
        'score': 0.0,
      });

      // 0% 라고 표시하면 '나쁜 홈'으로 읽힙니다. 잰 적이 없는 것과 다릅니다.
      expect(home.hasScore, isFalse);
    });

    test('실제 자리에서 잡은 홈만 점수를 보여준다', () {
      final home = HomePosition.fromValues(const {
        'source': 'robot_standing',
        'score': 84.2,
      });

      expect(home.hasScore, isTrue);
    });

    test('점수가 0 이면 실제 자리에서 잡았어도 보여주지 않는다', () {
      // 채점이 실패했거나 옛 형식입니다. 0% 를 보여줄 이유가 없습니다.
      final home = HomePosition.fromValues(const {
        'source': 'robot_standing',
        'score': 0.0,
      });

      expect(home.hasScore, isFalse);
    });

    test('확인 상태만 바꿔 복사한다', () {
      final home = HomePosition.fromValues(const {
        'x': 1.0,
        'y': 2.0,
        'yaw': 90.0,
        'source': 'map_pick',
        'visited_ok': false,
      });

      final visited = home.copyWith(visitedOk: true);

      expect(visited.visitedOk, isTrue);
      expect(visited.x, home.x);
      expect(visited.y, home.y);
      expect(visited.yaw, home.yaw);
      expect(visited.source, home.source);
    });

    test('저장 시각을 날짜로 줄여 보여준다', () {
      final home = HomePosition.fromValues(const {
        'saved_at': '2026-08-26T14:03:00',
      });

      expect(home.savedAtLabel, '2026-08-26');
    });

    test('시각을 못 읽으면 원문을 그대로 둔다', () {
      final home = HomePosition.fromValues(const {'saved_at': '언젠가'});

      expect(home.savedAtLabel, '언젠가');
    });
  });
}
