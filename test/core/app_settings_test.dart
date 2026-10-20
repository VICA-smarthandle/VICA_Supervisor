import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/core/app_settings.dart';

void main() {
  test('배송 서비스 기본값은 request_delivery 이다', () {
    expect(
      const AppSettings().missionDeliveryService,
      '/vica/mission/request_delivery',
    );
    expect(
      const AppSettings().missionRequestService,
      '/vica/mission/request_destination',
    );
  });

  test('배송 서비스 이름이 JSON 왕복과 copyWith 에서 살아남는다', () {
    final changed = const AppSettings()
        .copyWith(missionDeliveryService: '/vica/mission/request_delivery_v2');
    final restored = AppSettings.fromJson(changed.toJson());
    expect(
        restored.missionDeliveryService, '/vica/mission/request_delivery_v2');
    expect(restored.missionRequestService, '/vica/mission/request_destination');
  });

  test('옛 설정 JSON 에 항목이 없으면 기본값을 쓴다', () {
    final json = const AppSettings().toJson()..remove('missionDeliveryService');
    expect(
      AppSettings.fromJson(json).missionDeliveryService,
      '/vica/mission/request_delivery',
    );
  });
}
