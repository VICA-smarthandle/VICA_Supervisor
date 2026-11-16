// 대시보드 '주행 노드' 카드(2026-11-16 목업 B·C): 사람 감지 잠시 끄기·음성 LOCAL/외부 API 고르기.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vica_supervisor/models/mode_status.dart';
import 'package:vica_supervisor/providers/app_mode_provider.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';
import 'package:vica_supervisor/widgets/drive_nodes_card.dart';
import 'package:vica_supervisor/widgets/vica_ui.dart';

class _FakeSupervisor extends SupervisorProvider {
  final calls = <String>[];
  (bool, String) reply = (true, '처리했습니다.');

  @override
  Future<(bool, String)> setDetector(bool on) async {
    calls.add(on ? 'detector_on' : 'detector_off');
    return reply;
  }

  @override
  Future<(bool, String)> setVoice(VoiceChoice choice) async {
    calls.add('voice_${choice.wire}');
    return reply;
  }
}

ModeStatus drive({String detector = 'active', VoiceChoice voice = VoiceChoice.local}) => ModeStatus(
      mode: 'drive',
      state: ModeState.running,
      nav2: 'active',
      detector: detector,
      voice: 'active',
      voiceChoice: voice,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<_FakeSupervisor> pump(WidgetTester tester, ModeStatus? status) async {
    final supervisor = _FakeSupervisor()..setModeStatusForTest(status);
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
        child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: DriveNodesCard()))),
      ),
    );
    await tester.pump();
    return supervisor;
  }

  testWidgets('주행이 꺼져 있거나 모드 노드가 없으면 그리지 않는다', (tester) async {
    await pump(tester, null);
    expect(find.text('주행 노드'), findsNothing);
    await pump(tester, const ModeStatus(mode: 'idle', state: ModeState.idle));
    expect(find.text('주행 노드'), findsNothing);
  });

  testWidgets('사람 감지 스위치를 끄면 감지기만 끄라고 보낸다', (tester) async {
    final supervisor = await pump(tester, drive());
    expect(find.textContaining(vicaKeepWords('켜짐 · 지팡이 사용자')), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(supervisor.calls, ['detector_off']);
  });

  testWidgets('잠시 꺼진 감지기는 이유와 함께 보이고, 다시 켤 수 있다', (tester) async {
    final supervisor = await pump(tester, drive(detector: 'inactive'));
    expect(find.text(vicaKeepWords('잠시 꺼짐')), findsOneWidget);
    expect(find.textContaining(vicaKeepWords('주행을 껐다 켜면 자동으로 켜집니다')), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(supervisor.calls, ['detector_on']);
  });

  testWidgets('음성을 외부 API 로 고르면 음성만 바꾸라고 보낸다', (tester) async {
    final supervisor = await pump(tester, drive());
    await tester.tap(find.text('로컬(LOCAL)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('외부 API').last);
    await tester.pumpAndSettle();
    expect(supervisor.calls, ['voice_online']);
  });

  testWidgets('거절되면(움직이는 중) 이유를 띄운다', (tester) async {
    final supervisor = await pump(tester, drive());
    supervisor.reply = (false, '주행 중입니다. 정지한 뒤 바꿉니다.');
    await tester.tap(find.text('로컬(LOCAL)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('외부 API').last);
    await tester.pumpAndSettle();
    expect(find.text('안 됐습니다: 주행 중입니다. 정지한 뒤 바꿉니다.'), findsOneWidget);
  });
}
