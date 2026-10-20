import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/goal_event.dart';
import '../providers/supervisor_provider.dart';
import 'vica_ui.dart';

class GoalAlertDialog extends StatefulWidget {
  const GoalAlertDialog({super.key, required this.event});

  final GoalEvent event;

  @override
  State<GoalAlertDialog> createState() => _GoalAlertDialogState();
}

class _GoalAlertDialogState extends State<GoalAlertDialog> {
  /// 닫기를 한 번만 부르기 위한 표시. 닫히는 프레임 사이에 build 가 또 돌면
  bool _closing = false;

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final supervisor = context.watch<SupervisorProvider>();

    if (!_closing && supervisor.isGoalAlertResolved(event.id)) {
      _closing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pop();
        }
      });
    }

    final failure = event.isFailure;
    return VicaDialog(
      icon: failure ? Icons.error_outline : Icons.info_outline,
      iconColor: failure ? VicaColors.red : VicaColors.primary,
      title: event.title,
      body: event.description,
      rows: [
        for (final (label, value) in event.detailRows)
          VicaDialogRow(label: label, value: value),
      ],
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('확인'),
        ),
      ],
    );
  }
}
