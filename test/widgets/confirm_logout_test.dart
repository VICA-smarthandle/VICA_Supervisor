import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vica_supervisor/app.dart';
import 'package:vica_supervisor/core/app_settings.dart';
import 'package:vica_supervisor/core/auth_config.dart';
import 'package:vica_supervisor/providers/app_mode_provider.dart';
import 'package:vica_supervisor/providers/auth_provider.dart';
import 'package:vica_supervisor/providers/settings_provider.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';
import 'package:vica_supervisor/providers/ui_preferences_provider.dart';
import 'package:vica_supervisor/ros/ros_bridge_client.dart';
import 'package:vica_supervisor/screens/mapping_shell.dart';
import 'package:vica_supervisor/screens/mode_select_screen.dart';
import 'package:vica_supervisor/widgets/vica_ui.dart';

import '../ros/fake_ros_socket.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<(SupervisorProvider, AuthProvider)> pumpScreen(
    WidgetTester tester,
    Widget screen,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 1600);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final server = FakeRosServer();
    final supervisor = SupervisorProvider(rosChannelConnector: server.connect);
    await supervisor.connect(const AppSettings());
    final auth = AuthProvider();
    await auth.login(
      username: AuthConfig.adminUsername,
      password: AuthConfig.adminPassword,
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SupervisorProvider>.value(value: supervisor),
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ChangeNotifierProvider(create: (_) => AppModeProvider()),
          ChangeNotifierProvider(create: (_) => UiPreferencesProvider()),
        ],
        child: MaterialApp(home: screen),
      ),
    );
    await tester.pump();
    return (supervisor, auth);
  }

  Future<void> drain(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 15));

  final screens = <String, Widget>{
    '주행 셸': const SupervisorShell(),
    '지도 셸': const MappingShell(),
    '모드 선택': const ModeSelectScreen(),
  };

  for (final MapEntry(key: name, value: screen) in screens.entries) {
    testWidgets('$name: 한 번 묻고, 취소하면 그대로다', (tester) async {
      final (supervisor, auth) = await pumpScreen(tester, screen);

      await tester.tap(find.byTooltip('로그아웃'));
      await tester.pumpAndSettle();
      final dialog = find.byType(VicaDialog);
      expect(dialog, findsOneWidget);
      expect(
        find.descendant(
          of: dialog,
          matching: find.textContaining(vicaKeepWords('다음 실행 시')),
        ),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(OutlinedButton, '취소'));
      await tester.pumpAndSettle();
      expect(auth.isLoggedIn, isTrue);
      expect(supervisor.connectionState, RosConnectionState.connected);
      await drain(tester);
    });

    testWidgets('$name: 로그아웃하면 ROS 연결도 끊는다', (tester) async {
      final (supervisor, auth) = await pumpScreen(tester, screen);

      await tester.tap(find.byTooltip('로그아웃'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(VicaDialog),
          matching: find.widgetWithText(FilledButton, '로그아웃'),
        ),
      );
      await tester.pumpAndSettle();

      expect(auth.isLoggedIn, isFalse);
      expect(supervisor.connectionState, RosConnectionState.disconnected);
      await drain(tester);
    });
  }
}
