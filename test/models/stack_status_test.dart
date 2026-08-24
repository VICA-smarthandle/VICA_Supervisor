// 중복 실행 판정 규칙을 고정합니다.
//
// 이 판정이 틀리면 두 가지 중 하나가 됩니다 — 멀쩡한데 못 들어가거나(짜증),
// 충돌 중인데 들여보내거나(회차 유실). 뒤쪽이 훨씬 비싸므로 애매하면 막는 쪽입니다.
import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/models/stack_status.dart';

StackStatus status({
  List<String> nodes = const [],
  List<String> odomPublishers = const [],
}) {
  return StackStatus(
    nodes: nodes,
    odomPublishers: odomPublishers,
    checkedAt: DateTime(2026, 8, 21),
  );
}

void main() {
  group('StackStatus', () {
    test('아무것도 없으면 idle 이다', () {
      final s = status(nodes: ['/rosapi', '/rosbridge_websocket']);
      expect(s.nav2Running, isFalse);
      expect(s.mappingRunning, isFalse);
      expect(s.duplicated, isFalse);
      expect(s.idle, isTrue);
    });

    test('nav2 노드가 하나만 있어도 Nav2 로 본다', () {
      // lifecycle 관리 대상이라 부분 기동도 '떠 있다'로 보는 것이 안전하다.
      expect(status(nodes: ['/amcl']).nav2Running, isTrue);
      expect(status(nodes: ['/bt_navigator']).nav2Running, isTrue);
      expect(status(nodes: ['/planner_server']).nav2Running, isTrue);
    });

    test('cartographer 가 있으면 매핑으로 본다', () {
      expect(status(nodes: ['/cartographer_node']).mappingRunning, isTrue);
      expect(status(nodes: ['/occupancy_grid_node']).mappingRunning, isTrue);
    });

    test('공유 노드만으로는 어느 쪽인지 가르지 않는다', () {
      // EKF·encoder 는 두 스택이 함께 쓰므로 판정 근거가 될 수 없다.
      final s = status(nodes: ['/ekf_filter_node', '/encoder_feedback']);
      expect(s.nav2Running, isFalse);
      expect(s.mappingRunning, isFalse);
    });

    test('Nav2 와 매핑이 함께 있으면 종류 충돌이다', () {
      final s = status(nodes: ['/amcl', '/cartographer_node']);
      expect(s.conflicting, isTrue);
      expect(s.idle, isFalse);
    });

    test('같은 노드 이름이 두 번이면 두 벌로 본다', () {
      // 2026-08-11 20:07 에 이것으로 매핑 두 회차를 잃었다.
      final s = status(
        nodes: ['/ekf_filter_node', '/cartographer_node', '/ekf_filter_node'],
      );
      expect(s.duplicated, isTrue);
      expect(s.duplicatedNodeNames, ['/ekf_filter_node']);
    });

    test('/odom 발행자가 둘이면 이름이 안 겹쳐도 두 벌로 본다', () {
      // 그래프가 같은 이름을 어떻게 돌려주는지에 기대지 않는다.
      final s = status(
        nodes: ['/cartographer_node'],
        odomPublishers: ['/ekf_filter_node', '/ekf_filter_node_2'],
      );
      expect(s.duplicated, isTrue);
    });

    test('발행자가 하나면 두 벌이 아니다', () {
      final s = status(
        nodes: ['/cartographer_node'],
        odomPublishers: ['/ekf_filter_node'],
      );
      expect(s.duplicated, isFalse);
    });
  });
}
