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
      confirmPrompt: json['confirm_prompt'] as String? ??
          (name.isEmpty ? '' : '$name로 안내해드릴까요?'),
      arrivalMessage: json['arrival_message'] as String? ??
          (name.isEmpty ? '' : '$name 앞에 도착했습니다.'),
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
    };
  }
}
