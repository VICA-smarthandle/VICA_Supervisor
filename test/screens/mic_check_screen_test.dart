import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/app.dart' show vicaTheme;
import 'package:vica_supervisor/models/mic_check.dart';
import 'package:vica_supervisor/models/mode_status.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';
import 'package:vica_supervisor/screens/mic_check_screen.dart';
import 'package:vica_supervisor/services/mic_check_controller.dart';
import 'package:vica_supervisor/widgets/mic_check/values_card.dart';

// 가짜 컨트롤러: 보낸 명령을 기록하고 send 결과를 시험이 정합니다. 화면 위젯은 진짜입니다.
class _Fake extends MicCheckController {
  _Fake() : super(uri: Uri.parse('ws://h:8770/ws'));

  final List<(String, Map<String, Object?>)> sent = [];
  bool sendOk = true;

  // 점검기 toast 메시지를 흉내 냅니다.
  final StreamController<String> _fakeToasts = StreamController<String>.broadcast();
  void emitToast(String text) => _fakeToasts.add(text);
  @override
  Stream<String> get toasts => _fakeToasts.stream;

  @override
  bool send(String cmd, [Map<String, Object?> args = const {}]) {
    if (!sendOk) return false;
    sent.add((cmd, args));
    return true;
  }

  void push({
    MicCheckResults? results,
    MicCheckSavePreview? savePreview,
    String? busy,
    String? prep,
    MicCheckStatus? status,
    MicCheckFrame? frame,
    bool? connected,
  }) {
    if (prep != null) this.prep = prep;
    if (results != null) this.results = results;
    if (savePreview != null) this.savePreview = savePreview;
    if (busy != null) this.busy = busy;
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
  double listen = 0.012,
  double shortOver = 1.0,
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
        'listen_min_rms': listen, 'short_answer_min_rms': 0.02, 'approach_min_rms': null, 'band_min': 0.004,
        'wake_threshold': 0.62, 'emergency_single': 0.55,
        'agc': 0.007, 'agc_max_gain': null, 'echo': 'mid',
      },
      'env_values': {
        'listen_min_rms': 0.012, 'short_answer_min_rms': 0.02, 'approach_min_rms': null, 'band_min': 0.004,
        'wake_threshold': 0.62, 'emergency_single': 0.55,
        'agc': 0.007, 'agc_max_gain': null, 'echo': 'mid',
      },
      'ranges': {
        'listen_min_rms': [0.005, 0.04, 0.001], 'short_answer_min_rms': [0.01, 0.05, 0.001],
        'approach_min_rms': [0.002, 0.03, 0.001], 'band_min': [0.001, 0.008, 0.001],
        'wake_threshold': [0.5, 0.9, 0.01], 'emergency_single': [0.4, 0.7, 0.01],
      },
      'names': {
        'listen_min_rms': '수음 최소', 'short_answer_min_rms': '짧은 답 최소', 'approach_min_rms': '접근 대답 최소',
        'band_min': '말소리 대역 최소', 'wake_threshold': '호출 문턱', 'emergency_single': '“멈춰” 한 조각 문턱',
        'agc': 'AGC 목표', 'agc_max_gain': 'AGC 최대 증폭', 'echo': '에코 지우기',
      },
      'env_keys': {
        'listen_min_rms': 'VICA_LISTEN_MIN_RMS', 'short_answer_min_rms': 'VICA_SHORT_ANSWER_MIN_RMS',
        'approach_min_rms': 'VICA_APPROACH_MIN_RMS', 'band_min': 'VICA_LISTEN_BAND_MIN',
        'wake_threshold': 'VICA_WAKE_THRESHOLD', 'emergency_single': 'VICA_EMERGENCY_SINGLE_FRAME',
        'agc': 'VICA_MIC_AGC_DESIRED', 'agc_max_gain': 'VICA_MIC_AGC_MAX_GAIN', 'echo': 'VICA_MIC_GAMMA_ETAIL',
      },
      'agc_choices': [0.005, 0.007, 0.01],
      'gain_choices': [2.0, 4.0, 8.0, 31.6],
      'echo_choices': {'strong': '센', 'mid': '중간', 'factory': '공장값', 'start': '처음 값'},
      'gain_factory': 31.6,
      'short_over_listen': shortOver,
      'chip_ok': chipOk,
      if (noiseAtCheck != null) 'noise_at_check': noiseAtCheck,
    });

MicCheckFrame _frame({double? recLeft, double? noise, bool robot = false}) => MicCheckFrame.fromJson({
      'rms': 0.061, 'wake': 0.84, 'stop': 0.08, 'robot': robot, 'muted': false,
      'state': 'listening', 'vad': true,
      if (noise != null) 'noise': noise,
      if (recLeft != null) 'rec_left': recLeft,
    });

MicCheckResults _results({bool stale = false, bool withFirst = false}) => MicCheckResults.fromJson({
      'title': '사용 가능 · 확인 필요', 'overall': 'warn', 'stale': stale,
      'rows': [
        {'key': 'call', 'name': '호출', 'grade': 'pass', 'detail': '3/3 · 최고 0.84', 'todo': ''},
        {'key': 'aside', 'name': '옆사람 잡담 ×3', 'grade': 'warn', 'detail': '접근 창 1/3 샘', 'todo': '접근 대답 최소를 올려 보세요'},
      ],
      if (withFirst)
        'first': [
          {'key': 'call', 'name': '호출', 'grade': 'fail', 'detail': '1/3', 'todo': ''},
        ],
    });

Future<_Fake> _pump(WidgetTester tester, {double width = 390, void Function(_Fake)? setup}) async {
  tester.view.physicalSize = Size(width, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  final c = _Fake();
  addTearDown(c.dispose);
  setup?.call(c);
  await tester.pumpWidget(MaterialApp(theme: vicaTheme(), home: MicCheckScreen(controller: c)));
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
    expect(find.text('● 끊김 · 다시 붙는 중'), findsOneWidget);
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

  group('결과표', () {
    testWidgets('머리 칩·줄·낡음 안내·처음 값', (tester) async {
      final c = await _pump(tester, setup: (c) {
        c.connected = true;
        c.status = _status();
        c.results = _results(stale: true, withFirst: true);
      });
      expect(find.text('사용 가능 · 확인 필요'), findsOneWidget);
      expect(find.text('값이 바뀌었습니다 · 다시 채점하세요'), findsOneWidget);
      expect(find.text('옆사람 잡담 ×3'), findsOneWidget);
      expect(find.text('접근 창 1/3 샘'), findsOneWidget);
      expect(find.text('접근 대답 최소를 올려 보세요'), findsOneWidget);
      expect(find.text('1/3'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('mic_check_first_toggle')));
      await tester.pump();
      expect(find.text('1/3'), findsOneWidget);
      expect(find.textContaining('처음 값 결과 보기'), findsOneWidget);
      c.push(results: _results());
      await tester.pump();
      expect(find.text('값이 바뀌었습니다 · 다시 채점하세요'), findsNothing);
      expect(find.textContaining('처음 값 결과 보기'), findsNothing);
    });

    testWidgets('결과가 없으면 결과표 카드가 없다', (tester) async {
      await _pump(tester, setup: (c) {
        c.connected = true;
        c.status = _status();
      });
      expect(find.text('결과표'), findsNothing);
    });

    testWidgets('busy 면 다시 채점하는 중 덮개', (tester) async {
      final c = await _pump(tester, setup: (c) {
        c.connected = true;
        c.status = _status();
        c.results = _results();
      });
      expect(find.byKey(const ValueKey('mic_check_busy_cover')), findsNothing);
      c.push(busy: '다시 채점하는 중');
      await tester.pump();
      expect(find.descendant(of: find.byKey(const ValueKey('mic_check_busy_cover')), matching: find.text('다시 채점하는 중')),
          findsOneWidget);
    });
  });

  group('값 고치기', () {
    Future<_Fake> open(WidgetTester tester, {MicCheckStatus? status}) => _pump(tester, setup: (c) {
          c.connected = true;
          c.status = status ?? _status();
        });

    testWidgets('이름·키·범위·null 뜻·바뀜 없음', (tester) async {
      await open(tester);
      for (final t in ['수음 최소', '짧은 답 최소', '접근 대답 최소', '말소리 대역 최소', '호출 문턱', '“멈춰” 한 조각 문턱',
        'AGC 목표', 'AGC 최대 증폭', '에코 지우기']) {
        expect(find.descendant(of: find.byType(MicValuesCard), matching: find.text(t)), findsOneWidget, reason: t);
      }
      expect(find.text('VICA_LISTEN_MIN_RMS · 0.005~0.040'), findsOneWidget);
      expect(find.text('VICA_WAKE_THRESHOLD · 0.50~0.90'), findsOneWidget);
      expect(find.text('줄 없음 · 수음 최소 따름'), findsOneWidget);
      expect(find.text('×31.6 (줄 없음 · 칩 공장값)'), findsOneWidget);
      expect(find.text('바뀜'), findsNothing);
      expect(find.text('0.012'), findsOneWidget);
    });

    testWidgets('값이 .env 와 다르면 바뀜', (tester) async {
      await open(tester, status: _status(listen: 0.032));
      expect(find.text('바뀜'), findsOneWidget);
      expect(find.text('0.032'), findsOneWidget);
      expect(find.text('VICA_LISTEN_MIN_RMS · .env 0.012 · 0.005~0.040'), findsOneWidget);
    });

    testWidgets('슬라이더를 놓으면 set', (tester) async {
      final c = await open(tester);
      final s = find.byKey(const ValueKey('mic_check_slider_wake_threshold'));
      await tester.ensureVisible(s);
      await tester.pump();
      await tester.drag(s, const Offset(60, 0));
      await tester.pump();
      final set = c.sent.where((e) => e.$1 == 'set').toList();
      expect(set.length, 1);
      expect(set.single.$2['key'], 'wake_threshold');
      expect(set.single.$2['value'], isA<double>());
      expect(set.single.$2['value'] as double, greaterThan(0.62));
    });

    testWidgets('단추 묶음 set: AGC·최대 증폭·에코', (tester) async {
      final c = await open(tester);
      for (final k in ['mic_check_agc_0.01', 'mic_check_agc_max_gain_4', 'mic_check_echo_strong']) {
        final f = find.byKey(ValueKey(k));
        await tester.ensureVisible(f);
        await tester.pump();
        await tester.tap(f);
        await tester.pump();
      }
      expect(c.sent.map((e) => e.$2).toList(), [
        {'key': 'agc', 'value': 0.01},
        {'key': 'agc_max_gain', 'value': 4.0},
        {'key': 'echo', 'value': 'strong'},
      ]);
      for (final t in ['×2', '×4', '×8', '×31.6', '센', '중간', '공장값', '처음 값']) {
        expect(find.text(t), findsWidgets, reason: t);
      }
      expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('mic_check_agc_max_gain_31.6'))).selected, isTrue);
      expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('mic_check_echo_mid'))).selected, isTrue);
    });

    testWidgets('짧은 답 안내 한 줄 · 배율이 크면 저장 막힘', (tester) async {
      await open(tester);
      expect(find.text('수음 최소 이상'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('mic_check_save'))).onPressed, isNotNull);
      await tester.pumpWidget(const SizedBox());
      await open(tester, status: _status(shortOver: 2.0));
      expect(find.text('수음 최소의 2배 이상'), findsOneWidget);
      expect(find.textContaining('이대로는 저장할 수 없습니다'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('mic_check_save'))).onPressed, isNull);
    });
  });

  group('시트·끝', () {
    Future<void> tapKey(WidgetTester tester, String key) async {
      final f = find.byKey(ValueKey(key));
      await tester.ensureVisible(f);
      await tester.pump();
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    testWidgets('다시 채점', (tester) async {
      final c = await _pump(tester, setup: (c) {
        c.connected = true;
        c.status = _status();
      });
      await tapKey(tester, 'mic_check_rejudge');
      expect(c.sent.single.$1, 'rejudge');
    });

    testWidgets('저장 → save_preview 도착 → 시트 → 저장', (tester) async {
      final c = await _pump(tester, setup: (c) {
        c.connected = true;
        c.status = _status();
      });
      await tapKey(tester, 'mic_check_save');
      expect(c.sent.single.$1, 'save_preview');
      expect(find.text('.env 에 이렇게 씁니다'), findsNothing);
      c.push(savePreview: const MicCheckSavePreview(
        lines: ['VICA_LISTEN_MIN_RMS 0.012 → 0.032'], backupDir: '/b'));
      await tester.pumpAndSettle();
      expect(find.text('.env 에 이렇게 씁니다'), findsOneWidget);
      expect(find.text('VICA_LISTEN_MIN_RMS 0.012 → 0.032'), findsOneWidget);
      expect(find.text('백업 뒤 저장 · 음성 노드를 다시 켜야 적용'), findsOneWidget);
      await tapKey(tester, 'mic_check_sheet_ok');
      expect(c.sent.last.$1, 'save');
      expect(find.text('.env 에 이렇게 씁니다'), findsNothing);
    });

    testWidgets('저장 시트에서 취소하면 보내지 않는다', (tester) async {
      final c = await _pump(tester, setup: (c) {
        c.connected = true;
        c.status = _status();
      });
      await tapKey(tester, 'mic_check_save');
      c.push(savePreview: const MicCheckSavePreview(lines: ['a'], backupDir: '/b'));
      await tester.pumpAndSettle();
      await tapKey(tester, 'mic_check_sheet_cancel');
      expect(c.sent.map((e) => e.$1), ['save_preview']);
    });

    testWidgets('원래대로 → 시트 → 되돌리기', (tester) async {
      final c = await _pump(tester, setup: (c) {
        c.connected = true;
        c.status = _status();
      });
      await tapKey(tester, 'mic_check_restore');
      expect(find.text('가장 최근 백업으로 되돌릴까요?'), findsOneWidget);
      expect(find.text('마이크 값 10개만 · 음성 노드를 다시 켜야 적용'), findsOneWidget);
      expect(find.text('되돌리기'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mic_check_sheet_ok')));
      await tester.pumpAndSettle();
      expect(c.sent.single.$1, 'restore');
    });

    testWidgets('toasts 는 스낵 한 번', (tester) async {
      final c = await _pump(tester, setup: (c) {
        c.connected = true;
        c.status = _status();
      });
      c.emitToast('저장했습니다 · 음성 노드를 다시 켜야 적용됩니다');
      await tester.pump();
      expect(find.text('저장했습니다 · 음성 노드를 다시 켜야 적용됩니다'), findsOneWidget);
    });

    // 화면을 route 로 열어 pop 결과를 받습니다.
    Future<(_Fake, SupervisorProvider, List<bool?>)> openRoute(WidgetTester tester, {bool withStatus = true}) async {
      tester.view.physicalSize = const Size(390, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      final c = _Fake()..connected = true;
      if (withStatus) c.status = _status();
      addTearDown(c.dispose);
      final sup = _StopRecorder();
      addTearDown(sup.dispose);
      final results = <bool?>[];
      // 뒤 화면에 Scaffold 가 있어야 닫힌 뒤에도 스낵이 보입니다(실제 앱은 대시보드).
      await tester.pumpWidget(MaterialApp(theme: vicaTheme(),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () async => results.add(await Navigator.of(ctx).push<bool>(
                  MaterialPageRoute(builder: (_) => MicCheckScreen(controller: c, supervisor: sup)))),
              child: const Text('열기'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      return (c, sup, results);
    }

    testWidgets('끝내기 → 시트 → finish 보내고 true 로 닫힘', (tester) async {
      final (c, sup, results) = await openRoute(tester);
      await tester.tap(find.byKey(const ValueKey('mic_check_finish')));
      await tester.pumpAndSettle();
      expect(find.text('점검을 끝낼까요?'), findsOneWidget);
      expect(find.text('칩을 .env 값으로 되돌리고 끝냅니다 · 기록은 젯슨에 남음'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mic_check_sheet_ok')));
      await tester.pumpAndSettle();
      expect(c.sent.single.$1, 'finish');
      expect((sup as _StopRecorder).stops, 0);
      expect(results, [true]);
      expect(find.byType(MicCheckScreen), findsNothing);
    });

    testWidgets('끊겨 finish 를 못 보내면 stopMicCheck 로 대신하고 true', (tester) async {
      final (c, sup, results) = await openRoute(tester);
      c.sendOk = false;
      await tester.tap(find.byKey(const ValueKey('mic_check_finish')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mic_check_sheet_ok')));
      await tester.pumpAndSettle();
      expect((sup as _StopRecorder).stops, 1);
      expect(results, [true]);
    });

    testWidgets('준비 중(status 없음)에 끝내기를 확정하면 finish 대신 stopMicCheck 로 true', (tester) async {
      final (c, sup, results) = await openRoute(tester, withStatus: false);
      await tester.tap(find.byKey(const ValueKey('mic_check_finish')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mic_check_sheet_ok')));
      await tester.pumpAndSettle();
      expect(c.sent, isEmpty);
      expect((sup as _StopRecorder).stops, 1);
      expect(results, [true]);
    });

    testWidgets('끝내기 시트 취소는 닫지 않는다', (tester) async {
      final (c, _, results) = await openRoute(tester);
      await tester.tap(find.byKey(const ValueKey('mic_check_finish')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mic_check_sheet_cancel')));
      await tester.pumpAndSettle();
      expect(c.sent, isEmpty);
      expect(results, isEmpty);
      expect(find.byType(MicCheckScreen), findsOneWidget);
    });

    testWidgets('점검기가 스스로 끝나면(activating → inactive) 스낵 뒤 false 로 닫힘', (tester) async {
      final (_, sup, results) = await openRoute(tester);
      sup.setModeStatusForTest(const ModeStatus(mode: 'idle', state: ModeState.idle, micCheck: 'activating'));
      await tester.pump();
      expect(find.byType(MicCheckScreen), findsOneWidget);
      sup.setModeStatusForTest(const ModeStatus(mode: 'idle', state: ModeState.idle, micCheck: 'inactive'));
      await tester.pumpAndSettle();
      expect(find.text('점검기가 끝났습니다'), findsOneWidget);
      expect(find.byType(MicCheckScreen), findsNothing);
      expect(results, [false]);
    });

    testWidgets('점검 중이 아니던 상태의 inactive 는 닫지 않는다', (tester) async {
      final (_, sup, results) = await openRoute(tester);
      sup.setModeStatusForTest(const ModeStatus(mode: 'idle', state: ModeState.idle, micCheck: 'inactive'));
      await tester.pumpAndSettle();
      expect(find.byType(MicCheckScreen), findsOneWidget);
      expect(results, isEmpty);
    });
  });
}

class _StopRecorder extends SupervisorProvider {
  int stops = 0;

  @override
  Future<(bool, String)> stopMicCheck() async {
    stops++;
    return (true, '');
  }
}
