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
//
// [adjustableSpeed](지도 그리기, 2026-11-18 사용자): 속도 칸 0.1~0.7 m/s, 기본 0.3.
// 적정 속도 0.3 은 문구로만 알립니다. 회전·가속은 수동 주행과 같습니다 — 회전 max(0.2, v),
// 출발 가속 3.0(provider 의 _stepTeleop). 홈 위치 조종판은 예전 그대로 0.3 고정입니다.
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
  /// [_dialInset] 만큼 안쪽에 동서남북으로 놓입니다.
  // 200 이었는데 폰 화면에서 카드의 절반을 먹어 152 로 줄였습니다(2026-09-15).
  // 버튼 44 는 손가락으로 누를 수 있는 최소 크기입니다.
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
    // 누르는 도중 꺼지면(지도 그리기 끝 등) 떼기 처리기가 사라지므로 여기서 멈춥니다.
    // build 중이라 provider 알림은 이 프레임 끝에 보냅니다.
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

    // 버튼 넷의 자리. 화살표는 화면에서 보는 방향 그대로 가리킵니다 — 위는
    // 앞으로, 오른쪽은 오른쪽으로 도는 것입니다. 회전 아이콘(rotate_*)은 어느
    // 쪽으로 도는지 한 박자 생각해야 해서 화살표로 바꿨습니다(2026-09-14 시안).
    const mid = (TeleopPad._dialSize - TeleopPad._buttonSize) / 2;
    const far =
        TeleopPad._dialSize - TeleopPad._buttonSize - TeleopPad._dialInset;
    _PadButton button(
            IconData icon, String label, double left, double top, int v, int w) =>
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
          // 문장 끝에서 줄을 바꿉니다(2026-09-14 규칙). '손을 떼면 바로 멈춥니다'는
          // 앞 문장과 뜻이 겹쳐 뺐습니다(2026-09-15).
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
          // 가운데 정지 버튼은 없습니다. 손을 떼면 그 자리에서 멈추므로 누를
          // 일이 없고, 있으면 "눌러야 멈춘다"는 오해를 줍니다.
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
                // 좁은 폭·큰 글자에서는 띄어쓰기 자리에서 줄을 바꿉니다(넘침 방지).
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
  // 이 버튼의 명령이 실제로 나가고 있는가(provider 가 판정). 눌림 표시용.
  final bool pressed;
  final VoidCallback onDown;
  final VoidCallback onUp;

  @override
  Widget build(BuildContext context) {
    // GestureDetector 의 onTap 이 아니라 Listener 의 포인터 이벤트를 씁니다.
    // onTap 은 손을 뗀 뒤에야 불리므로 "누르고 있는 동안"을 표현할 수 없습니다.
    return Positioned(
      left: left,
      top: top,
      child: Listener(
        onPointerDown: enabled
            ? (event) {
                // 마우스는 왼쪽 버튼만(2026-11-18 검토): 오른쪽 버튼은 브라우저 메뉴가 떼기를
                // 먹어 손을 뗀 뒤에도 계속 갈 수 있습니다.
                if (event.kind == PointerDeviceKind.mouse &&
                    event.buttons != kPrimaryButton) {
                  return;
                }
                onDown();
              }
            : null,
        onPointerUp: enabled ? (_) => onUp() : null,
        // 손가락이 버튼 밖으로 미끄러지거나 시스템이 제스처를 가로채도 멈춥니다.
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
