// 주행 실패·취소 팝업 하나. 다섯 가지 goal 이벤트(주행 실패·거부·취소, 홈 복귀
// 실패·취소)가 모두 이 틀을 씁니다(2026-09-30 사용자 결정).
//
// 틀: 원 아이콘(실패는 빨강, 취소는 파랑) → 제목 → 본문 최대 세 줄 → 아래 칸에
// 목적지·사유 → '확인' 버튼 하나. 본문 각 줄은 폭이 모자라면 띄어쓰기에서만
// 접힙니다(VicaDialog 가 vicaKeepWords 를 거칩니다).
//
// 어디서 띄우는가. 앱 셸(SupervisorShell) 한 곳입니다. 종전에는 원격 주행·물류
// 배송 화면 둘이 각자 띄웠는데, 셸은 지금 보는 화면 하나만 그리므로 대시보드나
// 지도 설정을 보고 있을 때 실패가 오면 **아무것도 뜨지 않았습니다.** 알림은
// 담긴 채로 남았다가 원격 주행 화면을 열어야 그제서야 떴습니다.
import 'package:flutter/material.dart';

import '../models/goal_event.dart';
import 'vica_ui.dart';

class GoalAlertDialog extends StatelessWidget {
  const GoalAlertDialog({super.key, required this.event});

  final GoalEvent event;

  @override
  Widget build(BuildContext context) {
    final failure = event.isFailure;
    final destination = event.destinationLabel;
    return VicaDialog(
      icon: failure ? Icons.error_outline : Icons.info_outline,
      iconColor: failure ? VicaColors.red : VicaColors.primary,
      title: event.title,
      body: event.description,
      rows: [
        // 목적지 이름은 본문에 섞지 않습니다. 이름이 길면 본문 줄이 흔들리고
        // '(으)로' 조사도 맞출 수 없습니다.
        if (destination.isNotEmpty)
          VicaDialogRow(label: '목적지', value: destination),
        // 사유는 로봇이 적어 보낸 원문입니다. 없으면 칸을 그리지 않습니다.
        if (event.reason.isNotEmpty)
          VicaDialogRow(label: '사유', value: event.reason),
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
