// 이 파일은 주행 중 대시보드 맨 위의 '주행 노드' 카드입니다(2026-11-16 목업 B·C).
//
// 사용자 11-16 요청 두 가지:
//   - 사람 감지(⑮ detector)만 잠시 끄는 켜기/끄기 — 주행을 다시 켜면 켜진 상태로 돌아갑니다.
//   - 음성을 로컬(LOCAL, 로봇 안 midm2-mini) / 외부 API(클라우드 LLM) 중 고르기.
// '주행 끄기'는 2026-11-18 위쪽 막대로 옮겼습니다(drive_stop_button.dart).
// 2026-11-19 사용자: '빔포밍 회전'(호출 방향 회전) 켜기/끄기 — 음성 노드 서비스로 바로 갑니다.
// 둘 다 젯슨 모드 노드의 서비스로 갑니다. 지금 상태는 /vica/mode_status 만 보고 그립니다.
// 모드 노드가 없거나 주행이 꺼져 있으면 아무것도 그리지 않습니다.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/mode_status.dart';
import '../providers/app_mode_provider.dart';
import '../providers/supervisor_provider.dart';
import 'vica_ui.dart';
import 'voice_alert_snack.dart';

class DriveNodesCard extends StatefulWidget {
  const DriveNodesCard({super.key});

  @override
  State<DriveNodesCard> createState() => _DriveNodesCardState();
}

class _DriveNodesCardState extends State<DriveNodesCard> {
  bool _busy = false;

  Future<void> _run(Future<(bool, String)> Function() call) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    final (ok, message) = await call();
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    // 받아들여도(무엇을 했는지) 거절돼도(왜 안 됐는지) 모드 노드의 말을 그대로 보여 줍니다.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? message : '안 됐습니다: $message')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final supervisor = context.watch<SupervisorProvider>();
    final status = supervisor.modeStatus;
    if (status == null || !status.driveOn) {
      return const SizedBox.shrink();
    }
    final submode = context.watch<AppModeProvider>().driveSubmode;
    final detectorOff = status.detector == 'inactive';
    final beamOn = status.voice == 'active' ? supervisor.wakeDoaTurnOn : null;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: VicaColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: VicaColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                // 좁은 폭·큰 글자에서는 하위 모드 칩이 제목 아래로 내려갑니다.
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // 2026-11-17 사용자: '주행 노드' → '주행 설정'.
                    const Text(
                      '주행 설정',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: VicaColors.text),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: VicaColors.accentTint,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        submode.title,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: VicaColors.primaryDark,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Row(
            icon: detectorOff
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            title: '카메라 감지', // 2026-11-17 사용자: '사람 감지' → '카메라 감지'
            state: _detectorText(status.detector),
            trailing: Switch(
              key: const ValueKey('drive_nodes_detector_switch'),
              value: status.detectorOn,
              onChanged: _busy ||
                      status.detector == 'none' ||
                      status.detector == 'deactivating'
                  ? null
                  : (on) => _run(() => supervisor.setDetector(on)),
            ),
          ),
          if (detectorOff) ...[
            const SizedBox(height: 10),
            // 2026-11-17 제목·문구 간결화(사용자 승인).
            const _Note(
              warning: true,
              text: '감지 꺼짐 · 접근 요청·경비 알림 없음 · 다시 켜면 10~20초',
            ),
          ],
          const Divider(height: 28, color: VicaColors.border),
          // 2026-11-19 사용자: 빔포밍 회전(캔버스 101번 보드). 상태는 음성 노드가 남긴 토픽만 따릅니다.
          // 음성 유닛이 active 가 아니면 남아 있는 값은 낡은 것이라 모름으로 그립니다.
          // 다시 뜨는 중이거나 새 노드가 아직 상태를 안 냈으면 '재가동 중'(11-19 사용자, 캔버스 101 ③).
          _Row(
            icon: beamOn == false
                ? Icons.explore_off_outlined
                : Icons.explore_outlined,
            title: '빔포밍 회전',
            state: _beamText(beamOn, status.voice),
            trailing: Switch(
              key: const ValueKey('drive_nodes_wake_doa_turn_switch'),
              value: beamOn ?? false,
              onChanged: _busy || beamOn == null
                  ? null
                  : (on) => _run(() => supervisor.setWakeDoaTurn(on)),
            ),
          ),
          if (beamOn == false) ...[
            const SizedBox(height: 10),
            const _Note(
              warning: true,
              text: '회전 꺼짐', // 11-19 사용자: '불러도 돌지 않음 · 음성 다시 켜면 켜짐' 뺌
            ),
          ],
          const Divider(height: 28, color: VicaColors.border),
          _Row(
            icon: Icons.mic_none,
            title: '음성 LLM', // 2026-11-17 사용자: '음성' → '음성 LLM'
            state: _voiceLine(status.voice, supervisor.lastVoiceEvent),
            // 폭 상한을 두고 그 안에서 줄인다 — 좁은 폰·큰 글자에서 줄을 밀어내지 않게(11-16 APK 확인).
            trailing: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: DropdownButton<VoiceChoice>(
                isExpanded: true,
                alignment: AlignmentDirectional.centerEnd,
                value: status.voiceChoice,
                underline: const SizedBox.shrink(),
                borderRadius: BorderRadius.circular(12),
                onChanged: _busy
                    ? null
                    : (choice) {
                        if (choice == null || choice == status.voiceChoice) {
                          return;
                        }
                        _run(() => supervisor.setVoice(choice));
                      },
                items: [
                  for (final choice in VoiceChoice.values)
                    DropdownMenuItem(
                      value: choice,
                      // 오른쪽에 붙임(2026-11-17 사용자 지시).
                      alignment: AlignmentDirectional.centerEnd,
                      child: Text(
                        choice.label,
                        overflow: TextOverflow.ellipsis,
                        // 글자를 한 단계 줄임(2026-11-17 사용자 지시).
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          // 2026-11-17 제목·문구 간결화(사용자 승인). 음성 종류 설명(hint)은 뺐습니다.
          const _Note(text: '바꾸면 약 10초 재시작 · 주행 중엔 불가'),
        ],
      ),
    );
  }

  static (String, Color) _detectorText(String state) => switch (state) {
        'active' => ('켜짐', VicaColors.green), // 2026-11-17 간결화(사용자 승인)
        'activating' => ('켜는 중(10~20초)', VicaColors.primary),
        'deactivating' => ('끄는 중', VicaColors.warning),
        'inactive' => ('잠시 꺼짐', const Color(0xFF8A5F1C)),
        'failed' => ('꺼짐(오류) · 다시 켜 보세요', VicaColors.red),
        _ => ('유닛 없음', VicaColors.muted),
      };

  static (String, Color) _beamText(bool? on, String voice) => switch ((on, voice)) {
        (true, _) => ('켜짐', VicaColors.green),
        (false, _) => ('잠시 꺼짐', const Color(0xFF8A5F1C)),
        (null, 'active' || 'activating' || 'deactivating') => ('재가동 중', VicaColors.primary),
        (null, _) => ('음성 꺼짐 · 바꿀 수 없음', VicaColors.muted),
      };

  // 음성 줄: 유닛 상태에 마지막 연결 알림을 붙입니다(목업 D). 색은 알림을 따릅니다.
  static (String, Color) _voiceLine(String state, VoiceEvent? last) {
    final (label, color) = _voiceText(state);
    if (last == null || state != 'active') {
      return (label, color);
    }
    return (
      '$label · ${voiceEventClock(last.at)} ${last.text}',
      voiceEventColor(last)
    );
  }

  static (String, Color) _voiceText(String state) => switch (state) {
        'active' => ('켜짐', VicaColors.green),
        'activating' => ('켜는 중', VicaColors.primary),
        'deactivating' => ('다시 띄우는 중', VicaColors.warning),
        'inactive' => ('꺼짐', VicaColors.muted),
        'failed' => ('꺼짐(오류)', VicaColors.red),
        _ => ('유닛 없음', VicaColors.muted),
      };
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    required this.state,
    required this.trailing,
  });

  final IconData icon;
  final String title;
  final (String, Color) state;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final (label, color) = state;
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: VicaColors.accentTint,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 22, color: VicaColors.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: VicaColors.text),
              ),
              Text(
                vicaKeepWords(label),
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: color),
              ),
            ],
          ),
        ),
        trailing,
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text, this.warning = false});

  final String text;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: warning ? const Color(0xFFFBF3E6) : VicaColors.surfaceSunken,
        borderRadius: BorderRadius.circular(10),
        border: warning ? Border.all(color: const Color(0xFFE8D2AE)) : null,
      ),
      child: Text(
        vicaKeepWords(text),
        style: TextStyle(
          fontSize: 12,
          height: 1.5,
          color: warning ? const Color(0xFF6B4A15) : VicaColors.muted,
        ),
      ),
    );
  }
}
