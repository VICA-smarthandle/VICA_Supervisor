// '로봇 끄기'(2026-11-18 사용자 결정, 목업 '로봇 끄기 A', 문구 추천안).
//
// 확인 창을 거쳐서만 /vica/mode/shutdown 을 부르고, 종료 중 화면은 보이는 사실(주행 꺼짐 · 연결 끊김 ·
// 끊긴 뒤 30초)로만 단계를 그린다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vica_supervisor/app.dart';
import 'package:vica_supervisor/models/mode_status.dart';
import 'package:vica_supervisor/providers/settings_provider.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';
import 'package:vica_supervisor/ros/ros_bridge_client.dart';
import 'package:vica_supervisor/screens/robot_shutdown_screen.dart';
import 'package:vica_supervisor/widgets/vica_ui.dart';

class _FakeSupervisor extends SupervisorProvider {
  final calls = <String>[];
  (bool, String) reply = (true, '로봇을 끕니다. 곧 연결이 끊깁니다.');
  RosConnectionState state = RosConnectionState.connected;

  @override
  RosConnectionState get connectionState => state;

  void lose() {
    state = RosConnectionState.disconnected;
    notifyListeners();
  }

  @override
  Future<(bool, String)> robotShutdown() async {
    calls.add('shutdown');
    return reply;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<_FakeSupervisor> pump(WidgetTester tester, Widget home, {ModeStatus? status}) async {
    final supervisor = _FakeSupervisor()..setModeStatusForTest(status);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SupervisorProvider>.value(value: supervisor),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ],
        child: MaterialApp(theme: vicaTheme(), home: home),
      ),
    );
    await tester.pump();
    return supervisor;
  }

  Widget opener() => Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => confirmAndShutdownRobot(context),
              child: const Text('열기'),
            ),
          ),
        ),
      );

  final confirm = find.widgetWithText(FilledButton, '로봇 끄기');

  testWidgets('확인 창을 거쳐서만 끄고, 종료 중 화면을 연다', (tester) async {
    final supervisor = await pump(tester, opener());
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    expect(find.text('로봇을 끌까요?'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(supervisor.calls, isEmpty);

    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    await tester.tap(confirm);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(supervisor.calls, ['shutdown']);
    expect(find.byType(RobotShutdownScreen), findsOneWidget);
    expect(find.text('종료 중'), findsOneWidget);
  });

  testWidgets('거절되면 이유를 띄우고 종료 중 화면을 열지 않는다', (tester) async {
    final supervisor = await pump(tester, opener());
    supervisor.reply = (false, '주행 중입니다. 멈춘 뒤 끕니다.');
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(find.text('로봇을 끄지 못했습니다'), findsOneWidget);
    expect(find.text(vicaKeepWords(vicaBreakAtSentences('주행 중입니다. 멈춘 뒤 끕니다.'))), findsOneWidget);
    expect(find.byType(RobotShutdownScreen), findsNothing);
  });

  testWidgets('연결이 끊기고 30초가 지나야 전원을 꺼도 된다고 한다', (tester) async {
    var now = DateTime(2026, 11, 18, 10, 0);
    final supervisor = await pump(
      tester,
      RobotShutdownScreen(now: () => now),
      status: const ModeStatus(mode: 'idle', state: ModeState.idle),
    );
    expect(find.text('전원을 꺼도 됩니다'), findsNothing);
    // 시스템 종료 단계의 안내는 연결이 끊긴 뒤에만 보인다.
    expect(find.textContaining('연결이 끊기고 30초 뒤 완료'), findsNothing);

    supervisor.lose();
    await tester.pump();
    expect(find.textContaining('연결이 끊기고 30초 뒤 완료'), findsOneWidget);

    now = now.add(const Duration(seconds: 29));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('전원을 꺼도 됩니다'), findsNothing);

    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('전원을 꺼도 됩니다'), findsOneWidget);
    expect(find.text('종료가 끝났습니다.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
