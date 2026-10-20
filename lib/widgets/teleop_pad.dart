import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/supervisor_provider.dart';
import 'vica_ui.dart';

class TeleopPad extends StatelessWidget {
  const TeleopPad({super.key, required this.enabled});

  final bool enabled;

  /// 다이얼(바깥 원)의 지름과 방향 버튼의 지름입니다. 버튼은 원 가장자리에서
  static const double _dialSize = 152;
  static const double _buttonSize = 44;
  static const double _dialInset = 10;

  @override
  Widget build(BuildContext context) {
    final supervisor = context.watch<SupervisorProvider>();

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
          Text(
            vicaKeepWords(
              '버튼을 누르고 있는 동안만 움직입니다.\n'
              '최대 ${SupervisorProvider.teleopMaxLinear} m/s · '
              '${SupervisorProvider.teleopMaxAngular} rad/s.',
            ),
            style: const TextStyle(color: VicaColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 14),
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
  final bool pressed;
  final double linear;
  final double angular;

  @override
  Widget build(BuildContext context) {
    final supervisor = context.read<SupervisorProvider>();
    return Positioned(
      left: left,
      top: top,
      child: Listener(
        onPointerDown: enabled
            ? (_) => supervisor.holdTeleop(linear: linear, angular: angular)
            : null,
        onPointerUp: enabled ? (_) => supervisor.releaseTeleop() : null,
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
                size: 22,
                color: pressed ? Colors.white : VicaColors.primaryDark,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
