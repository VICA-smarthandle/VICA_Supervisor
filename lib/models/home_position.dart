/// 홈을 어떻게 정했는가.
enum HomeSource {
  /// 로봇을 실제 자리에 세우고 라이다로 채점해 잡았습니다.
  robotStanding('robot_standing', '실제 자리에서 지정'),

  /// 지도를 눌러 좌표만 찍었습니다. 로봇이 거기 없었으므로 채점값이 없습니다.
  mapPick('map_pick', '지도에서 지정');

  const HomeSource(this.wire, this.label);

  /// ROS 서비스에 실어 보내는 값입니다. 젯슨의 home_storage 와 같아야 합니다.
  final String wire;

  /// 화면에 보여줄 한국어 문구입니다.
  final String label;

  static HomeSource fromWire(String? value) {
    for (final source in HomeSource.values) {
      if (source.wire == value) {
        return source;
      }
    }
    return HomeSource.mapPick;
  }
}

class HomePosition {
  const HomePosition({
    required this.x,
    required this.y,
    required this.yaw,
    required this.source,
    required this.score,
    required this.label,
    required this.visitedOk,
    required this.savedAt,
  });

  final double x;
  final double y;

  /// 도(degree) 단위입니다. destinations.yaml 의 pose 와 같은 규약입니다.
  final double yaw;

  final HomeSource source;

  /// 실제 자리에서 지정했을 때의 라이다-지도 일치도(0~100)입니다.
  final double score;

  /// 관리자가 붙인 이름입니다. 로봇은 쓰지 않습니다.
  final String label;

  /// **이 모델에서 가장 중요한 값입니다.**
  final bool visitedOk;

  /// ISO 8601 문자열입니다. 사람에게 보여줄 시각이며 만료 판정에는 쓰지 않습니다.
  final String savedAt;

  /// 점수를 화면에 보여줄 수 있는가.
  bool get hasScore => source == HomeSource.robotStanding && score > 0;

  factory HomePosition.fromValues(Map<String, Object?> values) {
    double number(String key) => (values[key] as num?)?.toDouble() ?? 0;
    return HomePosition(
      x: number('x'),
      y: number('y'),
      yaw: number('yaw'),
      source: HomeSource.fromWire(values['source'] as String?),
      score: number('score'),
      label: values['label'] as String? ?? '',
      visitedOk: values['visited_ok'] == true,
      savedAt: values['saved_at'] as String? ?? '',
    );
  }

  HomePosition copyWith({bool? visitedOk}) {
    return HomePosition(
      x: x,
      y: y,
      yaw: yaw,
      source: source,
      score: score,
      label: label,
      visitedOk: visitedOk ?? this.visitedOk,
      savedAt: savedAt,
    );
  }

  /// 저장 시각을 '2026-08-26' 처럼 짧게 보여줍니다. 파싱에 실패하면 원문입니다.
  String get savedAtLabel {
    if (savedAt.isEmpty) {
      return '';
    }
    final parsed = DateTime.tryParse(savedAt);
    if (parsed == null) {
      return savedAt;
    }
    final month = parsed.month.toString().padLeft(2, '0');
    final day = parsed.day.toString().padLeft(2, '0');
    return '${parsed.year}-$month-$day';
  }
}
