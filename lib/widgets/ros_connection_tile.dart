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
class VicaRosConnectionTile extends StatelessWidget {
  const VicaRosConnectionTile({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    final supervisor = context.watch<SupervisorProvider>();
    final state = supervisor.connectionState;
    final connected = state == RosConnectionState.connected;
    final connecting = state == RosConnectionState.connecting;

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
              const SizedBox(width: 148, child: VicaRosConnectionButton()),
            ],
          );
        },
      ),
    );
  }
}
