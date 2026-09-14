import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/models/location_point.dart';

void main() {
  test('목적지를 destinations 스키마의 JSON으로 변환한다', () {
    const location = LocationPoint(
      locationId: 'starlight_1f_restroom',
      mapId: 'vica_map_0529',
      name: '별빛관 1층 화장실',
      aliases: ['별빛관 1층 화장실', '화장실'],
      category1: 'facility',
      category2: 'restroom',
      building: 'starlight_building',
      floor: 1,
      authorization: 'public',
      isApproachable: true,
      x: 1.2,
      y: -3.4,
      yaw: 90,
      confirmPrompt: '별빛관 1층 화장실로 안내해드릴까요?',
      arrivalMessage: '별빛관 1층 화장실 앞에 도착했습니다.',
    );

    final json = location.toJson();

    expect(json['id'], 'starlight_1f_restroom');
    expect(json.containsKey('map_id'), isFalse);
    expect(json['category1'], 'facility');
    expect(json['category2'], 'restroom');
    expect(json['aliases'], ['별빛관 1층 화장실', '화장실']);
    expect(json['pose'], {
      'frame_id': 'map',
      'x': 1.2,
      'y': -3.4,
      'yaw': 90.0,
    });
    expect(json.containsKey('x'), isFalse);
    expect(json.containsKey('location_id'), isFalse);
  });

  test('기존 location JSON도 읽을 수 있다', () {
    final location = LocationPoint.fromJson(
      {
        'location_id': 'legacy_room',
        'name': '기존 장소',
        'category': 'room',
        'x': 4,
        'y': 5,
        'yaw': 180,
      },
      'legacy_map',
    );

    expect(location.locationId, 'legacy_room');
    expect(location.mapId, 'legacy_map');
    expect(location.category1, 'room');
    expect(location.x, 4.0);
    expect(location.y, 5.0);
    expect(location.yaw, 180.0);
  });

  // -- 연락처 (물류 배송 도착 문자) ------------------------------------------
  //
  // 파일 키는 contact_phone 하나이고 숫자만 들어 있습니다. 옛 파일에는 키가
  // 없으니 없어도 읽혀야 합니다.
  group('contactPhone', () {
    test('JSON 왕복에서 살아남는다', () {
      const location = LocationPoint(
        locationId: '11111111-1111-4111-8111-111111111111',
        mapId: 'm1',
        name: '305호',
        x: 0,
        y: 0,
        yaw: 0,
        contactPhone: '01012345678',
      );
      final json = location.toJson();
      expect(json['contact_phone'], '01012345678');
      expect(LocationPoint.fromJson(json, 'm1').contactPhone, '01012345678');
      expect(location.canReceiveDelivery, isTrue);
    });

    test('키가 없는 옛 파일은 빈 값으로 읽힌다', () {
      final location = LocationPoint.fromJson(
        {'id': 'x', 'name': '옛 장소', 'pose': {'x': 1, 'y': 2, 'yaw': 0}},
        'm1',
      );
      expect(location.contactPhone, '');
      expect(location.canReceiveDelivery, isFalse);
    });
  });
}
