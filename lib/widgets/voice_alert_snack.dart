// 이 파일은 음성 연결 알림 띠입니다(2026-11-16 목업 D, 사용자 승인).
//
// '음성: 외부 API 연결 실패 → 로컬 API 로 전환 · 19:42' 처럼 한 줄로 화면 아래 잠깐 뜹니다.
// 앞 동그라미 색: 성공·복귀 초록, 로컬로 전환 주황, 실패 빨강. 같은 내용은 '알림 및 로그 ›
// 연결 상태'에도 남습니다(SupervisorProvider._ingestVoiceEvents).
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
          decoration: BoxDecoration(color: voiceEventColor(event), shape: BoxShape.circle),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                vicaKeepWords('음성: ${event.text}'),
                style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
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
