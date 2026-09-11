class VicaBreakpoints {
  const VicaBreakpoints._();

  /// 이 폭 미만이면 가로로 나란히 두던 것을 세로로 접습니다.
  static const double compact = 600;

  /// 사이드 메뉴가 서는 폭입니다. app.dart가 쓰던 값을 그대로 옮겼습니다.
  static const double medium = 900;

  /// 지표 카드를 4열로 펼치는 폭입니다. dashboard_screen.dart가 쓰던 값입니다.
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
