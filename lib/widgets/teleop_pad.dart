import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/supervisor_provider.dart';
import 'vica_ui.dart';

class TeleopPad extends StatefulWidget {
  const TeleopPad({
    super.key,
    required this.enabled,
    this.adjustableSpeed = false,
  });

  final bool enabled;

  /// true 면 속도 칸(0.1~0.7 m/s)을 보입니다 — 지도 그리기 화면.
  final bool adjustableSpeed;

  /// 다이얼(바깥 원)의 지름과 방향 버튼의 지름입니다. 버튼은 원 가장자리에서
  static const double _dialSize = 152;
  static const double _buttonSize = 44;
  static const double _dialInset = 10;

  /// 지도 작성 적정 속도(m/s). 속도 칸의 기본값이자 문구의 값입니다.
  static const double mappingSpeed = SupervisorProvider.teleopMaxLinear;

  @override
  State<TeleopPad> createState() => _TeleopPadState();
}

class _TeleopPadState extends State<TeleopPad> {
  static const double _minSpeed = 0.1;
  static const double _maxSpeed = SupervisorProvider.manualDriveMaxLinear;

  double _speed = TeleopPad.mappingSpeed;

  /// 누르고 있는 버튼(직진 부호, 회전 부호). 속도를 바꾸거나 조종판이 꺼질 때 씁니다.
  (int, int)? _held;

  double get _linear =>
      widget.adjustableSpeed ? _speed : SupervisorProvider.teleopMaxLinear;
  double get _angular => widget.adjustableSpeed
      ? math.max(0.2, _speed)
      : SupervisorProvider.teleopMaxAngular;

  @override
  void didUpdateWidget(covariant TeleopPad oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled && !widget.enabled && _held != null) {
      _held = null;
      final supervisor = context.read<SupervisorProvider>();
      WidgetsBinding.instance
          .addPostFrameCallback((_) => supervisor.releaseTeleop());
    }
  }

  void _hold(int v, int w) {
    _held = (v, w);
    final supervisor = context.read<SupervisorProvider>();
    if (widget.adjustableSpeed) {
      supervisor.holdTeleop(
        linear: v * _linear,
        angular: w * _angular,
        maxLinear: SupervisorProvider.manualDriveMaxLinear,
        maxAngular: SupervisorProvider.manualDriveMaxAngular,
        accel: SupervisorProvider.manualDriveAccel,
      );
    } else {
      supervisor.holdTeleop(linear: v * _linear, angular: w * _angular);
    }
  }

  void _release() {
    _held = null;
    context.read<SupervisorProvider>().releaseTeleop();
  }

  void _setSpeed(double value) {
    setState(() {
      _speed = (value.clamp(_minSpeed, _maxSpeed) * 10).roundToDouble() / 10;
    });
    final held = _held;
    if (held != null) {
      _hold(held.$1, held.$2);
    }
  }

  @override
  Widget build(BuildContext context) {
    final supervisor = context.watch<SupervisorProvider>();
    final enabled = widget.enabled;

    const mid = (TeleopPad._dialSize - TeleopPad._buttonSize) / 2;
    const far =
        TeleopPad._dialSize - TeleopPad._buttonSize - TeleopPad._dialInset;
    _PadButton button(IconData icon, String label, double left, double top,
            int v, int w) =>
        _PadButton(
          icon: icon,
          label: label,
          left: left,
          top: top,
          pressed: supervisor.isTeleopHeld(
            linear: v * _linear,
            angular: w * _angular,
          ),
          enabled: enabled,
          onDown: () => _hold(v, w),
          onUp: _release,
        );
    final buttons = [
      button(Icons.keyboard_arrow_up, '앞으로', mid, TeleopPad._dialInset, 1, 0),
      button(Icons.keyboard_arrow_right, '오른쪽', far, mid, 0, -1),
      button(Icons.keyboard_arrow_down, '뒤로', mid, far, -1, 0),
      button(Icons.keyboard_arrow_left, '왼쪽', TeleopPad._dialInset, mid, 0, 1),
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
              widget.adjustableSpeed
                  ? '버튼을 누르고 있는 동안만 움직입니다.\n'
                      '지도 작성 적정 속도는 ${TeleopPad.mappingSpeed} m/s입니다.'
                  : '버튼을 누르고 있는 동안만 움직입니다.\n'
                      '최대 ${SupervisorProvider.teleopMaxLinear} m/s · '
                      '${SupervisorProvider.teleopMaxAngular} rad/s.',
            ),
            style: const TextStyle(color: VicaColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 14),
          Center(
            child: Container(
              width: TeleopPad._dialSize,
              height: TeleopPad._dialSize,
              decoration: BoxDecoration(
                color: VicaColors.surfaceSunken,
                shape: BoxShape.circle,
                border: Border.all(color: VicaColors.border),
              ),
              child: Stack(children: buttons),
            ),
          ),
          if (widget.adjustableSpeed) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                const Text('속도', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    vicaKeepWords('${_linear.toStringAsFixed(2)} m/s · 회전 '
                        '${_angular.toStringAsFixed(2)} rad/s'),
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: VicaColors.primaryDark,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
            Slider(
              value: _speed,
              min: _minSpeed,
              max: _maxSpeed,
              divisions: 6,
              label: '${_speed.toStringAsFixed(1)} m/s',
              onChanged: enabled ? _setSpeed : null,
            ),
          ],
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
    required this.onDown,
    required this.onUp,
  });

  final IconData icon;

  /// 화면에는 안 보이고 접근성·시험이 읽는 이름입니다.
  final String label;

  /// 다이얼 안에서의 자리입니다.
  final double left;
  final double top;
  final bool enabled;
  final bool pressed;
  final VoidCallback onDown;
  final VoidCallback onUp;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      top: top,
      child: Listener(
        onPointerDown: enabled
            ? (event) {
                if (event.kind == PointerDeviceKind.mouse &&
                    event.buttons != kPrimaryButton) {
                  return;
                }
                onDown();
              }
            : null,
        onPointerUp: enabled ? (_) => onUp() : null,
        onPointerCancel: enabled ? (_) => onUp() : null,
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
