import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vica_supervisor/app.dart';
import 'package:vica_supervisor/core/app_settings.dart';
import 'package:vica_supervisor/models/dock_state.dart';
import 'package:vica_supervisor/models/mode_status.dart';
import 'package:vica_supervisor/providers/app_mode_provider.dart';
import 'package:vica_supervisor/providers/auth_provider.dart';
import 'package:vica_supervisor/providers/settings_provider.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';
import 'package:vica_supervisor/providers/ui_preferences_provider.dart';
import 'package:vica_supervisor/screens/save_location_screen.dart';
import 'package:vica_supervisor/widgets/dock_position_card.dart';
import 'package:vica_supervisor/widgets/drive_map_change.dart';
import 'package:vica_supervisor/widgets/map_canvas.dart';
import 'package:vica_supervisor/widgets/vica_ui.dart';

const _map = 'vica_map_test';

DockSpot _spot({String source = kDockSourceVDetect, bool visited = false}) =>
    DockSpot(
      mapId: _map,
      dockedX: -0.6,
      dockedY: 3.65,
      dockedYaw: math.pi,
      stagingX: 0.55,
      stagingY: 3.65,
      stagingYaw: math.pi,
      savedAt: '2026-11-19T11:52:00',
      visitedOk: visited,
      source: source,
    );

class _Flow extends SupervisorProvider {
  /// registerDock 이 차례로 돌려줄 결과.
  final registerResults = <DockRegisterResult>[];
  int registers = 0;

  /// 있으면 registerDock 이 이것이 끝날 때까지 답하지 않습니다(로봇의 답을 기다리는 사이를 흉내).
  Completer<void>? registerGate;

  /// setDockFromMap 이 받은 인자와 돌려줄 결과.
  final sets = <({String mapId, double x, double y, double yawDeg})>[];
  ({bool ok, String reason}) setResult = (ok: true, reason: '');

  @override
  Future<DockRegisterResult> registerDock(
      AppSettings settings, String mapId) async {
    registers += 1;
    await registerGate?.future;
    final result = registerResults.removeAt(0);
    if (result.ok) {
      setDockSpotForTest(mapId, _spot());
    }
    return result;
  }

  @override
  Future<({bool ok, String reason})> setDockFromMap(
    AppSettings settings, {
    required String mapId,
    required double x,
    required double y,
    required double yawDeg,
  }) async {
    sets.add((mapId: mapId, x: x, y: y, yawDeg: yawDeg));
    if (setResult.ok) {
      setDockSpotForTest(mapId, _spot(source: kDockSourceMapPick));
    }
    return setResult;
  }

  void prepare({bool robot = true, DockSpot? spot}) {
    handleMapListForTest({
      'maps': [
        {
          'map_id': _map,
          'map_name': '시험 지도',
          'image_url': '/maps/vica_map_test.png',
          'resolution': 0.05,
          'origin_x': -10.0,
          'origin_y': -10.0,
          'width': 400,
          'height': 300,
        },
      ],
    });
    if (robot) {
      handleRobotStatusForTest({
        'robot_id': 'vica_robot_01',
        'robot_name': 'VICA 1호기',
        'status': 'idle',
        'x': 1.0,
        'y': 2.0,
        'yaw': 0.0,
        'current_goal': '',
        'map_id': _map,
      });
    }
    if (spot != null) {
      setDockSpotForTest(_map, spot);
    }
  }
}

const _ok =
    DockRegisterResult(ok: true, reason: '', movedCm: 6.0, turnedDeg: 2.1);
const _notFound = DockRegisterResult(ok: false, reason: 'not_found');
const _unstable = DockRegisterResult(
    ok: false, reason: 'unstable', distM: 2.6, bearingDeg: 20, obliqueDeg: 50);

const _savedToast = '도크를 찾아 저장했습니다. 도크 앞 1 m 지점을 준비 위치로 잡았습니다(서 있던 자리에서 6 cm).';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const k = vicaKeepWords;
  var driveOpens = 0;

  Widget screen(SupervisorProvider supervisor, {int dockPanelRequest = 0}) =>
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SupervisorProvider>.value(value: supervisor),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ],
        child: MaterialApp(
          theme: vicaTheme(),
          home: Scaffold(
            body: SaveLocationScreen(
              onOpenDrive: () => driveOpens += 1,
              dockPanelRequest: dockPanelRequest,
            ),
          ),
        ),
      );

  /// 지도 설정 화면을 띄우고 도크 위치 칸을 펼칩니다.
  Future<_Flow> pumpDockPanel(WidgetTester tester,
      {bool robot = true, DockSpot? spot}) async {
    driveOpens = 0;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 2400);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final s = _Flow()..prepare(robot: robot, spot: spot);
    await tester.pumpWidget(screen(s));
    await tester.pump();
    await tester.tap(find.text('도크 위치'));
    await tester.pump();
    return s;
  }

  MapCanvas canvas(WidgetTester tester) =>
      tester.widget<MapCanvas>(find.byType(MapCanvas));
  DockPickStage stage(WidgetTester tester) =>
      tester.widget<DockPositionCard>(find.byType(DockPositionCard)).pickStage;

  final detect = find.widgetWithText(FilledButton, '도크 인식해서 저장');
  final detectAgain = find.widgetWithText(OutlinedButton, k('도크 인식해서 다시 저장'));
  final mapPick = find.widgetWithText(OutlinedButton, '지도에서 지정');
  final mapPickAgain = find.widgetWithText(OutlinedButton, k('지도에서 다시 지정'));

  group('도크 인식해서 저장', () {
    testWidgets('성공 — 서 있던 자리에서 몇 cm 인지 알리고 저장된 칸으로 바뀐다', (tester) async {
      final s = await pumpDockPanel(tester);
      s.registerResults.add(_ok);
      await tester.tap(detect);
      await tester.pumpAndSettle();
      expect(s.registers, 1);
      expect(find.text(k(_savedToast)), findsOneWidget);
      expect(find.byType(VicaDialog), findsNothing);
      expect(find.widgetWithText(FilledButton, '도킹해 보기'), findsOneWidget);
      expect(detectAgain, findsOneWidget);
      expect(find.text('지정됨'), findsWidgets);
    });

    testWidgets('도크를 찾지 못함 → 다시 찾기 → 성공', (tester) async {
      final s = await pumpDockPanel(tester);
      s.registerResults.addAll([_notFound, _notFound, _ok]);
      await tester.tap(detect);
      await tester.pumpAndSettle();
      expect(find.text(k('도크를 찾지 못했습니다')), findsOneWidget);
      expect(find.textContaining(k('저장된 도크는')), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, k('다시 찾기')));
      await tester.pumpAndSettle();
      expect(s.registers, 2);
      expect(find.text(k('도크를 찾지 못했습니다')), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, k('다시 찾기')));
      await tester.pumpAndSettle();
      expect(s.registers, 3);
      expect(find.byType(VicaDialog), findsNothing);
      expect(find.text(k(_savedToast)), findsOneWidget);
    });

    testWidgets('도크를 찾지 못함 → 닫기는 다시 부르지 않는다', (tester) async {
      final s = await pumpDockPanel(tester);
      s.registerResults.add(_notFound);
      await tester.tap(detect);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, k('닫기')));
      await tester.pumpAndSettle();
      expect(s.registers, 1);
      expect(find.byType(VicaDialog), findsNothing);
      expect(stage(tester), DockPickStage.none);
      expect(driveOpens, 0);
    });

    testWidgets('도크 위치가 이미 있고 로봇 위치를 알면 저장된 도크가 어느 쪽인지 알린다', (tester) async {
      final s = await pumpDockPanel(tester, spot: _spot());
      s.registerResults.add(_notFound);
      await tester.tap(detectAgain);
      await tester.pumpAndSettle();
      expect(find.text(k('저장된 도크는 로봇의 왼쪽 뒤 약 2.3 m에 있습니다.')), findsOneWidget);
    });

    testWidgets('로봇 위치를 모르면 저장된 도크 방향 칸이 없다', (tester) async {
      final s = await pumpDockPanel(tester, robot: false, spot: _spot());
      s.registerResults.add(_notFound);
      await tester.tap(detectAgain);
      await tester.pumpAndSettle();
      expect(find.text(k('도크를 찾지 못했습니다')), findsOneWidget);
      expect(find.textContaining(k('저장된 도크는')), findsNothing);
    });

    testWidgets('도크를 찾지 못함 → 지도에서 지정 → 1 / 2 로 들어간다', (tester) async {
      final s = await pumpDockPanel(tester);
      s.registerResults.add(_notFound);
      await tester.tap(detect);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '지도에서 지정'));
      await tester.pumpAndSettle();
      expect(s.registers, 1);
      expect(find.byType(VicaDialog), findsNothing);
      expect(stage(tester), DockPickStage.dock);
      expect(find.text(k('지도에서 도크 구조물을 눌러 주세요.')), findsOneWidget);
    });

    testWidgets('인식이 불안정 → 본 거리·방향을 보이고, 다시 찾기로 성공', (tester) async {
      final s = await pumpDockPanel(tester);
      s.registerResults.addAll([_unstable, _ok]);
      await tester.tap(detect);
      await tester.pumpAndSettle();
      expect(find.text(k('도크 인식이 불안정합니다')), findsOneWidget);
      expect(find.text(k('약 2.6 m 앞 · 왼쪽으로 20°')), findsOneWidget);
      expect(
          find.text(k('도크 쪽으로 1 m쯤까지 가까이 옮긴 뒤\n다시 눌러 주세요.')), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, k('다시 찾기')));
      await tester.pumpAndSettle();
      expect(s.registers, 2);
      expect(find.text(k(_savedToast)), findsOneWidget);
    });

    testWidgets('초기 위치가 없음 → 초기 위치 잡으러 가기는 원격 주행 탭을 연다', (tester) async {
      final s = await pumpDockPanel(tester);
      s.registerResults
          .add(const DockRegisterResult(ok: false, reason: 'no_amcl'));
      await tester.tap(detect);
      await tester.pumpAndSettle();
      expect(find.text(k('초기 위치를 잡아 주세요')), findsOneWidget);
      expect(driveOpens, 0);
      await tester.tap(find.widgetWithText(FilledButton, k('초기 위치\n잡으러 가기')));
      await tester.pumpAndSettle();
      expect(driveOpens, 1);
      expect(s.registers, 1);
      expect(find.byType(VicaDialog), findsNothing);
    });

    testWidgets('초기 위치가 없음 → 닫기는 탭을 옮기지 않는다', (tester) async {
      final s = await pumpDockPanel(tester);
      s.registerResults
          .add(const DockRegisterResult(ok: false, reason: 'no_amcl'));
      await tester.tap(detect);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, k('닫기')));
      await tester.pumpAndSettle();
      expect(driveOpens, 0);
      expect(find.byType(VicaDialog), findsNothing);
    });

    testWidgets('도크 서비스가 없음(주행 꺼짐) → 주행이 꺼져 있습니다', (tester) async {
      final s = await pumpDockPanel(tester);
      s.registerResults
          .add(const DockRegisterResult(ok: false, reason: 'call_failed'));
      await tester.tap(detect);
      await tester.pumpAndSettle();
      expect(find.text(k('주행이 꺼져 있습니다')), findsOneWidget);
      expect(find.text(k('도크를 찾으려면 주행이 켜져 있어야 합니다.\n주행을 켠 뒤 다시 눌러 주세요.')),
          findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '확인'));
      await tester.pumpAndSettle();
      expect(s.registers, 1);
      expect(find.byType(VicaDialog), findsNothing);
    });

    testWidgets('rosbridge 연결이 없음 → 주행 꺼짐 팝업이 아니라 짧은 알림', (tester) async {
      final s = await pumpDockPanel(tester);
      s.registerResults
          .add(const DockRegisterResult(ok: false, reason: 'not_connected'));
      await tester.tap(detect);
      await tester.pumpAndSettle();
      expect(find.byType(VicaDialog), findsNothing);
      expect(find.text(k('주행이 꺼져 있습니다')), findsNothing);
      expect(find.text(k('ROS Bridge에 연결되지 않았습니다.')), findsOneWidget);
      expect(s.registers, 1);
    });

    testWidgets('그 밖의 사유(도킹 중·쓰기 실패·시간 초과)는 팝업 없이 짧은 알림', (tester) async {
      for (final (reason, text) in [
        ('busy', '로봇이 도킹 일을 하는 중입니다. 끝난 뒤 다시 저장하세요.'),
        ('write_failed', '도크 위치를 저장하지 못했습니다(write_failed).'),
        ('timeout', '도크 위치를 저장하지 못했습니다(timeout).'),
      ]) {
        final s = await pumpDockPanel(tester);
        s.registerResults.add(DockRegisterResult(ok: false, reason: reason));
        await tester.tap(detect);
        await tester.pumpAndSettle();
        expect(find.byType(VicaDialog), findsNothing, reason: reason);
        expect(find.text(k(text)), findsOneWidget, reason: reason);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets('답을 기다리는 사이 다른 칸으로 넘어갔어도, 지도에서 지정은 도크 위치 칸을 펼치고 시작한다',
        (tester) async {
      final s = await pumpDockPanel(tester);
      s.registerGate = Completer<void>();
      s.registerResults.add(_notFound);
      await tester.tap(detect);
      await tester.pump();
      await tester.tap(find.text('홈 위치'));
      await tester.pump();
      expect(find.byType(DockPositionCard), findsNothing);

      s.registerGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text(k('도크를 찾지 못했습니다')), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, '지도에서 지정'));
      await tester.pumpAndSettle();

      expect(find.byType(DockPositionCard), findsOneWidget);
      expect(stage(tester), DockPickStage.dock);
      expect(find.text(k('지도에서 도크 구조물을 눌러 주세요.')), findsOneWidget);
      canvas(tester).onTapMap!(const Offset(1, 1));
      await tester.pump();
      expect(stage(tester), DockPickStage.front);
      expect(canvas(tester).dockPick!.dock, const Offset(1, 1));
      expect(canvas(tester).pickedLocation, isNull);
    });
  });

  group('지도에서 지정', () {
    testWidgets('도크 구조물 → 도크 앞쪽 → 미리보기 → 이 자리로 저장', (tester) async {
      final s = await pumpDockPanel(tester);
      expect(canvas(tester).dockPick, isNull);
      await tester.tap(mapPick);
      await tester.pump();

      expect(stage(tester), DockPickStage.dock);
      expect(find.text(k('도크 위치 — 지도에서 지정')), findsOneWidget);
      expect(find.text('1 / 2'), findsOneWidget);
      expect(canvas(tester).dockPick, isNull);

      canvas(tester).onTapMap!(const Offset(-6.9, 2.45));
      await tester.pump();

      expect(stage(tester), DockPickStage.front);
      expect(find.text('2 / 2'), findsOneWidget);
      var pick = canvas(tester).dockPick!;
      expect(pick.dock, const Offset(-6.9, 2.45));
      expect(pick.staging, isNull);
      expect(pick.second, isNull);
      expect(find.text('도크'), findsOneWidget);
      expect(find.text('도크 앞 1 m'), findsNothing);

      canvas(tester).onTapMap!(const Offset(-6.8, 2.5));
      await tester.pump();
      expect(stage(tester), DockPickStage.front);
      canvas(tester).onTapMap!(const Offset(-6.65, 2.45));
      await tester.pump();
      expect(stage(tester), DockPickStage.front);
      expect(canvas(tester).dockPick!.second, isNull);

      canvas(tester).onTapMap!(const Offset(-5.0, 2.45));
      await tester.pump();

      expect(stage(tester), DockPickStage.preview);
      expect(find.text(k('도크 앞 1 m 지점을 자동으로 잡았습니다.')), findsOneWidget);
      pick = canvas(tester).dockPick!;
      expect(pick.dock, const Offset(-6.9, 2.45));
      expect(pick.second, const Offset(-5.0, 2.45));
      expect(pick.staging!.dx, closeTo(-6.9 + 1.151, 1e-9));
      expect(pick.staging!.dy, closeTo(2.45, 1e-9));
      expect(find.text('도크'), findsOneWidget);
      expect(find.text('도크 앞 1 m'), findsOneWidget);
      expect(find.text('두 번째로 누른 자리'), findsOneWidget);

      canvas(tester).onTapMap!(const Offset(0, 0));
      await tester.pump();
      expect(canvas(tester).dockPick!.second, const Offset(-5.0, 2.45));
      expect(s.sets, isEmpty);

      await tester.tap(find.widgetWithText(FilledButton, k('이 자리로 저장')));
      await tester.pumpAndSettle();

      expect(s.sets.length, 1);
      expect(s.sets.single.mapId, _map);
      expect(s.sets.single.x, -6.9);
      expect(s.sets.single.y, 2.45);
      expect(s.sets.single.yawDeg.abs(), closeTo(180, 1e-9));

      expect(find.text(k("지도에서 지정한 자리로 저장했습니다.\n'도킹해 보기'로 확인해 주세요.")),
          findsOneWidget);
      expect(stage(tester), DockPickStage.none);
      expect(canvas(tester).dockPick, isNull);
      expect(find.text(k('11-19 11:52 · 지도에서 지정한 자리 · 아직 확인 안 됨')),
          findsOneWidget);
      expect(
          find.textContaining(k('처음 도킹 시 로봇이 도크 앞 1 m로 가서')), findsOneWidget);
      expect(mapPickAgain, findsOneWidget);
    });

    testWidgets('방향은 두 번째로 누른 쪽에서 도크를 바라보는 각도다', (tester) async {
      final s = await pumpDockPanel(tester);
      await tester.tap(mapPick);
      await tester.pump();
      canvas(tester).onTapMap!(const Offset(2, 5));
      await tester.pump();
      canvas(tester).onTapMap!(const Offset(2, 3));
      await tester.pump();
      final pick = canvas(tester).dockPick!;
      expect(pick.staging!.dx, closeTo(2, 1e-9));
      expect(pick.staging!.dy, closeTo(5 - 1.151, 1e-9));
      await tester.tap(find.widgetWithText(FilledButton, k('이 자리로 저장')));
      await tester.pumpAndSettle();
      expect(s.sets.single.x, 2);
      expect(s.sets.single.y, 5);
      expect(s.sets.single.yawDeg, closeTo(90, 1e-9));
    });

    testWidgets('다시 지정은 1 / 2 로, 취소는 칸으로 돌아간다 — 저장된 도크 점은 지정하는 동안만 감춘다',
        (tester) async {
      final s = await pumpDockPanel(tester, spot: _spot());
      expect(canvas(tester).dockPoint, const Offset(-0.6, 3.65));

      await tester.tap(mapPickAgain);
      await tester.pump();
      expect(stage(tester), DockPickStage.dock);
      expect(canvas(tester).dockPoint, isNull);

      canvas(tester).onTapMap!(const Offset(1, 1));
      await tester.pump();
      await tester.tap(find.widgetWithText(OutlinedButton, k('다시 지정')));
      await tester.pump();
      expect(stage(tester), DockPickStage.dock);
      expect(canvas(tester).dockPick, isNull);

      canvas(tester).onTapMap!(const Offset(1, 1));
      await tester.pump();
      canvas(tester).onTapMap!(const Offset(2, 1));
      await tester.pump();
      expect(stage(tester), DockPickStage.preview);
      await tester.tap(find.widgetWithText(OutlinedButton, k('다시 지정')));
      await tester.pump();
      expect(stage(tester), DockPickStage.dock);

      canvas(tester).onTapMap!(const Offset(1, 1));
      await tester.pump();
      await tester.tap(find.widgetWithText(OutlinedButton, '취소'));
      await tester.pump();
      expect(stage(tester), DockPickStage.none);
      expect(canvas(tester).dockPick, isNull);
      expect(canvas(tester).dockPoint, const Offset(-0.6, 3.65));
      expect(s.sets, isEmpty);
      expect(find.widgetWithText(FilledButton, '도킹해 보기'), findsOneWidget);
    });

    testWidgets('지정하는 동안의 지도 누름은 장소·홈으로 새지 않고, 칸을 접으면 지정도 접힌다', (tester) async {
      await pumpDockPanel(tester);
      await tester.tap(mapPick);
      await tester.pump();
      canvas(tester).onTapMap!(const Offset(1, 1));
      await tester.pump();
      expect(canvas(tester).pickedLocation, isNull);
      expect(canvas(tester).dockPick, isNotNull);

      await tester.tap(find.text('홈 위치'));
      await tester.pump();
      expect(canvas(tester).dockPick, isNull);
      await tester.tap(find.text('도크 위치'));
      await tester.pump();
      expect(stage(tester), DockPickStage.none);
      expect(mapPick, findsOneWidget);
      canvas(tester).onTapMap!(const Offset(1, 1));
      await tester.pump();
      expect(canvas(tester).dockPick, isNull);
    });

    testWidgets('저장 실패 — 주행 꺼짐이면 팝업, 그 밖은 짧은 알림, 누른 점은 남는다', (tester) async {
      final s = await pumpDockPanel(tester);
      await tester.tap(mapPick);
      await tester.pump();
      canvas(tester).onTapMap!(const Offset(1, 1));
      await tester.pump();
      canvas(tester).onTapMap!(const Offset(2, 1));
      await tester.pump();

      s.setResult = (ok: false, reason: 'call_failed');
      await tester.tap(find.widgetWithText(FilledButton, k('이 자리로 저장')));
      await tester.pumpAndSettle();
      expect(find.text(k('주행이 꺼져 있습니다')), findsOneWidget);
      expect(find.text(k('도크 위치를 저장하려면 주행이 켜져 있어야 합니다.\n주행을 켠 뒤 다시 눌러 주세요.')),
          findsOneWidget);
      expect(find.textContaining(k('도크를 찾으려면')), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, '확인'));
      await tester.pumpAndSettle();
      expect(stage(tester), DockPickStage.preview);

      s.setResult = (ok: false, reason: 'busy');
      await tester.tap(find.widgetWithText(FilledButton, k('이 자리로 저장')));
      await tester.pumpAndSettle();
      expect(find.byType(VicaDialog), findsNothing);
      expect(find.text(k('로봇이 도킹 일을 하는 중입니다. 끝난 뒤 다시 저장하세요.')), findsOneWidget);
      expect(stage(tester), DockPickStage.preview);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      s.setResult = (ok: false, reason: 'map_mismatch');
      await tester.tap(find.widgetWithText(FilledButton, k('이 자리로 저장')));
      await tester.pumpAndSettle();
      expect(find.text(k('도크 위치를 저장하지 못했습니다(map_mismatch).')), findsOneWidget);
      expect(stage(tester), DockPickStage.preview);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      s.setResult = (ok: false, reason: 'not_connected');
      await tester.tap(find.widgetWithText(FilledButton, k('이 자리로 저장')));
      await tester.pumpAndSettle();
      expect(find.byType(VicaDialog), findsNothing);
      expect(find.text(k('ROS Bridge에 연결되지 않았습니다.')), findsOneWidget);
      expect(stage(tester), DockPickStage.preview);
      expect(s.sets.length, 4);
      expect(find.text(k("지도에서 지정한 자리로 저장했습니다.\n'도킹해 보기'로 확인해 주세요.")),
          findsNothing);
    });
  });

  group('보는 지도가 주행 지도가 아니면 도크를 다루지 않는다', () {
    ModeStatus driving(String mapId) => ModeStatus.fromJson({
          'mode': 'drive',
          'current_map_id': mapId,
          'running_maps': {'nav2': mapId},
        });

    /// 도크 위치 칸의 채움·테두리 버튼이 전부 눌리지 않는가.
    void expectDockButtonsOff(WidgetTester tester, int count) {
      final buttons = tester.widgetList<ButtonStyleButton>(find.descendant(
        of: find.byType(DockPositionCard),
        matching: find
            .byWidgetPredicate((w) => w is FilledButton || w is OutlinedButton),
      ));
      expect(buttons.length, count);
      for (final button in buttons) {
        expect(button.onPressed, isNull);
      }
    }

    testWidgets('도킹 노드가 다른 지도의 도크를 돌려줌 — 그 좌표를 그리지 않고 버튼을 전부 잠근다',
        (tester) async {
      const other = DockSpot(
        mapId: 'other_map',
        dockedX: -0.6,
        dockedY: 3.65,
        dockedYaw: math.pi,
        stagingX: 0.55,
        stagingY: 3.65,
        stagingYaw: math.pi,
        savedAt: '2026-11-19T11:52:00',
        visitedOk: true,
      );
      final s = await pumpDockPanel(tester, spot: other);
      expect(s.dockOnOtherMap(_map), isTrue);
      expect(canvas(tester).dockPoint, isNull);
      expect(find.text(k('미지정 · 도킹 시작 버튼이 나오지 않습니다.')), findsOneWidget);
      expect(find.textContaining(k('도크 앞 1 m  x')), findsNothing);
      expect(find.text('도킹해 보기(다시 확인)'), findsNothing);
      expectDockButtonsOff(tester, 2);
      await tester.tap(detect, warnIfMissed: false);
      await tester.tap(mapPick, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(s.registers, 0);
      expect(stage(tester), DockPickStage.none);
      canvas(tester).onTapMap!(const Offset(1, 1));
      await tester.pump();
      expect(canvas(tester).dockPick, isNull);
    });

    testWidgets('도크가 아직 없어 응답에 map_id 가 없어도, 주행 지도가 다르면 잠그고 주행 지도 띠가 알린다',
        (tester) async {
      final s = await pumpDockPanel(tester);
      expect(find.byType(DriveMapBanner), findsOneWidget);
      expect(find.text('이 지도로 주행'), findsNothing);
      expect(tester.widget<FilledButton>(detect).onPressed, isNotNull);

      s.setModeStatusForTest(driving('other_map'));
      await tester.pump();
      expect(find.text('이 지도로 주행'), findsOneWidget);
      expectDockButtonsOff(tester, 2);
      await tester.tap(detect, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(s.registers, 0);

      s.setModeStatusForTest(driving(_map));
      await tester.pump();
      expect(find.text('이 지도로 주행'), findsNothing);
      expect(tester.widget<FilledButton>(detect).onPressed, isNotNull);
      expect(tester.widget<OutlinedButton>(mapPick).onPressed, isNotNull);
    });

    testWidgets('지도에서 지정하던 중에 주행 지도가 달라지면 누름·저장을 받지 않는다', (tester) async {
      final s = await pumpDockPanel(tester);
      await tester.tap(mapPick);
      await tester.pump();
      canvas(tester).onTapMap!(const Offset(1, 1));
      await tester.pump();
      expect(stage(tester), DockPickStage.front);

      s.setModeStatusForTest(driving('other_map'));
      await tester.pump();
      expect(stage(tester), DockPickStage.none);
      expect(canvas(tester).dockPick, isNull);
      canvas(tester).onTapMap!(const Offset(3, 1));
      await tester.pump();
      expect(canvas(tester).dockPick, isNull);
      expect(canvas(tester).pickedLocation, isNull);
      expect(find.widgetWithText(FilledButton, k('이 자리로 저장')), findsNothing);
      expect(s.sets, isEmpty);
    });

    testWidgets('주행 지도와 같은 지도를 보고 있으면 그대로 쓴다', (tester) async {
      final s = await pumpDockPanel(tester, spot: _spot());
      s.setModeStatusForTest(driving(_map));
      await tester.pump();
      expect(s.dockOnOtherMap(_map), isFalse);
      expect(canvas(tester).dockPoint, const Offset(-0.6, 3.65));
      expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, '도킹해 보기'))
              .onPressed,
          isNotNull);
      expect(tester.widget<OutlinedButton>(detectAgain).onPressed, isNotNull);
      expect(tester.widget<OutlinedButton>(mapPickAgain).onPressed, isNotNull);
      expect(
          tester
              .widget<OutlinedButton>(
                  find.widgetWithText(OutlinedButton, '도크 위치 지우기'))
              .onPressed,
          isNotNull);
    });
  });

  group('폰(390 × 844)에서 지도에서 지정 세 단계', () {
    for (final scale in [1.0, 1.3]) {
      testWidgets('넘침 없이 끝까지 돈다 — 글자 배율 $scale', (tester) async {
        final errors = <String>[];
        final previous = FlutterError.onError;
        FlutterError.onError = (details) =>
            errors.add(details.exceptionAsString().split('\n').first);
        addTearDown(() => FlutterError.onError = previous);
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 844);
        addTearDown(() {
          tester.view.resetDevicePixelRatio();
          tester.view.resetPhysicalSize();
        });
        final s = _Flow()..prepare();
        await tester.pumpWidget(MediaQuery(
          data: MediaQueryData(
            size: const Size(390, 844),
            textScaler: TextScaler.linear(scale),
          ),
          child: screen(s),
        ));
        await tester.pump();

        /// 화면 밖이면 굴려서 보이게 한 뒤 누른다.
        Future<void> tapVisible(Finder finder) async {
          await tester.ensureVisible(finder);
          await tester.pumpAndSettle();
          await tester.tap(finder);
          await tester.pumpAndSettle();
        }

        await tapVisible(find.text('도크 위치'));
        await tapVisible(mapPick);

        expect(stage(tester), DockPickStage.dock);
        expect(find.text('1 / 2'), findsOneWidget);
        expect(find.text(k('지도에서 도크 구조물을 눌러 주세요.')), findsOneWidget);
        canvas(tester).onTapMap!(const Offset(-6.9, 2.45));
        await tester.pumpAndSettle();

        expect(stage(tester), DockPickStage.front);
        expect(find.text('2 / 2'), findsOneWidget);
        await tapVisible(find.widgetWithText(OutlinedButton, k('다시 지정')));
        expect(stage(tester), DockPickStage.dock);
        canvas(tester).onTapMap!(const Offset(-6.9, 2.45));
        await tester.pumpAndSettle();
        canvas(tester).onTapMap!(const Offset(-5.0, 2.45));
        await tester.pumpAndSettle();

        expect(stage(tester), DockPickStage.preview);
        expect(find.text(k('도크 앞 1 m 지점을 자동으로 잡았습니다.')), findsOneWidget);
        expect(find.text(k('방향은 두 번째로 누른 쪽입니다. 처음 도킹 시 라이다로 다시 정확히 맞춥니다.')),
            findsOneWidget);
        expect(
            canvas(tester).dockPick!.staging!.dx, closeTo(-6.9 + 1.151, 1e-9));
        await tapVisible(find.widgetWithText(FilledButton, k('이 자리로 저장')));

        expect(s.sets.single.x, -6.9);
        expect(s.sets.single.y, 2.45);
        expect(s.sets.single.yawDeg.abs(), closeTo(180, 1e-9));
        expect(stage(tester), DockPickStage.none);
        expect(find.text(k("지도에서 지정한 자리로 저장했습니다.\n'도킹해 보기'로 확인해 주세요.")),
            findsOneWidget);
        expect(find.text(k('11-19 11:52 · 지도에서 지정한 자리 · 아직 확인 안 됨')),
            findsOneWidget);
        FlutterError.onError = previous;
        expect(errors, isEmpty, reason: '폰 폭에서 넘치거나 그리기 오류가 났습니다.');
      });
    }
  });

  group('도크 위치 칸을 펼친 채로 열기(도킹 실패 팝업의 도크 위치 다시 잡기)', () {
    testWidgets('요청이 있으면 처음부터 도크 위치 칸이 펼쳐져 있다', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 2400);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });
      final s = _Flow()..prepare(spot: _spot(source: kDockSourceMapPick));
      await tester.pumpWidget(screen(s, dockPanelRequest: 1));
      await tester.pump();
      expect(find.byType(DockPositionCard), findsOneWidget);
      expect(mapPickAgain, findsOneWidget);
    });

    testWidgets('요청이 없으면 접힌 채로, 보고 있는 동안 요청이 오면 펼친다', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 2400);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });
      final s = _Flow()..prepare(spot: _spot(source: kDockSourceMapPick));
      await tester.pumpWidget(screen(s));
      await tester.pump();
      expect(find.byType(DockPositionCard), findsNothing);
      await tester.tap(find.text('홈 위치'));
      await tester.pump();
      await tester.pumpWidget(screen(s, dockPanelRequest: 1));
      await tester.pumpAndSettle();
      expect(find.byType(DockPositionCard), findsOneWidget);
      await tester.pumpWidget(screen(s, dockPanelRequest: 2));
      await tester.pumpAndSettle();
      expect(find.byType(DockPositionCard), findsOneWidget);
    });
  });

  group('탭 옮기기(셸)', () {
    Future<_Flow> pumpShell(WidgetTester tester, {DockSpot? spot}) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1400, 2400);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });
      final s = _Flow()..prepare(spot: spot);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AuthProvider()),
            ChangeNotifierProvider(create: (_) => SettingsProvider()),
            ChangeNotifierProvider(create: (_) => UiPreferencesProvider()),
            ChangeNotifierProvider<SupervisorProvider>.value(value: s),
            ChangeNotifierProvider(create: (_) => AppModeProvider()),
          ],
          child: MaterialApp(theme: vicaTheme(), home: const SupervisorShell()),
        ),
      );
      await tester.pump();
      return s;
    }

    testWidgets('도킹 실패 팝업의 도크 위치 다시 잡기 → 지도 설정의 도크 위치 칸', (tester) async {
      final s =
          await pumpShell(tester, spot: _spot(source: kDockSourceMapPick));
      expect(find.widgetWithText(AppBar, '대시보드'), findsOneWidget);
      s.handleGoalEventForTest(
          {'event': 'dock_failed', 'reason': 'not_found', 'map_id': _map});
      await tester.pumpAndSettle();
      expect(find.text('도킹하지 못했습니다'), findsOneWidget);
      expect(find.text(k('지정한 자리나 방향이 도크와 다를 수 있습니다.')), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, k('도크 위치 다시 잡기')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, '지도 설정'), findsOneWidget);
      expect(find.byType(DockPositionCard), findsOneWidget);
      expect(mapPickAgain, findsOneWidget);
      expect(detectAgain, findsOneWidget);
    });

    testWidgets('지도 설정을 떠났다 돌아오면 도크 위치 칸은 다시 접혀 있다', (tester) async {
      final s =
          await pumpShell(tester, spot: _spot(source: kDockSourceMapPick));
      s.handleGoalEventForTest(
          {'event': 'dock_failed', 'reason': 'not_found', 'map_id': _map});
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, k('도크 위치 다시 잡기')));
      await tester.pumpAndSettle();
      expect(find.byType(DockPositionCard), findsOneWidget);

      final sidebar = find.byKey(const ValueKey('desktop_sidebar'));
      await tester.tap(
          find.descendant(of: sidebar, matching: find.text('대시보드')),
          warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: sidebar, matching: find.text('지도')),
          warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, '지도 설정'), findsOneWidget);
      expect(find.byType(DockPositionCard), findsNothing);
    });

    testWidgets('도크 인식으로 저장한 자리의 실패는 확인 하나뿐이고 탭이 그대로다', (tester) async {
      final s = await pumpShell(tester, spot: _spot());
      s.handleGoalEventForTest(
          {'event': 'dock_failed', 'reason': 'not_found', 'map_id': _map});
      await tester.pumpAndSettle();
      expect(find.text('도킹하지 못했습니다'), findsOneWidget);
      expect(find.text(k('도크 위치 다시 잡기')), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, '확인'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, '대시보드'), findsOneWidget);
    });

    testWidgets('초기 위치 잡으러 가기 → 원격 주행 탭', (tester) async {
      final s = await pumpShell(tester);
      final sidebar = find.byKey(const ValueKey('desktop_sidebar'));
      await tester.tap(find.descendant(of: sidebar, matching: find.text('지도')),
          warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.tap(find.text('도크 위치'));
      await tester.pumpAndSettle();
      s.registerResults
          .add(const DockRegisterResult(ok: false, reason: 'no_amcl'));
      await tester.tap(detect);
      await tester.pumpAndSettle();
      expect(find.text(k('초기 위치를 잡아 주세요')), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, k('초기 위치\n잡으러 가기')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, '원격 주행'), findsOneWidget);
    });
  });
}
