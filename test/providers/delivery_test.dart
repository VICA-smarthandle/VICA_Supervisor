// 배송 상태 기계를 고정합니다: 도착에만 문자를, 그것도 한 번만.
//
// **이 파일이 지키는 결함**
//   - 같은 도착 이벤트가 두 번 오면 문자가 두 번 나간다.
//   - 실패·취소·비상정지로 끝난 배송에 "물건 왔습니다" 문자가 나간다.
//   - 다른 장소로 간 주행(같은 이름 포함)이 내 배송의 도착으로 잡힌다.
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/core/app_settings.dart';
import 'package:vica_supervisor/models/delivery_job.dart';
import 'package:vica_supervisor/models/location_point.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';
import 'package:vica_supervisor/services/delivery_notifier.dart';

const _office = LocationPoint(
  locationId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  mapId: 'm1',
  name: '305호',
  x: 1,
  y: 2,
  yaw: 0,
  contactPhone: '01012345678',
);

const _noPhone = LocationPoint(
  locationId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
  mapId: 'm1',
  name: '로비',
  x: 0,
  y: 0,
  yaw: 0,
);

/// Mission Manager 가 /vica_goal_event 로 내는 것과 같은 모양입니다.
Map<String, Object?> goalEvent(
  String kind, {
  String locationId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  String name = '305호',
  String reason = '',
}) =>
    {
      'event': kind,
      'map_id': 'm1',
      'location_id': locationId,
      'destination_id': locationId,
      'name': name,
      'reason': reason,
    };

/// 보낸 척만 하고 호출 횟수를 셉니다.
class _CountingNotifier implements DeliveryNotifier {
  int calls = 0;
  String? lastPhone;
  String? lastText;
  bool succeed = true;

  @override
  String get modeLabel => '시험';

  @override
  Future<DeliveryNotifyResult> send({
    required String phone,
    required String text,
  }) async {
    calls += 1;
    lastPhone = phone;
    lastText = text;
    return DeliveryNotifyResult(sent: succeed, detail: succeed ? '갔다' : '안 갔다');
  }
}

void main() {
  late SupervisorProvider provider;
  late _CountingNotifier notifier;

  setUp(() {
    provider = SupervisorProvider();
    notifier = _CountingNotifier();
    provider.deliveryNotifierForTest = notifier;
  });
  tearDown(() => provider.dispose());

  DeliveryJob driving() => DeliveryJob(destination: _office, startedAt: DateTime(2026));

  group('startDelivery 문턱', () {
    test('연락처 없는 장소는 출발 자체를 막는다', () async {
      final message = await provider.startDelivery(const AppSettings(), _noPhone);
      expect(message, contains('연락처'));
      expect(provider.delivery, isNull);
    });

    test('연결이 없으면 요청이 안 나가고 배송도 기억하지 않는다', () async {
      final message = await provider.startDelivery(const AppSettings(), _office);
      expect(message, contains('연결'));
      expect(provider.delivery, isNull);
    });

    test('진행 중인 배송이 있으면 새 배송을 받지 않는다', () async {
      provider.setDeliveryForTest(driving());
      final message = await provider.startDelivery(const AppSettings(), _office);
      expect(message, contains('끝나지 않았습니다'));
    });
  });

  group('도착', () {
    test('내 목적지 도착에 문자를 한 번 보낸다', () async {
      provider.setDeliveryForTest(driving());
      provider.handleGoalEventForTest(goalEvent('goal_succeeded'));
      await Future<void>.delayed(Duration.zero);

      expect(provider.delivery?.phase, DeliveryPhase.arrived);
      expect(provider.delivery?.notified, isTrue);
      expect(notifier.calls, 1);
      expect(notifier.lastPhone, '01012345678');
      expect(notifier.lastText, contains('305호'));
      expect(provider.pendingDeliveryNotice?.result.sent, isTrue);
    });

    test('같은 도착이 두 번 와도 문자는 한 번이다', () async {
      provider.setDeliveryForTest(driving());
      provider.handleGoalEventForTest(goalEvent('goal_succeeded'));
      provider.handleGoalEventForTest(goalEvent('goal_succeeded'));
      await Future<void>.delayed(Duration.zero);
      expect(notifier.calls, 1);
    });

    test('다른 장소의 도착은 내 배송이 아니다 — 이름이 같아도', () async {
      provider.setDeliveryForTest(driving());
      provider.handleGoalEventForTest(
        goalEvent('goal_succeeded',
            locationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', name: '305호'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(provider.delivery?.phase, DeliveryPhase.driving);
      expect(notifier.calls, 0);
    });

    test('홈 복귀 성공은 배송 도착이 아니다', () async {
      provider.setDeliveryForTest(driving());
      provider.handleGoalEventForTest(
        goalEvent('return_home_succeeded', locationId: '__home__', name: '홈'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(provider.delivery?.phase, DeliveryPhase.driving);
      expect(notifier.calls, 0);
    });

    test('발송이 실패해도 상태는 도착이고 결과는 실패로 남는다', () async {
      notifier.succeed = false;
      provider.setDeliveryForTest(driving());
      provider.handleGoalEventForTest(goalEvent('goal_succeeded'));
      await Future<void>.delayed(Duration.zero);
      expect(provider.delivery?.phase, DeliveryPhase.arrived);
      expect(provider.pendingDeliveryNotice?.result.sent, isFalse);
    });

    test('기본 발송기는 미리보기라 실제로 보내지 않는다', () async {
      final plain = SupervisorProvider();
      addTearDown(plain.dispose);
      plain.setDeliveryForTest(driving());
      plain.handleGoalEventForTest(goalEvent('goal_succeeded'));
      await Future<void>.delayed(Duration.zero);
      expect(plain.deliveryNotifierLabel, '미리보기');
      expect(plain.pendingDeliveryNotice?.result.sent, isFalse);
    });
  });

  group('중단', () {
    for (final kind in ['goal_failed', 'goal_rejected', 'goal_canceled', 'emergency_stopped']) {
      test('$kind 이면 문자를 보내지 않는다', () async {
        provider.setDeliveryForTest(driving());
        provider.handleGoalEventForTest(goalEvent(kind, reason: '막힘'));
        await Future<void>.delayed(Duration.zero);
        expect(provider.delivery?.phase, DeliveryPhase.aborted);
        expect(provider.delivery?.abortReason, '막힘');
        expect(notifier.calls, 0);
      });
    }

    test('중단된 뒤에 오는 도착은 무시한다', () async {
      provider.setDeliveryForTest(driving());
      provider.handleGoalEventForTest(goalEvent('goal_canceled'));
      provider.handleGoalEventForTest(goalEvent('goal_succeeded'));
      await Future<void>.delayed(Duration.zero);
      expect(notifier.calls, 0);
    });
  });

  group('지우기', () {
    test('진행 중인 배송은 지워지지 않는다', () {
      provider.setDeliveryForTest(driving());
      provider.clearDelivery();
      expect(provider.delivery, isNotNull);
    });

    test('끝난 배송은 지워진다', () {
      provider.setDeliveryForTest(driving().copyWith(phase: DeliveryPhase.aborted));
      provider.clearDelivery();
      expect(provider.delivery, isNull);
    });
  });

  group('도착 뒤 홈 복귀', () {
    DeliveryJob arrivedJob() => driving().copyWith(
          phase: DeliveryPhase.arrived,
          notified: true,
          returnAt: DateTime.now().add(deliveryReturnDelay),
        );

    test('도착하면 2분 뒤 홈 복귀가 예약된다', () async {
      provider.setDeliveryForTest(driving());
      final before = DateTime.now();
      provider.handleGoalEventForTest(goalEvent('goal_succeeded'));
      await Future<void>.delayed(Duration.zero);
      final returnAt = provider.delivery?.returnAt;
      expect(returnAt, isNotNull);
      expect(returnAt!.difference(before), greaterThanOrEqualTo(deliveryReturnDelay));
      expect(provider.delivery?.isWaitingToReturn, isTrue);
    });

    test('시간이 다 되면 홈 복귀를 요청한다 — 연결이 없으면 거부 사유를 남긴다', () {
      fakeAsync((async) {
        provider.setDeliveryForTest(driving());
        provider.handleGoalEventForTest(goalEvent('goal_succeeded'));
        async.flushMicrotasks();
        expect(provider.delivery?.isWaitingToReturn, isTrue);

        async.elapse(deliveryReturnDelay - const Duration(seconds: 1));
        expect(provider.delivery?.isWaitingToReturn, isTrue, reason: '아직 1초 남음');

        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        // 시험에는 rosbridge 가 없어 요청이 거부됩니다. 그러면 도착 상태로 남고
        // 사유가 적히며 예정은 지워집니다 — 관리자가 다시 판단합니다.
        expect(provider.delivery?.phase, DeliveryPhase.arrived);
        expect(provider.delivery?.returnAt, isNull);
        expect(provider.delivery?.returnNote, contains('연결'));
      });
    });

    test('관리자가 복귀를 취소하면 예정이 사라지고 로봇은 그 자리에 남는다', () {
      fakeAsync((async) {
        provider.setDeliveryForTest(driving());
        provider.handleGoalEventForTest(goalEvent('goal_succeeded'));
        async.flushMicrotasks();
        provider.cancelDeliveryReturn();
        expect(provider.delivery?.returnAt, isNull);
        expect(provider.delivery?.returnNote, contains('취소'));

        async.elapse(deliveryReturnDelay * 2);
        async.flushMicrotasks();
        expect(provider.delivery?.phase, DeliveryPhase.arrived, reason: '취소 뒤엔 시계가 안 돈다');
      });
    });

    test('지금 복귀는 예정을 기다리지 않는다', () async {
      provider.setDeliveryForTest(arrivedJob());
      final message = await provider.returnDeliveryNow(const AppSettings());
      expect(message, contains('연결'));
      expect(provider.delivery?.returnAt, isNull);
    });

    test('복귀 중 홈 도착이면 완료, 실패면 도착 상태로 되돌린다', () {
      provider.setDeliveryForTest(driving().copyWith(phase: DeliveryPhase.returning));
      provider.handleGoalEventForTest(
        goalEvent('return_home_failed', locationId: '__home__', name: '홈', reason: '경로 막힘'),
      );
      expect(provider.delivery?.phase, DeliveryPhase.arrived);
      expect(provider.delivery?.returnNote, '경로 막힘');

      provider.setDeliveryForTest(driving().copyWith(phase: DeliveryPhase.returning));
      provider.handleGoalEventForTest(
        goalEvent('return_home_succeeded', locationId: '__home__', name: '홈'),
      );
      expect(provider.delivery?.phase, DeliveryPhase.completed);
    });

    test('복귀 예정이 살아 있거나 복귀 중이면 지워지지 않는다', () {
      provider.setDeliveryForTest(arrivedJob());
      provider.clearDelivery();
      expect(provider.delivery, isNotNull);

      provider.setDeliveryForTest(driving().copyWith(phase: DeliveryPhase.returning));
      provider.clearDelivery();
      expect(provider.delivery, isNotNull);

      provider.setDeliveryForTest(driving().copyWith(phase: DeliveryPhase.completed));
      provider.clearDelivery();
      expect(provider.delivery, isNull);
    });

    test('끝나지 않은 배송이 있으면 새 배송을 받지 않는다', () async {
      provider.setDeliveryForTest(arrivedJob());
      final message = await provider.startDelivery(const AppSettings(), _office);
      expect(message, contains('끝나지 않았습니다'));
    });
  });

  test('로그에 전화번호를 남기지 않는다', () async {
    provider.setDeliveryForTest(driving());
    provider.handleGoalEventForTest(goalEvent('goal_succeeded'));
    await Future<void>.delayed(Duration.zero);
    for (final log in provider.logs) {
      expect(log.message, isNot(contains('01012345678')));
      expect(log.message, isNot(contains('1234')));
    }
  });
}
