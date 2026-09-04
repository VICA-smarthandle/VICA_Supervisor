// 지도 위 점을 폰에서 2/3 로 줄여도 저장 장소를 손가락으로 고를 수 있는지
// 고정합니다(2026-09-04). 점은 작게 그리되 눌리는 판(16 px)은 넓게 둡니다.
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

    // 점 지름(폰 3.3 px) 밖이지만 판(16 px) 안이다.
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
}
