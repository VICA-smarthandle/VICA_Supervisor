import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vica_supervisor/providers/settings_provider.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';
import 'package:vica_supervisor/widgets/map_delete_card.dart';
import 'package:vica_supervisor/widgets/vica_ui.dart';

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

  @override
  Future<String> renameMap(settings, String mapId, String displayName) async {
    calls.add('rename:$mapId:$displayName');
    return '바꿨습니다.';
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

  testWidgets('체크박스를 켜지 않으면 지도를 골라도 눌리지 않는다', (tester) async {
    await pump(tester);

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('lobby_0821').last);
    await tester.pumpAndSettle();

    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '지도 삭제'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('되돌릴 수 없다는 것을 미리 알린다', (tester) async {
    await pump(tester);
    expect(
      find.textContaining(vicaKeepWords('되돌릴 수 없습니다')),
      findsOneWidget,
    );
    expect(
      find.textContaining(vicaKeepWords('현재 주행하는 지도는 삭제할 수 없습니다')),
      findsOneWidget,
    );
  });

  testWidgets('확인 창에서 그만두면 아무것도 안 지운다', (tester) async {
    final supervisor = await pump(tester);

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('lobby_0821').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, '지도 삭제'));
    await tester.pumpAndSettle();
    expect(find.text('지도를 삭제합니다'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, '취소'));
    await tester.pumpAndSettle();

    expect(supervisor.calls, isEmpty);
  });

  testWidgets('지우기를 눌러야 요청이 나간다', (tester) async {
    final supervisor = await pump(tester);

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('hall_0820').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, '지도 삭제'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '삭제'));
    await tester.pumpAndSettle();

    expect(supervisor.calls, ['hall_0820:true']);
  });

  testWidgets('확인 창이 장소도 함께 사라진다고 알린다', (tester) async {
    final supervisor = await pump(tester);

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('lobby_0821').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, '지도 삭제'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining(vicaKeepWords('저장한 장소를 삭제합니다')),
      findsOneWidget,
    );
    expect(find.textContaining(vicaKeepWords('되돌릴 수 없습니다')), findsWidgets);
    await tester.tap(find.widgetWithText(FilledButton, '삭제'));
    await tester.pumpAndSettle();

    expect(supervisor.calls, ['lobby_0821:true']);
  });

  testWidgets('지도를 고르면 지금 이름이 채워지고 그대로면 바꾸기 버튼이 닫혀 있다', (tester) async {
    await pump(tester);

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('hall_0820').last);
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'hall_0820');
    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '이름 바꾸기'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('이름을 고치고 누르면 표시 이름만 바꾸는 요청이 나간다', (tester) async {
    final supervisor = await pump(tester);

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('hall_0820').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '병원 2층');
    await tester.pump();

    await tester.tap(find.widgetWithText(OutlinedButton, '이름 바꾸기'));
    await tester.pumpAndSettle();

    expect(supervisor.calls, ['rename:hall_0820:병원 2층']);
  });
}
