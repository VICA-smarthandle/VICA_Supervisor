class VicaBreakpoints {
  const VicaBreakpoints._();

  /// 이 폭 미만이면 가로로 나란히 두던 것을 세로로 접습니다.
  static const double compact = 600;

  /// 사이드 메뉴가 서는 폭입니다. app.dart가 쓰던 값을 그대로 옮겼습니다.
  static const double medium = 900;

  /// 본문 최대 폭입니다. 더 넓어지면 한 줄이 길어져 오히려 읽기 어렵습니다.
  static const double contentMaxWidth = 1280;

  /// 지도 화면을 '지도 왼쪽 + 설정 칸 오른쪽'으로 나누는 본문 폭입니다(2026-11-09 사용자 요청).
  static const double mapSideBySideMinWidth = 700;

  /// 나란히 놓을 때 이보다 낮은 창은 지도가 납작해지므로 위아래로 쌓습니다.
  static const double mapSideBySideMinHeight = 420;

  /// 오른쪽 설정 칸의 폭입니다. 폰(본문 약 380px)에서 다 들어가던 칸이 잘리지 않게
  static const double mapSidePanelMinWidth = 400;
  static const double mapSidePanelMaxWidth = 460;
  static const double mapSidePanelRatio = 0.38;

  /// 세로로 든 태블릿(폭 [compact]~[medium])은 지도를 위에 고정하고 높이를 화면의
  static const double mapPinnedTopMinHeight = 640;

  /// 폰 세로(폭 < [compact])도 지도를 위에 고정합니다(2026-11-19 사용자). 키보드를 뺀 본문이
  static const double mapPinnedTopPhoneMinHeight = 560;
  static const double mapPinnedTopMinMapHeight = 220;
  static const double mapPinnedTopMaxMapHeight = 440;

  /// 본문 좌우 여백입니다. 좁은 창에서는 내용에 쓸 폭을 한 픽셀이라도 더 남깁니다.
  static double horizontalPadding(double width) {
    if (width >= medium) {
      return 32;
    }
    return width < compact ? 16 : 24;
  }

  static bool isCompact(double width) => width < compact;
}
