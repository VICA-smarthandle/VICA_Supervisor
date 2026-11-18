// 모드 선택 화면의 표시·차단 규칙을 고정합니다.
//
// 이 화면의 존재 이유는 "고르게 하는 것"보다 "중복 실행으로 들어가지 못하게 막는 것"에
// 가깝습니다. 그래서 카드가 뜨는지보다 언제 막히는지를 더 촘촘히 검증합니다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vica_supervisor/core/app_mode.dart';
import 'package:vica_supervisor/models/mode_status.dart';
import 'package:vica_supervisor/models/stack_status.dart';
import 'package:vica_supervisor/providers/app_mode_provider.dart';
import 'package:vica_supervisor/providers/auth_provider.dart';
import 'package:vica_supervisor/providers/settings_provider.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';
import 'package:vica_supervisor/screens/mode_select_screen.dart';
import 'package:vica_supervisor/widgets/vica_ui.dart';

class _FakeSupervisor extends SupervisorProvider {
  void injectStack(StackStatus? status) => setStackStatusForTest(status);
  void injectMode(ModeStatus? status) => setModeStatusForTest(status);

  final calls = <String>[];
  (bool, String) reply = (true, '');

  @override
  Future<(bool, String)> driveStart() async {
    calls.add('drive_start');
    return reply;
  }

  @override
  Future<(bool, String)> driveStop() async {
    calls.add('drive_stop');
    return reply;
  }

  @override
  Future<(bool, String)> setVoice(VoiceChoice choice) async {
    calls.add('voice_${choice.wire}');
    return reply;
  }
}

ModeStatus mode(String m, ModeState state, {List<String> stopTimeouts = const []}) =>
    ModeStatus(mode: m, state: state, stopTimeouts: stopTimeouts);

// 주행 카드를 누르면 하위 모드 시트가 뜹니다(2026-11-16 목업 '안 2'). 그중 하나를 고릅니다.
Future<void> chooseSubmode(WidgetTester tester, String title) async {
  await tester.tap(find.text('주행'));
  await tester.pumpAndSettle();
  expect(find.text('주행 모드 선택'), findsOneWidget);
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
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
    expect(find.text('안내·배송·경비'), findsOneWidget);
    expect(find.text('지도'), findsOneWidget);
    expect(find.text('새 지도 그리기'), findsOneWidget);
  });

  testWidgets('연결하지 않았으면 확인 불가로 두되 들어갈 수는 있다', (tester) async {
    // 막으면 연결이 안 되는 상황에서 사람이 갇힙니다. 대신 모른다는 사실을 숨기지 않습니다.
    final modeProvider = await pump(tester, _FakeSupervisor());

    // 안내문은 어절 단위 줄바꿈(vicaKeepWords)을 거치므로 같은 변환으로 찾습니다.
    expect(
      find.textContaining(vicaKeepWords('오프라인 · 상태')),  // 2026-11-17 온라인/오프라인
      findsOneWidget,
    );
    expect(find.textContaining('확인 불가'), findsNWidgets(2));

    await chooseSubmode(tester, '안내·배송');
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
    await chooseSubmode(tester, '안내·배송');
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

  group('모드 노드가 있을 때(부팅 자동 기동, 2026-11-16)', () {
    testWidgets('모드 노드가 없으면 경비를 골라도 화면만 바꾸고 경비 탭으로 간다', (tester) async {
      final supervisor = _FakeSupervisor();
      final modeProvider = await pump(tester, supervisor);

      await chooseSubmode(tester, '경비');

      expect(supervisor.calls, isEmpty, reason: '모드 노드가 없으면 주행 묶음을 켜지 않는다');
      expect(modeProvider.mode, AppMode.drive);
      expect(modeProvider.driveSubmode, DriveSubmode.patrol);
      expect(modeProvider.landingTab, '경비');
    });

    testWidgets('꺼져 있으면 주행 묶음을 켜고 준비 화면으로 간다', (tester) async {
      final supervisor = _FakeSupervisor();
      final modeProvider = await pump(tester, supervisor);
      supervisor.injectMode(mode('idle', ModeState.idle));
      await tester.pump();

      expect(find.textContaining('꺼져 있음'), findsOneWidget);
      await chooseSubmode(tester, '경비');

      expect(supervisor.calls, ['drive_start']);
      expect(find.text('주행 시작'), findsOneWidget);
      expect(find.text('경비 모드'), findsOneWidget);
      expect(modeProvider.mode, isNull, reason: '다 켜지기 전에는 주행 화면에 들어가지 않는다');
    });

    testWidgets('켜기가 거부되면 이유를 보여 주고 머문다', (tester) async {
      final supervisor = _FakeSupervisor()..reply = (false, '지도 그리기 중입니다(running).');
      await pump(tester, supervisor);
      supervisor.injectMode(mode('idle', ModeState.idle));
      await tester.pump();

      await chooseSubmode(tester, '안내·배송');

      expect(find.text('주행을 켜지 못했습니다'), findsOneWidget);
      expect(find.textContaining(vicaKeepWords('지도 그리기 중입니다')), findsOneWidget);
      expect(find.text('주행 시작'), findsNothing);
    });

    testWidgets('다 켜져 있으면 고른 하위 모드로 바로 들어간다', (tester) async {
      final supervisor = _FakeSupervisor();
      final modeProvider = await pump(tester, supervisor);
      supervisor.injectMode(mode('drive', ModeState.running));
      await tester.pump();

      await chooseSubmode(tester, '안내·배송');

      expect(supervisor.calls, isEmpty);
      expect(modeProvider.mode, AppMode.drive);
      expect(modeProvider.landingTab, isNull);
    });

    testWidgets('주행이 켜진 채 지도를 누르면 끌지 묻고, 끄면 지도로 바꾸는 화면으로 간다', (tester) async {
      final supervisor = _FakeSupervisor();
      await pump(tester, supervisor);
      supervisor.injectMode(mode('drive', ModeState.needInitialPose));
      await tester.pump();

      expect(find.textContaining('주행 켜짐'), findsOneWidget);
      await tester.tap(find.text('지도'));
      await tester.pumpAndSettle();
      expect(find.text('주행을 끄고 지도 그리기로 갈까요?'), findsOneWidget);

      await tester.tap(find.text('주행 끄고 지도로'));
      await tester.pumpAndSettle();

      expect(supervisor.calls, ['drive_stop']);
      expect(find.text('지도로 바꾸기'), findsOneWidget);
    });

    testWidgets('끄는 중에는 지도 카드를 막는다', (tester) async {
      final supervisor = _FakeSupervisor();
      final modeProvider = await pump(tester, supervisor);
      supervisor.injectMode(mode('drive', ModeState.stopping));
      await tester.pump();

      await tester.tap(find.text('지도'));
      await tester.pumpAndSettle();
      expect(modeProvider.mode, isNull);
      expect(find.textContaining('주행 끄는 중'), findsOneWidget);
    });

    testWidgets('지난 끄기에서 강제 종료가 있었으면 알린다', (tester) async {
      final supervisor = _FakeSupervisor();
      await pump(tester, supervisor);
      supervisor.injectMode(mode('idle', ModeState.idle, stopTimeouts: ['nav2', 'posecheck']));
      await tester.pump();

      expect(find.text('지난 주행 끄기가 늦었습니다'), findsOneWidget);
      expect(find.textContaining(vicaKeepWords('Nav2, 위치 확인')), findsOneWidget);
    });
  });

  testWidgets('시트에서 음성을 외부 API 로 바꾸면 켜기 전에 음성부터 바꾼다', (tester) async {
    final supervisor = _FakeSupervisor();
    await pump(tester, supervisor);
    supervisor.injectMode(mode('idle', ModeState.idle));
    await tester.pump();

    await tester.tap(find.text('주행'));
    await tester.pumpAndSettle();
    expect(find.text('로컬(LOCAL)'), findsOneWidget);
    await tester.tap(find.text('로컬(LOCAL)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('외부 API').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('안내·배송'));
    await tester.pumpAndSettle();

    expect(supervisor.calls, ['voice_online', 'drive_start']);
  });

  testWidgets('모드 노드가 없으면 시트에 음성 칸이 없다', (tester) async {
    await pump(tester, _FakeSupervisor());
    await tester.tap(find.text('주행'));
    await tester.pumpAndSettle();
    expect(find.text('주행 모드 선택'), findsOneWidget);
    expect(find.text('로컬(LOCAL)'), findsNothing);
  });
}
