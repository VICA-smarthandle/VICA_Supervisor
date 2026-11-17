// 원격 주행 탭 맨 위 주행 상태 줄(2026-11-17 목업 '원격 주행 A')과 공용 '주행 끄기' 버튼.
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
import 'package:vica_supervisor/widgets/drive_stop_button.dart';

class _FakeSupervisor extends SupervisorProvider {
  final calls = <String>[];

  @override
  Future<(bool, String)> driveStop() async {
    calls.add('drive_stop');
    return (true, '');
  }
}

ModeStatus drive(ModeState state) => ModeStatus(mode: 'drive', state: state, nav2: 'active');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<_FakeSupervisor> pump(WidgetTester tester, ModeStatus? status) async {
    final supervisor = _FakeSupervisor()..setModeStatusForTest(status);
    final modes = AppModeProvider()..enterDrive(DriveSubmode.guideDelivery);
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
          ChangeNotifierProvider<AppModeProvider>.value(value: modes),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ],
        child: const MaterialApp(home: Scaffold(body: DriveStatusStrip())),
      ),
    );
    await tester.pump();
    return supervisor;
  }

  final stopButton = find.widgetWithText(OutlinedButton, '주행 끄기');

  testWidgets('주행이 꺼져 있거나 모드 노드가 없으면 그리지 않는다', (tester) async {
    await pump(tester, null);
    expect(stopButton, findsNothing);
    await pump(tester, const ModeStatus(mode: 'idle', state: ModeState.idle));
    expect(stopButton, findsNothing);
  });

  testWidgets('주행 중이면 상태·하위 모드와 주행 끄기를 보인다', (tester) async {
    await pump(tester, drive(ModeState.needInitialPose));
    expect(find.textContaining('주행 켜짐'), findsOneWidget);
    expect(find.textContaining('안내·배송'), findsOneWidget);
    expect(stopButton, findsOneWidget);
  });

  testWidgets('끄는 중이면 그렇게 쓰고 버튼을 막는다', (tester) async {
    await pump(tester, drive(ModeState.stopping));
    expect(find.textContaining('주행 끄는 중'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(stopButton).onPressed, isNull);
  });

  testWidgets('누르면 대시보드와 같은 확인 창을 거쳐 끈다', (tester) async {
    final supervisor = await pump(tester, drive(ModeState.running));
    await tester.tap(stopButton);
    await tester.pumpAndSettle();
    expect(find.text('주행을 끌까요?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '주행 끄기'));
    await tester.pumpAndSettle();
    expect(supervisor.calls, ['drive_stop']);
    expect(find.byType(DriveBringupScreen), findsOneWidget);
  });
}
