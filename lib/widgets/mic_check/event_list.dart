import 'package:flutter/material.dart';

import '../../models/mic_check.dart';
import '../vica_ui.dart';

/// 화면에 보이는 알림 수(옛 페이지와 같은 6건). 컨트롤러는 50건까지 들고 있습니다.
const kMicEventsShown = 6;

class MicEventList extends StatelessWidget {
  const MicEventList({super.key, required this.events});

  /// 새것이 앞.
  final List<MicCheckEvent> events;

  static Color _color(String grade) => switch (grade) {
        'pass' => VicaColors.green,
        'fail' => VicaColors.red,
        _ => VicaColors.warning,
      };

  @override
  Widget build(BuildContext context) {
    final shown = events.take(kMicEventsShown).toList();
    return VicaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('실시간 판정',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          if (shown.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('아직 판정이 없습니다. 말하면 여기에 쌓입니다.',
                  style: TextStyle(fontSize: 13, color: VicaColors.muted)),
            )
          else
            for (final e in shown)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      margin: const EdgeInsets.only(top: 4, right: 8),
                      decoration: BoxDecoration(
                          color: _color(e.grade), shape: BoxShape.circle),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.title,
                              style:
                                  const TextStyle(fontSize: 13, height: 1.45)),
                          if (e.detail.isNotEmpty)
                            Text(e.detail,
                                style: const TextStyle(
                                    fontSize: 12, color: VicaColors.muted)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(e.time,
                        style: const TextStyle(
                            fontSize: 13, color: VicaColors.muted)),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
