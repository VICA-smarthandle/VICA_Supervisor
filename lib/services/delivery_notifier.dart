// 이 파일은 "도착 문자를 어떻게 보내는가"를 한 문 뒤에 숨깁니다.
//
// 배송 상태 기계(SupervisorProvider)는 "누구에게 무슨 문구를 언제 보낼지"만 정하고,
// 실제로 보내는 수단은 이 인터페이스의 구현이 맡습니다. 수도꼭지를 먼저 달고
// 수원은 나중에 바꾸는 식입니다 — 지금은 미리보기만 하는 구현 하나이고,
// 관리자 폰의 SMS 발송 구현은 다음 단계에서 같은 자리에 끼웁니다.
//
// 결과에 번호를 넣지 않습니다. 결과 문자열은 그대로 로그에 남기 때문입니다.

/// 발송 시도의 결과.
class DeliveryNotifyResult {
  const DeliveryNotifyResult({required this.sent, required this.detail});

  /// 실제로 문자가 나갔는가. 미리보기는 false 입니다 — "나간 척"하면 관리자가
  /// 안 간 문자를 갔다고 믿습니다.
  final bool sent;

  /// 사람에게 보여줄 설명. 번호는 넣지 않습니다.
  final String detail;
}

abstract class DeliveryNotifier {
  /// 화면 배지용. '미리보기' / 'SMS' 처럼 짧게.
  String get modeLabel;

  /// [phone] 은 숫자만 든 문자열입니다(core/contact_phone.dart 규칙).
  Future<DeliveryNotifyResult> send({
    required String phone,
    required String text,
  });
}

/// 아무것도 보내지 않고 "여기서 보냈을 것"만 알려 주는 구현.
///
/// 2단계(도착 포착까지)의 기본값이자, 문자를 보낼 수 없는 기기(리눅스 데스크탑,
/// 유심 없는 태블릿)에서의 대체입니다.
class PreviewDeliveryNotifier implements DeliveryNotifier {
  const PreviewDeliveryNotifier();

  @override
  String get modeLabel => '미리보기';

  @override
  Future<DeliveryNotifyResult> send({
    required String phone,
    required String text,
  }) async {
    return const DeliveryNotifyResult(
      sent: false,
      detail: '미리보기입니다. 실제 문자는 보내지 않았습니다 — 직접 연락하세요.',
    );
  }
}
