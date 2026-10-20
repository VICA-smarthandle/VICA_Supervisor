class StackStatus {
  const StackStatus({
    required this.nodes,
    required this.odomPublishers,
  });

  /// /rosapi/nodes 가 돌려준 노드 이름 전체. 같은 이름이 두 번 들어 있을 수 있고,
  final List<String> nodes;

  /// /rosapi/publishers 로 조회한 /odom 발행자 이름. 2개 이상이면 ㉯ 다.
  final List<String> odomPublishers;

  /// Nav2 를 대표하는 노드들. lifecycle 관리 대상이라 하나라도 있으면 Nav2 가 떴다고 본다.
  static const nav2Nodes = <String>[
    '/amcl',
    '/bt_navigator',
    '/controller_server',
    '/planner_server',
  ];

  /// 매핑을 대표하는 노드들. Cartographer 쪽만 본다 — EKF·encoder 는 두 스택이
  static const mappingNodes = <String>[
    '/cartographer_node',
    '/occupancy_grid_node',
  ];

  bool get nav2Running => nav2Nodes.any(nodes.contains);

  bool get mappingRunning => mappingNodes.any(nodes.contains);

  /// ㉮ 종류 충돌.
  bool get conflicting => nav2Running && mappingRunning;

  /// ㉯ 두 벌. 두 가지 신호 중 하나라도 걸리면 참으로 본다.
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
