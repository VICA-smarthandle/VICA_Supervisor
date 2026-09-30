// 레일 칸(B단계)과 레일 팝업의 확정 문구·표시 규칙을 고정합니다(2026-09-30 사용자 확정).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/models/route_edit.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';
import 'package:vica_supervisor/widgets/rail_card.dart';
import 'package:vica_supervisor/widgets/rail_far_place_dialog.dart';
import 'package:vica_supervisor/widgets/route_dialogs.dart';
import 'package:vica_supervisor/widgets/vica_ui.dart';

const _info = RouteInfo(
  found: true,
  version: 'v1',
  status: 'applied',
  checks: RouteChecks(
    places: [
      RoutePlace(name: '407호', distance: 0.02, far: false),
      RoutePlace(name: '409호', distance: 0.4, far: false),
      RoutePlace(name: '학과사무실', distance: 10.31, far: true),
    ],
    summary: RouteSummary(nodeCount: 59, lengthM: 50.4, junctionCount: 3),
  ),
);

Future<void> pumpCard(
  WidgetTester tester, {
  RouteInfo? info = _info,
  bool editing = false,
  bool connected = true,
  bool drivingHold = false,
  RouteChecks checks = RouteChecks.none,
  RouteEditState state = RouteEditState.idle,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(420, 1600);
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: RailCard(
          info: info,
          editing: editing,
          state: state,
          message: '',
          connected: connected,
          drivingHold: drivingHold,
          sketch: RouteSketch.empty
              .addNode(Offset.zero)
              .addNode(const Offset(1, 0))
              .connect(1, 2),
          tool: RouteEditTool.addNode,
          checks: checks,
          onStartEdit: () {},
          onDraft: () {},
          onReload: () {},
          onSave: () {},
          onCancel: () {},
          onTool: (_) {},
        ),
      ),
    ),
  ));
}

String _all(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
    .join('\n')
    .replaceAll(RegExp('[​-‍⁠ ]'), '')
    .replaceAll(' ', ' ');

void main() {
  testWidgets('평소: 배지 "레일 적용됨"만, "레일 있음" 글자는 없다', (tester) async {
    await pumpCard(tester);
    final text = _all(tester);
    expect(text, contains('레일 적용됨'));
    expect(text, isNot(contains('레일 있음')));
    expect(text, contains('로봇이 따라 달리는 길입니다.'));
    expect(text, contains('59개'));
    expect(text, contains('50.4 m'));
    expect(text, contains('3곳'));
  });

  testWidgets('장소별 레일 거리와 먼 장소 경고(확정 문구)', (tester) async {
    await pumpCard(tester);
    final text = _all(tester);
    expect(text, contains('레일 위'));
    expect(text, contains('레일 0.4 m'));
    expect(text, contains('레일에서 10.3 m'));
    expect(text.replaceAll(RegExp(r'\s+'), ' '),
        contains("새 장소 '학과사무실'이 레일에서 10.3 m 떨어져 있습니다."));
    expect(text, contains('자유주행함을 주의하세요'));
  });

  testWidgets('레일 없는 지도: 자동 초안 버튼이 크게(채움)', (tester) async {
    await pumpCard(tester, info: const RouteInfo(found: false));
    expect(find.widgetWithText(FilledButton, '자동 초안 만들기'), findsOneWidget);
    expect(find.text('레일 없음'), findsOneWidget);
    expect(find.text('레일 편집'), findsNothing);
  });

  testWidgets('레일 있는 지도: 자동 초안은 보조 버튼', (tester) async {
    await pumpCard(tester);
    expect(find.widgetWithText(FilledButton, '레일 편집'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '자동 초안 새로 만들기'), findsOneWidget);
  });

  testWidgets('주행 중에는 편집 시작이 잠긴다', (tester) async {
    await pumpCard(tester, drivingHold: true);
    final button =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, '레일 편집'));
    expect(button.onPressed, isNull);
    expect(find.text('주행 중 · 편집 잠김'), findsOneWidget);
  });

  testWidgets('적용 대기: 확정 문구', (tester) async {
    await pumpCard(tester,
        info: const RouteInfo(found: true, status: 'apply_pending'));
    expect(_all(tester).replaceAll(RegExp(r'\s+'), ' '),
        contains('현재 주행 중이므로 적용이 불가합니다. 주행 완료 후 적용합니다.'));
  });

  testWidgets('편집 중: 확정 안내·자동 설정 문구·도구 3개·노드 수', (tester) async {
    await pumpCard(tester, editing: true, state: RouteEditState.editing);
    final text = _all(tester).replaceAll(RegExp(r'\s+'), ' ');
    expect(text, contains('2개의 노드를 놓고 지정하고 그 사이 선을 이어줍니다.'));
    expect(text, contains('노드를 길게 누르면 옮길 수 있습니다.'));
    expect(text, contains('코너 둥글리기, 1 m마다 노드 추가, 양방향 주행 부분은 로봇이 자동으로 설정합니다.'));
    expect(find.text('노드 추가'), findsOneWidget);
    expect(find.text('선 잇기'), findsOneWidget);
    expect(find.text('지우기'), findsOneWidget);
    expect(find.text('노드 2 · 선 1'), findsOneWidget);
    expect(text, isNot(contains('역')), reason: "앱에서는 '역' 대신 '노드'");
  });

  testWidgets('편집 중 검사 실패는 번호 목록', (tester) async {
    await pumpCard(
      tester,
      editing: true,
      state: RouteEditState.editing,
      checks: const RouteChecks(errors: [
        RouteIssue(
            code: 'too_close_to_wall',
            x: 1,
            y: 1,
            message: '선이 벽에 0.52 m까지 붙습니다.'),
      ]),
    );
    expect(find.text('1'), findsOneWidget);
    expect(find.text('검사 1건'), findsOneWidget);
  });

  testWidgets('팝업 D: 확정 본문과 사유 칸', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home:
          Scaffold(body: RouteApplyFailedDialog(reason: 'route server 응답 없음')),
    ));
    final dialog = tester.widget<VicaDialog>(find.byType(VicaDialog));
    expect(dialog.title, '레일을 적용하지 못했습니다');
    expect(dialog.body, '저장은 됐지만 로봇에 반영되지 않았습니다.\n로봇은 이전 레일로 주행합니다.');
    expect(find.text('route server 응답 없음'), findsOneWidget);
  });

  testWidgets('팝업 F: 새 레일 불러오기 / 덮어쓰기', (tester) async {
    RouteConflictChoice? got;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => got = await showRouteConflictDialog(context),
          child: const Text('열기'),
        ),
      ),
    ));
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    expect(find.text('다른 곳에서 레일이 바뀌었습니다'), findsOneWidget);
    await tester.tap(find.text('덮어쓰기'));
    await tester.pumpAndSettle();
    expect(got, RouteConflictChoice.overwrite);
  });

  testWidgets('팝업 E: [확인] [레일 편집], 레일 편집은 true', (tester) async {
    bool? got;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => got = await showDialog<bool>(
            context: context,
            builder: (_) =>
                const RailFarPlaceDialog(name: '학과사무실', meters: 10.3),
          ),
          child: const Text('열기'),
        ),
      ),
    ));
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    expect(find.text('확인'), findsOneWidget);
    await tester.tap(find.text('레일 편집'));
    await tester.pumpAndSettle();
    expect(got, isTrue);
  });
}
