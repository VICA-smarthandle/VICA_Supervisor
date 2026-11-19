// 결함 짧은 문장(2026-11-17 사용자 '가' 안: '~하니 확인해주세요').
import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/core/fault_messages.dart';

void main() {
  String msg(String code, {String detail = '원문', String label = '부품'}) =>
      faultShortMessage(code: code, detail: detail, componentLabel: label);

  test('표에 있는 코드는 짧은 한 문장', () {
    expect(msg('LIDAR_SCAN_STALE'), 'LiDAR 신호가 끊겼으니 USB 연결을 확인해주세요.');
    expect(msg('CAMERA_DEPTH_STALE'), 'depth 카메라가 끊겼으니 D455 연결을 확인해주세요.');
    expect(msg('CAMERA_COLOR_STALE'), 'RGB 카메라가 끊겼으니 D455 연결을 확인해주세요.');
  });

  test('비상정지는 로봇이 보낸 원인을 끼워 넣는다', () {
    expect(
        msg('SAFETY_ESTOP_LATCHED',
            detail: '비상정지가 걸려 있습니다. 원인: physical_button'),
        '비상정지가 걸렸으니 원인(physical_button)을 확인해주세요.');
    expect(msg('SAFETY_ESTOP_LATCHED', detail: '비상정지가 걸려 있습니다.'),
        '비상정지가 걸렸으니 원인을 확인해주세요.');
  });

  test('진단 끊김은 부품 이름을 넣고, 모르는 코드는 로봇 원문 그대로', () {
    expect(
        msg('DIAG_COMPONENT_STALE', label: 'LiDAR'), 'LiDAR 신호가 끊겼으니 확인해주세요.');
    expect(msg('DIAG_COMPONENT_ERROR', detail: '장치가 보낸 문장'), '장치가 보낸 문장');
    expect(msg('NEW_UNKNOWN_CODE', detail: '새 결함 원문'), '새 결함 원문');
  });

  test('모든 문장은 "~하니/~으니 … 해주세요." 한 문장', () {
    for (final entry in kFaultMessages.entries) {
      expect(entry.value.endsWith('주세요.'), isTrue, reason: entry.key);
      expect('.'.allMatches(entry.value).length, 1, reason: entry.key);
    }
  });
}
