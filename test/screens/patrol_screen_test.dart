// 경비(순찰) 화면 — 목업 Patrol* 14개와 글자·흐름을 대조합니다(2026-11-14).
//
// 화면에 보이는 글자는 목업 그대로여야 합니다. 목업에 없는 글자를 넣거나 목업 글자가
// 바뀌면 여기서 깨집니다. 목업과 다르게 둔 곳은 그 까닭을 시험 이름에 적었습니다.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vica_supervisor/app.dart';
import 'package:vica_supervisor/core/app_settings.dart';
import 'package:vica_supervisor/core/log_filter.dart';
import 'package:vica_supervisor/models/patrol.dart';
import 'package:vica_supervisor/providers/app_mode_provider.dart';
import 'package:vica_supervisor/providers/auth_provider.dart';
import 'package:vica_supervisor/providers/settings_provider.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';
import 'package:vica_supervisor/providers/ui_preferences_provider.dart';
import 'package:vica_supervisor/screens/logs_screen.dart';
import 'package:vica_supervisor/screens/patrol_screen.dart';
import 'package:vica_supervisor/services/patrol_log_loader.dart';
import 'package:vica_supervisor/services/route_graph_loader.dart';
import 'package:vica_supervisor/widgets/map_canvas.dart';
import 'package:vica_supervisor/widgets/patrol_alarm_dialog.dart';
import 'package:vica_supervisor/widgets/patrol_media.dart';
import 'package:vica_supervisor/widgets/patrol_route_editor.dart';
import 'package:vica_supervisor/widgets/patrol_ui.dart';
import 'package:vica_supervisor/widgets/vica_ui.dart';

import '../ros/fake_ros_socket.dart';

const _phone = Size(390, 844);
const _wide = Size(1400, 1100);
const _intruder = '20261114_021341_intruder';
const _light = '20261114_005207_light';
const _sound = '20261114_014012_sound';
const _camera = '20261114_030255_camera_lost';

/// 목업의 장소 아홉 곳. 앞 여섯이 순찰 경로입니다.
const _places = <(String, String, double, double)>[
  ('p1', '입구', 4.0, 3.4),
  ('p2', '안내소', 3.3, 10.8),
  ('p3', '작업실', 9.4, 15.1),
  ('p4', '화장실', 22.8, 14.3),
  ('p5', '방2', 22.8, 5.8),
  ('p6', '407호', 17.1, 5.6),
  ('p7', '휴게실', 16.6, 10.2),
  ('p8', '민원실', 8.1, 5.8),
  ('p9', '식당', 20.2, 4.7),
];

String _k(String text) => vicaKeepWords(text);

/// 지도 서버가 내줄 경비 기록(목업 PatrolLog 의 네 줄).
String _records({String clipState = 'ready'}) => jsonEncode([
      {
        'alarm_id': _intruder,
        'kind': 'intruder',
        'time': '2026-11-14T02:13:41',
        'place': '화장실',
        'clip_id': _intruder,
        'photo': null,
        'level_db': null,
        'clip_state': clipState,
        'clip_sec': 42.0,
        'clip_start': '2026-11-14T02:13:36',
        'clip_end': '2026-11-14T02:14:18',
        'detect_sec': 5.0,
      },
      {
        'alarm_id': _sound,
        'kind': 'sound',
        'time': '2026-11-14T01:40:12',
        'place': '방2',
        'clip_id': _sound,
        'level_db': 70.2,
        'clip_state': 'ready',
        'clip_sec': 15.0,
      },
      {
        'alarm_id': _light,
        'kind': 'light',
        'time': '2026-11-14T00:52:07',
        'place': '407호',
        'photo': '20261114_005207.jpg',
        'clip_state': 'missing',
      },
      {
        'alarm_id': _camera,
        'kind': 'camera_lost',
        'time': '2026-11-13T03:02:55',
        'place': '작업실',
        'clip_state': 'missing',
      },
    ]);

class _Supervisor extends SupervisorProvider {
  _Supervisor({super.rosChannelConnector, String? records})
      : super(
          // 네트워크 없이: 레일은 없고, 경비 기록은 넣어 준 글자 그대로.
          routeGraphLoader: RouteGraphLoader(fetch: (_) async => null),
          patrolLogLoader: PatrolLogLoader(fetch: (_) async => records),
        );

  void injectMap() => handleMapListForTest({
        'maps': [
          {
            'map_id': 'm1',
            'map_name': '4층',
            'image_url': '/maps/m1.png',
            'resolution': 0.05,
            'origin_x': 0.0,
            'origin_y': 0.0,
            'width': 598,
            'height': 384,
            'is_current': true,
          },
        ],
        'current_map_id': 'm1',
      });

  void injectPlaces() => handleLocationListForTest({
        'map_id': 'm1',
        'locations': [
          for (final (id, name, x, y) in _places)
            {
              'id': id,
              'name': name,
              'pose': {'x': x, 'y': y, 'yaw': 0.0},
            },
        ],
      });

  void injectStatus(String dialog) => handleRobotStatusForTest({
        'robot_id': 'vica_01',
        'robot_name': 'VICA-01',
        'status': 'idle',
        'x': 20.0,
        'y': 14.0,
        'yaw': 0.0,
        'current_location': '',
        'current_goal': '',
        'error_reason': '',
        'waiting_reason': '',
        'map_id': 'm1',
        'timestamp': '2026-11-14T02:13:41',
        'dialog_state': dialog,
      });

  void injectRoute(int count) => setPatrolRouteForTest(
        PatrolRoute(
          mapId: 'm1',
          ids: [for (final p in _places.take(count)) p.$1],
          names: [for (final p in _places.take(count)) p.$2],
        ),
      );

  void event(String name, [Map<String, Object?> extra = const {}]) =>
      handleGoalEventForTest({
        'event': name,
        'map_id': 'm1',
        'name': '',
        'reason': '',
        'timestamp': '2026-11-14T02:13:41',
        ...extra,
      });

  void alarm(String name, String alarmId, String place,
          [Map<String, Object?> extra = const {}]) =>
      event(name, {
        'alarm_id': alarmId,
        'place': place,
        'robot_x': 20.0,
        'robot_y': 14.0,
        ...extra,
      });
}

/// 42초짜리 가짜 영상. 조작만 기록합니다.
class _FakePlayer extends ChangeNotifier implements PatrolClipPlayer {
  Duration _position = const Duration(seconds: 16);
  bool _playing = false;
  final List<String> calls = [];

  @override
  Duration get duration => const Duration(seconds: 42);

  @override
  Duration get position => _position;

  @override
  bool get playing => _playing;

  @override
  double get aspectRatio => 4 / 3;

  @override
  Future<void> play() async {
    _playing = true;
    calls.add('play');
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    _playing = false;
    calls.add('pause');
    notifyListeners();
  }

  @override
  Future<void> seekTo(Duration position) async {
    _position = position;
    calls.add('seek ${position.inSeconds}');
    notifyListeners();
  }

  @override
  Widget buildView(BuildContext context) =>
      const ColoredBox(color: Colors.black, key: ValueKey('fake_video'));
}

Widget _app(Widget child, SupervisorProvider supervisor, {double scale = 1.0}) {
  return MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: MultiProvider(
      providers: [
        ChangeNotifierProvider<SupervisorProvider>.value(value: supervisor),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: MaterialApp(theme: vicaTheme(), home: Scaffold(body: child)),
    ),
  );
}

void _size(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
}

/// rosbridge 에 붙은 provider.
Future<(_Supervisor, FakeRosServer)> _connected(
  WidgetTester tester, {
  String? records,
}) async {
  final server = FakeRosServer();
  final supervisor =
      _Supervisor(rosChannelConnector: server.connect, records: records);
  supervisor
    ..injectMap()
    ..injectPlaces();
  await supervisor.connect(const AppSettings());
  // 연결하면 고른 지도의 홈·금지구역을 묻고(응답 없이 5초 뒤 포기), 10초 버틴 뒤 재시도
  // 횟수를 되돌립니다. 그 타이머들을 먼저 흘려보냅니다 — 남겨 두면 시험이 끝날 때
  // '타이머가 남았다'로 걸립니다.
  await tester.pump(const Duration(seconds: 11));
  supervisor.injectStatus('idle');
  addTearDown(supervisor.dispose);
  return (supervisor, server);
}

/// 사람·큰 소리 경보는 영상이 저장될 때까지 5초마다 기록을 다시 받습니다(최대 90초).
/// 그 타이머가 스스로 멈출 때까지 흘려보냅니다.
Future<void> _drain(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 100));

/// 화면이 열리며 보낸 경로 읽기 요청에 답합니다.
Future<void> _answerRoute(
  WidgetTester tester,
  FakeRosServer server,
  int count,
) async {
  expect(
    server.last.answer('/vica/patrol/route/get', {
      'found': count > 0,
      'map_id': 'm1',
      'destination_ids': [for (final p in _places.take(count)) p.$1],
      'names': [for (final p in _places.take(count)) p.$2],
      'message': '',
    }),
    isTrue,
    reason: '화면이 경로를 읽지 않았습니다.',
  );
  // 응답을 받아들이는 박자 하나, 그 결과를 그리는 박자 하나.
  await tester.pump();
  await tester.pump();
}

List<Map<String, Object?>> _calls(FakeRosServer server, String service) => [
      for (final command in server.last.sent)
        if (command['op'] == 'call_service' && command['service'] == service)
          command,
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('꺼짐(목업 PatrolHome)', () {
    testWidgets('목업의 글자가 그대로 보인다', (tester) async {
      _size(tester, _phone);
      final (supervisor, server) =
          await _connected(tester, records: _records());
      await tester.pumpWidget(_app(const PatrolScreen(), supervisor));
      await tester.pump();
      await _answerRoute(tester, server, 6);

      for (final text in [
        '경비',
        '경비가 꺼져 있습니다',
        '순찰 경로',
        '장소 6곳',
        '경로 편집',
        '감시 항목',
        '사람 감지',
        '불 켜짐 확인',
        '큰 소리',
        '경비 시작',
      ]) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      for (final text in [
        '손잡이 LED: 평소 색(하늘색)',
        '입구 → 안내소 → 작업실 → 화장실 → 방2 → 407호 → 다시 입구',
        '카메라 · 보이면 멈추고 경보',
      ]) {
        expect(find.text(_k(text)), findsOneWidget, reason: text);
      }
      // 감시 항목은 셋 다 켜짐 표시뿐이다(끄는 길이 없다).
      expect(find.byType(PatrolOnMark), findsNWidgets(3));
      expect(find.byType(Switch), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('목업의 옛 기준(40 dB·0.3초·시험 뒤 확정)은 옮기지 않았다', (tester) async {
      _size(tester, _phone);
      final (supervisor, server) = await _connected(tester);
      await tester.pumpWidget(_app(const PatrolScreen(), supervisor));
      await tester.pump();
      await _answerRoute(tester, server, 6);

      expect(find.textContaining('dB'), findsNothing);
      expect(find.textContaining('0.3'), findsNothing);
      expect(find.textContaining('시험'), findsNothing);
      expect(find.text(_k('기준 이상이 0.5초 넘게 들리면')), findsOneWidget);
      expect(find.text(_k('밝기 대비로 판정')), findsOneWidget);
    });

    testWidgets('기록 건수는 지도 서버에서 받은 수다', (tester) async {
      _size(tester, _phone);
      final (supervisor, server) =
          await _connected(tester, records: _records());
      var opened = 0;
      await tester.pumpWidget(
        _app(PatrolScreen(onOpenRecords: () => opened += 1), supervisor),
      );
      await tester.pump();
      await _answerRoute(tester, server, 6);
      await tester.pump();

      final link = find.text('경비 기록 4건');
      expect(link, findsOneWidget);
      await tester.ensureVisible(link);
      await tester.tap(link);
      expect(opened, 1);
    });

    testWidgets('지점이 2곳 미만이면 로봇에 묻지 않고 목업 문구로 알린다', (tester) async {
      _size(tester, _phone);
      final (supervisor, server) = await _connected(tester);
      await tester.pumpWidget(_app(const PatrolScreen(), supervisor));
      await tester.pump();
      await _answerRoute(tester, server, 1);

      await tester.tap(find.text('경비 시작'));
      await tester.pump();
      expect(
        find.text(_k('순찰 지점이 2곳 이상이어야 경비를 시작할 수 있습니다.')),
        findsOneWidget,
      );
      expect(_calls(server, '/vica/mission/patrol_start'), isEmpty);
    });

    testWidgets('경비 시작 → 수락되면 알림 띠와 순찰 화면', (tester) async {
      _size(tester, _phone);
      final (supervisor, server) = await _connected(tester);
      await tester.pumpWidget(_app(const PatrolScreen(), supervisor));
      await tester.pump();
      await _answerRoute(tester, server, 6);

      await tester.tap(find.text('경비 시작'));
      await tester.pump();
      expect(_calls(server, '/vica/mission/patrol_start'), hasLength(1));
      server.last.answer('/vica/mission/patrol_start', {
        'accepted': true,
        'message': 'patrol_start 요청을 처리했습니다.',
      });
      await tester.pump();
      await tester.pump();

      expect(find.text(_k('경비를 시작했습니다.')), findsOneWidget);
      expect(find.text('순찰 중'), findsOneWidget);
      expect(find.text('경비가 꺼져 있습니다'), findsNothing);
    });

    testWidgets('연결이 없으면 꺼졌다고 적지 않고 시작을 잠근다', (tester) async {
      _size(tester, _phone);
      final supervisor = _Supervisor();
      addTearDown(supervisor.dispose);
      await tester.pumpWidget(_app(const PatrolScreen(), supervisor));
      await tester.pump();

      expect(find.text('ROS 연결 안 됨'), findsOneWidget);
      expect(find.text('경비가 꺼져 있습니다'), findsNothing);
      final start = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '경비 시작'),
      );
      expect(start.onPressed, isNull);
    });
  });

  group('순찰 중(목업 PatrolRunning)', () {
    Future<(_Supervisor, FakeRosServer)> running(WidgetTester tester) async {
      _size(tester, _phone);
      final (supervisor, server) = await _connected(tester);
      supervisor
        ..event('patrol_started', {
          'timestamp': '2026-11-14T22:04:10',
          'route': [for (final p in _places.take(6)) p.$2],
        })
        ..event('patrol_waypoint',
            {'name': '화장실', 'index': 3, 'lap': 3, 'count': 6})
        ..injectStatus('patrolling');
      await tester.pumpWidget(_app(const PatrolScreen(), supervisor));
      await tester.pump();
      await _answerRoute(tester, server, 6);
      return (supervisor, server);
    }

    testWidgets('어디로 가는 중인지, 시작 시각과 바퀴 수', (tester) async {
      await running(tester);

      expect(find.text('순찰 중'), findsOneWidget);
      expect(find.text(_k('작업실 → 화장실로 가는 중입니다.')), findsOneWidget);
      expect(find.text(_k('22:04 시작 · 3바퀴째')), findsOneWidget);
      expect(find.byType(MapCanvas), findsOneWidget);
      expect(find.text('카메라'), findsOneWidget);
      expect(find.text('정상'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '일시정지'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '경비 종료'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('마이크·영상 저장 공간 줄은 없다 — 로봇이 그 값을 보내지 않는다', (tester) async {
      await running(tester);
      expect(find.text('마이크'), findsNothing);
      expect(find.textContaining('저장 공간'), findsNothing);
      expect(find.textContaining('남은 용량'), findsNothing);
    });

    testWidgets('경비 종료는 한 번 묻고, 종료하면 홈으로 돌아간다고 알린다(목업 PatrolStopConfirm)',
        (tester) async {
      final (supervisor, server) = await running(tester);
      await tester.ensureVisible(find.text('경비 종료'));
      await tester.tap(find.text('경비 종료'));
      await tester.pumpAndSettle();

      expect(find.text('경비를 종료할까요?'), findsOneWidget);
      // 목업의 두 줄 그대로(2026-11-14 사용자 결정: 종료하면 로봇이 홈으로 돌아간다).
      expect(
        find.text(_k('순찰을 멈추고 로봇이 홈으로 돌아갑니다.\n녹화 중인 영상은 끝까지 저장합니다.')),
        findsOneWidget,
      );
      expect(find.text('계속 경비'), findsOneWidget);

      await tester.tap(find.text('계속 경비'));
      await tester.pumpAndSettle();
      expect(_calls(server, '/vica/mission/patrol_stop'), isEmpty);

      await tester.tap(find.text('경비 종료'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '경비 종료'));
      await tester.pumpAndSettle();
      expect(_calls(server, '/vica/mission/patrol_stop'), hasLength(1));
      // 미션은 종료 사건을 내고 응답한다.
      supervisor
          .event('patrol_stopped', {'reason': 'admin', 'return_home': true});
      server.last.answer('/vica/mission/patrol_stop',
          {'accepted': true, 'message': '경비를 종료했습니다.'});
      await tester.pump();
      await tester.pump();
      // 알림 띠는 목업 PatrolTexts 의 두 줄.
      expect(
        find.text(_k('경비를 종료했습니다.\n로봇이 홈으로 돌아갑니다.')),
        findsOneWidget,
      );
      expect(find.text('경비 시작'), findsOneWidget);
    });

    testWidgets('홈이 없어 못 돌아가면 홈 복귀 버튼과 같은 문구를 둘째 줄에 보인다', (tester) async {
      final (supervisor, server) = await running(tester);
      await tester.ensureVisible(find.text('경비 종료'));
      await tester.tap(find.text('경비 종료'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '경비 종료'));
      await tester.pumpAndSettle();
      supervisor
          .event('patrol_stopped', {'reason': 'admin', 'return_home': false});
      // 미션은 종료는 받아들이고, 홈 복귀 서비스의 거절과 같은 글자를 싣는다.
      server.last.answer('/vica/mission/patrol_stop',
          {'accepted': true, 'message': '홈 복귀 거부: no_home'});
      await tester.pump();
      await tester.pump();
      expect(
        find.text(_k(
          '경비를 종료했습니다.\n'
          '홈 위치가 지정되지 않았습니다. 지도 설정 화면에서 먼저 지정하세요.',
        )),
        findsOneWidget,
      );
      expect(find.textContaining('no_home'), findsNothing);
      expect(find.textContaining(_k('홈으로 돌아갑니다')), findsNothing);
      expect(find.text('경비 시작'), findsOneWidget);
    });

    testWidgets('일시정지 → 일시정지 화면과 순찰 재개', (tester) async {
      final (_, server) = await running(tester);
      await tester.ensureVisible(find.text('일시정지'));
      await tester.tap(find.text('일시정지'));
      await tester.pump();
      server.last.answer('/vica/mission/pause_navigation',
          {'accepted': true, 'message': 'pause 요청을 처리했습니다.'});
      await tester.pump();
      await tester.pump();

      // 알약 하나. 경보 이름이 붙지 않는다.
      expect(find.text('일시정지'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '순찰 재개'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);

      await tester.ensureVisible(find.text('순찰 재개'));
      await tester.tap(find.text('순찰 재개'));
      await tester.pump();
      server.last.answer(
          '/vica/mission/resume_navigation', {'accepted': true, 'message': ''});
      await tester.pump();
      await tester.pump();
      expect(find.text(_k('순찰을 재개했습니다.')), findsOneWidget);
      expect(find.text('순찰 중'), findsOneWidget);
    });
  });

  // 경비를 종료하면 로봇은 기존 홈 복귀(returning, return_home_sent …)로 넘어갑니다. 그동안
  // 경비 탭은 꺼짐 화면이고, 종료 알림 띠 말고 같은 내용을 또 알리는 것이 없어야 합니다.
  group('경비 종료 뒤 홈 복귀', () {
    Future<(_Supervisor, FakeRosServer)> stopFromShell(
      WidgetTester tester,
    ) async {
      _size(tester, _phone);
      final (supervisor, server) = await _connected(tester);
      supervisor
        ..event('patrol_started', {
          'route': [for (final p in _places.take(6)) p.$2],
        })
        ..event('patrol_waypoint',
            {'name': '화장실', 'index': 3, 'lap': 1, 'count': 6})
        ..injectStatus('patrolling');
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AuthProvider()),
            ChangeNotifierProvider(create: (_) => SettingsProvider()),
            ChangeNotifierProvider(create: (_) => UiPreferencesProvider()),
            ChangeNotifierProvider<SupervisorProvider>.value(value: supervisor),
            ChangeNotifierProvider(create: (_) => AppModeProvider()),
          ],
          child: MaterialApp(theme: vicaTheme(), home: const SupervisorShell()),
        ),
      );
      await tester.pump();
      await tester.tap(find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('경비'),
      ));
      await tester.pump();
      await tester.pump();
      await _answerRoute(tester, server, 6);

      await tester.ensureVisible(find.text('경비 종료'));
      await tester.tap(find.text('경비 종료'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '경비 종료'));
      await tester.pumpAndSettle();
      return (supervisor, server);
    }

    testWidgets('꺼짐 화면으로 돌아가고 알림은 종료 띠 하나뿐이다', (tester) async {
      final (supervisor, server) = await stopFromShell(tester);
      // 미션: 순찰 종료 사건 → 홈 복귀 출발 사건 → 응답. 상태는 returning 으로 넘어간다.
      supervisor
        ..event('patrol_stopped', {'reason': 'admin', 'return_home': true})
        ..event('return_home_sent', {'location_id': '__home__'})
        ..injectStatus('returning');
      server.last.answer('/vica/mission/patrol_stop',
          {'accepted': true, 'message': '경비를 종료했습니다.'});
      await tester.pump();
      await tester.pump();

      expect(find.byType(PatrolScreen), findsOneWidget);
      expect(find.text('경비가 꺼져 있습니다'), findsOneWidget);
      expect(find.text('경비 시작'), findsOneWidget);
      expect(find.text('순찰 중'), findsNothing);
      // 알림 띠 하나, 팝업 없음 — 홈 복귀 출발은 따로 알리지 않는다.
      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        find.text(_k('경비를 종료했습니다.\n로봇이 홈으로 돌아갑니다.')),
        findsOneWidget,
      );
      expect(find.byType(Dialog), findsNothing);

      // 귀띔(3초)이 지나도 returning 은 순찰 상태가 아니라 꺼짐 그대로다. 종료 띠가 4초 뒤
      // 스스로 내려간 다음에는, 홈에 닿아도 새 알림이 없다.
      // (띠의 4초는 올라오는 움직임이 끝난 뒤부터 셉니다 — 두 번에 나눠 넘깁니다.)
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('경비가 꺼져 있습니다'), findsOneWidget);
      supervisor
        ..event('return_home_succeeded', {'location_id': '__home__'})
        ..injectStatus('idle');
      await tester.pump();
      await tester.pump();
      expect(find.text('경비가 꺼져 있습니다'), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      await _drain(tester);
    });

    testWidgets('다른 화면에서 종료하면 이 화면은 알림 없이 꺼짐으로 바뀐다', (tester) async {
      _size(tester, _phone);
      final (supervisor, server) = await _connected(tester);
      supervisor.injectStatus('patrolling');
      await tester.pumpWidget(_app(const PatrolScreen(), supervisor));
      await tester.pump();
      await _answerRoute(tester, server, 6);
      expect(find.text('순찰 중'), findsOneWidget);

      supervisor
        ..event('patrol_stopped', {'reason': 'admin', 'return_home': true})
        ..event('return_home_sent', {'location_id': '__home__'})
        ..injectStatus('returning');
      await tester.pump();
      await tester.pump();
      expect(find.text('경비가 꺼져 있습니다'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('경보로 멈춤(목업 PatrolPaused)', () {
    testWidgets('침입을 확인한 뒤 — 상태·영상 칸·순찰 재개', (tester) async {
      _size(tester, _phone);
      final (supervisor, server) =
          await _connected(tester, records: _records());
      supervisor
        ..alarm('patrol_intruder', _intruder, '화장실')
        ..event('patrol_acked', {'alarm_id': _intruder})
        ..injectStatus('patrol_alarm');
      final player = _FakePlayer();
      await tester.pumpWidget(
        _app(
          PatrolScreen(clipOpener: (_, __) async => player),
          supervisor,
        ),
      );
      await tester.pump();
      await _answerRoute(tester, server, 6);
      await tester.pump();

      expect(find.text('일시정지 — 침입 감지'), findsOneWidget);
      expect(find.text(_k('침입 감지를 확인했습니다.')), findsOneWidget);
      expect(find.text(_k('02:13:41 · 화장실 · 경보음 꺼짐')), findsOneWidget);
      expect(find.text('영상 저장됨 0:42'), findsOneWidget);
      expect(find.text(_k('02:13:36 ~ 02:14:18')), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '순찰 재개'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '경비 종료'), findsOneWidget);

      // 영상 보기 → 영상 창(목업 PatrolVideo).
      await tester.ensureVisible(find.text('영상 보기'));
      await tester.tap(find.text('영상 보기'));
      await tester.pumpAndSettle();
      final dialog = find.byType(PatrolClipDialog);
      expect(dialog, findsOneWidget);
      Finder inDialog(Finder f) => find.descendant(of: dialog, matching: f);
      expect(inDialog(find.text(_k('침입 감지 · 화장실 · 02:13:41'))), findsOneWidget);
      expect(
          inDialog(find.byKey(const ValueKey('fake_video'))), findsOneWidget);
      expect(inDialog(find.text('0:16')), findsOneWidget);
      expect(inDialog(find.text('감지 0:05')), findsOneWidget);
      expect(inDialog(find.text('마지막 감지 0:32')), findsOneWidget);
      expect(inDialog(find.text('0:42')), findsOneWidget);
      expect(player.calls, ['play']);

      await tester.tap(inDialog(find.text('-10')));
      await tester.pump();
      await tester.tap(inDialog(find.text('+10')));
      await tester.tap(inDialog(find.text('+10')));
      await tester.tap(inDialog(find.text('+10')));
      await tester.tap(inDialog(find.text('+10')));
      await tester.pump();
      // 16 → 6 → 16 → 26 → 36 → 끝(42)에서 멈춘다.
      expect(player.calls.sublist(1),
          ['seek 6', 'seek 16', 'seek 26', 'seek 36', 'seek 42']);
      await tester.tap(inDialog(find.byTooltip('멈춤')));
      await tester.pump();
      expect(player.calls.last, 'pause');
      await tester.tap(inDialog(find.byTooltip('닫기')));
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
      expect(tester.takeException(), isNull);
      await _drain(tester);
    });

    testWidgets('영상이 아직 저장 중이면 녹화 시간을 보인다', (tester) async {
      _size(tester, _phone);
      final (supervisor, server) =
          await _connected(tester, records: _records(clipState: 'recording'));
      var now = DateTime(2026, 11, 14, 2, 13, 41);
      supervisor
        ..patrolNow = (() => now)
        ..alarm('patrol_intruder', _intruder, '화장실')
        ..event('patrol_acked', {'alarm_id': _intruder})
        ..injectStatus('patrol_alarm');
      now = now.add(const Duration(seconds: 13));
      await tester.pumpWidget(_app(const PatrolScreen(), supervisor));
      await tester.pump();
      await _answerRoute(tester, server, 6);
      await tester.pump();

      // 5초 전부터 담으므로 13초 뒤에는 0:18 이다(목업 PatrolIntruder 의 값).
      expect(find.text('영상 녹화 중 0:18'), findsOneWidget);
      expect(find.text('영상 보기'), findsNothing);
      now = now.add(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('영상 녹화 중 0:20'), findsOneWidget);
      await _drain(tester);
    });

    testWidgets('불 켜짐은 영상이 아니라 사진 한 장이다', (tester) async {
      _size(tester, _phone);
      final (supervisor, server) = await _connected(tester);
      supervisor
        ..alarm(
            'patrol_light', _light, '407호', {'photo': '20261114_005207.jpg'})
        ..event('patrol_acked', {'alarm_id': _light})
        ..injectStatus('patrol_light');
      await tester.pumpWidget(_app(const PatrolScreen(), supervisor));
      await tester.pump();
      await _answerRoute(tester, server, 6);

      expect(find.text('일시정지 — 불 켜짐'), findsOneWidget);
      expect(find.text(_k('불 켜짐을 확인했습니다.')), findsOneWidget);
      expect(find.text(_k('00:52:07 · 407호 · 경보음 꺼짐')), findsOneWidget);
      expect(find.textContaining('영상'), findsNothing);

      final photo = find.byKey(const ValueKey('patrol_photo'));
      await tester.ensureVisible(photo);
      await tester.tap(photo);
      await tester.pumpAndSettle();
      expect(find.text(_k('불 켜짐 · 407호 · 00:52:07')), findsOneWidget);
      await tester.tap(find.byTooltip('닫기'));
      await tester.pumpAndSettle();
    });

    testWidgets('카메라 끊김은 음성이 없어 경보음 꺼짐이 붙지 않는다', (tester) async {
      _size(tester, _phone);
      final (supervisor, server) = await _connected(tester);
      supervisor
        ..alarm('patrol_camera_lost', _camera, '작업실')
        ..event('patrol_acked', {'alarm_id': _camera})
        ..injectStatus('patrol_alarm');
      await tester.pumpWidget(_app(const PatrolScreen(), supervisor));
      await tester.pump();
      await _answerRoute(tester, server, 6);

      expect(find.text('일시정지 — 카메라 끊김'), findsOneWidget);
      expect(find.text(_k('카메라 끊김을 확인했습니다.')), findsOneWidget);
      expect(find.text(_k('03:02:55 · 작업실')), findsOneWidget);
      expect(find.textContaining('경보음'), findsNothing);
    });

    testWidgets('재개가 거절되면(카메라가 아직 끊김) 사유를 알리고 그대로 선다', (tester) async {
      _size(tester, _phone);
      final (supervisor, server) = await _connected(tester);
      supervisor
        ..alarm('patrol_camera_lost', _camera, '작업실')
        ..event('patrol_acked', {'alarm_id': _camera})
        ..injectStatus('patrol_alarm');
      await tester.pumpWidget(_app(const PatrolScreen(), supervisor));
      await tester.pump();
      await _answerRoute(tester, server, 6);

      await tester.ensureVisible(find.text('순찰 재개'));
      await tester.tap(find.text('순찰 재개'));
      await tester.pump();
      server.last.answer('/vica/mission/resume_navigation',
          {'accepted': false, 'message': '카메라가 준비되지 않았습니다.'});
      await tester.pump();
      await tester.pump();
      expect(find.text(_k('카메라가 준비되지 않았습니다.')), findsOneWidget);
      expect(find.text('일시정지 — 카메라 끊김'), findsOneWidget);
    });
  });

  group('경로 편집(목업 PatrolRouteEdit·Removed·DeleteConfirm)', () {
    Future<(_Supervisor, FakeRosServer)> editor(WidgetTester tester) async {
      _size(tester, _phone);
      final (supervisor, server) = await _connected(tester);
      await tester.pumpWidget(_app(const PatrolScreen(), supervisor));
      await tester.pump();
      await _answerRoute(tester, server, 6);
      await tester.tap(find.text('경로 편집'));
      await tester.pump();
      expect(find.byType(PatrolRouteEditor), findsOneWidget);
      return (supervisor, server);
    }

    testWidgets('목업의 글자와 여섯 줄', (tester) async {
      await editor(tester);

      expect(find.text('순찰 경로 편집'), findsOneWidget);
      expect(find.text('경로 삭제'), findsOneWidget);
      expect(find.byTooltip('뒤로'), findsOneWidget);
      // 안내 글의 '✕' 자리에는 빼기 버튼과 같은 그림이 들어 있다(앱 글꼴에 그 글자가 없다).
      final hintFinder = find.byKey(const ValueKey('patrol_route_hint'));
      final hint = tester.widget<Text>(hintFinder);
      expect(
        hint.textSpan!.toPlainText().replaceAll('⁠', '').replaceAll('￼', '✕'),
        '장소를 누르면 맨 뒤에 번호가 붙습니다.\n'
        '번호가 붙은 장소를 다시 누르거나 ✕를 누르면 빠지고, 뒤 번호가 하나씩 당겨집니다.',
      );
      expect(
        find.descendant(of: hintFinder, matching: find.byIcon(Icons.close)),
        findsOneWidget,
      );
      expect(find.text('순찰 순서 · 장소 6곳'), findsOneWidget);
      expect(find.text('마지막 다음엔 1번으로'), findsOneWidget);
      for (final (id, name, _, _) in _places.take(6)) {
        final row = find.byKey(ValueKey('patrol_order_$id'));
        expect(find.descendant(of: row, matching: find.text(name)),
            findsOneWidget);
        expect(find.byTooltip('$name 빼기'), findsOneWidget);
      }
      expect(find.widgetWithText(FilledButton, '저장'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '취소'), findsOneWidget);
      // 바뀐 것이 없으면 저장은 잠겨 있고 '저장하지 않은 변경' 줄도 없다.
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '저장'))
            .onPressed,
        isNull,
      );
      expect(find.text('저장하지 않은 변경이 있습니다.'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('중간 장소를 빼면 뒤 번호가 당겨지고 그렇게 알린다', (tester) async {
      await editor(tester);
      final remove = find.byTooltip('작업실 빼기');
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await tester.pump();

      expect(find.text('순찰 순서 · 장소 5곳'), findsOneWidget);
      expect(find.byKey(const ValueKey('patrol_order_p3')), findsNothing);
      for (final note in ['4 → 3', '5 → 4', '6 → 5']) {
        expect(find.text(note), findsOneWidget, reason: note);
      }
      expect(find.text('저장하지 않은 변경이 있습니다.'), findsOneWidget);
      expect(
        find.text(_k('작업실을 뺐습니다.\n뒤 번호를 하나씩 당겼습니다.')),
        findsOneWidget,
      );
    });

    testWidgets('지도의 번호를 누르면 빠지고, 번호 없는 장소를 누르면 맨 뒤에 붙는다', (tester) async {
      await editor(tester);
      final canvas = tester.widget<MapCanvas>(find.byType(MapCanvas));
      // 번호 없는 장소(휴게실)의 점을 누른 것과 같다.
      final lounge = canvas.locations.firstWhere((l) => l.name == '휴게실');
      canvas.onSelectLocation!(lounge);
      await tester.pump();
      expect(find.text('순찰 순서 · 장소 7곳'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('patrol_order_p7')),
          matching: find.text('7'),
        ),
        findsOneWidget,
      );

      // 번호가 붙은 장소(407호, 6번)의 번호 원을 누른다.
      await tester.tap(find.byKey(const ValueKey('patrol_badge_p6')),
          warnIfMissed: false);
      await tester.pump();
      expect(find.text('순찰 순서 · 장소 6곳'), findsOneWidget);
      expect(find.byKey(const ValueKey('patrol_order_p6')), findsNothing);
      expect(find.text('7 → 6'), findsOneWidget);
    });

    testWidgets('저장 — 누른 순서를 보내고 받아들여지면 꺼짐 화면으로 돌아간다', (tester) async {
      final (_, server) = await editor(tester);
      final remove = find.byTooltip('작업실 빼기');
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await tester.pump();
      await tester.ensureVisible(find.text('저장'));
      await tester.tap(find.text('저장'));
      await tester.pump();

      final call = _calls(server, '/vica/patrol/route/save').single;
      expect(call['args'], {
        'map_id': 'm1',
        'destination_ids': ['p1', 'p2', 'p4', 'p5', 'p6'],
      });
      server.last.answer('/vica/patrol/route/save',
          {'accepted': true, 'reason': 'ok', 'message': ''});
      await tester.pump();
      await tester.pump();

      expect(find.byType(PatrolRouteEditor), findsNothing);
      expect(find.text(_k('순찰 경로를 저장했습니다.')), findsOneWidget);
      expect(find.text('장소 5곳'), findsOneWidget);
      expect(
          find.text(_k('입구 → 안내소 → 화장실 → 방2 → 407호 → 다시 입구')), findsOneWidget);
    });

    testWidgets('로봇이 거절하면 그 한 줄을 보이고 편집에 머문다', (tester) async {
      final (_, server) = await editor(tester);
      for (final name in ['안내소', '작업실', '화장실', '방2', '407호']) {
        final remove = find.byTooltip('$name 빼기');
        await tester.ensureVisible(remove);
        await tester.tap(remove);
        await tester.pump();
      }
      await tester.ensureVisible(find.text('저장'));
      await tester.tap(find.text('저장'));
      await tester.pump();
      server.last.answer('/vica/patrol/route/save', {
        'accepted': false,
        'reason': 'too_few',
        'message': '순찰 경로는 장소 2곳 이상이어야 합니다.',
      });
      await tester.pump();
      await tester.pump();
      expect(find.text(_k('순찰 경로는 장소 2곳 이상이어야 합니다.')), findsOneWidget);
      expect(find.byType(PatrolRouteEditor), findsOneWidget);
    });

    testWidgets('취소·뒤로는 묻지 않고 버린다', (tester) async {
      final (_, server) = await editor(tester);
      final remove = find.byTooltip('입구 빼기');
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await tester.pump();
      await tester.ensureVisible(find.text('취소'));
      await tester.tap(find.text('취소'));
      await tester.pump();
      expect(find.byType(PatrolRouteEditor), findsNothing);
      expect(find.text('장소 6곳'), findsOneWidget);
      expect(_calls(server, '/vica/patrol/route/save'), isEmpty);
    });

    testWidgets('경로 삭제는 한 번 묻고 빈 순서를 저장한다', (tester) async {
      final (_, server) = await editor(tester);
      await tester.tap(find.text('경로 삭제'));
      await tester.pumpAndSettle();

      expect(find.text('순찰 경로를 지울까요?'), findsOneWidget);
      expect(
        find.text(_k('정해 둔 순서가 모두 지워집니다.\n저장된 장소는 지워지지 않습니다.')),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, '지우기'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '지우기'));
      await tester.pumpAndSettle();

      final call = _calls(server, '/vica/patrol/route/save').single;
      expect((call['args'] as Map)['destination_ids'], isEmpty);
      server.last.answer('/vica/patrol/route/save',
          {'accepted': true, 'reason': 'ok', 'message': ''});
      await tester.pump();
      await tester.pump();
      expect(find.byType(PatrolRouteEditor), findsNothing);
      expect(find.text('장소 0곳'), findsOneWidget);
    });
  });

  group('경보 팝업(목업 PatrolIntruder·Sound·Light·DeviceFault)', () {
    Future<SupervisorProvider> pumpShell(
      WidgetTester tester, {
      Size size = _wide,
    }) async {
      _size(tester, size);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AuthProvider()),
            ChangeNotifierProvider(create: (_) => SettingsProvider()),
            ChangeNotifierProvider(create: (_) => UiPreferencesProvider()),
            ChangeNotifierProvider<SupervisorProvider>(
              create: (_) => _Supervisor(records: _records()),
            ),
            ChangeNotifierProvider(create: (_) => AppModeProvider()),
          ],
          child: MaterialApp(theme: vicaTheme(), home: const SupervisorShell()),
        ),
      );
      await tester.pump();
      return tester
          .element(find.byType(SupervisorShell))
          .read<SupervisorProvider>();
    }

    final dialog = find.byType(PatrolAlarmDialog);
    Finder inDialog(Finder matching) =>
        find.descendant(of: dialog, matching: matching);

    testWidgets('침입 — 대시보드를 보고 있어도 뜬다', (tester) async {
      final supervisor = await pumpShell(tester) as _Supervisor;
      var now = DateTime(2026, 11, 14, 2, 13, 41);
      supervisor.patrolNow = () => now;
      supervisor.alarm('patrol_intruder', _intruder, '화장실');
      now = now.add(const Duration(seconds: 13));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, '대시보드'), findsOneWidget);
      expect(dialog, findsOneWidget);
      expect(inDialog(find.text('침입 감지')), findsOneWidget);
      expect(
        inDialog(find.text(_k('화장실에 사람이 감지되었습니다.\n확인해 주세요.'))),
        findsOneWidget,
      );
      for (final text in ['구역', '화장실', '시각', '02:13:41', '종류', '사람']) {
        expect(inDialog(find.text(text)), findsOneWidget, reason: text);
      }
      expect(inDialog(find.text('영상 녹화 중 0:18')), findsOneWidget);
      expect(
        inDialog(find.widgetWithText(FilledButton, '확인 (경보음 끄기)')),
        findsOneWidget,
      );
      // 로봇이 사람까지의 거리를 보내지 않아 '감지 위치' 칸은 없다.
      expect(inDialog(find.text('감지 위치')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('같은 경보가 10초마다 다시 와도 팝업은 하나다', (tester) async {
      final supervisor = await pumpShell(tester) as _Supervisor;
      supervisor.alarm('patrol_intruder', _intruder, '화장실');
      await tester.pumpAndSettle();
      supervisor.alarm('patrol_intruder', _intruder, '화장실',
          {'resend': true, 'timestamp': '2026-11-14T02:13:51'});
      await tester.pumpAndSettle();
      supervisor.alarm('patrol_intruder', _intruder, '화장실',
          {'resend': true, 'timestamp': '2026-11-14T02:14:01'});
      await tester.pumpAndSettle();
      expect(dialog, findsOneWidget);
    });

    testWidgets('바깥을 눌러서는 닫히지 않는다', (tester) async {
      final supervisor = await pumpShell(tester) as _Supervisor;
      supervisor.alarm('patrol_intruder', _intruder, '화장실');
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(dialog, findsOneWidget);
    });

    testWidgets('다른 화면에서 확인하면 저절로 닫히고 경비 탭은 멈춤 화면이다', (tester) async {
      final supervisor = await pumpShell(tester) as _Supervisor;
      supervisor
        ..injectStatus('patrol_alarm')
        ..alarm('patrol_intruder', _intruder, '화장실');
      await tester.pumpAndSettle();
      expect(dialog, findsOneWidget);
      supervisor.event('patrol_acked', {'alarm_id': _intruder});
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);

      final sidebar = find.byKey(const ValueKey('desktop_sidebar'));
      await tester.tap(find.descendant(of: sidebar, matching: find.text('경비')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, '경비'), findsOneWidget);
      expect(find.text('일시정지 — 침입 감지'), findsOneWidget);
      expect(find.text(_k('침입 감지를 확인했습니다.')), findsOneWidget);
    });

    testWidgets('순찰을 재개하면 팝업도 닫힌다', (tester) async {
      final supervisor = await pumpShell(tester) as _Supervisor;
      supervisor.alarm('patrol_sound', _sound, '방2', {'level_db': 70.2});
      await tester.pumpAndSettle();
      expect(dialog, findsOneWidget);
      supervisor.event('patrol_resumed');
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
    });

    testWidgets('큰 소리 — 크기를 종류 칸에 적는다', (tester) async {
      final supervisor = await pumpShell(tester) as _Supervisor;
      supervisor.alarm('patrol_sound', _sound, '방2', {'level_db': 70.2});
      await tester.pumpAndSettle();

      expect(inDialog(find.text('큰 소리 감지')), findsOneWidget);
      expect(
        inDialog(find.text(_k('방2에서 큰 소리 감지되었습니다.\n확인해 주세요.'))),
        findsOneWidget,
      );
      expect(inDialog(find.text('방2')), findsOneWidget);
      expect(inDialog(find.text('01:40:12')), findsOneWidget);
      expect(inDialog(find.text('큰 소리 (70 dB)')), findsOneWidget);
      expect(inDialog(find.widgetWithText(FilledButton, '확인 (경보음 끄기)')),
          findsOneWidget);
      // 로봇이 소리 방향을 보내지 않아 '감지 위치' 칸은 없다.
      expect(inDialog(find.text('감지 위치')), findsNothing);
    });

    testWidgets('불 켜짐 — 영상 띠가 없다', (tester) async {
      final supervisor = await pumpShell(tester) as _Supervisor;
      supervisor.alarm(
          'patrol_light', _light, '407호', {'photo': '20261114_005207.jpg'});
      await tester.pumpAndSettle();

      expect(inDialog(find.text('불 켜짐 확인 요청')), findsOneWidget);
      expect(
        inDialog(find.text(_k('407호에 불이 켜져 있습니다.\n확인해 주세요.'))),
        findsOneWidget,
      );
      for (final text in [
        '구역',
        '407호',
        '감지 위치',
        '로봇이 있는 곳',
        '시각',
        '00:52:07',
        '종류',
        '불 켜짐',
      ]) {
        expect(inDialog(find.text(text)), findsOneWidget, reason: text);
      }
      expect(inDialog(find.textContaining('녹화')), findsNothing);
      expect(inDialog(find.widgetWithText(FilledButton, '확인 (경보음 끄기)')),
          findsOneWidget);
    });

    testWidgets('카메라 끊김 — 본문 네 줄', (tester) async {
      final supervisor = await pumpShell(tester) as _Supervisor;
      supervisor.alarm('patrol_camera_lost', _camera, '작업실');
      await tester.pumpAndSettle();

      expect(inDialog(find.text('카메라 끊김')), findsNWidgets(2)); // 제목·종류
      expect(
        inDialog(find.text(_k(
          '카메라 신호가 끊겼습니다.\n'
          '사람 감지와 영상 저장을 할 수 없습니다.\n'
          '로봇은 대기하고 있습니다.\n'
          '확인해 주세요.',
        ))),
        findsOneWidget,
      );
      expect(inDialog(find.text('작업실')), findsOneWidget);
      expect(inDialog(find.text('03:02:55')), findsOneWidget);
      expect(inDialog(find.textContaining('녹화')), findsNothing);
    });

    testWidgets('연결이 없을 때 확인을 누르면 팝업은 남고 그렇게 알린다', (tester) async {
      final supervisor = await pumpShell(tester) as _Supervisor;
      supervisor.alarm('patrol_light', _light, '407호');
      await tester.pumpAndSettle();
      await tester
          .tap(inDialog(find.widgetWithText(FilledButton, '확인 (경보음 끄기)')));
      await tester.pumpAndSettle();
      expect(dialog, findsOneWidget);
      expect(find.text(_k('ROS Bridge에 연결되지 않았습니다.')), findsOneWidget);
    });

    testWidgets('확인을 누르면 patrol_ack 을 부르고 닫힌다', (tester) async {
      _size(tester, _phone);
      final (supervisor, server) = await _connected(tester);
      supervisor.injectStatus('patrol_light');
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AuthProvider()),
            ChangeNotifierProvider(create: (_) => SettingsProvider()),
            ChangeNotifierProvider(create: (_) => UiPreferencesProvider()),
            ChangeNotifierProvider<SupervisorProvider>.value(value: supervisor),
            ChangeNotifierProvider(create: (_) => AppModeProvider()),
          ],
          child: MaterialApp(theme: vicaTheme(), home: const SupervisorShell()),
        ),
      );
      await tester.pump();
      supervisor.alarm('patrol_light', _light, '407호');
      await tester.pumpAndSettle();
      expect(dialog, findsOneWidget);

      await tester
          .tap(inDialog(find.widgetWithText(FilledButton, '확인 (경보음 끄기)')));
      await tester.pump();
      final call = _calls(server, '/vica/mission/patrol_ack').single;
      // request_id 는 그 팝업의 alarm_id — 미션이 그 경보만 확인한다.
      expect((call['args'] as Map)['request_id'], _light);
      server.last.answer('/vica/mission/patrol_ack',
          {'accepted': true, 'message': '경보를 확인했습니다.'});
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      // 로봇은 그대로 서 있다 — 경보는 재개까지 남는다.
      expect(supervisor.patrolAlarm!.acked, isTrue);
    });

    testWidgets('미션이 확인을 거절하면 그 문구를 그대로 알리고 팝업은 남는다', (tester) async {
      _size(tester, _phone);
      final (supervisor, server) = await _connected(tester);
      supervisor
        ..injectStatus('patrol_light')
        ..alarm('patrol_light', _light, '407호');
      await tester.pumpWidget(
        _app(const PatrolAlarmDialog(alarmId: _light), supervisor),
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '확인 (경보음 끄기)'));
      await tester.pump();
      server.last.answer('/vica/mission/patrol_ack',
          {'accepted': false, 'message': '지금 경보와 다른 경보입니다.'});
      await tester.pump();
      await tester.pump();
      expect(find.text(_k('지금 경보와 다른 경보입니다.')), findsOneWidget);
      expect(find.text('불 켜짐 확인 요청'), findsOneWidget);
      expect(supervisor.patrolAlarm!.acked, isFalse);
    });

    // 녹화 띠('영상 녹화 중 0:18')의 초를 넘기려고 1초마다 다시 그립니다. 띠가 없는 팝업은
    // 다시 그릴 것이 없으므로 그 박자를 돌리지 않습니다(자원).
    group('1초 박자', () {
      /// [seconds] 초 동안 그려진 화면 장 수. 1초 박자가 돌면 초마다 한 장씩 그려집니다.
      Future<int> framesIn(WidgetTester tester, int seconds) async {
        var frames = 0;
        var counting = true;
        tester.binding.addPersistentFrameCallback((_) {
          if (counting) {
            frames += 1;
          }
        });
        for (var i = 0; i < seconds; i++) {
          await tester.pump(const Duration(seconds: 1));
        }
        counting = false;
        return frames;
      }

      Future<_Supervisor> popup(
        WidgetTester tester,
        String event,
        String id,
        String place, {
        String? records,
      }) async {
        _size(tester, _phone);
        final supervisor = _Supervisor(records: records);
        addTearDown(supervisor.dispose);
        if (records != null) {
          await supervisor.refreshPatrolRecords(const AppSettings());
        }
        supervisor.alarm(event, id, place);
        await tester.pumpWidget(
          _app(PatrolAlarmDialog(alarmId: id), supervisor),
        );
        await tester.pumpAndSettle();
        return supervisor;
      }

      testWidgets('불 켜짐 팝업은 돌리지 않는다', (tester) async {
        await popup(tester, 'patrol_light', _light, '407호');
        expect(find.textContaining('녹화'), findsNothing);
        expect(await framesIn(tester, 5), 0);
      });

      testWidgets('카메라 끊김 팝업은 돌리지 않는다', (tester) async {
        await popup(tester, 'patrol_camera_lost', _camera, '작업실');
        expect(await framesIn(tester, 5), 0);
      });

      testWidgets('영상이 이미 저장된 침입 팝업은 돌리지 않는다', (tester) async {
        await popup(tester, 'patrol_intruder', _intruder, '화장실',
            records: _records());
        expect(find.textContaining('녹화'), findsNothing);
        expect(await framesIn(tester, 5), 0);
      });

      testWidgets('녹화 중인 침입 팝업은 초마다 그리고, 녹화가 끝나면 멈춘다', (tester) async {
        _size(tester, _phone);
        final supervisor = _Supervisor();
        addTearDown(supervisor.dispose);
        var now = DateTime(2026, 11, 14, 2, 13, 41);
        supervisor
          ..patrolNow = (() => now)
          ..alarm('patrol_intruder', _intruder, '화장실');
        await tester.pumpWidget(
          _app(const PatrolAlarmDialog(alarmId: _intruder), supervisor),
        );
        await tester.pumpAndSettle();
        expect(find.text('영상 녹화 중 0:05'), findsOneWidget);
        expect(await framesIn(tester, 3), 3);

        // 가장 긴 영상(60초)을 넘기면 띠가 내려가고 박자도 멈춘다.
        now = now.add(const Duration(seconds: 70));
        await tester.pump(const Duration(seconds: 1));
        expect(find.textContaining('녹화'), findsNothing);
        // 띠가 빠지며 팝업 높이가 바뀐 것을 마저 그린 뒤로는 더 그리지 않는다.
        await tester.pumpAndSettle();
        expect(await framesIn(tester, 5), 0);
      });
    });

    testWidgets('순찰이 스스로 끝나면 한 줄로 알린다', (tester) async {
      final supervisor = await pumpShell(tester) as _Supervisor;
      supervisor.event('patrol_stopped', {'reason': 'nav_failed'});
      await tester.pump();
      await tester.pump();
      expect(
        find.text(_k('순찰 지점으로 가지 못해 경비를 종료했습니다.')),
        findsOneWidget,
      );
    });
  });

  group('아래 탭과 경비 기록(목업 PatrolHome·PatrolLog)', () {
    Future<_Supervisor> pumpPhoneShell(WidgetTester tester) async {
      _size(tester, _phone);
      final supervisor = _Supervisor(records: _records());
      addTearDown(supervisor.dispose);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AuthProvider()),
            ChangeNotifierProvider(create: (_) => SettingsProvider()),
            ChangeNotifierProvider(create: (_) => UiPreferencesProvider()),
            ChangeNotifierProvider<SupervisorProvider>.value(value: supervisor),
            ChangeNotifierProvider(create: (_) => AppModeProvider()),
          ],
          child: MaterialApp(theme: vicaTheme(), home: const SupervisorShell()),
        ),
      );
      await tester.pump();
      return supervisor;
    }

    testWidgets('아래 탭은 여섯 칸이고 경비가 더보기 앞이다', (tester) async {
      await pumpPhoneShell(tester);
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(
        bar.destinations.map((d) => (d as NavigationDestination).label),
        ['대시보드', '지도 설정', '원격 주행', '물류 배송', '경비', '더보기'],
      );
      await tester.tap(find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('경비'),
      ));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, '경비'), findsOneWidget);
      expect(find.byType(PatrolScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('경비 기록 N건 → 알림 및 로그의 경비 기록 분류', (tester) async {
      await pumpPhoneShell(tester);
      await tester.tap(find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('경비'),
      ));
      await tester.pumpAndSettle();
      final link = find.text('경비 기록 4건');
      await tester.ensureVisible(link);
      await tester.tap(link);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, '알림 및 로그'), findsOneWidget);
      final chip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, '경비 기록'),
      );
      expect(chip.selected, isTrue);
      expect(find.byType(PatrolRecordTile), findsNWidgets(4));

      // 다른 화면에 갔다가 메뉴로 다시 들어오면 지금처럼 '전체'다.
      await tester.tap(find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('대시보드'),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('더보기'),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('알림 및 로그'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '전체'))
            .selected,
        isTrue,
      );
    });

    testWidgets('경비 기록 네 줄 — 영상은 길이 버튼, 불 켜짐은 사진 버튼', (tester) async {
      _size(tester, _phone);
      final supervisor = _Supervisor(records: _records());
      addTearDown(supervisor.dispose);
      final player = _FakePlayer();
      await tester.pumpWidget(
        _app(
          LogsScreen(
            initialFilter: LogFilter.patrol,
            clipOpener: (_, __) async => player,
          ),
          supervisor,
        ),
      );
      await tester.pumpAndSettle();

      // 분류 칩 여섯 개, 맨 끝이 경비 기록.
      expect(
        tester.widgetList<ChoiceChip>(find.byType(ChoiceChip)).map(
              (chip) => (chip.label as Text).data,
            ),
        ['전체', '긴급 정지', '좌표 전송', '연결 상태', '물류 배송', '경비 기록'],
      );
      for (final text in [
        '침입 감지 · 사람',
        '11-14 02:13:41 · 화장실',
        '0:42',
        '큰 소리 · 70 dB',
        '11-14 01:40:12 · 방2',
        '0:15',
        '불 켜짐',
        '11-14 00:52:07 · 407호',
        '카메라 끊김',
        '11-13 03:02:55 · 작업실',
      ]) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      // 영상 버튼 둘, 사진 버튼 하나, 카메라 끊김 줄에는 버튼이 없다.
      expect(find.byIcon(Icons.play_arrow), findsNWidgets(2));
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
      // 로봇의 기록이라 지우는 버튼은 잠겨 있다.
      expect(
        tester
            .widget<IconButton>(
                find.widgetWithIcon(IconButton, Icons.delete_sweep))
            .onPressed,
        isNull,
      );

      await tester.tap(find.text('0:42'));
      await tester.pumpAndSettle();
      expect(find.byType(PatrolClipDialog), findsOneWidget);
      expect(find.text(_k('침입 감지 · 화장실 · 02:13:41')), findsOneWidget);
      await tester.tap(find.byTooltip('닫기'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.image_outlined));
      await tester.pumpAndSettle();
      expect(find.text(_k('불 켜짐 · 407호 · 00:52:07')), findsOneWidget);
      await tester.tap(find.byTooltip('닫기'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('지도 서버에 닿지 못하면 그렇게 적는다', (tester) async {
      _size(tester, _phone);
      final supervisor = _Supervisor();
      addTearDown(supervisor.dispose);
      await tester.pumpWidget(
        _app(const LogsScreen(initialFilter: LogFilter.patrol), supervisor),
      );
      await tester.pumpAndSettle();
      expect(find.text('경비 기록을 불러오지 못했습니다.'), findsOneWidget);
    });

    testWidgets('기록이 없으면 지금의 빈 목록 글자다', (tester) async {
      _size(tester, _phone);
      final supervisor = _Supervisor(records: '[]');
      addTearDown(supervisor.dispose);
      await tester.pumpWidget(
        _app(const LogsScreen(initialFilter: LogFilter.patrol), supervisor),
      );
      await tester.pumpAndSettle();
      expect(find.text('표시할 로그가 없습니다.'), findsOneWidget);
    });
  });

  group('영상 창(목업 PatrolVideo)', () {
    final record = PatrolRecord.fromJson({
      'alarm_id': _intruder,
      'kind': 'intruder',
      'time': '2026-11-14T02:13:41',
      'place': '화장실',
      'clip_id': _intruder,
      'clip_state': 'ready',
      'clip_sec': 42.0,
      'detect_sec': 5.0,
    })!;

    testWidgets('mp4 도 사진도 못 열면 그렇게 적고 조작을 잠근다', (tester) async {
      _size(tester, _phone);
      await tester.pumpWidget(
        MaterialApp(
          theme: vicaTheme(),
          home: PatrolClipDialog(
            record: record,
            baseUrl: 'http://x',
            opener: (_, __) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(_k('영상을 불러오지 못했습니다.')), findsOneWidget);
      final play = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(play.onPressed, isNull);
    });

    testWidgets('사진 넘기기 — 초당 5장으로 넘어가고 끝에서 멈춘다', (tester) async {
      _size(tester, _phone);
      final frames = PatrolFramesPlayer([
        for (var i = 1; i <= 10; i++)
          Uri.parse('http://x/patrol/clips/c/frames/00000$i.jpg'),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          theme: vicaTheme(),
          home: PatrolClipDialog(
            record: record,
            baseUrl: 'http://x',
            opener: (_, __) async => frames,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(frames.playing, isTrue);
      expect(frames.duration, const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 1000));
      expect(frames.index, 5);
      expect(find.text('0:01'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1000));
      expect(frames.index, 9);
      expect(frames.playing, isFalse);
      // 끝에서 다시 누르면 처음부터.
      await tester.tap(find.byTooltip('재생'));
      await tester.pump();
      expect(frames.index, 0);
      expect(frames.playing, isTrue);
      await tester.tap(find.byTooltip('멈춤'));
      await tester.pump();
      expect(frames.playing, isFalse);
    });

    testWidgets('사진 넘기기 — 서버가 알려 준 초당 장수로 넘긴다', (tester) async {
      _size(tester, _phone);
      // 초당 2.5장이면 10장이 4초다(5 고정이면 2초로 보였다).
      final frames = PatrolFramesPlayer(
        [
          for (var i = 1; i <= 10; i++)
            Uri.parse('http://x/patrol/clips/c/frames/00000$i.jpg'),
        ],
        fps: 2.5,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: vicaTheme(),
          home: PatrolClipDialog(
            record: record,
            baseUrl: 'http://x',
            opener: (_, __) async => frames,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(frames.duration, const Duration(seconds: 4));
      expect(find.text('0:04'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(frames.index, 5);
      expect(frames.position, const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));
      expect(frames.index, 9);
      expect(frames.playing, isFalse);
    });

    test('사진 넘기기 — 소수 속도에서도 길이와 자리 계산이 맞는다', () async {
      // 감지 노드가 실제로 잰 값은 3.41 같은 소수다. 63장 = 18.475초.
      final frames = PatrolFramesPlayer(
        [for (var i = 1; i <= 63; i++) Uri.parse('http://x/$i.jpg')],
        fps: 3.41,
      );
      addTearDown(frames.dispose);
      expect(frames.duration.inMilliseconds, closeTo(18475, 1));
      for (final index in [0, 1, 7, 30, 62]) {
        await frames.seekTo(
          Duration(microseconds: (index * 1000000 / 3.41).round()),
        );
        expect(frames.index, index);
        // 그 자리의 시각으로 다시 옮겨도 같은 장이다.
        await frames.seekTo(frames.position);
        expect(frames.index, index);
      }
      // 끝을 넘겨도 마지막 장에서 멈춘다.
      await frames.seekTo(const Duration(minutes: 1));
      expect(frames.index, 62);
    });

    test('사진 넘기기 — 쓸 수 없는 속도는 5로 본다', () {
      for (final bad in [0.0, -1.0, double.nan, double.infinity]) {
        final frames =
            PatrolFramesPlayer([Uri.parse('http://x/1.jpg')], fps: bad);
        expect(frames.fps, 5.0, reason: '$bad');
        frames.dispose();
      }
    });
  });

  group('폭과 글자 배율을 바꿔도 넘치지 않는다', () {
    const widths = <double>[320, 360, 390, 600, 900, 1440];
    const scales = <double>[1.0, 1.3];

    Future<void> check(
      WidgetTester tester,
      String name,
      Future<void> Function(_Supervisor supervisor) prepare,
      Widget Function() screen, {
      Future<void> Function(WidgetTester tester)? after,
    }) async {
      for (final scale in scales) {
        for (final width in widths) {
          final errors = <String>[];
          final previous = FlutterError.onError;
          FlutterError.onError = (details) {
            final message = details.exceptionAsString();
            if (!message.contains('NetworkImage') &&
                !message.contains('HTTP request failed')) {
              errors.add(message.split('\n').first);
            }
          };
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 900);
          final supervisor = _Supervisor(records: _records());
          supervisor
            ..injectMap()
            ..injectPlaces()
            ..injectStatus('idle')
            ..injectRoute(6);
          await prepare(supervisor);
          await tester.pumpWidget(_app(screen(), supervisor, scale: scale));
          await tester.pump();
          await tester.pump();
          await after?.call(tester);
          FlutterError.onError = previous;
          expect(errors, isEmpty,
              reason: '$name 화면이 폭 $width, 글자 배율 $scale 에서 넘쳤습니다.');
          // 다음 폭을 새 화면으로 그리게 비웁니다(열린 팝업도 닫힙니다).
          await tester.pumpWidget(const SizedBox.shrink());
          supervisor.dispose();
        }
      }
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    }

    testWidgets('꺼짐', (tester) async {
      await check(tester, '꺼짐', (s) async {}, () => const PatrolScreen());
    });

    testWidgets('순찰 중', (tester) async {
      await check(tester, '순찰 중', (s) async {
        s
          ..event('patrol_started', {
            'timestamp': '2026-11-14T22:04:10',
            'route': [for (final p in _places.take(6)) p.$2],
          })
          ..event('patrol_waypoint',
              {'name': '화장실', 'index': 3, 'lap': 3, 'count': 6})
          ..injectStatus('patrolling');
      }, () => const PatrolScreen());
    });

    testWidgets('경보로 멈춤(영상 칸)', (tester) async {
      await check(tester, '멈춤', (s) async {
        s
          ..alarm('patrol_intruder', _intruder, '화장실')
          ..event('patrol_acked', {'alarm_id': _intruder})
          ..injectStatus('patrol_alarm');
      }, () => const PatrolScreen());
    });

    testWidgets('경로 편집(번호가 당겨진 줄)', (tester) async {
      await check(
        tester,
        '경로 편집',
        (s) async {},
        () => const PatrolScreen(),
        after: (tester) async {
          await tester.tap(find.text('경로 편집'));
          await tester.pump();
          final remove = find.byTooltip('작업실 빼기');
          await tester.ensureVisible(remove);
          await tester.tap(remove);
          await tester.pump();
        },
      );
    });

    testWidgets('경비 기록', (tester) async {
      await check(
        tester,
        '경비 기록',
        (s) async {},
        () => const LogsScreen(initialFilter: LogFilter.patrol),
      );
    });

    for (final (name, event, id, place, extra) in [
      ('침입 팝업', 'patrol_intruder', _intruder, '화장실', <String, Object?>{}),
      ('큰 소리 팝업', 'patrol_sound', _sound, '방2', {'level_db': 70.2}),
      ('불 켜짐 팝업', 'patrol_light', _light, '407호', <String, Object?>{}),
      ('카메라 끊김 팝업', 'patrol_camera_lost', _camera, '작업실', <String, Object?>{}),
    ]) {
      testWidgets(name, (tester) async {
        await check(
          tester,
          name,
          (s) async => s.alarm(event, id, place, extra),
          () => PatrolAlarmDialog(alarmId: id),
        );
      });
    }

    testWidgets('영상 창', (tester) async {
      final record = PatrolRecord.fromJson({
        'alarm_id': _intruder,
        'kind': 'intruder',
        'time': '2026-11-14T02:13:41',
        'place': '화장실',
        'clip_id': _intruder,
        'clip_state': 'ready',
        'clip_sec': 42.0,
        'detect_sec': 5.0,
      })!;
      await check(
        tester,
        '영상 창',
        (s) async {},
        () => PatrolClipDialog(
          record: record,
          baseUrl: 'http://x',
          opener: (_, __) async => _FakePlayer(),
        ),
      );
    });
  });
}
