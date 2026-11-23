const kFaultMessages = <String, String>{
  'MOTOR_CAN_TIMEOUT': '모터 응답이 없으니 CAN 연결을 확인해주세요.',
  'MOTOR_CAN_FAILED': 'CAN 통신이 끊겼으니 케이블을 확인해주세요.',
  'MOTOR_NODE_SILENT': '모터 노드가 멈췄으니 실행 상태를 확인해주세요.',
  'SAFETY_STATE_STALE': '안전 제어 신호가 끊겼으니 safety 노드를 확인해주세요.',
  'SAFETY_SUPERVISOR_FAULT': '비상정지 신호가 늦으니 비상정지를 걸었다 풀어주세요.',
  'SAFETY_RESET_REQUIRED': '정지 원인이 풀렸으니 안전 초기화를 해주세요.',
  'LOCALIZATION_ODOM_STALE': '위치 정보가 멈췄으니 EKF·엔코더를 확인해주세요.',
  'LOCALIZATION_WHEEL_ODOM_STALE': '바퀴 회전 정보가 끊겼으니 엔코더 연결을 확인해주세요.',
  'LOCALIZATION_TF_STALE': '지도 위 위치가 멈췄으니 Nav2를 확인해주세요.',
  'NAV2_NOT_ACTIVE': '자율 주행이 꺼져 있으니 Nav2를 다시 켜주세요.',
  'NAV2_CMD_PATH_DOWN': '주행 명령이 막혔으니 Nav2를 다시 켜주세요.',
  'LIDAR_SCAN_STALE': 'LiDAR 신호가 끊겼으니 USB 연결을 확인해주세요.',
  'DEPTH_SCAN_STALE': '카메라 장애물 감지가 멈췄으니 카메라를 확인해주세요.',
  'CAMERA_DEPTH_STALE': 'depth 카메라가 끊겼으니 D455 연결을 확인해주세요.',
  'CAMERA_COLOR_STALE': 'RGB 카메라가 끊겼으니 D455 연결을 확인해주세요.',
  'GUIDANCE_HANDLE_DISCONNECTED': '핸들 연결이 끊겼으니 USB를 확인해주세요.',
  'GUIDANCE_UPLINK_STALE': '핸들 신호가 끊겼으니 핸들 USB·전원을 확인해주세요.',
  'GUIDANCE_NODE_SILENT': '핸들 드라이버가 멈췄으니 실행 상태를 확인해주세요.',
  'VOICE_NODE_SILENT': '음성이 꺼져 있으니 음성 실행 상태를 확인해주세요.',
  'APP_BRIDGE_SILENT': '앱 연결이 멈췄으니 앱 브리지를 확인해주세요.',
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
