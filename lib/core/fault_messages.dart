// 결함 코드별 짧은 안내 문장(2026-11-17 사용자: 핵심만 '~하니 확인해주세요' 한 문장).
//
// 로봇(vica_system_monitor fault_catalog.py)이 보내는 detail 은 '…가 N초 동안 수신되지
// 않았습니다' 처럼 길고, 할 일은 따로 온다. 화면에는 둘을 줄인 한 문장을 쓴다. 몇 초째인지는
// 진단 카드 머리 줄('N째')에 따로 나온다. 로봇 쪽 문장·로그는 그대로 둔다.
//
// 표에 없는 코드(새 결함, 장치가 직접 보내는 DIAG_COMPONENT_ERROR·WARN)는 로봇 문장을 그대로 쓴다.

const kFaultMessages = <String, String>{
  // 모터
  'MOTOR_CAN_TIMEOUT': '모터 응답이 없으니 CAN 연결을 확인해주세요.',
  'MOTOR_CAN_FAILED': 'CAN 통신이 끊겼으니 케이블을 확인해주세요.',
  'MOTOR_NODE_SILENT': '모터 노드가 멈췄으니 실행 상태를 확인해주세요.',
  // 안전 제어 (SAFETY_ESTOP_LATCHED 는 원인을 끼워 넣어야 해서 아래 함수가 만든다)
  'SAFETY_STATE_STALE': '안전 제어 신호가 끊겼으니 safety 노드를 확인해주세요.',
  'SAFETY_SUPERVISOR_FAULT': '비상정지 신호가 늦으니 비상정지를 걸었다 풀어주세요.',
  'SAFETY_RESET_REQUIRED': '정지 원인이 풀렸으니 안전 초기화를 해주세요.',
  // 위치 추정
  'LOCALIZATION_ODOM_STALE': '위치 정보가 멈췄으니 EKF·엔코더를 확인해주세요.',
  'LOCALIZATION_WHEEL_ODOM_STALE': '바퀴 회전 정보가 끊겼으니 엔코더 연결을 확인해주세요.',
  'LOCALIZATION_TF_STALE': '지도 위 위치가 멈췄으니 Nav2를 확인해주세요.',
  // 자율 주행
  'NAV2_NOT_ACTIVE': '자율 주행이 꺼져 있으니 Nav2를 다시 켜주세요.',
  'NAV2_CMD_PATH_DOWN': '주행 명령이 막혔으니 Nav2를 다시 켜주세요.',
  // LiDAR
  'LIDAR_SCAN_STALE': 'LiDAR 신호가 끊겼으니 USB 연결을 확인해주세요.',
  // 카메라 인식
  'DEPTH_SCAN_STALE': '카메라 장애물 감지가 멈췄으니 카메라를 확인해주세요.',
  'CAMERA_DEPTH_STALE': 'depth 카메라가 끊겼으니 D455 연결을 확인해주세요.',
  'CAMERA_COLOR_STALE': 'RGB 카메라가 끊겼으니 D455 연결을 확인해주세요.',
  // 핸들 및 초음파
  'GUIDANCE_HANDLE_DISCONNECTED': '핸들 연결이 끊겼으니 USB를 확인해주세요.',
  'GUIDANCE_UPLINK_STALE': '핸들 신호가 끊겼으니 핸들 USB·전원을 확인해주세요.',
  'GUIDANCE_NODE_SILENT': '핸들 드라이버가 멈췄으니 실행 상태를 확인해주세요.',
  // 음성 LLM
  'VOICE_NODE_SILENT': '음성이 꺼져 있으니 음성 실행 상태를 확인해주세요.',
  // 앱 연결
  'APP_BRIDGE_SILENT': '앱 연결이 멈췄으니 앱 브리지를 확인해주세요.',
  // 공통
  'MONITOR_DIAG_INPUT_STALE': '진단 신호가 끊겼으니 monitor 칸을 확인해주세요.',
};

/// 화면에 쓸 결함 한 문장. [detail] 은 로봇이 보낸 원문, [componentLabel] 은 부품 이름.
String faultShortMessage({
  required String code,
  required String detail,
  required String componentLabel,
}) {
  switch (code) {
    case 'SAFETY_ESTOP_LATCHED':
      // 로봇 원문: '비상정지가 걸려 있습니다. 원인: {reason}'
      final at = detail.indexOf('원인:');
      final reason = at < 0 ? '' : detail.substring(at + 3).trim();
      return reason.isEmpty
          ? '비상정지가 걸렸으니 원인을 확인해주세요.'
          : '비상정지가 걸렸으니 원인($reason)을 확인해주세요.';
    case 'DIAG_COMPONENT_STALE':
      return '$componentLabel 신호가 끊겼으니 확인해주세요.';
  }
  return kFaultMessages[code] ?? detail;
}
