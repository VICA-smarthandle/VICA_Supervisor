// 주행 화면 틀이 음성 연결 알림 띠를 어느 탭에서든 띄우는지(2026-11-16 목업 D).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vica_supervisor/app.dart';
import 'package:vica_supervisor/providers/app_mode_provider.dart';
import 'package:vica_supervisor/providers/auth_provider.dart';
import 'package:vica_supervisor/providers/settings_provider.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';
import 'package:vica_supervisor/providers/ui_preferences_provider.dart';
import 'package:vica_supervisor/widgets/vica_ui.dart';

Map<String, Object?> status(List<(int, String, String)> events) => {
      'mode': 'drive',
      'state': 'running',
      'voice_events_epoch': 7.0,
      'voice_events': [
        for (final (id, kind, text) in events) {'id': id, 'at': 1794825000.0 + id, 'kind': kind, 'text': text},
      ],
    };

void main() {
  testWidgets('새 음성 연결 알림이 오면 화면 아래 띠로 띄운다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
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
        child: MaterialApp(theme: vicaTheme(), home: const SupervisorShell()),
      ),
    );
    await tester.pump();

    // 연결 직후 첫 상태(기록만) → 그 뒤 새 알림(띄움).
    supervisor.handleModeStatusForTest(status([(1, 'external_ok', '외부 API 연결 성공')]));
    await tester.pump();
    expect(find.textContaining(vicaKeepWords('음성: 외부 API 연결 성공')), findsNothing);

    supervisor.handleModeStatusForTest(status([
      (1, 'external_ok', '외부 API 연결 성공'),
      (2, 'external_fallback', '외부 API 연결 실패 → 로컬 API 로 전환'),
    ]));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining(vicaKeepWords('음성: 외부 API 연결 실패 → 로컬 API 로 전환')), findsOneWidget);
    expect(find.textContaining('알림 및 로그 › 연결 상태에 남았습니다'), findsOneWidget);
  });
}
