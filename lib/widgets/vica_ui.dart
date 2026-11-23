import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/layout_breakpoints.dart';
import '../core/log_filter.dart';
import '../models/robot_status.dart';
import '../models/supervisor_log.dart';
import 'vica_motion.dart';

export 'vica_motion.dart';

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

/// 비카 로봇 로고(2026-11-17 사용자 제공, assets/images/vica_robot.png 256px·투명 바탕).
class VicaLogo extends StatelessWidget {
  const VicaLogo({super.key, this.size = 40, this.framed = false});

  final double size;
  final bool framed;

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      'assets/images/vica_robot.png',
      fit: BoxFit.contain,
      semanticLabel: 'VICA',
    );
    if (!framed) return SizedBox.square(dimension: size, child: image);
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.08),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: image,
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
    this.iconFilled = false,
    this.borderColor,
  });

  final String title;
  final IconData? icon;
  final Color iconColor;

  /// true 면 아이콘 원을 [iconColor] 로 채웁니다(경비의 침입 감지 팝업).
  final bool iconFilled;

  /// 있으면 팝업에 이 색 테두리(2px)를 두릅니다. 경비 경보 팝업이 종류를 색으로 가릅니다.
  final Color? borderColor;

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
      shape: borderColor == null
          ? null
          : RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(kVicaCardRadius),
              side: BorderSide(color: borderColor!, width: 2),
            ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null) ...[
                VicaIconCircle(
                  icon: icon!,
                  color: iconColor,
                  size: 44,
                  filled: iconFilled,
                ),
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
    return PressScale(
        child: OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: VicaColors.primary,
        side: const BorderSide(color: VicaColors.primary),
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      child: Text(label, textAlign: TextAlign.center),
    ));
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
  final confirmed = await showVicaDialog<bool>(
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
            PressScale(
                child: FilledButton(
              onPressed: () => pop(true),
              style: style,
              child: Text(confirmLabel),
            ))
          else
            PressScale(
                child: FilledButton.icon(
              onPressed: () => pop(true),
              style: style,
              icon: Icon(confirmIcon, size: 18),
              label: Text(confirmLabel),
            )),
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
  return showVicaDialog<void>(
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
            PressScale(
                child: FilledButton(onPressed: close, child: Text(okLabel)))
          else
            PressScale(
                child: FilledButton.icon(
              onPressed: close,
              icon: Icon(okIcon, size: 18),
              label: Text(okLabel),
            )),
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
          PressScale(
              child: Material(
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
          )),
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
                  '로봇 오프라인',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: VicaColors.red,
                  ),
                ),
                const SizedBox(height: 2),
                const Text('상태 수신 멈춤 · 주소 확인', style: TextStyle(fontSize: 13)),
                if (detail.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    vicaKeepWords(detail),
                    style:
                        const TextStyle(fontSize: 11, color: VicaColors.muted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// [VicaCountStrip] 의 칸 하나. 큰 숫자([value])와 그 아래 작은 라벨.
class VicaCount {
  const VicaCount({
    required this.label,
    required this.value,
    this.color = VicaColors.text,
    this.accent,
  });

  final String label;
  final String value;

  /// 숫자 색. 상태를 색으로 알려야 하는 칸(오류)만 바꿉니다.
  final Color color;

  /// 칸 바탕(아주 옅게)과 라벨 앞 점의 색. 없으면 바탕 없이 그립니다(2026-11-18 사용자).
  final Color? accent;
}

/// 대시보드 위쪽의 숫자 줄. 카드 하나 안에 칸을 나란히 둡니다.
class VicaCountStrip extends StatelessWidget {
  const VicaCountStrip({super.key, required this.items});

  final List<VicaCount> items;

  @override
  Widget build(BuildContext context) {
    return VicaCard(
      padding: const EdgeInsets.all(8),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: _CountCell(item: items[i])),
            ],
          ],
        ),
      ),
    );
  }
}

class _CountCell extends StatelessWidget {
  const _CountCell({required this.item});

  final VicaCount item;

  @override
  Widget build(BuildContext context) {
    final accent = item.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      decoration: BoxDecoration(
        color: accent?.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              item.value,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                height: 1.2,
                color: item.color,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (accent != null) ...[
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
              ],
              Flexible(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.25,
                    color: VicaColors.muted,
                  ),
                ),
              ),
            ],
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
          const VicaLogo(size: 50),
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
                    const SizedBox(height: 12),
                    _RobotCardRow(
                      label: '위치',
                      value: _empty(robot.currentLocation, '수신 대기'),
                    ),
                    const SizedBox(height: 6),
                    _RobotCardRow(
                      label: '목적지',
                      value: _empty(robot.currentGoal, '없음'),
                    ),
                    const SizedBox(height: 6),
                    _RobotCardRow(
                      label: '수신',
                      value: _relativeTime(robot.timestamp),
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

/// 로그 분류의 색(2026-11-17 알림·로그 시각화). 숫자 줄·시간대 막대·로그 줄 점이 같은 색을 씁니다.
Color vicaLogColor(LogFilter filter) => switch (filter) {
      LogFilter.emergencyStop => const Color(0xFFD55E00),
      LogFilter.connection => const Color(0xFF0072B2),
      LogFilter.delivery => const Color(0xFF009E73),
      LogFilter.coordinateTransfer => const Color(0xFFE69F00),
      LogFilter.patrol => const Color(0xFFCC79A7),
      LogFilter.all => VicaColors.primaryDark,
    };

/// 흰 바탕 위 숫자 글자색. 막대·점은 [vicaLogColor] 그대로, 글자만 같은 색조를 어둡게 해
Color vicaLogTextColor(LogFilter filter) => switch (filter) {
      LogFilter.emergencyStop => const Color(0xFFC25600),
      LogFilter.delivery => const Color(0xFF008662),
      LogFilter.coordinateTransfer => const Color(0xFF9C6C00),
      LogFilter.patrol => const Color(0xFFA36186),
      _ => vicaLogColor(filter),
    };

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
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: vicaLogColor(log.filter),
                shape: BoxShape.circle,
              ),
            ),
          ),
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

/// 로봇 카드의 한 줄: 왼쪽 라벨(옅은 글자, 56px) + 오른쪽 값(굵은 글자).
class _RobotCardRow extends StatelessWidget {
  const _RobotCardRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final labelWidth = MediaQuery.textScalerOf(context).scale(56);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: labelWidth,
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: VicaColors.muted),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: VicaColors.text,
            ),
          ),
        ),
      ],
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
