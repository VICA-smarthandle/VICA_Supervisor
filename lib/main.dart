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
  await Future.wait([
    authProvider.load(),
    settingsProvider.load(),
    uiPreferencesProvider.load(),
  ]);
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authProvider),
        ChangeNotifierProvider.value(value: settingsProvider),
        ChangeNotifierProvider.value(value: uiPreferencesProvider),
        ChangeNotifierProvider(create: (_) => SupervisorProvider()),
        ChangeNotifierProvider(create: (_) => AppModeProvider()),
      ],
      child: const VicaSupervisorApp(),
    ),
  );
}
