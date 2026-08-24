// 이 파일은 젯슨에 지금 어떤 ROS 스택이 떠 있는지를 표현합니다.
//
// 왜 필요한가 — 중복 실행이 이 프로젝트에서 실제로 회차를 날린 사고이기 때문입니다.
// 종류가 둘이고 원인이 다릅니다.
//
//   ㉮ 종류 충돌  Nav2 와 매핑이 동시에 떠 있다.
//                둘 다 wheel_ekf.launch.py 를 include 해서 /odom 발행자가 둘이 되고
//                map->odom TF 도 충돌한다. vica_terminator_layout.py 의 vica_map
//                프로파일 설명이 "nav2 는 뺀 것이 아니라 넣으면 안 되는 것"이라고 적었다.
//
//   ㉯ 두 벌      같은 스택이 두 번 떠 있다.
//                2026-08-11 20:07 에 이것으로 매핑 두 회차를 잃었다
//                (docs/cartographer_corridor_mapping.md 3절).
//
// 판정 근거는 rosbridge 가 함께 띄우는 rosapi 노드다
// (rosbridge_websocket_launch.xml 74행). 앱의 callService 가 이미 범용이라
// 클라이언트 코드를 고치지 않고 부를 수 있다.

class StackStatus {
  const StackStatus({
    required this.nodes,
    required this.odomPublishers,
    required this.checkedAt,
  });

  /// /rosapi/nodes 가 돌려준 노드 이름 전체. 같은 이름이 두 번 들어 있을 수 있고,
  /// 그것이 ㉯ 를 잡는 신호다.
  final List<String> nodes;

  /// /rosapi/publishers 로 조회한 /odom 발행자 이름. 2개 이상이면 ㉯ 다.
  final List<String> odomPublishers;

  final DateTime checkedAt;

  /// Nav2 를 대표하는 노드들. lifecycle 관리 대상이라 하나라도 있으면 Nav2 가 떴다고 본다.
  static const nav2Nodes = <String>[
    '/amcl',
    '/bt_navigator',
    '/controller_server',
    '/planner_server',
  ];

  /// 매핑을 대표하는 노드들. Cartographer 쪽만 본다 — EKF·encoder 는 두 스택이
  /// 공유하므로 어느 쪽인지 가르지 못한다.
  static const mappingNodes = <String>[
    '/cartographer_node',
    '/occupancy_grid_node',
  ];

  /// 두 스택이 공유하는 노드들. 여기서 같은 이름이 두 번 보이면 두 벌이 도는 것이다.
  static const sharedNodes = <String>[
    '/ekf_filter_node',
    '/encoder_feedback',
  ];

  bool get nav2Running => nav2Nodes.any(nodes.contains);

  bool get mappingRunning => mappingNodes.any(nodes.contains);

  /// ㉮ 종류 충돌.
  bool get conflicting => nav2Running && mappingRunning;

  /// ㉯ 두 벌. 두 가지 신호 중 하나라도 걸리면 참으로 본다.
  ///
  /// 이름 중복과 발행자 수를 함께 보는 이유: ROS 2 그래프가 같은 이름을 어떻게
  /// 돌려주는지에 기대지 않기 위해서다. 조용히 놓치는 것보다 두 번 보는 편이 낫다.
  bool get duplicated =>
      duplicatedNodeNames.isNotEmpty || odomPublishers.length > 1;

  List<String> get duplicatedNodeNames {
    final counts = <String, int>{};
    for (final node in nodes) {
      counts[node] = (counts[node] ?? 0) + 1;
    }
    return counts.entries
        .where((entry) => entry.value > 1)
        .map((entry) => entry.key)
        .toList(growable: false);
  }

  /// 아무 스택도 안 떠 있다. 어느 모드로도 들어갈 수 있다.
  bool get idle => !nav2Running && !mappingRunning && !duplicated;
}
