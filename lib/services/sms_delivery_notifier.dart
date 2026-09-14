// 이 파일은 관리자 안드로이드 폰의 유심으로 도착 문자를 직접 보냅니다(B안).
//
// 어떻게 동작하는가. 앱이 안드로이드의 문자 발송 창구(SmsManager)를 직접 부릅니다.
// 문자앱을 여는 것이 아니라서 화면에 아무것도 뜨지 않고 조용히 나가며, 인터넷이
// 아니라 통신사 문자망으로 갑니다. 그래서 젯슨 인터넷 여부와 무관하고 발신번호
// 사전등록 같은 절차도 없습니다 — 관리자 개인 번호에서 나가는 평범한 문자입니다.
//
// 알고 있어야 할 성질
//   - 받는 사람에게 관리자 폰 번호가 찍힙니다(답장·전화 가능).
//   - 기본 문자앱이 아니라서 폰의 문자함에는 기록이 남지 않습니다. 앱 로그가
//     유일한 발송 기록입니다.
//   - 유심이 없거나(와이파이 태블릿) 권한을 거부하면 못 보냅니다. 그때는
//     "안 갔다"를 크게 알립니다 — 안 간 문자를 갔다고 믿는 것이 최악입니다.
//   - 한글 45자를 넘으면 조각나므로 본문은 deliveryArrivalMessage 가 길이를 잽니다.
//     여기서는 혹시 넘겼을 때를 대비해 isMultipart 를 켭니다(안 켜면 잘립니다).
import 'dart:async';

import 'package:another_telephony/telephony.dart';

import 'delivery_notifier.dart';

class SmsDeliveryNotifier implements DeliveryNotifier {
  SmsDeliveryNotifier({Telephony? telephony})
      : _telephony = telephony ?? Telephony.instance;

  final Telephony _telephony;

  /// 통신사가 "보냈다"고 답할 때까지 기다리는 시간. 그 뒤로는 결과를 모르는
  /// 것으로 치고 "확인 불가"를 돌려줍니다. 무한정 기다리면 화면이 영영 안 뜹니다.
  static const _sentAckTimeout = Duration(seconds: 15);

  @override
  String get modeLabel => 'SMS';

  @override
  Future<DeliveryNotifyResult> send({
    required String phone,
    required String text,
  }) async {
    // 유심이 없는 기기는 여기서 걸립니다. 보내 보고 실패하는 것보다 먼저 아는
    // 편이 낫습니다.
    final capable = await _telephony.isSmsCapable;
    if (capable == false) {
      return const DeliveryNotifyResult(
        sent: false,
        detail: '이 기기는 문자를 보낼 수 없습니다(유심 없음). 직접 연락하세요.',
      );
    }

    // 안드로이드 6 이상은 문자가 '위험 권한'이라 사용자가 팝업에서 허용해야 합니다.
    // 이미 허용했으면 팝업 없이 바로 true 입니다.
    final granted = await _telephony.requestSmsPermissions;
    if (granted != true) {
      return const DeliveryNotifyResult(
        sent: false,
        detail: '문자 권한이 없습니다. 앱 설정에서 SMS 권한을 허용하세요. 직접 연락하세요.',
      );
    }

    // 통신사가 "보냈다(SENT)"고 알려 줄 때만 성공으로 칩니다. sendSms 가 예외 없이
    // 끝난 것은 "OS 에 넘겼다"일 뿐 나간 것이 아닙니다.
    final sentAck = Completer<void>();
    try {
      await _telephony.sendSms(
        to: phone,
        message: text,
        isMultipart: true,
        statusListener: (SendStatus status) {
          if (status == SendStatus.SENT && !sentAck.isCompleted) {
            sentAck.complete();
          }
        },
      );
    } catch (error) {
      return DeliveryNotifyResult(
        sent: false,
        detail: '문자 발송 요청이 실패했습니다: $error. 직접 연락하세요.',
      );
    }

    try {
      await sentAck.future.timeout(_sentAckTimeout);
    } on TimeoutException {
      return const DeliveryNotifyResult(
        sent: false,
        detail: '통신사가 발송을 확인해 주지 않았습니다(전파 없음?). 직접 연락해 확인하세요.',
      );
    }
    return const DeliveryNotifyResult(
      sent: true,
      detail: '관리자 폰에서 문자를 보냈습니다. 폰 문자함에는 남지 않고 앱 로그에만 남습니다.',
    );
  }
}
