// 이 파일은 ROS 연결, 지도 연결, 로봇 요약, 최근 알림을 카드형 대시보드로 보여줍니다.
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
    // '오류' 칸은 긴급정지도 셉니다. /robot_status에는 E-stop이 담기지 않으므로
    // 중앙 래치가 활성이면 로봇 진단에 오류가 없어도 최소 1건으로 셉니다.
    final emergencyActive =
        supervisor.emergencyStopState == EmergencyStopState.active;
    final errors = emergencyActive && errorRobots == 0 ? 1 : errorRobots;
    // 오류로 잡힌 로봇이 대기 수에 중복으로 들어가지 않게 제외합니다.
    final waiting = robots
        .where((robot) => robot.status != 'moving' && !robot.hasError)
        .length;
    final robot = supervisor.primaryRobot ?? _waitingRobot();
    // 2026-11-17 제목·문구 간결화(사용자 승인): 지표 카드 넷 → 카드 하나 안의 칸 넷. 숫자 색은
    // 오류 칸만 씁니다(0 초록·1 이상 빨강). 2026-11-18 사용자: 칸마다 은은한 바탕색·점을 넣는다.
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

    // 본문 제목('로봇 현황')은 뺐습니다 — 제목줄이 '대시보드'입니다(2026-11-17 사용자 승인).
    return VicaPage(
      children: [
        if (!connected)
          VicaDisconnectedNotice(detail: supervisor.connectionDetail),
        // 최고 등급 결함을 한 줄로 알립니다. 결함이 없으면 아무것도 그리지 않습니다.
        HealthBanner(onTap: onOpenDiagnostics),
        // 주행 노드(사람 감지 켜기·끄기, 음성 고르기). 모드 노드가 켠 주행일 때만 보입니다(2026-11-16).
        // 터미널에서 CURRENT_MAP 만 바뀌어 Nav2 와 지도가 어긋나면(2026-11-17 목업 ⑦).
        const DriveMapMismatchCard(),
        const DriveNodesCard(),
        // 좁은 창에서는 두 버튼을 나란히 두면 각 버튼이 130px까지 줄어 라벨이
        // 잘립니다. 그때는 위아래로 쌓아 문구를 그대로 보여줍니다.
        _ConnectionButtons(
          hasMaps: supervisor.maps.isNotEmpty,
          onRequestMaps:
              connected ? () => supervisor.requestMapList(settings) : null,
        ),
        const SizedBox(height: 18),
        // 다른 카드와 같은 폭으로 둡니다. 1040px 상한 때문에 넓은 웹 창에서 이 줄만 안쪽으로
        // 들어가 보였습니다(2026-11-18 사용자).
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

// ROS 연결과 지도 연결 버튼입니다. 넓으면 나란히, 좁으면 위아래로 놓습니다.
class _ConnectionButtons extends StatelessWidget {
  const _ConnectionButtons({
    required this.hasMaps,
    required this.onRequestMaps,
  });

  final bool hasMaps;
  final VoidCallback? onRequestMaps;

  @override
  Widget build(BuildContext context) {
    // 연결은 앱 전체에 하나뿐이라 버튼도 공통 위젯을 씁니다. 모드 선택 화면과
    // 매핑 준비 확인이 같은 것을 봅니다.
    const rosButton = VicaRosConnectionButton();
    final mapButton = PressScale(child: OutlinedButton.icon(
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
