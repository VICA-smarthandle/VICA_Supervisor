import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/core/fault_severity.dart';
import 'package:vica_supervisor/models/robot_event.dart';
import 'package:vica_supervisor/models/robot_health.dart';

const _healthPayload = r'''
{"header":{"stamp":{"sec":1785467841,"nanosec":401827224},"frame_id":""},"state":3,"motor_readiness":1,"safety_readiness":1,"localization_readiness":0,"navigation_readiness":0,"lidar_readiness":0,"perception_readiness":0,"guidance_readiness":0,"voice_readiness":0,"app_readiness":0,"active_fault_count":3,"highest_severity":3,"primary_fault_code":"DIAG_COMPONENT_STALE","active_faults":[{"component":"motor","fault_code":"DIAG_COMPONENT_STALE","severity":3,"active":true,"latched":false,"occurrence_count":1,"first_seen":{"sec":1785467841,"nanosec":400926351},"last_seen":{"sec":1785467841,"nanosec":400926351},"detail":"진단 항목이 보고되지 않았습니다.","suggested_action":"해당 노드 실행 상태를 확인해 주세요."},{"component":"safety","fault_code":"DIAG_COMPONENT_STALE","severity":3,"active":true,"latched":false,"occurrence_count":1,"first_seen":{"sec":1785467841,"nanosec":400926351},"last_seen":{"sec":1785467841,"nanosec":400926351},"detail":"진단이 갱신되지 않았습니다.","suggested_action":"해당 노드 실행 상태를 확인해 주세요."},{"component":"safety","fault_code":"SAFETY_STATE_STALE","severity":3,"active":true,"latched":false,"occurrence_count":1,"first_seen":{"sec":1785467841,"nanosec":400926351},"last_seen":{"sec":1785467841,"nanosec":400926351},"detail":"Safety 상태를 한 번도 수신하지 못했습니다.","suggested_action":"safety_supervisor_node 실행 상태를 확인해 주세요."}]}''';

const _eventPayload = r'''
{"header":{"stamp":{"sec":1785467841,"nanosec":401351098},"frame_id":""},"fault":{"component":"motor","fault_code":"DIAG_COMPONENT_STALE","severity":3,"active":true,"latched":false,"occurrence_count":1,"first_seen":{"sec":1785467841,"nanosec":400926351},"last_seen":{"sec":1785467841,"nanosec":400926351},"detail":"진단 항목이 보고되지 않았습니다.","suggested_action":"해당 노드 실행 상태를 확인해 주세요."},"transition":0}''';

Map<String, Object?> _decode(String raw) =>
    jsonDecode(raw.trim()) as Map<String, Object?>;

void main() {
  group('rosbridge 실측 payload', () {
    test('RobotHealth가 필드 손실 없이 파싱된다', () {
      final health = RobotHealth.fromRosMsg(_decode(_healthPayload));

      expect(health.state, RobotHealthState.stopped);
      expect(health.activeFaults.every((f) => !f.latched), isTrue);
      expect(health.highestSeverity, FaultSeverity.stop);
      expect(health.activeFaultCount, 3);
      expect(health.activeFaults, hasLength(3));
      expect(health.primaryFaultCode, 'DIAG_COMPONENT_STALE');
    });

    test('중첩 배열 active_faults의 각 항목이 모두 살아 있다', () {
      final health = RobotHealth.fromRosMsg(_decode(_healthPayload));

      expect(
        health.activeFaults.map((f) => f.component).toList(),
        ['motor', 'safety', 'safety'],
      );
      for (final fault in health.activeFaults) {
        expect(fault.faultCode, isNotEmpty);
        expect(fault.detail, isNotEmpty);
        expect(fault.suggestedAction, isNotEmpty);
      }
    });

    test('한국어 문구가 깨지지 않는다', () {
      final health = RobotHealth.fromRosMsg(_decode(_healthPayload));
      final motor = health.activeFaults.first;

      expect(motor.detail, '진단 항목이 보고되지 않았습니다.');
      expect(motor.suggestedAction, '해당 노드 실행 상태를 확인해 주세요.');
    });

    test('영문 요약어가 문구로 새지 않는다', () {
      final health = RobotHealth.fromRosMsg(_decode(_healthPayload));
      const leaked = {'missing', 'stale', 'error', 'warning', 'ok'};

      for (final fault in health.activeFaults) {
        expect(leaked.contains(fault.detail.trim().toLowerCase()), isFalse,
            reason: fault.detail);
        expect(fault.detail, isNot(contains('{')));
        expect(fault.detail, isNot(contains('?')));
      }
    });

    test('{sec, nanosec} 시각이 DateTime으로 바뀐다', () {
      final health = RobotHealth.fromRosMsg(_decode(_healthPayload));
      final fault = health.activeFaults.first;

      expect(fault.firstSeen.year, greaterThan(2020));
      expect(fault.lastSeen.year, greaterThan(2020));
      expect(fault.duration.inMilliseconds, greaterThanOrEqualTo(0));
    });

    test('9개 readiness가 모두 매핑된다', () {
      final health = RobotHealth.fromRosMsg(_decode(_healthPayload));

      expect(health.readiness, hasLength(9));
      expect(health.readiness['guidance'], ComponentReadiness.unknown);
      expect(health.readiness['voice'], ComponentReadiness.unknown);
      expect(health.readiness['app'], ComponentReadiness.unknown);
      expect(health.unobservableComponents, isNotEmpty);
    });

    test('RobotEvent가 중첩 fault까지 파싱된다', () {
      final event = RobotEvent.fromRosMsg(_decode(_eventPayload), id: 'x');

      expect(event.transition, FaultTransition.raised);
      expect(event.fault.component, 'motor');
      expect(event.fault.severity, FaultSeverity.stop);
      expect(event.fault.detail, isNotEmpty);
      expect(event.belongsInHistory, isTrue);
    });
  });
}
