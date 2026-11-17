// 대시보드 '주행 노드' 카드(2026-11-16 목업 B·C): 사람 감지 잠시 끄기·음성 LOCAL/외부 API 고르기.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vica_supervisor/models/mode_status.dart';
import 'package:vica_supervisor/providers/app_mode_provider.dart';
import 'package:vica_supervisor/providers/settings_provider.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';
import 'package:vica_supervisor/screens/drive_bringup_screen.dart';
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

  @override
  Future<(bool, String)> driveStop() async {
    calls.add('drive_stop');
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
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ],
        child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: DriveNodesCard()))),
      ),
    );
    await tester.pump();
    return supervisor;
  }

  testWidgets('주행이 꺼져 있거나 모드 노드가 없으면 그리지 않는다', (tester) async {
    await pump(tester, null);
    expect(find.text('주행 설정'), findsNothing);
    await pump(tester, const ModeStatus(mode: 'idle', state: ModeState.idle));
    expect(find.text('주행 설정'), findsNothing);
  });

  testWidgets('사람 감지 스위치를 끄면 감지기만 끄라고 보낸다', (tester) async {
    final supervisor = await pump(tester, drive());
    // 2026-11-17 간결화(사용자 승인): 감지기 'active' 는 '켜짐' 한 단어. 음성 줄도 '켜짐'이라 둘입니다.
    expect(find.text(vicaKeepWords('켜짐')), findsNWidgets(2));

    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(supervisor.calls, ['detector_off']);
  });

  testWidgets('잠시 꺼진 감지기는 이유와 함께 보이고, 다시 켤 수 있다', (tester) async {
    final supervisor = await pump(tester, drive(detector: 'inactive'));
    expect(find.text(vicaKeepWords('잠시 꺼짐')), findsOneWidget);
    expect(
      find.text(vicaKeepWords('감지 꺼짐 · 접근 요청·경비 알림 없음 · 다시 켜면 10~20초')),
      findsOneWidget,
    );

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

  testWidgets('음성 줄에 마지막 연결 알림을 붙인다', (tester) async {
    final supervisor = await pump(tester, drive());
    supervisor.handleModeStatusForTest({
      'mode': 'drive',
      'state': 'running',
      'nav2': 'active',
      'detector': 'active',
      'voice': 'active',
      'voice_mode': 'online',
      'voice_events_epoch': 1.0,
      'voice_events': [
        {'id': 1, 'at': 1794825000.0, 'kind': 'external_fallback', 'text': '외부 API 연결 실패 → 로컬 API 로 전환'},
      ],
    });
    await tester.pump();

    expect(find.textContaining(vicaKeepWords('외부 API 연결 실패 → 로컬 API 로 전환')), findsOneWidget);
  });

  // 2026-11-17 사용자: 주행 묶음을 내리는 '주행 끄기'를 대시보드 주행 설정 카드 머리 줄에(목업 ①).
  final stopButton = find.widgetWithText(OutlinedButton, '주행 끄기');
  final confirmStop = find.widgetWithText(FilledButton, '주행 끄기');

  testWidgets('주행 끄기는 확인 창을 거쳐서만 주행을 끄고, 끄는 진행 화면을 연다', (tester) async {
    final supervisor = await pump(tester, drive());
    expect(stopButton, findsOneWidget);

    await tester.tap(stopButton);
    await tester.pumpAndSettle();
    expect(find.text('주행을 끌까요?'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(supervisor.calls, isEmpty);

    await tester.tap(stopButton);
    await tester.pumpAndSettle();
    await tester.tap(confirmStop);
    await tester.pumpAndSettle();
    expect(supervisor.calls, ['drive_stop']);
    expect(find.byType(DriveBringupScreen), findsOneWidget);
    expect(find.text('주행 끄는 중'), findsOneWidget);
  });

  testWidgets('주행 끄기가 거절되면 이유를 띄우고 진행 화면을 열지 않는다', (tester) async {
    final supervisor = await pump(tester, drive());
    supervisor.reply = (false, '로봇이 움직이는 중이라 끌 수 없습니다.');
    await tester.tap(stopButton);
    await tester.pumpAndSettle();
    await tester.tap(confirmStop);
    await tester.pumpAndSettle();

    expect(supervisor.calls, ['drive_stop']);
    expect(find.text('주행을 끄지 못했습니다'), findsOneWidget);
    // 대화창 본문은 줄 내림용으로 vicaKeepWords·vicaBreakAtSentences 를 거칩니다.
    expect(find.text(vicaKeepWords(vicaBreakAtSentences('로봇이 움직이는 중이라 끌 수 없습니다.'))), findsOneWidget);
    expect(find.byType(DriveBringupScreen), findsNothing);
  });

  testWidgets('이미 끄는 중이면 주행 끄기를 누를 수 없다', (tester) async {
    await pump(
      tester,
      const ModeStatus(mode: 'drive', state: ModeState.stopping, nav2: 'active', detector: 'active', voice: 'active'),
    );
    expect(tester.widget<OutlinedButton>(stopButton).onPressed, isNull);
  });
}
