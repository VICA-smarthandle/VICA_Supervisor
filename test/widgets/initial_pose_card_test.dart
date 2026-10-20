import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/core/app_settings.dart';
import 'package:vica_supervisor/models/pose_check_result.dart';
import 'package:vica_supervisor/widgets/initial_pose_card.dart';
import 'package:vica_supervisor/widgets/vica_ui.dart';

PoseCheckResult result({
  bool ok = true,
  double score = 82,
  String message = '이 위치로 확정할 수 있습니다.',
}) =>
    PoseCheckResult(
      ok: ok,
      reason: ok ? '' : 'ambiguous',
      message: message,
      score: score,
      x: 1.0,
      y: 2.0,
      yaw: 0,
      usedBeams: 168,
      totalBeams: 721,
      margin: 24,
      movedM: 0.12,
      movedDeg: 8,
    );

/// 확정 버튼을 찾습니다.
Finder _commitButton() => find.widgetWithIcon(FilledButton, Icons.check);

void main() {
  Future<int> pump(
    WidgetTester tester, {
    Offset? picked,
    PoseDirection? direction = PoseDirection.right,
    PoseCheckResult? checked,
    bool busy = false,
    List<String>? calls,
  }) async {
    final log = calls ?? <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: InitialPoseCard(
              picked: picked,
              direction: direction,
              result: checked,
              busy: busy,
              onDirection: (value) => log.add('direction:${value?.name}'),
              onCheck: () => log.add('check'),
              onCommit: () => log.add('commit'),
              onReset: () => log.add('reset'),
              onClose: () => log.add('close'),
            ),
          ),
        ),
      ),
    );
    return log.length;
  }

  testWidgets('자리를 짚기 전에는 확인 버튼이 잠긴다', (tester) async {
    await pump(tester, picked: null);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '여기가 맞는지 확인'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('자리를 짚으면 확인 버튼이 열린다', (tester) async {
    final calls = <String>[];
    await pump(tester, picked: const Offset(1.2, 3.4), calls: calls);
    await tester.tap(find.widgetWithText(FilledButton, '여기가 맞는지 확인'));
    expect(calls, contains('check'));
  });

  testWidgets('확인 전에는 확정 버튼 자체가 없다', (tester) async {
    await pump(tester, picked: const Offset(1, 2));
    expect(_commitButton(), findsNothing);
  });

  testWidgets('노드가 막으면 확정 버튼이 잠긴다', (tester) async {
    await tester.pumpWidget(const SizedBox());
    await pump(
      tester,
      picked: const Offset(1, 2),
      checked: result(ok: false, score: 84, message: '앞뒤가 비슷해 구분이 안 됩니다.'),
    );
    final button = tester.widget<FilledButton>(
      _commitButton(),
    );
    expect(button.onPressed, isNull);
    expect(find.text('84%'), findsOneWidget);
  });

  testWidgets('통과하면 확정을 누를 수 있다', (tester) async {
    final calls = <String>[];
    await pump(
      tester,
      picked: const Offset(1, 2),
      checked: result(),
      calls: calls,
    );
    await tester.tap(_commitButton());
    expect(calls, contains('commit'));
  });

  testWidgets('확인 중에는 모든 버튼이 잠긴다', (tester) async {
    await pump(tester, picked: const Offset(1, 2), busy: true);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '확인 중…'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('얼마나 옮겼는지와 근거 숫자를 함께 보여준다', (tester) async {
    await pump(tester, picked: const Offset(1, 2), checked: result());
    expect(find.text('82%'), findsOneWidget);
    expect(find.text('12 cm, 8° 옮겼습니다.'), findsOneWidget);
    expect(find.text('유효 빔 168 / 721 · 헷갈릴 방향 없음(차이 24점)'), findsOneWidget);
  });

  testWidgets('자리를 짚기 전에는 방향 버튼도 잠긴다', (tester) async {
    await pump(tester, picked: null);
    final chip = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, '왼쪽'),
    );
    expect(chip.onSelected, isNull);
  });

  testWidgets('자리를 짚으면 방향 버튼이 열린다', (tester) async {
    final calls = <String>[];
    await pump(tester, picked: const Offset(1, 2), calls: calls);
    await tester.tap(find.widgetWithText(ChoiceChip, '왼쪽'));
    expect(calls, contains('direction:left'));
  });

  testWidgets('방향을 모르겠음으로 두면 대가를 알려준다', (tester) async {
    await pump(tester, picked: const Offset(1, 2), direction: null);
    expect(find.textContaining(vicaKeepWords('360°')), findsOneWidget);
  });

  group('방향 버튼이 지도 그림 기준이라는 것', () {
    const flipped = AppSettings();
    const notFlipped = AppSettings(flipMapY: false);

    test('좌우는 지도가 뒤집혀도 같다', () {
      expect(PoseDirection.right.yawFor(flipped), 0);
      expect(PoseDirection.right.yawFor(notFlipped), 0);
    });

    test('위아래는 지도가 뒤집히면 반대가 된다', () {
      expect(PoseDirection.up.yawFor(flipped), greaterThan(0));
      expect(PoseDirection.up.yawFor(notFlipped), lessThan(0));
      expect(
        PoseDirection.up.yawFor(flipped),
        -PoseDirection.up.yawFor(notFlipped),
      );
    });

    test('네 방향이 90도씩 벌어져 있다', () {
      final yaws = PoseDirection.values.map((d) => d.yawFor(flipped)).toList();
      expect(yaws.toSet().length, 4);
    });
  });
}
