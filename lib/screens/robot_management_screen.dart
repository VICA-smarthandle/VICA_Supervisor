// 이 파일은 로봇 카드 목록과 선택한 로봇의 상세 상태를 표시합니다.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/robot_status.dart';
import '../providers/supervisor_provider.dart';
import '../ros/ros_bridge_client.dart';
import '../widgets/vica_ui.dart';

class RobotManagementScreen extends StatefulWidget {
  const RobotManagementScreen({super.key});

  @override
  State<RobotManagementScreen> createState() => _RobotManagementScreenState();
}

class _RobotManagementScreenState extends State<RobotManagementScreen> {
  String? _selectedRobotId;

  @override
  Widget build(BuildContext context) {
    final supervisor = context.watch<SupervisorProvider>();
    final robots = supervisor.robots;
    final visibleRobots = robots.isEmpty ? [_waitingRobot()] : robots;
    final selected = _selectedRobotId == null
        ? visibleRobots.first
        : _findRobot(visibleRobots, _selectedRobotId!) ?? visibleRobots.first;

    return VicaPage(
      title: '로봇 관리',
      subtitle: 'ROS2 /robot_status 메시지를 수신하면 실제 로봇 상태로 교체됩니다.',
      children: [
        if (supervisor.connectionState != RosConnectionState.connected)
          VicaDisconnectedNotice(detail: supervisor.connectionDetail),
        ...visibleRobots.map(
          (robot) => VicaRobotCard(
            robot: robot,
            selected: selected.robotId == robot.robotId,
            onTap: () {
              setState(() => _selectedRobotId = robot.robotId);
              _showRobotDetail(context, robot);
            },
          ),
        ),
      ],
    );
  }

  Future<void> _showRobotDetail(BuildContext context, RobotStatus robot) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return DecoratedBox(
          decoration: const BoxDecoration(
            color: VicaColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          // 좁은 창에서는 항목이 두 줄로 접혀 시트가 길어집니다. 화면보다 길어지면
          // 아래가 잘려 '마지막 통신'을 볼 수 없으므로 시트 안에서 스크롤합니다.
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: VicaColors.muted,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text('상세 정보', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 14),
                VicaInfoRow(label: '상태', value: robot.status),
                VicaInfoRow(label: '현재 위치', value: robot.currentLocation),
                VicaInfoRow(label: '목적지', value: robot.currentGoal),
                VicaInfoRow(label: '오류 사유', value: robot.errorReason),
                VicaInfoRow(label: '대기 사유', value: robot.waitingReason),
                VicaInfoRow(
                    label: '마지막 통신',
                    value: robot.timestamp.toLocal().toString()),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  icon: const Icon(Icons.check),
                  label: const Text('확인'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  RobotStatus? _findRobot(List<RobotStatus> robots, String robotId) {
    for (final robot in robots) {
      if (robot.robotId == robotId) {
        return robot;
      }
    }
    return null;
  }

  RobotStatus _waitingRobot() {
    return RobotStatus(
      robotId: 'robot_status_waiting',
      robotName: '로봇 상태 수신 대기',
      status: 'waiting',
      x: 0,
      y: 0,
      yaw: 0,
      currentLocation: '수신 대기',
      currentGoal: '없음',
      errorReason: '',
      waitingReason: '로봇 상태 메시지 수신 대기',
      mapId: '',
      timestamp: DateTime.now().subtract(const Duration(minutes: 6)),
    );
  }
}
