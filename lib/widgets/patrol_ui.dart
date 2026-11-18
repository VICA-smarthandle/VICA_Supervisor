// 경비(순찰) 화면들이 함께 쓰는 색·작은 위젯·지도 위 순찰 번호입니다(2026-11-14).
//
// 색과 모양은 '앱 UI 사전확인' 캔버스의 Patrol* 목업에서 옮겼습니다. 경비 화면은 여기 있는
// 이름만 쓰고 직접 Color(0x..) 를 적지 않습니다(VicaColors 와 같은 규칙).
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../models/patrol.dart';
import 'vica_ui.dart';

class PatrolColors {
  const PatrolColors._();

  // 순찰 중(손잡이 LED 의 연두와 짝).
  static const runningTint = Color(0xFFEEF6E0);
  static const runningInk = Color(0xFF3F5F12);
  static const runningDot = Color(0xFF8CC63F);

  /// 경비가 꺼져 있을 때의 회색 점.
  static const offDot = Color(0xFFC9C5BC);

  // 침입(빨강).
  static const intruderTint = Color(0xFFFBEDEB);
  static const intruderInk = Color(0xFFA4473B);
  static const intruderSoftBorder = Color(0xFFE8C3BD);

  // 큰 소리·카메라 끊김(호박색).
  static const amberBorder = Color(0xFFD9A55A);
  static const amberTint = Color(0xFFFBE9CF);
  static const amberInk = Color(0xFF8A5A12);

  // 불 켜짐(연노랑).
  static const lightBorder = Color(0xFFE8C94A);
  static const lightTint = Color(0xFFFBF1C2);
  static const lightInk = Color(0xFF7A5C00);

  // 경로 편집에서 번호가 당겨진 줄.
  static const shiftedTint = Color(0xFFFFF6D6);
  static const shiftedInk = Color(0xFF8A6A00);

  // 영상 창.
  static const videoFrame = Color(0xFF1F201E);
  static const videoScreen = Color(0xFF2B2D2A);
  static const videoTrack = Color(0xFF4A4C47);
  static const videoProgress = Color(0xFF8CC9C2);
  static const videoDetectMark = Color(0xFFF08A7E);
  static const videoLastMark = Color(0xFFB9B6AE);
  static const videoLabel = Color(0xFFC9C5BC);
}

/// 경보 종류 하나의 색 묶음.
class PatrolPalette {
  const PatrolPalette({
    required this.border,
    required this.softBorder,
    required this.tint,
    required this.ink,
    required this.icon,
  });

  /// 팝업 테두리(2px).
  final Color border;

  /// 멈춤 화면 상태 칸의 테두리.
  final Color softBorder;

  /// 옅은 바탕(상태 알약·기록 줄 아이콘 칸·녹화 중 띠).
  final Color tint;

  /// 그 바탕 위의 글자.
  final Color ink;

  /// 아이콘 색.
  final Color icon;

  static PatrolPalette of(PatrolAlarmKind kind) => switch (kind) {
        PatrolAlarmKind.intruder => const PatrolPalette(
            border: VicaColors.red,
            softBorder: PatrolColors.intruderSoftBorder,
            tint: PatrolColors.intruderTint,
            ink: PatrolColors.intruderInk,
            icon: VicaColors.red,
          ),
        PatrolAlarmKind.light => const PatrolPalette(
            border: PatrolColors.lightBorder,
            softBorder: PatrolColors.lightBorder,
            tint: PatrolColors.lightTint,
            ink: PatrolColors.lightInk,
            icon: PatrolColors.lightInk,
          ),
        PatrolAlarmKind.sound ||
        PatrolAlarmKind.cameraLost =>
          const PatrolPalette(
            border: PatrolColors.amberBorder,
            softBorder: PatrolColors.amberBorder,
            tint: PatrolColors.amberTint,
            ink: PatrolColors.amberInk,
            icon: PatrolColors.amberInk,
          ),
      };
}

IconData patrolIconOf(PatrolAlarmKind kind) => switch (kind) {
      PatrolAlarmKind.intruder => Icons.person_outline,
      PatrolAlarmKind.sound => Icons.volume_up_outlined,
      PatrolAlarmKind.light => Icons.lightbulb_outline,
      PatrolAlarmKind.cameraLost => Icons.no_photography_outlined,
    };

/// 어절(띄어쓰기) 단위로만 줄이 바뀌게 합니다([vicaKeepWords]).
///
/// 띄어쓰기 없는 긴 토막(로봇이 보낸 오류 원문·주소)이 섞인 글은 그대로 둡니다 — 묶으면
/// 한 줄에 못 들어가 넘칩니다.
String patrolKeepWords(String text) {
  for (final word in text.split(RegExp(r'\s+'))) {
    if (word.length > 16) {
      return text;
    }
  }
  return vicaKeepWords(text);
}

/// 화면 아래 한 줄 알림. 빈 문구는 띄우지 않습니다.
void showPatrolToast(BuildContext context, String message) {
  if (message.isEmpty) {
    return;
  }
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(patrolKeepWords(message))));
}

/// 점 하나와 굵은 글자의 상태 알약('● 순찰 중', '● 일시정지 — 침입 감지').
class PatrolChip extends StatelessWidget {
  const PatrolChip({
    super.key,
    required this.label,
    required this.tint,
    required this.ink,
    required this.dot,
  });

  final String label;
  final Color tint;
  final Color ink;
  final Color dot;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 26),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: ink,
                fontSize: 12,
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

/// 감시 항목 줄 끝의 스위치 그림(목업 PatrolHome 의 '켜짐' 모양, 끄면 회색에 손잡이가 왼쪽).
/// 누르는 곳은 줄 전체입니다 — 이 위젯은 그림만 그립니다.
class PatrolSwitchMark extends StatelessWidget {
  const PatrolSwitchMark({super.key, required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: on ? '켜짐' : '꺼짐',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 44,
        height: 26,
        padding: const EdgeInsets.all(3),
        alignment: on ? Alignment.centerRight : Alignment.centerLeft,
        decoration: BoxDecoration(
          color: on ? VicaColors.primary : PatrolColors.offDot,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Container(
          width: 20,
          height: 20,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

/// '영상 녹화 중 0:18' 띠(목업 PatrolIntruder·PatrolSound).
class PatrolRecordingStrip extends StatelessWidget {
  const PatrolRecordingStrip({
    super.key,
    required this.seconds,
    required this.palette,
  });

  final int seconds;
  final PatrolPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: palette.tint,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              color: VicaColors.red,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '영상 녹화 중 ${patrolDuration(seconds)}',
              style: TextStyle(
                color: palette.ink,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 경비 기록 한 줄(목업 PatrolLog). 영상이 있으면 길이가 적힌 재생 버튼, 불 켜짐 사진이
/// 있으면 사진 버튼이 붙습니다.
class PatrolRecordTile extends StatelessWidget {
  const PatrolRecordTile({
    super.key,
    required this.record,
    this.onPlay,
    this.onPhoto,
  });

  final PatrolRecord record;
  final VoidCallback? onPlay;
  final VoidCallback? onPhoto;

  @override
  Widget build(BuildContext context) {
    final palette = PatrolPalette.of(record.kind);
    return VicaCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: palette.tint,
              borderRadius: BorderRadius.circular(10),
            ),
            child:
                Icon(patrolIconOf(record.kind), size: 20, color: palette.icon),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.title,
                  style: const TextStyle(
                    color: VicaColors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (record.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    record.subtitle,
                    style: const TextStyle(
                      color: VicaColors.textTertiary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (record.clipReady && onPlay != null) ...[
            const SizedBox(width: 8),
            Semantics(
              label: _playLabel(record.clipSec),
              button: true,
              excludeSemantics: true,
              child: PressScale(child: OutlinedButton.icon(
                onPressed: onPlay,
                style: patrolSmallButtonStyle(),
                icon: const Icon(Icons.play_arrow, size: 16),
                label: Text(record.clipLength, style: patrolSmallButtonText),
              )),
            ),
          ] else if (record.hasPhoto && onPhoto != null) ...[
            const SizedBox(width: 8),
            Semantics(
              label: record.kind.shortTitle,
              button: true,
              excludeSemantics: true,
              child: PressScale(child: OutlinedButton(
                onPressed: onPhoto,
                style: patrolSmallButtonStyle(),
                child: const Icon(Icons.image_outlined, size: 16),
              )),
            ),
          ],
        ],
      ),
    );
  }

  /// 화면 낭독기가 읽는 말 — '영상 재생 0분 42초'.
  static String _playLabel(double? seconds) {
    if (seconds == null) {
      return '영상 재생';
    }
    final total = seconds.floor();
    return '영상 재생 ${total ~/ 60}분 ${total % 60}초';
  }
}

/// 카드 안의 작은 외곽선 버튼('경로 편집', '영상 보기', 재생 길이). 테마의 최소 폭(무한대)을
/// 풀어 Row 안에서 내용 폭만 쓰게 합니다.
///
/// 글자 크기는 여기(ButtonStyle.textStyle)가 아니라 글자 위젯에 [patrolSmallButtonText] 로
/// 줍니다. 여기에 주면 테마의 글꼴까지 통째로 바뀌어 한글이 네모(□)로 나옵니다 —
/// app.dart 의 kVicaFontFamily 주석과 같은 사정입니다.
ButtonStyle patrolSmallButtonStyle(
    {Color foreground = VicaColors.primaryDark}) {
  return OutlinedButton.styleFrom(
    foregroundColor: foreground,
    minimumSize: const Size(0, 34),
    padding: const EdgeInsets.symmetric(horizontal: 12),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  );
}

/// [patrolSmallButtonStyle] 버튼의 글자.
const TextStyle patrolSmallButtonText =
    TextStyle(fontSize: 13, fontWeight: FontWeight.w700);

/// '경비 종료'·'경로 삭제'처럼 되돌리기 어려운 쪽의 외곽선 버튼.
ButtonStyle patrolDangerOutlineStyle() {
  return OutlinedButton.styleFrom(
    foregroundColor: PatrolColors.intruderInk,
    side: const BorderSide(color: PatrolColors.intruderSoftBorder),
  );
}

// ---- 지도 위 순찰 번호 ------------------------------------------------------

/// 순찰 번호 원의 지름. 지도 점(5)보다 크게 둡니다 — 번호를 읽어야 합니다. 폰 앱은 지도의
/// 다른 표시처럼 조금 줄입니다(map_canvas.dart 의 플랫폼 배율과 같은 까닭).
const double kPatrolBadgeSize = kIsWeb ? 16 : 14;

enum PatrolMarkStyle {
  /// 채운 원 + 흰 번호.
  normal,

  /// 다음에 갈 장소 — 흰 원 + 바깥 고리.
  next,

  /// 방금 번호가 당겨진 장소 — 노란 테두리.
  shifted,

  /// 경보로 멈춘 화면 — 흐리게, 번호 없이.
  faded,
}

/// 지도 위 장소 하나의 표시. [number] 가 없으면 순찰 경로 밖의 장소입니다(이름만 붙입니다).
class PatrolPlaceMark {
  const PatrolPlaceMark({
    required this.id,
    required this.x,
    required this.y,
    required this.name,
    this.number,
    this.style = PatrolMarkStyle.normal,
  });

  final String id;
  final double x;
  final double y;
  final String name;
  final int? number;
  final PatrolMarkStyle style;
}

/// MapCanvas.overlayBuilder 에 넘길 위젯들을 만듭니다.
///
/// [showNames] 면 장소 이름을 점 옆에 늘 보입니다(경로 편집). [onTap] 이 있으면 번호 원을
/// 눌러 그 장소를 뺄 수 있습니다 — 번호 없는 장소의 탭은 MapCanvas 의 장소 점이 받습니다.
List<Widget> buildPatrolMapOverlay(
  Offset Function(double x, double y) toPixel,
  List<PatrolPlaceMark> marks, {
  bool showNames = false,
  ValueChanged<String>? onTap,
}) {
  return [
    if (showNames)
      for (final mark in marks)
        if (mark.name.isNotEmpty)
          _PatrolNameLabel(
            offset: toPixel(mark.x, mark.y),
            name: mark.name,
            numbered: mark.number != null,
          ),
    for (final mark in marks)
      if (mark.number != null)
        _PatrolBadge(
          offset: toPixel(mark.x, mark.y),
          mark: mark,
          onTap: onTap == null ? null : () => onTap(mark.id),
        ),
  ];
}

class _PatrolBadge extends StatelessWidget {
  const _PatrolBadge({
    required this.offset,
    required this.mark,
    required this.onTap,
  });

  final Offset offset;
  final PatrolPlaceMark mark;
  final VoidCallback? onTap;

  /// 손가락 판. 번호 원은 작아도 눌리는 자리는 이만큼 둡니다.
  static const double _hit = 28;

  /// 브랜드색을 흰 바탕에 55 % 얹은 색(목업 PatrolPaused 의 흐린 원).
  static final Color _fadedFill = Color.alphaBlend(
    VicaColors.primary.withValues(alpha: 0.55),
    Colors.white,
  );

  @override
  Widget build(BuildContext context) {
    const size = kPatrolBadgeSize;
    final next = mark.style == PatrolMarkStyle.next;
    final faded = mark.style == PatrolMarkStyle.faded;
    final circle = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        // 흐린 원은 투명하게 두지 않고 옅은 색으로 칠합니다 — 투명하면 밑의 장소 점이 비칩니다.
        color: next ? Colors.white : (faded ? _fadedFill : VicaColors.primary),
        shape: BoxShape.circle,
        border: Border.all(
          color: switch (mark.style) {
            PatrolMarkStyle.next => VicaColors.primary,
            PatrolMarkStyle.shifted => PatrolColors.lightBorder,
            _ => Colors.white,
          },
          width: mark.style == PatrolMarkStyle.shifted ? 2 : 1.5,
        ),
      ),
      child: faded
          ? null
          : Text(
              '${mark.number}',
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                color: next ? VicaColors.primaryDark : Colors.white,
                fontSize: size * 0.56,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
    );
    final badge = SizedBox(
      width: _hit,
      height: _hit,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (next)
            Container(
              width: size + 8,
              height: size + 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: VicaColors.primary, width: 1.5),
              ),
            ),
          circle,
        ],
      ),
    );
    return Positioned(
      left: offset.dx - _hit / 2,
      top: offset.dy - _hit / 2,
      child: onTap == null
          // 누를 일이 없으면 손가락을 가로채지 않습니다(아래 장소 점의 이름 보기).
          ? IgnorePointer(child: badge)
          : Semantics(
              label: '${mark.name} 빼기',
              button: true,
              child: GestureDetector(
                key: ValueKey('patrol_badge_${mark.id}'),
                onTap: onTap,
                behavior: HitTestBehavior.opaque,
                child: badge,
              ),
            ),
    );
  }
}

class _PatrolNameLabel extends StatelessWidget {
  const _PatrolNameLabel({
    required this.offset,
    required this.name,
    required this.numbered,
  });

  final Offset offset;
  final String name;
  final bool numbered;

  @override
  Widget build(BuildContext context) {
    // 번호 원이 있는 장소는 원 밖으로, 없는 장소는 점 바로 옆에 붙입니다.
    final gap = numbered ? kPatrolBadgeSize / 2 + 2 : 5.0;
    return Positioned(
      left: offset.dx + gap,
      top: offset.dy - 7,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            name,
            maxLines: 1,
            softWrap: false,
            textScaler: TextScaler.noScaling,
            style: const TextStyle(
              color: VicaColors.text,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}
