// 모드 선택 화면의 표시·차단 규칙을 고정합니다.
//
// 이 화면의 존재 이유는 "고르게 하는 것"보다 "중복 실행으로 들어가지 못하게 막는 것"에
// 가깝습니다. 그래서 카드가 뜨는지보다 언제 막히는지를 더 촘촘히 검증합니다.
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
    checkedAt: DateTime(2026, 8, 21),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  // 상태는 화면이 뜬 뒤에 주입합니다. 화면이 initState 에서 refreshStackStatus 를
  // 부르는데, 연결이 없으면 그 호출이 status 를 비우기 때문입니다. 실제 순서도
  // "화면이 먼저 뜨고 조회 결과가 나중에 온다" 이므로 이쪽이 실제와 같습니다.
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
    expect(find.text('장소 저장·원격 주행 등 관리'), findsOneWidget);
    expect(find.text('지도'), findsOneWidget);
    expect(find.text('새 지도 그리기'), findsOneWidget);
  });

  testWidgets('연결하지 않았으면 확인 불가로 두되 들어갈 수는 있다', (tester) async {
    // 막으면 연결이 안 되는 상황에서 사람이 갇힙니다. 대신 모른다는 사실을 숨기지 않습니다.
    final modeProvider = await pump(tester, _FakeSupervisor());

    expect(find.textContaining('로봇 상태를 확인할 수 없습니다'), findsOneWidget);
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

    // 주행 쪽은 열려 있어야 합니다.
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
