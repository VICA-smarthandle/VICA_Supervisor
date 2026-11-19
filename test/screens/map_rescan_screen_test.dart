// '지도 다시 스캔하기' 화면 — 범위 고르기 → 물러나기·스캔 → 미리보기 → 적용의 흐름을 고정합니다.
//
// 단계의 주인은 로봇(map_fix_node)입니다. 화면은 토픽 /vica/map_fix/state 의 phase 를 그대로
// 보여 주므로, 시험은 그 상태를 넣어 주고 화면이 무엇을 보이고 무엇을 요청하는지만 봅니다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vica_supervisor/models/map_fix.dart';
import 'package:vica_supervisor/models/vica_map.dart';
import 'package:vica_supervisor/providers/settings_provider.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';
import 'package:vica_supervisor/screens/map_rescan_screen.dart';
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

MapFixResult _ok(Map<String, Object?> result) =>
    MapFixResult(accepted: true, reason: '', message: '', result: result);

class _FakeSupervisor extends SupervisorProvider {
  final calls = <_Call>[];

  final replies = <String, MapFixResult>{
    'scan_check': _ok({
      'ok': true,
      'reason': '',
      'score': 84.0,
      'ambiguous': <Object?>[],
      'hits': [
        [1.0, 2.0],
        [1.5, 2.0],
      ],
    }),
    'scan_start': _ok({'session': 's1'}),
    'scan_apply': _ok({
      'added': 41,
      'removed': 28,
      'score_before': 62.0,
      'score_after': 91.0,
      'applied': true,
      'mission_stale': false,
    }),
  };

  @override
  Future<MapFixResult> mapFix(
    String mapId,
    String action, {
    Map<String, Object?> args = const {},
    Duration? timeout,
  }) async {
    calls.add((action: action, args: args));
    return replies[action] ?? _ok(const {});
  }

  List<_Call> of(String action) =>
      calls.where((call) => call.action == action).toList();

  void robot({String status = 'idle'}) => handleRobotStatusForTest({
        'robot_id': 'vica_robot_01',
        'robot_name': 'VICA 1호기',
        'status': status,
        'x': 1.0,
        'y': 2.0,
        'yaw': 0.0,
        'current_location': '',
        'current_goal': '',
        'error_reason': '',
        'waiting_reason': '',
        'map_id': 'map_a',
      });

  void state(String phase, [Map<String, Object?> more = const {}]) =>
      handleMapFixStateForTest({
        'session': 's1',
        'map_id': 'map_a',
        'phase': phase,
        'radius_m': 2.0,
        ...more,
      });
}

void main() {
  Future<_FakeSupervisor> pumpScreen(
    WidgetTester tester, {
    void Function(MapFixResult?)? onClosed,
    void Function(_FakeSupervisor)? before,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 2400);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final supervisor = _FakeSupervisor()..robot();
    before?.call(supervisor);
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
                        builder: (_) => const MapRescanScreen(map: _map),
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

  testWidgets('들어오면 scan_check 를 부르고 위치 맞춤을 보인다', (tester) async {
    final supervisor = await pumpScreen(tester);

    expect(supervisor.of('scan_check'), hasLength(1));
    expect(find.text('지도 다시 스캔하기'), findsOneWidget);
    expect(find.text(vicaKeepWords('위치 맞춤 84 %')), findsOneWidget);
    expect(find.text(vicaKeepWords('지도와 라이다')), findsOneWidget);
    expect(find.text(vicaKeepWords('로봇 정지')), findsOneWidget);
    expect(
      find.text(
        '${vicaKeepWords('다시 스캔하고 싶은 곳에 비카를 두세요.')}\n'
        '${vicaKeepWords('범위가 작을수록 정확합니다.')}',
      ),
      findsOneWidget,
    );
    // 확인한 자세에서 본 라이다 점이 지도에 겹칩니다.
    expect(tester.widget<MapCanvas>(find.byType(MapCanvas)).scanHits, const [
      Offset(1.0, 2.0),
      Offset(1.5, 2.0),
    ]);
    // 처음 범위는 2 m 입니다.
    expect(find.text('1 m'), findsOneWidget);
    expect(find.text('3 m'), findsOneWidget);
    expect(find.text('2 m'), findsNWidgets(2)); // 단추 + 지도 위 글자
  });

  testWidgets('범위를 3 m 로 바꾸고 시작하면 scan_start 에 radius_m 3 이 간다', (
    tester,
  ) async {
    final supervisor = await pumpScreen(tester);

    await tester.tap(find.text('3 m'));
    await tester.pump();
    await tester.tap(find.text('스캔 시작'));
    await tester.pump();

    expect(supervisor.of('scan_start').single.args, {'radius_m': 3.0});
    // 첫 진행이 오기 전에도 진행 화면으로 넘어가고 뒤로 가기가 사라집니다.
    expect(find.text(vicaKeepWords('스캔 준비 중')), findsOneWidget);
    expect(find.text('중지'), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);

    supervisor.state('step_back', {'remaining_s': 5, 'radius_m': 3.0});
    await tester.pump();
    expect(find.text(vicaKeepWords('범위 3 m')), findsOneWidget);
    // 첫 진행을 기다리던 시계가 남지 않습니다.
    await tester.pump(const Duration(seconds: 6));
    expect(find.text(vicaKeepWords('스캔 준비 중')), findsOneWidget);
  });

  testWidgets('자세가 안 맞으면 시작 대신 다시 확인이 보인다', (tester) async {
    final supervisor = await pumpScreen(
      tester,
      before: (supervisor) {
        supervisor.replies['scan_check'] = _ok({
          'ok': false,
          'reason': 'ambiguous',
          'score': 88.0,
          'ambiguous': ['forward'],
          'hits': <Object?>[],
        });
      },
    );

    expect(find.text('스캔 시작'), findsNothing);
    expect(find.text('다시 확인'), findsOneWidget);
    expect(
      find.text(
        vicaKeepWords(
          vicaBreakAtSentences('앞뒤 위치를 구분할 수 없습니다. 모서리나 문틀이 보이는 곳으로 옮겨 주세요.'),
        ),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('다시 확인'));
    await tester.pump();
    expect(supervisor.of('scan_check'), hasLength(2));
  });

  testWidgets('step_back 상태가 오면 남은 초와 중지 버튼이 보인다', (tester) async {
    final supervisor = await pumpScreen(tester);
    await tester.tap(find.text('스캔 시작'));
    await tester.pump();

    supervisor.state('step_back', {
      'remaining_s': 3,
      'moved_m': 0.03,
      'moved_deg': 0.4,
      'score': 88.0,
    });
    await tester.pump();

    expect(find.text(vicaKeepWords('스캔 준비 중')), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text(vicaKeepWords('초 뒤 스캔')), findsOneWidget);
    expect(find.text(vicaKeepWords('위치 다시 맞춤')), findsOneWidget);
    expect(
      find.text(vicaKeepWords('안 바뀐 벽에 맞춤 · 3 cm · 0.4° 옮김')),
      findsOneWidget,
    );
    expect(find.text(vicaKeepWords('원 밖으로 물러나기')), findsOneWidget);
    expect(find.text(vicaKeepWords('원 안에 있으면 지도에 찍힙니다')), findsOneWidget);
    expect(find.text(vicaKeepWords('스캔 5초')), findsOneWidget);
    expect(find.text('이 원 밖으로'), findsOneWidget);

    supervisor.state('scanning', {'remaining_s': 4});
    await tester.pump();
    expect(find.text(vicaKeepWords('스캔 중')), findsOneWidget);
    expect(find.text('4'), findsOneWidget);

    await tester.tap(find.text('중지'));
    await tester.pump();
    expect(supervisor.of('scan_cancel').single.args, {'session': 's1'});
    // 범위 고르기로 돌아옵니다.
    expect(find.text('스캔 시작'), findsOneWidget);
  });

  testWidgets('preview 상태가 오면 칸 수와 수정 전·후 % 가 보인다', (tester) async {
    final supervisor = await pumpScreen(tester);
    supervisor.state('preview', {
      'added': 41,
      'removed': 28,
      'score_before': 62.0,
      'score_after': 91.0,
      'cells': [
        [1.025, 2.075, 1],
        [0.525, 1.025, -1],
      ],
    });
    await tester.pump();

    expect(find.textContaining('41칸', findRichText: true), findsOneWidget);
    expect(find.textContaining('28칸', findRichText: true), findsOneWidget);
    expect(find.text(vicaKeepWords('위치 맞춤')), findsOneWidget);
    expect(find.text(vicaKeepWords('같은 스캔으로 잰 값')), findsOneWidget);
    expect(find.text('수정 전'), findsOneWidget);
    expect(find.text('62 %'), findsOneWidget);
    expect(find.text('수정 후'), findsOneWidget);
    expect(find.text('91 %'), findsOneWidget);
    expect(
      find.text(vicaKeepWords('다른 장애물이 찍혔으면 적용한 뒤 지우기로 지우세요.')),
      findsOneWidget,
    );
    expect(find.text('적용'), findsOneWidget);
    expect(find.text('버리기'), findsOneWidget);
    // 미리보기에서는 뒤로 갈 수 없습니다.
    expect(find.byType(BackButton), findsNothing);
  });

  testWidgets('적용을 누르면 scan_apply 를 보내고 결과를 들고 닫힌다', (tester) async {
    MapFixResult? closedWith;
    final supervisor = await pumpScreen(
      tester,
      onClosed: (result) => closedWith = result,
    );
    supervisor.state('preview', {'added': 41, 'removed': 28});
    await tester.pump();

    await tester.tap(find.text('적용'));
    await tester.pumpAndSettle();

    expect(supervisor.of('scan_apply').single.args, {'session': 's1'});
    expect(closedWith!.applied, isTrue);
    expect(closedWith!.scoreAfter, 91.0);
    expect(find.byType(MapRescanScreen), findsNothing);
    expect(supervisor.mapFixScan, isNull);
  });

  testWidgets('버리기를 누르면 scan_discard 를 보내고 범위 고르기로 돌아간다', (tester) async {
    final supervisor = await pumpScreen(tester);
    supervisor.state('preview', {'added': 41, 'removed': 28});
    await tester.pump();

    await tester.tap(find.text('버리기'));
    await tester.pump();
    await tester.pump();

    expect(supervisor.of('scan_discard').single.args, {'session': 's1'});
    expect(supervisor.of('scan_apply'), isEmpty);
    expect(find.byType(MapRescanScreen), findsOneWidget);
    expect(find.text('스캔 시작'), findsOneWidget);
  });

  testWidgets('failed(ambiguous forward) 면 앞뒤 문구 팝업이 뜬다', (tester) async {
    final supervisor = await pumpScreen(tester);
    await tester.tap(find.text('스캔 시작'));
    await tester.pump();

    supervisor.state('failed', {
      'reason': 'ambiguous',
      'score': 88.0,
      'ambiguous': ['forward'],
    });
    await tester.pumpAndSettle();

    expect(find.text(vicaKeepWords('여기서는 다시 스캔할 수 없습니다')), findsOneWidget);
    expect(
      find.text(
        vicaKeepWords(
          vicaBreakAtSentences('앞뒤 위치를 구분할 수 없습니다. 모서리나 문틀이 보이는 곳으로 옮겨 주세요.'),
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('구분되지 않는 방향'), findsOneWidget);
    expect(find.text('앞뒤'), findsOneWidget);
    expect(find.text('88 %'), findsOneWidget);

    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();

    // 실패를 다 보면 치우고 범위 고르기로 돌아가 자세를 다시 확인합니다.
    expect(supervisor.mapFixScan, isNull);
    expect(find.text('스캔 시작'), findsOneWidget);
    expect(supervisor.of('scan_check'), hasLength(2));
  });

  testWidgets('시작했는데 진행이 오지 않으면 범위 고르기로 돌아간다', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('스캔 시작'));
    await tester.pump();
    expect(find.text(vicaKeepWords('스캔 준비 중')), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));

    expect(find.text('스캔 시작'), findsOneWidget);
    expect(
      find.text(
        vicaKeepWords(vicaBreakAtSentences('로봇이 스캔 진행을 보내지 않습니다. 다시 눌러 주세요.')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('로봇이 움직이는 중이면 스캔 시작이 꺼진다', (tester) async {
    final supervisor = await pumpScreen(tester);
    supervisor.robot(status: 'moving');
    await tester.pump();

    final start = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '스캔 시작'),
    );
    expect(start.onPressed, isNull);
  });

  test('mapFixFailText 사유별 글자', () {
    expect(
      mapFixFailText('ambiguous', ambiguous: ['forward']),
      '앞뒤 위치를 구분할 수 없습니다. 모서리나 문틀이 보이는 곳으로 옮겨 주세요.',
    );
    expect(
      mapFixFailText('ambiguous', ambiguous: ['lateral']),
      '좌우 위치를 구분할 수 없습니다. 모서리나 문틀이 보이는 곳으로 옮겨 주세요.',
    );
    expect(
      mapFixFailText('ambiguous', ambiguous: ['yaw']),
      '방향을 구분할 수 없습니다. 모서리나 문틀이 보이는 곳으로 옮겨 주세요.',
    );
    expect(
      mapFixFailText('ambiguous', ambiguous: ['forward', 'yaw']),
      '앞뒤 위치와 방향을 구분할 수 없습니다. 모서리나 문틀이 보이는 곳으로 옮겨 주세요.',
    );
    for (final reason in ['low_match', 'no_pose']) {
      expect(mapFixFailText(reason), '지도와 라이다가 맞지 않습니다. 초기 위치를 다시 잡아 주세요.');
    }
    expect(mapFixFailText('moved'), '로봇이 움직였습니다. 세운 뒤 다시 눌러 주세요.');
    expect(mapFixFailText('no_change'), '이 범위에서 변경된 곳을 찾지 못했습니다.');
    expect(mapFixFailText('busy_driving'), '주행 중에는 지도를 수정할 수 없습니다.');
    // 모르는 사유는 로봇이 보낸 문구 그대로입니다.
    expect(
      mapFixFailText('busy_session', message: '부분 스캔이 진행 중입니다.'),
      '부분 스캔이 진행 중입니다.',
    );
  });
}
