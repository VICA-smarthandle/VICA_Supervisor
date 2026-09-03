// 물류 배송 화면의 문턱을 고정합니다.
//
// **이 파일이 지키는 결함**
//   - 연락처 없는 장소가 배송 대상으로 보여 출발 버튼이 왜 잠겼는지 알 수 없다.
//   - "물건을 실었다"를 확인하지 않고도 출발할 수 있다 — 로봇은 적재 센서가 없다.
//   - 화면에 전화번호 전체가 그대로 보인다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vica_supervisor/models/delivery_job.dart';
import 'package:vica_supervisor/models/location_point.dart';
import 'package:vica_supervisor/providers/settings_provider.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';
import 'package:vica_supervisor/screens/delivery_screen.dart';

const _office = LocationPoint(
  locationId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  mapId: 'starlight_1f',
  name: '305호',
  x: 1,
  y: 2,
  yaw: 0,
  contactPhone: '01012345678',
);

class _FakeSupervisor extends SupervisorProvider {
  void injectMap() => handleMapListForTest({
        'maps': [
          {
            'map_id': 'starlight_1f',
            'map_name': 'starlight_1f',
            'resolution': 0.05,
            'origin_x': 0.0,
            'origin_y': 0.0,
            'width': 200,
            'height': 200,
          },
        ],
      });

  void injectLocations(List<LocationPoint> locations) =>
      handleLocationListForTest({
        'map_id': 'starlight_1f',
        'locations': locations.map((e) => e.toJson()).toList(),
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<_FakeSupervisor> pump(
    WidgetTester tester, {
    List<LocationPoint> locations = const [],
  }) async {
    // 화면이 세로로 깁니다(지도 + 카드 둘). 기본 시험 화면(800x600)에서는 아래
    // 칸이 밖에 있어 탭이 허공을 누릅니다. 세로를 넉넉히 줍니다.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final supervisor = _FakeSupervisor();
    supervisor.injectMap();
    supervisor.injectLocations(locations);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SupervisorProvider>.value(value: supervisor),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ],
        child: const MaterialApp(
          home: Scaffold(body: DeliveryScreen()),
        ),
      ),
    );
    await tester.pump();
    return supervisor;
  }

  FilledButton startButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, '배송 출발'));

  testWidgets('연락처 없는 장소는 배송 대상에 나오지 않는다', (tester) async {
    const lobby = LocationPoint(
      locationId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
      mapId: 'starlight_1f',
      name: '로비',
      x: 0,
      y: 0,
      yaw: 0,
    );
    await pump(tester, locations: [lobby]);
    expect(find.text('연락처가 저장된 장소가 아직 없습니다.'), findsOneWidget);
    expect(find.textContaining('로비'), findsNothing);
  });

  testWidgets('번호는 가려서 보인다', (tester) async {
    await pump(tester, locations: [_office]);
    expect(find.textContaining('010-****-5678'), findsOneWidget);
    expect(find.textContaining('01012345678'), findsNothing);
    expect(find.textContaining('1234'), findsNothing);
  });

  testWidgets('장소를 고르고 적재를 확인해야 출발이 열린다', (tester) async {
    await pump(tester, locations: [_office]);
    expect(startButton(tester).onPressed, isNull);

    await tester.tap(find.textContaining('305호'));
    await tester.pump();
    expect(startButton(tester).onPressed, isNull, reason: '적재 확인 전');

    await tester.tap(find.text('물건을 실었습니다'));
    await tester.pump();
    expect(startButton(tester).onPressed, isNotNull);
  });

  testWidgets('배송 중에는 새 출발이 잠기고 상태 카드가 뜬다', (tester) async {
    final supervisor = await pump(tester, locations: [_office]);
    supervisor.setDeliveryForTest(
      DeliveryJob(destination: _office, startedAt: DateTime(2026)),
    );
    await tester.pump();
    expect(find.text('배송 중'), findsWidgets);
    expect(find.widgetWithText(FilledButton, '배송 중'), findsOneWidget);
    expect(find.text('배송 취소'), findsOneWidget);
  });

  testWidgets('중단된 배송은 문자를 안 보냈다고 말하고 지울 수 있다', (tester) async {
    final supervisor = await pump(tester, locations: [_office]);
    supervisor.setDeliveryForTest(
      DeliveryJob(destination: _office, startedAt: DateTime(2026))
          .copyWith(phase: DeliveryPhase.aborted, abortReason: '경로 막힘'),
    );
    await tester.pump();
    expect(find.textContaining('문자를 보내지 않았습니다'), findsOneWidget);

    await tester.tap(find.text('배송 완료 · 지우기'));
    await tester.pump();
    expect(supervisor.delivery, isNull);
  });

  testWidgets('도착하면 카운트다운과 지금 복귀·복귀 취소가 뜬다', (tester) async {
    final supervisor = await pump(tester, locations: [_office]);
    supervisor.setDeliveryForTest(
      DeliveryJob(destination: _office, startedAt: DateTime(2026)).copyWith(
        phase: DeliveryPhase.arrived,
        notified: true,
        returnAt: DateTime.now().add(const Duration(seconds: 90)),
      ),
    );
    await tester.pump();
    expect(find.textContaining('뒤 홈 복귀'), findsOneWidget);
    expect(find.text('지금 복귀'), findsOneWidget);
    expect(find.text('복귀 취소'), findsOneWidget);

    await tester.tap(find.text('복귀 취소'));
    await tester.pump();
    expect(supervisor.delivery?.returnAt, isNull);
    expect(find.text('홈이 없습니다'), findsOneWidget, reason: '시험엔 홈이 없어 복귀 버튼이 잠긴다');
    expect(find.text('지우기'), findsOneWidget);
  });

  testWidgets('완료된 배송은 지울 수 있다', (tester) async {
    final supervisor = await pump(tester, locations: [_office]);
    supervisor.setDeliveryForTest(
      DeliveryJob(destination: _office, startedAt: DateTime(2026))
          .copyWith(phase: DeliveryPhase.completed),
    );
    await tester.pump();
    expect(find.textContaining('완료 · 홈 도착'), findsOneWidget);
    await tester.tap(find.text('배송 완료 · 지우기'));
    await tester.pump();
    expect(supervisor.delivery, isNull);
  });
}
