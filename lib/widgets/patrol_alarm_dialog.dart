// 경비 경보 팝업 네 가지입니다(2026-11-14, 목업 PatrolIntruder·PatrolSound·PatrolLight·
// PatrolDeviceFault).
//
// 순찰 중 사람·큰 소리·불 켜짐·카메라 끊김이 생기면 로봇이 그 자리에 서고 이 팝업이 뜹니다.
// 방식은 도움 요청 팝업과 같습니다 — alarm_id 하나에 팝업 하나. 미션은 관리자가 확인할
// 때까지 10초마다 같은 경보를 다시 보내고, 열린 팝업은 provider 의 patrolAlarm 을 봅니다.
// 확인(다른 폰·웹에서 누른 것 포함)·재개·종료가 오면 스스로 닫힙니다. 바깥을 누르거나 뒤로
// 가기로는 닫히지 않습니다.
//
// "확인"은 로봇의 음성 반복만 끕니다. 로봇은 경비 화면의 "순찰 재개"를 누를 때까지 서 있습니다.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/patrol.dart';
import '../providers/settings_provider.dart';
import '../providers/supervisor_provider.dart';
import 'patrol_ui.dart';
import 'vica_ui.dart';

class PatrolAlarmDialog extends StatefulWidget {
  const PatrolAlarmDialog({super.key, required this.alarmId});

  /// 이 팝업이 맡은 경보. 다른 경보로 바뀌면 이 팝업은 닫히고 셸이 새로 띄웁니다.
  final String alarmId;

  @override
  State<PatrolAlarmDialog> createState() => _PatrolAlarmDialogState();
}

class _PatrolAlarmDialogState extends State<PatrolAlarmDialog> {
  /// 닫기를 한 번만 부르기 위한 표시(GoalAlertDialog 와 같은 까닭).
  bool _closing = false;
  bool _sending = false;

  /// '영상 녹화 중 0:18'의 초를 넘기는 1초 박자. 녹화 띠가 보이는 동안에만 돕니다 —
  /// 불 켜짐·카메라 끊김 팝업이나 녹화가 끝난 뒤에는 1초마다 다시 그릴 것이 없습니다.
  Timer? _ticker;

  void _syncTicker(bool needed) {
    if (needed == (_ticker != null)) {
      return;
    }
    _ticker?.cancel();
    _ticker = needed
        ? Timer.periodic(const Duration(seconds: 1), (_) {
            if (mounted) {
              setState(() {});
            }
          })
        : null;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final supervisor = context.watch<SupervisorProvider>();
    final alarm = supervisor.patrolAlarm;

    if (alarm == null || alarm.alarmId != widget.alarmId || alarm.acked) {
      _syncTicker(false);
      if (!_closing) {
        _closing = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Navigator.of(context).pop();
          }
        });
      }
      return const SizedBox.shrink();
    }

    final kind = alarm.kind;
    final palette = PatrolPalette.of(kind);
    final intruder = kind == PatrolAlarmKind.intruder;
    // 영상이 다 저장됐다고 기록이 알려 주면 '녹화 중'을 내립니다.
    final saved = supervisor.patrolRecordFor(alarm.alarmId)?.clipReady ?? false;
    final recording = saved ? null : alarm.recordingSec(supervisor.patrolNow());
    _syncTicker(recording != null);

    return PopScope(
      canPop: false,
      child: VicaDialog(
        icon: patrolIconOf(kind),
        iconColor: palette.icon,
        iconFilled: intruder,
        borderColor: palette.border,
        title: kind.popupTitle,
        body: kind.popupBody(alarm.place, levelDb: alarm.levelDb),
        // 목업의 순서(칸 → 녹화 중 띠 → 버튼)를 지키려고 칸도 content 에 넣습니다.
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (alarm.place.isNotEmpty) ...[
              VicaDialogRow(label: '구역', value: alarm.place),
              const SizedBox(height: 8),
            ],
            // 사람·큰 소리의 감지 위치(거리·방향)는 로봇이 보내지 않아 칸을 두지 않습니다.
            if (kind == PatrolAlarmKind.light) ...[
              const VicaDialogRow(label: '감지 위치', value: '로봇이 있는 곳'),
              const SizedBox(height: 8),
            ],
            if (alarm.clock.isNotEmpty) ...[
              VicaDialogRow(label: '시각', value: alarm.clock),
              const SizedBox(height: 8),
            ],
            VicaDialogRow(label: '종류', value: kind.kindLabel(alarm.levelDb)),
            if (recording != null) ...[
              const SizedBox(height: 12),
              PatrolRecordingStrip(seconds: recording, palette: palette),
            ],
          ],
        ),
        actions: [
          FilledButton(
            onPressed: _sending ? null : () => _acknowledge(supervisor),
            style: intruder
                ? FilledButton.styleFrom(backgroundColor: VicaColors.red)
                : null,
            child: Text(kind.ackLabel),
          ),
        ],
      ),
    );
  }

  /// 확인을 로봇에 보냅니다. 받으면 provider 가 경보를 '확인됨'으로 바꿔 팝업이 스스로
  /// 닫히고, 연결이 없거나 거절이면 팝업은 남고 사유를 한 줄로 알립니다.
  Future<void> _acknowledge(SupervisorProvider supervisor) async {
    final messenger = ScaffoldMessenger.of(context);
    final settings = context.read<SettingsProvider>().settings;
    setState(() => _sending = true);
    // 이 팝업이 맡은 경보의 id 를 보냅니다 — 그사이 새 경보가 걸렸다면 미션이 거절합니다.
    final message =
        await supervisor.acknowledgePatrolAlarm(settings, widget.alarmId);
    if (mounted) {
      setState(() => _sending = false);
    }
    if (message.isNotEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(patrolKeepWords(message))));
    }
  }
}
