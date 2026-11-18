// 클릭·화면 전환 효과(2026-11-18).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/widgets/vica_motion.dart';

class _Counter extends StatefulWidget {
  const _Counter({super.key, required this.label});
  final String label;
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  static int created = 0;
  @override
  void initState() {
    super.initState();
    created++;
  }

  @override
  Widget build(BuildContext context) => Text(widget.label);
}

void main() {
  testWidgets('메뉴를 빠르게 A → B → A 로 눌러도 키가 겹치지 않고 A 가 남는다', (tester) async {
    final settingsKey = GlobalKey();
    Widget screen(int i) => i == 0
        ? _Counter(key: settingsKey, label: 'A')
        : const _Counter(label: 'B');
    Widget host(int i) => MaterialApp(
          home: Scaffold(body: VicaScreenSwitcher(index: i, child: screen(i))),
        );
    await tester.pumpWidget(host(0));
    await tester.pumpWidget(host(1));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpWidget(host(0)); // 나가던 A 가 아직 있는 동안 다시 A
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.takeException(), isNull);
    await tester.pump(kVicaTransition);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsNothing);
  });

  testWidgets('나가는 동안 화면 상태를 다시 만들지 않는다', (tester) async {
    Widget host(int i) => MaterialApp(
          home: Scaffold(
            body: VicaScreenSwitcher(
              index: i,
              child: _Counter(label: i == 0 ? 'A' : 'B'),
            ),
          ),
        );
    _CounterState.created = 0;
    await tester.pumpWidget(host(0));
    await tester.pumpWidget(host(1));
    await tester.pump(kVicaTransition);
    expect(_CounterState.created, 2); // A 하나, B 하나 — 나가는 A 를 새로 만들지 않음
  });

  testWidgets('누를 수 있는 버튼만 살짝 줄어든다', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          PressScale(
              child: FilledButton(onPressed: () {}, child: const Text('켜짐'))),
          const PressScale(
              child: FilledButton(onPressed: null, child: Text('꺼짐'))),
        ]),
      ),
    ));
    double scaleOf(String label) => tester
        .widget<AnimatedScale>(find.ancestor(
            of: find.text(label), matching: find.byType(AnimatedScale)))
        .scale;
    final on = await tester.startGesture(tester.getCenter(find.text('켜짐')));
    final off = await tester.startGesture(tester.getCenter(find.text('꺼짐')));
    await tester.pump();
    expect(scaleOf('켜짐'), kVicaPressScale);
    expect(scaleOf('꺼짐'), 1.0);
    await on.up();
    await off.up();
    await tester.pump();
    expect(scaleOf('켜짐'), 1.0);
  });

  testWidgets('확인 창은 바깥을 누르면 닫히고 결과를 돌려준다', (tester) async {
    bool? result = false;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await showVicaDialog<bool>(
              context: context,
              builder: (_) => const AlertDialog(content: Text('끌까요?')),
            );
          },
          child: const Text('열기'),
        ),
      ),
    ));
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    expect(find.text('끌까요?'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('끌까요?'), findsNothing);
    expect(result, isNull);
  });
}
