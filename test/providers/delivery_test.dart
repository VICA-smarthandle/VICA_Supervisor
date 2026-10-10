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
import 'package:vica_supervisor/services/delivery_job_store.dart';
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
  bool delivery = false,
  String stamp = '',
}) =>
    {
      'event': kind,
      'map_id': 'm1',
      'location_id': locationId,
      'destination_id': locationId,
      'name': name,
      'reason': reason,
      if (delivery) 'delivery': true,
      if (stamp.isNotEmpty) 'timestamp': stamp,
    };

/// 보낸 척만 하고 호출 횟수를 셉니다.
class _CountingNotifier implements DeliveryNotifier {
  int calls = 0;
  String? lastPhone;
  String? lastText;
  bool succeed = true;

  /// 이 기기가 문자를 보낼 수 있는가(유심 폰이면 true, 웹·유심 없는 폰이면 false).
  bool canSendNow = true;

  @override
  String get modeLabel => '시험';

  @override
  Future<bool> canSend() async => canSendNow;

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

/// /robot_status 한 줄. 되살린 배송을 대조할 때 목적지 이름만 본다.
Map<String, Object?> robotStatus({String goal = ''}) => {
      'robot_id': 'vica_01',
      'status': goal.isEmpty ? 'idle' : 'moving',
      'x': 0.0,
      'y': 0.0,
      'yaw': 0.0,
      'current_goal': goal,
      'error_reason': '',
      'waiting_reason': '',
      'map_id': 'm1',
    };

void main() {
  late SupervisorProvider provider;
  late _CountingNotifier notifier;
  late MemoryDeliveryJobStore store;

  setUp(() {
    store = MemoryDeliveryJobStore();
    provider = SupervisorProvider(deliveryJobStore: store);
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

    test('기본 발송기(웹·데스크탑)는 직접 보내지 않고, 유심 폰 결과가 30초 안에 없으면 안 간 것으로 알린다',
        () {
      fakeAsync((async) {
        final plain = SupervisorProvider();
        plain.setDeliveryForTest(driving());
        plain.handleGoalEventForTest(
            goalEvent('goal_succeeded', delivery: true, stamp: '2026-10-10T10:00:00'));
        async.flushMicrotasks();
        expect(plain.deliveryNotifierLabel, '미리보기');
        expect(plain.pendingDeliveryNotice, isNull, reason: '기다리는 동안 중간 표시는 없다');
        async.elapse(deliverySmsRelayWait);
        async.flushMicrotasks();
        expect(plain.pendingDeliveryNotice?.result.sent, isFalse);
        expect(plain.pendingDeliveryNotice?.result.detail, deliverySmsNoReplyDetail);
        plain.dispose();
      });
    });
  });

  // 2026-10-10 사용자 결정(웹 배송 문자 A안): 로봇이 배송지 도착에 표시를 싣고, 관리자 유심
  // 폰이 누가 보낸 배송이든 문자를 보낸다. 팝업은 배송을 보낸 화면에만, 지금과 같은 모양으로.
  group('웹 배송 문자', () {
    const stamp = '2026-10-10T10:00:00';
    Map<String, Object?> arrival({String at = stamp}) =>
        goalEvent('goal_succeeded', delivery: true, stamp: at);
    Map<String, Object?> relayed({String at = stamp, bool sent = true}) => {
          'map_id': 'm1',
          'location_id': _office.locationId,
          'arrival': at,
          'sent': sent,
          'detail': sent ? '관리자 폰에서 보냈다' : '통신사 확인 없음',
        };
    void injectOffice() => provider.handleLocationListForTest({
          'map_id': 'm1',
          'locations': [_office.toJson()],
        });

    test('문자를 못 보내는 화면의 배송은 유심 폰이 알린 결과로 지금과 같은 팝업을 띄운다', () async {
      notifier.canSendNow = false;
      provider.setDeliveryForTest(driving());
      provider.handleGoalEventForTest(arrival());
      await Future<void>.delayed(Duration.zero);
      expect(provider.pendingDeliveryNotice, isNull);
      provider.handleDeliverySmsResultForTest(relayed());
      await Future<void>.delayed(Duration.zero);
      expect(notifier.calls, 0, reason: '이 화면은 직접 보내지 않는다');
      expect(provider.pendingDeliveryNotice?.result.sent, isTrue);
      expect(provider.pendingDeliveryNotice?.result.detail, '관리자 폰에서 보냈다');
      expect(provider.pendingDeliveryNotice?.job.destination.name, '305호');
    });

    test('유심 폰의 실패도 그 사유 그대로 빨간 팝업이 된다', () async {
      notifier.canSendNow = false;
      provider.setDeliveryForTest(driving());
      provider.handleGoalEventForTest(arrival());
      await Future<void>.delayed(Duration.zero);
      provider.handleDeliverySmsResultForTest(relayed(sent: false));
      await Future<void>.delayed(Duration.zero);
      expect(provider.pendingDeliveryNotice?.result.sent, isFalse);
      expect(provider.pendingDeliveryNotice?.result.detail, '통신사 확인 없음');
    });

    test('결과가 기다림보다 먼저 와도 쓴다', () async {
      notifier.canSendNow = false;
      provider.setDeliveryForTest(driving());
      provider.handleDeliverySmsResultForTest(relayed());
      provider.handleGoalEventForTest(arrival());
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(provider.pendingDeliveryNotice?.result.sent, isTrue);
    });

    test('다른 도착의 결과는 쓰지 않는다 — 30초 뒤 안 간 것으로 알린다', () {
      fakeAsync((async) {
        notifier.canSendNow = false;
        provider.setDeliveryForTest(driving());
        provider.handleGoalEventForTest(arrival());
        async.flushMicrotasks();
        provider.handleDeliverySmsResultForTest(relayed(at: '2026-10-10T09:00:00'));
        async.elapse(deliverySmsRelayWait);
        async.flushMicrotasks();
        expect(provider.pendingDeliveryNotice?.result.sent, isFalse);
        expect(provider.pendingDeliveryNotice?.result.detail, deliverySmsNoReplyDetail);
      });
    });

    test('유심 폰은 다른 화면이 보낸 배송의 도착 문자를 대신 보낸다 — 팝업은 없다', () async {
      injectOffice();
      provider.handleGoalEventForTest(arrival());
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(notifier.calls, 1);
      expect(notifier.lastPhone, '01012345678');
      expect(notifier.lastText, contains('305호'));
      expect(provider.pendingDeliveryNotice, isNull, reason: '팝업은 배송을 보낸 화면에만');
    });

    test('같은 도착이 두 번 와도 대신 보내기는 한 번이다', () async {
      injectOffice();
      provider.handleGoalEventForTest(arrival());
      provider.handleGoalEventForTest(arrival());
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(notifier.calls, 1);
    });

    test('문자를 못 보내는 기기는 대신 보내기에 끼지 않는다', () async {
      notifier.canSendNow = false;
      injectOffice();
      provider.handleGoalEventForTest(arrival());
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(notifier.calls, 0);
    });

    test('배송 표시가 없는 도착(안내 주행)은 대신 보내지 않는다', () async {
      injectOffice();
      provider.handleGoalEventForTest(goalEvent('goal_succeeded', stamp: stamp));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(notifier.calls, 0);
    });

    test('내 배송의 도착이면 지금처럼 한 번만 보낸다(대신 보내기와 겹치지 않는다)', () async {
      injectOffice();
      provider.setDeliveryForTest(driving());
      provider.handleGoalEventForTest(arrival());
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(notifier.calls, 1);
      expect(provider.pendingDeliveryNotice?.result.sent, isTrue);
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
  group('복귀 중 일반 이벤트 (2026-09-03)', () {
    DeliveryJob returning() => driving().copyWith(phase: DeliveryPhase.returning);

    // 앱 '복귀 취소'는 미션의 on_app_cancel 을 거쳐 goal_canceled 로 온다.
    // 홈 이름만 기다리면 카드가 '홈 복귀 중'에 영영 남는다.
    for (final kind in ['goal_canceled', 'emergency_stopped', 'goal_rejected', 'state_idle']) {
      test('$kind 도 복귀 중단으로 받아 도착 상태로 되돌린다', () {
        provider.setDeliveryForTest(returning());
        provider.handleGoalEventForTest(
          goalEvent(kind, locationId: '__home__', name: '홈', reason: '관리자 취소'),
        );
        expect(provider.delivery?.phase, DeliveryPhase.arrived, reason: kind);
        expect(provider.delivery?.returnNote, isNotEmpty);
        expect(notifier.calls, 0, reason: '복귀 중단에 문자는 없다');
      });
    }

    test('복귀 중 일시정지·재출발 이벤트는 단계를 바꾸지 않는다', () {
      provider.setDeliveryForTest(returning());
      provider.handleGoalEventForTest(goalEvent('goal_paused', locationId: '__home__', name: '홈'));
      expect(provider.delivery?.phase, DeliveryPhase.returning);
      expect(provider.navigationPaused, isTrue);
      provider.handleGoalEventForTest(goalEvent('goal_accepted', locationId: '__home__', name: '홈'));
      expect(provider.delivery?.phase, DeliveryPhase.returning);
      expect(provider.navigationPaused, isFalse);
    });
  });

  group('저장과 이어받기 (2026-09-03)', () {
    test('배송 기억이 바뀔 때마다 저장소에 적히고, 지우면 비운다', () async {
      provider.setDeliveryForTest(driving());
      expect(store.job?.phase, DeliveryPhase.driving);
      provider.handleGoalEventForTest(goalEvent('goal_succeeded'));
      await Future<void>.delayed(Duration.zero);
      expect(store.job?.phase, DeliveryPhase.arrived);
      expect(store.job?.notified, isTrue);
      provider.cancelDeliveryReturn();
      provider.clearDelivery();
      expect(store.job, isNull);
    });

    test('배송 중이었고 로봇이 아직 그 목적지로 가면 그대로 잇는다', () async {
      final restored = SupervisorProvider(
        deliveryJobStore: MemoryDeliveryJobStore(driving()),
      );
      addTearDown(restored.dispose);
      await restored.restoreDelivery();
      expect(restored.delivery?.phase, DeliveryPhase.driving);
      restored.handleRobotStatusForTest(robotStatus(goal: '305호'));
      expect(restored.delivery?.phase, DeliveryPhase.driving);
      // 그 뒤 도착 이벤트는 평소처럼 받는다.
      restored.handleGoalEventForTest(goalEvent('goal_succeeded'));
      expect(restored.delivery?.phase, DeliveryPhase.arrived);
    });

    test('배송 중이었는데 로봇이 아무 데도 안 가면 확인 필요로 두고 문자는 안 보낸다', () async {
      final counting = _CountingNotifier();
      final restored = SupervisorProvider(
        deliveryJobStore: MemoryDeliveryJobStore(driving()),
        deliveryNotifier: counting,
      );
      addTearDown(restored.dispose);
      await restored.restoreDelivery();
      restored.handleRobotStatusForTest(robotStatus());
      expect(restored.delivery?.phase, DeliveryPhase.unconfirmed);
      expect(restored.delivery?.abortReason, contains('꺼진 사이'));
      expect(counting.calls, 0);
      // 새 배송은 막히고, 지우기는 된다.
      final message = await restored.startDelivery(const AppSettings(), _office);
      expect(message, contains('끝나지 않았습니다'));
      restored.clearDelivery();
      expect(restored.delivery, isNull);
    });

    test('확인 필요를 도착 처리하면 문자를 한 번 보내고 복귀 시계를 건다', () async {
      final counting = _CountingNotifier();
      final restored = SupervisorProvider(
        deliveryJobStore: MemoryDeliveryJobStore(
          driving().copyWith(phase: DeliveryPhase.unconfirmed),
        ),
        deliveryNotifier: counting,
      );
      addTearDown(restored.dispose);
      await restored.restoreDelivery();
      final message = await restored.confirmDeliveryArrival();
      await Future<void>.delayed(Duration.zero);
      expect(message, contains('도착으로 처리'));
      expect(restored.delivery?.phase, DeliveryPhase.arrived);
      expect(restored.delivery?.isWaitingToReturn, isTrue);
      expect(counting.calls, 1);
      // 이미 보냈다는 표시가 있으면 두 번 안 보낸다.
      final again = SupervisorProvider(
        deliveryJobStore: MemoryDeliveryJobStore(
          driving().copyWith(phase: DeliveryPhase.unconfirmed, notified: true),
        ),
        deliveryNotifier: counting,
      );
      addTearDown(again.dispose);
      await again.restoreDelivery();
      await again.confirmDeliveryArrival();
      await Future<void>.delayed(Duration.zero);
      expect(counting.calls, 1);
      expect(again.delivery?.phase, DeliveryPhase.arrived);
    });

    test('도착 뒤 복귀 예정이 남아 있으면 남은 시간만큼만 다시 잰다', () {
      fakeAsync((async) {
        final restored = SupervisorProvider(
          deliveryJobStore: MemoryDeliveryJobStore(driving().copyWith(
            phase: DeliveryPhase.arrived,
            notified: true,
            returnAt: DateTime.now().add(const Duration(seconds: 30)),
          )),
        );
        restored.restoreDelivery();
        async.flushMicrotasks();
        expect(restored.delivery?.isWaitingToReturn, isTrue);

        async.elapse(const Duration(seconds: 20));
        expect(restored.delivery?.isWaitingToReturn, isTrue, reason: '아직 10초 남음');

        async.elapse(const Duration(seconds: 12));
        async.flushMicrotasks();
        // 연결이 없어 거부되지만, 시계가 울렸다는 증거로 예정이 지워지고 사유가 남는다.
        expect(restored.delivery?.returnAt, isNull);
        expect(restored.delivery?.returnNote, contains('연결'));
        restored.dispose();
      });
    });

    test('복귀 예정 시각이 이미 지났으면 움직이지 않고 관리자에게 맡긴다', () {
      fakeAsync((async) {
        final restored = SupervisorProvider(
          deliveryJobStore: MemoryDeliveryJobStore(driving().copyWith(
            phase: DeliveryPhase.arrived,
            notified: true,
            returnAt: DateTime.now().subtract(const Duration(minutes: 5)),
          )),
        );
        restored.restoreDelivery();
        async.flushMicrotasks();
        expect(restored.delivery?.phase, DeliveryPhase.arrived);
        expect(restored.delivery?.returnAt, isNull);
        expect(restored.delivery?.returnNote, contains('지났습니다'));
        async.elapse(deliveryReturnDelay * 2);
        async.flushMicrotasks();
        expect(restored.delivery?.returnNote, contains('지났습니다'), reason: '시계가 안 돈다');
        restored.dispose();
      });
    });

    test('복귀 중이었는데 로봇이 서 있으면 도착 상태로 되돌린다', () async {
      final restored = SupervisorProvider(
        deliveryJobStore: MemoryDeliveryJobStore(
          driving().copyWith(phase: DeliveryPhase.returning),
        ),
      );
      addTearDown(restored.dispose);
      await restored.restoreDelivery();
      restored.handleRobotStatusForTest(robotStatus());
      expect(restored.delivery?.phase, DeliveryPhase.arrived);
      expect(restored.delivery?.returnNote, contains('꺼진 사이'));
    });

    test('끝난 배송은 그대로 되살아나고 대조하지 않는다', () async {
      final restored = SupervisorProvider(
        deliveryJobStore: MemoryDeliveryJobStore(
          driving().copyWith(phase: DeliveryPhase.completed),
        ),
      );
      addTearDown(restored.dispose);
      await restored.restoreDelivery();
      restored.handleRobotStatusForTest(robotStatus(goal: '엉뚱한 곳'));
      expect(restored.delivery?.phase, DeliveryPhase.completed);
    });

    test('저장된 것이 없으면 아무 일도 없다', () async {
      final fresh = SupervisorProvider(deliveryJobStore: MemoryDeliveryJobStore());
      addTearDown(fresh.dispose);
      await fresh.restoreDelivery();
      expect(fresh.delivery, isNull);
    });
  });
}
