// 이 파일은 젯슨의 모드 노드(scripts/autostart/vica_mode_node.py, 루트 feat/autostart)와
// 주고받는 이름입니다. 앱 설정으로 바꿀 값이 아니라 노드와 맞춘 계약이라 상수로 둡니다.
//
// 모드 노드는 부팅 때 자동으로 뜨는 기본 묶음에 들어 있습니다. 칸(Terminator)으로만
// 띄우는 지금 방식에서는 없을 수 있습니다 — 그때 앱은 예전처럼 화면만 바꿉니다.

/// 모드 상태(std_msgs/String JSON, 2 s 마다, TRANSIENT_LOCAL).
const String kModeStatusTopic = '/vica/mode_status';

/// 주행 묶음(Nav2·미션·손잡이·감시·위치 확인) 켜기. std_srvs/Trigger.
const String kDriveStartService = '/vica/mode/drive_start';

/// 주행 묶음 끄기. 움직이는 중이면 거부, Nav2 가 뜨는 중이면 다 뜬 뒤(늦어도 45 s) 끈다.
const String kDriveStopService = '/vica/mode/drive_stop';

/// Nav2 만 다시 띄우기(기동 실패 뒤 사람이 누름).
const String kNav2RestartService = '/vica/mode/nav2_restart';

/// ⑮ 감지기만 켜고 끄기(잠시 끄기 — 주행을 다시 켜면 켜진다). 주행 중에만 통한다.
const String kDetectorOnService = '/vica/mode/detector_on';
const String kDetectorOffService = '/vica/mode/detector_off';

/// 음성: 로컬(⑬, 로봇 안 midm2-mini) / 외부 API(⑫, 클라우드 LLM). 고른 값은 젯슨 파일에 남고,
/// 음성이 떠 있으면 다시 띄운다(말이 끊김). 움직이는 중에는 거절된다.
const String kVoiceLocalService = '/vica/mode/voice_offline';
const String kVoiceApiService = '/vica/mode/voice_online';

/// 모드 상태가 이보다 오래 안 오면 모드 노드가 없다고 본다. 노드는 2 s 마다 낸다.
const Duration kModeStatusStale = Duration(seconds: 8);
