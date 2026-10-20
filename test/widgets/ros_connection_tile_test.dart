import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vica_supervisor/providers/settings_provider.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';
import 'package:vica_supervisor/ros/ros_bridge_client.dart';
import 'package:vica_supervisor/widgets/ros_connection_tile.dart';

class _FakeSupervisor extends SupervisorProvider {
  _FakeSupervisor({required this.fakeState, required this.fakeUrl});

  final RosConnectionState fakeState;
  final String fakeUrl;

  @override
  RosConnectionState get connectionState => fakeState;

  @override
  String get connectedUrl => fakeUrl;
}

Future<void> pump(
  WidgetTester tester, {
  required RosConnectionState state,
  required String connectedUrl,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 800);
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SupervisorProvider>.value(
          value: _FakeSupervisor(fakeState: state, fakeUrl: connectedUrl),
        ),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: const MaterialApp(
        home: Scaffold(body: VicaRosConnectionTile()),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('연결 안 됐으면 상태와 주소를 보여준다', (tester) async {
    await pump(
      tester,
      state: RosConnectionState.disconnected,
      connectedUrl: '',
    );
    expect(find.text('ROS 연결 안 됨'), findsOneWidget);
    expect(find.textContaining('ws://127.0.0.1:9090'), findsOneWidget);
  });

  testWidgets('같은 주소로 연결됐으면 경고가 없다', (tester) async {
    await pump(
      tester,
      state: RosConnectionState.connected,
      connectedUrl: 'ws://127.0.0.1:9090',
    );
    expect(find.text('ROS 연결됨'), findsNWidgets(2));
    expect(find.textContaining('주소가 바뀌었습니다'), findsNothing);
  });

  testWidgets('주소를 바꿔 저장했는데 옛 연결이면 알려준다', (tester) async {
    await pump(
      tester,
      state: RosConnectionState.connected,
      connectedUrl: 'ws://192.168.0.10:9090',
    );
    expect(find.textContaining('주소가 바뀌었습니다'), findsOneWidget);
    expect(find.textContaining('ws://192.168.0.10:9090'), findsOneWidget);
  });

  testWidgets('연결한 적이 없으면 경고하지 않는다', (tester) async {
    await pump(
      tester,
      state: RosConnectionState.connected,
      connectedUrl: '',
    );
    expect(find.textContaining('주소가 바뀌었습니다'), findsNothing);
  });
}
