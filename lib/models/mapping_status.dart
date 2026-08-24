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

class MappingStatus {
  const MappingStatus({
    required this.state,
    required this.detail,
    required this.mapId,
    required this.nav2Running,
    required this.mappingRunning,
    required this.duplicated,
    required this.prerequisitesMissing,
    required this.receivedAt,
  });

  final MappingState state;
  final String detail;
  final String mapId;
  final bool nav2Running;
  final bool mappingRunning;
  final List<String> duplicated;
  final List<String> prerequisitesMissing;
  final DateTime receivedAt;

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
      nav2Running: json['nav2_running'] == true,
      mappingRunning: json['mapping_running'] == true,
      duplicated: _stringList(json['duplicated']),
      prerequisitesMissing: _stringList(json['prerequisites_missing']),
      receivedAt: DateTime.now(),
    );
  }
}
