// 도킹 화면(2026-11-18, 목업 62~73)을 고정합니다 — 원격 주행 탭의 버튼 배치·잠김과
// 지도 설정의 도크 위치 칸. 폭(폰·태블릿·웹)과 글자 배율을 바꿔도 넘치지 않는지도 봅니다.
//
// 도크 위치 지정 v2(2026-11-19, 목업 84~92): 도크 위치 칸의 다섯 상태와 지도에서 지정하는
// 세 단계, 인식 저장 실패 팝업 넷, 도킹 실패 팝업 변형의 문구·버튼도 여기서 고정합니다.
// 지도 설정 화면 안의 흐름(누름 → 저장 요청)은 dock_position_flow_test.dart 에 있습니다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vica_supervisor/core/app_settings.dart';
import 'package:vica_supervisor/models/dock_state.dart';
import 'package:vica_supervisor/models/goal_event.dart';
import 'package:vica_supervisor/models/home_position.dart';
import 'package:vica_supervisor/models/stack_status.dart';
import 'package:vica_supervisor/providers/settings_provider.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';
import 'package:vica_supervisor/screens/map_locations_screen.dart';
import 'package:vica_supervisor/app.dart' show vicaTheme;
import 'package:vica_supervisor/widgets/dock_dialogs.dart';
import 'package:vica_supervisor/widgets/dock_position_card.dart';
import 'package:vica_supervisor/widgets/goal_alert_dialog.dart';
import 'package:vica_supervisor/widgets/vica_ui.dart';

const _map = 'starlight_1f';

class _Supervisor extends SupervisorProvider {
  int dockStarts = 0;
  int undocks = 0;
  int dockCancels = 0;

  @override
  Future<String> startDocking(AppSettings settings) async {
    dockStarts += 1;
    return '도킹을 시작합니다.';
  }

  @override
  Future<String> undock(AppSettings settings) async {
    undocks += 1;
    return '도크에서 나옵니다.';
  }

  @override
  Future<String> cancelDocking(AppSettings settings) async {
    dockCancels += 1;
    return '멈췄습니다.';
  }

  void prepare({
    String dialog = '',
    String goal = '',
    bool dock = true,
    bool home = true,
    Map<String, Object?>? node,
  }) {
    handleMapListForTest({
      'maps': [
        {
          'map_id': _map,
          'map_name': _map,
          'resolution': 0.05,
          'origin_x': 0.0,
          'origin_y': 0.0,
          'width': 200,
          'height': 200,
        },
      ],
    });
    handleRobotStatusForTest({
      'robot_id': 'vica_robot_01',
      'robot_name': 'VICA 1호기',
      'status': goal.isEmpty ? 'idle' : 'moving',
      'x': 1.0,
      'y': 2.0,
      'yaw': 0.0,
      'current_goal': goal,
      'map_id': _map,
      'dialog_state': dialog,
    });
    setStackStatusForTest(const StackStatus(
      nodes: ['/amcl', '/bt_navigator'],
      odomPublishers: ['/ekf_filter_node'],
    ));
    if (dock) {
      setDockSpotForTest(_map, _spot());
    }
    if (node != null) {
      // 실제 앱과 같은 모양: rosbridge 클라이언트가 data 를 풀어 넘긴 맵(11-19 실기 버그 뒤 바꿈)
      handleDockStateForTest(Map<String, Object?>.from(node));
    }
    if (home) {
      setHomeForTest(_map, const HomePosition(
        x: 6.1, y: 2.4, yaw: 90, source: HomeSource.robotStanding, score: 90,
        label: '', visitedOk: true, savedAt: '2026-11-18T10:00:00'));
    }
  }
}

DockSpot _spot({
  bool visited = false,
  String source = kDockSourceVDetect,
  bool refined = false,
  String refinedFrom = '',
}) =>
    DockSpot(
      mapId: _map,
      dockedX: 1.0,
      dockedY: 3.0,
      dockedYaw: 1.57,
      stagingX: 1.0,
      stagingY: 2.0,
      stagingYaw: 1.57,
      savedAt: '2026-11-18T21:00:00',
      visitedOk: visited,
      source: source,
      refined: refined,
      refinedFrom: refinedFrom,
      refinedCm: refined ? 18 : 0,
      refinedDeg: refined ? 9 : 0,
    );

/// 도크 위치 칸의 다섯 상태(목업 84·85·91): 미지정 · 도크 인식 미확인 · 지도 지정 미확인 ·
/// 가 본 자리 · 가 본 자리 + 고쳐 저장함.
List<DockSpot?> _fiveStates() => [
      null,
      _spot(),
      _spot(source: kDockSourceMapPick),
      _spot(visited: true),
      _spot(
        visited: true,
        source: kDockSourceMapPick,
        refined: true,
        refinedFrom: kDockSourceMapPick,
      ),
    ];

/// 도크 위치 칸 하나. 누른 버튼 이름을 [pressed] 에 적습니다.
Widget _card({
  DockSpot? spot,
  bool busy = false,
  bool locked = false,
  String blockedReason = '',
  DockPickStage stage = DockPickStage.none,
  List<String>? pressed,
}) =>
    SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: DockPositionCard(
        spot: spot,
        busy: busy,
        locked: locked,
        canSendRobot: blockedReason.isEmpty,
        blockedReason: blockedReason,
        onSave: () => pressed?.add('save'),
        onTryDock: () => pressed?.add('try'),
        onDelete: () => pressed?.add('delete'),
        onStartMapPick: () => pressed?.add('map'),
        pickStage: stage,
        onPickAgain: () => pressed?.add('again'),
        onPickCancel: () => pressed?.add('cancel'),
        onPickSave: () => pressed?.add('pickSave'),
      ),
    );

/// 팝업을 여는 버튼 하나만 있는 화면. 고른 값은 [onResult] 로 돌려줍니다.
class _DialogHost extends StatelessWidget {
  const _DialogHost({required this.open, this.onResult});

  final Future<Object?> Function(BuildContext context) open;
  final ValueChanged<Object?>? onResult;

  @override
  Widget build(BuildContext context) => Center(
        child: TextButton(
          // onResult 가 없어도 팝업은 열어야 합니다(?. 는 인자 계산까지 건너뜁니다).
          onPressed: () async {
            final result = await open(context);
            onResult?.call(result);
          },
          child: const Text('열기'),
        ),
      );
}

const _unstableFar = DockRegisterResult(
    ok: false, reason: 'unstable', distM: 2.6, bearingDeg: 20, obliqueDeg: 50);

GoalEvent _dockFail(String reason, {bool firstTry = false}) {
  final event = GoalEvent.fromJson({'event': 'dock_failed', 'reason': reason}, id: 'x');
  return firstTry ? event.asDockFirstTry() : event;
}

Widget _app(Widget child, SupervisorProvider supervisor, {double scale = 1.0}) => MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<SupervisorProvider>.value(value: supervisor),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ],
        child: MaterialApp(
          theme: vicaTheme(),
          home: Scaffold(body: child),
        ),
      ),
    );

/// 도킹 노드 상태: 도크 가까이 서 있음(도킹을 중지한 자리 등) — 나오다 멈춘 것은 아니다.
const _nearNode = <String, Object?>{
  'state': 'idle',
  'near_dock': true,
  'undock_pending': false,
  'last': {'action': 'dock', 'result': 'failed', 'reason': 'canceled'},
};

/// 도킹 노드 상태: 나오다 멈춤(11-19).
const _pendingNode = <String, Object?>{
  'state': 'idle',
  'near_dock': false,
  'undock_pending': true,
  'last': {'action': 'undock', 'result': 'failed', 'reason': 'estop'},
};

Future<_Supervisor> _pump(WidgetTester tester,
    {String dialog = '',
    String goal = '',
    bool dock = true,
    bool home = true,
    Map<String, Object?>? node}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 2400);
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
  final s = _Supervisor()
    ..prepare(dialog: dialog, goal: goal, dock: dock, home: home, node: node);
  await tester.pumpWidget(_app(const MapLocationsScreen(), s));
  await tester.pump();
  return s;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('62 대기 중 — 홈으로 복귀 옆에 도킹 시작, 누르면 확인 뒤 미션에 요청', (tester) async {
    final s = await _pump(tester);
    expect(find.widgetWithText(OutlinedButton, '홈으로 복귀'), findsOneWidget);
    final dock = find.widgetWithText(OutlinedButton, '도킹 시작');
    expect(dock, findsOneWidget);
    // 한 줄에 반씩
    expect(tester.getTopLeft(dock).dy,
        tester.getTopLeft(find.widgetWithText(OutlinedButton, '홈으로 복귀')).dy);
    await tester.tap(dock);
    await tester.pumpAndSettle();
    expect(find.textContaining(vicaKeepWords('도크 앞으로 이동한 뒤')), findsOneWidget);
    await tester.tap(find.text('시작'));
    await tester.pumpAndSettle();
    expect(s.dockStarts, 1);
  });

  testWidgets('도크 위치가 없으면 도킹 시작이 없다', (tester) async {
    await _pump(tester, dock: false);
    expect(find.widgetWithText(OutlinedButton, '도킹 시작'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, '홈으로 복귀'), findsOneWidget);
  });

  testWidgets('63·64 도킹 중 — 잠긴 도킹 중·도킹 중지만, 상태 줄과 아래 버튼 없음', (tester) async {
    final s = await _pump(tester, dialog: kDialogDocking);
    expect(find.widgetWithText(FilledButton, '도킹 중'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '도킹 중지'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '홈으로 복귀'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, '도킹 시작'), findsNothing);
    expect(find.textContaining('도크 앞으로 가는 중'), findsNothing);
    await tester.tap(find.widgetWithText(OutlinedButton, '도킹 중지'));
    await tester.pumpAndSettle();
    expect(find.text('중지하기'), findsOneWidget);
    await tester.tap(find.text('중지하기'));
    await tester.pumpAndSettle();
    expect(s.dockCancels, 1);
  });

  testWidgets('66 도크에 들어가 있음 — 상태 줄 두 줄, 주행 요청 열림, 도크에서 나오기', (tester) async {
    final s = await _pump(tester, dialog: kDialogDocked);
    expect(find.textContaining(vicaKeepWords('도크에 들어가 있습니다.')), findsOneWidget);
    expect(find.textContaining(vicaKeepWords('장소를 고르면 도크에서 먼저 나온 뒤 출발합니다.')),
        findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '도킹 시작'), findsNothing);
    final out = find.widgetWithText(OutlinedButton, '도크에서 나오기');
    expect(out, findsOneWidget);
    await tester.tap(out);
    await tester.pumpAndSettle();
    expect(find.textContaining(vicaKeepWords('초음파를 켜고 약 70cm 후진 후')), findsOneWidget);
    expect(find.textContaining(vicaKeepWords('주행 모드로 전환됩니다.')), findsOneWidget);
    await tester.tap(find.text('나오기'));
    await tester.pumpAndSettle();
    expect(s.undocks, 1);
  });

  testWidgets('68 나오는 중 — 나오는 중·나오기 중지만', (tester) async {
    await _pump(tester, dialog: kDialogUndocking);
    expect(find.widgetWithText(FilledButton, '나오는 중'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '나오기 중지'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '도크에서 나오기'), findsNothing);
  });

  testWidgets('나오다 멈춤 — 도킹 시작은 없고, 홈 아래 도크에서 나오기 다시시작만(11-19 사용자)', (tester) async {
    final s = await _pump(tester, node: _pendingNode);
    final home = find.widgetWithText(OutlinedButton, '홈으로 복귀');
    final out = find.widgetWithText(OutlinedButton, '도크에서 나오기 다시시작');
    expect(home, findsOneWidget);
    expect(out, findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '도킹 시작'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, '도크에서 나오기'), findsNothing);
    // 홈은 한 줄, 그 아래 한 줄(글자가 길어 반씩 놓지 않는다)
    expect(tester.getTopLeft(home).dy, lessThan(tester.getTopLeft(out).dy));
    expect(tester.getSize(out).width, tester.getSize(home).width);
    // 도크 안이 아니다 — 도크 상태 줄은 없다
    expect(find.textContaining(vicaKeepWords('도크에 들어가 있습니다.')), findsNothing);
    await tester.tap(out);
    await tester.pumpAndSettle();
    expect(find.textContaining(vicaKeepWords('남은 나오기 동작을 이어서 합니다.')), findsOneWidget);
    expect(find.textContaining(vicaKeepWords('초음파를 켜고 약 70cm 후진 후')), findsNothing);
    await tester.tap(find.text('나오기'));
    await tester.pumpAndSettle();
    expect(s.undocks, 1);
    expect(s.dockStarts, 0);
  });

  testWidgets('나오다 멈춤 — 도크 위치가 없어도 홈 아래 다시시작', (tester) async {
    await _pump(tester, dock: false, node: _pendingNode);
    final home = find.widgetWithText(OutlinedButton, '홈으로 복귀');
    final out = find.widgetWithText(OutlinedButton, '도크에서 나오기 다시시작');
    expect(find.widgetWithText(OutlinedButton, '도킹 시작'), findsNothing);
    expect(tester.getTopLeft(home).dy, lessThan(tester.getTopLeft(out).dy));
  });

  testWidgets('도크 가까이 서 있음(나오다 멈춘 것은 아님) — 홈 한 줄, 그 아래 도킹 시작·도크에서 나오기 반씩', (tester) async {
    final s = await _pump(tester, node: _nearNode);
    final home = find.widgetWithText(OutlinedButton, '홈으로 복귀');
    final dock = find.widgetWithText(OutlinedButton, '도킹 시작');
    final out = find.widgetWithText(OutlinedButton, '도크에서 나오기');
    expect(home, findsOneWidget);
    expect(dock, findsOneWidget);
    expect(out, findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '도크에서 나오기 다시시작'), findsNothing);
    expect(tester.getTopLeft(dock).dy, tester.getTopLeft(out).dy);
    expect(tester.getTopLeft(dock).dx, lessThan(tester.getTopLeft(out).dx));
    expect(tester.getTopLeft(home).dy, lessThan(tester.getTopLeft(dock).dy));
    await tester.tap(out);
    await tester.pumpAndSettle();
    await tester.tap(find.text('나오기'));
    await tester.pumpAndSettle();
    expect(s.undocks, 1);
  });

  testWidgets('나오다 멈춤이어도 다른 주행 중이면 나오기 버튼은 없다(기존 잠김 규칙)', (tester) async {
    await _pump(tester, goal: '3층 대회의실', node: _pendingNode);
    expect(find.widgetWithText(OutlinedButton, '도크에서 나오기'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, '도크에서 나오기 다시시작'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, '주행 중에는 도킹을 시작할 수 없습니다'), findsOneWidget);
  });

  testWidgets('다른 주행 중 — 홈·도킹 둘 다 잠기고 한 줄씩', (tester) async {
    await _pump(tester, goal: '3층 대회의실');
    final dock = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, '주행 중에는 도킹을 시작할 수 없습니다'));
    expect(dock.onPressed, isNull);
  });

  group('폭과 글자 배율을 바꿔도 넘치지 않는다', () {
    const widths = <double>[320, 360, 390, 600, 900, 1440];
    const scales = <double>[1.0, 1.3];

    Future<void> check(WidgetTester tester, String name, String dialog, String goal,
        Widget Function() screen, {Map<String, Object?>? node}) async {
      for (final scale in scales) {
        for (final width in widths) {
          final errors = <String>[];
          final previous = FlutterError.onError;
          FlutterError.onError = (details) => errors.add(details.exceptionAsString().split('\n').first);
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 2400);
          final s = _Supervisor()..prepare(dialog: dialog, goal: goal, node: node);
          await tester.pumpWidget(_app(screen(), s, scale: scale));
          await tester.pump();
          FlutterError.onError = previous;
          expect(errors, isEmpty, reason: '$name 이 폭 $width, 글자 배율 $scale 에서 넘쳤습니다.');
          await tester.pumpWidget(const SizedBox.shrink());
          s.dispose();
        }
      }
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    }

    testWidgets('원격 주행 — 대기·도킹 중·도크 안·나오는 중·주행 중', (tester) async {
      for (final (dialog, goal) in [
        ('', ''),
        (kDialogDocking, ''),
        (kDialogDocked, ''),
        (kDialogUndocking, ''),
        ('', '3층 대회의실'),
      ]) {
        await check(tester, '원격 주행($dialog$goal)', dialog, goal, () => const MapLocationsScreen());
      }
      await check(tester, '원격 주행(나오다 멈춤)', '', '', () => const MapLocationsScreen(),
          node: _pendingNode);
      await check(tester, '원격 주행(도크 가까이)', '', '', () => const MapLocationsScreen(),
          node: _nearNode);
    });

    testWidgets('지도 설정 — 도크 위치 칸 다섯 상태와 찾는 중', (tester) async {
      for (final (i, spot) in _fiveStates().indexed) {
        await check(tester, '도크 위치 칸(상태 $i)', '', '', () => _card(spot: spot));
        await check(tester, '도크 위치 칸(상태 $i, 찾는 중)', '', '',
            () => _card(spot: spot, busy: true));
        await check(tester, '도크 위치 칸(상태 $i, 다른 지도라 잠김)', '', '',
            () => _card(spot: spot, locked: true));
      }
      await check(
          tester,
          '도크 위치 칸(로봇을 못 움직임)',
          '',
          '',
          () => _card(
              spot: _spot(),
              blockedReason: '안내 주행 중에는 홈을 다룰 수 없습니다. '
                  '사용자가 핸들을 잡고 따라 걷는 중이라 방향을 바꾸면 위험합니다. 먼저 주행을 취소하세요.'));
    });

    testWidgets('지도 설정 — 지도에서 지정 세 단계', (tester) async {
      for (final stage in [DockPickStage.dock, DockPickStage.front, DockPickStage.preview]) {
        await check(tester, '지도에서 지정($stage)', '', '', () => _card(stage: stage));
      }
    });

    /// 팝업을 열어 둔 채로 폭·글자 배율을 돌립니다. 폰 높이(800)에서 봅니다.
    Future<void> checkDialog(WidgetTester tester, String name,
        Future<Object?> Function(BuildContext context) open, {SupervisorProvider? using}) async {
      for (final scale in scales) {
        for (final width in widths) {
          final errors = <String>[];
          final previous = FlutterError.onError;
          FlutterError.onError =
              (details) => errors.add(details.exceptionAsString().split('\n').first);
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 800);
          final s = using ?? (_Supervisor()..prepare());
          await tester.pumpWidget(_app(_DialogHost(open: open), s, scale: scale));
          await tester.tap(find.text('열기'));
          await tester.pumpAndSettle();
          FlutterError.onError = previous;
          expect(find.byType(VicaDialog), findsOneWidget, reason: '$name 팝업이 뜨지 않았습니다.');
          expect(errors, isEmpty, reason: '$name 이 폭 $width, 글자 배율 $scale 에서 넘쳤습니다.');
          await tester.pumpWidget(const SizedBox.shrink());
          if (using == null) {
            s.dispose();
          }
        }
      }
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    }

    testWidgets('인식 저장 실패 팝업 넷', (tester) async {
      await checkDialog(tester, '도크를 찾지 못했습니다',
          (context) => showDockNotFoundDialog(context));
      await checkDialog(
          tester,
          '도크를 찾지 못했습니다(저장된 도크 있음)',
          (context) => showDockNotFoundDialog(context,
              savedDockHint: '저장된 도크는 로봇의 오른쪽 뒤 약 12.3 m에 있습니다.'));
      for (final result in const [
        _unstableFar,
        DockRegisterResult(
            ok: false, reason: 'unstable', distM: 1.4, bearingDeg: -38, obliqueDeg: 60),
        DockRegisterResult(
            ok: false, reason: 'unstable', distM: 1.2, bearingDeg: 2, obliqueDeg: 10),
      ]) {
        await checkDialog(tester, '도크 인식이 불안정합니다(${result.distM})',
            (context) => showDockUnstableDialog(context, result: result));
      }
      await checkDialog(tester, '초기 위치를 잡아 주세요', showDockNoPoseDialog);
      await checkDialog(tester, '주행이 꺼져 있습니다', showDockDriveOffDialog);
      await checkDialog(tester, '주행이 꺼져 있습니다(지도에서 지정 저장)',
          (context) => showDockDriveOffDialog(context, saving: true));
    });

    testWidgets('도킹 실패 팝업 — 다시 잡기 변형(92)과 기존 모양', (tester) async {
      for (final event in [
        _dockFail('not_found', firstTry: true),
        _dockFail('nav_failed', firstTry: true),
        _dockFail('not_found'),
      ]) {
        await checkDialog(
            tester,
            '도킹하지 못했습니다(${event.reason}, ${event.showsDockRedo})',
            (context) => showDialog<void>(
                context: context, builder: (_) => GoalAlertDialog(event: event)));
      }
    });
  });

  // ---- 도크 위치 지정 v2 (2026-11-19, 목업 84~92) ----

  group('도크 위치 칸의 다섯 상태(목업 84·85·91)', () {
    Future<List<String>> pumpCard(WidgetTester tester,
        {DockSpot? spot,
        bool busy = false,
        bool locked = false,
        String blockedReason = '',
        double width = 390}) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 1600);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });
      final pressed = <String>[];
      final s = _Supervisor()..prepare();
      await tester.pumpWidget(_app(
          _card(
            spot: spot,
            busy: busy,
            locked: locked,
            blockedReason: blockedReason,
            pressed: pressed,
          ),
          s));
      await tester.pump();
      return pressed;
    }

    /// 화면에 보이는 채움·테두리 버튼이 전부 눌리지 않는가.
    void expectAllButtonsOff(WidgetTester tester, int count) {
      final buttons = tester.widgetList<ButtonStyleButton>(find.byWidgetPredicate(
          (w) => w is FilledButton || w is OutlinedButton));
      expect(buttons.length, count);
      for (final button in buttons) {
        expect(button.onPressed, isNull);
      }
    }

    testWidgets('보는 지도가 주행 지도가 아니면(잠김) 미지정 칸의 두 버튼이 눌리지 않는다', (tester) async {
      final pressed = await pumpCard(tester, locked: true);
      // 글자는 그대로다 — 안내는 화면 위의 주행 지도 띠가 한다(새 문구 없음)
      expect(find.widgetWithText(FilledButton, '도크 인식해서 저장'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '지도에서 지정'), findsOneWidget);
      expect(find.text('도크 찾는 중…'), findsNothing);
      expectAllButtonsOff(tester, 2);
      await tester.tap(find.text('도크 인식해서 저장'), warnIfMissed: false);
      await tester.tap(find.text('지도에서 지정'), warnIfMissed: false);
      expect(pressed, isEmpty);
    });

    testWidgets('잠김 — 저장된 칸의 도킹해 보기·다시 저장·다시 지정·지우기가 전부 눌리지 않는다', (tester) async {
      for (final spot in _fiveStates().skip(1)) {
        final pressed = await pumpCard(tester, spot: spot, locked: true);
        expectAllButtonsOff(tester, 4);
        expect(find.text(vicaKeepWords('도크 인식해서 다시 저장')), findsOneWidget);
        await tester.tap(find.text('도크 위치 지우기'), warnIfMissed: false);
        expect(pressed, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets('로봇을 못 움직일 때의 사유도 띄어쓰기에서만 접힌다', (tester) async {
      const reason = '비상정지 상태에서는 로봇을 움직일 수 없습니다.';
      await pumpCard(tester, spot: _spot(), blockedReason: reason);
      expect(find.text(vicaKeepWords(reason)), findsOneWidget);
      expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, '도킹해 보기'))
              .onPressed,
          isNull);
      // 저장·지우기는 로봇을 움직이지 않아 막지 않는다
      expect(
          tester
              .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '도크 위치 지우기'))
              .onPressed,
          isNotNull);
    });

    testWidgets('84 미지정 — 두 가지 방법이 묶음으로 나온다', (tester) async {
      final pressed = await pumpCard(tester);
      expect(find.text(vicaKeepWords('충전하러 들어가는 자리 · 지도당 1개')), findsOneWidget);
      expect(find.text(vicaKeepWords('미지정 · 도킹 시작 버튼이 나오지 않습니다.')), findsOneWidget);
      expect(find.text(vicaKeepWords('도크 직접 인식')), findsOneWidget);
      expect(
          find.text(vicaKeepWords('정확히 세울 필요 없습니다. 도크를 보고만 있으면 라이다로 찾아 자동으로 맞춥니다.')),
          findsOneWidget);
      expect(find.text(vicaKeepWords('지도에서 도크 지정')), findsOneWidget);
      expect(
          find.text(vicaKeepWords('지도에서 도크와 도크 앞쪽을 차례로 누르면 도크 앞 1 m 지점을 자동으로 잡습니다.')),
          findsOneWidget);
      // 옛 문구는 없다
      expect(find.textContaining(vicaKeepWords('도크 정면 1 m쯤에 세운 뒤')), findsNothing);
      expect(find.text('도크 위치로 저장'), findsNothing);
      expect(find.textContaining(RegExp('V.?자')), findsNothing);

      final detect = find.widgetWithText(FilledButton, '도크 인식해서 저장');
      final map = find.widgetWithText(OutlinedButton, '지도에서 지정');
      expect(detect, findsOneWidget);
      expect(map, findsOneWidget);
      // 인식 묶음이 위, 지도 묶음이 아래
      expect(tester.getTopLeft(detect).dy, lessThan(tester.getTopLeft(map).dy));
      await tester.tap(detect);
      await tester.tap(map);
      expect(pressed, ['save', 'map']);
    });

    testWidgets('84 찾는 중 — 버튼 글자가 바뀌고 둘 다 잠긴다', (tester) async {
      await pumpCard(tester, busy: true);
      final detect =
          tester.widget<FilledButton>(find.widgetWithText(FilledButton, '도크 찾는 중…'));
      expect(detect.onPressed, isNull);
      expect(find.text('도크 인식해서 저장'), findsNothing);
      expect(
          tester
              .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '지도에서 지정'))
              .onPressed,
          isNull);
    });

    testWidgets('85 도크 인식으로 저장 · 아직 확인 안 됨', (tester) async {
      final pressed = await pumpCard(tester,
          spot: const DockSpot(
            mapId: _map,
            dockedX: -6.75,
            dockedY: 2.4,
            dockedYaw: 3.1067,
            stagingX: -5.88,
            stagingY: 2.4,
            stagingYaw: 3.1067,
            savedAt: '2026-11-19T11:40:12',
            visitedOk: false,
          ));
      // 저장된 뒤에는 설명 줄이 없다
      expect(find.text(vicaKeepWords('충전하러 들어가는 자리 · 지도당 1개')), findsNothing);
      // 음수는 긴 빼기표
      expect(find.text(vicaKeepWords('도크 앞 1 m  x −5.88   y 2.40   방향 178°')), findsOneWidget);
      expect(find.text(vicaKeepWords('11-19 11:40 · 아직 확인 안 됨')), findsOneWidget);
      expect(find.text(vicaKeepWords('아직 도킹해 보지 않음 · 아래 도킹해 보기')), findsOneWidget);
      expect(find.textContaining(vicaKeepWords('처음 도킹 시')), findsNothing);

      final tryDock = find.widgetWithText(FilledButton, '도킹해 보기');
      final again = find.widgetWithText(OutlinedButton, vicaKeepWords('도크 인식해서 다시 저장'));
      final map = find.widgetWithText(OutlinedButton, vicaKeepWords('지도에서 다시 지정'));
      final delete = find.widgetWithText(OutlinedButton, '도크 위치 지우기');
      expect(tryDock, findsOneWidget);
      expect(delete, findsOneWidget);
      // 한 줄에 반씩, 같은 폭·같은 높이
      expect(tester.getTopLeft(again).dy, tester.getTopLeft(map).dy);
      expect(tester.getTopLeft(again).dx, lessThan(tester.getTopLeft(map).dx));
      expect(tester.getSize(again), tester.getSize(map));
      // 도킹해 보기 → 반씩 두 개 → 지우기 순서
      expect(tester.getTopLeft(tryDock).dy, lessThan(tester.getTopLeft(again).dy));
      expect(tester.getTopLeft(again).dy, lessThan(tester.getTopLeft(delete).dy));
      // 옛 버튼은 없다
      expect(find.text('지금 자리에서 다시 저장'), findsNothing);

      await tester.tap(tryDock);
      await tester.tap(again);
      await tester.tap(map);
      await tester.tap(delete);
      expect(pressed, ['try', 'save', 'map', 'delete']);
    });

    testWidgets('91 지도에서 지정 · 아직 확인 안 됨 — 처음 도킹이 어떻게 되는지 알린다', (tester) async {
      await pumpCard(tester,
          spot: const DockSpot(
            mapId: _map,
            dockedX: -6.75,
            dockedY: 2.45,
            dockedYaw: 3.14159,
            stagingX: -5.9,
            stagingY: 2.45,
            stagingYaw: 3.14159,
            savedAt: '2026-11-19T11:52:00',
            visitedOk: false,
            source: kDockSourceMapPick,
          ));
      expect(find.text(vicaKeepWords('도크 앞 1 m  x −5.90   y 2.45   방향 180°')), findsOneWidget);
      expect(find.text(vicaKeepWords('11-19 11:52 · 지도에서 지정한 자리 · 아직 확인 안 됨')),
          findsOneWidget);
      expect(
          find.text(vicaKeepWords('처음 도킹 시 로봇이 도크 앞 1 m로 가서 라이다로 도크를 찾아 들어갑니다. '
              '성공하면 라이다로 잰 값으로 도크 위치를 고쳐 저장합니다.')),
          findsOneWidget);
      expect(find.text(vicaKeepWords('아직 도킹해 보지 않음 · 아래 도킹해 보기')), findsNothing);
      expect(find.widgetWithText(FilledButton, '도킹해 보기'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, vicaKeepWords('도크 인식해서 다시 저장')),
          findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, vicaKeepWords('지도에서 다시 지정')), findsOneWidget);
    });

    testWidgets('가 본 자리 — 라이다로 맞춘 자리, 경고 칸 없음, 도킹해 보기(다시 확인)', (tester) async {
      await pumpCard(tester, spot: _spot(visited: true));
      expect(find.text(vicaKeepWords('11-18 21:00 · 라이다로 맞춘 자리 · 가 본 자리')), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '도킹해 보기(다시 확인)'), findsOneWidget);
      expect(find.text(vicaKeepWords('아직 도킹해 보지 않음 · 아래 도킹해 보기')), findsNothing);
      expect(find.textContaining(vicaKeepWords('처음 도킹 시')), findsNothing);
      expect(find.textContaining(vicaKeepWords('도킹했습니다.')), findsNothing);
    });

    testWidgets('91 가 본 자리 + 고쳐 저장함 — 얼마나 고쳤는지 회색 칸', (tester) async {
      await pumpCard(tester,
          spot: _spot(
            visited: true,
            source: kDockSourceMapPick,
            refined: true,
            refinedFrom: kDockSourceMapPick,
          ));
      expect(find.text(vicaKeepWords('11-18 21:00 · 라이다로 맞춘 자리 · 가 본 자리')), findsOneWidget);
      expect(
          find.text(vicaKeepWords(
              '도킹했습니다. 라이다로 잰 값으로 도크 위치를 고쳐 저장했습니다(지정한 자리에서 18 cm · 9°).')),
          findsOneWidget);
      expect(find.widgetWithText(FilledButton, '도킹해 보기(다시 확인)'), findsOneWidget);
    });

    testWidgets('도크 인식으로 저장한 자리를 고쳤으면 "저장한 자리에서"', (tester) async {
      await pumpCard(tester,
          spot: _spot(visited: true, refined: true, refinedFrom: kDockSourceVDetect));
      expect(
          find.text(vicaKeepWords(
              '도킹했습니다. 라이다로 잰 값으로 도크 위치를 고쳐 저장했습니다(저장한 자리에서 18 cm · 9°).')),
          findsOneWidget);
    });

    testWidgets('좁은 폰(320)에서는 반씩 놓은 두 버튼이 띄어쓰기에서 접히고 높이가 같다', (tester) async {
      await pumpCard(tester, spot: _spot(), width: 320);
      final again = find.widgetWithText(OutlinedButton, vicaKeepWords('도크 인식해서 다시 저장'));
      final map = find.widgetWithText(OutlinedButton, vicaKeepWords('지도에서 다시 지정'));
      expect(tester.getTopLeft(again).dy, tester.getTopLeft(map).dy);
      expect(tester.getSize(again).height, tester.getSize(map).height);
      expect(tester.takeException(), isNull);
    });
  });

  group('지도에서 지정 세 단계의 안내(목업 89·90·90′)', () {
    Future<List<String>> pumpStage(WidgetTester tester, DockPickStage stage,
        {DockSpot? spot}) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 1600);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });
      final pressed = <String>[];
      final s = _Supervisor()..prepare();
      await tester.pumpWidget(_app(_card(spot: spot, stage: stage, pressed: pressed), s));
      await tester.pump();
      return pressed;
    }

    testWidgets('1 / 2 — 도크 구조물, 취소만', (tester) async {
      final pressed = await pumpStage(tester, DockPickStage.dock, spot: _spot());
      expect(find.text(vicaKeepWords('도크 위치 — 지도에서 지정')), findsOneWidget);
      expect(find.text('1 / 2'), findsOneWidget);
      expect(find.text(vicaKeepWords('지도에서 도크 구조물을 눌러 주세요.')), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '취소'), findsOneWidget);
      expect(find.text(vicaKeepWords('다시 지정')), findsNothing);
      expect(find.text(vicaKeepWords('이 자리로 저장')), findsNothing);
      // 지정하는 동안에는 저장된 자리의 요약·버튼을 보이지 않는다
      expect(find.textContaining(vicaKeepWords('도크 앞 1 m  x')), findsNothing);
      expect(find.text('도크 위치 지우기'), findsNothing);
      await tester.tap(find.text('취소'));
      expect(pressed, ['cancel']);
    });

    testWidgets('2 / 2 — 도크 앞쪽, 다시 지정·취소', (tester) async {
      final pressed = await pumpStage(tester, DockPickStage.front);
      expect(find.text('2 / 2'), findsOneWidget);
      expect(find.text(vicaKeepWords('도크 앞쪽을 눌러 주세요.')), findsOneWidget);
      final again = find.widgetWithText(OutlinedButton, vicaKeepWords('다시 지정'));
      final cancel = find.widgetWithText(OutlinedButton, '취소');
      expect(tester.getTopLeft(again).dy, tester.getTopLeft(cancel).dy);
      expect(tester.getTopLeft(again).dx, lessThan(tester.getTopLeft(cancel).dx));
      expect(find.text(vicaKeepWords('이 자리로 저장')), findsNothing);
      await tester.tap(again);
      await tester.tap(cancel);
      expect(pressed, ['again', 'cancel']);
    });

    testWidgets('미리보기 — 자동으로 잡았다는 띠와 방향 안내, 다시 지정·이 자리로 저장', (tester) async {
      final pressed = await pumpStage(tester, DockPickStage.preview);
      expect(find.text(vicaKeepWords('도크 앞 1 m 지점을 자동으로 잡았습니다.')), findsOneWidget);
      expect(find.text('1 / 2'), findsNothing);
      expect(find.text('2 / 2'), findsNothing);
      expect(
          find.text(vicaKeepWords('방향은 두 번째로 누른 쪽입니다. 처음 도킹 시 라이다로 다시 정확히 맞춥니다.')),
          findsOneWidget);
      final again = find.widgetWithText(OutlinedButton, vicaKeepWords('다시 지정'));
      final save = find.widgetWithText(FilledButton, vicaKeepWords('이 자리로 저장'));
      expect(tester.getTopLeft(again).dy, tester.getTopLeft(save).dy);
      expect(tester.getTopLeft(again).dx, lessThan(tester.getTopLeft(save).dx));
      expect(find.text('취소'), findsNothing);
      await tester.tap(again);
      await tester.tap(save);
      expect(pressed, ['again', 'pickSave']);
    });
  });

  group('도크 인식 저장 실패 팝업(목업 86·87·88)', () {
    Future<List<Object?>> openDialog(
        WidgetTester tester, Future<Object?> Function(BuildContext context) open) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });
      final results = <Object?>[];
      final s = _Supervisor()..prepare();
      await tester.pumpWidget(_app(_DialogHost(open: open, onResult: results.add), s));
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      return results;
    }

    testWidgets('86 도크를 찾지 못했습니다 — 그림 둘·세 줄·버튼 셋', (tester) async {
      final results = await openDialog(tester, (context) => showDockNotFoundDialog(context));
      expect(find.text(vicaKeepWords('도크를 찾지 못했습니다')), findsOneWidget);
      expect(find.text(vicaKeepWords('로봇 앞머리가 도크를 향하게 세운 뒤 다시 눌러 주세요.')), findsOneWidget);
      // 되는 자세·안 되는 자세 그림과 그 아래 말
      final good = find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is DockPosturePainter &&
              (w.painter! as DockPosturePainter).good);
      final bad = find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is DockPosturePainter &&
              !(w.painter! as DockPosturePainter).good);
      expect(good, findsOneWidget);
      expect(bad, findsOneWidget);
      expect(tester.getCenter(good).dx, lessThan(tester.getCenter(bad).dx));
      expect(tester.getSize(good), tester.getSize(bad));
      expect(find.text(vicaKeepWords('이렇게')), findsOneWidget);
      expect(find.text(vicaKeepWords('등지면 못 찾습니다')), findsOneWidget);
      expect(find.text(vicaKeepWords('· 도크 앞 1 m쯤 (멀어도 2 m 안)')), findsOneWidget);
      expect(find.text(vicaKeepWords('· 앞머리가 도크 쪽 (정면이 아니어도 됩니다)')), findsOneWidget);
      expect(find.text(vicaKeepWords('· 로봇과 도크 사이에 물건이 없게')), findsOneWidget);
      // 저장된 도크가 없으면 방향 칸이 없다
      expect(find.textContaining(vicaKeepWords('저장된 도크는')), findsNothing);
      // 옛 팝업 문구는 없다
      expect(find.textContaining(RegExp('V.?자')), findsNothing);

      final close = find.widgetWithText(OutlinedButton, vicaKeepWords('닫기'));
      final retry = find.widgetWithText(FilledButton, vicaKeepWords('다시 찾기'));
      final map = find.widgetWithText(TextButton, '지도에서 지정');
      expect(tester.getTopLeft(close).dy, tester.getTopLeft(retry).dy);
      expect(tester.getTopLeft(close).dx, lessThan(tester.getTopLeft(retry).dx));
      expect(tester.getTopLeft(retry).dy, lessThan(tester.getTopLeft(map).dy));
      // 밑줄 글자 버튼
      final label = tester.widget<RichText>(
          find.descendant(of: map, matching: find.byType(RichText)));
      expect(label.text.style?.decoration, TextDecoration.underline);

      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(results, [DockSaveFailChoice.retry]);
      expect(find.byType(VicaDialog), findsNothing);
    });

    testWidgets('86 저장된 도크가 있으면 어느 쪽 몇 m 인지 회색 칸, 지도에서 지정·닫기·바깥 누름', (tester) async {
      const hint = '저장된 도크는 로봇의 왼쪽 뒤 약 2.3 m에 있습니다.';
      final results = await openDialog(
          tester, (context) => showDockNotFoundDialog(context, savedDockHint: hint));
      expect(find.text(vicaKeepWords(hint)), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, '지도에서 지정'));
      await tester.pumpAndSettle();
      expect(results, [DockSaveFailChoice.mapPick]);

      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, vicaKeepWords('닫기')));
      await tester.pumpAndSettle();
      expect(results.last, DockSaveFailChoice.close);

      // 바깥을 눌러 닫아도 닫기와 같다
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byType(VicaDialog), findsNothing);
      expect(results.last, DockSaveFailChoice.close);
      expect(results.length, 3);
    });

    testWidgets('87 도크 인식이 불안정합니다 — 멀 때: 본 거리·방향과 가까이 옮기라는 두 줄', (tester) async {
      final results = await openDialog(
          tester, (context) => showDockUnstableDialog(context, result: _unstableFar));
      expect(find.text(vicaKeepWords('도크 인식이 불안정합니다')), findsOneWidget);
      expect(find.text(vicaKeepWords('지금 로봇에서 본 도크')), findsOneWidget);
      expect(find.text(vicaKeepWords('약 2.6 m 앞 · 왼쪽으로 20°')), findsOneWidget);
      // 사용자가 넣은 줄 나눔을 지킨다
      expect(find.text(vicaKeepWords('도크 쪽으로 1 m쯤까지 가까이 옮긴 뒤\n다시 눌러 주세요.')),
          findsOneWidget);
      // 다른 경우의 안내는 함께 나오지 않는다
      expect(find.textContaining(vicaKeepWords('옆에서 보고 있습니다')), findsNothing);
      expect(find.textContaining(vicaKeepWords('물건이 있는지')), findsNothing);
      // 지도에서 지정은 이 팝업에 없다
      expect(find.text('지도에서 지정'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, vicaKeepWords('닫기')), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, vicaKeepWords('다시 찾기')));
      await tester.pumpAndSettle();
      expect(results, [DockSaveFailChoice.retry]);
    });

    testWidgets('87 옆에서 볼 때·가깝고 정면인데도 — 굵은 줄만 바뀐다', (tester) async {
      await openDialog(
          tester,
          (context) => showDockUnstableDialog(context,
              result: const DockRegisterResult(
                  ok: false, reason: 'unstable', distM: 1.4, bearingDeg: -38, obliqueDeg: 60)));
      expect(find.text(vicaKeepWords('약 1.4 m 앞 · 오른쪽으로 38°')), findsOneWidget);
      expect(
          find.text(vicaKeepWords('도크를 옆에서 보고 있습니다. 도크 정면 쪽으로 옮긴 뒤 다시 눌러 주세요.')),
          findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, vicaKeepWords('닫기')));
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox.shrink());
      await openDialog(
          tester,
          (context) => showDockUnstableDialog(context,
              result: const DockRegisterResult(
                  ok: false, reason: 'unstable', distM: 1.2, bearingDeg: 2, obliqueDeg: 10)));
      expect(find.text(vicaKeepWords('약 1.2 m 앞 · 정면')), findsOneWidget);
      expect(find.text(vicaKeepWords('로봇과 도크 사이에 물건이 있는지 확인한 뒤 다시 눌러 주세요.')),
          findsOneWidget);
    });

    testWidgets('88 초기 위치를 잡아 주세요 — 닫기·초기 위치 / 잡으러 가기(두 줄)', (tester) async {
      final results = await openDialog(tester, showDockNoPoseDialog);
      expect(find.text(vicaKeepWords('초기 위치를 잡아 주세요')), findsOneWidget);
      expect(find.text(vicaKeepWords('초기 위치가 잡혀 있지 않아 도크 위치를 정할 수 없습니다.')),
          findsOneWidget);
      final close = find.widgetWithText(OutlinedButton, vicaKeepWords('닫기'));
      final go = find.widgetWithText(FilledButton, vicaKeepWords('초기 위치\n잡으러 가기'));
      expect(go, findsOneWidget);
      // 두 줄 버튼과 닫기의 높이가 같다
      expect(tester.getTopLeft(close).dy, tester.getTopLeft(go).dy);
      expect(tester.getSize(close).height, tester.getSize(go).height);
      await tester.tap(go);
      await tester.pumpAndSettle();
      expect(results, [DockSaveFailChoice.initialPose]);
    });

    testWidgets('88 주행이 꺼져 있습니다 — 두 줄 안내와 확인 하나', (tester) async {
      final results = await openDialog(tester, showDockDriveOffDialog);
      expect(find.text(vicaKeepWords('주행이 꺼져 있습니다')), findsOneWidget);
      expect(
          find.text(vicaKeepWords('도크를 찾으려면 주행이 켜져 있어야 합니다.\n주행을 켠 뒤 다시 눌러 주세요.')),
          findsOneWidget);
      expect(find.byType(OutlinedButton), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, '확인'));
      await tester.pumpAndSettle();
      expect(results.length, 1);
      expect(find.byType(VicaDialog), findsNothing);
    });
  });

  testWidgets('주행이 꺼져 있습니다 — 지도에서 지정 저장 때는 첫 줄만 다르다', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final s = _Supervisor()..prepare();
    await tester.pumpWidget(_app(
        _DialogHost(open: (context) => showDockDriveOffDialog(context, saving: true)), s));
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    expect(find.text(vicaKeepWords('주행이 꺼져 있습니다')), findsOneWidget);
    expect(
        find.text(vicaKeepWords('도크 위치를 저장하려면 주행이 켜져 있어야 합니다.\n주행을 켠 뒤 다시 눌러 주세요.')),
        findsOneWidget);
    expect(find.textContaining(vicaKeepWords('도크를 찾으려면')), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, '확인'));
    await tester.pumpAndSettle();
    expect(find.byType(VicaDialog), findsNothing);
  });

  group('도킹 실패 팝업 변형(목업 92)', () {
    Future<List<String>> openAlert(WidgetTester tester, GoalEvent event) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });
      final pressed = <String>[];
      final s = _Supervisor()..prepare();
      await tester.pumpWidget(_app(
          _DialogHost(
            open: (context) => showDialog<void>(
              context: context,
              builder: (_) =>
                  GoalAlertDialog(event: event, onRedoDock: () => pressed.add('redo')),
            ),
          ),
          s));
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      return pressed;
    }

    testWidgets('지도에서 지정만 한 자리에서 도크를 못 찾음 — 안내 칸과 도크 위치 다시 잡기', (tester) async {
      final pressed = await openAlert(tester, _dockFail('not_found', firstTry: true));
      expect(find.text('도킹하지 못했습니다'), findsOneWidget);
      expect(find.text(vicaKeepWords('도크를 찾지 못했습니다.\n로봇은 도크 앞에서 기다리고 있습니다.')),
          findsOneWidget);
      expect(find.text(vicaKeepWords('지정한 자리나 방향이 도크와 다를 수 있습니다.')), findsOneWidget);
      expect(find.text(vicaKeepWords('· 지도에서 도크를 다시 지정하거나')), findsOneWidget);
      expect(find.text(vicaKeepWords("· 로봇을 도크 앞에 세우고 '도크 인식해서 저장'을 눌러 주세요.")),
          findsOneWidget);
      // 기존 문구·사유 칸은 없다
      expect(find.textContaining(vicaKeepWords('구조물을 옮겼는지')), findsNothing);
      expect(find.byType(VicaDialogRow), findsNothing);

      final ok = find.widgetWithText(OutlinedButton, '확인');
      final redo = find.widgetWithText(FilledButton, vicaKeepWords('도크 위치 다시 잡기'));
      expect(tester.getTopLeft(ok).dy, tester.getTopLeft(redo).dy);
      expect(tester.getTopLeft(ok).dx, lessThan(tester.getTopLeft(redo).dx));
      await tester.tap(redo);
      await tester.pumpAndSettle();
      expect(pressed, ['redo']);
      expect(find.byType(VicaDialog), findsNothing);
    });

    testWidgets('도크 앞까지 못 감(nav_failed) — 기존 문구에 안내 칸과 도크 위치 다시 잡기가 붙는다', (tester) async {
      final pressed = await openAlert(tester, _dockFail('nav_failed', firstTry: true));
      expect(find.text('도킹하지 못했습니다'), findsOneWidget);
      expect(find.text(vicaKeepWords('도크 앞까지 가지 못했습니다.\n로봇은 그 자리에 멈춰 있습니다.')),
          findsOneWidget);
      expect(find.textContaining(vicaKeepWords('도크를 찾지 못했습니다.')), findsNothing);
      expect(find.text(vicaKeepWords('지정한 자리나 방향이 도크와 다를 수 있습니다.')), findsOneWidget);
      expect(find.text(vicaKeepWords('· 지도에서 도크를 다시 지정하거나')), findsOneWidget);
      expect(find.byType(VicaDialogRow), findsNothing);
      expect(find.widgetWithText(OutlinedButton, '확인'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, vicaKeepWords('도크 위치 다시 잡기')));
      await tester.pumpAndSettle();
      expect(pressed, ['redo']);
    });

    testWidgets('도크 인식으로 저장한 자리의 nav_failed 는 기존 팝업 그대로', (tester) async {
      await openAlert(tester, _dockFail('nav_failed'));
      expect(find.textContaining(vicaKeepWords('도크 앞까지 가지 못했습니다.')), findsOneWidget);
      expect(find.text(vicaKeepWords('도크 위치 다시 잡기')), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.widgetWithText(FilledButton, '확인'), findsOneWidget);
    });

    testWidgets('확인은 닫기만 한다', (tester) async {
      final pressed = await openAlert(tester, _dockFail('out_of_range', firstTry: true));
      await tester.tap(find.widgetWithText(OutlinedButton, '확인'));
      await tester.pumpAndSettle();
      expect(pressed, isEmpty);
      expect(find.byType(VicaDialog), findsNothing);
    });

    testWidgets('그 밖의 도킹 실패 팝업은 그대로 — 확인 하나, 기존 문구', (tester) async {
      await openAlert(tester, _dockFail('not_found'));
      expect(find.textContaining(vicaKeepWords('구조물을 옮겼는지 확인해주세요.')), findsOneWidget);
      expect(find.text(vicaKeepWords('도크 위치 다시 잡기')), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.widgetWithText(FilledButton, '확인'), findsOneWidget);
      expect(find.byType(VicaDialogRow), findsOneWidget); // 사유 칸
      await tester.tap(find.widgetWithText(FilledButton, '확인'));
      await tester.pumpAndSettle();

      // 지도에서 지정한 자리라도 사유가 다르면 그대로
      await tester.pumpWidget(const SizedBox.shrink());
      await openAlert(tester, _dockFail('lost', firstTry: true));
      expect(find.textContaining(vicaKeepWords('들어가는 중에 V자를 놓쳤습니다.')), findsOneWidget);
      expect(find.text(vicaKeepWords('도크 위치 다시 잡기')), findsNothing);
    });
  });
}
