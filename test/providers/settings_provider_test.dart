import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vica_supervisor/core/app_settings.dart';
import 'package:vica_supervisor/providers/settings_provider.dart';

const _key = 'vica_supervisor_settings';
const _defaults = AppSettings();

void main() {
  test('고칠 수 있는 값은 모두 저장되는 값이다', () {
    expect(_defaults.toJson().keys, containsAll(AppSettings.editableJsonKeys));
  });

  test('예전에 저장된, 화면에 칸이 없는 값은 버리고 기본값을 쓴다', () async {
    SharedPreferences.setMockInitialValues({
      _key: jsonEncode({
        'maxReconnectAttempts': 1,
        'missionPauseService': '/old/pause',
        'robotHealthTimeoutSeconds': 99,
        'mappingSaveService': '/old/mapping/save',
      }),
    });
    final provider = SettingsProvider();
    await provider.load();

    final settings = provider.settings;
    expect(settings.maxReconnectAttempts, _defaults.maxReconnectAttempts);
    expect(settings.missionPauseService, _defaults.missionPauseService);
    expect(
      settings.robotHealthTimeoutSeconds,
      _defaults.robotHealthTimeoutSeconds,
    );
    expect(settings.mappingSaveService, _defaults.mappingSaveService);
  });

  test('화면에서 고친 값은 되살린다', () async {
    SharedPreferences.setMockInitialValues({
      _key: jsonEncode({
        'rosBridgeUrl': 'ws://10.0.0.5:9090',
        'mapHttpBaseUrl': 'http://10.0.0.5:8000',
        'xOffset': 1.5,
        'flipMapY': false,
        'autoRequestLocationList': false,
        'emergencyServiceTimeoutSeconds': 12,
        'missionDeliveryService': '/vica/mission/request_delivery_v2',
      }),
    });
    final provider = SettingsProvider();
    await provider.load();

    final settings = provider.settings;
    expect(settings.rosBridgeUrl, 'ws://10.0.0.5:9090');
    expect(settings.mapHttpBaseUrl, 'http://10.0.0.5:8000');
    expect(settings.xOffset, 1.5);
    expect(settings.flipMapY, isFalse);
    expect(settings.autoRequestLocationList, isFalse);
    expect(settings.emergencyServiceTimeoutSeconds, 12);
    expect(
      settings.missionDeliveryService,
      '/vica/mission/request_delivery_v2',
    );
  });

  test('저장할 때는 화면에서 고칠 수 있는 값만 남긴다', () async {
    SharedPreferences.setMockInitialValues({});
    final provider = SettingsProvider();
    await provider.load();
    await provider.update(
      provider.settings.copyWith(rosBridgeUrl: 'ws://10.0.0.5:9090'),
    );

    final prefs = await SharedPreferences.getInstance();
    final stored = jsonDecode(prefs.getString(_key)!) as Map<String, Object?>;
    expect(stored.keys.toSet(), AppSettings.editableJsonKeys);
    expect(stored['rosBridgeUrl'], 'ws://10.0.0.5:9090');
    expect(stored.containsKey('maxReconnectAttempts'), isFalse);
  });
}
