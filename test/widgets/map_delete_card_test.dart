// 지도 삭제 UI 의 안전장치를 고정합니다.
//
// 카드는 장소 저장 화면 맨 아래에 있습니다. 위젯만 따로 띄워 규칙을 봅니다 —
// 자리를 옮겨도 이 시험은 그대로 유효해야 합니다.
//
// 지운 지도는 되돌릴 수 없습니다 — "지도 한 장은 사람이 로봇을 끌고 다닌 시간"
// (scripts/vica_map_save.sh). 그래서 "지워지는가"보다 "실수로 안 지워지는가"를 봅니다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vica_supervisor/providers/settings_provider.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';
import 'package:vica_supervisor/widgets/map_delete_card.dart';

class _FakeSupervisor extends SupervisorProvider {
  final calls = <String>[];

  void injectMaps() => handleMapListForTest({
        'maps': [
          {'map_id': 'lobby_0821', 'map_name': 'lobby_0821'},
          {'map_id': 'hall_0820', 'map_name': 'hall_0820'},
        ],
      });

  @override
  Future<String> deleteMap(
    settings,
    String mapId, {
    required bool deleteDestinations,
  }) async {
    calls.add('$mapId:$deleteDestinations');
    return '지웠습니다.';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<_FakeSupervisor> pump(WidgetTester tester,
      {bool withMaps = true}) async {
    final supervisor = _FakeSupervisor();
    if (withMaps) {
      supervisor.injectMaps();
    }
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 2600);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SupervisorProvider>.value(value: supervisor),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: MapDeleteCard())),
        ),
      ),
    );
    await tester.pump();
    return supervisor;
  }

  testWidgets('지도 목록이 비면 안내만 보여준다', (tester) async {
    await pump(tester, withMaps: false);
    expect(find.textContaining('지도 목록이 비어 있습니다'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '지도 삭제'), findsNothing);
  });

  testWidgets('지도를 고르기 전에는 삭제 버튼이 눌리지 않는다', (tester) async {
    await pump(tester);
    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '지도 삭제'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('되돌릴 수 없다는 것을 미리 알린다', (tester) async {
    await pump(tester);
    expect(find.textContaining('되돌릴 수 없습니다'), findsOneWidget);
    expect(find.textContaining('지금 쓰는 지도는 지울 수 없습니다'), findsOneWidget);
  });

  testWidgets('확인 창에서 그만두면 아무것도 안 지운다', (tester) async {
    final supervisor = await pump(tester);

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('lobby_0821').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, '지도 삭제'));
    await tester.pumpAndSettle();
    expect(find.text('지도를 지웁니다'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '그만두기'));
    await tester.pumpAndSettle();

    expect(supervisor.calls, isEmpty);
  });

  testWidgets('지우기를 눌러야 요청이 나간다', (tester) async {
    final supervisor = await pump(tester);

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('hall_0820').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, '지도 삭제'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '지우기'));
    await tester.pumpAndSettle();

    // 목적지 함께 삭제는 기본이 꺼져 있어야 한다 — 같은 이름으로 다시 그릴 때
    // 장소를 다시 찍는 일이 더 번거롭다.
    expect(supervisor.calls, ['hall_0820:false']);
  });

  testWidgets('장소도 함께 지우기를 켜면 그대로 전달된다', (tester) async {
    final supervisor = await pump(tester);

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('lobby_0821').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, '지도 삭제'));
    await tester.pumpAndSettle();
    expect(find.textContaining('장소도 함께 사라집니다'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '지우기'));
    await tester.pumpAndSettle();

    expect(supervisor.calls, ['lobby_0821:true']);
  });
}
