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

DeliveryJob job() =>
    DeliveryJob(destination: _office, startedAt: DateTime(2026));

void main() {
  group('matches', () {
    test('id 가 같으면 내 배송이다', () {
      expect(job().matches(locationId: _office.locationId, name: '엉뚱한 이름'),
          isTrue);
    });

    test('id 가 다르면 이름이 같아도 남의 주행이다', () {
      expect(
        job().matches(
            locationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', name: '305호'),
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

    test('메시지가 있으면 [장소] 비카 도착: 메시지', () {
      final text =
          deliveryArrivalMessage('410호', note: '서류 두 장입니다. 확인 후 회신 부탁드립니다');
      expect(text, '[410호] 비카 도착: 서류 두 장입니다. 확인 후 회신 부탁드립니다');
      expect(text.length, lessThanOrEqualTo(kDeliverySmsLimit));
    });

    test('메시지 칸 한도는 45 - 앞부분 — 410호면 31, 이름이 길면 이름을 빼고 38', () {
      expect(deliveryNoteLimit('410호'), 31);
      expect(deliveryNoteLimit('별빛관 3층 스마트로봇연구실 복도 끝'), 38);
      expect(deliveryNoteLimit(''), 38);
      final full = 'ㄱ' * deliveryNoteLimit('410호');
      expect(
          deliveryArrivalMessage('410호', note: full).length, kDeliverySmsLimit);
      expect(deliveryArrivalMessage('410호', note: full), startsWith('[410호] '));
    });

    test('한도를 넘긴 메시지(다른 화면이 보낸 값)는 이름을 빼고, 그래도 넘으면 끝을 자른다', () {
      final text = deliveryArrivalMessage('410호', note: 'ㄱ' * 60);
      expect(text, startsWith('비카 도착: '));
      expect(text.length, kDeliverySmsLimit);
    });

    test('줄바꿈·연속 공백은 한 칸으로, 빈 메시지는 예전 문구', () {
      expect(deliveryArrivalMessage('410호', note: '서류\n두  장'),
          '[410호] 비카 도착: 서류 두 장');
      expect(deliveryArrivalMessage('410호', note: '  \n '),
          '[410호] 비카가 물건을 가지고 문 앞에 와 있습니다. 확인해주세요');
    });

    test('이모지는 반쪽으로 잘리지 않는다', () {
      final text = deliveryArrivalMessage('', note: '${'ㄱ' * 37}😀😀');
      expect(text.length, lessThanOrEqualTo(kDeliverySmsLimit));
      expect(text.runes.last, isNot(inInclusiveRange(0xD800, 0xDFFF)));
    });
  });

  test('메시지는 저장했다 되살려도 남는다', () {
    final job = DeliveryJob(
      destination: const LocationPoint(
          locationId: 'a',
          mapId: 'm1',
          name: '410호',
          x: 0,
          y: 0,
          yaw: 0,
          contactPhone: '01012345678'),
      startedAt: DateTime(2026, 11, 17),
      note: '서류 두 장입니다',
    );
    expect(DeliveryJob.fromJson(job.toJson())!.note, '서류 두 장입니다');
    expect(job.copyWith(notified: true).note, '서류 두 장입니다');
    expect(DeliveryJob.fromJson({...job.toJson()}..remove('note'))!.note, '');
  });

  test('copyWith 는 목적지·번호를 그대로 두고 복귀 예정만 지울 수 있다', () {
    final started =
        DeliveryJob(destination: _office, startedAt: DateTime(2026));
    final arrived = started.copyWith(
      phase: DeliveryPhase.arrived,
      notified: true,
      returnAt: DateTime(2026, 1, 1, 0, 2),
    );
    expect(arrived.destination.contactPhone, '01012345678');
    expect(arrived.isActive, isFalse);
    expect(arrived.isWaitingToReturn, isTrue);

    final canceled = arrived.copyWith(clearReturnAt: true);
    expect(canceled.returnAt, isNull);
    expect(canceled.isWaitingToReturn, isFalse);
    expect(canceled.phase, DeliveryPhase.arrived);
  });

  test('끝난 단계만 지울 수 있다', () {
    expect(DeliveryPhase.completed.isFinished, isTrue);
    expect(DeliveryPhase.aborted.isFinished, isTrue);
    expect(DeliveryPhase.driving.isFinished, isFalse);
    expect(DeliveryPhase.arrived.isFinished, isFalse);
    expect(DeliveryPhase.returning.isFinished, isFalse);
  });

  test('복귀 대기는 시험하기 좋게 2분이다', () {
    expect(deliveryReturnDelay, const Duration(minutes: 2));
  });
  group('저장·되살리기 (2026-09-03)', () {
    test('JSON 으로 나갔다 돌아와도 같은 배송이다', () {
      final original = job().copyWith(
        phase: DeliveryPhase.arrived,
        arrivedAt: DateTime(2026, 9, 3, 14, 0),
        notified: true,
        returnAt: DateTime(2026, 9, 3, 14, 2),
        returnNote: '관리자가 복귀를 취소했습니다.',
      );
      final restored = DeliveryJob.fromJson(original.toJson());
      expect(restored, isNotNull);
      expect(restored!.destination.locationId, _office.locationId);
      expect(restored.destination.contactPhone, _office.contactPhone);
      expect(restored.phase, DeliveryPhase.arrived);
      expect(restored.arrivedAt, original.arrivedAt);
      expect(restored.notified, isTrue);
      expect(restored.returnAt, original.returnAt);
      expect(restored.returnNote, original.returnNote);
    });

    test('목적지가 없거나 단계 이름이 낯설면 되살리지 않거나 중단으로 친다', () {
      expect(DeliveryJob.fromJson({'phase': 'driving'}), isNull);
      final odd = DeliveryJob.fromJson({
        'destination': _office.toJson(),
        'phase': 'flying',
      });
      expect(odd?.phase, DeliveryPhase.aborted);
    });

    test('확인 필요는 끝난 것이 아니라 새 배송을 막지만, 지울 수는 있다', () {
      expect(DeliveryPhase.unconfirmed.isFinished, isFalse);
      final j = job().copyWith(phase: DeliveryPhase.unconfirmed);
      expect(j.isActive, isFalse);
      expect(j.isWaitingToReturn, isFalse);
    });
  });
}
