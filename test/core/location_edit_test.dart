// 저장된 장소 수정이 손으로 다듬은 멘트를 덮지 않는지 고정합니다 (2026-09-03).
//
// **이 파일이 지키는 결함**: 연락처 하나 고쳤는데 확인 멘트가 "OO으로"로 되돌아간다.
import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/core/location_edit.dart';
import 'package:vica_supervisor/models/location_point.dart';

const _original = LocationPoint(
  locationId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  mapId: 'm1',
  name: '화장실',
  x: 1,
  y: 2,
  yaw: 90,
  confirmPrompt: '화장실로 안내해드릴까요?',
  arrivalMessage: '화장실 앞에 도착했습니다. 남자는 왼쪽입니다.',
);

LocationPoint edited({String name = '화장실', String phone = '01012345678'}) =>
    LocationPoint(
      locationId: 'ignored-id',
      mapId: 'm2',
      name: name,
      x: 3,
      y: 4,
      yaw: 0,
      contactPhone: phone,
      confirmPrompt: '$name으로 안내해드릴까요?',
      arrivalMessage: '$name 앞에 도착했습니다.',
    );

void main() {
  test('이름이 그대로면 멘트·id·지도는 원본, 나머지는 고친 값', () {
    final merged = mergeEditedLocation(edited: edited(), original: _original);
    expect(merged.locationId, _original.locationId);
    expect(merged.mapId, _original.mapId);
    expect(merged.confirmPrompt, _original.confirmPrompt);
    expect(merged.arrivalMessage, _original.arrivalMessage);
    expect(merged.contactPhone, '01012345678');
    expect(merged.x, 3);
    expect(merged.yaw, 0);
  });

  test('이름이 바뀌면 멘트를 새로 만든다', () {
    final merged =
        mergeEditedLocation(edited: edited(name: '여자 화장실'), original: _original);
    expect(merged.confirmPrompt, '여자 화장실으로 안내해드릴까요?');
    expect(merged.arrivalMessage, '여자 화장실 앞에 도착했습니다.');
    expect(merged.locationId, _original.locationId, reason: '이름을 바꿔도 같은 장소다');
  });

  test('원본 멘트가 비어 있으면 새 멘트를 쓴다', () {
    const bare = LocationPoint(
        locationId: 'b', mapId: 'm1', name: '화장실', x: 0, y: 0, yaw: 0);
    final merged = mergeEditedLocation(edited: edited(), original: bare);
    expect(merged.confirmPrompt, isNotEmpty);
  });

  test('원본이 없으면 고친 값 그대로다', () {
    expect(mergeEditedLocation(edited: edited(), original: null).locationId, 'ignored-id');
  });
}
