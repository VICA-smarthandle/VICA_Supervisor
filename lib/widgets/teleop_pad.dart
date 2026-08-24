// 이 파일은 지도를 그릴 때 로봇을 끌고 다니는 조작판입니다.
//
// **반드시 누르고 있는 동안만 갑니다.** 한 번 눌러 계속 가게 만들면 안 됩니다.
// safety_supervisor_node 와 mdrobot_can_control 이 각각 cmd_timeout_sec 0.5 를
// 갖고 있어, 명령이 끊기면 0.5초 안에 두 계층이 각각 로봇을 세웁니다. 그 안전장치는
// "손을 떼면 명령이 끊긴다"를 전제로 하므로, 눌러 두고 손을 떼도 계속 가는 방식은
// 그 전제를 깨뜨립니다. 잔디깎이 손잡이와 같습니다.
//
// 속도 상한은 SupervisorProvider 가 갖고 있습니다(0.3 m/s, 0.4 rad/s).
// docs/cartographer_corridor_mapping.md 4절이 근거입니다 — 더 빠르면 스캔 사이
// 이동이 Cartographer 의 예측 탐색 창(0.1 m)에 닿아 지도가 나빠집니다.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/supervisor_provider.dart';
import 'vica_ui.dart';

class TeleopPad extends StatelessWidget {
  const TeleopPad({super.key, required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final supervisor = context.watch<SupervisorProvider>();

    return VicaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.gamepad_outlined, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '로봇 끌고 다니기',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (supervisor.teleopActive)
                const Text(
                  '이동 중',
                  style: TextStyle(
                    color: VicaColors.green,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            '버튼을 누르고 있는 동안만 움직입니다. 손을 떼면 곧바로 멈춥니다. '
            '최대 ${SupervisorProvider.teleopMaxLinear} m/s · '
            '${SupervisorProvider.teleopMaxAngular} rad/s.',
            style: TextStyle(color: VicaColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 14),
          Center(
            child: SizedBox(
              width: 208,
              child: Column(
                children: [
                  _PadButton(
                    icon: Icons.keyboard_arrow_up,
                    label: '앞으로',
                    enabled: enabled,
                    linear: SupervisorProvider.teleopMaxLinear,
                    angular: 0,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _PadButton(
                        icon: Icons.rotate_left,
                        label: '왼쪽',
                        enabled: enabled,
                        linear: 0,
                        angular: SupervisorProvider.teleopMaxAngular,
                      ),
                      const SizedBox(width: 8),
                      _StopButton(enabled: enabled),
                      const SizedBox(width: 8),
                      _PadButton(
                        icon: Icons.rotate_right,
                        label: '오른쪽',
                        enabled: enabled,
                        linear: 0,
                        angular: -SupervisorProvider.teleopMaxAngular,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _PadButton(
                    icon: Icons.keyboard_arrow_down,
                    label: '뒤로',
                    enabled: enabled,
                    linear: -SupervisorProvider.teleopMaxLinear,
                    angular: 0,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PadButton extends StatelessWidget {
  const _PadButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.linear,
    required this.angular,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final double linear;
  final double angular;

  @override
  Widget build(BuildContext context) {
    final supervisor = context.read<SupervisorProvider>();
    // GestureDetector 의 onTap 이 아니라 Listener 의 포인터 이벤트를 씁니다.
    // onTap 은 손을 뗀 뒤에야 불리므로 "누르고 있는 동안"을 표현할 수 없습니다.
    return Listener(
      onPointerDown: enabled
          ? (_) => supervisor.holdTeleop(linear: linear, angular: angular)
          : null,
      onPointerUp: enabled ? (_) => supervisor.releaseTeleop() : null,
      // 손가락이 버튼 밖으로 미끄러지거나 시스템이 제스처를 가로채도 멈춥니다.
      onPointerCancel: enabled ? (_) => supervisor.releaseTeleop() : null,
      child: Semantics(
        button: true,
        label: label,
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: Container(
            width: 64,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: VicaColors.softBlue,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: VicaColors.border),
            ),
            child: Icon(icon, size: 26, color: VicaColors.primaryDark),
          ),
        ),
      ),
    );
  }
}

// 손을 떼는 것으로 이미 멈추지만, 눌러서 멈출 수 있는 자리가 눈에 보이는 편이
// 안심됩니다. 비상정지와는 다릅니다 — 그쪽은 앱바의 빨간 버튼입니다.
class _StopButton extends StatelessWidget {
  const _StopButton({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final supervisor = context.read<SupervisorProvider>();
    return GestureDetector(
      onTap: enabled ? supervisor.releaseTeleop : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: Container(
          width: 64,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: VicaColors.border),
          ),
          child: const Icon(Icons.stop, size: 24, color: VicaColors.muted),
        ),
      ),
    );
  }
}
