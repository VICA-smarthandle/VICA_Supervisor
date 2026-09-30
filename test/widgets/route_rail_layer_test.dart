// 지도 위 레일 층이 확정된 모양(2026-09-30 사용자 결정)대로 그려지는지 고정합니다.
//
//   선      앱 기본색, 1.0 px
//   역 점   끝·갈림길 역에만, 지름 2.2 px
//   층 순서 금지구역 위, 장소 점 아래. 터치는 받지 않는다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/core/app_settings.dart';
import 'package:vica_supervisor/models/location_point.dart';
import 'package:vica_supervisor/models/route_graph.dart';
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

// 1-2-3 등뼈 + 2-4 곁가지.
const _graph = RouteGraph(
  nodes: {
    1: Offset(0, 0),
    2: Offset(1, 0),
    3: Offset(2, 0),
    4: Offset(1, -1),
  },
  edges: [RouteEdge(1, 2), RouteEdge(2, 3), RouteEdge(2, 4)],
);

Future<void> pumpCanvas(WidgetTester tester, {RouteGraph? graph}) async {
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
            routeGraph: graph,
            onSelectLocation: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

RouteRailPainter? railPainter(WidgetTester tester) {
  for (final paint in tester.widgetList<CustomPaint>(find.byType(CustomPaint))) {
    if (paint.painter is RouteRailPainter) {
      return paint.painter as RouteRailPainter;
    }
  }
  return null;
}

void main() {
  testWidgets('레일이 있으면 선분과 끝·갈림길 역 점을 그린다', (tester) async {
    await pumpCanvas(tester, graph: _graph);

    final painter = railPainter(tester)!;
    // 엣지 3개 → 점 6개(시작·끝 짝).
    expect(painter.segments, hasLength(6));
    // 역 1·3·4 는 끝, 2 는 갈림길. 넷 다 점을 찍는다.
    expect(painter.keyPoints, hasLength(4));
  });

  testWidgets('레일이 없으면 층 자체를 만들지 않는다', (tester) async {
    await pumpCanvas(tester);
    expect(railPainter(tester), isNull);

    await pumpCanvas(
      tester,
      graph: const RouteGraph(nodes: {}, edges: []),
    );
    expect(railPainter(tester), isNull);
  });

  testWidgets('레일 층은 터치를 받지 않아 장소 점을 여전히 누를 수 있다', (tester) async {
    final selected = <String>[];
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
              routeGraph: _graph,
              onSelectLocation: (location) => selected.add(location.name),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('안내소'));
    await tester.pump();

    expect(selected, ['안내소']);
  });

  test('확정한 모양: 앱 기본색, 선 1.0, 역 점 지름 2.2', () {
    expect(RouteRailPainter.color, VicaColors.primary);
    expect(RouteRailPainter.railWidth, 1.0);
    expect(RouteRailPainter.keyDotRadius * 2, closeTo(2.2, 0.001));
  });
}
