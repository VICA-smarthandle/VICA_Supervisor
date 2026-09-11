import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/layout_breakpoints.dart';
import '../models/robot_status.dart';
import '../models/supervisor_log.dart';

class VicaColors {
  const VicaColors._();

  static const background = Color(0xFFF3F6FA);
  static const card = Colors.white;
  static const border = Color(0xFFDDE4EE);
  static const primary = Color(0xFF5465A3);
  static const primaryDark = Color(0xFF203F91);
  static const text = Color(0xFF20222B);
  static const muted = Color(0xFF667085);
  static const softBlue = Color(0xFFE9EEF8);
  static const green = Color(0xFF22A86A);
  static const red = Color(0xFFE8424E);
}

class VicaPage extends StatelessWidget {
  const VicaPage({
    super.key,
    required this.title,
    this.subtitle,
    required this.children,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding =
            VicaBreakpoints.horizontalPadding(constraints.maxWidth);
        return ListView(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            24,
            horizontalPadding,
            28,
          ),
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: VicaBreakpoints.contentMaxWidth,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                    const SizedBox(height: 20),
                    ...children,
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class VicaCard extends StatelessWidget {
  const VicaCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: padding,
      decoration: BoxDecoration(
        color: VicaColors.card,
        border: Border.all(color: VicaColors.border),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class VicaSectionTitle extends StatelessWidget {
  const VicaSectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 14),
      child: Text(text, style: Theme.of(context).textTheme.headlineSmall),
    );
  }
}

class VicaDisconnectedNotice extends StatelessWidget {
  const VicaDisconnectedNotice({super.key, this.detail = ''});

  final String detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: VicaColors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: VicaColors.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.link_off, color: VicaColors.red, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ROS 연결 안 됨',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: VicaColors.red,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail.isEmpty ? '로봇 상태를 받을 수 없습니다.' : detail,
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class VicaMetricCard extends StatelessWidget {
  const VicaMetricCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.labelMaxLines = 1,
    this.labelFontSize = 12,
  });

  /// 글자 배율 1.0에서 카드 한 장이 차지하는 높이입니다.
  static const double baseHeight = 116;

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final int labelMaxLines;
  final double labelFontSize;

  @override
  Widget build(BuildContext context) {
    return VicaCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          _MetricIconBox(icon: icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: labelMaxLines,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: labelFontSize,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    maxLines: 1,
                    softWrap: false,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontSize: 25,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricIconBox extends StatelessWidget {
  const _MetricIconBox({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(icon, color: color, size: 21),
    );
  }
}

class VicaRobotCard extends StatelessWidget {
  const VicaRobotCard({
    super.key,
    required this.robot,
    this.onTap,
    this.selected = false,
  });

  final RobotStatus robot;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return VicaCard(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _IconBox(
                icon: Icons.smart_toy, color: VicaColors.primaryDark),
            const SizedBox(width: 14),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final contentWidth = constraints.maxWidth;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: contentWidth),
                            child: Text(
                              robot.robotName,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          _Pill(
                            text: _statusLabel(robot.status),
                            color: robot.hasError
                                ? VicaColors.red
                                : VicaColors.primary,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('ID: ${robot.robotId}',
                          style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 14,
                        runSpacing: 8,
                        children: [
                          _InfoChip(
                              icon: Icons.location_on_outlined,
                              maxWidth: contentWidth,
                              text:
                                  '현재 위치: ${_empty(robot.currentLocation, '수신 대기')}'),
                          _InfoChip(
                              icon: Icons.flag_outlined,
                              maxWidth: contentWidth,
                              text: '목적지: ${_empty(robot.currentGoal, '없음')}'),
                          _InfoChip(
                              icon: Icons.schedule,
                              maxWidth: contentWidth,
                              text:
                                  '마지막 통신: ${_relativeTime(robot.timestamp)}'),
                          _InfoChip(
                              icon: Icons.my_location_outlined,
                              maxWidth: contentWidth,
                              text:
                                  '좌표: ${robot.x.toStringAsFixed(2)}, ${robot.y.toStringAsFixed(2)}'),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class VicaFieldWithAction extends StatelessWidget {
  const VicaFieldWithAction({
    super.key,
    required this.field,
    required this.action,
    this.actionWidth = 132,
  });

  final Widget field;
  final Widget action;

  /// 넓은 창에서 버튼이 차지할 폭입니다.
  final double actionWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (VicaBreakpoints.isCompact(constraints.maxWidth)) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              field,
              const SizedBox(height: 10),
              action,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: field),
            const SizedBox(width: 10),
            SizedBox(width: actionWidth, child: action),
          ],
        );
      },
    );
  }
}

class VicaInfoRow extends StatelessWidget {
  const VicaInfoRow({
    super.key,
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  /// 라벨 열의 폭입니다. '마지막 통신'까지 한 줄에 들어가는 값으로 잡았습니다.
  static const double _labelWidth = 100;

  @override
  Widget build(BuildContext context) {
    final text = value.isEmpty ? '-' : value;
    const labelStyle = TextStyle(fontWeight: FontWeight.w800);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stack = constraints.maxWidth < _labelWidth * 2.4;
          if (stack) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: labelStyle),
                const SizedBox(height: 2),
                Text(text),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: _labelWidth,
                child: Text(label, style: labelStyle),
              ),
              Expanded(child: Text(text)),
            ],
          );
        },
      ),
    );
  }
}

class VicaLogTile extends StatelessWidget {
  const VicaLogTile({
    super.key,
    required this.log,
  });

  final SupervisorLog log;

  @override
  Widget build(BuildContext context) {
    final format = DateFormat('HH:mm');
    return VicaCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _LogIconBox(
              icon: Icons.info_outline, color: VicaColors.primaryDark),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  log.message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: VicaColors.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        height: 1.25,
                      ),
                ),
                const SizedBox(height: 3),
                Text(
                  log.filter.label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: VicaColors.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            format.format(log.createdAt),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: VicaColors.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                ),
          ),
        ],
      ),
    );
  }
}

class _LogIconBox extends StatelessWidget {
  const _LogIconBox({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: color, size: 18),
    );
  }
}

class _IconBox extends StatelessWidget {
  const _IconBox({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: color, size: 24),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.text,
    required this.maxWidth,
  });

  final IconData icon;
  final String text;

  /// 이 항목이 차지해도 되는 최대 폭입니다. Wrap 자식은 폭 제한을 받지 못하므로
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 16, color: const Color(0xFF758198)),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontWeight: FontWeight.w800),
      ),
    );
  }
}

String _empty(String value, String fallback) =>
    value.trim().isEmpty ? fallback : value;

String _statusLabel(String status) {
  return switch (status) {
    'moving' => '운행',
    'waiting' => '대기',
    'error' => '오류',
    'idle' => '대기',
    _ => status.isEmpty ? '대기' : status,
  };
}

String _relativeTime(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.isNegative) {
    return '방금 전';
  }
  if (diff.inSeconds < 60) {
    return '${diff.inSeconds}초 전';
  }
  if (diff.inHours < 1) {
    return '${diff.inMinutes}분 전';
  }
  return '${diff.inHours}시간 전';
}
