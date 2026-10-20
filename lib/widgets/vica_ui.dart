import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/layout_breakpoints.dart';
import '../models/robot_status.dart';
import '../models/supervisor_log.dart';

/// 모서리 둥글기. 화면마다 제각기 숫자를 적으면 같은 카드가 화면마다 다르게
const double kVicaCardRadius = 20;
const double kVicaFieldRadius = 14;

/// 앱 전체가 쓰는 색. 화면은 여기 있는 이름만 쓰고 직접 Color(0x..) 를 적지 않는다.
class VicaColors {
  const VicaColors._();

  static const background = Color(0xFFF4F2ED);
  static const card = Colors.white;

  /// 카드 **안**에서 한 단계 가라앉히는 칸. 정보 칸·입력칸·짝수 행에 쓴다.
  static const surfaceSunken = Color(0xFFFAF8F4);

  static const border = Color(0xFFE6E1D8);

  /// 외곽선 버튼처럼 선 자체가 버튼의 경계일 때. border 는 너무 옅어 눌리는
  static const borderStrong = Color(0xFFD5CEC2);

  static const primary = Color(0xFF3E7C76);
  static const primaryDark = Color(0xFF2F625D);

  /// primary 의 옅은 배경. 선택된 메뉴, 안내 상자, 진행 중 배지에 쓴다.
  static const accentTint = Color(0xFFE5F0EE);

  static const text = Color(0xFF232622);
  static const muted = Color(0xFF5E6159);

  /// muted 보다 한 단계 더 옅다. 값 위에 붙는 작은 라벨용.
  static const textTertiary = Color(0xFF93968C);

  static const green = Color(0xFF4A8A5C);

  /// 주의(WARN). 이전에는 fault_severity.dart 와 home_position_card.dart 가
  static const warning = Color(0xFFB4802F);

  /// 기능 저하(DEGRADED). 주의보다 붉다 — 등급이 한 단계 위임을 색으로 알린다.
  static const degraded = Color(0xFFC2743A);

  static const red = Color(0xFFC25F52);
}

/// 화면 본문의 공통 틀. 좌우 여백·최대 폭·세로 스크롤을 맡는다.
class VicaPage extends StatelessWidget {
  const VicaPage({
    super.key,
    this.title,
    this.subtitle,
    required this.children,
  });

  final String? title;
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
            16,
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
                    if (title != null) ...[
                      Text(
                        title!,
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
                    ],
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

/// 점 하나와 짧은 글자로 상태를 알리는 알약. '● 정상', '● 주행 중'처럼 쓴다.
class VicaStatusChip extends StatelessWidget {
  const VicaStatusChip({
    super.key,
    required this.label,
    required this.color,
    this.dot = true,
    this.fontSize = 12,
  });

  final String label;
  final Color color;
  final bool dot;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: fontSize,
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 옅은 원 위에 아이콘 하나. 카드 제목 왼쪽, 팝업 맨 위, 메뉴 항목에 쓴다.
class VicaIconCircle extends StatelessWidget {
  const VicaIconCircle({
    super.key,
    required this.icon,
    this.color = VicaColors.primary,
    this.size = 40,
    this.iconSize = 20,
    this.filled = false,
  });

  final IconData icon;
  final Color color;
  final double size;
  final double iconSize;

  /// true 면 원을 상태색으로 꽉 채우고 아이콘을 흰색으로 그린다.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        color: filled ? Colors.white : color,
        size: iconSize,
      ),
    );
  }
}

/// 앱의 모든 확인 팝업이 쓰는 틀. 왼쪽 위 아이콘 원, 제목, 설명, (선택) 값 줄,
class VicaDialog extends StatelessWidget {
  const VicaDialog({
    super.key,
    required this.title,
    this.icon,
    this.iconColor = VicaColors.primary,
    this.body,
    this.content,
    this.rows = const [],
    this.actions = const [],
    this.maxWidth = 440,
  });

  final String title;
  final IconData? icon;
  final Color iconColor;

  /// 짧은 설명 문장. 줄바꿈이 필요하면 content 로 위젯을 넘긴다.
  final String? body;
  final Widget? content;

  /// '목적지 · 회의실 A' 처럼 확인할 값들. 가라앉힌 칸에 라벨·값을 양끝으로 놓는다.
  final List<VicaDialogRow> rows;
  final List<Widget> actions;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null) ...[
                VicaIconCircle(icon: icon!, color: iconColor, size: 44),
                const SizedBox(height: 14),
              ],
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              if (body != null) ...[
                const SizedBox(height: 8),
                Text(
                  vicaKeepWords(vicaBreakAtSentences(body!)),
                  style: const TextStyle(
                    color: VicaColors.muted,
                    fontSize: 14,
                    height: 1.55,
                  ),
                ),
              ],
              if (content != null) ...[
                const SizedBox(height: 12),
                content!,
              ],
              if (rows.isNotEmpty) ...[
                const SizedBox(height: 14),
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  rows[i],
                ],
              ],
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 20),
                VicaButtonRow(foldWidth: 240, children: actions),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 팝업의 '취소' 자리 버튼. 초록(브랜드색) 테두리와 글자의 외곽선 버튼입니다.
class VicaCancelButton extends StatelessWidget {
  const VicaCancelButton({
    super.key,
    required this.onPressed,
    this.label = '취소',
  });

  final VoidCallback? onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: VicaColors.primary,
        side: const BorderSide(color: VicaColors.primary),
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      child: Text(label, textAlign: TextAlign.center),
    );
  }
}

/// 취소·확정 두 버튼짜리 확인 팝업을 띄웁니다. 확정을 눌렀을 때만 true 입니다.
Future<bool> showVicaConfirm(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  IconData? icon,
  Color iconColor = VicaColors.primary,
  String? body,
  Widget? content,
  List<VicaDialogRow> rows = const [],
  String cancelLabel = '취소',
  IconData? confirmIcon,
  bool danger = false,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      void pop(bool value) => Navigator.of(dialogContext).pop(value);
      final style = danger
          ? FilledButton.styleFrom(backgroundColor: VicaColors.red)
          : null;
      return VicaDialog(
        icon: icon,
        iconColor: iconColor,
        title: title,
        body: body,
        content: content,
        rows: rows,
        actions: [
          VicaCancelButton(onPressed: () => pop(false), label: cancelLabel),
          if (confirmIcon == null)
            FilledButton(
              onPressed: () => pop(true),
              style: style,
              child: Text(confirmLabel),
            )
          else
            FilledButton.icon(
              onPressed: () => pop(true),
              style: style,
              icon: Icon(confirmIcon, size: 18),
              label: Text(confirmLabel),
            ),
        ],
      );
    },
  );
  return confirmed == true;
}

/// 버튼 하나('확인')짜리 알림 팝업을 띄우고 닫힐 때까지 기다립니다.
Future<void> showVicaNotice(
  BuildContext context, {
  required String title,
  IconData? icon,
  Color iconColor = VicaColors.primary,
  String? body,
  Widget? content,
  List<VicaDialogRow> rows = const [],
  String okLabel = '확인',
  IconData? okIcon,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      void close() => Navigator.of(dialogContext).pop();
      return VicaDialog(
        icon: icon,
        iconColor: iconColor,
        title: title,
        body: body,
        content: content,
        rows: rows,
        actions: [
          if (okIcon == null)
            FilledButton(onPressed: close, child: Text(okLabel))
          else
            FilledButton.icon(
              onPressed: close,
              icon: Icon(okIcon, size: 18),
              label: Text(okLabel),
            ),
        ],
      );
    },
  );
}

/// 팝업 안의 '라벨 …… 값' 한 줄.
class VicaDialogRow extends StatelessWidget {
  const VicaDialogRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: VicaColors.surfaceSunken,
        borderRadius: BorderRadius.circular(kVicaFieldRadius),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: VicaColors.muted),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: valueColor ?? VicaColors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 버튼 여러 개를 한 줄에 같은 폭으로 놓는다. 좁으면 위아래로 접는다.
class VicaButtonRow extends StatelessWidget {
  const VicaButtonRow({
    super.key,
    required this.children,
    this.spacing = 10,
    this.foldWidth = 320,
  });

  final List<Widget> children;
  final double spacing;

  /// 이 폭 미만이면 세로로 쌓는다. 버튼 두 개에 글자가 네 자씩 들어가려면
  final double foldWidth;

  @override
  Widget build(BuildContext context) {
    if (children.length == 1) {
      return SizedBox(width: double.infinity, child: children.single);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < foldWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(height: spacing),
                children[i],
              ],
            ],
          );
        }
        return Row(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) SizedBox(width: spacing),
              Expanded(child: children[i]),
            ],
          ],
        );
      },
    );
  }
}

/// 제목 줄을 누르면 펼쳐지는 칸입니다. 한 화면에서 여러 작업을 할 때 씁니다.
class VicaExpandPanel extends StatelessWidget {
  const VicaExpandPanel({
    super.key,
    required this.title,
    required this.expanded,
    required this.onTap,
    required this.child,
    this.icon,
    this.summary = '',
    this.summaryColor,
    this.enabled = true,
  });

  final String title;
  final bool expanded;
  final VoidCallback onTap;
  final Widget child;
  final IconData? icon;

  /// 접혀 있을 때 오른쪽에 보이는 한 줄 요약입니다. '3개', '적용됨'처럼
  final String summary;
  final Color? summaryColor;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: VicaColors.card,
        border: Border.all(
          color: expanded ? VicaColors.primary : VicaColors.border,
          width: expanded ? 1.4 : 1,
        ),
        borderRadius: BorderRadius.circular(kVicaCardRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(kVicaCardRadius),
            child: InkWell(
              onTap: enabled ? onTap : null,
              borderRadius: BorderRadius.circular(kVicaCardRadius),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    if (icon != null) ...[
                      Icon(
                        icon,
                        size: 20,
                        color: enabled
                            ? (expanded ? VicaColors.primary : VicaColors.muted)
                            : VicaColors.border,
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                              color:
                                  enabled ? VicaColors.text : VicaColors.muted,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (summary.isNotEmpty) ...[
                      Text(
                        summary,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: summaryColor ?? VicaColors.muted,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      size: 22,
                      color: VicaColors.muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (expanded) ...[
            const Divider(height: 1, color: VicaColors.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: child,
            ),
          ],
        ],
      ),
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
        borderRadius: BorderRadius.circular(kVicaCardRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(type: MaterialType.transparency, child: child),
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

/// 문장 끝(마침표 뒤 공백)에서 줄을 바꿉니다.
String vicaBreakAtSentences(String text) {
  final sentences = <String>[];
  var start = 0;
  for (final match in RegExp(r'\.[ \t]+').allMatches(text)) {
    sentences.add(text.substring(start, match.start + 1));
    start = match.end;
  }
  sentences.add(text.substring(start));

  final out = StringBuffer(sentences.first);
  var previous = sentences.first;
  for (final next in sentences.skip(1)) {
    final joins = previous.trim().length <= kVicaShortSentence ||
        next.trim().length <= kVicaShortSentence;
    out.write(joins ? ' ' : '\n');
    out.write(next);
    previous = next;
  }
  return out.toString();
}

/// 이 글자 수 이하의 문장은 마침표 줄바꿈에서 이웃 문장과 한 줄로 붙습니다.
const int kVicaShortSentence = 16;

/// 어절(띄어쓰기) 단위로만 줄이 바뀌게 합니다.
String vicaKeepWords(String text) {
  return text.replaceAllMapped(
    RegExp(r'(\S)(?=\S)'),
    (m) => '${m[1]}\u2060',
  );
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
                  vicaKeepWords(
                    vicaBreakAtSentences(
                      detail.isEmpty ? '로봇 상태를 받을 수 없습니다.' : detail,
                    ),
                  ),
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

/// 대시보드 위쪽의 지표 카드. 상태색 하나([color])로 카드 전체의 분위기를 정합니다.
class VicaMetricCard extends StatelessWidget {
  const VicaMetricCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.labelMaxLines = 1,
    this.labelFontSize = 12,
    this.badge,
    this.unit = '',
  });

  /// 글자 배율 1.0에서 카드 한 장이 차지하는 높이입니다.
  static const double baseHeight = 124;

  final IconData icon;
  final String label;
  final String value;

  /// 카드의 상태색. 숫자·아이콘·배지 글자에 그대로 쓰고, 배경 틴트는
  final Color color;
  final int labelMaxLines;
  final double labelFontSize;

  /// 오른쪽 위 흰 알약에 들어가는 짧은 상태 글자('정상', '이상 없음').
  final String? badge;

  /// 큰 숫자 옆에 작게 붙는 단위('대', '건').
  final String unit;

  /// 상태색에서 배경 틴트를 얻습니다.
  static Color tintFor(Color color) {
    if (color == VicaColors.primary) {
      return VicaColors.accentTint;
    }
    if (color == VicaColors.green) {
      return color.withValues(alpha: 0.12);
    }
    return color.withValues(alpha: 0.10);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: tintFor(color),
        borderRadius: BorderRadius.circular(kVicaCardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _MetricIconBox(icon: icon, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: badge == null
                      ? const SizedBox.shrink()
                      : _MetricBadge(text: badge!, color: color),
                ),
              ),
            ],
          ),
          const Spacer(),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    maxLines: 1,
                    softWrap: false,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontSize: 28,
                          height: 1.15,
                          color: color,
                        ),
                  ),
                ),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    unit,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: VicaColors.muted,
                    ),
                  ),
                ),
              ],
            ],
          ),
          Text(
            label,
            maxLines: labelMaxLines,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: labelFontSize,
                  height: 1.25,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

/// 흰 원 안의 아이콘. 틴트 배경 위에서 아이콘이 상태색으로 또렷이 보입니다.
class _MetricIconBox extends StatelessWidget {
  const _MetricIconBox({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: const BoxDecoration(
        color: VicaColors.card,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 18),
    );
  }
}

/// 카드 오른쪽 위의 흰 알약. 점과 글자를 상태색으로 찍습니다.
class _MetricBadge extends StatelessWidget {
  const _MetricBadge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: VicaColors.card,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                height: 1.2,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class VicaRobotCard extends StatelessWidget {
  const VicaRobotCard({
    super.key,
    required this.robot,
  });

  final RobotStatus robot;

  @override
  Widget build(BuildContext context) {
    return VicaCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _IconBox(icon: Icons.smart_toy, color: VicaColors.primaryDark),
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
                            text: '마지막 통신: ${_relativeTime(robot.timestamp)}'),
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
    );
  }
}

/// 화면 맨 위 드롭다운(지도·로봇 고르기)의 낮은 칸 장식. 화면마다 이름([label])만
InputDecoration vicaCompactDropdownDecoration(String label) {
  return InputDecoration(
    labelText: label,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
  );
}

/// 칸 머리의 작은 상태 꼬리표('편집 중 · 저장 전'·'레일 적용됨' 등). 옅은 바탕에 같은 색
class VicaStateBadge extends StatelessWidget {
  const VicaStateBadge({super.key, required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
            fontSize: 11.5, fontWeight: FontWeight.w800, color: color),
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
        shape: BoxShape.circle,
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
        shape: BoxShape.circle,
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
