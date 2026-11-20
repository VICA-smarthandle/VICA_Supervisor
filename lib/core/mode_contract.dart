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

/// 로봇 끄기(사용자 11-18): 주행 묶음 → 기본 묶음 → sync → 시스템 종료. 움직이는 중·지도 그리기 중이면
/// 거부. 받아들이면 바로 답하고 곧 연결이 끊긴다(모드 노드·rosbridge 도 내려간다).
const String kShutdownService = '/vica/mode/shutdown';

/// 주행 켜기 거절 중 '칸(터미널)에서 띄운 주행 노드가 있다'의 앞부분(mode_logic.drive_start_refusal).
/// 모드 노드는 프로세스로 확인한다. 앱은 이 거절이면 예전처럼 화면만 바꾼다(2026-11-18).
const String kPaneDriveRefusal = '칸에서 띄운 주행 노드가 있습니다';

/// Nav2 만 다시 띄우기(기동 실패 뒤 사람이 누름).
const String kNav2RestartService = '/vica/mode/nav2_restart';

/// ⑮ 감지기만 켜고 끄기(잠시 끄기 — 주행을 다시 켜면 켜진다). 주행 중에만 통한다.
const String kDetectorOnService = '/vica/mode/detector_on';
const String kDetectorOffService = '/vica/mode/detector_off';

/// 음성 노드(호출어·'멈춰' 감지를 하는 음성 유닛)만 켜고 끄기. 움직이는 중에는 거절된다.
/// 2026-11-20 사용자(캔버스 104): 마이크 점검 때 사람이 직접 끄고 켠다.
const String kVoiceNodeOnService = '/vica/mode/voice_on';
const String kVoiceNodeOffService = '/vica/mode/voice_off';

/// 마이크 점검기(음성 저장소 `mic_check_session`, 유닛 `vica-miccheck`) 켜기·끝내기. 준비에 1~2분.
/// 점검기는 `ws://<로봇>:8770/ws` 로 앱과 말한다. 움직이는 중에는 거절된다.
const String kMicCheckStartService = '/vica/mode/mic_check_start';
const String kMicCheckStopService = '/vica/mode/mic_check_stop';
const int kMicCheckPort = 8770;

/// 음성: 로컬(⑬, 로봇 안 midm2-mini) / 외부 API(⑫, 클라우드 LLM). 고른 값은 젯슨 파일에 남고,
/// 음성이 떠 있으면 다시 띄운다(말이 끊김). 움직이는 중에는 거절된다.
const String kVoiceLocalService = '/vica/mode/voice_offline';
const String kVoiceApiService = '/vica/mode/voice_online';

/// 주행 지도 바꾸기(사용자 11-17). std_msgs/String JSON {request_id, map_id}. Trigger 는 인자가 없어
/// 토픽으로 보내고 결과는 모드 상태의 map_change(같은 request_id)로 받는다. 젯슨은 maps/CURRENT_MAP 을
/// 쓰고, 주행이 떠 있으면 Nav2·미션·음성·위치 확인을 다시 띄운다(약 1분).
const String kModeMapRequestTopic = '/vica/mode/map_request';

/// 지도 바꾸기 요청에 모드 노드가 답하기를 기다리는 시간. 노드는 받자마자 상태를 다시 낸다.
const Duration kModeMapRequestTimeout = Duration(seconds: 8);

/// 답이 없으면 같은 request_id 로 다시 보내는 간격(첫 발행이 DDS 연결 전에 사라질 수 있다, 11-17 실기).
const Duration kModeMapRequestRetry = Duration(milliseconds: 1500);

/// 모드 상태가 이보다 오래 안 오면 모드 노드가 없다고 본다. 노드는 2 s 마다 낸다.
const Duration kModeStatusStale = Duration(seconds: 8);
