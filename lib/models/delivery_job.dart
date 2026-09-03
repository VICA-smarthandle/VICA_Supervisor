// 이 파일은 물류 배송 한 건을 표현합니다.
//
// 배송은 로봇의 상태가 아니라 **앱의 기억**입니다. 로봇은 "어느 목적지로 간다"만
// 알고, 그 주행이 배송인지 안내인지는 모릅니다(Mission Manager 는 goal 이벤트에
// 목적지 id 와 이름만 싣습니다). 그래서 "이번 주행이 끝나면 이 번호로 문자를
// 보낸다"는 앱이 들고 있어야 하고, 앱이 닫히면 함께 사라집니다 — 그것은
// 의도된 한계입니다. 문자를 보내는 것도 앱(관리자 폰)이기 때문입니다.
//
// 도착 뒤에는 잠시 기다렸다가 **홈으로** 돌아갑니다(2026-09-02 사용자 결정).
// 출발했던 자리로 되돌아가는 안은 버렸습니다 — 배송은 일회성일 수 있고, 홈 복귀는
// 기존 서비스 그대로라 로봇 쪽에 새 문을 낼 필요가 없으며, 관리자는 언제든 앱에서
// 복귀를 취소하고 다시 부를 수 있습니다.
import '../services/delivery_notifier.dart';
import 'location_point.dart';

/// 도착 뒤 홈으로 출발하기까지 기다리는 시간. 받는 사람이 물건을 꺼낼 여유입니다.
///
/// 시험하기 좋게 2분으로 시작합니다(사용자 결정). 늘릴 때는 이 값만 바꿉니다.
const deliveryReturnDelay = Duration(minutes: 2);

/// 배송이 지금 어느 단계인가.
enum DeliveryPhase {
  /// 주행 요청이 수락됐고 로봇이 가는 중.
  driving('배송 중'),

  /// 로봇이 목적지에 섰다. 문자를 보냈고, 홈 복귀까지 기다리는 중.
  arrived('도착'),

  /// 홈으로 돌아가는 중.
  returning('홈 복귀 중'),

  /// 홈에 도착했다. 배송 한 건이 끝났다.
  completed('완료'),

  /// 목적지로 가던 주행이 실패·취소·비상정지로 끝났다. 문자는 보내지 않는다.
  aborted('중단'),

  /// 앱이 꺼진 사이 주행이 끝나 결과를 못 봤다(2026-09-03). 문자도 아직 안
  /// 나갔다. 관리자가 로봇이 문 앞에 있는지 눈으로 보고 '도착 처리'(문자 →
  /// 복귀)나 '지우기'를 고른다. 앱이 대신 짐작해 문자를 보내지는 않는다.
  unconfirmed('확인 필요');

  const DeliveryPhase(this.label);

  final String label;

  /// 배송 표시를 지워도 되는가. 로봇이 움직이는 중에는 지우지 않습니다 — 기억만
  /// 지우면 도착·복귀 결과를 화면이 못 잇습니다.
  bool get isFinished =>
      this == DeliveryPhase.completed || this == DeliveryPhase.aborted;

  /// 저장소에서 읽을 때. 모르는 이름은 '중단'으로 친다 — 되살린 배송으로
  /// 로봇이 움직이는 일은 없어야 한다.
  static DeliveryPhase fromName(String? name) {
    for (final phase in values) {
      if (phase.name == name) {
        return phase;
      }
    }
    return DeliveryPhase.aborted;
  }
}

class DeliveryJob {
  const DeliveryJob({
    required this.destination,
    required this.startedAt,
    this.phase = DeliveryPhase.driving,
    this.arrivedAt,
    this.notified = false,
    this.returnAt,
    this.returnNote = '',
    this.abortReason = '',
  });

  /// 어디로 가는가. 연락처는 이 안에 있습니다([LocationPoint.contactPhone]).
  ///
  /// 목록의 사본이 아니라 출발 순간의 값을 들고 있습니다. 주행 중에 관리자가
  /// 장소 정보를 고쳐도 이번 배송의 번호는 바뀌지 않습니다 — 바뀌면 "누구에게
  /// 보냈는지"를 되짚을 수 없습니다.
  final LocationPoint destination;

  final DateTime startedAt;

  final DeliveryPhase phase;
  final DateTime? arrivedAt;

  /// 도착 문자를 이미 보냈는가(또는 보내려고 했는가).
  ///
  /// 같은 도착 이벤트가 두 번 와도 문자는 한 번만 나가야 합니다. 이 표시가
  /// 그 빗장입니다.
  final bool notified;

  /// 홈으로 출발할 예정 시각. 도착 뒤 [deliveryReturnDelay] 뒤입니다.
  /// 관리자가 복귀를 취소하면 null 이 됩니다.
  final DateTime? returnAt;

  /// 홈 복귀가 거부·실패했을 때 그 사유. 관리자가 다시 시도하거나 지울 수 있게
  /// 화면에 보여줍니다.
  final String returnNote;

  final String abortReason;

  /// 목적지로 가는 중인가.
  bool get isActive => phase == DeliveryPhase.driving;

  /// 도착해서 복귀를 기다리는 중인가(예정 시각이 살아 있는가).
  bool get isWaitingToReturn =>
      phase == DeliveryPhase.arrived && returnAt != null;

  /// 로봇이 보낸 goal 이벤트가 이 배송의 것인가.
  ///
  /// **이름이 아니라 id 로 맞춥니다.** 같은 이름의 장소가 둘이면 이름 비교는
  /// 엉뚱한 사람에게 문자를 보냅니다. 옛 로봇이 id 를 안 실어 보낼 때만
  /// 이름으로 물러섭니다.
  bool matches({required String locationId, required String name}) {
    if (locationId.isNotEmpty) {
      return locationId == destination.locationId;
    }
    return name.isNotEmpty && name == destination.name;
  }

  /// 기기 저장소에 남길 모양. 앱을 껐다 켜도 이어받기 위해서다(2026-09-03).
  Map<String, Object?> toJson() {
    return {
      'destination': destination.toJson(),
      'started_at': startedAt.toIso8601String(),
      'phase': phase.name,
      'arrived_at': arrivedAt?.toIso8601String(),
      'notified': notified,
      'return_at': returnAt?.toIso8601String(),
      'return_note': returnNote,
      'abort_reason': abortReason,
    };
  }

  /// 저장분을 되살린다. 목적지가 없거나 깨졌으면 null — 되살릴 것이 없다.
  static DeliveryJob? fromJson(Map<String, Object?> json) {
    final rawDestination = json['destination'];
    if (rawDestination is! Map) {
      return null;
    }
    final destination = LocationPoint.fromJson(
      rawDestination.map((key, value) => MapEntry(key.toString(), value)),
      '',
    );
    if (destination.locationId.isEmpty) {
      return null;
    }
    DateTime? time(Object? raw) =>
        raw is String ? DateTime.tryParse(raw) : null;
    return DeliveryJob(
      destination: destination,
      startedAt: time(json['started_at']) ?? DateTime.now(),
      phase: DeliveryPhase.fromName(json['phase'] as String?),
      arrivedAt: time(json['arrived_at']),
      notified: json['notified'] == true,
      returnAt: time(json['return_at']),
      returnNote: json['return_note'] as String? ?? '',
      abortReason: json['abort_reason'] as String? ?? '',
    );
  }

  DeliveryJob copyWith({
    DeliveryPhase? phase,
    DateTime? arrivedAt,
    bool? notified,
    DateTime? returnAt,
    bool clearReturnAt = false,
    String? returnNote,
    String? abortReason,
  }) {
    return DeliveryJob(
      destination: destination,
      startedAt: startedAt,
      phase: phase ?? this.phase,
      arrivedAt: arrivedAt ?? this.arrivedAt,
      notified: notified ?? this.notified,
      returnAt: clearReturnAt ? null : (returnAt ?? this.returnAt),
      returnNote: returnNote ?? this.returnNote,
      abortReason: abortReason ?? this.abortReason,
    );
  }
}

/// 도착 문자 본문.
///
/// 한글 문자 한 통은 90바이트, 한 글자에 2바이트라 **45자**가 한계입니다. 넘으면
/// 여러 조각으로 나뉘어 나가고 요금제에 따라 여러 건으로 계산될 수 있습니다.
/// 그래서 장소 이름은 45자 안에 들어갈 때만 붙입니다.
String deliveryArrivalMessage(String destinationName) {
  const base = '비카가 물건을 가지고 문 앞에 와 있습니다. 확인해주세요';
  const limit = 45;
  final name = destinationName.trim();
  if (name.isEmpty) {
    return base;
  }
  final withName = '[$name] $base';
  return withName.length <= limit ? withName : base;
}

/// 도착 문자 발송 결과를 화면에 한 번 보여주기 위한 묶음.
///
/// 팝업은 그 자리에서 닫히지만 같은 내용이 로그에도 남습니다.
class DeliveryNotice {
  const DeliveryNotice({
    required this.job,
    required this.text,
    required this.result,
  });

  final DeliveryJob job;

  /// 보낸(또는 보내려 한) 본문.
  final String text;

  final DeliveryNotifyResult result;
}
