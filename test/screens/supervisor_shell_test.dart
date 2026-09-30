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
import 'package:vica_supervisor/widgets/goal_alert_dialog.dart';
import 'package:vica_supervisor/widgets/vica_ui.dart';

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
      '지도 설정',
      '원격 주행',
      '물류 배송',
      '현재 위치',
      '시스템 진단',
      '알림 및 로그',
      '설정',
    ];

    final sidebar = find.byKey(const ValueKey('desktop_sidebar'));
    for (final label in expected) {
      // 사이드바 안의 라벨을 누릅니다. 같은 글자가 AppBar 나 본문에도 있을 수
      // 있으므로 사이드바 안으로 범위를 좁힙니다.
      await tester.tap(
        find.descendant(of: sidebar, matching: find.text(label)),
        warnIfMissed: false,
      );
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

  // ---- 주행 실패 팝업 (2026-09-30) -------------------------------------------
  //
  // 종전에는 원격 주행·물류 배송 화면이 각자 팝업을 띄웠습니다. 셸은 지금 보는
  // 화면 하나만 그리므로 **대시보드를 보고 있을 때 실패가 오면 아무것도 뜨지
  // 않았습니다.** 이제 셸이 띄우므로 어느 화면이든 뜹니다.

  testWidgets('대시보드를 보고 있어도 주행 실패 팝업이 뜬다', (tester) async {
    await pumpShell(tester);
    // 첫 화면은 대시보드입니다 — 원격 주행 화면이 아닙니다.
    expect(find.widgetWithText(AppBar, '대시보드'), findsOneWidget);

    final supervisor = tester
        .element(find.byType(SupervisorShell))
        .read<SupervisorProvider>();
    supervisor.handleGoalEventForTest({
      'event': 'goal_failed',
      'name': '화장실',
      'reason': 'Nav2 task failed',
      'map_id': 'm1',
    });
    await tester.pumpAndSettle();

    // 같은 제목·사유가 대시보드의 알림 목록에도 한 줄로 남으므로 팝업 안으로
    // 좁혀서 찾습니다.
    final dialog = find.byType(GoalAlertDialog);
    Finder inDialog(Finder matching) =>
        find.descendant(of: dialog, matching: matching);

    expect(dialog, findsOneWidget);
    expect(inDialog(find.text('주행 실패')), findsOneWidget);
    // 본문 세 줄은 어절 단위 줄바꿈(vicaKeepWords)을 거치므로 같은 변환으로 찾습니다.
    expect(
      inDialog(find.textContaining(vicaKeepWords('목적지까지 주행에 실패했습니다.'))),
      findsOneWidget,
    );
    expect(
      inDialog(find.textContaining(vicaKeepWords('비카가 관리자를 호출했습니다.'))),
      findsOneWidget,
    );
    // 목적지·사유는 본문이 아니라 아래 칸에 따로 보입니다.
    expect(inDialog(find.text('목적지')), findsOneWidget);
    expect(inDialog(find.text('화장실')), findsOneWidget);
    expect(inDialog(find.text('사유')), findsOneWidget);
    expect(inDialog(find.text('Nav2 task failed')), findsOneWidget);

    // 확인을 누르면 닫히고, 같은 알림이 다시 뜨지 않습니다.
    await tester.tap(inDialog(find.widgetWithText(FilledButton, '확인')));
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
    expect(supervisor.pendingGoalAlert, isNull);
  });

  testWidgets('로봇이 다시 출발하면 실패 팝업이 저절로 닫힌다', (tester) async {
    // Nav2 실패 뒤 미션 매니저가 3초 뒤 같은 목적지로 재시도하면 goal_sent 가
    // 다시 옵니다. 로봇은 달리는데 팝업만 남아 있으면 안 됩니다(2026-09-30).
    await pumpShell(tester);
    final supervisor = tester
        .element(find.byType(SupervisorShell))
        .read<SupervisorProvider>();
    supervisor.handleGoalEventForTest({
      'event': 'goal_failed',
      'name': '화장실',
      'reason': 'Nav2 task failed',
      'map_id': 'm1',
    });
    await tester.pumpAndSettle();
    expect(find.byType(GoalAlertDialog), findsOneWidget);

    supervisor.handleGoalEventForTest({
      'event': 'goal_sent',
      'name': '화장실',
      'reason': '',
      'map_id': 'm1',
    });
    await tester.pumpAndSettle();

    expect(find.byType(GoalAlertDialog), findsNothing);
    // 팝업만 닫히고 셸은 그대로입니다 — pop 이 두 번 나가면 여기가 깨집니다.
    expect(find.widgetWithText(AppBar, '대시보드'), findsOneWidget);
  });

  testWidgets('사유가 없는 취소 팝업은 사유 칸을 그리지 않는다', (tester) async {
    await pumpShell(tester);
    final supervisor = tester
        .element(find.byType(SupervisorShell))
        .read<SupervisorProvider>();
    supervisor.handleGoalEventForTest({
      'event': 'return_home_canceled',
      'name': '',
      'reason': '',
      'map_id': 'm1',
    });
    await tester.pumpAndSettle();

    // 같은 제목이 대시보드의 알림 목록에도 한 줄로 남으므로 팝업 안으로 좁힙니다.
    final dialog = find.byType(GoalAlertDialog);
    Finder inDialog(String text) =>
        find.descendant(of: dialog, matching: find.text(text));

    expect(dialog, findsOneWidget);
    expect(inDialog('홈 복귀가 취소되었습니다'), findsOneWidget);
    // 홈은 카탈로그에 없어 이름이 비어 오지만 목적지 칸에는 '홈'이라고 적습니다.
    expect(inDialog('목적지'), findsOneWidget);
    expect(inDialog('홈'), findsOneWidget);
    expect(inDialog('사유'), findsNothing);
  });
}
