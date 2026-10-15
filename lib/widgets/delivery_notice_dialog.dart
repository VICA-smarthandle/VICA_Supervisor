// 도착 문자 결과 팝업 하나. **안 갔으면 크게 알립니다** — 안 간 문자를 갔다고
// 믿고 자리를 뜨는 것이 배송 기능의 가장 나쁜 실패입니다.
//
// 어디서 띄우는가. 앱 셸(SupervisorShell) 한 곳입니다. 종전에는 물류 배송 화면이
// 띄웠는데, 셸은 지금 보는 화면 하나만 그리므로 대시보드나 지도 설정을 보고 있을
// 때 문자가 오가면 **아무것도 뜨지 않았습니다.** 결과는 담긴 채로 남았다가 물류
// 배송 화면을 열어야 그제서야 떴습니다. 주행 실패 팝업(goal_alert_dialog.dart)을
// 셸로 옮긴 것(2026-09-30)과 같은 이유입니다.
import 'package:flutter/material.dart';

import '../core/contact_phone.dart';
import '../models/delivery_job.dart';
import 'vica_ui.dart';

class DeliveryNoticeDialog extends StatelessWidget {
  const DeliveryNoticeDialog({super.key, required this.notice});

  final DeliveryNotice notice;

  @override
  Widget build(BuildContext context) {
    final sent = notice.result.sent;
    return VicaDialog(
      icon: sent ? Icons.sms_outlined : Icons.sms_failed_outlined,
      iconColor: sent ? VicaColors.green : VicaColors.red,
      title: sent ? '도착 문자를 보냈습니다' : '도착 문자가 가지 않았습니다',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('받는 곳: ${notice.job.destination.name}'),
          Text(
            '받는 번호: ${maskContactPhone(notice.job.destination.contactPhone)}',
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: VicaColors.accentTint,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(notice.text),
          ),
          const SizedBox(height: 10),
          Text(
            notice.result.detail,
            style: TextStyle(
              color: sent ? VicaColors.muted : VicaColors.red,
              fontSize: 13,
            ),
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('확인'),
        ),
      ],
    );
  }
}
