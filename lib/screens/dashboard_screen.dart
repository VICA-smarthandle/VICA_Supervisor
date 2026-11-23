import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/layout_breakpoints.dart';
import '../models/robot_status.dart';
import '../providers/settings_provider.dart';
import '../providers/supervisor_provider.dart';
import '../ros/ros_bridge_client.dart';
import '../widgets/drive_map_change.dart';
import '../widgets/drive_nodes_card.dart';
import '../widgets/health_banner.dart';
import '../widgets/ros_connection_tile.dart';
import '../widgets/vica_ui.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, this.onOpenDiagnostics});

  /// 상단 배너를 탭하면 시스템 진단 화면으로 보냅니다.
  final VoidCallback? onOpenDiagnostics;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    final supervisor = context.watch<SupervisorProvider>();
    final connected =
        supervisor.connectionState == RosConnectionState.connected;
    final robots = supervisor.robots;
    final moving = robots.where((robot) => robot.status == 'moving').length;
    final errorRobots = robots.where((robot) => robot.hasError).length;
    final emergencyActive =
        supervisor.emergencyStopState == EmergencyStopState.active;
    final errors = emergencyActive && errorRobots == 0 ? 1 : errorRobots;
    final waiting = robots
        .where((robot) => robot.status != 'moving' && !robot.hasError)
        .length;
    final robot = supervisor.primaryRobot ?? _waitingRobot();
    final counts = [
      VicaCount(
        label: '로봇',
        value: robots.length.toString(),
        accent: VicaColors.primary,
      ),
      VicaCount(
        label: '운행',
        value: moving.toString(),
        accent: VicaColors.green,
      ),
      VicaCount(
        label: '대기',
        value: waiting.toString(),
        accent: VicaColors.warning,
      ),
      VicaCount(
        label: '오류',
        value: errors.toString(),
        color: errors == 0 ? VicaColors.green : VicaColors.red,
        accent: errors == 0 ? VicaColors.textTertiary : VicaColors.red,
      ),
    ];

    return VicaPage(
      children: [
        if (!connected)
          VicaDisconnectedNotice(detail: supervisor.connectionDetail),
        HealthBanner(onTap: onOpenDiagnostics),
        const DriveMapMismatchCard(),
        const DriveNodesCard(),
        _ConnectionButtons(
          hasMaps: supervisor.maps.isNotEmpty,
          onRequestMaps:
              connected ? () => supervisor.requestMapList(settings) : null,
        ),
        const SizedBox(height: 18),
        VicaCountStrip(items: counts),
        const VicaSectionTitle('로봇'),
        VicaRobotCard(robot: robot),
        const VicaSectionTitle('알림'),
        if (supervisor.logs.isEmpty)
          const VicaCard(child: Text('최근 알림이 없습니다.'))
        else
          ...supervisor.logs.take(3).map((log) => VicaLogTile(log: log)),
      ],
    );
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
      timestamp: DateTime.now().subtract(const Duration(minutes: 1)),
    );
  }
}

class _ConnectionButtons extends StatelessWidget {
  const _ConnectionButtons({
    required this.hasMaps,
    required this.onRequestMaps,
  });

  final bool hasMaps;
  final VoidCallback? onRequestMaps;

  @override
  Widget build(BuildContext context) {
    const rosButton = VicaRosConnectionButton();
    final mapButton = PressScale(
        child: OutlinedButton.icon(
      onPressed: onRequestMaps,
      icon: Icon(
        hasMaps ? Icons.check_circle : Icons.radio_button_unchecked,
      ),
      label: Text(hasMaps ? '지도 연결됨' : '지도 미연결'),
    ));

    return LayoutBuilder(
      builder: (context, constraints) {
        if (VicaBreakpoints.isCompact(constraints.maxWidth)) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              rosButton,
              const SizedBox(height: 10),
              mapButton,
            ],
          );
        }
        return Row(
          children: [
            const Expanded(child: rosButton),
            const SizedBox(width: 10),
            Expanded(child: mapButton),
          ],
        );
      },
    );
  }
}
