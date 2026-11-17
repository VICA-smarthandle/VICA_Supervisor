// 중복 실행 경고 띠(2026-11-17 목업 '② 두 벌 경고 띠', 문구 사용자 확정).
//
// 모드 노드가 1초마다 감시 프로세스 수를 세어 /vica/mode_status.duplicated 에 싣습니다.
// 앱은 그 목록이 비어 있지 않으면 주행·지도 화면 어느 탭에서든 위쪽에 띠를 띄웁니다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vica_supervisor/app.dart';
import 'package:vica_supervisor/models/mode_status.dart';
import 'package:vica_supervisor/providers/app_mode_provider.dart';
import 'package:vica_supervisor/providers/auth_provider.dart';
import 'package:vica_supervisor/providers/settings_provider.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';
import 'package:vica_supervisor/providers/ui_preferences_provider.dart';
import 'package:vica_supervisor/screens/mapping_shell.dart';
import 'package:vica_supervisor/widgets/duplicate_run_banner.dart';
import 'package:vica_supervisor/widgets/vica_ui.dart';

Map<String, Object?> drive(List<String> duplicated) => {
      'mode': 'drive',
      'state': 'running',
      'nav2': 'active',
      'duplicated': duplicated,
    };

final message = find.text(vicaKeepWords('앱과 터미널에서 함께 실행됐으니 하나를 꺼 주세요.'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('모드 상태에서 중복 목록을 읽는다', () {
    expect(ModeStatus.fromJson(drive(['ekf_node', 'amcl'])).duplicated, ['ekf_node', 'amcl']);
    expect(ModeStatus.fromJson(const {'mode': 'idle', 'state': 'idle'}).duplicated, isEmpty);
  });

  test('프로세스 이름을 묶음 이름으로 바꾸고, 모르는 이름은 그대로 둔다', () {
    expect(duplicateGroups(['ekf_node', 'amcl', 'bt_navigator']), ['Nav2']);
    expect(duplicateGroups(['vica_mission_ma', 'ekf_node']), ['미션', 'Nav2']);
    // 명령줄로 알아보는 유닛은 유닛 키가 옵니다(mode_logic._duplicated).
    expect(duplicateGroups(['app', 'llm']), ['rosbridge', '음성']);
    expect(duplicateGroups(['foo_node']), ['foo_node']);
  });

  Future<SupervisorProvider> pumpShell(WidgetTester tester, Widget shell, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final auth = AuthProvider();
    await auth.login(username: 'admin', password: '1234');
    final ui = UiPreferencesProvider();
    await ui.load();
    final supervisor = SupervisorProvider();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: auth),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ChangeNotifierProvider<SupervisorProvider>.value(value: supervisor),
          ChangeNotifierProvider.value(value: ui),
          ChangeNotifierProvider(create: (_) => AppModeProvider()),
        ],
        child: MaterialApp(theme: vicaTheme(), home: shell),
      ),
    );
    await tester.pump();
    return supervisor;
  }

  for (final (name, size) in const [('폰', Size(390, 844)), ('넓은 화면', Size(1280, 900))]) {
    testWidgets('주행 화면($name): 중복이면 띠를 띄우고, 없어지면 지운다', (tester) async {
      final supervisor = await pumpShell(tester, const SupervisorShell(), size);
      supervisor.handleModeStatusForTest(drive([]));
      await tester.pump();
      expect(find.byType(DuplicateRunBanner), findsOneWidget);
      expect(message, findsNothing);

      supervisor.handleModeStatusForTest(drive(['ekf_node', 'amcl', 'bt_navigator']));
      await tester.pump();
      expect(find.text(vicaKeepWords('중복 실행 중 · Nav2')), findsOneWidget);
      expect(message, findsOneWidget);
      expect(tester.takeException(), isNull);

      supervisor.handleModeStatusForTest(drive([]));
      await tester.pump();
      expect(message, findsNothing);
    });
  }

  testWidgets('지도 화면에서도 띄운다', (tester) async {
    final supervisor = await pumpShell(tester, const MappingShell(), const Size(390, 844));
    supervisor.handleModeStatusForTest({
      'mode': 'idle',
      'state': 'idle',
      'duplicated': ['rplidar_node'],
    });
    await tester.pump();
    expect(find.text(vicaKeepWords('중복 실행 중 · 라이다')), findsOneWidget);
    expect(message, findsOneWidget);
  });
}
