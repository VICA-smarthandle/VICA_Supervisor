// 지도 설정 화면 '장소 저장' 칸의 "찍기 -> 확인 -> 입력" 흐름을 고정합니다.
//
// 종전에는 지도를 누르는 즉시 정보 입력 시트가 덮어서, 점이 원하는 자리에 찍혔는지
// 볼 수가 없었습니다. 시트를 닫으면 점까지 사라져 처음부터 다시 해야 했습니다.
// 이 테스트가 지키는 것은 "누르는 것과 입력을 시작하는 것이 다른 동작"이라는 점입니다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vica_supervisor/models/location_point.dart';
import 'package:vica_supervisor/providers/settings_provider.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';
import 'package:vica_supervisor/screens/save_location_screen.dart';
import 'package:vica_supervisor/widgets/vica_ui.dart';
import 'package:vica_supervisor/widgets/map_canvas.dart';
import 'package:vica_supervisor/widgets/rail_card.dart';

class _FakeSupervisor extends SupervisorProvider {
  void injectMaps(Map<String, Object?> message) =>
      handleMapListForTest(message);

  void injectLocations(List<LocationPoint> locations) =>
      handleLocationListForTest({
        'map_id': 'vica_map_test',
        'locations': locations.map((e) => e.toJson()).toList(),
      });
}

const _savedRestroom = LocationPoint(
  locationId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  mapId: 'vica_map_test',
  name: '화장실',
  x: 1,
  y: 2,
  yaw: 90,
  category1: 'facility',
  category2: 'restroom',
  building: '로봇관',
  floor: 4,
  confirmPrompt: '화장실로 안내해드릴까요?',
  arrivalMessage: '화장실 앞에 도착했습니다.',
  doorYaw: 270,
);

// 대기 장소가 딸린 목적지(2026-10-07).
const _withWait = LocationPoint(
  locationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  mapId: 'vica_map_test',
  name: '407호',
  x: 3,
  y: 2,
  yaw: 270,
  category1: 'facility',
  category2: 'restroom',
  building: '로봇관',
  floor: 4,
  doorYaw: 270,
  waitSpot: WaitSpot(x: 1.5, y: 2, yaw: 0, side: 'right'),
);

// 입구 방향이 없는 옛 목적지.
const _oldNoDoor = LocationPoint(
  locationId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
  mapId: 'vica_map_test',
  name: '세미나실',
  x: 5,
  y: 5,
  yaw: 0,
);

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
    // 칸은 모두 접힌 채로 시작하므로(2026-09-30) 장소 저장 칸을 눌러 엽니다.
    await tester.tap(find.text('장소 저장'));
    await tester.pump();
    return supervisor;
  }

  // 버튼 문구는 어절 단위 줄바꿈(vicaKeepWords)을 거치므로 같은 변환으로 찾습니다.
  final enterInfo = vicaKeepWords('장소 정보 입력');
  final editSaved = vicaKeepWords('선택 장소 수정');
  final deleteSaved = vicaKeepWords('선택 장소 삭제');

  testWidgets('처음 들어가면 어느 칸도 펼쳐져 있지 않다', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 2400);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final supervisor = _FakeSupervisor()..injectMaps(mapListMsg());
    await tester.pumpWidget(wrap(supervisor));
    await tester.pump();

    // 장소 저장 칸의 내용(찍기 안내)이 보이지 않아야 합니다.
    expect(find.text('장소 저장'), findsOneWidget);
    expect(find.textContaining(vicaKeepWords('지도를 눌러')), findsNothing);

    // 눌러야 열립니다 — 다른 칸과 같습니다.
    await tester.tap(find.text('장소 저장'));
    await tester.pump();
    expect(find.textContaining(vicaKeepWords('지도를 눌러')), findsOneWidget);
  });

  testWidgets('수정·삭제 버튼 문구는 어절 단위로만 줄이 바뀐다', (tester) async {
    final supervisor = await pumpWithMap(tester);
    supervisor.injectLocations([_savedRestroom]);
    await tester.pump();

    expect(find.text(editSaved), findsOneWidget);
    expect(find.text(deleteSaved), findsOneWidget);
  });

  testWidgets('지도를 누르면 시트가 뜨지 않고 좌표만 잡힌다', (tester) async {
    await pumpWithMap(tester);

    expect(find.textContaining(vicaKeepWords('지도를 눌러')), findsOneWidget);

    // MapCanvas 가 좌표를 돌려주는 지점을 직접 부릅니다. 실제 탭은 지도 이미지
    // 로드에 묶여 있어 테스트 환경에서 재현이 어렵습니다.
    tester.widget<MapCanvas>(find.byType(MapCanvas)).onTapMap!(
      const Offset(1.5, -2.25),
    );
    await tester.pump();

    // 시트는 뜨지 않아야 합니다. 이것이 이 변경의 핵심입니다.
    expect(find.byType(BottomSheet), findsNothing);
    // 대신 찍힌 좌표가 글자로 보여 원하는 자리인지 확인할 수 있어야 합니다.
    // 음수는 목업처럼 긴 빼기표(−)로 씁니다.
    expect(find.textContaining('1.50'), findsOneWidget);
    expect(find.textContaining('−2.25'), findsOneWidget);
    // 찍은 뒤에는 위치 옮기기·입구 방향 단계가 보입니다(목업 1).
    expect(find.text('위치 옮기기'), findsOneWidget);
    expect(find.text('↓ 아래'), findsOneWidget);
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

  testWidgets('입구 방향을 고르기 전에는 정보 입력 버튼을 누를 수 없다', (tester) async {
    await pumpWithMap(tester);
    tester.widget<MapCanvas>(find.byType(MapCanvas)).onTapMap!(
      const Offset(1.5, -2.25),
    );
    await tester.pump();

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, enterInfo),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('입구 방향을 고르고 정보 입력을 눌러야 시트가 열린다', (tester) async {
    await pumpWithMap(tester);

    tester.widget<MapCanvas>(find.byType(MapCanvas)).onTapMap!(
      const Offset(1.5, -2.25),
    );
    await tester.pump();
    await tester.tap(find.text('↓ 아래'));
    await tester.pump();
    // 지도에 입구 화살표가 그려집니다.
    expect(
        tester.widget<MapCanvas>(find.byType(MapCanvas)).doorArrow, isNotNull);

    await tester.tap(find.widgetWithText(FilledButton, enterInfo));
    await tester.pumpAndSettle();

    // 옛 '도착 방향' 드롭다운 대신 입구 방향 줄과 '바꾸기'(목업 2).
    expect(find.text('도착 방향'), findsNothing);
    expect(find.text(vicaKeepWords('입구 방향 (앱의 지도 그림 기준)')), findsOneWidget);
    // 시트 안의 값과 시트 뒤 지도 칸의 칩, 둘입니다.
    expect(find.text('↓ 아래'), findsNWidgets(2));
    expect(find.text('임시 저장'), findsOneWidget);
  });

  testWidgets('바꾸기를 누르면 시트가 닫히고 입구 방향 칸이 강조된다(목업 2′)', (tester) async {
    await pumpWithMap(tester);
    tester.widget<MapCanvas>(find.byType(MapCanvas)).onTapMap!(
      const Offset(1.5, -2.25),
    );
    await tester.pump();
    await tester.tap(find.text('↓ 아래'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, enterInfo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('바꾸기'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(
      find.text(vicaKeepWords('방향을 선택 후 장소 정보 입력을 누르세요. 입력하신 정보는 남아있습니다.')),
      findsOneWidget,
    );
  });

  testWidgets('위치 옮기기는 한 번에 5 cm 옮긴다(목업 1′)', (tester) async {
    await pumpWithMap(tester);
    tester.widget<MapCanvas>(find.byType(MapCanvas)).onTapMap!(
      const Offset(1.5, -2.25),
    );
    await tester.pump();
    await tester.tap(find.text('위치 옮기기'));
    await tester.pump();
    await tester.tap(find.text('→'));
    await tester.pump();

    expect(find.textContaining('1.55'), findsOneWidget);
    await tester.tap(find.text('완료'));
    await tester.pump();
    expect(find.text('위치 옮기기'), findsOneWidget);
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
    expect(find.textContaining(vicaKeepWords('지도를 눌러')), findsOneWidget);
  });

  // ---- 저장된 장소 수정 (2026-09-03) ----------------------------------------

  testWidgets('선택 장소 수정은 지도부터 — 위치·입구 방향 뒤 원본이 채워진 시트(목업 15~17)',
      (tester) async {
    final supervisor = await pumpWithMap(tester);
    supervisor.injectLocations([_savedRestroom]);
    await tester.pump();

    // 저장된 장소가 하나뿐이라 드롭다운 기본 선택이 그것이다.
    final edit = find.widgetWithText(OutlinedButton, editSaved);
    expect(edit, findsOneWidget);
    await tester.tap(edit);
    await tester.pumpAndSettle();

    // 시트가 바로 열리지 않고 지도에서 고치는 단계가 보입니다.
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('수정 중'), findsOneWidget);
    // 원래 자리가 회색 점선 원으로 남습니다.
    expect(
        tester.widget<MapCanvas>(find.byType(MapCanvas)).ghostPoint, isNotNull);

    await tester
        .tap(find.widgetWithText(FilledButton, vicaKeepWords('수정 내용 입력')));
    await tester.pumpAndSettle();

    expect(find.text('장소 정보 수정'), findsOneWidget);
    expect(find.text('ROS2에 수정 저장'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '화장실'), findsOneWidget);
    expect(find.text('임시 저장'), findsNothing);
  });

  testWidgets('저장된 장소가 없으면 수정·삭제 버튼이 없다', (tester) async {
    await pumpWithMap(tester);
    expect(find.widgetWithText(OutlinedButton, editSaved), findsNothing);
    expect(find.text('저장된 장소 0개'), findsOneWidget);
  });

  // ---- 대기 장소 (2026-10-07) -----------------------------------------------

  testWidgets('목록 머리에 대기 장소 수를 따로 센다(목업 5)', (tester) async {
    final supervisor = await pumpWithMap(tester);
    supervisor.injectLocations([_savedRestroom, _withWait]);
    await tester.pump();

    expect(find.text('저장된 장소 2개'), findsOneWidget);
    expect(find.text('대기 장소 1개'), findsOneWidget);
    // 지도에는 대기 장소 하나가 점선으로 이어져 그려집니다.
    expect(tester.widget<MapCanvas>(find.byType(MapCanvas)).waitSpots,
        hasLength(1));
  });

  testWidgets('대기 장소 없는 목적지에 추가 버튼, 입구 방향이 없으면 잠김', (tester) async {
    final supervisor = await pumpWithMap(tester);
    supervisor.injectLocations([_oldNoDoor]);
    await tester.pump();

    final add = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, vicaKeepWords('세미나실에 대기 장소 추가')));
    expect(add.onPressed, isNull);
  });

  testWidgets('대기 장소 찍기 — 입구 앞은 저장할 수 없다', (tester) async {
    final supervisor = await pumpWithMap(tester);
    supervisor.injectLocations([_savedRestroom]);
    await tester.pump();

    await tester.tap(
        find.widgetWithText(OutlinedButton, vicaKeepWords('화장실에 대기 장소 추가')));
    await tester.pump();
    expect(find.text('대기 장소 · 화장실'), findsOneWidget);

    // 목적지 (1,2), 입구는 아래(270°). 바로 아래 0.8 m = 입구 앞.
    tester.widget<MapCanvas>(find.byType(MapCanvas)).onTapMap!(
      const Offset(1.0, 1.2),
    );
    await tester.pump();
    await tester.tap(find.text('→ 오른쪽'));
    await tester.pump();

    expect(find.text(vicaKeepWords('입구 앞')), findsOneWidget);
    final save = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, vicaKeepWords('대기 장소 저장')));
    expect(save.onPressed, isNull);
  });

  testWidgets('목적지를 지우면 대기 장소도 함께 지워진다고 먼저 묻는다(목업 7)', (tester) async {
    final supervisor = await pumpWithMap(tester);
    supervisor.injectLocations([_withWait]);
    await tester.pump();

    await tester.tap(find.widgetWithText(OutlinedButton, deleteSaved));
    await tester.pumpAndSettle();

    expect(find.text('407호를 지울까요?'), findsOneWidget);
    expect(find.text('둘 다 지우기'), findsOneWidget);
    expect(find.text('407호-대기'), findsOneWidget);
  });

  testWidgets('레일 칸은 금지구역 다음·지도 관리 위에, 접힌 채로 있다(2026-09-30 확정)',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 2400);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final supervisor = _FakeSupervisor()..injectMaps(mapListMsg());
    await tester.pumpWidget(wrap(supervisor));
    await tester.pump();
    final keepout = tester.getTopLeft(find.text('금지구역')).dy;
    final rail = tester.getTopLeft(find.text('레일')).dy;
    final manage = tester.getTopLeft(find.text('지도 관리')).dy;
    expect(keepout < rail && rail < manage, isTrue);
    expect(find.byType(RailCard), findsNothing, reason: '접힌 채 시작');

    await tester.tap(find.text('레일'));
    await tester.pump();
    expect(find.byType(RailCard), findsOneWidget);
  });
}
