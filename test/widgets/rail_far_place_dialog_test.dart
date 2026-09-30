// 레일 팝업 E(새 장소가 레일에서 멀 때)와 레일까지 거리 계산을 고정합니다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/models/route_graph.dart';
import 'package:vica_supervisor/widgets/rail_far_place_dialog.dart';
import 'package:vica_supervisor/widgets/vica_ui.dart';

// (0,0)-(4,0) 직선 레일 하나. 가운데 노드 없이 엣지 한 개.
const _line = RouteGraph(
  nodes: {1: Offset(0, 0), 2: Offset(4, 0)},
  edges: [RouteEdge(1, 2)],
);

void main() {
  test('레일까지 거리는 노드가 아니라 선 위 가장 가까운 점까지다', () {
    expect(_line.distanceTo(2, 3), closeTo(3.0, 1e-9));
    expect(_line.distanceTo(7, 4), closeTo(5.0, 1e-9)); // 끝 노드 (4,0)까지
    expect(const RouteGraph(nodes: {}, edges: []).distanceTo(0, 0), isNull);
  });

  test('기준 거리는 BT 가 레일을 내려놓는 2 m 와 같다', () {
    expect(kRailHandoffMeters, 2.0);
  });

  test('이름 끝 받침에 맞춰 조사를 붙인다', () {
    expect(subjectParticle('학과사무실'), '이');
    expect(subjectParticle('407호'), '가');
    expect(subjectParticle('Lab'), '이(가)');
  });

  test('문구는 사용자 확정본이다', () {
    expect(
      railFarPlaceMessage('학과사무실', 10.31),
      "새 장소 '학과사무실'이 레일에서 10.3 m 떨어져 있습니다.\n"
      '레일 없이 자유주행함을 주의하세요.',
    );
  });

  testWidgets('팝업은 제목·본문·확인 버튼을 그리고 확인으로 닫힌다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) =>
                  const RailFarPlaceDialog(name: '학과사무실', meters: 10.3),
            ),
            child: const Text('열기'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    expect(find.text('새 장소가 레일에서 떨어져 있습니다'), findsOneWidget);
    // 본문은 어절 단위 줄바꿈 문자를 거쳐 그려지므로 넘긴 값으로 확인합니다.
    expect(
      tester.widget<VicaDialog>(find.byType(VicaDialog)).body,
      railFarPlaceMessage('학과사무실', 10.3),
    );
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    expect(find.byType(RailFarPlaceDialog), findsNothing);
  });
}
