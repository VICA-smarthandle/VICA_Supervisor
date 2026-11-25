// 물류 배송 '매니퓰레이터' 칸(2026-11-25, 목업 112)의 규칙을 고정합니다.
//
// 평소엔 [동작] 하나, 누르면 응답까지 '동작 중…'으로 잠김, 응답 문장은 그대로 남김,
// '홈 복귀 실패'일 때만 [홈으로]. rosbridge 없이 callManipulator 만 바꿔 끼웁니다.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';
import 'package:vica_supervisor/widgets/manipulator_card.dart';

class _FakeSupervisor extends SupervisorProvider {
  final calls = <String>[];
  final replies = <Completer<(bool, String)>>[];

  @override
  Future<(bool, String)> callManipulator(String service, Duration timeout) {
    calls.add('$service ${timeout.inSeconds}');
    final reply = Completer<(bool, String)>();
    replies.add(reply);
    return reply.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<_FakeSupervisor> pump(WidgetTester tester) async {
    final supervisor = _FakeSupervisor();
    await tester.pumpWidget(
      ChangeNotifierProvider<SupervisorProvider>.value(
        value: supervisor,
        child: const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: ManipulatorCard())),
        ),
      ),
    );
    await tester.pump();
    return supervisor;
  }

  FilledButton runButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byWidgetPredicate((w) => w is FilledButton));

  Future<void> answer(WidgetTester tester, _FakeSupervisor s, bool ok, String message) async {
    s.replies.last.complete((ok, message));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('처음엔 [동작] 하나만 있다', (tester) async {
    await pump(tester);
    expect(find.text('매니퓰레이터'), findsOneWidget);
    expect(find.text('동작'), findsOneWidget);
    expect(find.text('홈으로'), findsNothing);
  });

  testWidgets('누르면 응답까지 동작 중…으로 잠기고 응답 문장을 그대로 남긴다', (tester) async {
    final s = await pump(tester);
    await tester.tap(find.text('동작'));
    await tester.pump();
    expect(s.calls, ['/app/arm_demo 190']);
    expect(find.text('동작 중…'), findsOneWidget);
    expect(runButton(tester).onPressed, isNull);

    // 11-25 14:32 실측 응답.
    const done = '시연 완료(down, 닿음, 불 안 켜짐) → 홈 (27초)';
    await answer(tester, s, true, done);
    expect(find.textContaining(done), findsOneWidget);
    expect(find.text('동작'), findsOneWidget);
    expect(runButton(tester).onPressed, isNotNull);
    expect(find.text('홈으로'), findsNothing);
  });

  testWidgets('거절은 문장만 남기고 [홈으로]는 없다', (tester) async {
    final s = await pump(tester);
    await tester.tap(find.text('동작'));
    await tester.pump();
    await answer(tester, s, false, '거절: 비상정지 중');
    expect(find.textContaining('거절: 비상정지 중'), findsOneWidget);
    expect(find.text('홈으로'), findsNothing);
  });

  testWidgets('홈 복귀 실패일 때만 [홈으로]가 나오고 /app/arm_home 을 부른다', (tester) async {
    final s = await pump(tester);
    await tester.tap(find.text('동작'));
    await tester.pump();
    await answer(tester, s, false,
        '시연 실패(down): 계획 실패 → 홈 복귀 실패: 계획 실패 — 팔이 펴져 있을 수 있음');
    expect(find.text('홈으로'), findsOneWidget);
    expect(find.textContaining('현장에서 팔을 받친 뒤 힘 빼기'), findsOneWidget);

    await tester.tap(find.text('홈으로'));
    await tester.pump();
    expect(s.calls, ['/app/arm_demo 190', '/app/arm_home 70']);
    expect(find.text('동작 중…'), findsOneWidget);

    await answer(tester, s, true, '홈 도착');
    expect(find.textContaining('홈 도착'), findsOneWidget);
    expect(find.text('홈으로'), findsNothing);
  });
}
