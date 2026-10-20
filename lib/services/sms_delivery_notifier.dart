import 'dart:async';

import 'package:another_telephony/telephony.dart';

import 'delivery_notifier.dart';

class SmsDeliveryNotifier implements DeliveryNotifier {
  SmsDeliveryNotifier({Telephony? telephony})
      : _telephony = telephony ?? Telephony.instance;

  final Telephony _telephony;

  /// 통신사가 "보냈다"고 답할 때까지 기다리는 시간. 그 뒤로는 결과를 모르는
  static const _sentAckTimeout = Duration(seconds: 15);

  @override
  String get modeLabel => 'SMS';

  /// 문자 기능이 있고 유심이 준비됐는가. 권한은 여기서 묻지 않고 보내는 순간 묻습니다
  @override
  Future<bool> canSend() async {
    try {
      if (await _telephony.isSmsCapable == false) {
        return false;
      }
      return simReadyForSms(await _telephony.simState);
    } catch (_) {
      return false;
    }
  }

  /// 문자 기능이 없거나 유심이 아예 빠졌을 때만 맡깁니다. 판정에 실패하면 맡기지 않고
  @override
  Future<bool> needsRelay() async {
    try {
      if (await _telephony.isSmsCapable == false) {
        return true;
      }
      return await _telephony.simState == SimState.ABSENT;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<DeliveryNotifyResult> send({
    required String phone,
    required String text,
  }) async {
    final capable = await _telephony.isSmsCapable;
    if (capable == false) {
      return const DeliveryNotifyResult(
        sent: false,
        detail: '이 기기는 문자를 보낼 수 없습니다(문자 기능 없음). 직접 연락하세요.',
      );
    }

    final sim = await _telephony.simState;
    if (!simReadyForSms(sim)) {
      return DeliveryNotifyResult(
        sent: false,
        detail: '이 폰의 유심이 준비되지 않았습니다(${simStateLabel(sim)}). 직접 연락하세요.',
      );
    }

    final granted = await _telephony.requestSmsPermissions;
    if (granted != true) {
      return const DeliveryNotifyResult(
        sent: false,
        detail: '문자 권한이 없습니다. 앱 설정에서 SMS 권한을 허용하세요. 직접 연락하세요.',
      );
    }

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

/// 유심이 문자를 보낼 수 있는 상태인가. 안드로이드 SIM_STATE_READY 만 보낼 수 있습니다
bool simReadyForSms(SimState state) => state == SimState.READY;

/// 유심 상태를 관리자가 읽을 말로.
String simStateLabel(SimState state) {
  switch (state) {
    case SimState.READY:
      return '준비됨';
    case SimState.ABSENT:
      return '유심 없음';
    case SimState.PIN_REQUIRED:
    case SimState.PUK_REQUIRED:
      return '유심 잠김(PIN)';
    case SimState.NETWORK_LOCKED:
      return '통신사 잠김';
    case SimState.NOT_READY:
      return '유심 준비 중';
    case SimState.PERM_DISABLED:
    case SimState.CARD_IO_ERROR:
    case SimState.CARD_RESTRICTED:
      return '유심 사용 불가';
    default:
      return '유심 상태 모름';
  }
}
