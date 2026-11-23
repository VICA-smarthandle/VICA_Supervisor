import 'package:flutter/material.dart';

import '../../models/mic_check.dart';
import '../vica_ui.dart';
import 'step_card.dart' show MicSend;

/// `status.steps` 의 첫 단계(조용히)가 화면 번호 2 입니다(1단계는 점검 시작 안내).
const kMicFirstStepNo = 2;

class MicProgressCard extends StatelessWidget {
  const MicProgressCard(
      {super.key,
      required this.status,
      required this.frame,
      required this.onSend});

  final MicCheckStatus status;
  final MicCheckFrame? frame;
  final MicSend onSend;

  static Color _grade(String g) => switch (g) {
        'pass' => VicaColors.green,
        'warn' => VicaColors.warning,
        'fail' => VicaColors.red,
        _ => VicaColors.border,
      };

  @override
  Widget build(BuildContext context) {
    final noiseAt = status.noiseAtCheck;
    final noiseNow = frame?.noise;
    return VicaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('진행',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          for (var i = 0; i < status.steps.length; i++)
            _row(status.steps[i], i),
          if (noiseAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '잡음: 점검 때 ${noiseAt.toStringAsFixed(4)}'
                '${noiseNow != null ? ' · 지금 ${noiseNow.toStringAsFixed(4)}' : ''}',
                style: const TextStyle(fontSize: 12, color: VicaColors.muted),
              ),
            ),
          const SizedBox(height: 12),
          const Wrap(
            spacing: 12,
            children: [
              _Legend('●', VicaColors.green, '통과'),
              _Legend('●', VicaColors.warning, '주의'),
              _Legend('●', VicaColors.red, '실패'),
              _Legend('○', VicaColors.muted, '아직'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(({String key, String name, int need}) s, int index) {
    final got = status.progress[s.key] ?? const <String>[];
    final count = got.length > s.need ? got.length : s.need;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text('${index + kMicFirstStepNo} ${s.name}',
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (var i = 0; i < count; i++)
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color:
                          i < got.length ? _grade(got[i]) : Colors.transparent,
                      border: Border.all(
                        color: i < got.length
                            ? _grade(got[i])
                            : VicaColors.borderStrong,
                        width: 1.5,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (got.isNotEmpty)
            SizedBox(
              height: 28,
              child: TextButton(
                onPressed: () => onSend('redo', {'step': s.key}),
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
                child: const Text('다시', style: TextStyle(fontSize: 12)),
              ),
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
          Text(mark, style: TextStyle(color: color, fontSize: 11)),
          const SizedBox(width: 3),
          Text(text,
              style: const TextStyle(fontSize: 11, color: VicaColors.muted)),
        ],
      );
}
