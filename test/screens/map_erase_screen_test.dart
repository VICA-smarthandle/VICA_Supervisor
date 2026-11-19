// '지도 부분 지우기' 화면 — 사각형을 여러 개 그려 한 번에 지우는 흐름을 고정합니다.
//
// 로봇과 주고받는 모양(MapFix.srv)은 test/providers/map_fix_provider_test.dart 가 봅니다.
// 여기서는 mapFix 를 가짜로 바꿔 화면이 무엇을 언제 요청하는지만 봅니다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vica_supervisor/models/map_fix.dart';
import 'package:vica_supervisor/models/vica_map.dart';
import 'package:vica_supervisor/providers/settings_provider.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';
import 'package:vica_supervisor/screens/map_erase_screen.dart';
import 'package:vica_supervisor/widgets/map_canvas.dart';
import 'package:vica_supervisor/widgets/vica_ui.dart';

const _map = VicaMap(
  mapId: 'map_a',
  mapName: '시험 지도',
  imageUrl: '/maps/map_a.png',
  resolution: 0.05,
  originX: -10,
  originY: -10,
  width: 400,
  height: 300,
);

typedef _Call = ({String action, Map<String, Object?> args});

class _FakeSupervisor extends SupervisorProvider {
  final calls = <_Call>[];

  /// action 별 응답. 없으면 사각형마다 검은 칸 4 · 회색 칸 1 로 셉니다.
  final replies = <String, MapFixResult>{};

  @override
  Future<MapFixResult> mapFix(
    String mapId,
    String action, {
    Map<String, Object?> args = const {},
    Duration? timeout,
  }) async {
    calls.add((action: action, args: args));
    final fixed = replies[action];
    if (fixed != null) {
      return fixed;
    }
    final rects = (args['rects'] as List?) ?? const [];
    return MapFixResult(
      accepted: true,
      reason: '',
      message: '',
      result: {
        'rects': [
          for (final _ in rects)
            {'w_m': 1.0, 'h_m': 0.5, 'black': 4, 'gray': 1},
        ],
        'black': 4 * rects.length,
        'gray': rects.length,
        'applied': true,
        'mission_stale': false,
      },
    );
  }

  List<_Call> of(String action) =>
      calls.where((call) => call.action == action).toList();
}

void main() {
  Future<_FakeSupervisor> pumpScreen(
    WidgetTester tester, {
    void Function(MapFixResult?)? onClosed,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 2400);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final supervisor = _FakeSupervisor();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SupervisorProvider>.value(value: supervisor),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    final result =
                        await Navigator.of(context).push<MapFixResult>(
                      MaterialPageRoute(
                        builder: (_) => const MapEraseScreen(map: _map),
                      ),
                    );
                    onClosed?.call(result);
                  },
                  child: const Text('열기'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    return supervisor;
  }

  // MapCanvas 가 드래그 좌표(ROS m)를 돌려주는 지점을 직접 부릅니다. 실제 드래그는 지도
  // 그림 로드에 묶여 있어 시험 환경에서 재현이 어렵습니다.
  Future<void> drag(WidgetTester tester, Offset from, Offset to) async {
    final canvas = tester.widget<MapCanvas>(find.byType(MapCanvas));
    canvas.onKeepoutPanStart!(from);
    canvas.onKeepoutPanUpdate!(to);
    canvas.onKeepoutPanEnd!();
    await tester.pump();
    await tester.pump();
  }

  FilledButton eraseButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, '지우기'));

  testWidgets('처음에는 안내와 빈 목록이 보이고 지우기는 꺼져 있다', (tester) async {
    final supervisor = await pumpScreen(tester);

    expect(find.text('지도 부분 지우기'), findsOneWidget);
    expect(find.text(vicaKeepWords('지울 곳을 드래그해서 표시하세요')), findsOneWidget);
    expect(find.text(vicaKeepWords('고른 구역')), findsOneWidget);
    expect(find.text('0곳'), findsOneWidget);
    expect(eraseButton(tester).onPressed, isNull);
    expect(supervisor.calls, isEmpty);
    // 드래그를 사각형 그리기에 씁니다.
    expect(
      tester.widget<MapCanvas>(find.byType(MapCanvas)).keepoutEditMode,
      isTrue,
    );
  });

  testWidgets('사각형을 더하면 erase_count 를 전체 목록으로 부르고 줄이 생긴다', (tester) async {
    final supervisor = await pumpScreen(tester);

    await drag(tester, const Offset(1, 1), const Offset(2, 1.5));
    expect(supervisor.of('erase_count'), hasLength(1));
    expect(supervisor.of('erase_count').last.args['rects'], [
      {'x_min': 1.0, 'y_min': 1.0, 'x_max': 2.0, 'y_max': 1.5},
    ]);
    expect(find.text('1곳'), findsOneWidget);
    expect(find.text('1.0 × 0.5 m'), findsOneWidget);
    expect(find.text(vicaKeepWords('검은 칸 4 · 회색 칸 1')), findsOneWidget);

    // 오른쪽 아래에서 왼쪽 위로 끌어도 같은 사각형입니다.
    await drag(tester, const Offset(4, 3), const Offset(3, 2));
    final rects = supervisor.of('erase_count').last.args['rects']! as List;
    expect(rects, hasLength(2));
    expect(rects.last, {
      'x_min': 3.0,
      'y_min': 2.0,
      'x_max': 4.0,
      'y_max': 3.0,
    });
    expect(find.text('2곳'), findsOneWidget);
    expect(find.text(vicaKeepWords('검은 칸 8개 · 회색 칸 2개')), findsOneWidget);
    expect(eraseButton(tester).onPressed, isNotNull);
  });

  testWidgets('✕ 를 누르면 그 줄만 빠지고 다시 센다', (tester) async {
    final supervisor = await pumpScreen(tester);
    await drag(tester, const Offset(1, 1), const Offset(2, 2));
    await drag(tester, const Offset(3, 3), const Offset(4, 4));

    await tester.tap(find.byTooltip('1번 구역 빼기'));
    await tester.pump();
    await tester.pump();

    expect(find.text('1곳'), findsOneWidget);
    expect(supervisor.of('erase_count').last.args['rects'], [
      {'x_min': 3.0, 'y_min': 3.0, 'x_max': 4.0, 'y_max': 4.0},
    ]);
  });

  testWidgets('0.05 m 보다 작은 드래그는 버린다', (tester) async {
    final supervisor = await pumpScreen(tester);

    await drag(tester, const Offset(1, 1), const Offset(1.04, 2));
    await drag(tester, const Offset(1, 1), const Offset(2, 1.04));

    expect(find.text('0곳'), findsOneWidget);
    expect(supervisor.calls, isEmpty);
  });

  testWidgets('스무 개에서 더 받지 않는다', (tester) async {
    final supervisor = await pumpScreen(tester);
    for (var i = 0; i < 20; i++) {
      await drag(tester, Offset(i.toDouble(), 0), Offset(i + 0.5, 0.5));
    }
    expect(find.text('20곳'), findsOneWidget);
    expect(supervisor.of('erase_count'), hasLength(20));

    await drag(tester, const Offset(0, 5), const Offset(1, 6));
    expect(find.text('20곳'), findsOneWidget);
    expect(supervisor.of('erase_count'), hasLength(20));
    expect(find.text(vicaKeepWords('한 번에 20곳까지 지울 수 있습니다.')), findsOneWidget);
  });

  testWidgets('지도 밖 사각형은 빼고 로봇 문구를 보인다', (tester) async {
    final supervisor = await pumpScreen(tester);
    await drag(tester, const Offset(1, 1), const Offset(2, 2));

    supervisor.replies['erase_count'] = const MapFixResult(
      accepted: false,
      reason: 'out_of_map',
      message: '지도 밖입니다.',
    );
    await drag(tester, const Offset(90, 90), const Offset(91, 91));

    expect(find.text('1곳'), findsOneWidget);
    expect(find.text(vicaKeepWords('지도 밖입니다.')), findsOneWidget);
    // 앞서 센 값은 남은 사각형과 그대로 맞습니다.
    expect(find.text(vicaKeepWords('검은 칸 4개 · 회색 칸 1개')), findsOneWidget);
  });

  testWidgets('확인에서 지우기를 누르면 erase 를 보내고 결과를 들고 닫힌다', (tester) async {
    MapFixResult? closedWith;
    var closed = false;
    final supervisor = await pumpScreen(
      tester,
      onClosed: (result) {
        closed = true;
        closedWith = result;
      },
    );
    await drag(tester, const Offset(1, 1), const Offset(2, 2));
    await drag(tester, const Offset(3, 3), const Offset(4, 4));

    await tester.tap(find.widgetWithText(FilledButton, '지우기'));
    await tester.pumpAndSettle();
    expect(find.text(vicaKeepWords('선택한 구역을 지울까요?')), findsOneWidget);
    expect(find.text(vicaKeepWords('실제로 없는 장애물인지 다시 확인하세요.')), findsOneWidget);
    expect(find.text('2곳'), findsNWidgets(2)); // 목록 머리 + 확인 줄
    expect(find.text('8개'), findsOneWidget);
    expect(find.text('2개'), findsOneWidget);
    expect(supervisor.of('erase'), isEmpty);

    // 확인 창의 [지우기] 는 화면의 [지우기] 위에 뜹니다.
    await tester.tap(find.widgetWithText(FilledButton, '지우기').last);
    await tester.pumpAndSettle();

    expect(supervisor.of('erase'), hasLength(1));
    expect(
      (supervisor.of('erase').single.args['rects']! as List),
      hasLength(2),
    );
    expect(closed, isTrue);
    expect(closedWith!.applied, isTrue);
    expect(find.byType(MapEraseScreen), findsNothing);
  });

  testWidgets('확인에서 취소하면 아무것도 보내지 않는다', (tester) async {
    final supervisor = await pumpScreen(tester);
    await drag(tester, const Offset(1, 1), const Offset(2, 2));

    await tester.tap(find.widgetWithText(FilledButton, '지우기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소').last);
    await tester.pumpAndSettle();

    expect(supervisor.of('erase'), isEmpty);
    expect(find.byType(MapEraseScreen), findsOneWidget);
    expect(find.text('1곳'), findsOneWidget);
  });

  testWidgets('거절되면 화면에 남고 로봇 문구를 보인다', (tester) async {
    var closed = false;
    final supervisor = await pumpScreen(tester, onClosed: (_) => closed = true);
    await drag(tester, const Offset(1, 1), const Offset(2, 2));
    supervisor.replies['erase'] = const MapFixResult(
      accepted: false,
      reason: 'busy_driving',
      message: '주행 중에는 지도를 수정할 수 없습니다.',
    );

    await tester.tap(find.widgetWithText(FilledButton, '지우기'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '지우기').last);
    await tester.pumpAndSettle();

    expect(closed, isFalse);
    expect(find.byType(MapEraseScreen), findsOneWidget);
    expect(find.text(vicaKeepWords('주행 중에는 지도를 수정할 수 없습니다.')), findsOneWidget);
    // 그린 것은 그대로 남아 다시 누를 수 있습니다.
    expect(find.text('1곳'), findsOneWidget);
    expect(eraseButton(tester).onPressed, isNotNull);
  });
}
