import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';
import 'package:vica_supervisor/widgets/teleop_pad.dart';
import 'package:vica_supervisor/widgets/vica_ui.dart';

class _RecordingSupervisor extends SupervisorProvider {
  final calls = <String>[];

  @override
  void holdTeleop({required double linear, required double angular}) {
    calls.add('hold($linear, $angular)');
  }

  @override
  void releaseTeleop() => calls.add('release');
}

class _HoldingSupervisor extends SupervisorProvider {
  double? heldLinear;
  double? heldAngular;

  @override
  void holdTeleop({required double linear, required double angular}) {
    heldLinear = linear;
    heldAngular = angular;
    notifyListeners();
  }

  @override
  void releaseTeleop() {
    heldLinear = null;
    heldAngular = null;
    notifyListeners();
  }

  @override
  bool isTeleopHeld({required double linear, required double angular}) =>
      heldLinear == linear && heldAngular == angular;
}

Color _buttonColor(WidgetTester tester, IconData icon) {
  final container = tester.widget<Container>(
    find
        .ancestor(of: find.byIcon(icon), matching: find.byType(Container))
        .first,
  );
  return (container.decoration! as BoxDecoration).color!;
}

// ignore: library_private_types_in_public_api - 테스트 안에서만 쓰는 도우미다.
Future<_RecordingSupervisor> pump(WidgetTester tester,
    {bool enabled = true}) async {
  final supervisor = _RecordingSupervisor();
  await tester.pumpWidget(
    ChangeNotifierProvider<SupervisorProvider>.value(
      value: supervisor,
      child: MaterialApp(
        home: Scaffold(body: TeleopPad(enabled: enabled)),
      ),
    ),
  );
  await tester.pump();
  return supervisor;
}

void main() {
  testWidgets('누르면 명령이 나가고 떼면 멈춘다', (tester) async {
    final supervisor = await pump(tester);

    final gesture = await tester
        .startGesture(tester.getCenter(find.bySemanticsLabel('앞으로')));
    await tester.pump();
    expect(supervisor.calls.single, contains('hold('));

    await gesture.up();
    await tester.pump();
    expect(supervisor.calls.last, 'release');
  });

  testWidgets('앞으로는 양수, 뒤로는 음수 선속도를 보낸다', (tester) async {
    final supervisor = await pump(tester);

    for (final label in ['앞으로', '뒤로']) {
      final gesture = await tester
          .startGesture(tester.getCenter(find.bySemanticsLabel(label)));
      await tester.pump();
      await gesture.up();
      await tester.pump();
    }

    expect(
      supervisor.calls.first,
      'hold(${SupervisorProvider.teleopMaxLinear}, 0.0)',
    );
    expect(
      supervisor.calls[2],
      'hold(${-SupervisorProvider.teleopMaxLinear}, 0.0)',
    );
  });

  testWidgets('손가락이 미끄러져 취소돼도 멈춘다', (tester) async {
    final supervisor = await pump(tester);

    final gesture = await tester
        .startGesture(tester.getCenter(find.bySemanticsLabel('왼쪽')));
    await tester.pump();
    await gesture.cancel();
    await tester.pump();

    expect(supervisor.calls.last, 'release');
  });

  testWidgets('비활성이면 아무 명령도 나가지 않는다', (tester) async {
    final supervisor = await pump(tester, enabled: false);

    final gesture = await tester
        .startGesture(tester.getCenter(find.bySemanticsLabel('앞으로')));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(supervisor.calls, isEmpty);
  });

  testWidgets('상한을 화면에 적어 둔다', (tester) async {
    await pump(tester);
    expect(
      find.textContaining(
        vicaKeepWords('${SupervisorProvider.teleopMaxLinear} m/s'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('누르고 있는 동안만 그 버튼이 진해진다', (tester) async {
    final supervisor = _HoldingSupervisor();
    await tester.pumpWidget(
      ChangeNotifierProvider<SupervisorProvider>.value(
        value: supervisor,
        child: const MaterialApp(
          home: Scaffold(body: TeleopPad(enabled: true)),
        ),
      ),
    );
    await tester.pump();
    expect(_buttonColor(tester, Icons.keyboard_arrow_up), VicaColors.card);

    final gesture = await tester
        .startGesture(tester.getCenter(find.bySemanticsLabel('앞으로')));
    await tester.pump();
    expect(_buttonColor(tester, Icons.keyboard_arrow_up), VicaColors.primary);
    expect(_buttonColor(tester, Icons.keyboard_arrow_down), VicaColors.card);

    await gesture.up();
    await tester.pump();
    expect(_buttonColor(tester, Icons.keyboard_arrow_up), VicaColors.card);
  });
}
