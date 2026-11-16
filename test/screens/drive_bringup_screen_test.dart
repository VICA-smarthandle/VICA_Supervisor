// 주행 준비 화면(2026-11-16 목업 ②~⑤·⑥)이 모드 노드 상태대로 그리고 움직이는지 고정합니다.
//
// 이 화면은 상태를 쥐지 않고 /vica/mode_status 만 봅니다. 그래서 시험도 상태를 주입하고
// 무엇을 보여 주는지, 어떤 서비스를 부르는지, 언제 화면을 떠나는지만 봅니다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vica_supervisor/core/app_mode.dart';
import 'package:vica_supervisor/models/mode_status.dart';
import 'package:vica_supervisor/providers/app_mode_provider.dart';
import 'package:vica_supervisor/providers/settings_provider.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';
import 'package:vica_supervisor/screens/drive_bringup_screen.dart';
import 'package:vica_supervisor/widgets/vica_ui.dart';

class _FakeSupervisor extends SupervisorProvider {
  final calls = <String>[];

  void inject(ModeStatus? status) => setModeStatusForTest(status);

  @override
  Future<(bool, String)> driveStart() async {
    calls.add('drive_start');
    return (true, '');
  }

  (bool, String) stopReply = (true, '');

  @override
  Future<(bool, String)> driveStop() async {
    calls.add('drive_stop');
    return stopReply;
  }

  @override
  Future<(bool, String)> nav2Restart() async {
    calls.add('nav2_restart');
    return (true, '');
  }
}

ModeStatus status(
  String mode,
  ModeState state, {
  String nav2 = 'starting',
  String detail = '',
  int? stopInSec,
}) =>
    ModeStatus(mode: mode, state: state, nav2: nav2, detail: detail, stopInSec: stopInSec);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  // 준비 화면은 모드 선택 위에 쌓여 뜹니다. 같은 모양으로 아래에 빈 화면을 두고 그 위에 엽니다.
  Future<AppModeProvider> open(
    WidgetTester tester,
    _FakeSupervisor supervisor,
    ModeStatus? initial, {
    DriveSubmode submode = DriveSubmode.guideDelivery,
    bool thenMapping = false,
  }) async {
    final modes = AppModeProvider();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 860);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    supervisor.inject(initial);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SupervisorProvider>.value(value: supervisor),
          ChangeNotifierProvider<AppModeProvider>.value(value: modes),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => DriveBringupScreen(
                        submode: submode,
                        thenMapping: thenMapping,
                      ),
                    ),
                  ),
                  child: const Text('열기'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    return modes;
  }

  testWidgets('켜는 중에는 단계와 끄기 버튼을 보이고, 끄기는 모드 노드에 맡긴다', (tester) async {
    final supervisor = _FakeSupervisor();
    await open(tester, supervisor, status('drive', ModeState.starting));

    expect(find.text('주행 준비 중'), findsOneWidget);
    expect(find.text('Nav2 뜨는 중'), findsOneWidget);
    expect(find.text('안내·배송 모드'), findsOneWidget);

    await tester.tap(find.text('주행 끄기'));
    await tester.pump();
    expect(supervisor.calls, ['drive_stop']);
  });

  testWidgets('끄기가 거부되면(움직이는 중) 끄는 중으로 남지 않고 이유를 띄운다', (tester) async {
    final supervisor = _FakeSupervisor()..stopReply = (false, '주행 중입니다. 정지한 뒤 내립니다.');
    await open(tester, supervisor, status('drive', ModeState.needInitialPose, nav2: 'waiting_pose'));

    await tester.tap(find.text('주행 끄기'));
    await tester.pump();

    expect(supervisor.calls, ['drive_stop']);
    expect(find.text('주행 끄는 중'), findsNothing);
    expect(find.text('초기 위치를 잡아 주세요'), findsOneWidget);
    expect(find.text('주행 중입니다. 정지한 뒤 내립니다.'), findsOneWidget);
  });

  testWidgets('Nav2 가 아닌 유닛이 원인이면 Nav2 다시 띄우기를 보이지 않는다', (tester) async {
    await open(
      tester,
      _FakeSupervisor(),
      status('drive', ModeState.error, nav2: 'waiting_pose', detail: '실패한 유닛: mission'),
    );

    expect(find.text('주행 노드에 문제가 있습니다'), findsOneWidget);
    expect(find.text('Nav2 다시 띄우기'), findsNothing);
    expect(find.text('주행 끄기'), findsOneWidget);
  });

  testWidgets('끄기가 예약되면 남은 초를 알리고, 주행 계속은 예약 취소다', (tester) async {
    final supervisor = _FakeSupervisor();
    await open(tester, supervisor, status('drive', ModeState.stopping, stopInSec: 32));

    expect(find.text('끄기 예약됨'), findsOneWidget);
    // 안내문은 어절 단위 줄바꿈(vicaKeepWords)을 거치므로 같은 변환으로 찾습니다.
    expect(find.textContaining(vicaKeepWords('32초')), findsOneWidget);

    await tester.tap(find.text('끄기 취소 — 주행 계속'));
    await tester.pump();
    expect(supervisor.calls, ['drive_start']);
  });

  testWidgets('기동 실패면 이유와 Nav2 다시 띄우기를 보인다', (tester) async {
    final supervisor = _FakeSupervisor();
    await open(
      tester,
      supervisor,
      status('drive', ModeState.error, nav2: 'aborted', detail: 'Nav2 기동 중단(자동 재시도 뒤에도)'),
    );

    expect(find.text('Nav2 를 띄우지 못했습니다'), findsOneWidget);
    await tester.tap(find.text('Nav2 다시 띄우기'));
    await tester.pump();
    expect(supervisor.calls, ['nav2_restart']);
  });

  testWidgets('초기 위치 대기면 원격 주행 탭(초기 위치 카드)으로 들어간다', (tester) async {
    final supervisor = _FakeSupervisor();
    final modes = await open(
      tester,
      supervisor,
      status('drive', ModeState.needInitialPose, nav2: 'waiting_pose'),
      submode: DriveSubmode.patrol,
    );

    expect(find.text('초기 위치를 잡아 주세요'), findsOneWidget);
    await tester.tap(find.text('초기 위치 잡기'));
    await tester.pumpAndSettle();

    expect(modes.mode, AppMode.drive);
    expect(modes.driveSubmode, DriveSubmode.patrol);
    expect(modes.landingTab, '원격 주행');
    expect(find.byType(DriveBringupScreen), findsNothing);
  });

  testWidgets('다 켜지면 고른 하위 모드의 첫 화면으로 들어간다', (tester) async {
    final supervisor = _FakeSupervisor();
    final modes = await open(
      tester,
      supervisor,
      status('drive', ModeState.starting),
      submode: DriveSubmode.patrol,
    );

    supervisor.inject(status('drive', ModeState.running, nav2: 'active'));
    await tester.pumpAndSettle();

    expect(modes.mode, AppMode.drive);
    expect(modes.landingTab, '경비');
    expect(find.byType(DriveBringupScreen), findsNothing);
  });

  testWidgets('지도로 바꾸는 중이면 다 꺼진 뒤 지도 모드로 들어간다', (tester) async {
    final supervisor = _FakeSupervisor();
    final modes = await open(
      tester,
      supervisor,
      status('drive', ModeState.stopping),
      thenMapping: true,
    );

    expect(find.text('주행 끄는 중'), findsOneWidget);
    expect(modes.mode, isNull);

    supervisor.inject(status('idle', ModeState.idle, nav2: 'down'));
    await tester.pumpAndSettle();

    expect(modes.mode, AppMode.mapping);
    expect(find.byType(DriveBringupScreen), findsNothing);
  });

  testWidgets('상태가 안 오면 기다린다고 알린다', (tester) async {
    await open(tester, _FakeSupervisor(), null);

    expect(find.text('로봇에서 주행 상태를 받지 못했습니다'), findsOneWidget);
  });
}
