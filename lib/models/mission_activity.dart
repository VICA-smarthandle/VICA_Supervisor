// 원격 주행 화면이 '목적지 이름' 없이도 보여 줄 미션의 지금 하는 일(2026-10-29).
//
// 앱은 /robot_status.current_goal 이 있을 때만 상태 줄과 [일시정지][주행 취소]를 띄워,
// 대기 장소 이동·대기·사람 접근·처음 안내 중에는 아무것도 못 눌렀습니다(10-21 기록).
// 미션이 1 Hz 로 알리는 dialog_state 를 상태 노드가 넘겨 주므로, 그 값으로 상태 줄·잠긴
// 버튼 글자·취소 버튼을 정합니다. 화면 문구는 '앱 UI 사전확인' 목업 38~46(10-29 승인) 그대로입니다.
//
// 단계별 버튼(10-29 사용자 결정 표):
//   approaching · awaiting_user            → [접근 취소]
//   turning · grip_wait                    → 버튼 없음(처음 안내)
//   waiting_release · moving_to_wait_spot
//   · waiting · moving_back_to_dest        → [대기 취소]
//   그 밖(idle·navigating·returning …)     → null, 종전 화면(current_goal) 그대로
import 'robot_status.dart';

enum MissionActivityKind { wait, approach, firstGuide }

class MissionActivity {
  const MissionActivity({required this.kind, required this.lines});

  final MissionActivityKind kind;

  /// 카드의 회색 상태 줄. 두 줄이면 줄을 바꿔 보입니다.
  final List<String> lines;

  /// 취소 버튼이 있는가. 처음 안내 중에는 없습니다(10-21·10-29 사용자 결정).
  bool get cancellable => kind != MissionActivityKind.firstGuide;

  /// 잠긴 주행 요청 버튼의 글자.
  String get lockedRequestLabel => switch (kind) {
        MissionActivityKind.wait => '대기 중',
        MissionActivityKind.approach => '접근 중',
        MissionActivityKind.firstGuide => '안내 중',
      };

  /// 잠긴 홈 복귀 버튼의 글자.
  String get homeLockedLabel => '$lockedRequestLabel에는 홈으로 부를 수 없습니다';

  /// 취소 버튼 글자. 취소가 없으면 빈 문자열입니다.
  String get cancelLabel => switch (kind) {
        MissionActivityKind.wait => '대기 취소',
        MissionActivityKind.approach => '접근 취소',
        MissionActivityKind.firstGuide => '',
      };

  /// 취소 확인 팝업(목업 44·45).
  String get cancelTitle => cancelLabel;

  String get cancelBody => switch (kind) {
        MissionActivityKind.wait =>
          '기다리던 것을 끝냅니다. 로봇은 그 자리에 멈춥니다. 다른 곳으로 보내려면 장소를 골라 다시 요청하세요.',
        MissionActivityKind.approach =>
          '사람에게 다가가거나 묻던 것을 멈춥니다. 로봇은 그 자리에 멈추고, 이 사람에게는 1분 동안 다시 다가가지 않습니다.',
        MissionActivityKind.firstGuide => '',
      };

  /// 확인 팝업의 '그냥 두기' 글자.
  String get keepLabel => switch (kind) {
        MissionActivityKind.wait => '계속 대기',
        MissionActivityKind.approach => '계속 진행',
        MissionActivityKind.firstGuide => '',
      };

  /// 미션 dialog_state 로 지금 하는 일을 정합니다. 해당 없으면 null(종전 화면).
  static MissionActivity? of(RobotStatus? robot) {
    if (robot == null) {
      return null;
    }
    final name = robot.lastDestination.trim();
    final place = robot.waitPlace.trim();
    switch (robot.dialogState.trim()) {
      case 'waiting_release':
      case 'moving_to_wait_spot':
        // 멘트 뒤 출발 직전(waiting_release)도 '가는 중'으로 보입니다(목업 39).
        return MissionActivity(
          kind: MissionActivityKind.wait,
          lines: [_goingToWaitSpot(name, place)],
        );
      case 'moving_back_to_dest':
        return MissionActivity(
          kind: MissionActivityKind.wait,
          lines: ['${name.isEmpty ? '목적지' : name} 앞으로 돌아가 기다리려는 중입니다.'],
        );
      case 'waiting':
        return MissionActivity(
          kind: MissionActivityKind.wait,
          lines: [
            _waitingAt(name, place),
            if (robot.waitLeftSec >= 0) '남은 시간 ${formatWaitLeft(robot.waitLeftSec)}',
          ],
        );
      case 'approaching':
        return const MissionActivity(
          kind: MissionActivityKind.approach,
          lines: ['사람에게 다가가는 중입니다.'],
        );
      case 'awaiting_user':
        return const MissionActivity(
          kind: MissionActivityKind.approach,
          lines: ['안내를 받을지 묻는 중입니다.'],
        );
      case 'turning':
        return const MissionActivity(
          kind: MissionActivityKind.firstGuide,
          lines: ['안내하려고 돌아서는 중입니다.'],
        );
      case 'grip_wait':
        return const MissionActivity(
          kind: MissionActivityKind.firstGuide,
          lines: ['사용자에게 처음 안내를 하는 중입니다.', '끝나면 다시 요청할 수 있습니다.'],
        );
      default:
        return null;
    }
  }

  static String _goingToWaitSpot(String name, String place) {
    if (name.isEmpty) {
      return '대기 장소로 가는 중입니다.';
    }
    if (place.isEmpty) {
      return '$name 대기 장소로 가는 중입니다.';
    }
    // 쪽 이름('입구 왼쪽'·'입구 오른쪽'·'입구 맞은편'·'입구 앞')은 모두 받침으로 끝나 '으로'입니다.
    return '$name $place(대기 장소)으로 가는 중입니다.';
  }

  static String _waitingAt(String name, String place) {
    if (name.isEmpty) {
      return '그 자리에서 기다리는 중입니다.';
    }
    if (place.isEmpty) {
      return '$name 앞에서 기다리는 중입니다.';
    }
    return '$name $place에서 기다리는 중입니다.';
  }
}

/// 대기 남은 시간 '2분 30초'·'2분'·'45초'.
String formatWaitLeft(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  if (m > 0 && s > 0) {
    return '$m분 $s초';
  }
  if (m > 0) {
    return '$m분';
  }
  return '$s초';
}
