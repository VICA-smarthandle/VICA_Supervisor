// 비상정지 원인 이름(2026-11-17 알림 및 로그 '비상정지' 분류).
import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/core/estop_sources.dart';

void main() {
  test('사람이 건 것과 넘어짐', () {
    expect(estopSourceLabel('physical_f1'), '물리 버튼');
    expect(estopSourceLabel('voice'), '음성');
    expect(estopSourceLabel('app'), '관리자 앱');
    expect(estopSourceLabel('tipped'), '넘어짐');
  });

  test('통신 끊김', () {
    expect(estopSourceLabel('motor_can'), '모터 통신 끊김');
    expect(estopSourceLabel('motor_can_stale'), '모터 CAN 신호 끊김');
    expect(estopSourceLabel('physical_waiting'), '물리 버튼 신호 기다림');
    expect(estopSourceLabel('imu_stale'), 'IMU 신호 끊김');
  });

  test('모르는 원인은 원문 그대로', () {
    expect(estopSourceLabel('something_new'), 'something_new');
  });
}
