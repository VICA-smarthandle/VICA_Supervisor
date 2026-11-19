// 지도 화면 배치(map_work_layout.dart) — 폰 세로도 지도를 위에 고정합니다(2026-11-19 사용자,
// 목업 RXMvVxPh A안 · 키보드가 열리면 지도 접기 · 높이 본문 3분의 1, 최소 220px).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/core/layout_breakpoints.dart';
import 'package:vica_supervisor/widgets/map_work_layout.dart';
import 'package:vica_supervisor/widgets/vica_ui.dart';

const _mapKey = ValueKey('map');
const _fieldKey = ValueKey('field');

Widget _host() => MaterialApp(
      home: Scaffold(
        body: MapWorkLayout(
          children: [
            const Text('지도 위 줄'),
            const SizedBox(height: 14),
            const MapWorkMap(
              child: ColoredBox(key: _mapKey, color: Colors.teal),
            ),
            const SizedBox(height: 20),
            const TextField(key: _fieldKey),
            for (var i = 0; i < 30; i++)
              SizedBox(height: 60, child: Text('칸 $i')),
          ],
        ),
      ),
    );

Future<void> _pump(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
    tester.view.resetViewInsets();
  });
  await tester.pumpWidget(_host());
  await tester.pump();
}

double _visibleMapHeight(WidgetTester tester) => tester
    .getSize(find
        .ancestor(of: find.byKey(_mapKey), matching: find.byType(ClipRect))
        .first)
    .height;

void main() {
  test('폰 세로는 본문 560px 이상이면 위 고정, 작은 폰·가로는 쌓기', () {
    MapWorkArrangement at(double w, double h, {double keyboard = 0}) =>
        MapWorkLayout.arrangementFor(
          BoxConstraints.tight(Size(w, h)),
          keyboard: keyboard,
        );
    expect(at(390, 627), MapWorkArrangement.pinnedTop);
    expect(at(360, 480), MapWorkArrangement.stacked);
    expect(at(800, 330), MapWorkArrangement.stacked); // 폰 가로
    // 키보드가 본문을 330 으로 줄여도 줄기 전 높이로 고릅니다.
    expect(at(390, 330, keyboard: 300), MapWorkArrangement.pinnedTop);
    // 세로 태블릿·넓은 창은 예전 그대로.
    expect(at(820, 1000), MapWorkArrangement.pinnedTop);
    expect(at(1280, 800), MapWorkArrangement.sideBySide);
  });

  testWidgets('폰: 지도만 고정 — 스크롤해도 지도는 그 자리, 지도 위 줄은 같이 스크롤', (tester) async {
    await _pump(tester, const Size(390, 627));
    final mapTop = tester.getTopLeft(find.byKey(_mapKey)).dy;
    final lineTop = tester.getTopLeft(find.text('지도 위 줄')).dy;
    // A안: 지도 위 줄은 지도 아래(스크롤 칸 맨 위)에 있습니다.
    expect(lineTop, greaterThan(mapTop));
    // 높이는 본문 3분의 1, 최소 220px.
    expect(tester.getSize(find.byKey(_mapKey)).height, closeTo(220, 1));

    await tester.drag(find.text('칸 3'), const Offset(0, -300));
    await tester.pump();
    expect(tester.getTopLeft(find.byKey(_mapKey)).dy, mapTop);
    expect(tester.getTopLeft(find.text('지도 위 줄')).dy, lessThan(lineTop));
  });

  testWidgets('폰: 키보드가 열리면 지도를 접고, 입력 칸의 초점·글은 그대로', (tester) async {
    await _pump(tester, const Size(390, 627));
    expect(_visibleMapHeight(tester), closeTo(226, 1)); // 지도 220 + 아래 틈 6

    await tester.tap(find.byKey(_fieldKey));
    await tester.enterText(find.byKey(_fieldKey), '민원 창구 3');
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(_visibleMapHeight(tester), 0);
    final field = tester.widget<EditableText>(find.byType(EditableText));
    expect(field.focusNode.hasFocus, isTrue);
    expect(field.controller.text, '민원 창구 3');
    // 접힌 지도는 눌리지 않습니다.
    expect(find.byKey(_mapKey).hitTestable(), findsNothing);

    tester.view.resetViewInsets();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(_visibleMapHeight(tester), closeTo(226, 1));
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
    );
  });

  testWidgets('작은 폰(본문 < 560px)은 지금처럼 함께 스크롤', (tester) async {
    await _pump(tester, const Size(360, 480));
    expect(find.byType(VicaPage), findsOneWidget);
    final mapTop = tester.getTopLeft(find.byKey(_mapKey)).dy;
    await tester.drag(find.text('칸 0'), const Offset(0, -200));
    await tester.pump();
    expect(tester.getTopLeft(find.byKey(_mapKey)).dy, lessThan(mapTop));
  });

  testWidgets('세로 태블릿은 예전 그대로 — 지도 위 줄도 고정', (tester) async {
    await _pump(
      tester,
      const Size(VicaBreakpoints.compact + 100, 1000),
    );
    final lineTop = tester.getTopLeft(find.text('지도 위 줄')).dy;
    expect(lineTop, lessThan(tester.getTopLeft(find.byKey(_mapKey)).dy));
    await tester.drag(find.text('칸 3'), const Offset(0, -300));
    await tester.pump();
    expect(tester.getTopLeft(find.text('지도 위 줄')).dy, lineTop);
  });
}
