// 이 파일은 VICA_Supervisor 화면들이 공통으로 사용하는 모바일 카드형 UI 위젯을 제공합니다.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/layout_breakpoints.dart';
import '../models/robot_status.dart';
import '../models/supervisor_log.dart';

/// 모서리 둥글기. 화면마다 제각기 숫자를 적으면 같은 카드가 화면마다 다르게
/// 보인다. Figma 의 라운딩 토큰과 같은 값이다.
///
/// 여기(app.dart 가 아니라)에 두는 이유는 import 방향 때문이다. app.dart 는
/// 이 파일을 읽지만 이 파일은 app.dart 를 읽지 않는다 — 반대로 두면 순환된다.
///
/// 버튼에는 상수가 없다. StadiumBorder(완전한 알약)라 높이가 곧 반지름이다.
const double kVicaCardRadius = 20;
const double kVicaFieldRadius = 14;

/// 앱 전체가 쓰는 색. 화면은 여기 있는 이름만 쓰고 직접 Color(0x..) 를 적지 않는다.
///
/// 값은 Figma 파일 'VICA Supervisor — UI Redesign' 의 VICA Tokens 컬렉션과 같다.
/// 디자인이 바뀌면 이 열 몇 줄만 고치면 되고, 화면 파일은 건드리지 않는다.
///
/// 색 계열을 파랑에서 세이지 틸로 바꿨다(2026-09-14). 이전 팔레트는 채도가 높아
/// 상태색(초록·빨강)과 브랜드색이 화면에서 서로 다퉜다. 바탕도 회색에 가까워
/// 카드와 구분이 약했다. 지금은 바탕이 따뜻한 오프화이트라 흰 카드가 떠 보인다.
class VicaColors {
  const VicaColors._();

  // ---- 바탕과 면 --------------------------------------------------------
  static const background = Color(0xFFF4F2ED);
  static const card = Colors.white;

  /// 카드 **안**에서 한 단계 가라앉히는 칸. 정보 칸·입력칸·짝수 행에 쓴다.
  /// 카드와 같은 흰색을 쓰면 경계가 사라져 표가 읽히지 않는다.
  static const surfaceSunken = Color(0xFFFAF8F4);

  static const border = Color(0xFFE6E1D8);

  /// 외곽선 버튼처럼 선 자체가 버튼의 경계일 때. border 는 너무 옅어 눌리는
  /// 자리로 보이지 않는다.
  static const borderStrong = Color(0xFFD5CEC2);

  // ---- 브랜드 -----------------------------------------------------------
  static const primary = Color(0xFF3E7C76);
  static const primaryDark = Color(0xFF2F625D);

  /// primary 의 옅은 배경. 선택된 메뉴, 안내 상자, 진행 중 배지에 쓴다.
  static const accentTint = Color(0xFFE5F0EE);

  // ---- 글자 -------------------------------------------------------------
  static const text = Color(0xFF232622);
  static const muted = Color(0xFF5E6159);

  /// muted 보다 한 단계 더 옅다. 값 위에 붙는 작은 라벨용.
  /// 본문에 쓰면 대비가 모자란다.
  static const textTertiary = Color(0xFF93968C);

  // ---- 상태 -------------------------------------------------------------
  //
  // RobotFault.SEVERITY_* 와 짝이 맞는다. 등급이 다섯인데 색은 넷인 이유는
  // stop 과 fault 가 같은 빨강을 쓰기 때문이다(fault_severity.dart 참고).
  static const green = Color(0xFF4A8A5C);

  /// 주의(WARN). 이전에는 fault_severity.dart 와 home_position_card.dart 가
  /// 각자 0xFFE0A800 / 0xFFA8730F 를 들고 있어 같은 '주의'가 두 색이었다.
  static const warning = Color(0xFFB4802F);

  /// 기능 저하(DEGRADED). 주의보다 붉다 — 등급이 한 단계 위임을 색으로 알린다.
  static const degraded = Color(0xFFC2743A);

  static const red = Color(0xFFC25F52);
}

/// 화면 본문의 공통 틀. 좌우 여백·최대 폭·세로 스크롤을 맡는다.
///
/// 제목은 이제 선택이다(2026-09-14 리디자인). 화면 제목은 AppBar 가 그리므로
/// 본문이 다시 적으면 같은 글자가 두 번 보인다. 모드 선택처럼 AppBar 가 없는
/// 화면만 제목을 넘긴다.
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
///
/// 시안의 status chip 이다. 배경은 상태색을 옅게 깐 것이라 색 상수를 새로 두지
/// 않는다 — 상태색이 바뀌면 배경도 따라간다.
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
  /// 시안에서 '완료' 단계와 비상정지 팝업이 이 모양이다.
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

/// 카드 맨 위 제목 줄. 왼쪽 제목, 오른쪽 배지나 버튼.
class VicaCardHeader extends StatelessWidget {
  const VicaCardHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.bottomSpacing = 14,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final double bottomSpacing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottomSpacing),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 10),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// 카드 안에서 한 단계 가라앉힌 칸. 작은 라벨 위, 굵은 값 아래.
///
/// 시안이 좌표·목적지·받는 곳처럼 "이름표 + 값" 을 전부 이 모양으로 그린다.
class VicaValueTile extends StatelessWidget {
  const VicaValueTile({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.icon,
    this.trailing,
    this.valueFontSize = 15,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final IconData? icon;
  final Widget? trailing;
  final double valueFontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: VicaColors.surfaceSunken,
        borderRadius: BorderRadius.circular(kVicaFieldRadius),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            VicaIconCircle(icon: icon!, size: 36, iconSize: 18),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: VicaColors.textTertiary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value.trim().isEmpty ? '-' : value,
                  style: TextStyle(
                    fontSize: valueFontSize,
                    fontWeight: FontWeight.w800,
                    color: valueColor ?? VicaColors.text,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// 앱의 모든 확인 팝업이 쓰는 틀. 왼쪽 위 아이콘 원, 제목, 설명, (선택) 값 줄,
/// 아래 버튼 줄. AlertDialog 대신 이것을 쓰면 화면마다 팝업 모양이 갈리지 않는다.
///
/// 버튼은 그대로 넘긴다(취소는 OutlinedButton, 확정은 FilledButton). 두 개면
/// 나란히, 좁으면 위아래로 접는다. 버튼 폭은 알약 테마가 정하므로 여기서
/// 감싸기만 한다.
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
                  body!,
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
                VicaButtonRow(children: actions),
              ],
            ],
          ),
        ),
      ),
    );
  }
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
///
/// 시안의 카드 아래 버튼 줄('지도에서 찍기 | 저장', '일시정지 | 취소하기')이
/// 전부 이 모양이다. 버튼 하나면 그냥 가로로 꽉 채운다.
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
  /// 대략 이만큼은 있어야 한다.
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
///
/// 왜 접는가. 지도 설정 화면에는 장소·홈·금지구역 세 가지가 들어갑니다. 셋을
/// 모두 펼쳐 두면 지도가 화면 위쪽으로 밀려 손톱만 해지는데, 세 작업 모두
/// **지도를 보면서** 하는 일입니다. 접어 두면 지도가 넓게 보입니다.
///
/// 접는 것이 보기 편해서만은 아닙니다. 세 작업은 지도 터치를 서로 다르게
/// 씁니다 — 장소 찍기·홈 찍기·사각형 끌기. 펼친 칸이 지도 조작권을 가지므로
/// '지금 무엇을 찍는 중인지'가 화면에 늘 드러납니다.
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
  /// 펼치지 않고도 상태를 알 수 있는 값만 넣습니다.
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
          // Material 로 한 번 감쌉니다. InkWell 의 물결은 '가장 가까운 Material'
          // 위에 그려지는데, 그것이 이 칸 뒤의 Scaffold 면 물결이 흰 배경에
          // 가려 보이지 않습니다. 눌러도 아무 반응이 없는 것처럼 보입니다.
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
      // 투명한 Material 한 겹. ListTile·Switch·Checkbox 계열은 잉크를 가장
      // 가까운 Material 에 그리는데, 색 있는 Container 가 그 사이에 있으면
      // 디버그 빌드가 assertion 으로 멈춥니다(2026-09-14 물류 배송 화면).
      // transparency 라 보이는 모양은 그대로입니다.
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

// ROS 연결이 끊긴 동안 로봇 상태를 신뢰할 수 없다는 것을 화면에 알립니다.
// 연결이 끊기면 로봇 실시간 값은 비워지므로, 빈 화면의 이유를 설명하는 역할도 합니다.
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

/// 대시보드 위쪽의 지표 카드. 상태색 하나([color])로 카드 전체의 분위기를 정합니다.
///
/// 흰 카드 넷이 나란히 서면 어느 것이 위험한지 숫자를 읽기 전엔 모릅니다.
/// 카드 배경을 상태색의 옅은 틴트로 깔고 숫자를 상태색으로 찍어, 색만으로
/// 상태가 읽히게 합니다(2026-09-14 시안). 아이콘과 배지는 흰 원·흰 알약이라
/// 틴트 위에서 떠 보입니다.
///
/// [badge] 와 [unit] 은 선택입니다. 없으면 그 자리를 비웁니다.
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
  ///
  /// 카드를 놓는 쪽이 이 값을 배율에 맞춰 늘려야 합니다. 고정 높이로 두면 배율을
  /// 올린 기기에서 카드 아래가 잘립니다. 라벨이 두 줄인 카드까지 들어가는
  /// 값입니다 — 한 줄이면 남는 자리를 아이콘 줄과 숫자 사이가 먹습니다.
  static const double baseHeight = 124;

  final IconData icon;
  final String label;
  final String value;

  /// 카드의 상태색. 숫자·아이콘·배지 글자에 그대로 쓰고, 배경 틴트는
  /// [tintFor] 로 여기서 계산합니다.
  final Color color;
  final int labelMaxLines;
  final double labelFontSize;

  /// 오른쪽 위 흰 알약에 들어가는 짧은 상태 글자('정상', '이상 없음').
  final String? badge;

  /// 큰 숫자 옆에 작게 붙는 단위('대', '건').
  final String unit;

  /// 상태색에서 배경 틴트를 얻습니다.
  ///
  /// 브랜드색은 이미 정해 둔 [VicaColors.accentTint] 를 쓰고, 나머지는 상태색을
  /// 옅게 깝니다. 초록은 다른 색보다 연해 보여 한 단계(12%) 더 진하게 깝니다.
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
              // 배지는 남는 폭만 씁니다. 좁은 카드에서 아이콘을 밀어내면 안 됩니다.
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
              // 카드가 좁아지면 두 자리 숫자가 두 줄로 접혀 카드 아래로 넘쳤습니다.
              // 숫자는 줄을 바꾸지 않고 자리에 맞게 줄어들게 합니다. 지표는 한눈에
              // 읽는 값이라 말줄임표로 자르면 뜻이 사라집니다.
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
            // Wrap은 자식에게 폭 제한을 물려주지 않아 긴 문구가 그대로 카드 밖으로
            // 나갔습니다. 실제로 쓸 수 있는 폭을 재서 각 항목에 직접 넘깁니다.
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final contentWidth = constraints.maxWidth;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 로봇 이름이 길고 창이 좁으면 이름과 배지가 한 줄에 못 들어갑니다.
                      // Wrap으로 두어 그럴 때 배지가 다음 줄로 내려가게 합니다.
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
                          // 좌표를 표시하는 이유: 이 카드에서 10 Hz로 실제 변하는
                          // 값은 좌표뿐입니다. 나머지(상태·현재 위치·마지막 통신)는
                          // 몇 초씩 같은 값이라, 좌표가 없으면 화면이 멈춘 것처럼
                          // 보입니다. 2026-08-02에 "상태가 갱신되지 않는다"는 보고가
                          // 있었고 실제로는 초당 6회 갱신 중이었습니다.
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

// 선택 드롭다운과 그 옆의 실행 버튼을 한 줄에 놓습니다.
//
// 버튼 폭이 고정이라 좁은 창에서는 드롭다운이 130px까지 밀려 지도 이름이 거의
// 보이지 않았습니다. 좁으면 버튼을 아래로 내려 드롭다운이 한 줄을 다 쓰게 합니다.
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

// 라벨과 값을 나란히 보여주는 한 줄입니다. 로봇 상세와 현재 위치 화면이 각자
// 같은 위젯을 들고 있었고 라벨 폭도 92·100으로 달랐습니다. 하나로 합칩니다.
//
// 좁은 창에서는 고정폭 라벨이 값에게 남기는 폭이 너무 적어 값이 여러 줄로 흩어집니다.
// 그럴 때는 라벨을 값 위로 올려 값이 한 줄 전체를 쓰게 합니다.
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
          // 값에게 라벨 열만큼도 남지 않으면 나란히 두는 의미가 없습니다.
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
  /// 부모가 잰 값을 여기로 넘겨야 문구가 카드 밖으로 나가지 않습니다.
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 문구가 여러 줄로 접히면 아이콘이 가운데로 떠 보이므로 첫 줄에 맞춥니다.
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 16, color: const Color(0xFF758198)),
          ),
          const SizedBox(width: 4),
          // 장소 이름은 관리자가 읽어야 할 정보라 말줄임표로 자르지 않고 줄을 바꿉니다.
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
  // 1분 미만을 '방금 전' 하나로 뭉개면 통신이 살아 있는지 화면으로 알 수 없습니다.
  // /robot_status는 10 Hz로 오므로 정상이면 항상 '0초 전'이고, 숫자가 올라가기
  // 시작하면 그 자체가 끊김 신호입니다(2026-08-02).
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
