// 배송 한 건이 로봇의 goal 이벤트를 어떻게 자기 것으로 알아보는지 고정합니다.
//
// **이 파일이 지키는 결함**: 이름으로 맞추면 같은 이름의 장소가 둘일 때 엉뚱한
// 사람에게 "물건 왔습니다" 문자가 갑니다. id 가 정본이고 이름은 옛 로봇용
// 대비책입니다.
import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/models/delivery_job.dart';
import 'package:vica_supervisor/models/location_point.dart';

const _office = LocationPoint(
  locationId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  mapId: 'm1',
  name: '305호',
  x: 1,
  y: 2,
  yaw: 0,
  contactPhone: '01012345678',
);

DeliveryJob job() => DeliveryJob(destination: _office, startedAt: DateTime(2026));

void main() {
  group('matches', () {
    test('id 가 같으면 내 배송이다', () {
      expect(job().matches(locationId: _office.locationId, name: '엉뚱한 이름'),
          isTrue);
    });

    test('id 가 다르면 이름이 같아도 남의 주행이다', () {
      expect(
        job().matches(locationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', name: '305호'),
        isFalse,
      );
    });

    test('id 를 안 실어 보낸 옛 로봇이면 이름으로 물러선다', () {
      expect(job().matches(locationId: '', name: '305호'), isTrue);
      expect(job().matches(locationId: '', name: '306호'), isFalse);
      expect(job().matches(locationId: '', name: ''), isFalse);
    });
  });

  group('deliveryArrivalMessage', () {
    test('짧은 이름은 앞에 붙는다', () {
      expect(
        deliveryArrivalMessage('305호'),
        '[305호] 비카가 물건을 가지고 문 앞에 와 있습니다. 확인해주세요',
      );
    });

    test('45자를 넘기면 이름을 뺀다 — 문자 한 통 한계', () {
      final text = deliveryArrivalMessage('별빛관 3층 스마트로봇연구실 복도 끝');
      expect(text, '비카가 물건을 가지고 문 앞에 와 있습니다. 확인해주세요');
      expect(text.length, lessThanOrEqualTo(45));
    });

    test('이름이 없으면 본문만', () {
      expect(deliveryArrivalMessage('  '), '비카가 물건을 가지고 문 앞에 와 있습니다. 확인해주세요');
    });
  });

  test('copyWith 는 출발 자리와 목적지를 그대로 둔다', () {
    final started = DeliveryJob(
      destination: _office,
      startedAt: DateTime(2026),
      origin: const DeliveryOrigin(x: 3, y: 4, yaw: 90),
    );
    final arrived = started.copyWith(phase: DeliveryPhase.arrived, notified: true);
    expect(arrived.origin?.x, 3);
    expect(arrived.destination.contactPhone, '01012345678');
    expect(arrived.isActive, isFalse);
    expect(arrived.notified, isTrue);
  });
}
