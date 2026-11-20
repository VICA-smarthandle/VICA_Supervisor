import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/models/mic_check.dart';
import 'package:vica_supervisor/screens/mic_check_screen.dart';
import 'package:vica_supervisor/services/mic_check_controller.dart';

// 가짜 컨트롤러: 보낸 명령을 기록하고 send 결과를 시험이 정합니다. 화면 위젯은 진짜입니다.
class _Fake extends MicCheckController {
  _Fake() : super(uri: Uri.parse('ws://h:8770/ws'));

  final List<(String, Map<String, Object?>)> sent = [];
  bool sendOk = true;

  @override
  bool send(String cmd, [Map<String, Object?> args = const {}]) {
    if (!sendOk) return false;
    sent.add((cmd, args));
    return true;
  }

  void push({
    String? prep,
    MicCheckStatus? status,
    MicCheckFrame? frame,
    bool? connected,
  }) {
    if (prep != null) this.prep = prep;
    if (status != null) this.status = status;
    if (frame != null) this.frame = frame;
    if (connected != null) this.connected = connected;
    notifyListeners();
  }
}

MicCheckStatus _status({
  String key = 'call',
  int no = 3,
  String name = '호출',
  bool robot = false,
  bool chipOk = true,
  double? noiseAtCheck,
}) =>
    MicCheckStatus.fromJson({
      'place': '4층 복도',
      'step': {
        'key': key, 'no': no, 'of': 9, 'name': name,
        'say': '“비카야” — 한 박자 쉬고 — “화장실로 가자”',
        'rep': 2, 'reps': 5, 'seconds': 6.0, 'recording': false, 'robot': robot,
      },
      'steps': [
        {'key': 'quiet', 'name': '조용히', 'need': 1},
        {'key': 'call', 'name': '호출', 'need': 5},
      ],
      'progress': {'quiet': ['pass'], 'call': ['pass', 'warn']},
      'values': {
        'listen_min_rms': 0.012, 'short_answer_min_rms': 0.02,
        'wake_threshold': 0.62, 'emergency_single': 0.55,
      },
      'chip_ok': chipOk,
      if (noiseAtCheck != null) 'noise_at_check': noiseAtCheck,
    });

MicCheckFrame _frame({double? recLeft, double? noise, bool robot = false}) => MicCheckFrame.fromJson({
      'rms': 0.061, 'wake': 0.84, 'stop': 0.08, 'robot': robot, 'muted': false,
      'state': 'listening', 'vad': true,
      if (noise != null) 'noise': noise,
      if (recLeft != null) 'rec_left': recLeft,
    });

Future<_Fake> _pump(WidgetTester tester, {double width = 390, void Function(_Fake)? setup}) async {
  tester.view.physicalSize = Size(width, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  final c = _Fake();
  addTearDown(c.dispose);
  setup?.call(c);
  await tester.pumpWidget(MaterialApp(home: MicCheckScreen(controller: c)));
  return c;
}

void main() {
  testWidgets('prep 만 있으면 준비 중 카드', (tester) async {
    await _pump(tester, setup: (c) => c.prep = '모델 올리는 중');
    expect(find.text('준비 중'), findsOneWidget);
    expect(find.text('모델 올리는 중 · 1~2분'), findsOneWidget);
    expect(find.text('● 칩 확인 중'), findsOneWidget);
    expect(find.text('마이크 점검'), findsOneWidget);
    expect(find.text('끝내기'), findsOneWidget);
  });

  testWidgets('머리 칩과 칩 쓰기 실패 경고', (tester) async {
    final c = await _pump(tester, setup: (c) {
      c.connected = true;
      c.status = _status();
    });
    expect(find.text('4층 복도'), findsOneWidget);
    expect(find.text('● 연결됨'), findsOneWidget);
    expect(find.text('● 칩 정상'), findsOneWidget);
    expect(find.textContaining('칩에 값을 쓰지 못해'), findsNothing);
    c.push(status: _status(chipOk: false));
    await tester.pump();
    expect(find.text('칩에 값을 쓰지 못해 시작하지 않습니다 · 끝내기 뒤 다시 시작하세요'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('mic_check_record'))).onPressed, isNull);
  });

  testWidgets('단계 카드: 녹음 시작·다시 명령', (tester) async {
    final c = await _pump(tester, setup: (c) {
      c.connected = true;
      c.status = _status();
    });
    expect(find.text('3 / 9 · 호출'), findsOneWidget);
    expect(find.text('2/5회'), findsOneWidget);
    expect(find.text('“비카야” — 한 박자 쉬고 — “화장실로 가자”'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mic_check_record')));
    await tester.tap(find.byKey(const ValueKey('mic_check_redo')));
    expect(c.sent[0].$1, 'record');
    expect(c.sent[1].$1, 'redo');
    expect(c.sent[1].$2, {'step': 'call'});
  });

  testWidgets('녹음 중이면 남은 초를 보이고 버튼은 비활성', (tester) async {
    await _pump(tester, setup: (c) {
      c.connected = true;
      c.status = _status();
      c.frame = _frame(recLeft: 4.2);
    });
    expect(find.text('녹음 중 · 4.2초 남음'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('mic_check_record'))).onPressed, isNull);
  });

  testWidgets('6단계 로봇 말하기 → robot 명령, 말하는 중엔 30 s 부터 1 s 씩 셈', (tester) async {
    final c = await _pump(tester, setup: (c) {
      c.connected = true;
      c.status = _status(key: 'robot', no: 6, name: '로봇 혼자 말하기');
    });
    await tester.tap(find.byKey(const ValueKey('mic_check_robot')));
    expect(c.sent.single.$1, 'robot');
    c.push(status: _status(key: 'robot', no: 6, name: '로봇 혼자 말하기', robot: true));
    await tester.pump();
    expect(find.text('로봇 말하는 중 · 30초 남음'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('로봇 말하는 중 · 27초 남음'), findsOneWidget);
    c.push(status: _status(key: 'robot', no: 6, name: '로봇 혼자 말하기'));
    await tester.pump();
    expect(find.textContaining('로봇 말하는 중 ·'), findsNothing);
  });

  testWidgets('9단계는 점검이 끝났습니다', (tester) async {
    await _pump(tester, setup: (c) {
      c.connected = true;
      c.status = _status(key: 'result', no: 9, name: '결과표');
    });
    expect(find.text('점검이 끝났습니다'), findsOneWidget);
  });

  testWidgets('섹션 제목·진행 범례·잡음 줄', (tester) async {
    await _pump(tester, setup: (c) {
      c.connected = true;
      c.status = _status(noiseAtCheck: 0.0028);
      c.frame = _frame(noise: 0.0031);
    });
    for (final t in ['실시간', '최근 10초', '실시간 판정', '진행', '통과', '주의', '실패', '아직']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.text('잡음: 점검 때 0.0028 · 지금 0.0031'), findsOneWidget);
    expect(find.text('2 조용히'), findsOneWidget);
    expect(find.text('3 호출'), findsOneWidget);
  });

  testWidgets('끊긴 상태에서 녹음 시작 → 스낵', (tester) async {
    final c = await _pump(tester, setup: (c) {
      c.connected = false;
      c.status = _status();
    });
    c.sendOk = false;
    await tester.tap(find.byKey(const ValueKey('mic_check_record')));
    await tester.pump();
    expect(find.text('연결이 끊겨 보내지 못했습니다 · 다시 붙은 뒤 누르세요'), findsOneWidget);
    expect(find.text('● 연결 끊김 · 다시 붙는 중'), findsOneWidget);
  });

  testWidgets('폭 1200 은 두 칸(진행이 오른쪽), 폭 390 은 한 줄', (tester) async {
    await _pump(tester, width: 1200, setup: (c) {
      c.connected = true;
      c.status = _status();
    });
    expect(find.byKey(const ValueKey('mic_check_columns')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('mic_check_right')), matching: find.text('진행')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('mic_check_left')), matching: find.text('실시간')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('mic_check_left')), matching: find.text('진행')), findsNothing);
  });

  testWidgets('폭 390 은 한 줄', (tester) async {
    await _pump(tester, setup: (c) {
      c.connected = true;
      c.status = _status();
    });
    expect(find.byKey(const ValueKey('mic_check_columns')), findsNothing);
    expect(find.text('진행'), findsOneWidget);
  });
}
