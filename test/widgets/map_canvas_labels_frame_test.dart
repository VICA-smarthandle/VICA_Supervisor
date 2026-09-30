// 2026-09-30 사용자 요청 두 가지를 고정합니다.
//
//   1. 초기 위치를 찍는 동안(showLocationLabels false)은 장소 점에 이름표가 없다.
//   2. 지도 판(ResponsiveMapFrame)은 흰 바탕 + 얇은 테두리로 지도 범위를 보인다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/core/app_settings.dart';
import 'package:vica_supervisor/models/location_point.dart';
import 'package:vica_supervisor/models/vica_map.dart';
import 'package:vica_supervisor/widgets/map_canvas.dart';
import 'package:vica_supervisor/widgets/vica_ui.dart';

const _map = VicaMap(
  mapId: 'm',
  mapName: '시험 지도',
  imageUrl: '/maps/m.png',
  resolution: 0.05,
  originX: -10,
  originY: -10,
  width: 400,
  height: 300,
);

const _reception = LocationPoint(
  locationId: 'loc-1',
  mapId: 'm',
  name: '안내소',
  x: 1,
  y: 2,
  yaw: 0,
);

Future<void> pumpCanvas(WidgetTester tester, {required bool labels}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 400,
          child: MapCanvas(
            map: _map,
            settings: const AppSettings(),
            locations: const [_reception],
            showLocationLabels: labels,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('평소에는 장소 점에 이름표가 붙는다', (tester) async {
    await pumpCanvas(tester, labels: true);
    expect(find.byTooltip('안내소'), findsOneWidget);
  });

  testWidgets('초기 위치를 찍는 동안은 장소 이름표가 없다', (tester) async {
    await pumpCanvas(tester, labels: false);
    expect(find.byTooltip('안내소'), findsNothing);
  });

  testWidgets('지도 판은 흰 바탕과 얇은 테두리를 가진다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ResponsiveMapFrame(map: _map, child: SizedBox.expand()),
        ),
      ),
    );
    final box = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(ResponsiveMapFrame),
            matching: find.byType(Container),
          )
          .first,
    );
    final deco = box.decoration! as BoxDecoration;
    expect(deco.color, VicaColors.card);
    expect(deco.border, Border.all(color: VicaColors.border));
  });
}
