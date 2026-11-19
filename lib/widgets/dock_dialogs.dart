// 이 파일은 '도크 인식해서 저장'이 실패했을 때의 팝업 넷입니다(2026-11-19, 목업 86·87·88 승인).
//
//   도크를 찾지 못했습니다      되는 자세·안 되는 자세 그림, 세울 자리 세 줄, 저장된 도크가 있으면 그 방향
//   도크 인식이 불안정합니다    지금 로봇에서 본 도크(거리·방향)와 경우에 맞는 안내 한 줄
//   초기 위치를 잡아 주세요     로봇 위치를 몰라 도크 위치를 정할 수 없을 때
//   주행이 꺼져 있습니다        도크 서비스가 없을 때(주행 꺼짐)
//
// 새 음성 멘트는 없습니다 — 저장 실패는 이 팝업으로만 알립니다(11-19 사용자).
// 문구와 줄 나눔은 목업 그대로입니다. 틀은 앱의 다른 팝업과 같은 [VicaDialog] 입니다.
// 이 트리의 다른 팝업처럼 showVicaDialog 로 열고 버튼은 PressScale 로 감쌉니다(2026-11-18 클릭 효과).
import 'package:flutter/material.dart';

import '../models/dock_state.dart';
import 'vica_ui.dart';

/// 실패 팝업에서 고른 것.
enum DockSaveFailChoice {
  /// 닫기(바깥을 눌러 닫은 것도 같습니다)
  close,

  /// 다시 찾기 — 같은 자리에서 한 번 더 인식합니다
  retry,

  /// 지도에서 지정 — 지도에서 도크와 도크 앞쪽을 누르는 흐름으로 갑니다
  mapPick,

  /// 초기 위치 잡으러 가기 — 원격 주행 탭으로 갑니다
  initialPose,
}

/// 도크를 찾지 못했을 때 세울 자리 세 줄(목업 86).
const List<String> kDockNotFoundTips = [
  '도크 앞 1 m쯤 (멀어도 2 m 안)',
  '앞머리가 도크 쪽 (정면이 아니어도 됩니다)',
  '로봇과 도크 사이에 물건이 없게',
];

/// 목업 86 — 도크를 찾지 못했습니다. [savedDockHint] 는 도크 위치가 이미 저장돼 있고 로봇 위치를
/// 알 때의 한 줄('저장된 도크는 로봇의 왼쪽 뒤 약 2.3 m에 있습니다.')입니다.
Future<DockSaveFailChoice> showDockNotFoundDialog(
  BuildContext context, {
  String? savedDockHint,
}) async {
  final choice = await showVicaDialog<DockSaveFailChoice>(
    context: context,
    builder: (dialogContext) {
      void pop(DockSaveFailChoice value) => Navigator.of(dialogContext).pop(value);
      return VicaDialog(
        title: vicaKeepWords('도크를 찾지 못했습니다'),
        body: '로봇 앞머리가 도크를 향하게 세운 뒤 다시 눌러 주세요.',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _PostureBox(good: true)),
                  SizedBox(width: 8),
                  Expanded(child: _PostureBox(good: false)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            for (final tip in kDockNotFoundTips)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  vicaKeepWords('· $tip'),
                  style: const TextStyle(color: VicaColors.text, fontSize: 13, height: 1.5),
                ),
              ),
            if (savedDockHint != null) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: VicaColors.background,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  vicaKeepWords(savedDockHint),
                  style: const TextStyle(color: VicaColors.muted, fontSize: 13, height: 1.5),
                ),
              ),
            ],
            const SizedBox(height: 20),
            DockChoiceRow(
              left: _plainButton('닫기', () => pop(DockSaveFailChoice.close)),
              right: _filledButton('다시 찾기', () => pop(DockSaveFailChoice.retry)),
            ),
            const SizedBox(height: 4),
            PressScale(child: TextButton(
              onPressed: () => pop(DockSaveFailChoice.mapPick),
              style: TextButton.styleFrom(
                foregroundColor: VicaColors.primaryDark,
                minimumSize: const Size.fromHeight(44),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.underline,
                ),
              ),
              child: const Text('지도에서 지정'),
            )),
          ],
        ),
      );
    },
  );
  return choice ?? DockSaveFailChoice.close;
}

/// 목업 87 — 도크 인식이 불안정합니다. 로봇이 본 거리·방향은 [result] 의 값입니다.
Future<DockSaveFailChoice> showDockUnstableDialog(
  BuildContext context, {
  required DockRegisterResult result,
}) async {
  final dist = result.distM;
  final choice = await showVicaDialog<DockSaveFailChoice>(
    context: context,
    builder: (dialogContext) {
      void pop(DockSaveFailChoice value) => Navigator.of(dialogContext).pop(value);
      return VicaDialog(
        title: vicaKeepWords('도크 인식이 불안정합니다'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (dist != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: VicaColors.warning.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vicaKeepWords('지금 로봇에서 본 도크'),
                      style: const TextStyle(color: VicaColors.warning, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      vicaKeepWords(dockSeenText(dist, result.bearingDeg ?? 0)),
                      style: const TextStyle(
                        color: VicaColors.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              vicaKeepWords(
                dockUnstableAdvice(distM: dist, obliqueDeg: result.obliqueDeg),
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: VicaColors.text,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                height: 1.55,
              ),
            ),
            const SizedBox(height: 20),
            DockChoiceRow(
              left: _plainButton('닫기', () => pop(DockSaveFailChoice.close)),
              right: _filledButton('다시 찾기', () => pop(DockSaveFailChoice.retry)),
            ),
          ],
        ),
      );
    },
  );
  return choice ?? DockSaveFailChoice.close;
}

/// 목업 88 위 — 초기 위치를 잡아 주세요.
Future<DockSaveFailChoice> showDockNoPoseDialog(BuildContext context) async {
  final choice = await showVicaDialog<DockSaveFailChoice>(
    context: context,
    builder: (dialogContext) {
      void pop(DockSaveFailChoice value) => Navigator.of(dialogContext).pop(value);
      return VicaDialog(
        title: vicaKeepWords('초기 위치를 잡아 주세요'),
        body: '초기 위치가 잡혀 있지 않아 도크 위치를 정할 수 없습니다.',
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: DockChoiceRow(
            left: _plainButton('닫기', () => pop(DockSaveFailChoice.close)),
            // 줄 나눔은 사용자가 넣은 것입니다(목업 88).
            right: _filledButton(
              '초기 위치\n잡으러 가기',
              () => pop(DockSaveFailChoice.initialPose),
            ),
          ),
        ),
      );
    },
  );
  return choice ?? DockSaveFailChoice.close;
}

/// 목업 88 아래 — 주행이 꺼져 있습니다. 도크 서비스가 없을 때입니다(rosbridge 연결이 없는 것은
/// 주행 꺼짐이 아니라 짧은 알림입니다).
///
/// [saving] 은 지도에서 지정한 자리를 저장하다 실패했을 때입니다 — 그때는 도크를 찾던 것이 아니라
/// 첫 줄만 다릅니다(2026-11-19 검토).
Future<void> showDockDriveOffDialog(BuildContext context, {bool saving = false}) {
  return showVicaNotice(
    context,
    title: vicaKeepWords('주행이 꺼져 있습니다'),
    // 줄 나눔은 목업 그대로입니다.
    body: '${saving ? '도크 위치를 저장하려면' : '도크를 찾으려면'} 주행이 켜져 있어야 합니다.\n'
        '주행을 켠 뒤 다시 눌러 주세요.',
  );
}

Widget _plainButton(String label, VoidCallback onPressed) => PressScale(child: OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      child: Text(vicaKeepWords(label), textAlign: TextAlign.center),
    ));

Widget _filledButton(String label, VoidCallback onPressed) => PressScale(child: FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      child: Text(vicaKeepWords(label), textAlign: TextAlign.center),
    ));

/// 두 버튼을 반씩 놓고 높이를 맞춥니다 — 한쪽 글자가 두 줄이어도('초기 위치 / 잡으러 가기') 나란합니다.
/// 도킹 실패 팝업의 '확인 · 도크 위치 다시 잡기'(목업 92)도 이 줄을 씁니다.
class DockChoiceRow extends StatelessWidget {
  const DockChoiceRow({super.key, required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: left),
          const SizedBox(width: 10),
          Expanded(child: right),
        ],
      ),
    );
  }
}

/// 되는 자세('이렇게')와 안 되는 자세('등지면 못 찾습니다') 그림 한 칸(목업 86).
class _PostureBox extends StatelessWidget {
  const _PostureBox({required this.good});

  final bool good;

  @override
  Widget build(BuildContext context) {
    final color = good ? VicaColors.primaryDark : VicaColors.red;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: good ? VicaColors.accentTint : VicaColors.red.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Semantics(
            label: good
                ? '되는 자세 — 로봇이 도크를 향해 약 1 m 앞에 있음'
                : '안 되는 자세 — 로봇이 도크를 등지고 있음',
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: AspectRatio(
                aspectRatio: 140 / 118,
                child: CustomPaint(painter: DockPosturePainter(good: good)),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            vicaKeepWords(good ? '이렇게' : '등지면 못 찾습니다'),
            textAlign: TextAlign.center,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// 벽선·V자 도크·로봇 사각형·앞머리 화살표를 그립니다. 목업 86 의 그림(140 × 118)을 칸 크기에 맞춰 줄입니다.
class DockPosturePainter extends CustomPainter {
  const DockPosturePainter({required this.good});

  /// true: 도크를 향해 선 로봇(되는 자세) · false: 도크를 등진 로봇(안 되는 자세)
  final bool good;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 140;
    canvas.save();
    canvas.scale(k);

    Paint line(Color color, double width) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // 벽과 벽에 붙은 V자 도크
    canvas.drawLine(const Offset(10, 10), const Offset(130, 10),
        line(const Color(0xFF9B978E), 3)..strokeCap = StrokeCap.butt);
    canvas.drawPath(
      Path()
        ..moveTo(58, 24)
        ..lineTo(70, 12)
        ..lineTo(82, 24),
      line(Colors.deepPurple, 3),
    );

    if (good) {
      // 라이다가 도크를 보는 범위(점선)
      final sight = line(VicaColors.primary, 1);
      _dashed(canvas, const Offset(70, 28), const Offset(36, 84), sight);
      _dashed(canvas, const Offset(70, 28), const Offset(104, 84), sight);
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(56, 78, 28, 30), const Radius.circular(5)),
        Paint()..color = VicaColors.primary,
      );
      // 앞머리(위쪽 = 도크 쪽)
      final arrow = line(Colors.white, 2);
      canvas.drawLine(const Offset(70, 96), const Offset(70, 84), arrow);
      canvas.drawLine(const Offset(70, 84), const Offset(66, 88), arrow);
      canvas.drawLine(const Offset(70, 84), const Offset(74, 88), arrow);
      // 거리 눈금
      canvas.drawLine(const Offset(112, 28), const Offset(112, 78),
          line(const Color(0xFF8A877F), 1));
      final label = TextPainter(
        text: const TextSpan(
          text: '1 m',
          style: TextStyle(color: VicaColors.muted, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(116, 54 - label.height / 2));
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(56, 62, 28, 30), const Radius.circular(5)),
        Paint()..color = const Color(0xFFB9B5AC),
      );
      // 앞머리(아래쪽 = 도크 반대쪽)
      final arrow = line(Colors.white, 2);
      canvas.drawLine(const Offset(70, 72), const Offset(70, 86), arrow);
      canvas.drawLine(const Offset(70, 86), const Offset(66, 82), arrow);
      canvas.drawLine(const Offset(70, 86), const Offset(74, 82), arrow);
      // 안 됨 표시
      final cross = line(VicaColors.red, 3);
      canvas.drawLine(const Offset(98, 56), const Offset(114, 72), cross);
      canvas.drawLine(const Offset(114, 56), const Offset(98, 72), cross);
    }
    canvas.restore();
  }

  void _dashed(Canvas canvas, Offset from, Offset to, Paint paint) {
    const dash = 3.0;
    final total = (to - from).distance;
    final step = (to - from) / total;
    for (var d = 0.0; d < total; d += dash * 2) {
      final end = d + dash < total ? d + dash : total;
      canvas.drawLine(from + step * d, from + step * end, paint);
    }
  }

  @override
  bool shouldRepaint(DockPosturePainter oldDelegate) => oldDelegate.good != good;
}
