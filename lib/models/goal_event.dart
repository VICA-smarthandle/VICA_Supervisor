/// goal 에 일어난 일.
enum GoalEventKind {
  sent('goal_sent'),
  accepted('goal_accepted'),
  rejected('goal_rejected'),
  succeeded('goal_succeeded'),
  failed('goal_failed'),
  canceled('goal_canceled'),
  paused('goal_paused'),
  emergencyStopped('emergency_stopped'),

  returnHomeSent('return_home_sent'),
  returnHomeSucceeded('return_home_succeeded'),
  returnHomeFailed('return_home_failed'),
  returnHomeCanceled('return_home_canceled'),

  /// 취소를 눌렀는데 취소할 주행이 없었다 — 지금은 대기라는 통보입니다.
  stateIdle('state_idle'),

  /// 대기 장소로 가는 주행을 Nav2 가 실패로 끝냈다 — 로봇은 목적지로 돌아가 기다립니다.
  waitSpotBlocked('wait_spot_blocked'),

  /// 대기 시간이 끝났다 — 로봇은 "대기 시간이 종료되어…"를 말하고 홈으로 갑니다.
  waitExpired('wait_expired'),

  /// 사용자가 도움을 청했다. 관리자가 확인할 때까지 10초마다 같은 help_id 로 다시 옵니다.
  helpRequested('help_requested'),

  /// 관리자가(어느 화면에서든) 확인했다 — 떠 있는 도움 팝업을 닫습니다.
  helpAcknowledged('help_acknowledged'),

  /// 사용자가 취소했거나 로봇이 다시 출발했다 — 떠 있는 도움 팝업을 닫습니다.
  helpCanceled('help_canceled'),

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
  bool get needsPopup =>
      this == GoalEventKind.failed ||
      this == GoalEventKind.rejected ||
      this == GoalEventKind.canceled ||
      this == GoalEventKind.returnHomeFailed ||
      this == GoalEventKind.returnHomeCanceled ||
      this == GoalEventKind.waitSpotBlocked ||
      this == GoalEventKind.waitExpired;

  /// 주행이 실패로 끝났는가. 취소는 사람이 시킨 일이라 실패가 아닙니다.
  bool get isFailure =>
      this == GoalEventKind.failed ||
      this == GoalEventKind.rejected ||
      this == GoalEventKind.returnHomeFailed ||
      this == GoalEventKind.waitSpotBlocked;

  /// 대기 알림인가. 뒤이은 출발(홈 복귀 등)이 이 팝업을 거두면 안 됩니다 —
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
    this.waitPlace = '',
    this.waitMinutes = -1,
    this.delivery = false,
    this.robotStamp = '',
    this.helpId = '',
    this.place = '',
    this.robotX,
    this.robotY,
  });

  /// 앱이 붙이는 고유값입니다. 같은 실패가 두 번 와도 팝업을 각각 띄우기 위해
  final String id;

  final GoalEventKind kind;
  final String destinationName;

  /// 로봇이 실어 보낸 목적지 id. 배송이 "내 주행이 끝났나"를 이름이 아니라
  final String locationId;

  /// 로봇이 적어 보낸 사유입니다. 비어 있을 수 있습니다.
  final String reason;

  final String mapId;

  /// 대기 알림의 기다린 곳 — `spot`(대기 장소)·`destination`(목적지 앞). 그 밖은 빈 값.
  final String waitPlace;

  /// 대기 알림의 대기 시간(분). 모르면 -1.
  final int waitMinutes;

  /// 배송 요청으로 간 목적지의 도착인가(2026-10-10). 미션이 그 도착에만 싣습니다. 관리자 유심
  final bool delivery;

  /// 로봇이 이벤트에 적은 시각(초 단위 문자열). 같은 도착을 화면끼리 맞추는 열쇠입니다 —
  final String robotStamp;

  /// 도움 요청 하나의 식별자(uuid4). 재전송·확인·취소가 모두 이 값을 씁니다. 그 밖은 빈 값.
  final String helpId;

  /// 도움 요청 때 로봇이 있는 곳의 문장("407호 앞", "407호와 화장실 사이"). 모르면 빈 값.
  final String place;

  /// 도움 요청 때 로봇의 지도 좌표(m, AMCL). 모르면 null. 기존 x·y 는 목적지 좌표 칸이라 따로 둡니다.
  final double? robotX;
  final double? robotY;

  /// 도움 요청 사건인가(요청·확인·취소).
  bool get isHelp =>
      kind == GoalEventKind.helpRequested ||
      kind == GoalEventKind.helpAcknowledged ||
      kind == GoalEventKind.helpCanceled;

  /// 관리자에게 팝업으로 알려야 하는가. 판정은 [GoalEventKind] 가 합니다.
  bool get needsPopup => kind.needsPopup;

  /// 주행이 실패로 끝났는가. 취소는 사람이 시킨 일이라 실패가 아닙니다.
  bool get isFailure => kind.isFailure;

  bool get isHomeReturn => kind.isHomeReturn;

  /// 지도 설정 '대기 장소로 가보기'의 주행인가. 미션은 이 주행의 목적지 id 를
  bool get isWaitSpotTry => locationId.startsWith('wait_spot:');

  factory GoalEvent.fromJson(Map<String, Object?> json, {required String id}) {
    return GoalEvent(
      id: id,
      kind: GoalEventKind.fromWire(json['event'] as String?),
      destinationName: (json['name'] as String?)?.trim() ?? '',
      locationId: ((json['location_id'] ?? json['destination_id']) as String?)
              ?.trim() ??
          '',
      reason: (json['reason'] as String?)?.trim() ?? '',
      mapId: (json['map_id'] as String?)?.trim() ?? '',
      waitPlace: (json['wait_place'] as String?)?.trim() ?? '',
      waitMinutes: (json['wait_minutes'] as num?)?.toInt() ?? -1,
      delivery: json['delivery'] == true,
      robotStamp: (json['timestamp'] as String?)?.trim() ?? '',
      helpId: (json['help_id'] as String?)?.trim() ?? '',
      place: (json['place'] as String?)?.trim() ?? '',
      robotX: (json['robot_x'] as num?)?.toDouble(),
      robotY: (json['robot_y'] as num?)?.toDouble(),
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
  String get description {
    if (isWaitSpotTry && kind == GoalEventKind.failed) {
      return '대기 장소까지 가지 못했습니다.\n'
          '대기 장소 주변이 막혔는지, 벽에 너무 붙었는지 확인해 주세요.';
    }
    switch (kind) {
      case GoalEventKind.failed:
        return '목적지까지 주행에 실패했습니다.\n'
            '로봇 주변이 막혔거나 위치가 어긋났는지 확인해 주세요.\n'
            '비카가 관리자를 호출했습니다.';
      case GoalEventKind.rejected:
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
  String get destinationLabel {
    if (isHomeReturn) {
      return '홈';
    }
    return destinationName;
  }
}
