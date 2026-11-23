import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/models/mic_check.dart';

const _values = {
  'listen_min_rms': 0.012,
  'short_answer_min_rms': 0.02,
  'wake_threshold': 0.7,
  'emergency_single': 0.5,
  'agc': 0.007,
  'echo': 'mid',
  'agc_max_gain': null,
  'approach_min_rms': null,
  'band_min': 0.002,
};

String _status() => jsonEncode({
      'type': 'status',
      'place': '복도',
      'step': {
        'key': 'call',
        'no': 3,
        'of': 9,
        'name': '호출',
        'say': '비카야',
        'rep': 2,
        'reps': 4,
        'seconds': 5,
        'recording': true,
        'robot': false,
      },
      'steps': [
        {'key': 'quiet', 'name': '조용', 'need': 1},
        {'key': 'call', 'name': '호출', 'need': 4},
      ],
      'progress': {
        'quiet': ['pass'],
        'call': ['pass', 'fail'],
      },
      'values': _values,
      'env_values': _values,
      'ranges': {
        'listen_min_rms': [0.005, 0.040, 0.0005],
        'band_min': [1, 8, 1],
      },
      'names': {'listen_min_rms': '수음 최소'},
      'agc_choices': [0.005, 0.007, 0.01],
      'echo_choices': {'strong': '센 (1.5·켜짐)', 'mid': '중간 (1.0·켜짐)'},
      'gain_choices': [2.0, 4, 31.6],
      'gain_factory': 31.6,
      'short_over_listen': 1.0,
      'env_keys': {'listen_min_rms': 'VICA_LISTEN_MIN_RMS'},
      'chip_ok': false,
      'chip_problems': ['AGC 쓰기 실패'],
      'noise_at_check': 0.004,
    });

void main() {
  test('status: 단계·범위·값·칩 상태를 읽는다', () {
    final m = MicCheckMessage.parse(_status());
    expect(m, isA<MicStatusMessage>());
    final s = (m as MicStatusMessage).status;
    expect(s.place, '복도');
    expect(s.step.no, 3);
    expect(s.step.of, 9);
    expect(s.step.say, '비카야');
    expect(s.step.rep, 2);
    expect(s.step.reps, 4);
    expect(s.step.seconds, 5.0);
    expect(s.step.recording, isTrue);
    expect(s.step.robot, isFalse);
    expect(s.steps.length, 2);
    expect(s.steps[1].key, 'call');
    expect(s.steps[1].need, 4);
    expect(s.progress['call'], ['pass', 'fail']);
    expect(s.ranges['listen_min_rms']!.max, 0.040);
    expect(s.ranges['listen_min_rms']!.step, 0.0005);
    expect(s.ranges['band_min']!.min, 1.0);
    expect(s.values['echo'], 'mid');
    expect(s.values['agc_max_gain'], isNull);
    expect(s.envValues['band_min'], 0.002);
    expect(s.names['listen_min_rms'], '수음 최소');
    expect(s.envKeys['listen_min_rms'], 'VICA_LISTEN_MIN_RMS');
    expect(s.agcChoices, [0.005, 0.007, 0.01]);
    expect(s.gainChoices, [2.0, 4.0, 31.6]);
    expect(s.echoChoices['mid'], '중간 (1.0·켜짐)');
    expect(s.gainFactory, 31.6);
    expect(s.chipOk, isFalse);
    expect(s.chipProblems, ['AGC 쓰기 실패']);
    expect(s.noiseAtCheck, 0.004);
    expect(s.shortOverListen, 1.0);
  });

  test('status: 빠진 칸은 기본값', () {
    final s =
        (MicCheckMessage.parse('{"type":"status"}') as MicStatusMessage).status;
    expect(s.step.no, 0);
    expect(s.steps, isEmpty);
    expect(s.ranges, isEmpty);
    expect(s.chipOk, isTrue);
    expect(s.chipProblems, isEmpty);
    expect(s.noiseAtCheck, isNull);
    expect(s.shortOverListen, 1.0);
  });

  test('status: noise_at_check·short_over_listen 정수·null', () {
    final s = (MicCheckMessage.parse(
                '{"type":"status","noise_at_check":null,"short_over_listen":2}')
            as MicStatusMessage)
        .status;
    expect(s.noiseAtCheck, isNull);
    expect(s.shortOverListen, 2.0);
    final t = (MicCheckMessage.parse('{"type":"status","noise_at_check":1}')
            as MicStatusMessage)
        .status;
    expect(t.noiseAtCheck, 1.0);
  });

  test('frame: null 칸과 숫자 형식', () {
    final f = (MicCheckMessage.parse(jsonEncode({
      'type': 'frame',
      'rms': 0,
      'wake': 0.5,
      'stop': 1,
      'vad': null,
      'robot': false,
      'muted': false,
      'state': 'IDLE',
      'noise': null,
      'rec_left': null,
      'busy': '',
    })) as MicFrameMessage)
        .frame;
    expect(f.rms, 0.0);
    expect(f.stop, 1.0);
    expect(f.vad, isNull);
    expect(f.noise, isNull);
    expect(f.recLeft, isNull);
    expect(f.state, 'IDLE');
    final g = (MicCheckMessage.parse(jsonEncode({
      'type': 'frame',
      'rms': 0.02,
      'wake': 0.1,
      'stop': 0.2,
      'vad': true,
      'robot': true,
      'muted': true,
      'state': 'LISTEN',
      'noise': 0.004,
      'rec_left': 3.5,
      'busy': '채점 중',
    })) as MicFrameMessage)
        .frame;
    expect(g.vad, isTrue);
    expect(g.muted, isTrue);
    expect(g.recLeft, 3.5);
    expect(g.busy, '채점 중');
  });

  test('event·toast·busy·prep', () {
    final e = (MicCheckMessage.parse(jsonEncode({
      'type': 'event',
      'grade': 'pass',
      'title': '호출 확정',
      'detail': '점수 0.81',
      'time': '12:00:01',
    })) as MicEventMessage)
        .event;
    expect(e.grade, 'pass');
    expect(e.title, '호출 확정');
    expect(e.detail, '점수 0.81');
    expect(e.time, '12:00:01');
    expect(
        (MicCheckMessage.parse('{"type":"toast","text":"안녕"}') as MicToast)
            .text,
        '안녕');
    expect(
        (MicCheckMessage.parse('{"type":"busy","text":"채점 중"}') as MicBusy)
            .text,
        '채점 중');
    expect(
        (MicCheckMessage.parse('{"type":"prep","text":"준비"}') as MicPrep).text,
        '준비');
  });

  test('results: first 가 null 이거나 줄 목록', () {
    final row = {
      'key': 'call',
      'name': '호출',
      'grade': 'warn',
      'detail': '3/4',
      'todo': '문턱↓'
    };
    final r = (MicCheckMessage.parse(jsonEncode({
      'type': 'results',
      'title': '사용 가능',
      'overall': 'pass',
      'rows': [row],
      'first': null,
      'stale': true,
    })) as MicResultsMessage)
        .results;
    expect(r.title, '사용 가능');
    expect(r.overall, 'pass');
    expect(r.rows.single.todo, '문턱↓');
    expect(r.first, isNull);
    expect(r.stale, isTrue);
    final r2 = (MicCheckMessage.parse(jsonEncode({
      'type': 'results',
      'title': 't',
      'overall': 'fail',
      'rows': [row],
      'first': [row, row],
      'stale': false,
    })) as MicResultsMessage)
        .results;
    expect(r2.first!.length, 2);
    final r3 = (MicCheckMessage.parse(jsonEncode({
      'type': 'results',
      'title': 't',
      'overall': 'fail',
      'rows': [
        {'key': 'a', 'name': 'b', 'grade': 'pass', 'detail': 'd'}
      ],
    })) as MicResultsMessage)
        .results;
    expect(r3.rows.single.todo, '');
  });

  test('save_preview', () {
    final p = (MicCheckMessage.parse(jsonEncode({
      'type': 'save_preview',
      'lines': ['a → b', 'c → d'],
      'backup_dir': '/x/backup',
    })) as MicSavePreviewMessage)
        .preview;
    expect(p.lines, ['a → b', 'c → d']);
    expect(p.backupDir, '/x/backup');
  });

  test('모르는 type·깨진 JSON·type 없음·객체 아님은 null', () {
    expect(MicCheckMessage.parse('{"type":"nope"}'), isNull);
    expect(MicCheckMessage.parse('{not json'), isNull);
    expect(MicCheckMessage.parse('{"text":"x"}'), isNull);
    expect(MicCheckMessage.parse('[1,2]'), isNull);
  });
}
