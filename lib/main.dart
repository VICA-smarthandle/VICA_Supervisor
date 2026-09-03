// 이 파일은 VICA_Supervisor 앱의 진입점이며 provider들을 앱 전체에 등록합니다.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'providers/app_mode_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/supervisor_provider.dart';
import 'providers/ui_preferences_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final authProvider = AuthProvider();
  final settingsProvider = SettingsProvider();
  final uiPreferencesProvider = UiPreferencesProvider();
  // 배송 기억도 연결 전에 되살립니다. 연결 뒤 첫 로봇 상태가 그 기억과 대조하는데,
  // 되살리기가 늦으면 대조할 기회를 놓칩니다(2026-09-03).
  final supervisorProvider = SupervisorProvider();
  await Future.wait([
    authProvider.load(),
    settingsProvider.load(),
    uiPreferencesProvider.load(),
    supervisorProvider.restoreDelivery(),
  ]);
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authProvider),
        ChangeNotifierProvider.value(value: settingsProvider),
        ChangeNotifierProvider.value(value: uiPreferencesProvider),
        ChangeNotifierProvider.value(value: supervisorProvider),
        ChangeNotifierProvider(create: (_) => AppModeProvider()),
      ],
      child: const VicaSupervisorApp(),
    ),
  );
}
