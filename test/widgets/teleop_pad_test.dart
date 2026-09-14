// teleop 조작판이 "누르고 있는 동안만" 명령을 내는지 고정합니다.
//
// 이것이 무너지면 데드맨이 통째로 무력해집니다. safety_supervisor_node 와
// mdrobot_can_control 의 cmd_timeout_sec 0.5 는 "손을 떼면 명령이 끊긴다"를
// 전제로 로봇을 세웁니다. 눌러 두고 손을 떼도 계속 가면 그 전제가 깨집니다.
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

// 명령을 실제로 "들고 있는" 척하는 provider. 버튼 색은 이 판정을 따른다.
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
    find.ancestor(of: find.byIcon(icon), matching: find.byType(Container)).first,
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
    // 버튼 밖으로 끌고 나가거나 시스템이 제스처를 가로챌 때다. 이때 안 멈추면
    // 사용자는 뗐다고 생각하는데 로봇은 간다.
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
    // 값이 코드에서만 바뀌고 문구가 그대로면 사람이 잘못 안다.
    await pump(tester);
    expect(
      find.textContaining('${SupervisorProvider.teleopMaxLinear} m/s'),
      findsOneWidget,
    );
  });

  testWidgets('누르고 있는 동안만 그 버튼이 진해진다', (tester) async {
    // 색의 근거는 버튼의 눌림이 아니라 provider 가 실제로 보내는 명령이다.
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
    expect(_buttonColor(tester, Icons.keyboard_arrow_up), VicaColors.softBlue);

    final gesture = await tester
        .startGesture(tester.getCenter(find.bySemanticsLabel('앞으로')));
    await tester.pump();
    expect(_buttonColor(tester, Icons.keyboard_arrow_up), VicaColors.primary);
    // 다른 버튼은 그대로다 — 명령이 하나뿐이라 하나만 빛난다.
    expect(_buttonColor(tester, Icons.keyboard_arrow_down), VicaColors.softBlue);

    await gesture.up();
    await tester.pump();
    expect(_buttonColor(tester, Icons.keyboard_arrow_up), VicaColors.softBlue);
  });
}
