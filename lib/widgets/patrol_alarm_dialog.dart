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
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (alarm.place.isNotEmpty) ...[
              VicaDialogRow(label: '구역', value: alarm.place),
              const SizedBox(height: 8),
            ],
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
          PressScale(
              child: FilledButton(
            onPressed: _sending ? null : () => _acknowledge(supervisor),
            style: intruder
                ? FilledButton.styleFrom(backgroundColor: VicaColors.red)
                : null,
            child: Text(kind.ackLabel),
          )),
        ],
      ),
    );
  }

  /// 확인을 로봇에 보냅니다. 받으면 provider 가 경보를 '확인됨'으로 바꿔 팝업이 스스로
  Future<void> _acknowledge(SupervisorProvider supervisor) async {
    final messenger = ScaffoldMessenger.of(context);
    final settings = context.read<SettingsProvider>().settings;
    setState(() => _sending = true);
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
