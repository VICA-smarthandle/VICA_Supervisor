// 장소 저장 화면의 "찍기 -> 확인 -> 입력" 흐름을 고정합니다.
//
// 종전에는 지도를 누르는 즉시 정보 입력 시트가 덮어서, 점이 원하는 자리에 찍혔는지
// 볼 수가 없었습니다. 시트를 닫으면 점까지 사라져 처음부터 다시 해야 했습니다.
// 이 테스트가 지키는 것은 "누르는 것과 입력을 시작하는 것이 다른 동작"이라는 점입니다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vica_supervisor/providers/settings_provider.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';
import 'package:vica_supervisor/screens/save_location_screen.dart';
import 'package:vica_supervisor/widgets/map_canvas.dart';

class _FakeSupervisor extends SupervisorProvider {
  void injectMaps(Map<String, Object?> message) =>
      handleMapListForTest(message);
}

Map<String, Object?> mapListMsg() {
  return {
    'maps': [
      {
        'map_id': 'vica_map_test',
        'map_name': '시험 지도',
        'image_url': '/maps/vica_map_test.png',
        'resolution': 0.05,
        'origin_x': -10.0,
        'origin_y': -10.0,
        'width': 400,
        'height': 300,
      },
    ],
  };
}

Widget wrap(SupervisorProvider supervisor) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<SupervisorProvider>.value(value: supervisor),
      ChangeNotifierProvider(create: (_) => SettingsProvider()),
    ],
    child: const MaterialApp(home: Scaffold(body: SaveLocationScreen())),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<_FakeSupervisor> pumpWithMap(WidgetTester tester) async {
    // 기본 800x600 에서는 카드와 시트 내용이 화면 밖으로 밀려 탭이 닿지 않습니다.
    // 표시 규칙만 보려는 테스트이므로 창을 넉넉히 키웁니다.
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 2400);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    final supervisor = _FakeSupervisor()..injectMaps(mapListMsg());
    await tester.pumpWidget(wrap(supervisor));
    await tester.pump();
    return supervisor;
  }

  testWidgets('지도를 누르면 시트가 뜨지 않고 좌표만 잡힌다', (tester) async {
    await pumpWithMap(tester);

    expect(find.text('장소 정보 입력'), findsOneWidget);
    expect(find.textContaining('지도를 눌러'), findsOneWidget);

    // MapCanvas 가 좌표를 돌려주는 지점을 직접 부릅니다. 실제 탭은 지도 이미지
    // 로드에 묶여 있어 테스트 환경에서 재현이 어렵습니다.
    tester.widget<MapCanvas>(find.byType(MapCanvas)).onTapMap!(
      const Offset(1.5, -2.25),
    );
    await tester.pump();

    // 시트는 뜨지 않아야 합니다. 이것이 이 변경의 핵심입니다.
    expect(find.byType(BottomSheet), findsNothing);
    // 대신 찍힌 좌표가 글자로 보여 원하는 자리인지 확인할 수 있어야 합니다.
    expect(find.textContaining('1.50'), findsOneWidget);
    expect(find.textContaining('-2.25'), findsOneWidget);
  });

  testWidgets('다시 누르면 좌표만 옮겨간다', (tester) async {
    await pumpWithMap(tester);
    final canvas = tester.widget<MapCanvas>(find.byType(MapCanvas));

    canvas.onTapMap!(const Offset(1.5, -2.25));
    await tester.pump();
    canvas.onTapMap!(const Offset(4.0, 5.0));
    await tester.pump();

    expect(find.textContaining('1.50'), findsNothing);
    expect(find.textContaining('4.00'), findsOneWidget);
    expect(find.textContaining('5.00'), findsOneWidget);
  });

  testWidgets('좌표가 없으면 정보 입력 버튼을 누를 수 없다', (tester) async {
    await pumpWithMap(tester);

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '장소 정보 입력'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('정보 입력 버튼을 눌러야 시트가 열린다', (tester) async {
    await pumpWithMap(tester);

    tester.widget<MapCanvas>(find.byType(MapCanvas)).onTapMap!(
      const Offset(1.5, -2.25),
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, '장소 정보 입력'));
    await tester.pumpAndSettle();

    expect(find.text('도착 방향'), findsOneWidget);
  });

  testWidgets('도착 방향은 정면·후면으로 보여준다', (tester) async {
    await pumpWithMap(tester);

    tester.widget<MapCanvas>(find.byType(MapCanvas)).onTapMap!(
      const Offset(1.5, -2.25),
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '장소 정보 입력'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();

    expect(find.textContaining('정면'), findsWidgets);
    expect(find.textContaining('후면'), findsWidgets);
    expect(find.textContaining('앞 ('), findsNothing);
    expect(find.textContaining('뒤 ('), findsNothing);
  });

  testWidgets('선택 취소를 누르면 찍은 좌표가 사라진다', (tester) async {
    await pumpWithMap(tester);

    tester.widget<MapCanvas>(find.byType(MapCanvas)).onTapMap!(
      const Offset(1.5, -2.25),
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(OutlinedButton, '선택 취소'));
    await tester.pump();

    expect(find.textContaining('1.50'), findsNothing);
    expect(find.textContaining('지도를 눌러'), findsOneWidget);
  });
}
