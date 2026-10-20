import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vica_supervisor/core/app_mode.dart';
import 'package:vica_supervisor/models/stack_status.dart';
import 'package:vica_supervisor/providers/app_mode_provider.dart';
import 'package:vica_supervisor/providers/auth_provider.dart';
import 'package:vica_supervisor/providers/settings_provider.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';
import 'package:vica_supervisor/screens/mode_select_screen.dart';
import 'package:vica_supervisor/widgets/vica_ui.dart';

class _FakeSupervisor extends SupervisorProvider {
  void injectStack(StackStatus? status) => setStackStatusForTest(status);
}

StackStatus stack({
  List<String> nodes = const [],
  List<String> odomPublishers = const [],
}) {
  return StackStatus(
    nodes: nodes,
    odomPublishers: odomPublishers,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<AppModeProvider> pump(
    WidgetTester tester,
    _FakeSupervisor supervisor, {
    StackStatus? status,
  }) async {
    final modeProvider = AppModeProvider();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 1600);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SupervisorProvider>.value(value: supervisor),
          ChangeNotifierProvider<AppModeProvider>.value(value: modeProvider),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ChangeNotifierProvider(create: (_) => AuthProvider()),
        ],
        child: const MaterialApp(home: ModeSelectScreen()),
      ),
    );
    await tester.pump();
    if (status != null) {
      supervisor.injectStack(status);
      await tester.pump();
    }
    return modeProvider;
  }

  testWidgets('두 모드 카드를 제목과 부제로 보여준다', (tester) async {
    await pump(tester, _FakeSupervisor());

    expect(find.text('주행'), findsOneWidget);
    expect(find.text('지도 설정·원격 주행 등 관리'), findsOneWidget);
    expect(find.text('지도'), findsOneWidget);
    expect(find.text('새 지도 그리기'), findsOneWidget);
  });

  testWidgets('연결하지 않았으면 확인 불가로 두되 들어갈 수는 있다', (tester) async {
    final modeProvider = await pump(tester, _FakeSupervisor());

    expect(
      find.textContaining(vicaKeepWords('로봇 상태를 확인할 수 없습니다')),
      findsOneWidget,
    );
    expect(find.textContaining('확인 불가'), findsNWidgets(2));

    await tester.tap(find.text('주행'));
    await tester.pump();
    expect(modeProvider.mode, AppMode.drive);
  });

  testWidgets('Nav2 가 떠 있으면 지도 카드를 막는다', (tester) async {
    final modeProvider = await pump(
      tester,
      _FakeSupervisor(),
      status: stack(nodes: ['/amcl', '/bt_navigator']),
    );

    expect(find.textContaining('Nav2 실행 중'), findsOneWidget);

    await tester.tap(find.text('지도'));
    await tester.pump();
    expect(modeProvider.mode, isNull, reason: '막힌 카드는 눌려도 들어가면 안 된다');

    await tester.tap(find.text('주행'));
    await tester.pump();
    expect(modeProvider.mode, AppMode.drive);
  });

  testWidgets('매핑이 떠 있으면 주행 카드를 막는다', (tester) async {
    final modeProvider = await pump(
      tester,
      _FakeSupervisor(),
      status: stack(nodes: ['/cartographer_node']),
    );

    expect(find.textContaining('매핑 실행 중'), findsOneWidget);

    await tester.tap(find.text('주행'));
    await tester.pump();
    expect(modeProvider.mode, isNull);
  });

  testWidgets('두 벌이 돌면 양쪽을 막고 무엇이 겹쳤는지 알린다', (tester) async {
    final modeProvider = await pump(
      tester,
      _FakeSupervisor(),
      status: stack(nodes: ['/ekf_filter_node', '/ekf_filter_node']),
    );

    expect(find.text('스택이 중복 실행 중입니다'), findsOneWidget);
    expect(find.textContaining('/ekf_filter_node'), findsOneWidget);
    expect(find.textContaining('이미 충돌 중'), findsNWidgets(2));

    await tester.tap(find.text('주행'));
    await tester.tap(find.text('지도'));
    await tester.pump();
    expect(modeProvider.mode, isNull);
  });

  testWidgets('아무것도 안 떠 있으면 양쪽 다 준비됨이다', (tester) async {
    await pump(
      tester,
      _FakeSupervisor(),
      status: stack(nodes: ['/rosapi', '/rosbridge_websocket']),
    );

    expect(find.textContaining('준비됨'), findsNWidgets(2));
    expect(find.text('스택이 중복 실행 중입니다'), findsNothing);
  });
}
