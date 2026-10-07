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

  /// 취소를 눌렀는데 취소할 주행이 없었다 — 지금은 대기라는 통보입니다.
  ///
  /// 앱 표시가 로봇보다 뒤처져 있을 때 되맞추는 새로고침입니다(2026-09-02).
  /// 사건이 아니라 사실 통보라 팝업은 띄우지 않습니다.
  stateIdle('state_idle'),

  // 대기 장소(2026-10-07). 주행 결과가 아니라 미션의 판단이라 미션이 따로 냅니다.
  /// 대기 장소로 가는 주행을 Nav2 가 실패로 끝냈다 — 로봇은 목적지로 돌아가 기다립니다.
  waitSpotBlocked('wait_spot_blocked'),

  /// 대기 시간이 끝났다 — 로봇은 "대기 시간이 종료되어…"를 말하고 홈으로 갑니다.
  waitExpired('wait_expired'),

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
      this == GoalEventKind.returnHomeCanceled ||
      this == GoalEventKind.waitSpotBlocked ||
      this == GoalEventKind.waitExpired;

  /// 주행이 실패로 끝났는가. 취소는 사람이 시킨 일이라 실패가 아닙니다.
  /// 대기 장소 막힘은 빨간 아이콘(목업 10번), 대기 만료는 정보 아이콘(11번)입니다.
  bool get isFailure =>
      this == GoalEventKind.failed ||
      this == GoalEventKind.rejected ||
      this == GoalEventKind.returnHomeFailed ||
      this == GoalEventKind.waitSpotBlocked;

  /// 대기 알림인가. 뒤이은 출발(홈 복귀 등)이 이 팝업을 거두면 안 됩니다 —
  /// 대기 만료는 바로 홈 복귀가 나가서, 거두면 관리자가 볼 틈이 없습니다.
  bool get isWaitAlert =>
      this == GoalEventKind.waitSpotBlocked ||
      this == GoalEventKind.waitExpired;

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
    this.waitPlace = '',
    this.waitMinutes = -1,
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

  /// 대기 알림의 기다린 곳 — `spot`(대기 장소)·`destination`(목적지 앞). 그 밖은 빈 값.
  final String waitPlace;

  /// 대기 알림의 대기 시간(분). 모르면 -1.
  final int waitMinutes;

  /// 관리자에게 팝업으로 알려야 하는가. 판정은 [GoalEventKind] 가 합니다.
  bool get needsPopup => kind.needsPopup;

  /// 주행이 실패로 끝났는가. 취소는 사람이 시킨 일이라 실패가 아닙니다.
  bool get isFailure => kind.isFailure;

  bool get isHomeReturn => kind.isHomeReturn;

  /// 지도 설정 '대기 장소로 가보기'의 주행인가. 미션은 이 주행의 목적지 id 를
  /// `wait_spot:<목적지 id>` 로 보냅니다(mission_logic.WAIT_SPOT_DESTINATION_PREFIX).
  /// 사용자 안내가 아니라 관리자 확인용이라 실패 문구가 다릅니다 — 관리자 호출도 없습니다.
  bool get isWaitSpotTry => locationId.startsWith('wait_spot:');

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
      waitPlace: (json['wait_place'] as String?)?.trim() ?? '',
      waitMinutes: (json['wait_minutes'] as num?)?.toInt() ?? -1,
    );
  }

  /// 팝업 제목.
  String get title {
    if (isWaitSpotTry && kind == GoalEventKind.failed) {
      return '대기 장소 가보기 실패';
    }
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
      case GoalEventKind.waitSpotBlocked:
        return '대기 장소가 막혔습니다';
      case GoalEventKind.waitExpired:
        return '대기 시간이 끝났습니다';
      default:
        return '주행 알림';
    }
  }

  /// 팝업 본문. **무슨 일이 일어났는지와 다음에 할 일을 함께 적습니다.**
  ///
  /// 사유 문자열만 보여주면 관리자가 다음 행동을 모릅니다.
  ///
  /// 한 줄에 문장 하나, 최대 세 줄입니다(2026-09-30 사용자 결정). 목적지 이름과
  /// 사유는 본문에 섞지 않고 [destinationLabel]·[reason] 으로 팝업 아래 칸에
  /// 따로 보입니다 — 이름이 길어도 본문 줄이 흔들리지 않고 '(으)로' 같은 조사
  /// 문제도 없습니다. 줄은 `\n` 으로 직접 나눕니다. 마침표 뒤 공백으로 나누면
  /// 짧은 문장('비카가 관리자를 호출했습니다.')이 이웃 줄에 붙어 버립니다.
  String get description {
    if (isWaitSpotTry && kind == GoalEventKind.failed) {
      return '대기 장소까지 가지 못했습니다.\n'
          '대기 장소 주변이 막혔는지, 벽에 너무 붙었는지 확인해 주세요.';
    }
    switch (kind) {
      case GoalEventKind.failed:
        // 마지막 줄은 로봇이 이용자에게 하는 안내와 짝입니다. 주행이 실패하면
        // 이용자는 그 자리에 남으므로 로봇이 관리자를 부릅니다 — 관리자 화면도
        // 같은 사실을 알아야 사람이 기다리고 있다는 것을 압니다.
        return '목적지까지 주행에 실패했습니다.\n'
            '로봇 주변이 막혔거나 위치가 어긋났는지 확인해 주세요.\n'
            '비카가 관리자를 호출했습니다.';
      case GoalEventKind.rejected:
        // 로봇이 보내는 사유는 둘뿐입니다 — "Nav2 goal rejected" 와
        // "이전 goal 취소가 아직 처리 중입니다." 둘 다 잠시 뒤 다시 하면 됩니다.
        return '주행 요청을 로봇이 받지 않았습니다.\n'
            '목적지가 지도 밖이거나 갈 수 없는 자리인지 확인해 주세요.\n'
            '잠시 뒤 다시 요청해 주세요.';
      case GoalEventKind.canceled:
        return '목적지로 가던 주행을 취소했습니다.\n'
            '로봇은 그 자리에 멈춰 있습니다.';
      case GoalEventKind.returnHomeFailed:
        return '홈까지 주행에 실패했습니다.\n'
            '로봇 주변이 막혔거나 홈 위치가 갈 수 없는 자리인지 확인해 주세요.\n'
            '지도 설정에서 홈 위치를 다시 지정할 수 있습니다.';
      case GoalEventKind.returnHomeCanceled:
        return '홈으로 가던 주행을 취소했습니다.\n'
            '로봇은 그 자리에 멈춰 있습니다.';
      case GoalEventKind.waitSpotBlocked:
        return '로봇이 대기 장소에 들어가지 못했습니다.\n'
            '목적지 앞으로 돌아가 그곳에서 기다립니다.';
      case GoalEventKind.waitExpired:
        return '사용자가 돌아오지 않아 로봇이 홈으로 돌아갑니다.';
      default:
        return reason;
    }
  }

  /// 팝업 아래 칸들(라벨, 값). 비어 있는 값은 뺍니다.
  ///
  /// 대기 알림은 목업 10·11번의 칸을 씁니다 — 막힘은 목적지·대기 장소·사유, 만료는
  /// 목적지·기다린 곳·대기 시간(사유 칸 없음). 그 밖은 지금처럼 목적지·사유입니다.
  List<(String, String)> get detailRows {
    final name = destinationLabel;
    final rows = <(String, String)>[];
    void add(String label, String value) {
      if (value.isNotEmpty) {
        rows.add((label, value));
      }
    }

    switch (kind) {
      case GoalEventKind.waitSpotBlocked:
        add('목적지', name);
        add('대기 장소', name.isEmpty ? '' : '$name-대기');
        add('사유', reason);
      case GoalEventKind.waitExpired:
        add('목적지', name);
        add(
          '기다린 곳',
          name.isEmpty
              ? ''
              : waitPlace == 'spot'
                  ? '$name-대기'
                  : '$name 앞',
        );
        add('대기 시간', waitMinutes > 0 ? '$waitMinutes분' : '');
      default:
        add('목적지', name);
        add('사유', reason);
    }
    return rows;
  }

  /// 팝업 아래 '목적지' 칸에 보일 이름. 홈 복귀는 카탈로그에 없어 이름이 비어
  /// 오므로 '홈'으로 적습니다. 이름도 없고 홈도 아니면 빈 문자열이고, 그때는
  /// 팝업이 칸을 그리지 않습니다.
  String get destinationLabel {
    if (isHomeReturn) {
      return '홈';
    }
    return destinationName;
  }
}
