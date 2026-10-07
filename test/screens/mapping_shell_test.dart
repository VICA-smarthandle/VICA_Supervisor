// 매핑 4단계 화면의 진행과 차단 규칙을 고정합니다.
//
// ①단계가 이 화면의 존재 이유입니다. 매핑은 시작하면 되돌릴 수 없는 일이고,
// 이 프로젝트는 그 30분을 실제로 여러 번 잃었습니다.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vica_supervisor/core/app_settings.dart';
import 'package:vica_supervisor/providers/app_mode_provider.dart';
import 'package:vica_supervisor/providers/auth_provider.dart';
import 'package:vica_supervisor/providers/settings_provider.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';
import 'package:vica_supervisor/screens/mapping_shell.dart';
import 'package:vica_supervisor/widgets/vica_ui.dart';

class _FakeSupervisor extends SupervisorProvider {
  // 저장 요청을 젯슨에 보내지 않고 기록만 합니다(2026-10-07 정렬 팝업 시험).
  final saveCalls = <({String name, bool align})>[];

  @override
  Future<String> saveMap(
    AppSettings settings,
    String name, {
    bool align = false,
  }) async {
    saveCalls.add((name: name, align: align));
    return '저장을 시작했습니다.';
  }

  void injectEstop(Map<String, Object?> json) =>
      handleEmergencyStopStateForTest(json);

  void injectStatus(Map<String, Object?> json) =>
      handleMappingStatusForTest({'data': _encode(json)});

  void injectPreview(Map<String, Object?> json) =>
      handleMapPreviewForTest({'data': _encode(json)});

  // save_align 처럼 안에 묶음이 든 값도 보내야 해서 jsonEncode 를 씁니다.
  static String _encode(Map<String, Object?> json) => jsonEncode(json);
}

Map<String, Object?> previewJson({bool withRobot = false, double? tilt}) {
  return {
    'image_url': '/maps/_live/preview.png',
    'seq': 1,
    'width': 40,
    'height': 30,
    'resolution': 0.05,
    'origin_x': -1.5,
    'origin_y': -2.5,
    'bytes': 4533,
    if (withRobot) ...{'robot_x': 0.5, 'robot_y': 0.25, 'robot_yaw': 90.0},
    if (tilt != null) 'tilt_deg': tilt,
  };
}

Map<String, Object?> statusJson({
  String state = 'idle',
  bool nav2 = false,
  List<String> duplicated = const [],
  List<String> missing = const [],
  String detail = '',
  String mapId = '',
  Map<String, Object?>? saveAlign,
}) {
  return {
    'state': state,
    'detail': detail,
    'map_id': mapId,
    if (saveAlign != null) 'save_align': saveAlign,
    'nav2_running': nav2,
    'mapping_running': state == 'mapping',
    'duplicated': duplicated,
    'prerequisites_missing': missing,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<_FakeSupervisor> pump(
    WidgetTester tester, {
    Map<String, Object?>? status,
  }) async {
    final supervisor = _FakeSupervisor();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 2600);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SupervisorProvider>.value(value: supervisor),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ChangeNotifierProvider(create: (_) => AppModeProvider()),
          ChangeNotifierProvider(create: (_) => AuthProvider()),
        ],
        child: const MaterialApp(home: MappingShell()),
      ),
    );
    await tester.pump();
    if (status != null) {
      supervisor.injectStatus(status);
      await tester.pump();
    }
    return supervisor;
  }

  testWidgets('상태를 못 받았으면 감독 노드를 확인하라고 알린다', (tester) async {
    await pump(tester);
    expect(
      find.textContaining(vicaKeepWords('mapping_supervisor_node')),
      findsOneWidget,
    );
  });

  testWidgets('네 단계를 모두 보여준다', (tester) async {
    await pump(tester, status: statusJson());
    for (final title in ['준비 확인', '작성 중', '저장', '완료']) {
      expect(find.text(title), findsOneWidget);
    }
  });

  testWidgets('E-stop 확인 전에는 시작할 수 없다', (tester) async {
    // AGENTS.md 5절 — 물리 E-stop 확인은 사람만 할 수 있다.
    await pump(tester, status: statusJson());

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '매핑 시작'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('E-stop 을 확인하면 시작할 수 있다', (tester) async {
    await pump(tester, status: statusJson());

    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '매핑 시작'),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('Nav2 가 떠 있으면 이유를 적고 시작을 막는다', (tester) async {
    await pump(tester, status: statusJson(nav2: true));

    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    expect(find.textContaining(vicaKeepWords('Nav2 가 실행 중')), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '매핑 시작'),
    );
    expect(button.onPressed, isNull, reason: 'E-stop 을 확인해도 막혀 있어야 한다');
  });

  testWidgets('노드가 두 벌이면 무엇이 겹쳤는지 적는다', (tester) async {
    await pump(
      tester,
      status: statusJson(duplicated: ['ekf_filter_node']),
    );
    expect(
        find.textContaining(vicaKeepWords('ekf_filter_node')), findsOneWidget);
  });

  testWidgets('선행 노드가 빠져 있으면 무엇이 없는지 적는다', (tester) async {
    // d455·imu 는 앱이 안 띄운다. 없으면 회차가 무효가 되므로 확인은 한다.
    await pump(
      tester,
      status: statusJson(missing: ['imu_base_link_adapter']),
    );
    expect(find.textContaining(vicaKeepWords('imu_base_link_adapter')),
        findsOneWidget);
  });

  testWidgets('그리는 중이면 2단계로 넘어가고 조작판이 열린다', (tester) async {
    await pump(tester, status: statusJson(state: 'mapping'));

    expect(find.textContaining(vicaKeepWords('지도를 띄우는 중입니다')), findsOneWidget);
    expect(find.bySemanticsLabel('앞으로'), findsOneWidget);
    // 1단계 내용은 접혀 있어야 한다.
    expect(find.widgetWithText(FilledButton, '매핑 시작'), findsNothing);
  });

  testWidgets('미리보기에 로봇 자세가 실려 오면 화살표를 그린다', (tester) async {
    // RViz 처럼 어디를 그리고 있는지 보이게 한다. 자세는 /robot_status 가 아니라
    // 미리보기 JSON 에서 온다 — 매핑 중엔 그쪽 위치가 /odom 좌표라 못 쓴다.
    final supervisor = await pump(tester, status: statusJson(state: 'mapping'));
    supervisor.injectPreview(previewJson(withRobot: true));
    await tester.pump();

    expect(find.byTooltip('로봇 위치'), findsOneWidget);
    expect(find.textContaining('로봇 위치 없음'), findsNothing);
  });

  testWidgets('로봇 자세가 없으면 화살표 대신 그 사실을 적는다', (tester) async {
    // Cartographer 가 아직 안 떴거나 /tracked_pose 가 꺼져 있을 때. 화살표만
    // 조용히 빠지면 관리자가 지도 문제로 오해한다.
    final supervisor = await pump(tester, status: statusJson(state: 'mapping'));
    supervisor.injectPreview(previewJson());
    await tester.pump();

    expect(find.byTooltip('로봇 위치'), findsNothing);
    expect(find.textContaining('로봇 위치 없음'), findsOneWidget);
  });

  testWidgets('매핑 중에는 모드를 바꿀 수 없다', (tester) async {
    await pump(tester, status: statusJson(state: 'mapping'));

    await tester.tap(find.widgetWithText(TextButton, '모드 바꾸기'));
    await tester.pumpAndSettle();

    expect(find.text('매핑이 진행 중입니다'), findsOneWidget);
  });

  testWidgets('비상정지가 안 걸려 있으면 해제 카드를 그리지 않는다', (tester) async {
    await pump(tester, status: statusJson());
    expect(find.textContaining('비상정지가 걸려 있습니다'), findsNothing);
  });

  testWidgets('비상정지가 걸려 있으면 해제 버튼을 준다', (tester) async {
    // 래치는 기동 직후 latched 로 시작한다. 풀지 않으면 /cmd_vel_safe 가 안 나가
    // 로봇을 끌고 다닐 수 없어 지도 작성 자체가 시작되지 않는다.
    final supervisor = await pump(tester, status: statusJson());
    supervisor.injectEstop({'active': true});
    await tester.pump();

    expect(find.text('비상정지가 걸려 있습니다'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '비상정지 해제'),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('해제 카드가 선행 조건을 적어 둔다', (tester) async {
    // motor 가 없으면 motor_can_stale 이 남아 reset 이 거부된다. 고장이 아니라 설계다.
    final supervisor = await pump(tester, status: statusJson());
    supervisor.injectEstop({'active': true});
    await tester.pump();

    expect(find.textContaining(vicaKeepWords('safety 와 motor 가 먼저')),
        findsOneWidget);
  });

  testWidgets('대기 상태면 모드를 바꿀 수 있다', (tester) async {
    await pump(tester, status: statusJson());

    await tester.tap(find.widgetWithText(TextButton, '모드 바꾸기'));
    await tester.pumpAndSettle();

    expect(find.text('매핑이 진행 중입니다'), findsNothing);
  });

  // -- 지도 정렬(2026-10-07, 목업 12~14번) ------------------------------------

  testWidgets('준비 확인에 시작 방향 안내가 있다', (tester) async {
    await pump(tester, status: statusJson());
    expect(
      find.textContaining(vicaKeepWords('로봇 앞을 내 오른쪽(시계방향 90°)으로')),
      findsOneWidget,
    );
    // 목업 12번 아래 세 줄.
    for (final words in ['방향 하나만 기준입니다', '확인법:', '마무리합니다.']) {
      expect(find.textContaining(vicaKeepWords(words)), findsOneWidget);
    }
    // 목업 12번의 굵은 글씨 다섯 곳.
    final bold = <String>[];
    for (final widget in tester.widgetList<RichText>(find.byType(RichText))) {
      widget.text.visitChildren((span) {
        if (span is TextSpan && span.style?.fontWeight == FontWeight.w800) {
          bold.add((span.text ?? '').replaceAll('\u2060', ''));
        }
        return true;
      });
    }
    for (final words in [
      '위쪽',
      '내 오른쪽',
      "'매핑 시작'을 누르는 순간",
      '오른쪽',
      "'정렬해서 저장'",
    ]) {
      expect(bold, contains(words));
    }
  });

  Future<_FakeSupervisor> openSaveStep(
    WidgetTester tester, {
    double? tilt,
  }) async {
    final supervisor = await pump(tester, status: statusJson(state: 'mapping'));
    supervisor.injectPreview(previewJson(tilt: tilt));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '지도 작성 완료'));
    await tester.pump();
    return supervisor;
  }

  testWidgets('저장을 누르면 세 가지를 묻고 지금 기울기를 보인다', (tester) async {
    await openSaveStep(tester, tilt: -5.5);
    await tester.enterText(find.byType(TextField), '복지관');
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();

    expect(find.text(vicaKeepWords('지도를 바르게 세워 저장할까요?')), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '정렬해서 저장'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '정렬하지 않고 저장'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '취소'), findsOneWidget);
    expect(find.text('지금 기울기'), findsOneWidget);
    expect(find.text(vicaKeepWords('약 5.5°')), findsOneWidget);
    // 안내 상자의 '2° 미만'은 굵게(목업 13번). Text.rich 는 조각을 한 겹 더 감싸
    // 넣으므로 전부 훑어 찾습니다.
    final bold = <TextSpan>[];
    for (final widget in tester.widgetList<RichText>(find.byType(RichText))) {
      widget.text.visitChildren((span) {
        if (span is TextSpan &&
            (span.text ?? '').startsWith(vicaKeepWords('2° 미만'))) {
          bold.add(span);
        }
        return true;
      });
    }
    expect(bold.single.style?.fontWeight, FontWeight.w800);
  });

  testWidgets('기울기를 못 쟀으면 그 줄을 숨긴다', (tester) async {
    await openSaveStep(tester);
    await tester.enterText(find.byType(TextField), '복지관');
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();

    // '지도 이름'은 입력칸 라벨에도 있어 팝업 안에서만 찾습니다.
    final inDialog = find.descendant(
      of: find.byType(Dialog),
      matching: find.text('지도 이름'),
    );
    expect(inDialog, findsOneWidget);
    expect(find.text('지금 기울기'), findsNothing);
  });

  testWidgets('정렬해서 저장은 align 을 켜서 보낸다', (tester) async {
    final supervisor = await openSaveStep(tester, tilt: 5.5);
    await tester.enterText(find.byType(TextField), '복지관');
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '정렬해서 저장'));
    await tester.pumpAndSettle();

    expect(supervisor.saveCalls, [(name: '복지관', align: true)]);
  });

  testWidgets('정렬하지 않고 저장은 align 을 끄고 보낸다', (tester) async {
    final supervisor = await openSaveStep(tester, tilt: 5.5);
    await tester.enterText(find.byType(TextField), '복지관');
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, '정렬하지 않고 저장'));
    await tester.pumpAndSettle();

    expect(supervisor.saveCalls, [(name: '복지관', align: false)]);
  });

  testWidgets('취소하면 저장하지 않는다', (tester) async {
    final supervisor = await openSaveStep(tester, tilt: 5.5);
    await tester.enterText(find.byType(TextField), '복지관');
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '취소'));
    await tester.pumpAndSettle();

    expect(supervisor.saveCalls, isEmpty);
    expect(find.text(vicaKeepWords('지도를 바르게 세워 저장할까요?')), findsNothing);
  });

  testWidgets('이름이 비었으면 묻지 않고 이름부터 달라고 한다', (tester) async {
    final supervisor = await openSaveStep(tester, tilt: 5.5);
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();

    expect(find.text(vicaKeepWords('지도를 바르게 세워 저장할까요?')), findsNothing);
    expect(find.text('지도 이름을 입력해 주세요.'), findsOneWidget);
    expect(supervisor.saveCalls, isEmpty);
  });

  testWidgets('완료 단계에 바르게 세운 결과를 한 줄로 보인다', (tester) async {
    await pump(
      tester,
      status: statusJson(
        state: 'mapping',
        detail: '복지관 (map_1007_143012) 저장 완료.',
        mapId: 'map_1007_143012',
        saveAlign: {'result': 'rotated', 'tilt_deg': 5.5, 'rotated_deg': -5.5},
      ),
    );
    expect(
      find.text(vicaKeepWords('지도를 5.5° 돌려 바르게 세웠습니다.')),
      findsOneWidget,
    );
  });

  testWidgets('옛 감독 노드(결과 없음)면 결과 줄 없이 저장만 알린다', (tester) async {
    await pump(
      tester,
      status: statusJson(
        state: 'mapping',
        detail: 'lobby_1007 저장 완료.',
        mapId: 'lobby_1007',
      ),
    );
    // 화면 글자는 vicaKeepWords 를 거쳐 있어 같은 처리를 한 말로 찾아야 합니다 —
    // 그냥 찾으면 '없다' 검사가 늘 통과해 버립니다.
    expect(find.textContaining(vicaKeepWords('저장했습니다:')), findsOneWidget);
    expect(find.textContaining(vicaKeepWords('바르게 세웠습니다')), findsNothing);
    expect(find.textContaining(vicaKeepWords('그대로 저장했습니다')), findsNothing);
  });

  testWidgets('좁은 폰 폭(360)에서도 팝업이 넘치지 않는다', (tester) async {
    final supervisor = await openSaveStep(tester, tilt: 5.5);
    tester.view.physicalSize = const Size(360, 740);
    await tester.pump();
    await tester.enterText(find.byType(TextField), '아주 긴 이름의 복지관 일층 동쪽 복도');
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await tester.tap(find.widgetWithText(OutlinedButton, '정렬하지 않고 저장'));
    await tester.pumpAndSettle();
    expect(supervisor.saveCalls.single.align, isFalse);
  });

  testWidgets('저장하는 중에는 저장 버튼이 막힌다', (tester) async {
    await pump(tester, status: statusJson(state: 'saving'));
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '저장'),
    );
    expect(button.onPressed, isNull);
  });
}
