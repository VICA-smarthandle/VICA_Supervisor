// 알림 및 로그의 '오늘 N건' 숫자 줄과 시간대 막대(2026-11-17 사용자 채택 초안 ①).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vica_supervisor/core/log_filter.dart';
import 'package:vica_supervisor/models/supervisor_log.dart';
import 'package:vica_supervisor/providers/settings_provider.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';
import 'package:vica_supervisor/screens/logs_screen.dart';
import 'package:vica_supervisor/widgets/log_summary.dart';
import 'package:vica_supervisor/widgets/vica_ui.dart';

class _LogsSupervisor extends SupervisorProvider {
  _LogsSupervisor(this.fake);

  final List<SupervisorLog> fake;

  @override
  List<SupervisorLog> get logs => fake;
}

SupervisorLog _log(LogFilter filter, DateTime at, [String message = '기록']) =>
    SupervisorLog(filter: filter, message: message, createdAt: at);

Future<void> _pumpScreen(
  WidgetTester tester,
  List<SupervisorLog> logs, {
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SupervisorProvider>.value(
            value: _LogsSupervisor(logs)),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
              size: size, textScaler: TextScaler.linear(textScale)),
          child: const Scaffold(body: LogsScreen()),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('분류색은 사용자가 고른 색 G(Okabe–Ito) 다섯 가지다', () {
    expect(
      [for (final f in kLogSummaryFilters) vicaLogColor(f)],
      const [
        Color(0xFFD55E00), // 긴급 정지 주홍
        Color(0xFF0072B2), // 연결 파랑
        Color(0xFF009E73), // 배송 청록
        Color(0xFFE69F00), // 좌표 전송 주황
        Color(0xFFCC79A7), // 경비 분홍보라
      ],
    );
  });

  testWidgets('오늘 기록만 분류별로 세고 시간대 막대에 쌓는다', (tester) async {
    final now = DateTime(2026, 11, 17, 14, 50);
    final logs = [
      _log(LogFilter.emergencyStop, DateTime(2026, 11, 17, 14, 43)),
      _log(LogFilter.connection, DateTime(2026, 11, 17, 14, 52)),
      _log(LogFilter.delivery, DateTime(2026, 11, 17, 12, 10)),
      _log(LogFilter.emergencyStop, DateTime(2026, 11, 17, 9, 5)),
      _log(LogFilter.delivery, DateTime(2026, 11, 16, 14, 0)), // 어제 — 세지 않는다
    ];
    int? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LogTodaySummary(
              logs: logs,
              filter: LogFilter.all,
              hour: null,
              now: now,
              onHour: (h) => picked = h,
              onFilter: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('오늘 4건'), findsOneWidget);
    expect(find.text('최근 7시간'), findsOneWidget); // 막대 범위를 제목에(사용자 11-17)
    expect(find.bySemanticsLabel('긴급 정지 2건'), findsOneWidget);
    expect(find.bySemanticsLabel('배송 1건'), findsOneWidget);
    // 막대는 지금까지 최근 7시간(8~14시). 9시 기록은 들어가고 칸 수는 7.
    expect(find.text('8시'), findsOneWidget);
    expect(find.text('14시'), findsOneWidget);
    expect(find.text('7시'), findsNothing);
    expect(find.bySemanticsLabel('14시 2건'), findsOneWidget);
    expect(find.bySemanticsLabel('9시 1건'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('14시 2건'));
    expect(picked, 14);
  });

  testWidgets('막대를 누르면 그 시의 기록만, 모든 시간으로 되돌린다', (tester) async {
    final now = DateTime.now();
    final logs = [
      _log(LogFilter.connection, now, '이번 시간 기록'),
      _log(LogFilter.delivery, now.subtract(const Duration(days: 1)), '어제 기록'),
    ];
    await _pumpScreen(tester, logs);
    expect(find.text('이번 시간 기록'), findsOneWidget);
    expect(find.text('어제 기록'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('${now.hour}시 1건'));
    await tester.pump();
    expect(find.text('${now.hour}시 기록'), findsOneWidget);
    expect(find.text('이번 시간 기록'), findsOneWidget);
    expect(find.text('어제 기록'), findsNothing);

    await tester.tap(find.text('모든 시간'));
    await tester.pump();
    expect(find.text('어제 기록'), findsOneWidget);
  });

  testWidgets('숫자 칸을 누르면 그 분류의 로그만 — 막대는 전체에서만', (tester) async {
    final now = DateTime.now();
    await _pumpScreen(tester, [
      _log(LogFilter.emergencyStop, now, '비상정지 기록'),
      _log(LogFilter.delivery, now, '배송 기록'),
    ]);
    expect(find.byType(LogTodaySummary), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('긴급 정지 1건'));
    await tester.pump();
    expect(find.byType(LogTodaySummary), findsNothing);
    expect(find.text('비상정지 기록'), findsOneWidget);
    expect(find.text('배송 기록'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, '전체'));
    await tester.pump();
    expect(find.byType(LogTodaySummary), findsOneWidget);
    expect(find.text('배송 기록'), findsOneWidget);
  });

  testWidgets('다른 분류 칩에는 막대가 없고, 고른 시는 풀린다', (tester) async {
    final now = DateTime.now();
    await _pumpScreen(tester, [
      _log(LogFilter.connection, now, '연결 기록'),
      _log(LogFilter.connection, now.subtract(const Duration(days: 1)),
          '어제 연결 기록'),
    ]);
    await tester.tap(find.bySemanticsLabel('${now.hour}시 1건'));
    await tester.pump();
    expect(find.text('어제 연결 기록'), findsNothing);

    final chip = find.widgetWithText(ChoiceChip, '연결 상태');
    await tester.ensureVisible(chip); // 칩 줄은 가로로 밀립니다
    await tester.pump();
    await tester.tap(chip);
    await tester.pump();
    expect(find.byType(LogTodaySummary), findsNothing);
    expect(find.text('연결 기록'), findsOneWidget);
    expect(find.text('어제 연결 기록'), findsOneWidget);
  });

  testWidgets('기록이 없으면 숫자 줄·막대를 그리지 않는다', (tester) async {
    await _pumpScreen(tester, const []);
    expect(find.byType(LogTodaySummary), findsNothing);
    expect(find.text('표시할 로그가 없습니다.'), findsOneWidget);
  });

  for (final (size, scale) in [
    (const Size(320, 640), 1.0),
    (const Size(320, 640), 1.6),
    (const Size(390, 844), 2.0),
  ]) {
    testWidgets('좁은 폭·큰 글씨에서도 넘치지 않는다 ${size.width.toInt()}×$scale',
        (tester) async {
      final now = DateTime.now();
      await _pumpScreen(
        tester,
        [
          for (final f in kLogSummaryFilters)
            _log(f, now, '${f.label} 기록이 꽤 길게 적힌 경우'),
        ],
        size: size,
        textScale: scale,
      );
      await tester.tap(find.bySemanticsLabel('${now.hour}시 5건'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
