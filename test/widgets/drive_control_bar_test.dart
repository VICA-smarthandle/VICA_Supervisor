import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vica_supervisor/providers/settings_provider.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';
import 'package:vica_supervisor/widgets/drive_control_bar.dart';
import 'package:vica_supervisor/widgets/vica_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<SupervisorProvider> pump(WidgetTester tester,
      {required bool paused}) async {
    final supervisor = SupervisorProvider();
    addTearDown(supervisor.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SupervisorProvider>.value(value: supervisor),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: DriveControlBar(
              supervisor: supervisor,
              paused: paused,
              cancelLabel: '복귀 취소',
              cancelTitle: '홈 복귀 취소',
              cancelBody: '홈으로 가던 주행을 취소합니다.',
            ),
          ),
        ),
      ),
    );
    return supervisor;
  }

  testWidgets('주행 중이면 일시정지, 멈춰 있으면 다시 출발', (tester) async {
    await pump(tester, paused: false);
    expect(find.text('일시정지'), findsOneWidget);
    expect(find.text('복귀 취소'), findsOneWidget);

    await pump(tester, paused: true);
    expect(find.text('다시 출발'), findsOneWidget);
    expect(find.text('일시정지'), findsNothing);
  });

  testWidgets('취소는 화면이 준 문구로 한 번 묻고, 그만두면 아무것도 안 보낸다', (tester) async {
    final supervisor = await pump(tester, paused: false);
    await tester.tap(find.text('복귀 취소'));
    await tester.pumpAndSettle();
    expect(find.text('홈 복귀 취소'), findsOneWidget);
    expect(find.text(vicaKeepWords('홈으로 가던 주행을 취소합니다.')), findsOneWidget);

    await tester.tap(find.text('계속'));
    await tester.pumpAndSettle();
    expect(find.text('홈 복귀 취소'), findsNothing);
    expect(supervisor.logs.where((l) => l.message.contains('취소')), isEmpty);
  });
}
