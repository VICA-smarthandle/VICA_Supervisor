import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vica_supervisor/app.dart';
import 'package:vica_supervisor/models/delivery_job.dart';
import 'package:vica_supervisor/models/location_point.dart';
import 'package:vica_supervisor/providers/app_mode_provider.dart';
import 'package:vica_supervisor/providers/auth_provider.dart';
import 'package:vica_supervisor/providers/settings_provider.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';
import 'package:vica_supervisor/providers/ui_preferences_provider.dart';
import 'package:vica_supervisor/services/delivery_notifier.dart';
import 'package:vica_supervisor/widgets/delivery_notice_dialog.dart';
import 'package:vica_supervisor/widgets/goal_alert_dialog.dart';
import 'package:vica_supervisor/widgets/vica_ui.dart';

const _wide = Size(1400, 1100);

const _office = LocationPoint(
  locationId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  mapId: 'm1',
  name: '305호',
  x: 1,
  y: 2,
  yaw: 0,
  contactPhone: '01012345678',
);

/// 이 기기에서 직접 보내고 늘 성공하는 척합니다.
class _SentNotifier implements DeliveryNotifier {
  @override
  String get modeLabel => '시험';

  @override
  Future<bool> canSend() async => true;

  @override
  Future<bool> needsRelay() async => false;

  @override
  Future<DeliveryNotifyResult> send({
    required String phone,
    required String text,
  }) async =>
      const DeliveryNotifyResult(sent: true, detail: '통신사가 받았습니다');
}

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

  testWidgets('대시보드를 보고 있어도 주행 실패 팝업이 뜬다', (tester) async {
    await pumpShell(tester);
    expect(find.widgetWithText(AppBar, '대시보드'), findsOneWidget);

    final supervisor =
        tester.element(find.byType(SupervisorShell)).read<SupervisorProvider>();
    supervisor.handleGoalEventForTest({
      'event': 'goal_failed',
      'name': '화장실',
      'reason': 'Nav2 task failed',
      'map_id': 'm1',
    });
    await tester.pumpAndSettle();

    final dialog = find.byType(GoalAlertDialog);
    Finder inDialog(Finder matching) =>
        find.descendant(of: dialog, matching: matching);

    expect(dialog, findsOneWidget);
    expect(inDialog(find.text('주행 실패')), findsOneWidget);
    expect(
      inDialog(find.textContaining(vicaKeepWords('목적지까지 주행에 실패했습니다.'))),
      findsOneWidget,
    );
    expect(
      inDialog(find.textContaining(vicaKeepWords('비카가 관리자를 호출했습니다.'))),
      findsOneWidget,
    );
    expect(inDialog(find.text('목적지')), findsOneWidget);
    expect(inDialog(find.text('화장실')), findsOneWidget);
    expect(inDialog(find.text('사유')), findsOneWidget);
    expect(inDialog(find.text('Nav2 task failed')), findsOneWidget);

    await tester.tap(inDialog(find.widgetWithText(FilledButton, '확인')));
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
    expect(supervisor.pendingGoalAlert, isNull);
  });

  testWidgets('로봇이 다시 출발하면 실패 팝업이 저절로 닫힌다', (tester) async {
    await pumpShell(tester);
    final supervisor =
        tester.element(find.byType(SupervisorShell)).read<SupervisorProvider>();
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
    expect(find.widgetWithText(AppBar, '대시보드'), findsOneWidget);
  });

  testWidgets('사유가 없는 취소 팝업은 사유 칸을 그리지 않는다', (tester) async {
    await pumpShell(tester);
    final supervisor =
        tester.element(find.byType(SupervisorShell)).read<SupervisorProvider>();
    supervisor.handleGoalEventForTest({
      'event': 'return_home_canceled',
      'name': '',
      'reason': '',
      'map_id': 'm1',
    });
    await tester.pumpAndSettle();

    final dialog = find.byType(GoalAlertDialog);
    Finder inDialog(String text) =>
        find.descendant(of: dialog, matching: find.text(text));

    expect(dialog, findsOneWidget);
    expect(inDialog('홈 복귀가 취소되었습니다'), findsOneWidget);
    expect(inDialog('목적지'), findsOneWidget);
    expect(inDialog('홈'), findsOneWidget);
    expect(inDialog('사유'), findsNothing);
  });

  testWidgets('대시보드를 보고 있어도 도착 문자 결과 팝업이 뜬다', (tester) async {
    await pumpShell(tester);
    expect(find.widgetWithText(AppBar, '대시보드'), findsOneWidget);

    final supervisor =
        tester.element(find.byType(SupervisorShell)).read<SupervisorProvider>();
    supervisor.deliveryNotifierForTest = _SentNotifier();
    supervisor.setDeliveryForTest(
      DeliveryJob(destination: _office, startedAt: DateTime(2026)),
    );
    supervisor.handleGoalEventForTest({
      'event': 'goal_succeeded',
      'map_id': 'm1',
      'location_id': _office.locationId,
      'destination_id': _office.locationId,
      'name': '305호',
      'reason': '',
    });
    await tester.pumpAndSettle();

    final dialog = find.byType(DeliveryNoticeDialog);
    Finder inDialog(String text) =>
        find.descendant(of: dialog, matching: find.text(text));

    expect(dialog, findsOneWidget);
    expect(inDialog('도착 문자를 보냈습니다'), findsOneWidget);
    expect(inDialog('받는 곳: 305호'), findsOneWidget);
    expect(inDialog('통신사가 받았습니다'), findsOneWidget);
    expect(find.widgetWithText(AppBar, '대시보드'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: dialog,
        matching: find.widgetWithText(FilledButton, '확인'),
      ),
    );
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
    expect(supervisor.pendingDeliveryNotice, isNull);
  });
}
