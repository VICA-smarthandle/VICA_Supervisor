import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/models/mission_activity.dart';
import 'package:vica_supervisor/models/robot_status.dart';

RobotStatus robot({
  String dialog = '',
  String place = '',
  int left = -1,
  String last = '',
  String goal = '',
}) =>
    RobotStatus.fromJson({
      'status': 'idle',
      'current_goal': goal,
      'map_id': 'm1',
      'dialog_state': dialog,
      'wait_place': place,
      'wait_left_sec': left,
      'last_destination': last,
    });

void main() {
  group('단계별 버튼(10-29 표)', () {
    test('사람에게 다가가는 중·묻는 중은 접근 취소', () {
      for (final dialog in ['approaching', 'awaiting_user']) {
        final a = MissionActivity.of(robot(dialog: dialog, goal: '접근 대상'))!;
        expect(a.kind, MissionActivityKind.approach);
        expect(a.cancellable, isTrue);
        expect(a.cancelLabel, '접근 취소');
        expect(a.lockedRequestLabel, '접근 중');
        expect(a.homeLockedLabel, '접근 중에는 홈으로 부를 수 없습니다');
      }
      expect(MissionActivity.of(robot(dialog: 'approaching'))!.lines,
          ['사람에게 다가가는 중입니다.']);
      expect(MissionActivity.of(robot(dialog: 'awaiting_user'))!.lines,
          ['안내를 받을지 묻는 중입니다.']);
    });

    test('돌아서는 중·손잡이 잡기 대기는 처음 안내 — 취소 없음', () {
      final turning = MissionActivity.of(robot(dialog: 'turning'))!;
      expect(turning.kind, MissionActivityKind.firstGuide);
      expect(turning.cancellable, isFalse);
      expect(turning.lines, ['안내하려고 돌아서는 중입니다.']);
      final grip = MissionActivity.of(robot(dialog: 'grip_wait'))!;
      expect(grip.cancellable, isFalse);
      expect(grip.lockedRequestLabel, '안내 중');
      expect(grip.lines, ['사용자에게 처음 안내를 하는 중입니다.', '끝나면 다시 요청할 수 있습니다.']);
    });

    test('대기 장소로 가는 중(출발 직전 포함)은 대기 취소', () {
      for (final dialog in ['waiting_release', 'moving_to_wait_spot']) {
        final a = MissionActivity.of(
            robot(dialog: dialog, place: '입구 왼쪽', last: '남자 화장실'))!;
        expect(a.kind, MissionActivityKind.wait);
        expect(a.cancelLabel, '대기 취소');
        expect(a.lines, ['남자 화장실 입구 왼쪽(대기 장소)으로 가는 중입니다.']);
      }
    });

    test('대기 장소가 막혀 목적지로 돌아갈 때', () {
      final a = MissionActivity.of(
          robot(dialog: 'moving_back_to_dest', last: '남자 화장실'))!;
      expect(a.kind, MissionActivityKind.wait);
      expect(a.lines, ['남자 화장실 앞으로 돌아가 기다리려는 중입니다.']);
    });

    test('기다리는 중 — 대기 장소·목적지 앞, 남은 시간', () {
      expect(
        MissionActivity.of(robot(
                dialog: 'waiting', place: '입구 왼쪽', left: 150, last: '남자 화장실'))!
            .lines,
        ['남자 화장실 입구 왼쪽에서 기다리는 중입니다.', '남은 시간 2분 30초'],
      );
      expect(
        MissionActivity.of(robot(dialog: 'waiting', left: 150, last: '남자 화장실'))!
            .lines,
        ['남자 화장실 앞에서 기다리는 중입니다.', '남은 시간 2분 30초'],
      );
      expect(
        MissionActivity.of(robot(dialog: 'waiting', last: '남자 화장실'))!.lines,
        ['남자 화장실 앞에서 기다리는 중입니다.'],
      );
    });

    test('그 밖은 종전 화면 그대로', () {
      for (final dialog in [
        '',
        'idle',
        'navigating',
        'paused',
        'returning',
        'asking_next',
        'asking_wait_time',
        'estopped',
      ]) {
        expect(MissionActivity.of(robot(dialog: dialog)), isNull,
            reason: dialog);
      }
      expect(MissionActivity.of(null), isNull);
    });
  });

  test('취소 확인 팝업 문구(목업 44·45)', () {
    final wait = MissionActivity.of(robot(dialog: 'waiting'))!;
    expect(wait.cancelTitle, '대기 취소');
    expect(wait.keepLabel, '계속 대기');
    expect(wait.cancelBody, contains('로봇은 그 자리에 멈춥니다'));
    final approach = MissionActivity.of(robot(dialog: 'approaching'))!;
    expect(approach.cancelTitle, '접근 취소');
    expect(approach.keepLabel, '계속 진행');
    expect(approach.cancelBody, contains('1분 동안 다시 다가가지 않습니다'));
  });

  test('남은 시간 글자', () {
    expect(formatWaitLeft(150), '2분 30초');
    expect(formatWaitLeft(120), '2분');
    expect(formatWaitLeft(45), '45초');
    expect(formatWaitLeft(0), '0초');
  });

  test('옛 상태 노드(네 칸 없음)는 빈 값', () {
    final old = RobotStatus.fromJson({'status': 'idle', 'current_goal': ''});
    expect(old.dialogState, '');
    expect(old.waitLeftSec, -1);
    expect(MissionActivity.of(old), isNull);
  });
}
