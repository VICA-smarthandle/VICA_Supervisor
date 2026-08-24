// 창 폭을 줄이거나 글자 배율을 올려도 화면 안의 내용이 넘치지 않는지 고정합니다.
//
// 여기 적힌 폭은 실제로 깨졌던 지점입니다. 고치기 전 측정값은 다음과 같았습니다.
//   - 로봇 카드의 정보 칩: 320px에서 148px 넘침 (Wrap이 자식에게 폭 제한을 안 줌)
//   - '연결된 로봇' 드롭다운: 320px에서 179px 넘침 (isExpanded 없음)
//   - '장소 선택' 드롭다운: 320px에서 85px 넘침 (isExpanded 없음)
//   - 지표 카드 숫자: 130px 셀에서 두 줄로 접혀 아래로 14px 넘침
//   - 지표 카드 셀 높이: 글자 배율 1.3에서 14px 넘침 (높이가 116으로 고정)
//
// 문구를 짧게 바꾸면 넘침이 우연히 사라지므로, 현장에서 나올 만한 긴 이름을 씁니다.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vica_supervisor/models/stack_status.dart';
import 'package:vica_supervisor/providers/app_mode_provider.dart';
import 'package:vica_supervisor/providers/auth_provider.dart';
import 'package:vica_supervisor/providers/settings_provider.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';
import 'package:vica_supervisor/screens/current_location_screen.dart';
import 'package:vica_supervisor/screens/dashboard_screen.dart';
import 'package:vica_supervisor/screens/logs_screen.dart';
import 'package:vica_supervisor/screens/map_locations_screen.dart';
import 'package:vica_supervisor/screens/mapping_shell.dart';
import 'package:vica_supervisor/screens/mode_select_screen.dart';
import 'package:vica_supervisor/screens/save_location_screen.dart';
import 'package:vica_supervisor/screens/settings_screen.dart';
import 'package:vica_supervisor/screens/system_diagnostics_screen.dart';
import 'package:vica_supervisor/widgets/vica_ui.dart';

import '../screens/system_diagnostics_screen_test.dart'
    show faultMsg, healthMsg;

/// 화면 표시 규칙만 보기 위해 rosbridge 없이 상태를 넣습니다.
class _Supervisor extends SupervisorProvider {
  void injectHealth(Map<String, Object?> msg) => handleRobotHealthForTest(msg);

  // 카드에 가장 긴 문구가 들어가는 상태(중복 실행 경고)로 배치를 확인합니다.
  void injectConflictingStack() => setStackStatusForTest(
        StackStatus(
          nodes: const [
            '/amcl',
            '/cartographer_node',
            '/ekf_filter_node',
            '/ekf_filter_node',
          ],
          odomPublishers: const ['/ekf_filter_node', '/ekf_filter_node'],
          checkedAt: DateTime(2026, 8, 21),
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

Widget _wrap(Widget child, SupervisorProvider supervisor, double textScale) {
  return MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: MultiProvider(
      providers: [
        ChangeNotifierProvider<SupervisorProvider>.value(value: supervisor),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => AppModeProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    ),
  );
}

/// 화면을 그리면서 발생한 overflow 경고를 모읍니다.
///
/// 지도 이미지는 네트워크에서 받아오므로 테스트에서는 항상 실패합니다. 그것은
/// 배치 문제가 아니므로 걸러냅니다.
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
    if (message.contains('overflowed')) {
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
  // 320은 창을 가장 좁게 줄인 경우, 1440은 최대화한 경우입니다.
  // 900은 사이드 메뉴가 서는 경계라 반드시 포함합니다.
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
      '장소 저장': (s) {
        s
          ..injectMaps()
          ..injectLocations();
        return const SaveLocationScreen();
      },
      '원격 주행': (s) {
        s
          ..injectMaps()
          ..injectLocations()
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
      '설정': (s) => const SettingsScreen(),
      '알림 및 로그': (s) {
        s
          ..injectMaps()
          ..injectLocations();
        return const LogsScreen();
      },
    };

    for (final entry in screens.entries) {
      testWidgets(entry.key, (tester) async {
        for (final scale in textScales) {
          for (final width in widths) {
            final overflows = await _overflowsWhilePumping(
              tester,
              width,
              scale,
              () {
                final supervisor = _Supervisor();
                return _wrap(entry.value(supervisor), supervisor, scale);
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
    // 폭 320일 때 2열 그리드의 셀 폭입니다. 좌우 여백 32, 열 간격 12를 뺀 값입니다.
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
    // 두 줄로 접히면 높이가 두 배가 되고 카드 아래로 넘칩니다.
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
