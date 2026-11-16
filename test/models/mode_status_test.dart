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

  test('음성을 모르면 로컬로 본다(젯슨도 그렇게 띄운다)', () {
    expect(VoiceChoice.fromWire(null), VoiceChoice.local);
    expect(VoiceChoice.fromWire('offline'), VoiceChoice.local);
    expect(VoiceChoice.fromWire('online'), VoiceChoice.api);
    expect(VoiceChoice.local.label, '로컬(LOCAL)');
    expect(VoiceChoice.api.label, '외부 API');
  });
}
