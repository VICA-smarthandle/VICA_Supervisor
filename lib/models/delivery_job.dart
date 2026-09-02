// 이 파일은 물류 배송 한 건을 표현합니다.
//
// 배송은 로봇의 상태가 아니라 **앱의 기억**입니다. 로봇은 "어느 목적지로 간다"만
// 알고, 그 주행이 배송인지 안내인지는 모릅니다(Mission Manager 는 goal 이벤트에
// 목적지 id 와 이름만 싣습니다). 그래서 "이번 주행이 끝나면 이 번호로 문자를
// 보낸다"는 앱이 들고 있어야 하고, 앱이 닫히면 함께 사라집니다 — 그것은
// 의도된 한계입니다. 문자를 보내는 것도 앱(관리자 폰)이기 때문입니다.
import '../services/delivery_notifier.dart';
import 'location_point.dart';

/// 배송이 지금 어느 단계인가.
enum DeliveryPhase {
  /// 주행 요청이 수락됐고 로봇이 가는 중.
  driving('배송 중'),

  /// 로봇이 목적지에 섰다. 문자를 보낼 차례이거나 보냈다.
  arrived('도착'),

  /// 주행이 실패·취소·비상정지로 끝났다. 문자는 보내지 않는다.
  aborted('중단');

  const DeliveryPhase(this.label);

  final String label;
}

/// 출발한 순간 로봇이 서 있던 자리(map 좌표, yaw 는 도).
///
/// 나중에 "출발지로 복귀"가 씁니다. 출발할 때 로봇 상태를 못 받고 있었으면
/// 이 값이 없고, 그때는 홈 복귀로 대신합니다.
class DeliveryOrigin {
  const DeliveryOrigin({required this.x, required this.y, required this.yaw});

  final double x;
  final double y;
  final double yaw;
}

class DeliveryJob {
  const DeliveryJob({
    required this.destination,
    required this.startedAt,
    this.origin,
    this.phase = DeliveryPhase.driving,
    this.arrivedAt,
    this.notified = false,
    this.abortReason = '',
  });

  /// 어디로 가는가. 연락처는 이 안에 있습니다([LocationPoint.contactPhone]).
  ///
  /// 목록의 사본이 아니라 출발 순간의 값을 들고 있습니다. 주행 중에 관리자가
  /// 장소 정보를 고쳐도 이번 배송의 번호는 바뀌지 않습니다 — 바뀌면 "누구에게
  /// 보냈는지"를 되짚을 수 없습니다.
  final LocationPoint destination;

  final DateTime startedAt;
  final DeliveryOrigin? origin;

  final DeliveryPhase phase;
  final DateTime? arrivedAt;

  /// 도착 문자를 이미 보냈는가(또는 보내려고 했는가).
  ///
  /// 같은 도착 이벤트가 두 번 와도 문자는 한 번만 나가야 합니다. 이 표시가
  /// 그 빗장입니다.
  final bool notified;

  final String abortReason;

  bool get isActive => phase == DeliveryPhase.driving;

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

  DeliveryJob copyWith({
    DeliveryPhase? phase,
    DateTime? arrivedAt,
    bool? notified,
    String? abortReason,
  }) {
    return DeliveryJob(
      destination: destination,
      startedAt: startedAt,
      origin: origin,
      phase: phase ?? this.phase,
      arrivedAt: arrivedAt ?? this.arrivedAt,
      notified: notified ?? this.notified,
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
