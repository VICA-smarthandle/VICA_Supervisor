import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vica_supervisor/models/map_fix.dart';
import 'package:vica_supervisor/models/vica_map.dart';
import 'package:vica_supervisor/providers/settings_provider.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';
import 'package:vica_supervisor/screens/map_erase_screen.dart';
import 'package:vica_supervisor/screens/map_rescan_screen.dart';
import 'package:vica_supervisor/widgets/map_canvas.dart';
import 'package:vica_supervisor/widgets/map_fix_card.dart';
import 'package:vica_supervisor/widgets/vica_ui.dart';

const _map = VicaMap(
  mapId: 'map_a',
  mapName: '시험 지도',
  imageUrl: '/maps/map_a.png',
  resolution: 0.05,
  originX: -10,
  originY: -10,
  width: 572,
  height: 443,
);

const _sizes = <String, Size>{
  '폰 360': Size(360, 760),
  '폰 390': Size(390, 844),
  '태블릿 820': Size(820, 1180),
  '노트북 1440': Size(1440, 900),
};

MapFixResult _ok(Map<String, Object?> result) =>
    MapFixResult(accepted: true, reason: '', message: '', result: result);

class _FakeSupervisor extends SupervisorProvider {
  final replies = <String, MapFixResult>{};

  @override
  Future<MapFixResult> mapFix(
    String mapId,
    String action, {
    Map<String, Object?> args = const {},
    Duration? timeout,
  }) async {
    final fixed = replies[action];
    if (fixed != null) {
      return fixed;
    }
    final rects = (args['rects'] as List?) ?? const [];
    return _ok({
      'rects': [
        for (final _ in rects)
          {'w_m': 12.5, 'h_m': 10.25, 'black': 1234, 'gray': 5678},
      ],
      'black': 12340,
      'gray': 56780,
    });
  }

  void robot() => handleRobotStatusForTest({
        'robot_id': 'vica_robot_01',
        'robot_name': 'VICA 1호기',
        'status': 'idle',
        'x': 1.0,
        'y': 2.0,
        'yaw': 0.0,
        'current_location': '',
        'current_goal': '',
        'error_reason': '',
        'waiting_reason': '',
        'map_id': 'map_a',
      });
}

Future<void> _setSize(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
}

Widget _host(_FakeSupervisor supervisor, Widget child) => MultiProvider(
      providers: [
        ChangeNotifierProvider<SupervisorProvider>.value(value: supervisor),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: MaterialApp(home: child),
    );

/// 화면을 띄운 뒤 넘침 오류가 있었는지 모아 돌려줍니다.
void _expectNoLayoutError(WidgetTester tester, String where) {
  final error = tester.takeException();
  expect(error, isNull, reason: '$where: $error');
}

const _history = MapFixStatus(
  lock: '',
  canScan: false,
  history: [
    MapFixHistoryEntry(
      at: '2026-11-18T15:42:07',
      kind: 'scan',
      radiusM: 3.0,
      added: 1999,
      removed: 1888,
    ),
    MapFixHistoryEntry(
      at: '2026-11-18T15:31:00',
      kind: 'erase',
      black: 12345,
      gray: 67890,
      rectCount: 10,
    ),
    MapFixHistoryEntry(
      at: '2026-11-18T15:20:00',
      kind: 'erase',
      black: 1,
      gray: 0,
      rectCount: 1,
    ),
  ],
);

void main() {
  for (final entry in _sizes.entries) {
    final label = entry.key;
    final size = entry.value;
    final cardWidth = size.width < 600 ? size.width - 32 : 400.0;

    testWidgets('$label — 지도 수정 칸(기록 세 줄·이유 두 줄·오류 문구)', (tester) async {
      await _setSize(tester, size);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: cardWidth,
              child: VicaExpandPanel(
                title: '지도 수정',
                icon: Icons.auto_fix_high,
                summary: kMapFixWordUnknown,
                expanded: true,
                onTap: () {},
                child: MapFixCard(
                  connected: true,
                  status: _history,
                  note: kMapFixNoReplyText,
                  onErase: () {},
                  onScan: () {},
                  onUndo: () {},
                ),
              ),
            ),
          ),
        ),
      ));
      _expectNoLayoutError(tester, '$label 칸');
    });

    testWidgets('$label — 지우기 화면(10곳·큰 칸 수·사유) + 확인 팝업', (tester) async {
      await _setSize(tester, size);
      final supervisor = _FakeSupervisor()..robot();
      await tester.pumpWidget(
        _host(supervisor, const MapEraseScreen(map: _map)),
      );
      final canvas = tester.widget<MapCanvas>(find.byType(MapCanvas));
      for (var i = 0; i < 11; i++) {
        canvas.onKeepoutPanStart!(Offset(i.toDouble(), 0));
        canvas.onKeepoutPanUpdate!(Offset(i + 0.5, 0.5));
        canvas.onKeepoutPanEnd!();
        await tester.pump();
      }
      await tester.pump();
      _expectNoLayoutError(tester, '$label 지우기');

      await tester.tap(find.text(vicaKeepWords('지도 이동')));
      await tester.pump();
      _expectNoLayoutError(tester, '$label 지우기·지도 이동');

      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '지우기'))
          .onPressed!();
      await tester.pumpAndSettle();
      expect(find.text(vicaKeepWords('선택한 구역을 지울까요?')), findsOneWidget);
      _expectNoLayoutError(tester, '$label 지우기 확인');
    });

    testWidgets('$label — 다시 스캔: 준비(두 줄 사유)·스캔 중·미리보기·못 할 때', (tester) async {
      await _setSize(tester, size);
      final supervisor = _FakeSupervisor()..robot();
      supervisor.replies['scan_check'] = _ok({
        'ok': false,
        'reason': 'ambiguous',
        'score': 88.0,
        'ambiguous': ['forward', 'lateral', 'yaw'],
        'hits': <Object?>[],
      });
      await tester.pumpWidget(
        _host(supervisor, const MapRescanScreen(map: _map)),
      );
      await tester.pump();
      await tester.pump();
      _expectNoLayoutError(tester, '$label 준비');

      supervisor.handleMapFixStateForTest({
        'session': 's1',
        'map_id': 'map_a',
        'phase': 'scanning',
        'remaining_s': 5,
        'radius_m': 3.0,
        'moved_m': 0.29,
        'moved_deg': 9.9,
      });
      await tester.pump();
      _expectNoLayoutError(tester, '$label 스캔 중');

      supervisor.handleMapFixStateForTest({
        'session': 's1',
        'map_id': 'map_a',
        'phase': 'preview',
        'radius_m': 3.0,
        'added': 1999,
        'removed': 1888,
        'score_before': 100.0,
        'score_after': 100.0,
        'ambiguous': ['forward', 'lateral'],
        'cells': [
          for (var i = 0; i < 200; i++) [i * 0.05, 1.0, i.isEven ? 1 : -1],
        ],
      });
      await tester.pump();
      _expectNoLayoutError(tester, '$label 미리보기');

      supervisor.handleMapFixStateForTest({
        'session': 's1',
        'map_id': 'map_a',
        'phase': 'failed',
        'reason': 'ambiguous',
        'score': 88.0,
        'ambiguous': ['forward', 'lateral', 'yaw'],
      });
      await tester.pumpAndSettle();
      expect(
        find.text(vicaKeepWords('여기서는 다시 스캔할 수 없습니다')),
        findsOneWidget,
      );
      _expectNoLayoutError(tester, '$label 못 할 때 팝업');
    });

    testWidgets('$label — 되돌리기 팝업과 미션 알림 끝 알림', (tester) async {
      await _setSize(tester, size);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () {
                  unawaited(showVicaConfirm(
                    context,
                    icon: Icons.undo,
                    title: vicaKeepWords('마지막 수정을 되돌릴까요?'),
                    confirmLabel: '되돌리기',
                    danger: true,
                  ));
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(
                      [
                        '지도를 수정했습니다. 위치 맞춤 100 % → 100 %',
                        ...kMapFixMissionStaleText.split('\n'),
                      ].map(vicaKeepWords).join('\n'),
                    ),
                  ));
                },
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      _expectNoLayoutError(tester, '$label 되돌리기·끝 알림');
    });
  }
}
