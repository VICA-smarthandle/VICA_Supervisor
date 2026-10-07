// 이 파일은 지도 위 목적지와 destinations.yaml에 대응할 상세 데이터를 표현합니다.

/// 목적지에 딸린 대기 장소(2026-10-07). 사용자가 "기다려 줘"라고 하면 로봇이
/// 손잡이를 놓은 뒤 혼자 이 자리로 가서 기다립니다.
///
/// 목적지가 아니라 목적지 안의 칸입니다 — LLM·배송·원격 주행 목록에 나오지 않고,
/// 목적지를 지우면 함께 지워집니다. 파일 키는 `wait_spot{x, y, yaw, side}` 이고
/// 로봇의 vica_destination_manager.storage.normalize_wait_spot 과 같은 모양입니다.
class WaitSpot {
  const WaitSpot({
    required this.x,
    required this.y,
    required this.yaw,
    required this.side,
  });

  final double x;
  final double y;

  /// 나가는 방향(도). 로봇은 이쪽을 보고 서서 다음 출발 때 돌지 않습니다.
  final double yaw;

  /// 입구를 바라볼 때 대기 장소가 어느 쪽인가 — `right`·`left`·`across`.
  /// 앱이 저장할 때 계산해 보내고, 로봇은 다시 계산하지 않고 멘트에 씁니다
  /// ("입구 오른쪽에서 기다리겠습니다"). 화면 글자와 로봇 말이 같아야 합니다.
  final String side;

  static const sides = ['right', 'left', 'across'];

  /// 멘트·화면에 쓰는 말. 로봇의 mission_logic.WAIT_PLACE_PHRASES 와 같습니다.
  String get placePhrase => waitPlacePhrase(side);

  static WaitSpot? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final x = (raw['x'] as num?)?.toDouble();
    final y = (raw['y'] as num?)?.toDouble();
    final side = (raw['side'] as String?)?.trim().toLowerCase() ?? '';
    if (x == null || y == null || !sides.contains(side)) {
      return null;
    }
    return WaitSpot(
      x: x,
      y: y,
      yaw: (raw['yaw'] as num?)?.toDouble() ?? 0,
      side: side,
    );
  }

  Map<String, Object> toJson() => {'x': x, 'y': y, 'yaw': yaw, 'side': side};
}

/// 대기 장소 방향 말. 로봇의 mission_logic.WAIT_PLACE_PHRASES 와 글자까지 같아야
/// 합니다 — 관리자가 화면에서 본 말을 로봇이 그대로 합니다.
String waitPlacePhrase(String side) {
  switch (side) {
    case 'right':
      return '입구 오른쪽';
    case 'left':
      return '입구 왼쪽';
    case 'across':
      return '입구 맞은편';
    default:
      return '';
  }
}

class LocationPoint {
  const LocationPoint({
    required this.locationId,
    required this.mapId,
    required this.name,
    required this.x,
    required this.y,
    required this.yaw,
    this.aliases = const [],
    this.category1 = '',
    this.category2 = '',
    this.building = '',
    this.floor = 0,
    this.owner = '',
    this.authorization = 'public',
    this.isApproachable = true,
    this.unavailableReason = '',
    this.frameId = 'map',
    this.confirmPrompt = '',
    this.arrivalMessage = '',
    this.contactPhone = '',
    this.doorYaw,
    this.waitSpot,
  });

  final String locationId;
  final String mapId;
  final String name;
  final List<String> aliases;
  final String category1;
  final String category2;
  final String building;
  final int floor;
  final String owner;
  final String authorization;
  final bool isApproachable;
  final String unavailableReason;
  final String frameId;
  final double x;
  final double y;
  final double yaw;
  final String confirmPrompt;
  final String arrivalMessage;

  /// 물류 배송 도착 문자를 받을 휴대폰 번호. 숫자만('01012345678') 들어 있고
  /// 비어 있으면 배송 대상이 아닙니다. 화면에는 core/contact_phone.dart 로
  /// 가려서 보여줍니다. 로봇은 이 값을 읽지 않습니다.
  final String contactPhone;

  /// 입구 방향(도, 지도 기준). 도착 멘트 "화장실은 오른쪽에 있습니다"의 계산과
  /// 배송 도착 방향에 같이 씁니다. 옛 장소는 비어 있습니다(null).
  final double? doorYaw;

  /// 대기 장소. 지정하지 않았으면 null — 로봇은 목적지에서 그대로 기다립니다.
  final WaitSpot? waitSpot;

  /// 목록에 보이는 대기 장소 이름("화장실 입구-대기"). 로봇의 goal 이름과 같습니다.
  String get waitSpotName => '$name-대기';

  /// 배송 문자를 보낼 수 있는 장소인가.
  bool get canReceiveDelivery => contactPhone.isNotEmpty;

  factory LocationPoint.fromJson(
      Map<String, Object?> json, String fallbackMapId) {
    final name = json['name'] as String? ?? '';
    final rawAliases = json['aliases'];
    final rawPose = json['pose'];
    final pose = rawPose is Map
        ? rawPose.map((key, value) => MapEntry(key.toString(), value))
        : const <String, Object?>{};
    return LocationPoint(
      locationId:
          (json['id'] as String?) ?? (json['location_id'] as String?) ?? '',
      mapId: json['map_id'] as String? ?? fallbackMapId,
      name: name,
      aliases: rawAliases is List
          ? rawAliases.map((value) => value.toString()).toList()
          : name.isEmpty
              ? const []
              : [name],
      category1:
          (json['category1'] as String?) ?? (json['category'] as String?) ?? '',
      category2: json['category2'] as String? ?? '',
      building: json['building'] as String? ?? '',
      floor: (json['floor'] as num?)?.toInt() ?? 0,
      owner: json['owner'] as String? ?? '',
      authorization: json['authorization'] as String? ?? 'public',
      isApproachable: json['is_approachable'] as bool? ?? true,
      unavailableReason: json['unavailable_reason'] as String? ?? '',
      frameId: pose['frame_id'] as String? ?? 'map',
      x: (pose['x'] as num?)?.toDouble() ??
          (json['x'] as num?)?.toDouble() ??
          0,
      y: (pose['y'] as num?)?.toDouble() ??
          (json['y'] as num?)?.toDouble() ??
          0,
      yaw: (pose['yaw'] as num?)?.toDouble() ??
          (json['yaw'] as num?)?.toDouble() ??
          0,
      // 멘트는 앱이 만들지 않습니다(2026-10-07). 비어 있으면 로봇이 조사를 맞춰
      // 채웁니다 — '$name로'는 받침 있는 이름에서 틀렸습니다.
      confirmPrompt: json['confirm_prompt'] as String? ?? '',
      arrivalMessage: json['arrival_message'] as String? ?? '',
      // 옛 파일에는 이 키가 없습니다. 없으면 빈 값이고 그것은 오류가 아닙니다.
      contactPhone: (json['contact_phone'] as String?)?.trim() ?? '',
      // 옛 파일에는 두 칸이 없습니다. 없으면 null 이고 오류가 아닙니다.
      doorYaw: (json['door_yaw'] as num?)?.toDouble(),
      waitSpot: WaitSpot.fromJson(json['wait_spot']),
    );
  }

  /// 칸 몇 개만 바꾼 사본. 대기 장소를 빼려면 [clearWaitSpot] 을 씁니다 —
  /// null 을 넘기는 것과 '안 바꿈'을 가르기 위해서입니다.
  LocationPoint copyWith({
    double? x,
    double? y,
    double? yaw,
    double? doorYaw,
    WaitSpot? waitSpot,
    bool clearWaitSpot = false,
  }) {
    return LocationPoint(
      locationId: locationId,
      mapId: mapId,
      name: name,
      x: x ?? this.x,
      y: y ?? this.y,
      yaw: yaw ?? this.yaw,
      aliases: aliases,
      category1: category1,
      category2: category2,
      building: building,
      floor: floor,
      owner: owner,
      authorization: authorization,
      isApproachable: isApproachable,
      unavailableReason: unavailableReason,
      frameId: frameId,
      confirmPrompt: confirmPrompt,
      arrivalMessage: arrivalMessage,
      contactPhone: contactPhone,
      doorYaw: doorYaw ?? this.doorYaw,
      waitSpot: clearWaitSpot ? null : (waitSpot ?? this.waitSpot),
    );
  }

  Map<String, Object> toJson() {
    return {
      'id': locationId,
      'name': name,
      'aliases': aliases,
      'category1': category1,
      'category2': category2,
      'building': building,
      'floor': floor,
      'owner': owner,
      'authorization': authorization,
      'is_approachable': isApproachable,
      'unavailable_reason': unavailableReason,
      'pose': {
        'frame_id': frameId,
        'x': x,
        'y': y,
        'yaw': yaw,
      },
      'confirm_prompt': confirmPrompt,
      'arrival_message': arrivalMessage,
      'contact_phone': contactPhone,
      // 선택 칸은 있을 때만 싣습니다. 로봇 저장 노드도 없으면 키를 쓰지 않습니다.
      if (doorYaw != null) 'door_yaw': doorYaw!,
      if (waitSpot != null) 'wait_spot': waitSpot!.toJson(),
    };
  }
}
