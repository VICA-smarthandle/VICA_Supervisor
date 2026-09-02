// 이 파일은 Mission Manager 가 내는 goal 생명주기 이벤트를 표현합니다.
//
// **왜 앱이 직접 구독하는가.** 이 이벤트는 원래 vica_status_app_node 를 거쳐
// /robot_status 로 요약됐는데, 그 노드는 실패·취소 이벤트를 받으면
// current_goal 을 비우기만 하고 **reason 을 버렸습니다.** 그래서 주행이
// 실패해도 앱에서는 목적지가 조용히 사라질 뿐 원인을 알 수 없었습니다.
//
// /robot_status 스키마는 그대로 두고 앱이 이 토픽을 직접 봅니다.
// /robot/health·/robot/events 를 직접 구독하는 것과 같은 방식입니다.

/// goal 에 일어난 일.
///
/// Mission Manager 의 `_publish_goal_event` 가 내는 값과 1:1 입니다.
enum GoalEventKind {
  sent('goal_sent'),
  accepted('goal_accepted'),
  rejected('goal_rejected'),
  succeeded('goal_succeeded'),
  failed('goal_failed'),
  canceled('goal_canceled'),
  paused('goal_paused'),
  emergencyStopped('emergency_stopped'),

  // 홈 복귀는 사용자 안내가 아니라 관리자 조작이라 이벤트를 따로 냅니다.
  // 같은 이름을 쓰면 앱이 "화장실 주행이 실패했다"처럼 잘못 표시합니다.
  returnHomeSent('return_home_sent'),
  returnHomeSucceeded('return_home_succeeded'),
  returnHomeFailed('return_home_failed'),
  returnHomeCanceled('return_home_canceled'),

  unknown('');

  const GoalEventKind(this.wire);

  final String wire;

  static GoalEventKind fromWire(String? value) {
    for (final kind in GoalEventKind.values) {
      if (kind.wire == value && kind != GoalEventKind.unknown) {
        return kind;
      }
    }
    return GoalEventKind.unknown;
  }

  /// 관리자에게 팝업으로 알려야 하는가.
  ///
  /// **성공은 알리지 않습니다.** 도착은 로봇이 사용자에게 말로 알리고 앱 상태에도
  /// 드러나므로, 팝업까지 띄우면 관리자가 팝업 닫기에 익숙해집니다. 그러면
  /// 정작 중요한 실패 팝업도 읽지 않고 닫습니다.
  bool get needsPopup =>
      this == GoalEventKind.failed ||
      this == GoalEventKind.rejected ||
      this == GoalEventKind.canceled ||
      this == GoalEventKind.returnHomeFailed ||
      this == GoalEventKind.returnHomeCanceled;

  /// 주행이 실패로 끝났는가. 취소는 사람이 시킨 일이라 실패가 아닙니다.
  bool get isFailure =>
      this == GoalEventKind.failed ||
      this == GoalEventKind.rejected ||
      this == GoalEventKind.returnHomeFailed;

  bool get isHomeReturn =>
      this == GoalEventKind.returnHomeSent ||
      this == GoalEventKind.returnHomeSucceeded ||
      this == GoalEventKind.returnHomeFailed ||
      this == GoalEventKind.returnHomeCanceled;
}

class GoalEvent {
  const GoalEvent({
    required this.id,
    required this.kind,
    required this.destinationName,
    this.locationId = '',
    required this.reason,
    required this.mapId,
    required this.receivedAt,
  });

  /// 앱이 붙이는 고유값입니다. 같은 실패가 두 번 와도 팝업을 각각 띄우기 위해
  /// 필요하며, 로봇이 보내는 값이 아닙니다.
  final String id;

  final GoalEventKind kind;
  final String destinationName;

  /// 로봇이 실어 보낸 목적지 id. 배송이 "내 주행이 끝났나"를 이름이 아니라
  /// 이것으로 맞춥니다 — 같은 이름의 장소가 둘이면 이름은 믿을 수 없습니다.
  /// 홈 복귀처럼 카탈로그에 없는 자리는 `__home__` 같은 값이 옵니다.
  final String locationId;

  /// 로봇이 적어 보낸 사유입니다. 비어 있을 수 있습니다.
  final String reason;

  final String mapId;
  final DateTime receivedAt;

  /// 관리자에게 팝업으로 알려야 하는가. 판정은 [GoalEventKind] 가 합니다.
  bool get needsPopup => kind.needsPopup;

  /// 주행이 실패로 끝났는가. 취소는 사람이 시킨 일이라 실패가 아닙니다.
  bool get isFailure => kind.isFailure;

  bool get isHomeReturn => kind.isHomeReturn;

  factory GoalEvent.fromJson(Map<String, Object?> json, {required String id}) {
    return GoalEvent(
      id: id,
      kind: GoalEventKind.fromWire(json['event'] as String?),
      destinationName: (json['name'] as String?)?.trim() ?? '',
      // mission_manager_node._publish_goal_event 는 location_id 와
      // destination_id 에 같은 값을 싣습니다. 둘 중 있는 쪽을 씁니다.
      locationId: ((json['location_id'] ?? json['destination_id']) as String?)
              ?.trim() ??
          '',
      reason: (json['reason'] as String?)?.trim() ?? '',
      mapId: (json['map_id'] as String?)?.trim() ?? '',
      receivedAt: DateTime.now(),
    );
  }

  /// 팝업 제목.
  String get title {
    switch (kind) {
      case GoalEventKind.failed:
        return '주행 실패';
      case GoalEventKind.rejected:
        return '주행을 시작하지 못했습니다';
      case GoalEventKind.canceled:
        return '주행이 취소되었습니다';
      case GoalEventKind.returnHomeFailed:
        return '홈 복귀 실패';
      case GoalEventKind.returnHomeCanceled:
        return '홈 복귀가 취소되었습니다';
      default:
        return '주행 알림';
    }
  }

  /// 팝업 본문. **무슨 일이 일어났는지와 다음에 할 일을 함께 적습니다.**
  ///
  /// 사유 문자열만 보여주면 관리자가 다음 행동을 모릅니다.
  String get description {
    final where = destinationName.isEmpty ? '목적지' : destinationName;
    final detail = reason.isEmpty ? '' : '\n\n사유: $reason';

    switch (kind) {
      case GoalEventKind.failed:
        // 마지막 줄은 로봇이 이용자에게 하는 안내와 짝입니다. 주행이 실패하면
        // 이용자는 그 자리에 남으므로 로봇이 관리자를 부릅니다 — 관리자 화면도
        // 같은 사실을 알아야 사람이 기다리고 있다는 것을 압니다.
        return '$where(으)로 가는 도중 주행이 실패했습니다. '
            '경로가 막혔거나 로봇이 자기 위치를 잃었을 수 있습니다.\n'
            '로봇 주변을 확인하고 다시 요청하세요. '
            '위치가 어긋난 것 같으면 초기 위치를 다시 잡으세요.\n'
            '비카가 관리자를 호출했습니다. 확인이 필요합니다.$detail';
      case GoalEventKind.rejected:
        return '$where(으)로 가는 요청을 Nav2 가 받지 않았습니다. '
            '목적지 좌표가 지도 밖이거나 갈 수 없는 자리일 수 있습니다.$detail';
      case GoalEventKind.canceled:
        return '$where(으)로 가던 주행이 취소되었습니다.$detail';
      case GoalEventKind.returnHomeFailed:
        return '홈으로 돌아가지 못했습니다. 경로가 막혔거나 홈 좌표가 '
            '갈 수 없는 자리일 수 있습니다.\n'
            '지도 설정 화면에서 홈 위치를 다시 지정해 보세요.$detail';
      case GoalEventKind.returnHomeCanceled:
        return '홈 복귀가 취소되었습니다.$detail';
      default:
        return reason;
    }
  }
}
