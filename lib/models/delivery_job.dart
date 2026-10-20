import '../services/delivery_notifier.dart';
import 'location_point.dart';

/// 도착 뒤 홈으로 출발하기까지 기다리는 시간. 받는 사람이 물건을 꺼낼 여유입니다.
const deliveryReturnDelay = Duration(minutes: 2);

/// 이 화면이 문자를 못 보낼 때(웹·유심 없는 폰) 관리자 유심 폰이 대신 보낸 결과를 기다리는
const deliverySmsRelayWait = Duration(seconds: 30);

/// 그 시간 안에 결과가 오지 않았을 때 빨간 팝업의 사유(2026-10-10 사용자 승인 문구).
const deliverySmsNoReplyDetail =
    '문자를 보내지 못했습니다. 관리자 폰 앱이 켜져 있는지 확인하고, 직접 연락하세요.';

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
  unconfirmed('확인 필요');

  const DeliveryPhase(this.label);

  final String label;

  /// 배송 표시를 지워도 되는가. 로봇이 움직이는 중에는 지우지 않습니다 — 기억만
  bool get isFinished =>
      this == DeliveryPhase.completed || this == DeliveryPhase.aborted;

  /// 저장소에서 읽을 때. 모르는 이름은 '중단'으로 친다 — 되살린 배송으로
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
  final LocationPoint destination;

  final DateTime startedAt;

  final DeliveryPhase phase;
  final DateTime? arrivedAt;

  /// 도착 문자를 이미 보냈는가(또는 보내려고 했는가).
  final bool notified;

  /// 홈으로 출발할 예정 시각. 도착 뒤 [deliveryReturnDelay] 뒤입니다.
  final DateTime? returnAt;

  /// 홈 복귀가 거부·실패했을 때 그 사유. 관리자가 다시 시도하거나 지울 수 있게
  final String returnNote;

  final String abortReason;

  /// 목적지로 가는 중인가.
  bool get isActive => phase == DeliveryPhase.driving;

  /// 도착해서 복귀를 기다리는 중인가(예정 시각이 살아 있는가).
  bool get isWaitingToReturn =>
      phase == DeliveryPhase.arrived && returnAt != null;

  /// 로봇이 보낸 goal 이벤트가 이 배송의 것인가.
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
