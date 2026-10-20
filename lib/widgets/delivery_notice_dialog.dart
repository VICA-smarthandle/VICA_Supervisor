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
