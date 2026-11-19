// 수동 주행 조종판(2026-11-18). 누르는 동안만 보내고, 놓거나 주행이 시작되면 바로 멈춰야 합니다.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vica_supervisor/app.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';
import 'package:vica_supervisor/ros/ros_bridge_client.dart';
import 'package:vica_supervisor/widgets/manual_drive_card.dart';
import 'package:vica_supervisor/widgets/vica_ui.dart';

class _Recording extends SupervisorProvider {
  final calls = <String>[];
  bool active = false;

  @override
  RosConnectionState get connectionState => RosConnectionState.connected;

  @override
  bool get teleopActive => active;

  @override
  void holdTeleop({
    required double linear,
    required double angular,
    double maxLinear = SupervisorProvider.teleopMaxLinear,
    double maxAngular = SupervisorProvider.teleopMaxAngular,
    double? accel,
  }) {
    active = true;
    calls.add(
        'hold(${linear.toStringAsFixed(2)}, ${angular.toStringAsFixed(2)}, '
        'max ${maxLinear.toStringAsFixed(1)})');
  }

  @override
  void releaseTeleop() {
    active = false;
    calls.add('release');
  }
}

Widget _app(_Recording supervisor, {bool busy = false}) => MaterialApp(
      theme: vicaTheme(),
      home: ChangeNotifierProvider<SupervisorProvider>.value(
        value: supervisor,
        child: Scaffold(
          body: SingleChildScrollView(
            child: ManualDriveCard(
              blockedMessage: busy ? kManualDriveBusyMessage : null,
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('누르는 동안만 보내고 떼면 멈춘다 — 수동 주행 상한 0.7', (tester) async {
    final supervisor = _Recording();
    await tester.pumpWidget(_app(supervisor));
    final gesture = await tester
        .startGesture(tester.getCenter(find.bySemanticsLabel('앞으로')));
    await tester.pump();
    expect(supervisor.calls, ['hold(0.30, 0.00, max 0.7)']);
    await gesture.up();
    await tester.pump();
    expect(supervisor.calls.last, 'release');
  });

  testWidgets('대각선은 직진과 회전을 같이 — 회전은 속도와 같이', (tester) async {
    final supervisor = _Recording();
    await tester.pumpWidget(_app(supervisor));
    final gesture = await tester
        .startGesture(tester.getCenter(find.bySemanticsLabel('앞 오른쪽 선회')));
    await tester.pump();
    expect(supervisor.calls, ['hold(0.30, -0.30, max 0.7)']);
    await gesture.up();
  });

  testWidgets('키보드: ↑ 직진, ↑+← 선회, 놓으면 멈춤, q 로 속도 올림', (tester) async {
    final supervisor = _Recording();
    await tester.pumpWidget(_app(supervisor));
    // 키보드는 조종판에 포커스가 있을 때 받는다(웹은 자동, 시험은 한 번 눌러 준다).
    await tester.tap(find.bySemanticsLabel('정지'));
    await tester.pump();
    supervisor.calls.clear();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyQ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyQ);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyI);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyI);
    expect(supervisor.calls, [
      'hold(0.30, 0.00, max 0.7)',
      'hold(0.30, 0.30, max 0.7)',
      'hold(0.30, 0.00, max 0.7)',
      'release',
      'hold(0.40, 0.00, max 0.7)',
      'release',
    ]);
    await tester.pump();
    expect(find.text(vicaKeepWords('0.40 m/s · 회전 0.40 rad/s')),
        findsOneWidget);
  });

  testWidgets('주행 중이면 막고 두 줄 안내 — 누르던 중 주행이 시작되면 멈춘다', (tester) async {
    final supervisor = _Recording();
    await tester.pumpWidget(_app(supervisor));
    final gesture = await tester
        .startGesture(tester.getCenter(find.bySemanticsLabel('뒤로')));
    await tester.pump();
    expect(supervisor.calls, ['hold(-0.30, 0.00, max 0.7)']);

    await tester.pumpWidget(_app(supervisor, busy: true));
    await tester.pump();
    expect(supervisor.calls.last, 'release');
    expect(find.text('현재 주행 중입니다.\n주행이 완료된 후 사용해주세요.'), findsOneWidget);
    await gesture.up();

    supervisor.calls.clear();
    await tester.tap(find.bySemanticsLabel('앞으로'));
    await tester.pump();
    expect(supervisor.calls.where((c) => c.startsWith('hold')), isEmpty);
  });

  testWidgets('화면을 떠나면 멈춘다', (tester) async {
    final supervisor = _Recording();
    await tester.pumpWidget(_app(supervisor));
    await tester.startGesture(tester.getCenter(find.bySemanticsLabel('앞으로')));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(supervisor.calls.last, 'release');
  });
}
