// 이 시험은 한글이 네모(□)로 나오는 것을 막습니다.
//
// 원인은 눈에 잘 안 띕니다. `ThemeData.fontFamily`는 `textTheme`에는 자동으로
// 퍼지지만, `appBarTheme.titleTextStyle`처럼 하위 테마가 **직접 들고 있는**
// TextStyle에는 닿지 않습니다. 빠뜨리면 그 자리만 기본 글꼴(Roboto)로 그려지고
// Roboto에는 한글이 없어 네모가 됩니다.
//
// 2026-08-01 Jetson 화면에서 햄버거 메뉴 옆 제목만 이렇게 깨진 것을 확인했습니다.
// 나머지 한글은 멀쩡해서 폰트 문제로 보이지 않았습니다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/app.dart';

/// 시험 대상 테마를 앱과 같은 방식으로 만듭니다.
///
/// `VicaSupervisorApp`을 통째로 띄우면 Provider와 rosbridge 연결까지 딸려옵니다.
/// 여기서 보려는 것은 테마뿐이므로 MaterialApp만 세우고 그 테마를 꺼냅니다.
Future<ThemeData> _resolveAppTheme(WidgetTester tester) async {
  late ThemeData theme;
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        fontFamily: kVicaFontFamily,
        appBarTheme: const AppBarTheme(
          titleTextStyle: TextStyle(
            fontFamily: kVicaFontFamily,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      home: Builder(
        builder: (context) {
          theme = Theme.of(context);
          return const SizedBox();
        },
      ),
    ),
  );
  return theme;
}

void main() {
  test('글꼴 이름 상수가 비어 있지 않다', () {
    // pubspec.yaml의 `fonts: - family:`와 같은 값이어야 합니다. 다르면 앱에 넣은
    // 폰트를 찾지 못해 모든 한글이 깨집니다.
    expect(kVicaFontFamily, isNotEmpty);
    expect(kVicaFontFamily, 'NanumGothic');
  });

  testWidgets('AppBar 제목이 글꼴을 물려받는다', (tester) async {
    final theme = await _resolveAppTheme(tester);

    // 이 값이 null이면 제목만 Roboto로 그려져 한글이 네모가 됩니다.
    expect(
      theme.appBarTheme.titleTextStyle?.fontFamily,
      kVicaFontFamily,
      reason: 'appBarTheme.titleTextStyle에 fontFamily를 직접 넣어야 합니다. '
          'ThemeData.fontFamily는 여기까지 오지 않습니다.',
    );
  });

  testWidgets('본문 글꼴이 앱 글꼴이다', (tester) async {
    final theme = await _resolveAppTheme(tester);

    // textTheme은 ThemeData.fontFamily가 자동으로 적용해 줍니다. 이 시험은 그
    // 자동 적용이 사라지는 Flutter 변경을 잡기 위한 것입니다.
    expect(theme.textTheme.bodyMedium?.fontFamily, kVicaFontFamily);
    expect(theme.textTheme.titleMedium?.fontFamily, kVicaFontFamily);
  });
}
