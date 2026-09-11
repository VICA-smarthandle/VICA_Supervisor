import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_settings.dart';

class SettingsProvider extends ChangeNotifier {
  AppSettings _settings = const AppSettings();
  bool _loaded = false;

  AppSettings get settings => _settings;
  bool get loaded => _loaded;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('vica_supervisor_settings');
    if (raw != null) {
      _settings = AppSettings.fromJson(
        jsonDecode(raw) as Map<String, Object?>,
      );
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> update(AppSettings next) async {
    if (mapEquals(_settings.toJson(), next.toJson())) {
      return;
    }
    _settings = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'vica_supervisor_settings', jsonEncode(next.toJson()));
    notifyListeners();
  }
}
