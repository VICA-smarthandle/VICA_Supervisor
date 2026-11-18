// '주행 끄기'를 위쪽 막대로(2026-11-18 사용자 결정 — 목업 '위쪽 막대로 — 넓은 화면'·'폰 C').
//
// 넓은 화면: 온라인 칩 다음, 모드 바꾸기 왼쪽에 글자 버튼. 폰: 주행 중이면 '모드 ▾' 메뉴에
// '모드 바꾸기 / 주행 끄기'. 주행이 꺼져 있으면 둘 다 예전 그대로(⇄ 아이콘·버튼 없음).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vica_supervisor/app.dart';
import 'package:vica_supervisor/models/mode_status.dart';
import 'package:vica_supervisor/providers/app_mode_provider.dart';
import 'package:vica_supervisor/providers/auth_provider.dart';
import 'package:vica_supervisor/providers/settings_provider.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';
import 'package:vica_supervisor/providers/ui_preferences_provider.dart';
import 'package:vica_supervisor/screens/drive_bringup_screen.dart';
import 'package:vica_supervisor/widgets/vica_ui.dart';

class _FakeSupervisor extends SupervisorProvider {
  final calls = <String>[];
  (bool, String) reply = (true, '');

  @override
  Future<(bool, String)> driveStop() async {
    calls.add('drive_stop');
    return reply;
  }
}

const running = ModeStatus(mode: 'drive', state: ModeState.running, nav2: 'active');
const idle = ModeStatus(mode: 'idle', state: ModeState.idle);

final confirmStop = find.widgetWithText(FilledButton, '주행 끄기');
const phone = Size(390, 844);
const wide = Size(1280, 900);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<_FakeSupervisor> pumpShell(WidgetTester tester, Size size, ModeStatus status, {double scale = 1}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final auth = AuthProvider();
    await auth.login(username: 'admin', password: '1234');
    final ui = UiPreferencesProvider();
    await ui.load();
    final supervisor = _FakeSupervisor()..setModeStatusForTest(status);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: auth),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ChangeNotifierProvider<SupervisorProvider>.value(value: supervisor),
          ChangeNotifierProvider.value(value: ui),
          ChangeNotifierProvider(create: (_) => AppModeProvider()),
        ],
        child: MaterialApp(
          theme: vicaTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const SupervisorShell(),
        ),
      ),
    );
    await tester.pump();
    return supervisor;
  }

  group('넓은 화면', () {
    final stop = find.widgetWithText(OutlinedButton, '주행 끄기');

    testWidgets('주행이 꺼져 있으면 주행 끄기가 없다', (tester) async {
      await pumpShell(tester, wide, idle);
      expect(stop, findsNothing);
      expect(find.text('모드 바꾸기'), findsOneWidget);
    });

    testWidgets('주행 중이면 모드 바꾸기 왼쪽에 주행 끄기', (tester) async {
      await pumpShell(tester, wide, running);
      expect(stop, findsOneWidget);
      expect(tester.getTopLeft(stop).dx, lessThan(tester.getTopLeft(find.text('모드 바꾸기')).dx));
      expect(tester.getTopLeft(stop).dx, lessThan(tester.getTopLeft(find.text('비상정지')).dx));
    });

    testWidgets('확인 창을 거쳐서만 끄고, 끄는 진행 화면을 연다', (tester) async {
      final supervisor = await pumpShell(tester, wide, running);
      await tester.tap(stop);
      await tester.pumpAndSettle();
      expect(find.text('주행을 끌까요?'), findsOneWidget);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(supervisor.calls, isEmpty);

      await tester.tap(stop);
      await tester.pumpAndSettle();
      await tester.tap(confirmStop);
      await tester.pumpAndSettle();
      expect(supervisor.calls, ['drive_stop']);
      expect(find.byType(DriveBringupScreen), findsOneWidget);
      expect(find.text('주행 끄는 중'), findsOneWidget);
    });

    testWidgets('거절되면 이유를 띄우고 진행 화면을 열지 않는다', (tester) async {
      final supervisor = await pumpShell(tester, wide, running);
      supervisor.reply = (false, '로봇이 움직이는 중이라 끌 수 없습니다.');
      await tester.tap(stop);
      await tester.pumpAndSettle();
      await tester.tap(confirmStop);
      await tester.pumpAndSettle();
      expect(find.text('주행을 끄지 못했습니다'), findsOneWidget);
      expect(find.text(vicaKeepWords(vicaBreakAtSentences('로봇이 움직이는 중이라 끌 수 없습니다.'))), findsOneWidget);
      expect(find.byType(DriveBringupScreen), findsNothing);
    });

    testWidgets('끄는 중이면 누를 수 없다', (tester) async {
      await pumpShell(tester, wide, const ModeStatus(mode: 'drive', state: ModeState.stopping, nav2: 'active'));
      expect(tester.widget<OutlinedButton>(stop).onPressed, isNull);
    });
  });

  group('폰', () {
    testWidgets('주행이 꺼져 있으면 예전처럼 ⇄ 아이콘으로 바로 모드 바꾸기', (tester) async {
      await pumpShell(tester, phone, idle);
      expect(find.byTooltip('모드 바꾸기'), findsOneWidget);
      expect(find.text('모드'), findsNothing);
    });

    testWidgets("주행 중이면 '모드 ▾' 메뉴에 모드 바꾸기·주행 끄기", (tester) async {
      final supervisor = await pumpShell(tester, phone, running);
      expect(find.byTooltip('모드 바꾸기'), findsNothing);
      await tester.tap(find.text('모드'));
      await tester.pumpAndSettle();
      expect(find.text('모드 바꾸기'), findsOneWidget);
      await tester.tap(find.text('주행 끄기'));
      await tester.pumpAndSettle();
      expect(find.text('주행을 끌까요?'), findsOneWidget);
      await tester.tap(confirmStop);
      await tester.pumpAndSettle();
      expect(supervisor.calls, ['drive_stop']);
      expect(find.byType(DriveBringupScreen), findsOneWidget);
    });

    // 좁은 폰·큰 글자에서 위쪽 막대가 넘치지 않고 메뉴가 열리는지(실제 셸 막대).
    for (final width in [320.0, 360.0]) {
      for (final scale in [1.0, 1.3]) {
        testWidgets('폭 $width · 글자 $scale 배에서 막대가 넘치지 않고 메뉴가 열린다', (tester) async {
          await pumpShell(tester, Size(width, 760), running, scale: scale);
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('모드'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('주행 끄기'), findsOneWidget);
        });
      }
    }

    testWidgets('끄는 중이면 메뉴의 주행 끄기를 막는다', (tester) async {
      final supervisor =
          await pumpShell(tester, phone, const ModeStatus(mode: 'drive', state: ModeState.stopping, nav2: 'active'));
      await tester.tap(find.text('모드'));
      await tester.pumpAndSettle();
      expect(find.text('주행 끄는 중'), findsOneWidget);
      await tester.tap(find.text('주행 끄는 중'));
      await tester.pumpAndSettle();
      expect(find.text('주행을 끌까요?'), findsNothing);
      expect(supervisor.calls, isEmpty);
    });
  });
}
