// 이 파일은 설정 화면의 입력값을 shared_preferences에 저장하고 다시 불러옵니다.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_settings.dart';

class SettingsProvider extends ChangeNotifier {
  AppSettings _settings = const AppSettings();
  bool _loaded = false;

  AppSettings get settings => _settings;
  bool get loaded => _loaded;

  // 앱 시작 시 저장된 설정을 읽습니다.
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

  // 값이 실제로 바뀐 경우에만 저장하고 notifyListeners를 호출합니다.
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
