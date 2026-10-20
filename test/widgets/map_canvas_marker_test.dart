import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/core/app_settings.dart';
import 'package:vica_supervisor/models/location_point.dart';
import 'package:vica_supervisor/models/vica_map.dart';
import 'package:vica_supervisor/widgets/map_canvas.dart';

void main() {
  const map = VicaMap(
    mapId: 'm',
    mapName: 'm',
    imageUrl: '/maps/m.png',
    resolution: 0.05,
    originX: 0,
    originY: 0,
    width: 200,
    height: 200,
  );
  const reception = LocationPoint(
    locationId: 'l1',
    mapId: 'm',
    name: '접수',
    x: 5.0,
    y: 5.0,
    yaw: 0,
  );

  Future<List<String>> pump(WidgetTester tester) async {
    final selected = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 400,
            child: MapCanvas(
              map: map,
              settings: const AppSettings(),
              locations: const [reception],
              onSelectLocation: (location) => selected.add(location.name),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return selected;
  }

  testWidgets('점 옆 손가락 판을 눌러도 장소가 골라진다', (tester) async {
    final selected = await pump(tester);
    final centre = tester.getCenter(find.byTooltip('접수'));

    await tester.tapAt(centre + const Offset(6, 0));
    await tester.pump();

    expect(selected, ['접수']);
  });

  testWidgets('판 밖을 누르면 장소가 골라지지 않는다', (tester) async {
    final selected = await pump(tester);
    final centre = tester.getCenter(find.byTooltip('접수'));

    await tester.tapAt(centre + const Offset(12, 0));
    await tester.pump();

    expect(selected, isEmpty);
  });

  testWidgets('다른 지도의 임시 저장 장소는 그리지 않는다', (tester) async {
    Future<void> pumpDraft(String draftMapId) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: MapCanvas(
                map: map,
                settings: const AppSettings(),
                locations: const [],
                draftLocation: LocationPoint(
                  locationId: 'd1',
                  mapId: draftMapId,
                  name: '새 장소',
                  x: 5.0,
                  y: 5.0,
                  yaw: 0,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    await pumpDraft('m');
    expect(find.byTooltip('임시 저장'), findsOneWidget);

    await pumpDraft('other_map');
    expect(find.byTooltip('임시 저장'), findsNothing);
  });

  testWidgets('지도 그림은 주소가 바뀌어도 옛 그림을 둔다', (tester) async {
    await pump(tester);
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.gaplessPlayback, isTrue);
  });

  testWidgets('다른 지도로 바꾸면 옛 지도 그림을 남기지 않는다', (tester) async {
    Future<State> pumpMap(VicaMap shown) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: MapCanvas(
                map: shown,
                settings: const AppSettings(),
                locations: const [],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return tester.state(find.byType(Image));
    }

    const other = VicaMap(
      mapId: 'other',
      mapName: 'other',
      imageUrl: '/maps/other.png',
      resolution: 0.05,
      originX: 0,
      originY: 0,
      width: 200,
      height: 200,
    );
    final first = await pumpMap(map);
    final sameMapAgain = await pumpMap(map);
    final switched = await pumpMap(other);
    expect(identical(first, sameMapAgain), isTrue, reason: '같은 지도는 그림을 이어 쓴다');
    expect(identical(first, switched), isFalse, reason: '다른 지도는 새로 그린다');
  });
}
