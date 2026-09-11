import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vica_supervisor/providers/settings_provider.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';
import 'package:vica_supervisor/screens/system_diagnostics_screen.dart';
import 'package:vica_supervisor/widgets/health_banner.dart';

Map<String, Object?> faultMsg({
  String component = 'lidar',
  String faultCode = 'LIDAR_SCAN_STALE',
  int severity = 3,
  bool latched = false,
  int occurrenceCount = 3,
  String detail = '/scan이 2.1초 동안 수신되지 않았습니다.',
  String action = 'LiDAR USB 연결과 rplidar 노드 실행 상태를 확인해 주세요.',
}) {
  return {
    'component': component,
    'fault_code': faultCode,
    'severity': severity,
    'active': true,
    'latched': latched,
    'occurrence_count': occurrenceCount,
    'first_seen': {'sec': 1785410054, 'nanosec': 0},
    'last_seen': {'sec': 1785410096, 'nanosec': 0},
    'detail': detail,
    'suggested_action': action,
  };
}

Map<String, Object?> healthMsg({
  int state = 3,
  int highestSeverity = 3,
  String primary = 'LIDAR_SCAN_STALE',
  List<Map<String, Object?>>? faults,
  int guidanceReadiness = 0,
}) {
  final list = faults ?? [faultMsg()];
  return {
    'state': state,
    'motor_readiness': 2,
    'safety_readiness': 2,
    'localization_readiness': 2,
    'navigation_readiness': 2,
    'lidar_readiness': 1,
    'perception_readiness': 2,
    'guidance_readiness': guidanceReadiness,
    'voice_readiness': 0,
    'app_readiness': 0,
    'active_fault_count': list.length,
    'highest_severity': highestSeverity,
    'primary_fault_code': primary,
    'active_faults': list,
  };
}

/// 테스트에서 provider에 상태를 넣기 위한 도우미.
class _FakeSupervisor extends SupervisorProvider {
  void injectHealth(Map<String, Object?> msg) => handleRobotHealthForTest(msg);

  void injectEvent(Map<String, Object?> msg) => handleRobotEventForTest(msg);
}

Widget wrap(Widget child, SupervisorProvider supervisor) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<SupervisorProvider>.value(value: supervisor),
      ChangeNotifierProvider(create: (_) => SettingsProvider()),
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  group('SystemDiagnosticsScreen', () {
    testWidgets('상태를 아직 못 받았으면 안내 문구를 보여준다', (tester) async {
      final supervisor = _FakeSupervisor();
      await tester
          .pumpWidget(wrap(const SystemDiagnosticsScreen(), supervisor));
      await tester.pump();

      expect(find.textContaining('아직 로봇 상태를 받지 못했습니다'), findsOneWidget);
    });

    testWidgets('활성 결함의 컴포넌트·등급·조치를 모두 보여준다', (tester) async {
      final supervisor = _FakeSupervisor()..injectHealth(healthMsg());
      await tester
          .pumpWidget(wrap(const SystemDiagnosticsScreen(), supervisor));
      await tester.pump();

      expect(find.text('LiDAR'), findsWidgets);
      expect(find.text('주행 불가'), findsWidgets);
      expect(find.text('LIDAR_SCAN_STALE'), findsOneWidget);
      expect(find.textContaining('2.1초'), findsOneWidget);
      expect(find.textContaining('USB 연결'), findsOneWidget);
    });

    testWidgets('발생 횟수와 지속 시간을 보여준다', (tester) async {
      final supervisor = _FakeSupervisor()..injectHealth(healthMsg());
      await tester
          .pumpWidget(wrap(const SystemDiagnosticsScreen(), supervisor));
      await tester.pump();

      expect(find.textContaining('3회'), findsOneWidget);
      expect(find.textContaining('지속'), findsOneWidget);
    });

    testWidgets('래치된 결함에 래치 배지를 붙인다', (tester) async {
      final supervisor = _FakeSupervisor()
        ..injectHealth(healthMsg(faults: [faultMsg(latched: true)]));
      await tester
          .pumpWidget(wrap(const SystemDiagnosticsScreen(), supervisor));
      await tester.pump();

      expect(find.text('래치'), findsOneWidget);
    });

    testWidgets('관측 불가를 정상과 구분해 표시한다', (tester) async {
      final supervisor = _FakeSupervisor()..injectHealth(healthMsg());
      await tester
          .pumpWidget(wrap(const SystemDiagnosticsScreen(), supervisor));
      await tester.pump();

      expect(find.text('관측 불가'), findsWidgets);
      expect(
        find.textContaining('상태를 확인할 수단이 없다는'),
        findsOneWidget,
      );
    });

    testWidgets('관측 불가가 없으면 설명 문구도 없다', (tester) async {
      final supervisor = _FakeSupervisor()
        ..injectHealth(healthMsg(guidanceReadiness: 2));
      await tester
          .pumpWidget(wrap(const SystemDiagnosticsScreen(), supervisor));
      await tester.pump();

      expect(find.text('안내 장치'), findsOneWidget);
    });

    testWidgets('결함이 없으면 없다고 알린다', (tester) async {
      final supervisor = _FakeSupervisor()
        ..injectHealth(
          healthMsg(state: 1, highestSeverity: 0, primary: '', faults: []),
        );
      await tester
          .pumpWidget(wrap(const SystemDiagnosticsScreen(), supervisor));
      await tester.pump();

      expect(find.text('현재 보고된 결함이 없습니다.'), findsOneWidget);
      expect(find.text('준비 완료'), findsOneWidget);
    });

    testWidgets('이벤트 이력을 보여주고 reminder는 제외한다', (tester) async {
      final supervisor = _FakeSupervisor()
        ..injectHealth(healthMsg())
        ..injectEvent({'fault': faultMsg(), 'transition': 0})
        ..injectEvent({'fault': faultMsg(), 'transition': 2})
        ..injectEvent({
          'fault': faultMsg(component: 'motor', faultCode: 'MOTOR_CAN_TIMEOUT'),
          'transition': 3,
        });
      await tester
          .pumpWidget(wrap(const SystemDiagnosticsScreen(), supervisor));
      await tester.pump();

      expect(find.textContaining('· 발생'), findsWidgets);
      expect(find.textContaining('· 해소'), findsWidgets);
      expect(find.textContaining('지속 중'), findsNothing);
    });
  });

  group('HealthBanner', () {
    testWidgets('상태를 못 받았으면 아무것도 그리지 않는다', (tester) async {
      final supervisor = _FakeSupervisor();
      await tester.pumpWidget(wrap(const HealthBanner(), supervisor));
      await tester.pump();

      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('결함이 없으면 아무것도 그리지 않는다', (tester) async {
      final supervisor = _FakeSupervisor()
        ..injectHealth(
          healthMsg(state: 1, highestSeverity: 0, primary: '', faults: []),
        );
      await tester.pumpWidget(wrap(const HealthBanner(), supervisor));
      await tester.pump();

      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('최고 등급 결함을 한 줄로 보여준다', (tester) async {
      final supervisor = _FakeSupervisor()..injectHealth(healthMsg());
      await tester.pumpWidget(wrap(const HealthBanner(), supervisor));
      await tester.pump();

      expect(find.textContaining('주행 불가'), findsOneWidget);
      expect(find.textContaining('LiDAR'), findsOneWidget);
      expect(find.textContaining('2.1초'), findsOneWidget);
    });

    testWidgets('다른 결함 수를 함께 알린다', (tester) async {
      final supervisor = _FakeSupervisor()
        ..injectHealth(
          healthMsg(
            faults: [
              faultMsg(),
              faultMsg(component: 'motor', faultCode: 'MOTOR_CAN_TIMEOUT'),
            ],
          ),
        );
      await tester.pumpWidget(wrap(const HealthBanner(), supervisor));
      await tester.pump();

      expect(find.text('다른 결함 1건'), findsOneWidget);
    });

    testWidgets('탭하면 콜백을 부른다', (tester) async {
      var tapped = false;
      final supervisor = _FakeSupervisor()..injectHealth(healthMsg());
      await tester.pumpWidget(
        wrap(HealthBanner(onTap: () => tapped = true), supervisor),
      );
      await tester.pump();

      await tester.tap(find.byType(InkWell));
      expect(tapped, isTrue);
    });
  });
}
