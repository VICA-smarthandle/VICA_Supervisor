import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vica_supervisor/app.dart';
import 'package:vica_supervisor/providers/auth_provider.dart';
import 'package:vica_supervisor/providers/settings_provider.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';
import 'package:vica_supervisor/providers/ui_preferences_provider.dart';

void main() {
  Future<Widget> buildShell() async {
    SharedPreferences.setMockInitialValues({});
    final authProvider = AuthProvider();
    await authProvider.login(username: 'admin', password: '1234');
    final uiPreferencesProvider = UiPreferencesProvider();
    await uiPreferencesProvider.load();

    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authProvider),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => SupervisorProvider()),
        ChangeNotifierProvider.value(value: uiPreferencesProvider),
      ],
      child: const MaterialApp(home: SupervisorShell()),
    );
  }

  testWidgets('좁은 화면에서는 하단 탭과 더보기 목록을 사용한다', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    await tester.pumpWidget(await buildShell());
    await tester.pump();

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.drawer, isNull);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byKey(const ValueKey('desktop_sidebar')), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('더보기'));
    await tester.pumpAndSettle();
    for (final label in ['현재 위치', '시스템 진단', '알림 및 로그', '설정', '로그아웃']) {
      expect(find.text(label), findsWidgets, reason: "더보기에 '$label' 이 없습니다.");
    }
    expect(find.byTooltip('모드 바꾸기'), findsOneWidget);
    expect(find.byTooltip('설정'), findsOneWidget);
    await tester.tap(find.text('설정'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '설정'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('넓은 화면에서는 접고 펼칠 수 있는 사이드 메뉴를 사용한다', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    await tester.pumpWidget(await buildShell());
    await tester.pump();

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    final sidebar = find.byKey(const ValueKey('desktop_sidebar'));
    expect(sidebar, findsOneWidget);
    expect(tester.getSize(sidebar).width, 240);
    expect(find.text('admin'), findsOneWidget);
    expect(scaffold.drawer, isNull);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('사이드 메뉴 접기'));
    await tester.pumpAndSettle();

    expect(tester.getSize(sidebar).width, 80);
    expect(find.byTooltip('사이드 메뉴 펼치기'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
