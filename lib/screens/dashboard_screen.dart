import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/layout_breakpoints.dart';
import '../models/robot_status.dart';
import '../providers/settings_provider.dart';
import '../providers/supervisor_provider.dart';
import '../ros/ros_bridge_client.dart';
import '../widgets/health_banner.dart';
import '../widgets/vica_ui.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, this.onOpenDiagnostics});

  /// 상단 배너를 탭하면 시스템 진단 화면으로 보냅니다.
  final VoidCallback? onOpenDiagnostics;

  static const double metricLabelFontSize = 14;
  static const double errorMetricLabelFontSize = 12;

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
    final metricCards = [
      VicaMetricCard(
        icon: Icons.smart_toy,
        label: '전체 로봇',
        value: robots.length.toString(),
        color: VicaColors.primaryDark,
        labelFontSize: metricLabelFontSize,
      ),
      VicaMetricCard(
        icon: Icons.navigation,
        label: '운행 중',
        value: moving.toString(),
        color: VicaColors.green,
        labelFontSize: metricLabelFontSize,
      ),
      VicaMetricCard(
        icon: Icons.hourglass_empty,
        label: '대기 중',
        value: waiting.toString(),
        color: Colors.blueAccent,
        labelFontSize: metricLabelFontSize,
      ),
      VicaMetricCard(
        icon: Icons.warning,
        label: '오류/\n긴급 정지',
        value: errors.toString(),
        color: VicaColors.red,
        labelMaxLines: 2,
        labelFontSize: errorMetricLabelFontSize,
      ),
    ];

    return VicaPage(
      title: '로봇 현황',
      children: [
        if (!connected)
          VicaDisconnectedNotice(detail: supervisor.connectionDetail),
        HealthBanner(onTap: onOpenDiagnostics),
        _ConnectionButtons(
          connected: connected,
          hasMaps: supervisor.maps.isNotEmpty,
          onToggleRos: connected
              ? supervisor.disconnect
              : () => supervisor.connect(settings),
          onRequestMaps:
              connected ? () => supervisor.requestMapList(settings) : null,
        ),
        const SizedBox(height: 18),
        Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: VicaBreakpoints.metricGridMaxWidth,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columnCount =
                    constraints.maxWidth >= VicaBreakpoints.metricGridWide
                        ? 4
                        : 2;
                final cellHeight = MediaQuery.textScalerOf(context)
                    .scale(VicaMetricCard.baseHeight);
                return GridView.builder(
                  itemCount: metricCards.length,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columnCount,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 4,
                    mainAxisExtent: cellHeight,
                  ),
                  itemBuilder: (context, index) => metricCards[index],
                );
              },
            ),
          ),
        ),
        const VicaSectionTitle('로봇 상태'),
        VicaRobotCard(robot: robot),
        const VicaSectionTitle('최근 알림'),
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
    required this.connected,
    required this.hasMaps,
    required this.onToggleRos,
    required this.onRequestMaps,
  });

  final bool connected;
  final bool hasMaps;
  final VoidCallback onToggleRos;
  final VoidCallback? onRequestMaps;

  @override
  Widget build(BuildContext context) {
    final rosButton = OutlinedButton.icon(
      onPressed: onToggleRos,
      icon: Icon(
        connected ? Icons.check_circle : Icons.radio_button_unchecked,
      ),
      label: Text(connected ? 'ROS 연결됨' : 'ROS 연결'),
    );
    final mapButton = OutlinedButton.icon(
      onPressed: onRequestMaps,
      icon: Icon(
        hasMaps ? Icons.check_circle : Icons.radio_button_unchecked,
      ),
      label: Text(hasMaps ? '지도 연결됨' : '지도 미연결'),
    );

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
            Expanded(child: rosButton),
            const SizedBox(width: 10),
            Expanded(child: mapButton),
          ],
        );
      },
    );
  }
}
