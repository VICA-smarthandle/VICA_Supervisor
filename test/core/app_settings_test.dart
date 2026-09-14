// 설정이 저장(JSON)과 복원을 거쳐도 배송 서비스 이름을 잃지 않는지 고정합니다.
//
// **이 파일이 지키는 결함**: AppSettings 는 toJson/fromJson/copyWith 세 곳에
// 같은 항목을 손으로 적어야 합니다. 한 곳을 빠뜨리면 앱을 다시 켤 때 그 항목만
// 기본값으로 돌아가는데, 화면에는 아무 표시가 없습니다.
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
    expect(restored.missionDeliveryService, '/vica/mission/request_delivery_v2');
    // 옆 항목은 건드리지 않는다.
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
