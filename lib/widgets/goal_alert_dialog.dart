// 주행 실패·취소 팝업 하나. 다섯 가지 goal 이벤트(주행 실패·거부·취소, 홈 복귀
// 실패·취소)가 모두 이 틀을 씁니다(2026-09-30 사용자 결정). 대기 장소 막힘·대기
// 시간 만료(2026-10-07)도 같은 틀입니다.
//
// 틀: 원 아이콘(실패는 빨강, 취소는 파랑) → 제목 → 본문 최대 세 줄 → 아래 칸에
// 목적지·사유 → '확인' 버튼 하나. 본문 각 줄은 폭이 모자라면 띄어쓰기에서만
// 접힙니다(VicaDialog 가 vicaKeepWords 를 거칩니다).
//
// 어디서 띄우는가. 앱 셸(SupervisorShell) 한 곳입니다. 종전에는 원격 주행·물류
// 배송 화면 둘이 각자 띄웠는데, 셸은 지금 보는 화면 하나만 그리므로 대시보드나
// 지도 설정을 보고 있을 때 실패가 오면 **아무것도 뜨지 않았습니다.** 알림은
// 담긴 채로 남았다가 원격 주행 화면을 열어야 그제서야 떴습니다.
//
// 언제 저절로 닫히는가. 로봇이 다시 출발하면(goal_sent 등) 닫힙니다. Nav2 가
// 실패해도 미션 매니저가 3초 뒤 같은 목적지로 재시도하므로, 로봇은 달리는데
// 팝업만 남는 일이 있었습니다. 실패 사실은 알림 목록에 남습니다.
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
  /// 지도에서 지정만 한 자리로 처음 도킹하다 도크를 못 찾았을 때([GoalEvent.showsDockRedo])만
  /// 버튼이 나옵니다. 탭은 셸이 쥐고 있어 셸이 넘깁니다.
  final VoidCallback? onRedoDock;

  @override
  State<GoalAlertDialog> createState() => _GoalAlertDialogState();
}

class _GoalAlertDialogState extends State<GoalAlertDialog> {
  /// 닫기를 한 번만 부르기 위한 표시. 닫히는 프레임 사이에 build 가 또 돌면
  /// pop 이 두 번 나가 뒤 화면까지 닫힙니다.
  bool _closing = false;

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final supervisor = context.watch<SupervisorProvider>();

    // build 안에서 바로 닫으면 프레임을 그리는 도중에 화면을 바꾸는 것이라
    // 예외가 납니다. 한 프레임 뒤로 미룹니다.
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
      // 목업 92: 지정한 자리·방향이 틀렸을 수 있다는 안내와 두 가지 방법, 그 아래 버튼 둘.
      // 버튼은 글자가 두 줄로 접혀도 높이가 같게 여기서 직접 놓습니다(actions 는 가운데 맞춤).
      content: redoDock
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _DockRedoBox(),
                const SizedBox(height: 20),
                DockChoiceRow(
                  left: PressScale(child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('확인'),
                  )),
                  right: PressScale(child: FilledButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onRedoDock?.call();
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
      // 목적지 이름은 본문에 섞지 않습니다. 이름이 길면 본문 줄이 흔들리고
      // '(으)로' 조사도 맞출 수 없습니다. 사유는 로봇이 적어 보낸 원문이고, 빈
      // 칸은 그리지 않습니다. 어떤 칸을 보일지는 GoalEvent.detailRows 가 정합니다.
      rows: [
        for (final (label, value) in event.detailRows)
          VicaDialogRow(label: label, value: value),
      ],
      actions: [
        if (!redoDock)
          PressScale(child: FilledButton(
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
              style: const TextStyle(color: VicaColors.muted, fontSize: 13, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }
}
