import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/goal_event.dart';
import '../providers/supervisor_provider.dart';
import 'dock_dialogs.dart' show DockChoiceRow;
import 'vica_ui.dart';

class GoalAlertDialog extends StatefulWidget {
  const GoalAlertDialog({super.key, required this.event, this.onRedoDock});

  final GoalEvent event;

  /// '도크 위치 다시 잡기'(2026-11-19, 목업 92) — 지도 설정의 도크 위치 칸으로 보냅니다.
  final VoidCallback? onRedoDock;

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
    final redoDock = event.showsDockRedo;
    return VicaDialog(
      icon: failure ? Icons.error_outline : Icons.info_outline,
      iconColor: failure ? VicaColors.red : VicaColors.primary,
      title: event.title,
      body: event.description,
      content: redoDock
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _DockRedoBox(),
                const SizedBox(height: 20),
                DockChoiceRow(
                  left: PressScale(
                      child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('확인'),
                  )),
                  right: PressScale(
                      child: FilledButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onRedoDock?.call();
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                    ),
                    child: Text(
                      vicaKeepWords('도크 위치 다시 잡기'),
                      textAlign: TextAlign.center,
                    ),
                  )),
                ),
              ],
            )
          : null,
      rows: [
        for (final (label, value) in event.detailRows)
          VicaDialogRow(label: label, value: value),
      ],
      actions: [
        if (!redoDock)
          PressScale(
              child: FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('확인'),
          )),
      ],
    );
  }
}

/// 목업 92 의 회색 칸 — 지정한 자리나 방향이 도크와 다를 수 있다는 안내와 다시 잡는 두 가지 방법.
class _DockRedoBox extends StatelessWidget {
  const _DockRedoBox();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: VicaColors.background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, line) in GoalEvent.dockRedoLines.indexed) ...[
            if (i > 0) const SizedBox(height: 4),
            Text(
              vicaKeepWords(line),
              style: const TextStyle(
                  color: VicaColors.muted, fontSize: 13, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }
}
