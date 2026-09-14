// 원격 주행 화면에서 초기 위치를 잡을 수 있는 조건을 고정합니다.
//
// 초기 위치 확정은 AMCL 이 자기 위치를 다시 믿는 순간입니다. 아무 때나 열려
// 있으면 안 됩니다. 특히 **주행 중에 바꾸면** Nav2 가 따라가던 경로를 엉뚱한
// 곳에서 이어가려 합니다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vica_supervisor/models/stack_status.dart';
import 'package:vica_supervisor/providers/settings_provider.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';
import 'package:vica_supervisor/screens/map_locations_screen.dart';

class _FakeSupervisor extends SupervisorProvider {
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
          checkedAt: DateTime(2026, 8, 25),
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
    expect(find.textContaining('먼저 시작하세요'), findsOneWidget);
  });

  testWidgets('주행 중에는 잠긴다', (tester) async {
    await pump(tester, goal: '3층 대회의실');
    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '초기 위치 잡기'),
    );
    expect(button.onPressed, isNull);
    expect(find.textContaining('주행 중에는'), findsOneWidget);
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

  testWidgets('버튼을 누르면 3단계 화면이 열린다', (tester) async {
    await pump(tester);
    final entry = find.widgetWithText(OutlinedButton, '초기 위치 잡기');
    await tester.ensureVisible(entry);
    await tester.pump();
    await tester.tap(entry);
    await tester.pump();
    expect(find.text('초기 위치 잡기'), findsOneWidget);
    expect(find.text('여기가 맞는지 확인'), findsOneWidget);
    // 아직 안 짚었으므로 잠겨 있어야 합니다.
    final check = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '여기가 맞는지 확인'),
    );
    expect(check.onPressed, isNull);
  });
}
