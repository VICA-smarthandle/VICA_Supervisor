import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/app.dart';

/// 시험 대상 테마를 앱과 같은 방식으로 만듭니다.
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
    expect(kVicaFontFamily, isNotEmpty);
    expect(kVicaFontFamily, 'NanumGothic');
  });

  testWidgets('AppBar 제목이 글꼴을 물려받는다', (tester) async {
    final theme = await _resolveAppTheme(tester);

    expect(
      theme.appBarTheme.titleTextStyle?.fontFamily,
      kVicaFontFamily,
      reason: 'appBarTheme.titleTextStyle에 fontFamily를 직접 넣어야 합니다. '
          'ThemeData.fontFamily는 여기까지 오지 않습니다.',
    );
  });

  testWidgets('본문 글꼴이 앱 글꼴이다', (tester) async {
    final theme = await _resolveAppTheme(tester);

    expect(theme.textTheme.bodyMedium?.fontFamily, kVicaFontFamily);
    expect(theme.textTheme.titleMedium?.fontFamily, kVicaFontFamily);
  });
}
