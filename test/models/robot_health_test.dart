// rosbridge가 보내는 필드 map 파싱을 검증합니다.
//
// 실제 /robot/health 출력을 노트북에서 받아 그 형태를 그대로 씁니다.
import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/core/fault_severity.dart';
import 'package:vica_supervisor/models/robot_event.dart';
import 'package:vica_supervisor/models/robot_fault.dart';
import 'package:vica_supervisor/models/robot_health.dart';

Map<String, Object?> faultMsg({
  String component = 'navigation',
  String faultCode = 'NAV2_NOT_ACTIVE',
  int severity = 3,
  bool active = true,
  bool latched = false,
  int occurrenceCount = 8,
  int firstSec = 1785410054,
  int lastSec = 1785410061,
  String detail = 'Nav2가 active 상태가 아닙니다. 현재 상태: unavailable',
  String suggestedAction = 'Nav2 lifecycle 상태를 확인하고 필요하면 다시 실행해 주세요.',
}) {
  return {
    'component': component,
    'fault_code': faultCode,
    'severity': severity,
    'active': active,
    'latched': latched,
    'occurrence_count': occurrenceCount,
    'first_seen': {'sec': firstSec, 'nanosec': 370967149},
    'last_seen': {'sec': lastSec, 'nanosec': 370763540},
    'detail': detail,
    'suggested_action': suggestedAction,
  };
}

Map<String, Object?> healthMsg({
  int state = 3,
  int highestSeverity = 3,
  String primary = 'NAV2_NOT_ACTIVE',
  List<Map<String, Object?>>? faults,
  Map<String, int>? readiness,
}) {
  final levels = <String, int>{
    'motor_readiness': 2,
    'safety_readiness': 2,
    'localization_readiness': 0,
    'navigation_readiness': 1,
    'lidar_readiness': 2,
    'perception_readiness': 1,
    'guidance_readiness': 0,
    'voice_readiness': 0,
    'app_readiness': 0,
    ...?readiness,
  };
  return {
    'state': state,
    ...levels,
    'active_fault_count': (faults ?? [faultMsg()]).length,
    'highest_severity': highestSeverity,
    'primary_fault_code': primary,
    'active_faults': faults ?? [faultMsg()],
  };
}

void main() {
  group('RobotFault', () {
    test('실제 rosbridge 출력 형태를 읽는다', () {
      final fault = RobotFault.fromRosMsg(faultMsg());

      expect(fault.component, 'navigation');
      expect(fault.faultCode, 'NAV2_NOT_ACTIVE');
      expect(fault.severity, FaultSeverity.stop);
      expect(fault.active, isTrue);
      expect(fault.latched, isFalse);
      expect(fault.occurrenceCount, 8);
      expect(fault.detail, contains('unavailable'));
      expect(fault.suggestedAction, isNotEmpty);
    });

    test('builtin_interfaces/Time을 DateTime으로 바꾼다', () {
      final fault = RobotFault.fromRosMsg(faultMsg());

      expect(fault.firstSeen.millisecondsSinceEpoch, 1785410054370);
      expect(fault.lastSeen.millisecondsSinceEpoch, 1785410061370);
    });

    test('지속 시간을 계산한다', () {
      final fault = RobotFault.fromRosMsg(faultMsg());
      expect(fault.duration.inSeconds, 7);
    });

    test('lastSeen이 firstSeen보다 이르면 지속을 0으로 둔다', () {
      final fault = RobotFault.fromRosMsg(
        faultMsg(firstSec: 1785410061, lastSec: 1785410054),
      );
      expect(fault.duration, Duration.zero);
    });

    test('sec이 0이면 1970년이 아니라 현재 시각을 쓴다', () {
      final before = DateTime.now();
      final fault = RobotFault.fromRosMsg(faultMsg(firstSec: 0));

      expect(fault.firstSeen.isBefore(before.subtract(const Duration(days: 1))),
          isFalse);
    });

    test('필드가 비어도 예외를 던지지 않는다', () {
      final fault = RobotFault.fromRosMsg(const {});

      expect(fault.component, '');
      expect(fault.severity, FaultSeverity.ok);
      expect(fault.occurrenceCount, 0);
    });

    test('컴포넌트 이름을 한국어로 바꾼다', () {
      expect(
          RobotFault.fromRosMsg(faultMsg(component: 'lidar'))
              .componentLabelText,
          'LiDAR');
      expect(
          RobotFault.fromRosMsg(faultMsg(component: 'guidance'))
              .componentLabelText,
          '안내 장치');
    });

    test('모르는 컴포넌트는 원문을 그대로 보여준다', () {
      // 새 컴포넌트가 추가됐을 때 조용히 사라지면 안 됩니다.
      final fault = RobotFault.fromRosMsg(faultMsg(component: 'brand_new'));
      expect(fault.componentLabelText, 'brand_new');
    });
  });

  group('FaultSeverity', () {
    test('메시지 상수 값과 일치한다', () {
      expect(FaultSeverity.ok.value, 0);
      expect(FaultSeverity.warn.value, 1);
      expect(FaultSeverity.degraded.value, 2);
      expect(FaultSeverity.stop.value, 3);
      expect(FaultSeverity.fault.value, 4);
    });

    test('등급 축에 비상 정지가 없다', () {
      // E-stop은 STOP보다 심각한 등급이 아니라 종류가 다른 것입니다. 래치가 걸리고
      // 관리자 reset이 있어야 풀립니다. 그 사실은 RobotHealthState.estopped와
      // RobotFault.latched가 나타냅니다.
      expect(
        FaultSeverity.values.map((s) => s.code),
        isNot(contains('ESTOP')),
      );
      expect(
        FaultSeverity.values.map((s) => s.label),
        isNot(contains('비상 정지')),
      );
      // 상태 축에는 그대로 남아 있어야 합니다.
      expect(RobotHealthState.estopped.label, '비상 정지');
    });

    test('알 수 없는 값은 fault로 본다', () {
      // 조용히 ok로 떨어뜨리면 위험을 놓칩니다.
      expect(FaultSeverity.fromValue(99), FaultSeverity.fault);
      expect(FaultSeverity.fromValue(-1), FaultSeverity.fault);
    });

    test('STOP 이상이 주행을 막는 등급이다', () {
      expect(FaultSeverity.degraded.blocksDriving, isFalse);
      expect(FaultSeverity.stop.blocksDriving, isTrue);
      expect(FaultSeverity.fault.blocksDriving, isTrue);
    });
  });

  group('ComponentReadiness', () {
    test('메시지 상수 값과 일치한다', () {
      expect(ComponentReadiness.unknown.value, 0);
      expect(ComponentReadiness.notReady.value, 1);
      expect(ComponentReadiness.ready.value, 2);
    });

    test('unknown은 정상이 아니라 관측 불가로 표시한다', () {
      // READY로 표시하면 관리자에게 잘못된 안심을 줍니다.
      expect(ComponentReadiness.unknown.label, '관측 불가');
      expect(ComponentReadiness.ready.label, '정상');
    });

    test('알 수 없는 값은 unknown으로 본다', () {
      expect(ComponentReadiness.fromValue(9), ComponentReadiness.unknown);
    });
  });

  group('RobotHealth', () {
    test('실제 rosbridge 출력 형태를 읽는다', () {
      final health = RobotHealth.fromRosMsg(healthMsg());

      expect(health.state, RobotHealthState.stopped);
      expect(health.highestSeverity, FaultSeverity.stop);
      expect(health.primaryFaultCode, 'NAV2_NOT_ACTIVE');
      expect(health.activeFaults, hasLength(1));
    });

    test('readiness 필드 9개를 컴포넌트 이름으로 매핑한다', () {
      final health = RobotHealth.fromRosMsg(healthMsg());

      expect(health.readiness, hasLength(9));
      expect(health.readiness['motor'], ComponentReadiness.ready);
      expect(health.readiness['navigation'], ComponentReadiness.notReady);
      expect(health.readiness['guidance'], ComponentReadiness.unknown);
    });

    test('관측 불가 컴포넌트를 모아 보여준다', () {
      final health = RobotHealth.fromRosMsg(healthMsg());

      // 노트북 실기동에서 나온 값: localization은 grace 중, guidance/voice/app은
      // 관측 수단이 없다.
      expect(
        health.unobservableComponents,
        containsAll(<String>['guidance', 'voice', 'app']),
      );
    });

    test('대표 결함을 primary_fault_code로 찾는다', () {
      final health = RobotHealth.fromRosMsg(
        healthMsg(
          primary: 'LIDAR_SCAN_STALE',
          faults: [
            faultMsg(),
            faultMsg(component: 'lidar', faultCode: 'LIDAR_SCAN_STALE'),
          ],
        ),
      );

      expect(health.primaryFault?.faultCode, 'LIDAR_SCAN_STALE');
    });

    test('primary가 목록에 없으면 첫 항목을 대표로 쓴다', () {
      final health = RobotHealth.fromRosMsg(healthMsg(primary: 'NOT_IN_LIST'));
      expect(health.primaryFault?.faultCode, 'NAV2_NOT_ACTIVE');
    });

    test('결함이 없으면 대표도 없다', () {
      final health = RobotHealth.fromRosMsg(
        healthMsg(state: 1, highestSeverity: 0, primary: '', faults: []),
      );

      expect(health.hasFault, isFalse);
      expect(health.primaryFault, isNull);
      expect(health.state, RobotHealthState.ready);
    });

    test('만료를 판정한다', () {
      final health = RobotHealth.fromRosMsg(healthMsg());

      expect(health.isStale(const Duration(seconds: 5)), isFalse);
      expect(health.isStale(Duration.zero), isTrue);
    });

    test('빈 메시지에도 예외를 던지지 않는다', () {
      final health = RobotHealth.fromRosMsg(const {});

      expect(health.activeFaults, isEmpty);
      expect(health.readiness, hasLength(9));
      expect(health.readiness['motor'], ComponentReadiness.unknown);
    });
  });

  group('RobotEvent', () {
    test('전이 종류를 읽는다', () {
      final event = RobotEvent.fromRosMsg(
        {'fault': faultMsg(), 'transition': 0},
        id: 'a',
      );

      expect(event.transition, FaultTransition.raised);
      expect(event.fault.faultCode, 'NAV2_NOT_ACTIVE');
      expect(event.id, 'a');
    });

    test('메시지 상수 값과 일치한다', () {
      expect(FaultTransition.raised.value, 0);
      expect(FaultTransition.escalated.value, 1);
      expect(FaultTransition.reminder.value, 2);
      expect(FaultTransition.cleared.value, 3);
    });

    test('reminder는 이력에 남기지 않는다', () {
      // 같은 항목으로 목록이 가득 차는 것을 막습니다. 현재 상태는 activeFaults가
      // 보여줍니다.
      for (final transition in FaultTransition.values) {
        final event = RobotEvent.fromRosMsg(
          {'fault': faultMsg(), 'transition': transition.value},
          id: 'x',
        );
        expect(
          event.belongsInHistory,
          transition != FaultTransition.reminder,
          reason: transition.name,
        );
      }
    });

    test('알 수 없는 전이 값도 버리지 않는다', () {
      final event = RobotEvent.fromRosMsg(
        {'fault': faultMsg(), 'transition': 77},
        id: 'x',
      );
      expect(event.transition, FaultTransition.raised);
    });

    test('fault가 없어도 예외를 던지지 않는다', () {
      final event = RobotEvent.fromRosMsg(const {'transition': 3}, id: 'x');

      expect(event.transition, FaultTransition.cleared);
      expect(event.fault.component, '');
    });
  });
}
