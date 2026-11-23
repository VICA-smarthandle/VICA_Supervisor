import 'package:flutter/material.dart';

import '../models/mode_status.dart';
import 'vica_ui.dart';

/// 알림 종류별 동그라미 색.
Color voiceEventColor(VoiceEvent event) {
  if (event.isSuccess) {
    return VicaColors.green;
  }
  if (event.isFallback) {
    return const Color(0xFFE0A84A);
  }
  return VicaColors.red;
}

String voiceEventClock(DateTime at) =>
    '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';

SnackBar voiceAlertSnackBar(VoiceEvent event) {
  return SnackBar(
    behavior: SnackBarBehavior.floating,
    duration: const Duration(seconds: 6),
    backgroundColor: const Color(0xFF2B2E29),
    content: Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
              color: voiceEventColor(event), shape: BoxShape.circle),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                vicaKeepWords('음성: ${event.text}'),
                style: const TextStyle(
                    fontWeight: FontWeight.w700, color: Colors.white),
              ),
              Text(
                '${voiceEventClock(event.at)} · 알림 및 로그 › 연결 상태에 남았습니다',
                style: const TextStyle(fontSize: 12, color: Color(0xFFC9CCC2)),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
