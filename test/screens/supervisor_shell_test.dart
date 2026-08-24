// 사이드 메뉴 항목과 실제로 뜨는 화면이 어긋나지 않는지 고정합니다.
//
// **왜 필요한가.** app.dart 는 화면·제목·드로어 항목·사이드바 항목 **네 개의
// 목록**을 손으로 맞춰 들고 있습니다. 하나라도 어긋나면 "메뉴는 A 인데 화면은 B"
// 가 되고, 예외도 경고도 안 납니다 — 사람이 눈으로 봐야만 압니다.
//
// 2026-08-21 에 화면 하나(로봇 관리)를 지우면서 그 위험이 실제로 드러났습니다.
// 인덱스 상수는 _titles 에서 찾도록 바꿨고, 목록끼리의 정렬은 이 시험이 잠급니다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vica_supervisor/app.dart';
import 'package:vica_supervisor/providers/app_mode_provider.dart';
import 'package:vica_supervisor/providers/auth_provider.dart';
import 'package:vica_supervisor/providers/settings_provider.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';
import 'package:vica_supervisor/providers/ui_preferences_provider.dart';

// 넓은 창이라 사이드바(NavigationRail)가 섭니다. 900 이 그 경계입니다.
const _wide = Size(1400, 1100);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpShell(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = _wide;
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ChangeNotifierProvider(create: (_) => UiPreferencesProvider()),
          ChangeNotifierProvider(create: (_) => SupervisorProvider()),
          ChangeNotifierProvider(create: (_) => AppModeProvider()),
        ],
        child: const MaterialApp(home: SupervisorShell()),
      ),
    );
    await tester.pump();
  }

  testWidgets('사이드 메뉴를 누르면 같은 이름의 화면이 뜬다', (tester) async {
    await pumpShell(tester);

    // 메뉴 라벨과 AppBar 제목이 같아야 합니다. 목록이 어긋나면 여기서 깨집니다.
    const expected = [
      '대시보드',
      '장소 저장',
      '원격 주행',
      '현재 위치',
      '시스템 진단',
      '알림 및 로그',
      '설정',
    ];

    for (final label in expected) {
      // 사이드바 라벨을 누릅니다. 같은 글자가 AppBar 에도 있을 수 있으므로
      // 마지막(= 사이드바 쪽)을 고릅니다.
      await tester.tap(find.text(label).last, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(AppBar, label),
        findsOneWidget,
        reason: "'$label' 을 눌렀는데 그 제목의 화면이 뜨지 않았습니다.",
      );
    }
  });

  testWidgets('삭제한 로봇 관리는 메뉴에 남아 있지 않다', (tester) async {
    await pumpShell(tester);
    expect(find.text('로봇 관리'), findsNothing);
  });
}
