import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/models/location_point.dart';

void main() {
  test('목적지를 destinations 스키마의 JSON으로 변환한다', () {
    const location = LocationPoint(
      locationId: '11111111-1111-4111-8111-111111111111',
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
    expect(json['id'], location.locationId);
    expect(json.containsKey('map_id'), isFalse);
    expect(json['pose'], {
      'frame_id': 'map',
      'x': 1.2,
      'y': -3.4,
      'yaw': 90.0,
    });
    expect(json.containsKey('x'), isFalse);
    expect(json.containsKey('location_id'), isFalse);
  });

  test('목적지 목록 transport의 map_id를 fallback으로 사용한다', () {
    final location = LocationPoint.fromJson(
      {
        'id': '11111111-1111-4111-8111-111111111111',
        'name': '목적지',
        'pose': {'frame_id': 'map', 'x': 4, 'y': 5, 'yaw': 180},
      },
      'vica_map_0630',
    );

    expect(location.mapId, 'vica_map_0630');
    expect(location.x, 4.0);
    expect(location.y, 5.0);
    expect(location.yaw, 180.0);
  });
}
