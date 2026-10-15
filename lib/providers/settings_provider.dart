// 이 파일은 설정 화면의 입력값을 shared_preferences에 저장하고 다시 불러옵니다.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_settings.dart';

class SettingsProvider extends ChangeNotifier {
  AppSettings _settings = const AppSettings();

  AppSettings get settings => _settings;

  // 앱 시작 시 저장된 설정을 읽습니다. 설정 화면에서 고칠 수 있는 값만 되살립니다 —
  // 예전 판이 함께 저장해 둔 나머지 값은 버리고 코드의 기본값을 씁니다.
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

  // 값이 실제로 바뀐 경우에만 저장하고 notifyListeners를 호출합니다. 저장하는 것은
  // 설정 화면에서 고칠 수 있는 값뿐입니다(AppSettings.editableJsonKeys).
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
