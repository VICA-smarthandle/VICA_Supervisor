// 이 파일은 마이크 점검 화면의 '최근 10초' 카드(캔버스 108)를 그립니다.
// 소리 크기(로그)·"비카야" 점수(선형) 두 줄과 수음 최소 점선을 한 판에 겹쳐 그립니다.
import 'package:flutter/material.dart';

import '../../services/mic_check_controller.dart' show kMicHistory;
import '../vica_ui.dart';
import 'live_card.dart' show micLinPos, micLogPos;

class MicRecentGraph extends StatelessWidget {
  const MicRecentGraph({
    super.key,
    required this.rms,
    required this.wake,
    required this.listenMin,
  });

  final List<double> rms;
  final List<double> wake;

  /// 수음 최소(`values.listen_min_rms`). 모르면 null.
  final double? listenMin;

  @override
  Widget build(BuildContext context) {
    return VicaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('최근 10초', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          SizedBox(
            height: 120,
            child: ClipRect(
              child: CustomPaint(
                painter: _GraphPainter(List.of(rms), List.of(wake), listenMin),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Wrap(
            spacing: 14,
            children: [
              _Legend('━', VicaColors.primary, '소리 크기'),
              _Legend('━', VicaColors.warning, '“비카야” 점수'),
              _Legend('┄', VicaColors.muted, '수음 최소'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend(this.mark, this.color, this.text);
  final String mark;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(mark, style: TextStyle(color: color, fontSize: 12)),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontSize: 12, color: VicaColors.muted)),
        ],
      );
}

class _GraphPainter extends CustomPainter {
  _GraphPainter(this.rms, this.wake, this.listenMin);

  final List<double> rms;
  final List<double> wake;
  final double? listenMin;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = VicaColors.surfaceSunken);
    final step = size.width / (kMicHistory - 1);

    if (listenMin != null) {
      final y = size.height - micLogPos(listenMin!) * size.height;
      final paint = Paint()
        ..color = VicaColors.text.withValues(alpha: 0.55)
        ..strokeWidth = 1;
      for (double x = 0; x < size.width; x += 8) {
        canvas.drawLine(Offset(x, y), Offset(x + 4, y), paint);
      }
    }
    _line(canvas, size, step, rms, micLogPos, VicaColors.primary);
    _line(canvas, size, step, wake, micLinPos, VicaColors.warning);
  }

  // 오른쪽 끝이 '지금'. 점이 125개보다 적으면 왼쪽을 비워 둡니다.
  void _line(Canvas canvas, Size size, double step, List<double> data, double Function(double) pos, Color color) {
    if (data.length < 2) return;
    final off = kMicHistory - data.length;
    final path = Path();
    for (var i = 0; i < data.length; i++) {
      final x = step * (i + off);
      final y = size.height - pos(data[i]) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_GraphPainter old) => true;
}
