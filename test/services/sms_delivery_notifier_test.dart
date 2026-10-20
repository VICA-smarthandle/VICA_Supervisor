import 'package:another_telephony/telephony.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/services/sms_delivery_notifier.dart';

void main() {
  test('유심이 준비됨일 때만 보낼 수 있다', () {
    expect(simReadyForSms(SimState.READY), isTrue);
    for (final state in SimState.values.where((s) => s != SimState.READY)) {
      expect(simReadyForSms(state), isFalse, reason: '$state');
    }
  });

  test('유심 없음·잠김은 관리자가 알아볼 말로 보인다', () {
    expect(simStateLabel(SimState.ABSENT), '유심 없음');
    expect(simStateLabel(SimState.PIN_REQUIRED), '유심 잠김(PIN)');
    expect(simStateLabel(SimState.UNKNOWN), '유심 상태 모름');
  });
}
