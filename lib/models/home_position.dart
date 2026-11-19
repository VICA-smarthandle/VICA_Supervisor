// 이 파일은 지도별 홈 위치를 표현합니다.
//
// **홈은 목적지가 아닙니다.** 사용자가 "홈으로 가줘"라고 말할 수 있는 장소가
// 아니라, 안내가 끝난 뒤 로봇이 스스로 돌아가는 자리입니다. 그래서 장소 목록
// (LocationPoint)과 별도 모델이고, 젯슨에서도 destinations.yaml 이 아니라
// 같은 폴더의 home.yaml 하나로 관리합니다. 파일이 하나라서 "지도당 1개"가
// 저절로 지켜집니다.

/// 홈을 어떻게 정했는가.
///
/// 두 방식은 서로 다른 축에서 강합니다. 세워놓고 잡으면 **방향이 정확**하지만
/// 위치는 AMCL 을 믿어야 하고(복도에서 앞뒤로 밀려 있어도 모릅니다), 지도에서
/// 찍으면 **위치가 사람 의도 그대로**지만 방향은 90도 단위로 거칩니다.
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
    // 모르는 값은 채점이 없는 쪽으로 봅니다. 있지도 않은 점수를 믿게 하는 것보다
    // 안전합니다.
    return HomeSource.mapPick;
  }
}

/// 홈에 한 번도 가 본 적이 없을 때 원격 주행의 '홈으로 복귀' 아래에 보일 말.
const kHomeUnvisitedText = '홈에 아직 가 본 적이 없습니다. 지도 설정 화면에서 확인해주세요.';

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
    this.note = '',
  });

  final double x;
  final double y;

  /// 도(degree) 단위입니다. destinations.yaml 의 pose 와 같은 규약입니다.
  final double yaw;

  final HomeSource source;

  /// 실제 자리에서 지정했을 때의 라이다-지도 일치도(0~100)입니다.
  /// 지도에서 찍었으면 0 이며, 그때는 화면에 점수를 보여주지 않습니다.
  final double score;

  /// 관리자가 붙인 이름입니다. 로봇은 쓰지 않습니다.
  final String label;

  /// **이 모델에서 가장 중요한 값입니다.**
  ///
  /// 나머지 필드는 "어떻게 정했나"를 적은 것이고, 이 하나만이 **"실제로 갈 수
  /// 있는 자리임을 확인했나"** 를 답합니다. 좌표를 정하는 일과 그 자리에
  /// 도달할 수 있다는 사실은 별개입니다 — 로봇을 세워놓고 잡았어도 Nav2 가
  /// 거기까지 경로를 그릴 수 있다는 보장은 없습니다.
  ///
  /// 지도를 새로 저장하면 false 로 돌아갑니다. 좌표는 그대로인데 지도가 달라져
  /// 홈이 벽 속에 들어갈 수 있기 때문입니다.
  final bool visitedOk;

  /// ISO 8601 문자열입니다. 사람에게 보여줄 시각이며 만료 판정에는 쓰지 않습니다.
  final String savedAt;

  /// 로봇이 홈에 대해 알리는 말(GetHome.message). 마지막 홈 복귀가 막혀 실패했으면
  /// '홈에 접근할 수 없습니다.' 이고, 아니면 빈 문자열입니다(2026-11-19 사용자). 한 번 가 본
  /// 홈이 막혔을 때 '가 본 적 없음' 대신 이 말을 보입니다. 홈에 다시 들어오면 로봇이 지웁니다.
  final String note;

  /// 점수를 화면에 보여줄 수 있는가.
  ///
  /// 지도에서 찍은 홈에는 점수가 없습니다. 0% 라고 표시하면 "나쁜 홈"으로
  /// 읽히지만 사실은 **잰 적이 없는 것**이라 뜻이 완전히 다릅니다.
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
      note: (values['message'] as String? ?? '').trim(),
    );
  }

  HomePosition copyWith({bool? visitedOk, String? note}) {
    return HomePosition(
      x: x,
      y: y,
      yaw: yaw,
      source: source,
      score: score,
      label: label,
      visitedOk: visitedOk ?? this.visitedOk,
      savedAt: savedAt,
      note: note ?? this.note,
    );
  }

  /// 홈 칸·홈 복귀 버튼 아래에 보일 경고. 없으면 빈 문자열입니다.
  ///
  /// 로봇이 막힘을 알렸으면 그 말, 아니고 한 번도 가 본 적이 없으면 [unvisitedText] 입니다.
  String warning(String unvisitedText) =>
      note.isNotEmpty ? note : (visitedOk ? '' : unvisitedText);

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
