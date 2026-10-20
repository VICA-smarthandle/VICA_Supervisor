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
import 'package:vica_supervisor/widgets/help_alert_dialog.dart';
import 'package:vica_supervisor/widgets/map_canvas.dart';

const _wide = Size(1400, 1100);
const _idA = '6f1c2b0e-8a7d-4c1e-9b2a-3d4e5f607182';

Map<String, Object?> _event(String event,
        {String place = '407호 앞', String stamp = '2026-10-16T14:03:21'}) =>
    {
      'event': event,
      'map_id': 'm1',
      'name': '',
      'reason': '',
      'timestamp': stamp,
      'help_id': _idA,
      if (event == 'help_requested') ...{
        'place': place,
        'robot_x': 1.0,
        'robot_y': 2.0,
      },
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<SupervisorProvider> pumpShell(WidgetTester tester) async {
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
    return tester
        .element(find.byType(SupervisorShell))
        .read<SupervisorProvider>();
  }

  final dialog = find.byType(HelpAlertDialog);
  Finder inDialog(Finder matching) =>
      find.descendant(of: dialog, matching: matching);

  testWidgets('대시보드를 보고 있어도 도움 요청 팝업이 뜬다', (tester) async {
    final supervisor = await pumpShell(tester);
    supervisor.handleGoalEventForTest(_event('help_requested'));
    await tester.pumpAndSettle();

    expect(dialog, findsOneWidget);
    expect(inDialog(find.text('도움 요청')), findsOneWidget);
    expect(inDialog(find.text('위치')), findsOneWidget);
    expect(inDialog(find.text('407호 앞')), findsOneWidget);
    expect(inDialog(find.text('요청 시각')), findsOneWidget);
    expect(inDialog(find.text('14:03:21')), findsOneWidget);
    expect(inDialog(find.widgetWithText(FilledButton, '확인')), findsOneWidget);
  });

  testWidgets('지도가 있으면 팝업 안에 지도를 그린다', (tester) async {
    final supervisor = await pumpShell(tester);
    supervisor.handleMapListForTest({
      'maps': [
        {
          'map_id': 'm1',
          'map_name': 'm1',
          'resolution': 0.05,
          'origin_x': 0.0,
          'origin_y': 0.0,
          'width': 200,
          'height': 200,
        },
      ],
    });
    supervisor.handleGoalEventForTest(_event('help_requested'));
    await tester.pumpAndSettle();

    expect(dialog, findsOneWidget);
    expect(inDialog(find.byType(MapCanvas)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('같은 요청이 다시 오면 팝업은 하나, 위치만 바뀐다', (tester) async {
    final supervisor = await pumpShell(tester);
    supervisor.handleGoalEventForTest(_event('help_requested'));
    await tester.pumpAndSettle();
    supervisor.handleGoalEventForTest(_event('help_requested',
        place: '407호와 화장실 사이', stamp: '2026-10-16T14:03:31'));
    await tester.pumpAndSettle();

    expect(dialog, findsOneWidget);
    expect(inDialog(find.text('407호와 화장실 사이')), findsOneWidget);
    expect(inDialog(find.text('14:03:21')), findsOneWidget);
  });

  testWidgets('취소가 오면 저절로 닫힌다', (tester) async {
    final supervisor = await pumpShell(tester);
    supervisor.handleGoalEventForTest(_event('help_requested'));
    await tester.pumpAndSettle();
    supervisor.handleGoalEventForTest(_event('help_canceled'));
    await tester.pumpAndSettle();

    expect(dialog, findsNothing);
    expect(find.byType(SupervisorShell), findsOneWidget);
  });

  testWidgets('바깥을 눌러서는 닫히지 않는다', (tester) async {
    final supervisor = await pumpShell(tester);
    supervisor.handleGoalEventForTest(_event('help_requested'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(dialog, findsOneWidget);
  });

  testWidgets('확인이 로봇에 닿지 않으면 팝업은 남고 이유를 알린다', (tester) async {
    final supervisor = await pumpShell(tester);
    supervisor.handleGoalEventForTest(_event('help_requested'));
    await tester.pumpAndSettle();
    await tester.tap(inDialog(find.widgetWithText(FilledButton, '확인')));
    await tester.pumpAndSettle();

    expect(dialog, findsOneWidget);
    expect(find.text('ROS Bridge에 연결되지 않았습니다.'), findsOneWidget);
  });

  testWidgets('관리자 확인 뒤 사용자가 취소하면 한 줄로 알린다', (tester) async {
    final supervisor = await pumpShell(tester);
    supervisor.handleGoalEventForTest(_event('help_requested'));
    await tester.pumpAndSettle();
    supervisor.handleGoalEventForTest(_event('help_acknowledged'));
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);

    supervisor.handleGoalEventForTest(_event('help_canceled'));
    await tester.pump();
    await tester.pump();

    expect(
      find.descendant(
          of: find.byType(SnackBar),
          matching: find.text('사용자가 도움 요청을 취소했습니다.')),
      findsOneWidget,
    );
  });
}
