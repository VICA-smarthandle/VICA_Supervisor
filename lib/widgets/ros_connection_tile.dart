// 이 파일은 ROS 연결 상태를 보여주고 연결·해제를 시키는 공통 위젯을 제공합니다.
//
// 왜 공통으로 두는가 — 연결은 원래 앱 전체에 하나입니다. main.dart 가
// SupervisorProvider 를 앱 최상위에 등록하므로, 화면마다 따로 연결하는 것이 아니라
// 같은 연결을 여러 곳에서 보여주는 것입니다. 그래서 각 화면이 콜백을 위로 올릴
// 이유가 없고, 이 위젯이 provider 를 직접 읽습니다.
//
// 비유하면 아파트 인터폰입니다. 로비에서 눌러도 집 안에서 눌러도 같은 회선입니다.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/layout_breakpoints.dart';
import '../providers/settings_provider.dart';
import '../providers/supervisor_provider.dart';
import '../ros/ros_bridge_client.dart';
import 'vica_ui.dart';

/// 대시보드의 연결 버튼과 같은 모양입니다. 다른 화면도 이것을 씁니다.
class VicaRosConnectionButton extends StatelessWidget {
  const VicaRosConnectionButton({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    final supervisor = context.watch<SupervisorProvider>();
    final connected =
        supervisor.connectionState == RosConnectionState.connected;

    return OutlinedButton.icon(
      onPressed: connected
          ? supervisor.disconnect
          : () => supervisor.connect(settings),
      icon: Icon(
        connected ? Icons.check_circle : Icons.radio_button_unchecked,
      ),
      label: Text(connected ? 'ROS 연결됨' : 'ROS 연결'),
    );
  }
}

/// 상태 점 + 주소 + 버튼을 한 줄에 담은 형태입니다.
/// 모드 선택 화면과 매핑 준비 확인처럼 "연결이 전제인 화면" 맨 위에 둡니다.
class VicaRosConnectionTile extends StatelessWidget {
  const VicaRosConnectionTile({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    final supervisor = context.watch<SupervisorProvider>();
    final state = supervisor.connectionState;
    final connected = state == RosConnectionState.connected;
    final connecting = state == RosConnectionState.connecting;

    // 주소를 바꿔 저장해도 이미 맺은 연결은 옛 주소 그대로입니다. 그대로 두면
    // "연결됨"이라 적힌 채 새 주소가 보여 사람이 헷갈립니다.
    final stale = connected &&
        supervisor.connectedUrl.isNotEmpty &&
        supervisor.connectedUrl != settings.rosBridgeUrl;

    final color = connected
        ? VicaColors.green
        : (connecting ? VicaColors.primary : VicaColors.muted);
    final label = switch (state) {
      RosConnectionState.connected => 'ROS 연결됨',
      RosConnectionState.connecting => '연결 중',
      RosConnectionState.failed => '연결 실패',
      RosConnectionState.disconnected => 'ROS 연결 안 됨',
    };

    return VicaCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final status = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      settings.rosBridgeUrl,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: VicaColors.muted,
                        fontSize: 12,
                      ),
                    ),
                    if (stale)
                      Text(
                        '주소가 바뀌었습니다. 지금 연결은 '
                        '${supervisor.connectedUrl} 입니다 — 다시 연결하세요.',
                        style: const TextStyle(
                          color: VicaColors.red,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );

          if (VicaBreakpoints.isCompact(constraints.maxWidth)) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                status,
                const SizedBox(height: 10),
                const VicaRosConnectionButton(),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: status),
              const SizedBox(width: 12),
              const VicaRosConnectionButton(),
            ],
          );
        },
      ),
    );
  }
}
