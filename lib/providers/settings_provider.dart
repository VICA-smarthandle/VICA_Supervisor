import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_settings.dart';

class SettingsProvider extends ChangeNotifier {
  AppSettings _settings = const AppSettings();

  AppSettings get settings => _settings;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('vica_supervisor_settings');
    if (raw != null) {
      _settings = AppSettings.fromJson(
        _editableOnly(jsonDecode(raw) as Map<String, Object?>),
      );
    }
    notifyListeners();
  }

  Future<void> update(AppSettings next) async {
    if (mapEquals(_settings.toJson(), next.toJson())) {
      return;
    }
    _settings = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'vica_supervisor_settings', jsonEncode(_editableOnly(next.toJson())));
    notifyListeners();
  }

  static Map<String, Object?> _editableOnly(Map<String, Object?> json) => {
        for (final entry in json.entries)
          if (AppSettings.editableJsonKeys.contains(entry.key))
            entry.key: entry.value,
      };
}
