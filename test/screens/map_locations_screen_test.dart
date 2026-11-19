// 원격 주행 화면에서 초기 위치를 잡을 수 있는 조건을 고정합니다.
//
// 초기 위치 확정은 AMCL 이 자기 위치를 다시 믿는 순간입니다. 아무 때나 열려
// 있으면 안 됩니다. 특히 **주행 중에 바꾸면** Nav2 가 따라가던 경로를 엉뚱한
// 곳에서 이어가려 합니다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vica_supervisor/core/app_settings.dart';
import 'package:vica_supervisor/models/mode_status.dart';
import 'package:vica_supervisor/models/stack_status.dart';
import 'package:vica_supervisor/providers/app_mode_provider.dart';
import 'package:vica_supervisor/providers/settings_provider.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';
import 'package:vica_supervisor/screens/map_locations_screen.dart';
import 'package:vica_supervisor/widgets/drive_map_canvas.dart';
import 'package:vica_supervisor/widgets/initial_pose_card.dart';
import 'package:vica_supervisor/widgets/vica_ui.dart';

import '../ros/fake_ros_socket.dart';

class _FakeSupervisor extends SupervisorProvider {
  _FakeSupervisor({super.rosChannelConnector});

  int waitCancels = 0;
  int approachCancels = 0;
  int driveCancels = 0;

  @override
  Future<String> cancelWait(AppSettings settings) async {
    waitCancels += 1;
    return '대기를 취소했습니다.';
  }

  @override
  Future<String> cancelApproach(AppSettings settings) async {
    approachCancels += 1;
    return '접근을 취소했습니다.';
  }

  @override
  Future<String> cancelDestination(AppSettings settings) async {
    driveCancels += 1;
    return '주행을 취소했습니다.';
  }

  void injectMap() => handleMapListForTest({
        'maps': [
          {
            'map_id': 'starlight_1f',
            'map_name': 'starlight_1f',
            'resolution': 0.05,
            'origin_x': 0.0,
            'origin_y': 0.0,
            'width': 200,
            'height': 200,
          },
        ],
      });

  void injectRobot({
    String goal = '',
    String waiting = '',
    String dialog = '',
    String place = '',
    int left = -1,
    String last = '',
  }) =>
      handleRobotStatusForTest({
        'robot_id': 'vica_robot_01',
        'robot_name': 'VICA 1호기',
        'status': goal.isEmpty ? 'idle' : 'moving',
        'x': 1.0,
        'y': 2.0,
        'yaw': 0.0,
        'current_location': '로비',
        'current_goal': goal,
        'error_reason': '',
        'waiting_reason': waiting,
        'map_id': 'starlight_1f',
        'dialog_state': dialog,
        'wait_place': place,
        'wait_left_sec': left,
        'last_destination': last,
      });

  void injectStack({required bool nav2}) => setStackStatusForTest(
        StackStatus(
          nodes: nav2 ? const ['/amcl', '/bt_navigator'] : const ['/rosbridge'],
          odomPublishers: const ['/ekf_filter_node'],
        ),
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<_FakeSupervisor> pump(
    WidgetTester tester, {
    bool nav2 = true,
    String goal = '',
    String waiting = '',
    String dialog = '',
    String place = '',
    int left = -1,
    String last = '',
  }) async {
    final supervisor = _FakeSupervisor();
    supervisor.injectMap();
    supervisor.injectRobot(
      goal: goal,
      waiting: waiting,
      dialog: dialog,
      place: place,
      left: left,
      last: last,
    );
    supervisor.injectStack(nav2: nav2);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SupervisorProvider>.value(value: supervisor),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ChangeNotifierProvider(create: (_) => AppModeProvider()),
        ],
        child: const MaterialApp(
          home: Scaffold(body: MapLocationsScreen()),
        ),
      ),
    );
    await tester.pump();
    return supervisor;
  }

  testWidgets('Nav2 가 떠 있으면 초기 위치를 잡을 수 있다', (tester) async {
    await pump(tester);
    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '초기 위치 잡기'),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('Nav2 가 꺼져 있으면 잠기고 이유를 말해 준다', (tester) async {
    await pump(tester, nav2: false);
    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '초기 위치 잡기'),
    );
    expect(button.onPressed, isNull);
    // 문구는 '주행(Nav2)이 꺼져 있습니다. 확인해주세요.' 이고 어절 단위 줄바꿈을
    // 거치므로 같은 변환으로 찾습니다.
    expect(
      find.textContaining(vicaKeepWords('주행(Nav2)이 꺼져 있습니다')),
      findsOneWidget,
    );
  });

  testWidgets('노드 목록이 늦어도 모드 노드가 초기 위치 대기라고 하면 열린다', (tester) async {
    // 2026-11-16 실기: Nav2 가 막 뜬 직후 rosapi 목록에 Nav2 가 아직 없어 잠겼다(새로고침 뒤 풀림).
    final supervisor = await pump(tester, nav2: false);
    supervisor.setModeStatusForTest(
      const ModeStatus(mode: 'drive', state: ModeState.needInitialPose, nav2: 'waiting_pose'),
    );
    await tester.pump();
    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '초기 위치 잡기'),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('모드 노드도 Nav2 가 아직이라고 하면 잠긴 채다', (tester) async {
    final supervisor = await pump(tester, nav2: false);
    supervisor.setModeStatusForTest(
      const ModeStatus(mode: 'drive', state: ModeState.starting, nav2: 'starting'),
    );
    await tester.pump();
    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '초기 위치 잡기'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('주행 중에는 잠긴다', (tester) async {
    await pump(tester, goal: '3층 대회의실');
    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '초기 위치 잡기'),
    );
    expect(button.onPressed, isNull);
    expect(find.textContaining(vicaKeepWords('주행 중에는')), findsOneWidget);
  });

  // 2026-10-29 사용자 결정 표·목업 38~46: 대기·접근 중에도 원격 주행 탭에서 취소, 처음 안내 중엔 버튼 없음.
  group('대기·접근·처음 안내 표시', () {
    testWidgets('대기 장소에서 기다리는 중 — 상태 줄·남은 시간·대기 취소, 요청·초기 위치 잠김', (tester) async {
      await pump(tester,
          dialog: 'waiting', place: '입구 왼쪽', left: 150, last: '남자 화장실');
      expect(find.textContaining(vicaKeepWords('남자 화장실 입구 왼쪽에서 기다리는 중입니다.')),
          findsOneWidget);
      expect(find.textContaining(vicaKeepWords('남은 시간 2분 30초')), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '대기 취소'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '대기 중'), findsOneWidget);
      expect(find.text('일시정지'), findsNothing);
      final pose = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, '초기 위치 잡기'),
      );
      expect(pose.onPressed, isNull);
    });

    testWidgets('사람에게 다가가는 중 — 접근 취소 하나, 일시정지·주행 취소 없음', (tester) async {
      await pump(tester, goal: '접근 대상', dialog: 'approaching');
      expect(find.textContaining(vicaKeepWords('사람에게 다가가는 중입니다.')), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '접근 취소'), findsOneWidget);
      expect(find.text('일시정지'), findsNothing);
      expect(find.text('주행 취소'), findsNothing);
      expect(find.widgetWithText(FilledButton, '접근 중'), findsOneWidget);
    });

    testWidgets('처음 안내(손잡이 잡기 대기) 중에는 취소 버튼이 없다', (tester) async {
      await pump(tester, dialog: 'grip_wait');
      expect(find.textContaining(vicaKeepWords('사용자에게 처음 안내를 하는 중입니다.')),
          findsOneWidget);
      expect(find.text('대기 취소'), findsNothing);
      expect(find.text('접근 취소'), findsNothing);
      expect(find.text('주행 취소'), findsNothing);
      expect(find.widgetWithText(FilledButton, '안내 중'), findsOneWidget);
    });

    testWidgets('대기 취소를 누르면 확인 뒤 대기 취소를 보낸다', (tester) async {
      // 버튼이 기본 시험 화면(800×600) 아래에 있어 세로로 크게 잡는다.
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final supervisor = await pump(tester,
          dialog: 'moving_to_wait_spot', place: '입구 왼쪽', last: '남자 화장실');
      final cancel = find.widgetWithText(OutlinedButton, '대기 취소');
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      expect(find.text('계속 대기'), findsOneWidget);
      expect(find.textContaining(vicaKeepWords('로봇은 그 자리에 멈춥니다')), findsOneWidget);
      await tester.tap(find.text('취소하기'));
      await tester.pumpAndSettle();
      expect(supervisor.waitCancels, 1);
      expect(supervisor.driveCancels, 0);
      expect(find.text('대기를 취소했습니다.'), findsOneWidget);
    });

    testWidgets('접근 취소는 계속 진행을 누르면 보내지 않는다', (tester) async {
      // 버튼이 기본 시험 화면(800×600) 아래에 있어 세로로 크게 잡는다.
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final supervisor = await pump(tester, dialog: 'awaiting_user');
      final cancel = find.widgetWithText(OutlinedButton, '접근 취소');
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      expect(find.textContaining(vicaKeepWords('1분 동안 다시 다가가지 않습니다')), findsOneWidget);
      await tester.tap(find.text('계속 진행'));
      await tester.pumpAndSettle();
      expect(supervisor.approachCancels, 0);
    });

    testWidgets('확인창이 떠 있는 사이 돌아서는 중이 되면 접근 취소를 보내지 않는다', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final supervisor = await pump(tester, dialog: 'awaiting_user');
      await tester.tap(find.widgetWithText(OutlinedButton, '접근 취소'));
      await tester.pumpAndSettle();
      // 사람이 "네"라고 답해 돌아서기 시작했다 — 처음 안내는 취소가 없다(10-29 표).
      supervisor.injectRobot(dialog: 'turning');
      await tester.pumpAndSettle();
      await tester.tap(find.text('취소하기'));
      await tester.pumpAndSettle();
      expect(supervisor.approachCancels, 0);
      expect(find.text('접근을 취소했습니다.'), findsNothing);
    });

    testWidgets('확인창이 떠 있는 사이 새 안내가 시작되면 대기 취소를 보내지 않는다', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final supervisor = await pump(tester, dialog: 'waiting', last: '남자 화장실');
      await tester.tap(find.widgetWithText(OutlinedButton, '대기 취소'));
      await tester.pumpAndSettle();
      // 사용자가 "비카야"로 목적지를 정해 손잡이 안내가 출발했다.
      supervisor.injectRobot(goal: '408호', dialog: 'navigating');
      await tester.pumpAndSettle();
      await tester.tap(find.text('취소하기'));
      await tester.pumpAndSettle();
      expect(supervisor.waitCancels, 0);
      expect(supervisor.driveCancels, 0);
    });

    testWidgets('안내 주행 중은 종전 그대로 일시정지·주행 취소', (tester) async {
      await pump(tester, goal: '남자 화장실', dialog: 'navigating');
      expect(find.text('일시정지'), findsOneWidget);
      expect(find.text('주행 취소'), findsOneWidget);
      expect(find.text('대기 취소'), findsNothing);
    });
  });

  testWidgets('일시정지 중에도 잠긴다', (tester) async {
    // 일시정지는 목적지를 기억한 채 멈춘 상태입니다. 여기서 자세를 바꾸면
    // 다시 출발할 때 엉뚱한 곳에서 이어갑니다.
    await pump(tester, goal: '3층 대회의실', waiting: '일시정지');
    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '초기 위치 잡기'),
    );
    expect(button.onPressed, isNull);
  });

  // 초기 위치를 짚던 중에 지도를 바꾸면 그 점은 이전 지도의 좌표입니다. 남기면 새 지도의 같은
  // 자리에 점이 떠 엉뚱한 곳을 확정하게 됩니다. 알리지 않고 지웁니다(2026-10-12 사용자 결정).
  testWidgets('초기 위치를 짚던 중 지도를 바꾸면 점이 알림 없이 지워진다', (tester) async {
    final supervisor = await pump(tester);
    supervisor.handleMapListForTest({
      'maps': [
        for (final id in ['starlight_1f', 'starlight_2f'])
          {
            'map_id': id,
            'map_name': id,
            'resolution': 0.05,
            'origin_x': 0.0,
            'origin_y': 0.0,
            'width': 200,
            'height': 200,
          },
      ],
    });
    await tester.pump();
    final entry = find.widgetWithText(OutlinedButton, '초기 위치 잡기');
    await tester.ensureVisible(entry);
    await tester.pump();
    await tester.tap(entry);
    await tester.pump();
    tester.widget<DriveMapCanvas>(find.byType(DriveMapCanvas)).onTapMap!(
      const Offset(3, 3),
    );
    await tester.pump();
    expect(tester.widget<InitialPoseCard>(find.byType(InitialPoseCard)).picked,
        isNotNull);

    final picker = find.byType(DropdownButtonFormField<String>).first;
    await tester.ensureVisible(picker);
    await tester.pumpAndSettle();
    await tester.tap(picker);
    await tester.pumpAndSettle();
    await tester.tap(find.text('starlight_2f').last);
    await tester.pumpAndSettle();

    expect(supervisor.selectedMapId, 'starlight_2f');
    expect(find.byType(VicaDialog), findsNothing);
    expect(tester.widget<InitialPoseCard>(find.byType(InitialPoseCard)).picked,
        isNull);
  });

  testWidgets('버튼을 누르면 3단계 화면이 열린다', (tester) async {
    await pump(tester);
    final entry = find.widgetWithText(OutlinedButton, '초기 위치 잡기');
    await tester.ensureVisible(entry);
    await tester.pump();
    await tester.tap(entry);
    await tester.pump();
    // 카드 제목·확인 버튼은 2026-11-17 간결화(사용자 승인)로 '초기 위치'·'확인'.
    expect(find.text('초기 위치'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '확인'), findsOneWidget);
    // 아직 안 짚었으므로 잠겨 있어야 합니다.
    final check = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '확인'),
    );
    expect(check.onPressed, isNull);
  });

  // 지도 설정의 홈 칸('여기가 맞는지 확인')도 같은 채점을 빌려 씁니다. 그 결과가
  // 남은 채로 초기 위치 잡기를 열면, 짚은 점도 없는데 그 점수로 '확정'이 열렸습니다
  // (검토 35bc1d0 B4).
  testWidgets('들어오기 전부터 남아 있던 채점 결과는 보이지 않는다', (tester) async {
    final server = FakeRosServer();
    final supervisor = _FakeSupervisor(rosChannelConnector: server.connect);
    await supervisor.connect(const AppSettings());
    supervisor.injectMap();
    supervisor.injectRobot();
    supervisor.injectStack(nav2: true);
    // 다른 화면이 남긴 결과.
    final leftover = supervisor.checkInitialPose(
      const AppSettings(),
      x: 1,
      y: 2,
    );
    server.last.answer('/vica/pose_check', {
      'ok': true,
      'score': 88.0,
      'x': 1.0,
      'y': 2.0,
      'hit_x': [1.0],
      'hit_y': [2.0],
    });
    await leftover;
    expect(supervisor.poseCheck, isNotNull);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SupervisorProvider>.value(value: supervisor),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ],
        child: const MaterialApp(home: Scaffold(body: MapLocationsScreen())),
      ),
    );
    await tester.pump();

    final entry = find.widgetWithText(OutlinedButton, '초기 위치 잡기');
    await tester.ensureVisible(entry);
    await tester.pump();
    await tester.tap(entry);
    await tester.pump();
    // 문을 열 때 Nav2 생사를 새로 묻습니다.
    server.last.answer('/rosapi/nodes', {
      'nodes': ['/amcl', '/bt_navigator'],
    });
    await tester.pump();
    server.last.answer('/rosapi/publishers', {
      'publishers': ['/ekf_filter_node'],
    });
    await tester.pump();

    final card = tester.widget<InitialPoseCard>(find.byType(InitialPoseCard));
    expect(card.result, isNull);
    expect(supervisor.poseCheck, isNull);
    expect(
      tester.widget<DriveMapCanvas>(find.byType(DriveMapCanvas)).scanHits,
      isEmpty,
    );
    // 홈·금지구역 조회가 응답 없이 끝나기를 기다립니다.
    await tester.pump(const Duration(seconds: 15));
  });

  // 2026-11-18: '주행 끄기'는 위쪽 막대로 옮겼습니다. 원격 주행 맨 위 줄은 뺐습니다.
  testWidgets('주행 중이어도 원격 주행 화면 안에는 주행 끄기가 없다', (tester) async {
    final supervisor = await pump(tester);
    supervisor.setModeStatusForTest(
      const ModeStatus(mode: 'drive', state: ModeState.running, nav2: 'active'),
    );
    await tester.pump();
    expect(find.text('주행 끄기'), findsNothing);
  });

  // 수동 주행(2026-11-18): 로봇이 할 일이 없을 때만 열린다. 경비 구간·찾기·대화 중은 current_goal 이
  // 비어 있어도 막아야 한다(검토 지적 — Nav2 와 같은 /cmd_vel_req 에 섞인다).
  group('수동 주행 막기', () {
    Future<void> openManual(WidgetTester tester) async {
      await tester.tap(find.text('수동 주행'));
      await tester.pump();
    }

    testWidgets('쉬는 중이면 열린다', (tester) async {
      await pump(tester);
      await openManual(tester);
      expect(find.text('현재 주행 중입니다.\n주행이 완료된 후 사용해주세요.'), findsNothing);
      expect(find.text('속도'), findsOneWidget);
    });

    for (final dialog in ['patrolling', 'patrol_dwell', 'seeking', 'confirming', 'asking_next', 'returning']) {
      testWidgets('$dialog 이면 막는다', (tester) async {
        await pump(tester, dialog: dialog);
        await openManual(tester);
        expect(find.text('현재 주행 중입니다.\n주행이 완료된 후 사용해주세요.'), findsOneWidget);
      });
    }

    testWidgets('목적지 주행 중이면 막는다', (tester) async {
      await pump(tester, goal: '로비');
      await openManual(tester);
      expect(find.text('현재 주행 중입니다.\n주행이 완료된 후 사용해주세요.'), findsOneWidget);
    });
  });
}
