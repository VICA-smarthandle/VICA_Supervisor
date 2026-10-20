import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vica_supervisor/app.dart';
import 'package:vica_supervisor/core/app_settings.dart';
import 'package:vica_supervisor/models/stack_status.dart';
import 'package:vica_supervisor/providers/app_mode_provider.dart';
import 'package:vica_supervisor/providers/auth_provider.dart';
import 'package:vica_supervisor/providers/settings_provider.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';
import 'package:vica_supervisor/providers/ui_preferences_provider.dart';
import 'package:vica_supervisor/screens/current_location_screen.dart';
import 'package:vica_supervisor/screens/dashboard_screen.dart';
import 'package:vica_supervisor/screens/delivery_screen.dart';
import 'package:vica_supervisor/screens/login_screen.dart';
import 'package:vica_supervisor/screens/logs_screen.dart';
import 'package:vica_supervisor/screens/map_locations_screen.dart';
import 'package:vica_supervisor/screens/mapping_shell.dart';
import 'package:vica_supervisor/screens/mode_select_screen.dart';
import 'package:vica_supervisor/screens/save_location_screen.dart';
import 'package:vica_supervisor/screens/settings_screen.dart';
import 'package:vica_supervisor/screens/mode_select_screen.dart'
    show ModeSelectScreen;
import 'package:vica_supervisor/screens/system_diagnostics_screen.dart';
import 'package:vica_supervisor/widgets/vica_ui.dart';

import '../screens/system_diagnostics_screen_test.dart'
    show faultMsg, healthMsg;

/// 화면 표시 규칙만 보기 위해 rosbridge 없이 상태를 넣습니다.
class _Supervisor extends SupervisorProvider {
  void injectHealth(Map<String, Object?> msg) => handleRobotHealthForTest(msg);

  void injectConflictingStack() => setStackStatusForTest(
        const StackStatus(
          nodes: [
            '/amcl',
            '/cartographer_node',
            '/ekf_filter_node',
            '/ekf_filter_node',
          ],
          odomPublishers: ['/ekf_filter_node', '/ekf_filter_node'],
        ),
      );

  void injectMaps() => handleMapListForTest({
        'maps': [
          {
            'map_id': 'starlight_1f',
            'map_name': '별빛관 1층 전체 평면도 (2026-07 갱신본)',
            'image_url': '/maps/starlight_1f.png',
            'width': 800,
            'height': 600,
          },
        ],
      });

  void injectLocations() => handleLocationListForTest({
        'map_id': 'starlight_1f',
        'locations': [
          {
            'id': 'loc_1',
            'name': '별빛관 1층 남자 화장실 앞 복도',
            'pose': {'x': 1.0, 'y': 2.0, 'yaw': 0.0},
          },
        ],
      });

  void injectMapping(String state, {String mapId = '', String detail = ''}) {
    handleMappingStatusForTest({
      'data': jsonEncode({
        'state': state,
        'detail': detail,
        'map_id': mapId,
        'nav2_running': false,
        'mapping_running': state == 'mapping',
        'duplicated': <String>[],
        'prerequisites_missing': <String>[],
      }),
    });
    handleMapPreviewForTest({
      'data': jsonEncode({
        'image_url': '/maps/_live/preview.png',
        'seq': 1,
        'width': 40,
        'height': 30,
        'resolution': 0.05,
        'origin_x': -1.5,
        'origin_y': -2.5,
        'bytes': 4533,
        'robot_x': 0.5,
        'robot_y': 0.25,
        'robot_yaw': 90.0,
      }),
    });
  }

  void selectFirstMap() => selectMap(const AppSettings(), 'starlight_1f');

  void injectRobot() => handleRobotStatusForTest({
        'robot_id': 'vica_robot_01',
        'robot_name': 'VICA 실내 안내 로봇 1호기 (별빛관)',
        'status': 'moving',
        'x': 1.0,
        'y': 2.0,
        'yaw': 0.0,
        'current_location': '별빛관 1층 로비 안내데스크 앞',
        'current_goal': '별빛관 3층 대회의실',
        'error_reason': '전방 범퍼 충돌 감지로 주행을 중단했습니다.',
        'waiting_reason': '',
        'map_id': 'starlight_1f',
      });
}

/// 실제 앱 테마(vicaTheme)로 감쌉니다. 기본 테마로 돌리면 버튼 최소 폭 같은
Widget _wrap(
  Widget child,
  SupervisorProvider supervisor,
  double textScale, {
  bool bare = false,
}) {
  return MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: MultiProvider(
      providers: [
        ChangeNotifierProvider<SupervisorProvider>.value(value: supervisor),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => AppModeProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => UiPreferencesProvider()),
      ],
      child: MaterialApp(
        theme: vicaTheme(),
        home: bare ? child : Scaffold(body: child),
      ),
    ),
  );
}

/// 화면을 그리면서 발생한 배치 오류를 모읍니다 — 넘침(overflowed)뿐 아니라
Future<List<String>> _overflowsWhilePumping(
  WidgetTester tester,
  double width,
  double textScale,
  Widget Function() build,
) async {
  final collected = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final message = details.exceptionAsString();
    final isImageLoad = message.contains('NetworkImage') ||
        message.contains('HTTP request failed') ||
        message.contains('SocketException') ||
        message.contains('Failed host lookup') ||
        message.contains('Connection refused');
    if (!isImageLoad) {
      collected.add(message.split('\n').first);
    }
  };
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
  await tester.pumpWidget(build());
  await tester.pump();
  FlutterError.onError = previous;
  return collected;
}

void main() {
  const widths = <double>[320, 360, 480, 600, 720, 900, 1024, 1440];
  const textScales = <double>[1.0, 1.3];

  group('폭과 글자 배율을 바꿔도 화면이 넘치지 않는다', () {
    final screens = <String, Widget Function(_Supervisor)>{
      '대시보드': (s) {
        s
          ..injectHealth(healthMsg())
          ..injectMaps()
          ..injectRobot();
        return const DashboardScreen();
      },
      '시스템 진단': (s) {
        s.injectHealth(healthMsg(faults: [faultMsg(latched: true)]));
        return const SystemDiagnosticsScreen();
      },
      '지도 설정': (s) {
        s
          ..injectMaps()
          ..injectLocations()
          ..selectFirstMap();
        return const SaveLocationScreen();
      },
      '원격 주행': (s) {
        s
          ..injectMaps()
          ..injectLocations()
          ..selectFirstMap()
          ..injectRobot();
        return const MapLocationsScreen();
      },
      '현재 위치': (s) {
        s
          ..injectMaps()
          ..injectLocations()
          ..injectRobot();
        return const CurrentLocationScreen();
      },
      '모드 선택': (s) {
        s.injectConflictingStack();
        return const ModeSelectScreen();
      },
      '지도 모드': (s) => const MappingShell(),
      '지도 모드 (작성 중)': (s) {
        s.injectMapping('mapping');
        return const MappingShell();
      },
      '지도 모드 (저장 중)': (s) {
        s.injectMapping('saving');
        return const MappingShell();
      },
      '지도 모드 (대기)': (s) {
        s.injectMapping('idle');
        return const MappingShell();
      },
      '지도 모드 (완료)': (s) {
        s.injectMapping('idle', mapId: 'map_0915_202648', detail: '저장 완료');
        return const MappingShell();
      },
      '설정': (s) => const SettingsScreen(),
      '물류 배송': (s) {
        s
          ..injectMaps()
          ..injectLocations()
          ..selectFirstMap()
          ..injectRobot();
        return const DeliveryScreen();
      },
      '알림 및 로그': (s) {
        s
          ..injectMaps()
          ..injectLocations();
        return const LogsScreen();
      },
    };

    final bareScreens = <String, Widget Function(_Supervisor)>{
      '로그인': (s) => const LoginScreen(),
      '설정 페이지': (s) => const SettingsPage(),
      '주행 모드 셸': (s) {
        s
          ..injectHealth(healthMsg())
          ..injectMaps()
          ..injectRobot();
        return const SupervisorShell();
      },
      '지도 모드 셸 (작성 중)': (s) {
        s.injectMapping('mapping');
        return const MappingShell();
      },
    };

    final all = <String, (Widget Function(_Supervisor), bool)>{
      for (final e in screens.entries) e.key: (e.value, false),
      for (final e in bareScreens.entries) e.key: (e.value, true),
    };

    for (final entry in all.entries) {
      testWidgets(entry.key, (tester) async {
        SharedPreferences.setMockInitialValues({});
        for (final scale in textScales) {
          for (final width in widths) {
            final overflows = await _overflowsWhilePumping(
              tester,
              width,
              scale,
              () {
                final supervisor = _Supervisor();
                return _wrap(
                  entry.value.$1(supervisor),
                  supervisor,
                  scale,
                  bare: entry.value.$2,
                );
              },
            );
            expect(
              overflows,
              isEmpty,
              reason: '${entry.key} 화면이 폭 $width, 글자 배율 $scale에서 넘쳤습니다.',
            );
          }
        }
      });
    }
  });

  testWidgets('지표 카드의 숫자는 좁은 카드에서도 한 줄을 지킨다', (tester) async {
    const narrowCellWidth = 138.0;
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: narrowCellWidth,
              height: VicaMetricCard.baseHeight,
              child: VicaMetricCard(
                icon: Icons.smart_toy,
                label: '전체 로봇',
                value: '12',
                color: Colors.blue,
                labelFontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );

    final value = tester.renderObject<RenderParagraph>(find.text('12'));
    expect(
      value.didExceedMaxLines,
      isFalse,
      reason: '지표 숫자가 잘렸습니다.',
    );
    final single = tester.renderObject<RenderParagraph>(find.text('전체 로봇'));
    expect(
      value.size.height,
      lessThan(single.size.height * 2.6),
      reason: '지표 숫자가 두 줄로 접혔습니다.',
    );
  });

  testWidgets('좁은 창에서는 연결 버튼 두 개를 위아래로 놓는다', (tester) async {
    Future<Offset> gapBetweenButtons(double width) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 900);
      final supervisor = _Supervisor();
      await tester.pumpWidget(
        _wrap(const DashboardScreen(), supervisor, 1.0),
      );
      await tester.pump();
      final ros = tester.getTopLeft(find.text('ROS 연결'));
      final map = tester.getTopLeft(find.text('지도 미연결'));
      return Offset(map.dx - ros.dx, map.dy - ros.dy);
    }

    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    final narrow = await gapBetweenButtons(400);
    expect(narrow.dy, greaterThan(0), reason: '좁은 창에서 버튼이 나란히 있습니다.');

    final wide = await gapBetweenButtons(1000);
    expect(wide.dy, 0, reason: '넓은 창에서 버튼이 위아래로 쌓였습니다.');
    expect(wide.dx, greaterThan(0));
  });

  testWidgets('좁은 창에서는 라벨을 값 위로 올린다', (tester) async {
    Future<double> labelToValueDy(double width) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: width,
              child: const VicaInfoRow(
                label: '마지막 통신',
                value: '2026-08-01 14:22:31.000',
              ),
            ),
          ),
        ),
      );
      final label = tester.getTopLeft(find.text('마지막 통신'));
      final value = tester.getTopLeft(find.text('2026-08-01 14:22:31.000'));
      return value.dy - label.dy;
    }

    expect(await labelToValueDy(200), greaterThan(0),
        reason: '좁을 때 접히지 않았습니다.');
    expect(await labelToValueDy(600), 0, reason: '넓을 때도 접혔습니다.');
  });
}
