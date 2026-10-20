import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

import 'sms_delivery_notifier.dart';

/// 발송 시도의 결과.
class DeliveryNotifyResult {
  const DeliveryNotifyResult({required this.sent, required this.detail});

  /// 실제로 문자가 나갔는가. 미리보기는 false 입니다 — "나간 척"하면 관리자가
  final bool sent;

  /// 사람에게 보여줄 설명. 번호는 넣지 않습니다.
  final String detail;
}

abstract class DeliveryNotifier {
  /// 화면 배지용. '미리보기' / 'SMS' 처럼 짧게.
  String get modeLabel;

  /// 이 기기가 지금 문자를 보낼 수 있는가(2026-10-10). 관리자 유심 폰이 다른 화면의 배송을
  Future<bool> canSend();

  /// 이 기기에 문자를 보낼 수단이 아예 없어 관리자 유심 폰에 맡겨야 하는가(2026-10-10).
  Future<bool> needsRelay();

  /// [phone] 은 숫자만 든 문자열입니다(core/contact_phone.dart 규칙).
  Future<DeliveryNotifyResult> send({
    required String phone,
    required String text,
  });
}

/// 아무것도 보내지 않고 "여기서 보냈을 것"만 알려 주는 구현.
class PreviewDeliveryNotifier implements DeliveryNotifier {
  const PreviewDeliveryNotifier();

  @override
  String get modeLabel => '미리보기';

  @override
  Future<bool> canSend() async => false;

  @override
  Future<bool> needsRelay() async => true;

  @override
  Future<DeliveryNotifyResult> send({
    required String phone,
    required String text,
  }) async {
    return const DeliveryNotifyResult(
      sent: false,
      detail: '유심이 없습니다. 실제 문자는 보내지 않았습니다 — 직접 연락하세요.',
    );
  }
}

/// 이 기기에 맞는 발송기를 고릅니다.
DeliveryNotifier createDeliveryNotifier() {
  if (!kIsWeb && Platform.isAndroid) {
    return SmsDeliveryNotifier();
  }
  return const PreviewDeliveryNotifier();
}
