// 이 파일은 창 폭에 따른 배치 기준을 한곳에 모읍니다.
//
// 화면마다 제각기 다른 숫자를 쓰면 같은 폭에서 화면끼리 다르게 접혀 관리자가 혼란스럽습니다.
// 아래 값 대부분은 이미 화면들이 쓰고 있던 숫자를 옮겨온 것이고, compact만 새로 정했습니다.
class VicaBreakpoints {
  const VicaBreakpoints._();

  /// 이 폭 미만이면 가로로 나란히 두던 것을 세로로 접습니다.
  ///
  /// Material 3의 compact 창 구간 경계와 같은 값입니다. 실측으로도 이 아래에서
  /// '드롭다운 + 고정폭 버튼' 한 줄이 드롭다운을 130px까지 밀어내 지도 이름이
  /// 거의 보이지 않았습니다.
  static const double compact = 600;

  /// 사이드 메뉴가 서는 폭입니다. app.dart가 쓰던 값을 그대로 옮겼습니다.
  static const double medium = 900;

  /// 지표 카드를 4열로 펼치는 폭입니다. dashboard_screen.dart가 쓰던 값입니다.
  ///
  /// 이보다 좁으면 4열일 때 카드 하나가 160px 밑으로 내려가 숫자와 라벨이 함께
  /// 들어가지 못합니다.
  static const double metricGridWide = 720;

  /// 본문 최대 폭입니다. 더 넓어지면 한 줄이 길어져 오히려 읽기 어렵습니다.
  static const double contentMaxWidth = 1280;

  /// 지표 카드 묶음의 최대 폭입니다. 본문보다 좁게 두어 카드가 과하게 늘어나지 않게 합니다.
  static const double metricGridMaxWidth = 1040;

  /// 본문 좌우 여백입니다. 좁은 창에서는 내용에 쓸 폭을 한 픽셀이라도 더 남깁니다.
  static double horizontalPadding(double width) {
    if (width >= medium) {
      return 32;
    }
    return width < compact ? 16 : 24;
  }

  static bool isCompact(double width) => width < compact;
}
