// 모드 노드가 내는 JSON(scripts/autostart/mode_logic.py 의 derive_status)을 고정합니다.
import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/models/mode_status.dart';

void main() {
  test('모드 노드의 상태 JSON 을 읽는다', () {
    final status = ModeStatus.fromJson({
      'mode': 'drive',
      'state': 'need_initial_pose',
      'detail': '초기 위치를 잡아 주세요',
      'nav2': 'waiting_pose',
      'safety': 'READY_TO_GO',
      'reset_needed': false,
      'failed_units': <Object?>[],
      'missing_nodes': <Object?>[],
      'duplicated': <Object?>[],
      'can_up': true,
      'stop_timeouts': ['nav2'],
      'timestamp': 1794815270.5,
    });

    expect(status.driveOn, isTrue);
    expect(status.state, ModeState.needInitialPose);
    expect(status.nav2, 'waiting_pose');
    expect(status.stopTimeouts, ['nav2']);
    expect(status.stopPending, isFalse);
  });

  test('끄기 예약은 stopping 과 남은 초가 함께 있을 때다', () {
    final pending = ModeStatus.fromJson({'mode': 'drive', 'state': 'stopping', 'stop_in_sec': 31});
    final going = ModeStatus.fromJson({'mode': 'drive', 'state': 'stopping'});

    expect(pending.stopPending, isTrue);
    expect(pending.stopInSec, 31);
    expect(going.stopPending, isFalse);
  });

  test('모르는 값과 빠진 항목은 안전한 쪽으로 읽는다', () {
    final status = ModeStatus.fromJson({'state': 'weird'});

    expect(status.mode, 'unknown');
    expect(status.driveOn, isFalse);
    expect(status.state, ModeState.unknown);
    expect(status.stopTimeouts, isEmpty);
  });

  test('유닛 키를 사람이 읽는 이름으로 바꾼다', () {
    expect(modeUnitLabel('posecheck'), '위치 확인');
    expect(modeUnitLabel('nav2'), 'Nav2');
    expect(modeUnitLabel('새것'), '새것');
  });

  test('감지기·음성 상태와 고른 음성을 읽는다', () {
    final status = ModeStatus.fromJson({
      'mode': 'drive',
      'state': 'running',
      'nav2': 'active',
      'detector': 'inactive',
      'voice': 'active',
      'voice_mode': 'online',
    });

    expect(status.detector, 'inactive');
    expect(status.detectorOn, isFalse);
    expect(status.voice, 'active');
    expect(status.voiceChoice, VoiceChoice.api);
    expect(status.nav2Up, isTrue);
  });

  test('음성 노드는 active·activating 일 때 켜진 것으로 본다(캔버스 104)', () {
    bool on(String v) => ModeStatus(mode: 'drive', state: ModeState.running, voice: v).voiceOn;
    expect(on('active'), isTrue);
    expect(on('activating'), isTrue);
    expect(on('inactive'), isFalse);
    expect(on('failed'), isFalse);
    expect(on('none'), isFalse);
  });

  test('음성을 모르면 로컬로 본다(젯슨도 그렇게 띄운다)', () {
    expect(VoiceChoice.fromWire(null), VoiceChoice.local);
    expect(VoiceChoice.fromWire('offline'), VoiceChoice.local);
    expect(VoiceChoice.fromWire('online'), VoiceChoice.api);
    expect(VoiceChoice.local.label, '로컬(LOCAL)');
    expect(VoiceChoice.api.label, '외부 API');
  });

  test('음성 연결 알림을 읽고 종류를 가른다', () {
    final status = ModeStatus.fromJson({
      'mode': 'drive',
      'state': 'running',
      'voice_events_epoch': 1794825000.5,
      'voice_events': [
        {'id': 1, 'at': 1794825010.0, 'kind': 'external_ok', 'text': '외부 API 연결 성공'},
        {'id': 2, 'at': 1794825020.0, 'kind': 'external_fallback', 'text': '외부 API 연결 실패 → 로컬 API 로 전환'},
        {'id': 3, 'at': 1794825030.0, 'kind': 'local_fail', 'text': '로컬 API 연결 실패'},
        {'id': 'x'},
      ],
    });

    expect(status.voiceEventsEpoch, 1794825000.5);
    expect(status.voiceEvents.map((e) => e.id), [1, 2, 3], reason: '깨진 항목은 버린다');
    expect(status.voiceEvents[0].isSuccess, isTrue);
    expect(status.voiceEvents[1].isFallback, isTrue);
    expect(status.voiceEvents[2].isSuccess || status.voiceEvents[2].isFallback, isFalse);
  });

  test('주행 지도 칸(11-17): 현재 지도·유닛이 읽은 지도·막힘 이유·요청 결과', () {
    final status = ModeStatus.fromJson({
      'mode': 'drive',
      'state': 'running',
      'current_map_id': 'map_b',
      'running_maps': {'nav2': 'map_a', 'mission': 'map_a'},
      'map_mismatch': true,
      'map_change_block': '안내 중엔 불가',
      'dialog_state': 'patrol_paused',
      'map_change': {
        'request_id': 'r1', 'map_id': 'map_b', 'from': 'map_a', 'state': 'applied',
        'message': 'Nav2·미션·음성 재시작 · 약 1분', 'restarted': ['nav2', 'mission', 'llm', 'posecheck'],
        'at': 1794878000.5,
      },
    });
    expect(status.currentMapId, 'map_b');
    expect(status.driveMapId, 'map_a');
    expect(status.mapMismatch, isTrue);
    expect(status.mapChangeBlock, '안내 중엔 불가');
    expect(status.paused, isTrue);
    expect(status.mapChange!.applied, isTrue);
    expect(status.mapChange!.restarted, hasLength(4));
    expect(status.mapChange!.requestId, 'r1');
  });

  test('옛 모드 노드(지도 칸 없음)는 비어 있고 Nav2 지도는 현재 지도로 본다', () {
    final status = ModeStatus.fromJson({'mode': 'idle', 'state': 'idle'});
    expect(status.currentMapId, '');
    expect(status.runningMaps, isEmpty);
    expect(status.mapMismatch, isFalse);
    expect(status.mapChange, isNull);
    expect(status.paused, isFalse);
  });

  // 2026-11-18 B안: 유닛 밖(칸·터미널)에서 뜬 주행 노드. 칸이 없으면(옛 모드 노드) null — 앱은 노드 목록으로 판단.
  test('pane_nodes 를 읽고, 그중 Nav2 이름이 있으면 칸 Nav2 로 본다', () {
    final none = ModeStatus.fromJson({'mode': 'idle', 'state': 'idle', 'pane_nodes': []});
    expect(none.paneNodes, isEmpty);
    expect(none.paneNav2, isFalse);
    final nav2 = ModeStatus.fromJson({'mode': 'idle', 'state': 'idle', 'pane_nodes': ['controller_serv']});
    expect(nav2.paneNav2, isTrue);
    final mission = ModeStatus.fromJson({'mode': 'idle', 'state': 'idle', 'pane_nodes': ['mission_manager']});
    expect(mission.paneNav2, isFalse);
    expect(ModeStatus.fromJson({'mode': 'idle', 'state': 'idle'}).paneNodes, isNull);
  });

  test('mic_check 칸: 없으면 none, active·activating·deactivating 이 점검 중', () {
    final none = ModeStatus.fromJson({'mode': 'idle', 'state': 'idle'});
    expect(none.micCheck, 'none');
    expect(none.micCheckActive, isFalse);
    final going = ModeStatus.fromJson({
      'mode': 'idle',
      'state': 'idle',
      'mic_check': {'state': 'deactivating', 'port': 8770},
    });
    expect(going.micCheck, 'deactivating');
    expect(going.micCheckActive, isTrue);
    final off = ModeStatus.fromJson({
      'mode': 'idle',
      'state': 'idle',
      'mic_check': {'state': 'inactive', 'port': 8770},
    });
    expect(off.micCheckActive, isFalse);
  });
}
