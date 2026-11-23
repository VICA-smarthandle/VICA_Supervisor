import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/app.dart' show vicaTheme;
import 'package:vica_supervisor/models/mic_check.dart';
import 'package:vica_supervisor/widgets/mic_check/live_card.dart';

MicCheckStatus _status({double listen = 0.012, double short = 0.02}) =>
    MicCheckStatus.fromJson({
      'place': '4층 복도',
      'step': {
        'key': 'call',
        'no': 3,
        'of': 9,
        'name': '호출',
        'say': '',
        'rep': 1,
        'reps': 5,
        'seconds': 6.0,
        'recording': false,
        'robot': false,
      },
      'steps': [
        {'key': 'call', 'name': '호출', 'need': 5},
      ],
      'progress': {'call': []},
      'values': {
        'listen_min_rms': listen,
        'short_answer_min_rms': short,
        'approach_min_rms': null,
        'band_min': 0.004,
        'wake_threshold': 0.62,
        'emergency_single': 0.55,
        'agc': 0.007,
        'agc_max_gain': null,
        'echo': 'mid',
      },
      'env_values': {
        'listen_min_rms': 0.012,
        'short_answer_min_rms': 0.02,
        'approach_min_rms': null,
        'band_min': 0.004,
        'wake_threshold': 0.62,
        'emergency_single': 0.55,
        'agc': 0.007,
        'agc_max_gain': null,
        'echo': 'mid',
      },
    });

MicCheckFrame _frame({double wake = 0.1, double stop = 0.0}) =>
    MicCheckFrame.fromJson({
      'rms': 0.01,
      'wake': wake,
      'stop': stop,
      'robot': false,
      'muted': false,
      'state': 'listening',
      'vad': false,
    });

void main() {
  testWidgets('문턱을 넘은 프레임 뒤 낮은 프레임이 와도 1.5 s 안에는 걸림, 지나면 아래', (tester) async {
    var t = DateTime(2026, 11, 20, 12);
    final status = _status();
    Future<void> show(MicCheckFrame f) async {
      await tester.pumpWidget(MaterialApp(
        theme: vicaTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
              child: MicLiveCard(status: status, frame: f, now: () => t)),
        ),
      ));
    }

    await show(_frame(wake: 0.9, stop: 0.9));
    expect(find.textContaining('걸림'), findsNWidgets(2));

    t = t.add(const Duration(milliseconds: 1000));
    await show(_frame());
    expect(find.textContaining('걸림'), findsNWidgets(2));

    t = t.add(const Duration(milliseconds: 600));
    await show(_frame());
    expect(find.textContaining('걸림'), findsNothing);
    expect(find.textContaining('아래'), findsNWidgets(3));
  });

  testWidgets('수음·짧은 답 문턱이 가까우면 눈금 글자를 한 번만 적는다', (tester) async {
    Future<void> show(MicCheckStatus st) async {
      await tester.pumpWidget(MaterialApp(
        theme: vicaTheme(),
        home: Scaffold(
            body: SingleChildScrollView(
                child: MicLiveCard(status: st, frame: _frame()))),
      ));
    }

    await show(_status(listen: 0.027, short: 0.027));
    expect(find.text('수음·짧은 답'), findsOneWidget);
    expect(find.text('짧은 답'), findsNothing);
    expect(find.text('수음'), findsNothing);

    await show(_status(listen: 0.008, short: 0.05));
    expect(find.text('수음'), findsOneWidget);
    expect(find.text('짧은 답'), findsOneWidget);
    expect(find.text('수음·짧은 답'), findsNothing);
  });
}
