// 대시보드 '주행 노드' 카드(2026-11-16 목업 B·C): 사람 감지 잠시 끄기·음성 LOCAL/외부 API 고르기.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vica_supervisor/models/mode_status.dart';
import 'package:vica_supervisor/providers/app_mode_provider.dart';
import 'package:vica_supervisor/providers/settings_provider.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';
import 'package:vica_supervisor/services/mic_check_controller.dart';
import 'package:vica_supervisor/widgets/drive_nodes_card.dart';
import 'package:vica_supervisor/widgets/mic_check_entry.dart';
import 'package:vica_supervisor/widgets/vica_ui.dart';

class _FakeSupervisor extends SupervisorProvider {
  final calls = <String>[];
  (bool, String) reply = (true, '처리했습니다.');

  @override
  String get connectedUrl => 'ws://10.0.0.5:9090';

  @override
  Future<(bool, String)> setDetector(bool on) async {
    calls.add(on ? 'detector_on' : 'detector_off');
    return reply;
  }

  @override
  Future<(bool, String)> setVoiceNode(bool on) async {
    calls.add(on ? 'voice_node_on' : 'voice_node_off');
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

  @override
  Future<(bool, String)> startMicCheck() async {
    calls.add('mic_check_start');
    return reply;
  }

  @override
  Future<(bool, String)> setWakeDoaTurn(bool on) async {
    calls.add(on ? 'beam_on' : 'beam_off');
    return reply;
  }
}

// 2026-11-19: 스위치가 둘(카메라 감지·빔포밍 회전)이라 키로 찾습니다.
final _detectorSwitch = find.byKey(const ValueKey('drive_nodes_detector_switch'));
final _voiceNodeSwitch = find.byKey(const ValueKey('drive_nodes_voice_node_switch'));
final _beamSwitch = find.byKey(const ValueKey('drive_nodes_wake_doa_turn_switch'));

bool _disposed = false;

// 점검 화면 자리표시용 — 연결하지 않고 버려졌는지만 기록합니다.
class _NoopController extends MicCheckController {
  _NoopController(Uri uri) : super(uri: uri);
  @override
  void start() {}
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

// 자리표시 화면의 두 버튼이 쓰는 pop. 시험의 Navigator 는 하나뿐이라 전역 키로 부릅니다.
final _navKey = GlobalKey<NavigatorState>();
void _pop(bool value) => _navKey.currentState!.pop(value);

ModeStatus drive({
  String detector = 'active',
  VoiceChoice voice = VoiceChoice.local,
  String voiceState = 'active',
  String micCheck = 'none',
}) =>
    ModeStatus(
      mode: 'drive',
      state: ModeState.running,
      nav2: 'active',
      detector: detector,
      voice: voiceState,
      voiceChoice: voice,
      micCheck: micCheck,
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
        child: MaterialApp(navigatorKey: _navKey, home: const Scaffold(body: SingleChildScrollView(child: DriveNodesCard()))),
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
    // 2026-11-17 간결화(사용자 승인): 감지기 'active' 는 '켜짐' 한 단어. 음성 노드·음성 LLM 줄도 '켜짐'이라 셋입니다.
    expect(find.text(vicaKeepWords('켜짐')), findsNWidgets(3));

    await tester.tap(_detectorSwitch);
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

    await tester.tap(_detectorSwitch);
    await tester.pump();
    expect(supervisor.calls, ['detector_on']);
  });

  // ---- 음성 노드 켜기·끄기(2026-11-20 사용자, 캔버스 104 ①②③) ----

  Switch voiceNodeSwitch(WidgetTester tester) => tester.widget<Switch>(_voiceNodeSwitch);

  testWidgets('음성 노드 켜짐: 제목·켜진 스위치, 안내 없음', (tester) async {
    await pump(tester, drive());
    expect(find.text('음성 노드'), findsOneWidget);
    expect(voiceNodeSwitch(tester).value, isTrue);
    expect(find.text(vicaKeepWords('호출어·‘멈춰’ 안 됨')), findsNothing);
  });

  testWidgets('음성 노드 꺼짐: 꺼진 스위치·꺼짐 글자·안내', (tester) async {
    final supervisor = await pump(tester, drive(voiceState: 'inactive'));
    expect(voiceNodeSwitch(tester).value, isFalse);
    expect(voiceNodeSwitch(tester).onChanged, isNotNull);
    // 음성 노드 줄과 음성 LLM 줄이 둘 다 '꺼짐'.
    expect(find.text(vicaKeepWords('꺼짐')), findsNWidgets(2));
    expect(find.text(vicaKeepWords('호출어·‘멈춰’ 안 됨')), findsOneWidget);

    await tester.tap(_voiceNodeSwitch);
    await tester.pump();
    expect(supervisor.calls, ['voice_node_on']);
  });

  testWidgets('음성 노드 상태 글자: 켜는 중·끄는 중', (tester) async {
    await pump(tester, drive(voiceState: 'activating'));
    expect(find.text(vicaKeepWords('켜는 중')), findsWidgets);
    expect(voiceNodeSwitch(tester).value, isTrue);
    await pump(tester, drive(voiceState: 'deactivating'));
    expect(find.text(vicaKeepWords('끄는 중')), findsOneWidget);
  });

  testWidgets('음성 노드가 끄는 중이면 스위치를 못 누른다', (tester) async {
    await pump(tester, drive(voiceState: 'deactivating'));
    expect(voiceNodeSwitch(tester).onChanged, isNull);
  });

  testWidgets('음성 노드 스위치를 끄면 setVoiceNode(false) 와 받은 문구를 스낵으로 보인다', (tester) async {
    final supervisor = await pump(tester, drive());
    supervisor.reply = (true, '음성 노드를 껐습니다');
    await tester.tap(_voiceNodeSwitch);
    await tester.pump();
    await tester.pump();
    expect(supervisor.calls, ['voice_node_off']);
    expect(find.text('음성 노드를 껐습니다'), findsOneWidget);
  });

  testWidgets('음성 노드 거절이면 "안 됐습니다: " 를 붙여 보인다', (tester) async {
    final supervisor = await pump(tester, drive());
    supervisor.reply = (false, '로봇이 움직이는 중입니다. 멈춘 뒤 다시 누르세요.');
    await tester.tap(_voiceNodeSwitch);
    await tester.pump();
    await tester.pump();
    expect(find.text('안 됐습니다: 로봇이 움직이는 중입니다. 멈춘 뒤 다시 누르세요.'), findsOneWidget);
  });

  // ---- 마이크 점검 들어가는 곳(2026-11-20, 캔버스 104 ②④·106) ----

  final starts = <Uri>[];
  setUp(() {
    starts.clear();
    _disposed = false;
    micCheckControllerFactory = (uri) {
      starts.add(uri);
      return _NoopController(uri);
    };
    // 점검 화면 대신 '끝내기'(true)·'저절로 끝남'(false) 버튼만 있는 자리표시 화면.
    micCheckScreenBuilder = (controller, supervisor) => Scaffold(
          body: Column(children: [
            TextButton(onPressed: () => _pop(true), child: const Text('끝내기')),
            TextButton(onPressed: () => _pop(false), child: const Text('저절로 끝남')),
          ]),
        );
  });

  Finder micButton() => find.byKey(const ValueKey('mic_check_entry_button'));
  bool micButtonEnabled(WidgetTester tester) =>
      tester.widget<FilledButton>(micButton()).onPressed != null;

  testWidgets('마이크 점검 줄: 음성 켜짐이면 "음성을 끄면 시작"·점검 비활성', (tester) async {
    await pump(tester, drive());
    expect(find.text('마이크 점검'), findsOneWidget);
    expect(find.text(vicaKeepWords('음성을 끄면 시작')), findsOneWidget);
    expect(micButtonEnabled(tester), isFalse);
  });

  testWidgets('마이크 점검 줄: 음성 꺼짐이면 "약 12분 · 로봇 정지"·점검 활성', (tester) async {
    await pump(tester, drive(voiceState: 'inactive'));
    expect(find.text(vicaKeepWords('약 12분 · 로봇 정지')), findsOneWidget);
    expect(micButtonEnabled(tester), isTrue);
  });

  testWidgets('점검 중: "● 점검 중"·"이어 하기", 음성 노드 스위치 잠김·"점검 중 · 켤 수 없음"', (tester) async {
    await pump(tester, drive(voiceState: 'inactive', micCheck: 'active'));
    expect(find.text(vicaKeepWords('● 점검 중')), findsOneWidget);
    expect(find.text('이어 하기'), findsOneWidget);
    expect(find.text(vicaKeepWords('점검 중 · 켤 수 없음')), findsOneWidget);
    expect(tester.widget<Switch>(_voiceNodeSwitch).onChanged, isNull);
    expect(find.text(vicaKeepWords('호출어·‘멈춰’ 안 됨')), findsNothing);
  });

  testWidgets('점검 → 확인 창(감지 켜짐이면 세 줄) → 취소하면 아무 일 없다', (tester) async {
    final supervisor = await pump(tester, drive(voiceState: 'inactive'));
    await tester.tap(micButton());
    await tester.pumpAndSettle();
    expect(find.text('마이크 점검을 시작할까요?'), findsOneWidget);
    expect(find.text('약 12분 · 손잡이 자리에서 진행'), findsOneWidget);
    expect(find.text('카메라 감지도 끕니다'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(supervisor.calls, isEmpty);
  });

  testWidgets('감지가 이미 꺼져 있으면 확인 창에 세 번째 줄이 없다', (tester) async {
    await pump(tester, drive(voiceState: 'inactive', detector: 'inactive'));
    await tester.tap(micButton());
    await tester.pumpAndSettle();
    expect(find.text('약 12분 · 손잡이 자리에서 진행'), findsOneWidget);
    expect(find.text('카메라 감지도 끕니다'), findsNothing);
  });

  testWidgets('시작 → startMicCheck, 받으면 노드 문구 스낵 + 점검 화면', (tester) async {
    final supervisor = await pump(tester, drive(voiceState: 'inactive'));
    supervisor.reply = (true, '마이크 점검을 시작합니다 · 준비 1~2분');
    await tester.tap(micButton());
    await tester.pumpAndSettle();
    await tester.tap(find.text('시작'));
    await tester.pumpAndSettle();
    expect(supervisor.calls, ['mic_check_start']);
    expect(find.text('마이크 점검을 시작합니다 · 준비 1~2분'), findsOneWidget);
    expect(find.text('끝내기'), findsOneWidget);
    expect(starts, hasLength(1));
    expect(starts.single.port, 8770);
  });

  testWidgets('시작이 거절되면 "안 됐습니다: " + 문구, 점검 화면은 안 열린다', (tester) async {
    final supervisor = await pump(tester, drive(voiceState: 'inactive'));
    supervisor.reply = (false, '로봇이 움직이는 중입니다. 멈춘 뒤 다시 누르세요.');
    await tester.tap(micButton());
    await tester.pumpAndSettle();
    await tester.tap(find.text('시작'));
    await tester.pumpAndSettle();
    expect(find.text('안 됐습니다: 로봇이 움직이는 중입니다. 멈춘 뒤 다시 누르세요.'), findsOneWidget);
    expect(find.text('끝내기'), findsNothing);
    expect(starts, isEmpty);
  });

  testWidgets('이어 하기는 시작 서비스 없이 화면만 연다', (tester) async {
    final supervisor = await pump(tester, drive(voiceState: 'inactive', micCheck: 'active'));
    await tester.tap(micButton());
    await tester.pumpAndSettle();
    expect(supervisor.calls, isEmpty);
    expect(find.text('끝내기'), findsOneWidget);
  });

  testWidgets('true 로 닫히면 주행 켜짐 끝 스낵, 컨트롤러는 버린다', (tester) async {
    await pump(tester, drive(voiceState: 'inactive', micCheck: 'active'));
    await tester.tap(micButton());
    await tester.pumpAndSettle();
    await tester.tap(find.text('끝내기'));
    await tester.pumpAndSettle();
    expect(find.text('점검을 끝냈습니다 · 음성 노드를 켜야 새 값이 적용됩니다'), findsOneWidget);
    expect(_disposed, isTrue);
  });

  testWidgets('false 로 닫히면(저절로 끝남) 끝 스낵 없음', (tester) async {
    await pump(tester, drive(voiceState: 'inactive', micCheck: 'active'));
    await tester.tap(micButton());
    await tester.pumpAndSettle();
    await tester.tap(find.text('저절로 끝남'));
    await tester.pumpAndSettle();
    expect(find.textContaining('점검을 끝냈습니다'), findsNothing);
  });

  // ---- 빔포밍 회전(2026-11-19 사용자, 캔버스 101번 보드) ----

  Switch beamSwitch(WidgetTester tester) => tester.widget<Switch>(_beamSwitch);

  testWidgets('빔포밍 켜짐: 켜진 스위치, 나침반 아이콘, 경고 칸 없음', (tester) async {
    final supervisor = await pump(tester, drive());
    supervisor.setWakeDoaTurnForTest(true);
    await tester.pump();
    expect(find.text('빔포밍 회전'), findsOneWidget);
    // 감지기·음성 노드·빔포밍·음성 LLM 네 줄이 '켜짐'.
    expect(find.text(vicaKeepWords('켜짐')), findsNWidgets(4));
    expect(beamSwitch(tester).value, isTrue);
    expect(beamSwitch(tester).onChanged, isNotNull);
    expect(find.byIcon(Icons.explore_outlined), findsOneWidget);
    expect(find.text(vicaKeepWords('회전 꺼짐')), findsNothing);
  });

  testWidgets('빔포밍 꺼짐: 잠시 꺼짐과 경고 칸, 사선 나침반', (tester) async {
    final supervisor = await pump(tester, drive());
    supervisor.setWakeDoaTurnForTest(false);
    await tester.pump();
    expect(find.text(vicaKeepWords('잠시 꺼짐')), findsOneWidget);
    expect(find.text(vicaKeepWords('회전 꺼짐')), findsOneWidget);
    expect(beamSwitch(tester).value, isFalse);
    expect(find.byIcon(Icons.explore_off_outlined), findsOneWidget);

    await tester.tap(_beamSwitch);
    await tester.pump();
    expect(supervisor.calls, ['beam_on']);
  });

  testWidgets('끄면 beam_off 를 보내고 노드 문구를 띄우지만, 표시는 상태 토픽이 올 때까지 그대로', (tester) async {
    final supervisor = await pump(tester, drive());
    supervisor
      ..setWakeDoaTurnForTest(true)
      ..reply = (true, '빔포밍 회전을 껐습니다');
    await tester.pump();

    await tester.tap(_beamSwitch);
    await tester.pumpAndSettle();
    expect(supervisor.calls, ['beam_off']);
    expect(find.text('빔포밍 회전을 껐습니다'), findsOneWidget);
    expect(beamSwitch(tester).value, isTrue);
  });

  testWidgets('빔포밍 거절이면 이유를 띄운다', (tester) async {
    final supervisor = await pump(tester, drive());
    supervisor
      ..setWakeDoaTurnForTest(true)
      ..reply = (false, '빔포밍 회전을 바꾸지 못했습니다.');
    await tester.pump();

    await tester.tap(_beamSwitch);
    await tester.pumpAndSettle();
    expect(find.text('안 됐습니다: 빔포밍 회전을 바꾸지 못했습니다.'), findsOneWidget);
  });

  // 2026-11-19 사용자: 음성이 다시 뜨는 동안은 이전 값 대신 '재가동 중'(캔버스 101 ③).
  ModeStatus driveVoice(String voice) => ModeStatus(
        mode: 'drive',
        state: ModeState.running,
        nav2: 'active',
        detector: 'active',
        voice: voice,
        voiceChoice: VoiceChoice.local,
      );

  testWidgets('음성은 active 인데 상태를 아직 못 받았으면 재가동 중, 스위치는 잠긴다', (tester) async {
    final supervisor = await pump(tester, drive());
    expect(find.text(vicaKeepWords('재가동 중')), findsOneWidget);
    expect(beamSwitch(tester).onChanged, isNull);

    await tester.tap(_beamSwitch);
    await tester.pump();
    expect(supervisor.calls, isEmpty);
  });

  for (final voice in ['deactivating', 'activating']) {
    testWidgets('음성 유닛이 $voice 이면 남아 있는 켜짐 값 대신 재가동 중', (tester) async {
      final supervisor = await pump(tester, driveVoice(voice));
      supervisor.setWakeDoaTurnForTest(true);
      await tester.pump();
      expect(find.text(vicaKeepWords('재가동 중')), findsOneWidget);
      expect(beamSwitch(tester).onChanged, isNull);
    });
  }

  for (final voice in ['inactive', 'failed', 'none']) {
    testWidgets('음성 유닛이 $voice 이면 음성 꺼짐 · 바꿀 수 없음', (tester) async {
      await pump(tester, driveVoice(voice));
      expect(find.text(vicaKeepWords('음성 꺼짐 · 바꿀 수 없음')), findsOneWidget);
      expect(find.text(vicaKeepWords('재가동 중')), findsNothing);
      expect(beamSwitch(tester).onChanged, isNull);
    });
  }

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

  // 2026-11-18: '주행 끄기'는 위쪽 막대로 옮겼습니다(drive_stop_button_test.dart).
  testWidgets('카드에는 주행 끄기 버튼이 없다', (tester) async {
    await pump(tester, drive());
    expect(find.text('주행 끄기'), findsNothing);
    expect(find.text('주행 설정'), findsOneWidget);
  });
}
