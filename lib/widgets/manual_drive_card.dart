import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/supervisor_provider.dart';
import '../ros/ros_bridge_client.dart';
import 'vica_ui.dart';

/// 수동 주행을 막을 때 보이는 문구(2026-11-18 사용자).
const String kManualDriveBusyMessage = '현재 주행 중입니다.\n주행이 완료된 후 사용해주세요.';

class ManualDriveCard extends StatefulWidget {
  const ManualDriveCard({super.key, this.blockedMessage});

  /// null 이 아니면 버튼·키를 막고 이 문구를 보입니다.
  final String? blockedMessage;

  @override
  State<ManualDriveCard> createState() => _ManualDriveCardState();
}

class _ManualDriveCardState extends State<ManualDriveCard> {
  static const double _minSpeed = 0.1;
  static const double _maxSpeed = SupervisorProvider.manualDriveMaxLinear;
  static const double _button = 64;

  double _speed = 0.3;
  final FocusNode _focus = FocusNode(debugLabel: 'manual-drive');

  final FocusNode _sliderFocus = FocusNode(
    debugLabel: 'manual-drive-speed',
    canRequestFocus: false,
    skipTraversal: true,
  );
  final Set<LogicalKeyboardKey> _keys = {};

  /// 손가락·마우스로 누르고 있는 칸(직진 부호, 회전 부호). 속도를 바꾸면 이 값으로 다시 보냅니다.
  (int, int)? _padHeld;
  SupervisorProvider? _supervisor;

  static final Map<LogicalKeyboardKey, (int, int)> _teleopKeys = {
    LogicalKeyboardKey.keyU: (1, 1),
    LogicalKeyboardKey.keyI: (1, 0),
    LogicalKeyboardKey.keyO: (1, -1),
    LogicalKeyboardKey.keyJ: (0, 1),
    LogicalKeyboardKey.keyL: (0, -1),
    LogicalKeyboardKey.keyM: (-1, -1),
    LogicalKeyboardKey.comma: (-1, 0),
    LogicalKeyboardKey.period: (-1, 1),
  };
  static final Set<LogicalKeyboardKey> _stopKeys = {
    LogicalKeyboardKey.keyK,
    LogicalKeyboardKey.space,
  };
  static final Set<LogicalKeyboardKey> _arrowKeys = {
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
  };

  bool get _blocked => widget.blockedMessage != null;
  double get _turnRate => math.max(0.2, _speed);

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) {
        _keys.clear();
        _release();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _supervisor = context.read<SupervisorProvider>();
  }

  @override
  void didUpdateWidget(covariant ManualDriveCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_blocked && oldWidget.blockedMessage == null) {
      _keys.clear();
      _padHeld = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _release());
    }
  }

  @override
  void dispose() {
    final supervisor = _supervisor;
    if (supervisor != null && supervisor.teleopActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (supervisor.teleopActive) {
          supervisor.releaseTeleop();
        }
      });
    }
    _focus.dispose();
    _sliderFocus.dispose();
    super.dispose();
  }

  void _release() {
    final supervisor = _supervisor;
    if (supervisor != null && supervisor.teleopActive) {
      supervisor.releaseTeleop();
    }
  }

  void _drive(int v, int w) {
    final supervisor = _supervisor;
    if (supervisor == null) {
      return;
    }
    if (_blocked || (v == 0 && w == 0)) {
      _release();
      return;
    }
    supervisor.holdTeleop(
      linear: v * _speed,
      angular: w * _turnRate,
      maxLinear: SupervisorProvider.manualDriveMaxLinear,
      maxAngular: SupervisorProvider.manualDriveMaxAngular,
      accel: SupervisorProvider.manualDriveAccel,
    );
  }

  void _driveFromKeys() {
    if (_keys.any(_stopKeys.contains)) {
      _drive(0, 0);
      return;
    }
    for (final entry in _teleopKeys.entries) {
      if (_keys.contains(entry.key)) {
        _drive(entry.value.$1, entry.value.$2);
        return;
      }
    }
    final v = (_keys.contains(LogicalKeyboardKey.arrowUp) ? 1 : 0) -
        (_keys.contains(LogicalKeyboardKey.arrowDown) ? 1 : 0);
    var w = (_keys.contains(LogicalKeyboardKey.arrowLeft) ? 1 : 0) -
        (_keys.contains(LogicalKeyboardKey.arrowRight) ? 1 : 0);
    if (v < 0) {
      w = -w;
    }
    _drive(v, w);
  }

  void _setSpeed(double value) {
    setState(() {
      _speed = (value.clamp(_minSpeed, _maxSpeed) * 10).roundToDouble() / 10;
    });
    final held = _padHeld;
    if (held != null) {
      _drive(held.$1, held.$2);
    } else if (_keys.isNotEmpty) {
      _driveFromKeys();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    final known = _teleopKeys.containsKey(key) ||
        _stopKeys.contains(key) ||
        _arrowKeys.contains(key);
    if (event is KeyDownEvent && key == LogicalKeyboardKey.keyQ) {
      _setSpeed(_speed + 0.1);
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent && key == LogicalKeyboardKey.keyZ) {
      _setSpeed(_speed - 0.1);
      return KeyEventResult.handled;
    }
    if (!known) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) {
      _keys.add(key);
      _driveFromKeys();
    } else if (event is KeyUpEvent) {
      _keys.remove(key);
      _driveFromKeys();
    }
    return KeyEventResult.handled;
  }

  /// 마우스는 왼쪽 버튼만 받습니다. 오른쪽 버튼은 브라우저 메뉴가 떼기를 먹어 계속 갈 수 있습니다.
  static bool _primary(PointerDownEvent event) =>
      event.kind != PointerDeviceKind.mouse || event.buttons == kPrimaryButton;

  @override
  Widget build(BuildContext context) {
    final supervisor = context.watch<SupervisorProvider>();
    final connected =
        supervisor.connectionState == RosConnectionState.connected;
    final enabled = connected && !_blocked;

    Widget padButton(int v, int w, IconData icon, String label) {
      final held = supervisor.isTeleopHeld(
        linear: v * _speed,
        angular: w * _turnRate,
      );
      final diagonal = v != 0 && w != 0;
      return Semantics(
        button: true,
        label: label,
        child: Listener(
          onPointerDown: enabled
              ? (event) {
                  if (!_primary(event)) {
                    return;
                  }
                  _focus.requestFocus();
                  _padHeld = (v, w);
                  _drive(v, w);
                }
              : null,
          onPointerUp: enabled
              ? (_) {
                  _padHeld = null;
                  _drive(0, 0);
                }
              : null,
          onPointerCancel: enabled
              ? (_) {
                  _padHeld = null;
                  _drive(0, 0);
                }
              : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            width: _button,
            height: _button,
            decoration: BoxDecoration(
              color: held ? VicaColors.primary : VicaColors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: held ? VicaColors.primaryDark : VicaColors.borderStrong,
              ),
            ),
            child: Icon(
              icon,
              size: diagonal ? 24 : 28,
              color: held
                  ? VicaColors.card
                  : diagonal
                      ? VicaColors.primary
                      : VicaColors.primaryDark,
            ),
          ),
        ),
      );
    }

    final stopButton = Semantics(
      button: true,
      label: '정지',
      excludeSemantics: true,
      child: Listener(
        onPointerDown: enabled
            ? (_) {
                _focus.requestFocus();
                _padHeld = null;
                _drive(0, 0);
              }
            : null,
        child: Container(
          width: _button,
          height: _button,
          decoration: BoxDecoration(
            color: VicaColors.red.withValues(alpha: 0.1),
            shape: BoxShape.circle,
            border: Border.all(color: VicaColors.red.withValues(alpha: 0.35)),
          ),
          alignment: Alignment.center,
          child: const Text(
            '정지',
            style: TextStyle(
              color: VicaColors.red,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );

    Widget row(List<Widget> cells) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < cells.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              cells[i],
            ],
          ],
        );

    final pad = Opacity(
      opacity: enabled ? 1 : 0.35,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: VicaColors.surfaceSunken,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            row([
              padButton(1, 1, Icons.north_west, '앞 왼쪽 선회'),
              padButton(1, 0, Icons.arrow_upward, '앞으로'),
              padButton(1, -1, Icons.north_east, '앞 오른쪽 선회'),
            ]),
            const SizedBox(height: 8),
            row([
              padButton(0, 1, Icons.rotate_left, '제자리 왼쪽 회전'),
              stopButton,
              padButton(0, -1, Icons.rotate_right, '제자리 오른쪽 회전'),
            ]),
            const SizedBox(height: 8),
            row([
              padButton(-1, -1, Icons.south_west, '뒤 왼쪽 선회'),
              padButton(-1, 0, Icons.arrow_downward, '뒤로'),
              padButton(-1, 1, Icons.south_east, '뒤 오른쪽 선회'),
            ]),
          ],
        ),
      ),
    );

    final message = widget.blockedMessage;
    return Focus(
      focusNode: _focus,
      autofocus: kIsWeb,
      onKeyEvent: _onKey,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _focus.requestFocus(),
        child: VicaCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (message != null) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: VicaColors.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, height: 1.45),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Center(child: pad),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Text('속도', style: TextStyle(fontSize: 13)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      vicaKeepWords('${_speed.toStringAsFixed(2)} m/s · 회전 '
                          '${_turnRate.toStringAsFixed(2)} rad/s'),
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
                focusNode: _sliderFocus,
                value: _speed,
                min: _minSpeed,
                max: _maxSpeed,
                divisions: 6,
                label: '${_speed.toStringAsFixed(1)} m/s',
                onChanged: enabled ? _setSpeed : null,
              ),
              if (kIsWeb)
                const Text(
                  '웹에서는 키보드로도 조종할 수 있습니다.',
                  style: TextStyle(fontSize: 12.5, color: VicaColors.muted),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
