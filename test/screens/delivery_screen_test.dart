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
import 'package:vica_supervisor/core/app_settings.dart';
import 'package:vica_supervisor/models/delivery_job.dart';
import 'package:vica_supervisor/models/location_point.dart';
import 'package:vica_supervisor/providers/settings_provider.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';
import 'package:vica_supervisor/screens/delivery_screen.dart';
import 'package:vica_supervisor/widgets/vica_ui.dart';

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

  final saved = <LocationPoint>[];
  final started = <(String, String, String)>[];

  @override
  (bool, String) saveLocation(AppSettings settings, LocationPoint location) {
    saved.add(location);
    return (true, '${location.name} 수정을 저장했습니다.');
  }

  /// 연결 없이 출발이 받아들여진 것처럼 둡니다(연락처 저장 체크 시험용).
  bool acceptStart = false;

  @override
  Future<String> startDelivery(
    AppSettings settings,
    LocationPoint location, {
    String note = '',
    String phone = '',
  }) async {
    if (!acceptStart) {
      return super.startDelivery(settings, location, note: note, phone: phone);
    }
    started.add((location.name, note, phone));
    setDeliveryForTest(DeliveryJob(destination: location, startedAt: DateTime(2026), note: note));
    return '${location.name}(으)로 배송을 시작합니다.';
  }
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

  // 2026-11-17 사용자 지시: 장소 칩 버튼을 지우고 '배송 받을 곳'·'연락처'·'메시지' 세 칸(B안: 모든 장소).
  // 배송 받을 곳은 검색 드롭다운(DropdownMenu, 목업 ⑧). 누르면 목록, 항목을 누르면 고름.
  Future<void> pickPlace(WidgetTester tester, String name) async {
    await tester.tap(find.byType(DropdownMenu<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, name).last);
    await tester.pumpAndSettle();
  }

  Finder phoneField() => find.widgetWithText(TextField, '연락처');
  Finder noteField() => find.widgetWithText(TextField, '메시지 (선택)');

  testWidgets('번호 없는 장소도 고를 수 있고, 연락처를 써야 출발이 열린다', (tester) async {
    const lobby = LocationPoint(
      locationId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
      mapId: 'starlight_1f',
      name: '로비',
      x: 0,
      y: 0,
      yaw: 0,
    );
    await pump(tester, locations: [lobby]);
    await pickPlace(tester, '로비');
    await tester.tap(find.text('물건을 실었습니다'));
    await tester.pump();
    expect(startButton(tester).onPressed, isNull, reason: '연락처 없음');
    expect(find.text('저장된 번호 없음 · 써 주세요(이번 배송만)'), findsOneWidget);
    await tester.enterText(phoneField(), '010-12');
    await tester.pump();
    expect(find.text('휴대폰 번호 모양이 아님'), findsOneWidget);
    expect(startButton(tester).onPressed, isNull);
    await tester.enterText(phoneField(), '010-9876-5432');
    await tester.pump();
    expect(find.text('직접 입력 · 이번 배송만 씀'), findsOneWidget);
    expect(startButton(tester).onPressed, isNotNull);
  });

  testWidgets('장소를 고르기 전에는 번호가 보이지 않고, 고르면 저장된 번호가 연락처 칸에 채워진다', (tester) async {
    await pump(tester, locations: [_office]);
    // 연락처 관리 카드는 가린 번호만 보인다. 전체 번호는 고른 뒤 편집 칸에만.
    expect(find.text('010-1234-5678'), findsNothing);
    await pickPlace(tester, '305호');
    expect(find.text('010-1234-5678'), findsOneWidget, reason: '편집 칸이라 전체를 보인다');
    expect(find.text('저장된 번호 · 바꾸면 이번 배송만'), findsOneWidget);
  });

  testWidgets('장소를 고르고 적재를 확인해야 출발이 열린다', (tester) async {
    await pump(tester, locations: [_office]);
    expect(startButton(tester).onPressed, isNull);
    await pickPlace(tester, '305호');
    expect(startButton(tester).onPressed, isNull, reason: '적재 확인 전');
    await tester.tap(find.text('물건을 실었습니다'));
    await tester.pump();
    expect(startButton(tester).onPressed, isNotNull);
  });

  testWidgets('메시지를 쓰면 도착 문자 미리보기가 바뀐다', (tester) async {
    await pump(tester, locations: [_office]);
    await pickPlace(tester, '305호');
    expect(find.text(vicaKeepWords(deliveryArrivalMessage('305호'))), findsOneWidget,
        reason: '메시지가 없으면 예전 문구');
    await tester.enterText(noteField(), '서류 두 장');
    await tester.pump();
    expect(find.text('6/31'), findsOneWidget, reason: '305호면 45 - "[305호] 비카 도착: " = 31');
    expect(find.text(vicaKeepWords('[305호] 비카 도착: 서류 두 장')), findsOneWidget);
  });

  testWidgets('출발 확인 창 — 저장된 번호는 가리고, 바꾼 번호는 전체와 직접 입력', (tester) async {
    await pump(tester, locations: [_office]);
    await pickPlace(tester, '305호');
    await tester.enterText(noteField(), 'ㄱ' * 50);
    await tester.pump();
    expect(find.text('31/31'), findsOneWidget, reason: '한도를 넘겨 쓸 수 없다');
    await tester.tap(find.text('물건을 실었습니다'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '배송 출발'));
    await tester.pumpAndSettle();
    expect(find.text('305호(으)로 배송 출발'), findsOneWidget);
    // 창 뒤 연락처 관리 카드에도 같은 가린 번호가 있다 — 창 안에서만 찾는다.
    expect(find.descendant(of: find.byType(Dialog), matching: find.text('010-****-5678')), findsOneWidget);
    expect(find.text('ㄱ' * 31), findsWidgets);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    await tester.enterText(phoneField(), '01098765432');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '배송 출발'));
    await tester.pumpAndSettle();
    expect(find.text('010-9876-5432 · 직접 입력'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
  });

  testWidgets('검색 드롭다운 — 글자를 치면 목록이 걸러진다', (tester) async {
    const room409 = LocationPoint(
      locationId: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
      mapId: 'starlight_1f',
      name: '409호',
      x: 3,
      y: 3,
      yaw: 0,
    );
    await pump(tester, locations: [_office, room409]);
    await tester.tap(find.byType(DropdownMenu<String>));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(MenuItemButton, '305호'), findsWidgets);
    expect(find.widgetWithText(MenuItemButton, '409호'), findsWidgets);
    await tester.enterText(find.widgetWithText(TextField, '배송 장소'), '40');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(MenuItemButton, '305호'), findsNothing);
    expect(find.widgetWithText(MenuItemButton, '409호'), findsWidgets);
  });

  testWidgets('연락처 관리 — 가린 번호·없음, 눌러서 저장·지우기(목업 ⑥⑦)', (tester) async {
    const lobby = LocationPoint(
      locationId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
      mapId: 'starlight_1f',
      name: '로비',
      x: 0,
      y: 0,
      yaw: 0,
    );
    final supervisor = await pump(tester, locations: [_office, lobby]);
    expect(find.text('연락처 관리'), findsOneWidget);
    expect(find.text('010-****-5678'), findsOneWidget);
    expect(find.text('없음'), findsOneWidget);

    await tester.ensureVisible(find.text('없음'));
    await tester.tap(find.text('없음'));
    await tester.pumpAndSettle();
    expect(find.text('로비 연락처'), findsOneWidget);
    expect(find.text('지우기'), findsNothing, reason: '저장된 번호가 없으면 지울 것도 없다');
    await tester.enterText(find.descendant(of: find.byType(Dialog), matching: find.byType(TextField)), '010-2222-3333');
    await tester.pump();
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(supervisor.saved.single.name, '로비');
    expect(supervisor.saved.single.contactPhone, '01022223333');

    await tester.ensureVisible(find.text('010-****-5678'));
    await tester.tap(find.text('010-****-5678'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('지우기'));
    await tester.pumpAndSettle();
    expect(supervisor.saved.last.name, '305호');
    expect(supervisor.saved.last.contactPhone, '');
  });

  testWidgets('직접 쓴 번호는 체크하면 출발 뒤 그 장소 연락처로 저장된다', (tester) async {
    final supervisor = await pump(tester, locations: [_office]);
    supervisor.acceptStart = true;
    await pickPlace(tester, '305호');
    expect(find.text('이 장소 연락처로 저장'), findsNothing, reason: '저장된 번호 그대로면 체크가 없다');
    await tester.enterText(phoneField(), '010-9876-5432');
    await tester.pump();
    expect(find.text('이 장소 연락처로 저장'), findsOneWidget);
    await tester.tap(find.text('이 장소 연락처로 저장'));
    await tester.tap(find.text('물건을 실었습니다'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '배송 출발'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '출발'));
    await tester.pumpAndSettle();
    expect(supervisor.started.single.$3, '01098765432');
    expect(supervisor.saved.single.contactPhone, '01098765432');
  });

  testWidgets('체크하지 않으면 직접 쓴 번호는 이번 배송에만 쓴다', (tester) async {
    final supervisor = await pump(tester, locations: [_office]);
    supervisor.acceptStart = true;
    await pickPlace(tester, '305호');
    await tester.enterText(phoneField(), '010-9876-5432');
    await tester.tap(find.text('물건을 실었습니다'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '배송 출발'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '출발'));
    await tester.pumpAndSettle();
    expect(supervisor.started.single.$3, '01098765432');
    expect(supervisor.saved, isEmpty);
  });

  testWidgets('배송 중 카드에 남긴 메시지가 보인다', (tester) async {
    final supervisor = await pump(tester, locations: [_office]);
    supervisor.setDeliveryForTest(
      DeliveryJob(destination: _office, startedAt: DateTime(2026), note: '서류 두 장입니다'),
    );
    await tester.pump();
    expect(find.text(vicaKeepWords('메시지 · 서류 두 장입니다')), findsOneWidget);
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
    expect(find.textContaining(vicaKeepWords('문자를 보내지 않았습니다')), findsOneWidget);

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
    expect(find.text('홈이 없습니다'), findsOneWidget,
        reason: '시험엔 홈이 없어 복귀 버튼이 잠긴다');
    expect(find.text('지우기'), findsOneWidget);
  });

  testWidgets('완료된 배송은 지울 수 있다', (tester) async {
    final supervisor = await pump(tester, locations: [_office]);
    supervisor.setDeliveryForTest(
      DeliveryJob(destination: _office, startedAt: DateTime(2026))
          .copyWith(phase: DeliveryPhase.completed),
    );
    await tester.pump();
    expect(find.text('완료'), findsOneWidget);
    await tester.tap(find.text('배송 완료 · 지우기'));
    await tester.pump();
    expect(supervisor.delivery, isNull);
  });
}
