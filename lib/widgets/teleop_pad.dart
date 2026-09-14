// 이 파일은 지도를 그릴 때 로봇을 끌고 다니는 조작판입니다.
//
// **반드시 누르고 있는 동안만 갑니다.** 한 번 눌러 계속 가게 만들면 안 됩니다.
// safety_supervisor_node 와 mdrobot_can_control 이 각각 cmd_timeout_sec 0.5 를
// 갖고 있어, 명령이 끊기면 0.5초 안에 두 계층이 각각 로봇을 세웁니다. 그 안전장치는
// "손을 떼면 명령이 끊긴다"를 전제로 하므로, 눌러 두고 손을 떼도 계속 가는 방식은
// 그 전제를 깨뜨립니다. 잔디깎이 손잡이와 같습니다.
//
// 속도 상한은 SupervisorProvider 가 갖고 있습니다(직진 0.3 m/s, 회전 0.3 rad/s).
// docs/cartographer_corridor_mapping.md 4절이 근거입니다 — 더 빠르면 스캔 사이
// 이동이 Cartographer 의 예측 탐색 창(0.1 m)에 닿아 지도가 나빠집니다.
// 회전은 그 문서의 0.4 보다 한 단계 더 내렸습니다 — 직진과 같은 0.3 이 지도가
// 곱게 나온다는 운영자 관찰(2026-09-03)입니다.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/supervisor_provider.dart';
import 'vica_ui.dart';

class TeleopPad extends StatelessWidget {
  const TeleopPad({super.key, required this.enabled});

  final bool enabled;

  /// 다이얼(바깥 원)의 지름과 방향 버튼의 지름입니다. 버튼은 원 가장자리에서
  /// [_dialInset] 만큼 안쪽에 동서남북으로 놓입니다.
  static const double _dialSize = 200;
  static const double _buttonSize = 52;
  static const double _dialInset = 14;

  @override
  Widget build(BuildContext context) {
    final supervisor = context.watch<SupervisorProvider>();

    // 버튼 넷의 자리. 화살표는 화면에서 보는 방향 그대로 가리킵니다 — 위는
    // 앞으로, 오른쪽은 오른쪽으로 도는 것입니다. 회전 아이콘(rotate_*)은 어느
    // 쪽으로 도는지 한 박자 생각해야 해서 화살표로 바꿨습니다(2026-09-14 시안).
    const mid = (_dialSize - _buttonSize) / 2;
    const far = _dialSize - _buttonSize - _dialInset;
    final buttons = [
      _PadButton(
        icon: Icons.keyboard_arrow_up,
        label: '앞으로',
        left: mid,
        top: _dialInset,
        pressed: supervisor.isTeleopHeld(
          linear: SupervisorProvider.teleopMaxLinear,
          angular: 0,
        ),
        enabled: enabled,
        linear: SupervisorProvider.teleopMaxLinear,
        angular: 0,
      ),
      _PadButton(
        icon: Icons.keyboard_arrow_right,
        label: '오른쪽',
        left: far,
        top: mid,
        pressed: supervisor.isTeleopHeld(
          linear: 0,
          angular: -SupervisorProvider.teleopMaxAngular,
        ),
        enabled: enabled,
        linear: 0,
        angular: -SupervisorProvider.teleopMaxAngular,
      ),
      _PadButton(
        icon: Icons.keyboard_arrow_down,
        label: '뒤로',
        left: mid,
        top: far,
        pressed: supervisor.isTeleopHeld(
          linear: -SupervisorProvider.teleopMaxLinear,
          angular: 0,
        ),
        enabled: enabled,
        linear: -SupervisorProvider.teleopMaxLinear,
        angular: 0,
      ),
      _PadButton(
        icon: Icons.keyboard_arrow_left,
        label: '왼쪽',
        left: _dialInset,
        top: mid,
        pressed: supervisor.isTeleopHeld(
          linear: 0,
          angular: SupervisorProvider.teleopMaxAngular,
        ),
        enabled: enabled,
        linear: 0,
        angular: SupervisorProvider.teleopMaxAngular,
      ),
    ];

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
                  '원격 조종',
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
            '버튼을 누르고 있는 동안만 움직입니다. 손을 떼면 바로 멈춥니다. '
            '최대 ${SupervisorProvider.teleopMaxLinear} m/s · '
            '${SupervisorProvider.teleopMaxAngular} rad/s.',
            style: TextStyle(color: VicaColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 14),
          // 가운데 정지 버튼은 없습니다. 손을 떼면 그 자리에서 멈추므로 누를
          // 일이 없고, 있으면 "눌러야 멈춘다"는 오해를 줍니다.
          Center(
            child: Container(
              width: _dialSize,
              height: _dialSize,
              decoration: BoxDecoration(
                color: VicaColors.surfaceSunken,
                shape: BoxShape.circle,
                border: Border.all(color: VicaColors.border),
              ),
              child: Stack(children: buttons),
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
    required this.left,
    required this.top,
    required this.enabled,
    required this.pressed,
    required this.linear,
    required this.angular,
  });

  final IconData icon;

  /// 화면에는 안 보이고 접근성·시험이 읽는 이름입니다.
  final String label;

  /// 다이얼 안에서의 자리입니다.
  final double left;
  final double top;
  final bool enabled;
  // 이 버튼의 명령이 실제로 나가고 있는가(provider 가 판정). 눌림 표시용.
  final bool pressed;
  final double linear;
  final double angular;

  @override
  Widget build(BuildContext context) {
    final supervisor = context.read<SupervisorProvider>();
    // GestureDetector 의 onTap 이 아니라 Listener 의 포인터 이벤트를 씁니다.
    // onTap 은 손을 뗀 뒤에야 불리므로 "누르고 있는 동안"을 표현할 수 없습니다.
    return Positioned(
      left: left,
      top: top,
      child: Listener(
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
              width: TeleopPad._buttonSize,
              height: TeleopPad._buttonSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                // 눌려서 명령이 나가는 동안만 진하게(2026-09-04). 근거는 버튼의
                // 눌림이 아니라 provider 의 실제 명령값(isTeleopHeld)이라, 연결이
                // 끊겨 명령이 안 나가면 색도 꺼집니다.
                color: pressed ? VicaColors.primary : VicaColors.card,
                shape: BoxShape.circle,
                border: Border.all(
                  color: pressed
                      ? VicaColors.primaryDark
                      : VicaColors.borderStrong,
                ),
              ),
              child: Icon(
                icon,
                size: 26,
                color: pressed ? Colors.white : VicaColors.primaryDark,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
