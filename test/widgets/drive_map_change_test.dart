// 앱에서 주행 지도 바꾸기(2026-11-17 목업 ①~⑦). 젯슨은 모드 노드가 맡고, 앱은 고른 지도를 보내고
// 모드 상태(map_change_block·map_mismatch·dialog_state)대로 그립니다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vica_supervisor/models/mode_status.dart';
import 'package:vica_supervisor/providers/app_mode_provider.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';
import 'package:vica_supervisor/widgets/drive_map_change.dart';
import 'package:vica_supervisor/widgets/vica_ui.dart';

class _FakeSupervisor extends SupervisorProvider {
  final requested = <String>[];
  List<String> restart = const ['nav2', 'mission', 'llm', 'posecheck'];

  @override
  Future<(bool, String)> requestMapChange(String mapId) async {
    requested.add(mapId);
    final now = modeStatus!;
    setModeStatusForTest(ModeStatus(
      mode: now.mode,
      state: now.state,
      nav2: now.nav2,
      voice: now.voice,
      currentMapId: mapId,
      runningMaps: now.runningMaps,
      dialogState: now.dialogState,
      mapChange: MapChangeResult(
        requestId: 'r',
        mapId: mapId,
        from: now.currentMapId,
        state: 'applied',
        message: now.driveOn ? 'Nav2·미션·음성 재시작 · 약 1분' : '다음 주행부터 적용',
        restarted: now.driveOn ? restart : const [],
      ),
    ));
    return (true, now.driveOn ? 'Nav2·미션·음성 재시작 · 약 1분' : '다음 주행부터 적용');
  }
}

const _maps = {
  'maps': [
    {'map_id': 'map_a', 'map_name': '4층 복도', 'has_route': true, 'has_keepout': true,
     'destination_count': 4, 'saved_at': '2026-11-16T20:30:26', 'is_current': true},
    {'map_id': 'map_b', 'map_name': '킨텍스', 'has_route': true, 'has_keepout': true,
     'destination_count': 3, 'saved_at': '2026-11-03T14:28:58'},
    {'map_id': 'map_c', 'map_name': '빈 지도', 'destination_count': 0},
  ],
  'current_map_id': 'map_a',
};

ModeStatus drive({
  String dialog = 'idle',
  String block = '',
  String current = 'map_a',
  String running = 'map_a',
  bool mismatch = false,
}) =>
    ModeStatus(
      mode: 'drive',
      state: ModeState.running,
      nav2: 'active',
      voice: 'active',
      currentMapId: current,
      runningMaps: {'nav2': running, 'mission': running, 'llm': running},
      mapMismatch: mismatch,
      mapChangeBlock: block,
      dialogState: dialog,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<_FakeSupervisor> pump(WidgetTester tester, ModeStatus? status, Widget child) async {
    final supervisor = _FakeSupervisor()
      ..handleMapListForTest(Map<String, Object?>.from(_maps))
      ..setModeStatusForTest(status);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 900);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SupervisorProvider>.value(value: supervisor),
          ChangeNotifierProvider(create: (_) => AppModeProvider()),
        ],
        child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))),
      ),
    );
    await tester.pump();
    return supervisor;
  }

  testWidgets('③ 보는 지도가 주행 지도와 같거나 주행이 꺼져 있으면 띠가 없다', (tester) async {
    await pump(tester, drive(), const DriveMapBanner(viewedMapId: 'map_a'));
    expect(find.text('이 지도로 주행'), findsNothing);
    await pump(tester, const ModeStatus(mode: 'idle', state: ModeState.idle),
        const DriveMapBanner(viewedMapId: 'map_b'));
    expect(find.text('이 지도로 주행'), findsNothing);
  });

  testWidgets('③→④→⑤ 다른 지도를 보면 띠, 확인 뒤 보내고 진행 화면으로 간다', (tester) async {
    final supervisor = await pump(tester, drive(), const DriveMapBanner(viewedMapId: 'map_b'));
    expect(find.textContaining('로봇 위치 표시 안 함'), findsOneWidget);
    await tester.tap(find.text('이 지도로 주행'));
    await tester.pumpAndSettle();
    expect(find.text('주행 지도 바꾸기'), findsOneWidget);
    expect(find.text('Nav2·미션·음성 재시작 · 약 1분'), findsOneWidget);
    expect(find.text(vicaKeepWords('일시정지한 안내·순찰 취소')), findsNothing);
    await tester.tap(find.text('바꾸기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(supervisor.requested, ['map_b']);
    expect(find.text('지도 바꾸는 중'), findsWidgets);
    expect(find.text('지도 기록'), findsOneWidget);
    expect(find.text('음성 켜기'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('④-2 일시정지 중이면 남은 안내·순찰 취소를 알린다', (tester) async {
    await pump(tester, drive(dialog: 'paused'), const DriveMapBanner(viewedMapId: 'map_b'));
    await tester.tap(find.text('이 지도로 주행'));
    await tester.pumpAndSettle();
    expect(find.text(vicaKeepWords('일시정지한 안내·순찰 취소')), findsOneWidget);
    expect(find.text('취소하고 바꾸기'), findsOneWidget);
  });

  testWidgets('⑥ 막혀 있으면 버튼이 꺼지고 이유를 보인다', (tester) async {
    final supervisor = await pump(tester, drive(dialog: 'navigating', block: '안내 중엔 불가 · 끝나거나 일시정지하면 가능'),
        const DriveMapBanner(viewedMapId: 'map_b'));
    expect(find.textContaining(vicaKeepWords('안내 중엔 불가')), findsOneWidget);
    final button = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '이 지도로 주행'));
    expect(button.onPressed, isNull);
    expect(supervisor.requested, isEmpty);
  });

  testWidgets('⑦ 파일만 바뀌었으면 불일치 카드 — 되돌리기는 확인 없이 보낸다', (tester) async {
    final supervisor = await pump(tester, drive(current: 'map_b', running: 'map_a', mismatch: true),
        const DriveMapMismatchCard());
    expect(find.text('지도 불일치'), findsOneWidget);
    expect(find.textContaining('설정 킨텍스'), findsOneWidget);
    expect(find.textContaining('실행 중 4층 복도'), findsOneWidget);
    expect(find.text('킨텍스 적용'), findsOneWidget);
    await tester.tap(find.text('되돌리기'));
    await tester.pumpAndSettle();
    expect(supervisor.requested, ['map_a']);
    expect(find.text('주행 지도 바꾸기'), findsNothing);
  });

  testWidgets('⑦ 어긋나지 않았으면 카드가 없다', (tester) async {
    await pump(tester, drive(), const DriveMapMismatchCard());
    expect(find.text('지도 불일치'), findsNothing);
  });

  testWidgets('①② 주행이 꺼져 있으면 고른 지도를 확인 없이 보낸다', (tester) async {
    final supervisor = await pump(tester, const ModeStatus(mode: 'idle', state: ModeState.idle, currentMapId: 'map_a'),
        const DriveMapRow());
    expect(find.text('4층 복도'), findsOneWidget);
    expect(find.text('11-16 20:30 · 레일 · 금지구역 · 목적지 4'), findsOneWidget);
    await tester.tap(find.text('바꾸기'));
    await tester.pumpAndSettle();
    expect(find.text('주행 지도 고르기'), findsOneWidget);
    expect(find.text('사용 중'), findsOneWidget);
    expect(find.text('목적지 0 · 안내 불가'), findsOneWidget);
    await tester.tap(find.text('킨텍스'));
    await tester.pump();
    await tester.tap(find.text('킨텍스로 정하기'));
    await tester.pumpAndSettle();
    expect(supervisor.requested, ['map_b']);
    expect(find.text('주행 지도 바꾸기'), findsNothing);
  });
}
