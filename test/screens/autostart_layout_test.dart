import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vica_supervisor/app.dart';
import 'package:vica_supervisor/core/app_mode.dart';
import 'package:vica_supervisor/models/mode_status.dart';
import 'package:vica_supervisor/providers/app_mode_provider.dart';
import 'package:vica_supervisor/providers/auth_provider.dart';
import 'package:vica_supervisor/providers/settings_provider.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';
import 'package:vica_supervisor/screens/drive_bringup_screen.dart';
import 'package:vica_supervisor/screens/mode_select_screen.dart';
import 'package:vica_supervisor/widgets/drive_map_change.dart';
import 'package:vica_supervisor/widgets/drive_nodes_card.dart';
import 'package:vica_supervisor/widgets/drive_stop_button.dart';
import 'package:vica_supervisor/widgets/duplicate_run_banner.dart';
import 'package:vica_supervisor/widgets/voice_alert_snack.dart';

const _widths = <double>[320, 360, 390, 600, 900];
const _scales = <double>[1.0, 1.3, 1.6];

const _maps = {
  'maps': [
    {
      'map_id': 'map_1116_203022',
      'map_name': '4층 복도 동쪽 끝 세미나실 앞 임시 지도',
      'has_route': true,
      'has_keepout': true,
      'destination_count': 14,
      'saved_at': '2026-11-16T20:30:26'
    },
    {
      'map_id': 'map_1103_142858',
      'map_name': '킨텍스 제2전시장 9홀 로봇 시연 구역',
      'has_route': true,
      'has_keepout': true,
      'destination_count': 3,
      'saved_at': '2026-11-03T14:28:58'
    },
    {'map_id': 'map_x', 'map_name': '빈 지도', 'destination_count': 0},
  ],
  'current_map_id': 'map_1116_203022',
};

const _longDetail =
    'Nav2 기동 90 s 넘게 진행 없음(자동 재시도 뒤에도) — /vica/mode/nav2_restart 로 다시 띄웁니다';

Map<String, Object?> _status({
  String mode = 'drive',
  String state = 'running',
  String nav2 = 'active',
  String detector = 'active',
  String detail = '',
  int? stopIn,
  List<String> stopTimeouts = const [],
  String current = 'map_1116_203022',
  String running = 'map_1116_203022',
  String block = '',
  String dialog = 'idle',
}) =>
    {
      'mode': mode,
      'state': state,
      'nav2': nav2,
      'detector': detector,
      'voice': 'active',
      'voice_mode': 'online',
      'detail': detail,
      'stop_in_sec': stopIn,
      'stop_timeouts': stopTimeouts,
      'voice_events_epoch': 1.0,
      'current_map_id': current,
      'running_maps': {'nav2': running, 'mission': running, 'llm': running},
      'map_mismatch': current != running,
      'map_change_block': block,
      'dialog_state': dialog,
      'voice_events': [
        {
          'id': 1,
          'at': 1794825000.0,
          'kind': 'both_fail',
          'text':
              '외부 API·로컬 API 모두 연결 실패 (Connection refused by the remote host)'
        },
      ],
    };

Widget _app(Widget home, SupervisorProvider supervisor, double scale) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<SupervisorProvider>.value(value: supervisor),
      ChangeNotifierProvider(
          create: (_) => AppModeProvider()..enterDrive(DriveSubmode.patrol)),
      ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ChangeNotifierProvider(create: (_) => AuthProvider()),
    ],
    child: MaterialApp(
      theme: vicaTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: home,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> check(
    WidgetTester tester,
    String name,
    Map<String, Object?>? status,
    Widget Function() screen, {
    Future<void> Function(WidgetTester tester)? after,
  }) async {
    for (final scale in _scales) {
      for (final width in _widths) {
        final errors = <String>[];
        final previous = FlutterError.onError;
        FlutterError.onError = (details) =>
            errors.add(details.exceptionAsString().split('\n').first);
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 800);
        final supervisor = SupervisorProvider();
        supervisor.handleMapListForTest(Map<String, Object?>.from(_maps));
        if (status != null) {
          supervisor.handleModeStatusForTest(status);
        }
        try {
          await tester.pumpWidget(_app(screen(), supervisor, scale));
          await tester.pump();
          await tester.pump();
          await after?.call(tester);
        } finally {
          FlutterError.onError = previous;
        }
        expect(errors, isEmpty,
            reason: '$name 이(가) 폭 $width, 글자 배율 $scale 에서 넘쳤습니다.');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
      }
    }
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  }

  testWidgets('모드 선택 — 꺼짐·지난 끄기 경고', (tester) async {
    await check(
        tester,
        '모드 선택',
        _status(
            mode: 'idle',
            state: 'idle',
            nav2: 'down',
            stopTimeouts: ['nav2', 'posecheck', 'monitor']),
        () => const ModeSelectScreen());
  });

  testWidgets('모드 선택 — 주행 켜짐(지도 카드 끄고 지도로)', (tester) async {
    await check(
        tester,
        '모드 선택(주행 켜짐)',
        _status(state: 'need_initial_pose', nav2: 'waiting_pose'),
        () => const ModeSelectScreen());
  });

  testWidgets('주행 시트 — 음성 드롭다운', (tester) async {
    await check(
        tester,
        '주행 시트',
        _status(mode: 'idle', state: 'idle', nav2: 'down'),
        () => const ModeSelectScreen(), after: (tester) async {
      await tester.tap(find.text('주행'));
      await tester.pumpAndSettle();
    });
  });

  for (final (name, status, thenMapping) in [
    ('켜는 중', _status(state: 'starting', nav2: 'starting'), false),
    ('끄기 예약', _status(state: 'stopping', nav2: 'starting', stopIn: 32), false),
    (
      '기동 실패',
      _status(state: 'error', nav2: 'stalled', detail: _longDetail),
      false
    ),
    (
      '초기 위치 대기',
      _status(state: 'need_initial_pose', nav2: 'waiting_pose'),
      false
    ),
    (
      '지도로 바꾸는 중',
      _status(
          state: 'stopping',
          nav2: 'active',
          detail: '정지가 늦어지고 있습니다(34 s) — 되풀이되면 재부팅이 필요합니다'),
      true
    ),
  ]) {
    testWidgets('주행 준비 — $name', (tester) async {
      await check(
          tester,
          '주행 준비($name)',
          status,
          () => DriveBringupScreen(
              submode: DriveSubmode.patrol, thenMapping: thenMapping));
    });
  }

  testWidgets('주행 노드 카드 — 감지기 꺼짐·긴 음성 알림', (tester) async {
    await check(
        tester,
        '주행 노드 카드',
        _status(detector: 'inactive'),
        () => const Scaffold(
            body: SingleChildScrollView(
                child: Padding(
                    padding: EdgeInsets.all(16), child: DriveNodesCard()))));
  });

  testWidgets('주행 끄기 — 넓은 화면 버튼·끄는 진행 화면', (tester) async {
    await check(tester, '넓은 화면 주행 끄기', _status(),
        () => const Scaffold(body: Center(child: DriveStopButton())));
    await check(tester, '주행 끄는 중', _status(state: 'stopping', nav2: 'active'),
        () => const DriveBringupScreen(stopOnly: true));
  });

  testWidgets('중복 실행 띠', (tester) async {
    await check(
        tester,
        '중복 실행 띠',
        {
          ..._status(),
          'duplicated': [
            'ekf_node',
            'vica_mission_ma',
            'turn_guide_node',
            'vica_llm_node',
            'rplidar_node'
          ]
        },
        () => const Scaffold(body: DuplicateRunBanner()));
  });

  Widget scroll(Widget child) => Scaffold(
      body: SingleChildScrollView(
          child: Padding(padding: const EdgeInsets.all(16), child: child)));

  testWidgets('지도 바꾸기 — ③ 띠·⑥ 막힘 이유', (tester) async {
    await check(tester, '지도 띠', _status(),
        () => scroll(const DriveMapBanner(viewedMapId: 'map_1103_142858')));
    await check(
        tester,
        '지도 띠(막힘)',
        _status(
            dialog: 'navigating', block: '도착 뒤 기다리는 중엔 불가 · 끝나거나 일시정지하면 가능'),
        () => scroll(const DriveMapBanner(viewedMapId: 'map_1103_142858')));
  });

  testWidgets('지도 바꾸기 — ⑦ 불일치 카드', (tester) async {
    await check(tester, '지도 불일치', _status(current: 'map_1103_142858'),
        () => scroll(const DriveMapMismatchCard()));
  });

  testWidgets('지도 바꾸기 — ① 지도 줄·② 목록', (tester) async {
    await check(
        tester,
        '지도 줄',
        _status(mode: 'idle', state: 'idle', nav2: 'down'),
        () => scroll(const DriveMapRow()), after: (tester) async {
      await tester.tap(find.text('변경'));
      await tester.pumpAndSettle();
    });
  });

  testWidgets('지도 바꾸기 — ④-2 확인 창', (tester) async {
    await check(tester, '지도 확인 창', _status(dialog: 'paused'),
        () => scroll(const DriveMapBanner(viewedMapId: 'map_1103_142858')),
        after: (tester) async {
      await tester.tap(find.text('이 지도로 주행'));
      await tester.pumpAndSettle();
    });
  });

  testWidgets('지도 바꾸기 — ⑤ 진행 화면', (tester) async {
    await check(
        tester,
        '지도 바꾸는 중',
        _status(state: 'starting', nav2: 'starting'),
        () => const DriveBringupScreen(
              submode: DriveSubmode.guideDelivery,
              mapChange: ('4층 복도 동쪽 끝 세미나실 앞 임시 지도', '킨텍스 제2전시장 9홀 로봇 시연 구역'),
            ));
  });

  testWidgets('음성 알림 띠', (tester) async {
    final event = VoiceEvent(
      id: 1,
      at: DateTime(2026, 11, 16, 19, 42),
      kind: 'external_fallback',
      text:
          '외부 API 연결 실패 → 로컬 API 로 전환 (timeout: Request timed out after 30 seconds)',
    );
    await check(
        tester,
        '음성 알림 띠',
        null,
        () => Scaffold(
              body: Builder(builder: (context) {
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => ScaffoldMessenger.of(context)
                      .showSnackBar(voiceAlertSnackBar(event)),
                );
                return const SizedBox.expand();
              }),
            ), after: (tester) async {
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('알림 및 로그'), findsOneWidget);
    });
  });
}
