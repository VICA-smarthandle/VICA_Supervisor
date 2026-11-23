import 'package:flutter/material.dart';

const Duration kVicaTransition = Duration(milliseconds: 240);
const Duration kVicaPress = Duration(milliseconds: 90);
const double kVicaPressScale = 0.96;

bool _reduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// 클릭 효과 ② — 누르는 동안 [kVicaPressScale] 배로 줄입니다.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, this.enabled});

  final Widget child;
  final bool? enabled;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;
  Offset? _downAt;

  /// 이만큼 움직이면 누르기가 아니라 끌기(목록 굴리기)로 보고 원래 크기로 돌립니다.
  static const double _slop = 10;

  bool get _enabled {
    final explicit = widget.enabled;
    if (explicit != null) {
      return explicit;
    }
    final child = widget.child;
    if (child is ButtonStyleButton) {
      return child.enabled;
    }
    if (child is IconButton) {
      return child.onPressed != null;
    }
    if (child is InkWell) {
      return child.onTap != null || child.onLongPress != null;
    }
    if (child is ListTile) {
      return child.enabled &&
          (child.onTap != null || child.onLongPress != null);
    }
    if (child is Material && child.child is InkWell) {
      final ink = child.child! as InkWell;
      return ink.onTap != null || ink.onLongPress != null;
    }
    return true;
  }

  void _set(bool down) {
    if (_down != down && mounted) {
      setState(() => _down = down);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_reduceMotion(context)) {
      return widget.child;
    }
    return Listener(
      onPointerDown: (event) {
        if (_enabled) {
          _downAt = event.position;
          _set(true);
        }
      },
      onPointerMove: (event) {
        final at = _downAt;
        if (_down && at != null && (event.position - at).distance > _slop) {
          _set(false);
        }
      },
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? kVicaPressScale : 1.0,
        duration: kVicaPress,
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// 화면 위에 새 화면을 열 때(Navigator.push) — 오른쪽에서 밀려 들어옵니다.
class VicaSlidePageTransitionsBuilder extends PageTransitionsBuilder {
  const VicaSlidePageTransitionsBuilder();

  @override
  Duration get transitionDuration => kVicaTransition;

  @override
  Duration get reverseTransitionDuration => kVicaTransition;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (_reduceMotion(context)) {
      return child;
    }
    final ease = CurveTween(curve: Curves.easeOutCubic);
    return SlideTransition(
      position: secondaryAnimation.drive(
        Tween(begin: Offset.zero, end: const Offset(-0.3, 0)).chain(ease),
      ),
      child: SlideTransition(
        position: animation.drive(
          Tween(begin: const Offset(1, 0), end: Offset.zero).chain(ease),
        ),
        child: child,
      ),
    );
  }
}

/// 메뉴 화면 바꾸기 — 새 화면이 오른쪽에서, 이전 화면은 왼쪽으로 30 % 밀리며 흐려집니다.
class VicaScreenSwitcher extends StatefulWidget {
  const VicaScreenSwitcher(
      {super.key, required this.index, required this.child});

  /// 지금 화면 번호. 바뀔 때만 움직입니다.
  final int index;
  final Widget child;

  @override
  State<VicaScreenSwitcher> createState() => _VicaScreenSwitcherState();
}

class _VicaScreenSwitcherState extends State<VicaScreenSwitcher>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: kVicaTransition, value: 1)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed && _outChild != null) {
            setState(() {
              _outChild = null;
              _outIndex = null;
            });
          }
        });
  late final Animation<double> _curved =
      _controller.drive(CurveTween(curve: Curves.easeOutCubic));
  int? _outIndex;
  Widget? _outChild;

  @override
  void didUpdateWidget(covariant VicaScreenSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      if (_reduceMotion(context)) {
        _outChild = null;
        _outIndex = null;
        _controller.value = 1;
        return;
      }
      _outIndex = oldWidget.index;
      _outChild = oldWidget.child;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final out = _outChild;
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (out != null)
            _Slide(
              key: ValueKey<int>(_outIndex!),
              position: Tween(begin: Offset.zero, end: const Offset(-0.3, 0))
                  .animate(_curved),
              opacity: ReverseAnimation(_curved),
              interactive: false,
              child: out,
            ),
          _Slide(
            key: ValueKey<int>(widget.index),
            position: Tween(begin: const Offset(1, 0), end: Offset.zero)
                .animate(_curved),
            opacity: kAlwaysCompleteAnimation,
            interactive: true,
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

class _Slide extends StatelessWidget {
  const _Slide({
    super.key,
    required this.position,
    required this.opacity,
    required this.interactive,
    required this.child,
  });

  final Animation<Offset> position;
  final Animation<double> opacity;

  /// false = 나가는 화면. 누르기·키보드 초점을 받지 않습니다(수동 주행 키를 쥔 채 메뉴를 바꾸면
  final bool interactive;
  final Widget child;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        ignoring: !interactive,
        child: ExcludeFocus(
          excluding: !interactive,
          child: FadeTransition(
            opacity: opacity,
            child: SlideTransition(position: position, child: child),
          ),
        ),
      );
}

/// 확인 창 — showDialog 와 같게 쓰고, 오른쪽에서 조금 밀려 들어오며 나타납니다.
Future<T?> showVicaDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  final reduce = _reduceMotion(context);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black54,
    transitionDuration: reduce ? Duration.zero : kVicaTransition,
    pageBuilder: (dialogContext, animation, secondaryAnimation) =>
        SafeArea(child: Builder(builder: builder)),
    transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
      final curved = animation.drive(CurveTween(curve: Curves.easeOutCubic));
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: curved.drive(
            Tween(begin: const Offset(0.08, 0), end: Offset.zero),
          ),
          child: child,
        ),
      );
    },
  );
}
