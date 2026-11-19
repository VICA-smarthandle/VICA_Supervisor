// 지도 설정에 끼우는 '지도 수정' 칸 한 덩어리 — 펼칠 때 로봇에 묻기, 다른 칸과 한 번에 하나만
// 펼쳐지기, 되돌리기, 끝 알림(미션 문구 덧붙임)을 고정합니다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vica_supervisor/core/app_settings.dart';
import 'package:vica_supervisor/models/map_fix.dart';
import 'package:vica_supervisor/models/vica_map.dart';
import 'package:vica_supervisor/providers/settings_provider.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';
import 'package:vica_supervisor/ros/ros_bridge_client.dart';
import 'package:vica_supervisor/widgets/map_fix_card.dart';
import 'package:vica_supervisor/widgets/map_fix_panel.dart';
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

MapFixResult _ok(Map<String, Object?> result) =>
    MapFixResult(accepted: true, reason: '', message: '', result: result);

const _oneErase = {
  'lock': '',
  'can_scan': true,
  'history': [
    {
      'at': '2026-11-18T15:31:00',
      'kind': 'erase',
      'black': 19,
      'gray': 3,
      'rects': [
        {'x_min': 0, 'y_min': 0, 'x_max': 1, 'y_max': 1},
      ],
    },
  ],
};

class _FakeSupervisor extends SupervisorProvider {
  final actions = <String>[];
  final replies = <String, MapFixResult>{'get': _ok(_oneErase)};
  int mapListRequests = 0;
  bool online = true;

  @override
  RosConnectionState get connectionState =>
      online ? RosConnectionState.connected : RosConnectionState.disconnected;

  @override
  Future<MapFixResult> mapFix(
    String mapId,
    String action, {
    Map<String, Object?> args = const {},
    Duration? timeout,
  }) async {
    actions.add(action);
    return replies[action] ?? _ok(const {});
  }

  @override
  void requestMapList(AppSettings settings) => mapListRequests++;

  int count(String action) => actions.where((a) => a == action).length;
}

void main() {
  Widget host(
    _FakeSupervisor supervisor, {
    bool otherPanelOpen = false,
    Future<bool> Function()? onCloseOthers,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SupervisorProvider>.value(value: supervisor),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MapFixPanel(
              map: _map,
              otherPanelOpen: otherPanelOpen,
              onCloseOthers: onCloseOthers ?? () async => true,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('지도 수정'));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('접혀 있을 때는 로봇에 묻지 않는다', (tester) async {
    final supervisor = _FakeSupervisor();
    await tester.pumpWidget(host(supervisor));

    expect(find.text('지도 수정'), findsOneWidget);
    expect(find.text('지우기'), findsNothing);
    expect(supervisor.actions, isEmpty);
    // 옛 답으로 '가능'이라 적지 않습니다.
    expect(find.text(kMapFixWordReady), findsNothing);
  });

  testWidgets('칸을 열면 get 을 부르고 상태와 최근 수정이 보인다', (tester) async {
    final supervisor = _FakeSupervisor();
    await tester.pumpWidget(host(supervisor));
    await open(tester);

    expect(supervisor.actions, ['get']);
    expect(find.text(kMapFixWordReady), findsOneWidget);
    expect(find.text('지우기'), findsOneWidget);
    expect(find.text('부분 스캔'), findsOneWidget);
    expect(find.text(vicaKeepWords('지우기 · 1곳')), findsOneWidget);
    expect(find.text('되돌리기'), findsOneWidget);
  });

  testWidgets('연결이 끊겨 있으면 접힌 채로도 오프라인이 보인다', (tester) async {
    final supervisor = _FakeSupervisor()..online = false;
    await tester.pumpWidget(host(supervisor));
    expect(find.text(kMapFixWordOffline), findsOneWidget);
  });

  testWidgets('로봇이 답하지 않으면 그 문구가 보이고 버튼이 꺼진다', (tester) async {
    final supervisor = _FakeSupervisor();
    supervisor.replies['get'] = MapFixResult.offline(
      '지도 수정 노드(map_fix_node)가 응답하지 않습니다.',
    );
    await tester.pumpWidget(host(supervisor));
    await open(tester);

    expect(find.textContaining('map_fix_node'), findsOneWidget);
    final erase = tester.widget<ButtonStyleButton>(
      find
          .ancestor(
            of: find.text('지우기'),
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          )
          .first,
    );
    expect(erase.onPressed, isNull);
  });

  testWidgets('다른 칸이 열리면 접힌다', (tester) async {
    final supervisor = _FakeSupervisor();
    await tester.pumpWidget(host(supervisor));
    await open(tester);
    expect(find.text('지우기'), findsOneWidget);

    await tester.pumpWidget(host(supervisor, otherPanelOpen: true));
    await tester.pump();
    expect(find.text('지우기'), findsNothing);
  });

  testWidgets('다른 칸이 열려 있으면 먼저 접어 달라고 하고, 남기로 하면 열지 않는다', (tester) async {
    final supervisor = _FakeSupervisor();
    var asked = 0;
    await tester.pumpWidget(
      host(
        supervisor,
        otherPanelOpen: true,
        onCloseOthers: () async {
          asked++;
          return false;
        },
      ),
    );
    await open(tester);

    expect(asked, 1);
    expect(find.text('지우기'), findsNothing);
    expect(supervisor.actions, isEmpty);
  });

  testWidgets('되돌리기 — 확인 뒤 undo 를 보내고 기록과 지도 그림을 다시 받는다', (tester) async {
    final supervisor = _FakeSupervisor();
    supervisor.replies['undo'] = _ok({
      'kind': 'erase',
      'applied': true,
      'mission_stale': false,
    });
    await tester.pumpWidget(host(supervisor));
    await open(tester);

    await tester.tap(find.text('되돌리기'));
    await tester.pumpAndSettle();
    expect(find.text(vicaKeepWords('마지막 수정을 되돌릴까요?')), findsOneWidget);
    expect(supervisor.count('undo'), 0);

    await tester.tap(find.widgetWithText(FilledButton, '되돌리기'));
    await tester.pumpAndSettle();

    expect(supervisor.count('undo'), 1);
    expect(find.text(vicaKeepWords('되돌렸습니다.')), findsOneWidget);
    expect(supervisor.count('get'), 2);
    expect(supervisor.mapListRequests, 1);
  });

  testWidgets('되돌리기를 취소하면 보내지 않는다', (tester) async {
    final supervisor = _FakeSupervisor();
    await tester.pumpWidget(host(supervisor));
    await open(tester);

    await tester.tap(find.text('되돌리기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    expect(supervisor.count('undo'), 0);
    expect(supervisor.mapListRequests, 0);
  });

  testWidgets('미션이 켜져 있으면 끝 알림에 미션 문구가 붙는다', (tester) async {
    final supervisor = _FakeSupervisor();
    supervisor.replies['undo'] = _ok({
      'kind': 'scan',
      'applied': true,
      'mission_stale': true,
    });
    await tester.pumpWidget(host(supervisor));
    await open(tester);

    await tester.tap(find.text('되돌리기'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '되돌리기'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        '${vicaKeepWords('되돌렸습니다.')}\n'
        '${vicaKeepWords(vicaBreakAtSentences(kMapFixMissionStaleText))}',
      ),
      findsOneWidget,
    );
  });

  testWidgets('거절되면 로봇 문구를 보이고 지도 그림은 다시 받지 않는다', (tester) async {
    final supervisor = _FakeSupervisor();
    supervisor.replies['undo'] = const MapFixResult(
      accepted: false,
      reason: 'busy_driving',
      message: '주행 중에는 지도를 수정할 수 없습니다.',
    );
    await tester.pumpWidget(host(supervisor));
    await open(tester);

    await tester.tap(find.text('되돌리기'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '되돌리기'));
    await tester.pumpAndSettle();

    // 칸 안의 빨간 줄과 아래 알림 두 곳에 보입니다.
    expect(
      find.text(vicaKeepWords('주행 중에는 지도를 수정할 수 없습니다.')),
      findsNWidgets(2),
    );
    expect(supervisor.mapListRequests, 0);
  });
}
