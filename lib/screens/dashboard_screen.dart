// 이 파일은 ROS 연결, 지도 연결, 로봇 요약, 최근 알림을 카드형 대시보드로 보여줍니다.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/robot_status.dart';
import '../providers/settings_provider.dart';
import '../providers/supervisor_provider.dart';
import '../ros/ros_bridge_client.dart';
import '../widgets/vica_ui.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

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
    // 카드 라벨이 '오류/긴급 정지'인데 /robot_status에는 E-stop이 담기지 않습니다.
    // 중앙 래치가 활성이면 로봇 진단에 오류가 없어도 최소 1건으로 셉니다.
    final emergencyActive =
        supervisor.emergencyStopState == EmergencyStopState.active;
    final errors =
        emergencyActive && errorRobots == 0 ? 1 : errorRobots;
    // 오류로 잡힌 로봇이 대기 수에 중복으로 들어가지 않게 제외합니다.
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
        // Flutter는 공백에서만 줄을 나눠 '오류/긴급' + '정지'로 갈라지므로
        // 의미 단위가 유지되도록 개행 위치를 직접 지정합니다.
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
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: connected
                    ? supervisor.disconnect
                    : () => supervisor.connect(settings),
                icon: Icon(
                  connected ? Icons.check_circle : Icons.radio_button_unchecked,
                ),
                label: Text(connected ? 'ROS 연결됨' : 'ROS 연결'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: connected
                    ? () => supervisor.requestMapList(settings)
                    : null,
                icon: Icon(
                  supervisor.maps.isEmpty
                      ? Icons.radio_button_unchecked
                      : Icons.check_circle,
                ),
                label: Text(
                  supervisor.maps.isEmpty ? '지도 미연결' : '지도 연결됨',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columnCount = constraints.maxWidth >= 720 ? 4 : 2;
                return GridView.builder(
                  itemCount: metricCards.length,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columnCount,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 4,
                    mainAxisExtent: 116,
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
