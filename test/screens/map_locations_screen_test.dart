import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vica_supervisor/core/app_settings.dart';
import 'package:vica_supervisor/models/stack_status.dart';
import 'package:vica_supervisor/providers/settings_provider.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';
import 'package:vica_supervisor/screens/map_locations_screen.dart';
import 'package:vica_supervisor/widgets/drive_map_canvas.dart';
import 'package:vica_supervisor/widgets/initial_pose_card.dart';
import 'package:vica_supervisor/widgets/vica_ui.dart';

import '../ros/fake_ros_socket.dart';

class _FakeSupervisor extends SupervisorProvider {
  _FakeSupervisor({super.rosChannelConnector});

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

  void injectRobot({String goal = '', String waiting = ''}) =>
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
  }) async {
    final supervisor = _FakeSupervisor();
    supervisor.injectMap();
    supervisor.injectRobot(goal: goal, waiting: waiting);
    supervisor.injectStack(nav2: nav2);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SupervisorProvider>.value(value: supervisor),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
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
    expect(
      find.textContaining(vicaKeepWords('주행(Nav2)이 꺼져 있습니다')),
      findsOneWidget,
    );
  });

  testWidgets('주행 중에는 잠긴다', (tester) async {
    await pump(tester, goal: '3층 대회의실');
    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '초기 위치 잡기'),
    );
    expect(button.onPressed, isNull);
    expect(find.textContaining(vicaKeepWords('주행 중에는')), findsOneWidget);
  });

  testWidgets('일시정지 중에도 잠긴다', (tester) async {
    await pump(tester, goal: '3층 대회의실', waiting: '일시정지');
    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '초기 위치 잡기'),
    );
    expect(button.onPressed, isNull);
  });

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
    expect(find.text('초기 위치 잡기'), findsOneWidget);
    expect(find.text('여기가 맞는지 확인'), findsOneWidget);
    final check = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '여기가 맞는지 확인'),
    );
    expect(check.onPressed, isNull);
  });

  testWidgets('들어오기 전부터 남아 있던 채점 결과는 보이지 않는다', (tester) async {
    final server = FakeRosServer();
    final supervisor = _FakeSupervisor(rosChannelConnector: server.connect);
    await supervisor.connect(const AppSettings());
    supervisor.injectMap();
    supervisor.injectRobot();
    supervisor.injectStack(nav2: true);
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
    await tester.pump(const Duration(seconds: 15));
  });
}
