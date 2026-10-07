// 이 파일은 mapping_supervisor_node 가 1 Hz 로 보내는 매핑 세션 상태를 표현합니다.
//
// 앱이 "지금 시작해도 되나 / 저장해도 되나 / 모드를 바꿔도 되나"를 이것으로 판정합니다.
// 젯슨에서 프로세스를 실제로 소유한 노드가 보내는 값이라, 노드 목록을 훑어 추측하는
// 것보다 정확합니다.
enum MappingState {
  idle('idle', '대기'),
  starting('starting', '시작하는 중'),
  mapping('mapping', '지도 그리는 중'),
  stopping('stopping', '정리하는 중'),
  saving('saving', '저장하는 중'),
  error('error', '오류');

  const MappingState(this.value, this.label);

  final String value;
  final String label;

  static MappingState fromValue(String raw) {
    for (final state in MappingState.values) {
      if (state.value == raw) {
        return state;
      }
    }
    return MappingState.error;
  }
}

/// 지도를 저장할 때 바르게 세웠는지(2026-10-07). 감독 노드가 저장 스크립트의
/// 결과 줄(map_align 의 VICA_ALIGN)을 읽어 상태의 save_align 으로 보냅니다.
/// 완료 단계의 결과 한 줄(목업 14번)이 이것으로 정해집니다.
enum MapAlignResult {
  /// 돌려서 다시 저장했다.
  rotated('rotated'),

  /// 정렬을 골랐지만 2° 미만이라 그대로 뒀다.
  small('small'),

  /// 벽 방향을 찾지 못해 그대로 뒀다.
  noWalls('no_walls'),

  /// '정렬하지 않고 저장'을 골랐다.
  notRequested('not_requested'),

  /// 돌리다 실패해 그대로 뒀다(지도 자체는 저장됐다).
  failed('failed');

  const MapAlignResult(this.value);

  final String value;

  static MapAlignResult? fromValue(Object? raw) {
    for (final result in MapAlignResult.values) {
      if (result.value == raw) {
        return result;
      }
    }
    return null;
  }
}

class MapSaveAlign {
  const MapSaveAlign({
    required this.result,
    this.tiltDeg,
    this.rotatedDeg = 0,
  });

  final MapAlignResult result;

  /// 저장할 때 잰 기울기(도, 반시계 양수). 못 쟀으면 null.
  final double? tiltDeg;

  /// 실제로 돌린 각도(도). 돌리지 않았으면 0.
  final double rotatedDeg;

  /// 완료 단계에 보일 결과 한 줄. 문구는 목업 14번과 같습니다.
  String get sentence {
    String deg(double value) => value.abs().toStringAsFixed(1);
    final tilt = tiltDeg;
    return switch (result) {
      MapAlignResult.rotated => '지도를 ${deg(rotatedDeg)}° 돌려 바르게 세웠습니다.',
      MapAlignResult.small => tilt == null
          ? '기울기가 작아 돌리지 않고 그대로 저장했습니다.'
          : '기울기가 ${deg(tilt)}°라 돌리지 않고 그대로 저장했습니다.',
      MapAlignResult.noWalls => '벽 방향을 찾지 못해 돌리지 않고 그대로 저장했습니다.',
      MapAlignResult.notRequested => tilt == null
          ? '정렬하지 않고 그대로 저장했습니다.'
          : '정렬하지 않고 그대로 저장했습니다(기울기 ${deg(tilt)}°).',
      MapAlignResult.failed => '지도를 돌리지 못해 그대로 저장했습니다.',
    };
  }

  /// 모르는 값·옛 노드(키 없음)면 null 이고, 그때 완료 단계는 결과 줄을 안 보입니다.
  static MapSaveAlign? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final result = MapAlignResult.fromValue(raw['result']);
    if (result == null) {
      return null;
    }
    return MapSaveAlign(
      result: result,
      tiltDeg: (raw['tilt_deg'] as num?)?.toDouble(),
      rotatedDeg: (raw['rotated_deg'] as num?)?.toDouble() ?? 0,
    );
  }
}

class MappingStatus {
  const MappingStatus({
    required this.state,
    required this.detail,
    required this.mapId,
    this.mapName = '',
    required this.nav2Running,
    required this.mappingRunning,
    required this.duplicated,
    required this.prerequisitesMissing,
    required this.receivedAt,
    this.saveAlign,
  });

  final MappingState state;
  final String detail;
  final String mapId;

  /// 사람이 적은 지도 이름(한글 가능). 감독 노드가 저장할 때 함께 보냅니다
  /// (2026-09-04). 옛 노드는 안 보내며 그때는 빈 값이라 id 를 보여줍니다.
  final String mapName;

  String get displayName => mapName.isEmpty ? mapId : mapName;
  final bool nav2Running;
  final bool mappingRunning;
  final List<String> duplicated;
  final List<String> prerequisitesMissing;
  final DateTime receivedAt;

  /// 마지막 저장을 바르게 세웠는지. 저장 전·옛 노드면 null 입니다.
  final MapSaveAlign? saveAlign;

  /// 지금 시작 버튼을 누를 수 있는가. 판정 이유는 노드가 detail 로 알려줍니다.
  bool get canStart =>
      state == MappingState.idle &&
      !nav2Running &&
      duplicated.isEmpty &&
      prerequisitesMissing.isEmpty;

  /// 진행 중이라 모드를 바꾸면 안 되는 상태인가.
  bool get busy =>
      state == MappingState.starting ||
      state == MappingState.mapping ||
      state == MappingState.stopping ||
      state == MappingState.saving;

  bool get canSave => state == MappingState.mapping;

  bool get canStop => state != MappingState.idle;

  static List<String> _stringList(Object? value) {
    if (value is! List) {
      return const [];
    }
    return value.whereType<String>().toList(growable: false);
  }

  factory MappingStatus.fromJson(Map<String, Object?> json) {
    return MappingStatus(
      state: MappingState.fromValue(json['state'] as String? ?? ''),
      detail: json['detail'] as String? ?? '',
      mapId: json['map_id'] as String? ?? '',
      mapName: json['map_name'] as String? ?? '',
      nav2Running: json['nav2_running'] == true,
      mappingRunning: json['mapping_running'] == true,
      duplicated: _stringList(json['duplicated']),
      prerequisitesMissing: _stringList(json['prerequisites_missing']),
      receivedAt: DateTime.now(),
      saveAlign: MapSaveAlign.fromJson(json['save_align']),
    );
  }
}
