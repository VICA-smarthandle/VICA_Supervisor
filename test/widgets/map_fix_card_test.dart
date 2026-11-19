// 지도 설정의 '지도 수정' 칸 — 상태 단어·버튼 잠금·최근 수정 줄·끝 알림 문구를 고정합니다.
//
// 잠금의 주인은 로봇(map_fix_node)입니다. 이 칸은 로봇이 준 답대로 버튼을 끄고 켭니다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/models/map_fix.dart';
import 'package:vica_supervisor/widgets/map_fix_card.dart';
import 'package:vica_supervisor/widgets/vica_ui.dart';

const _free = MapFixStatus(lock: '', canScan: true);
const _locked = MapFixStatus(lock: 'busy_driving', canScan: false);
const _otherMap = MapFixStatus(lock: '', canScan: false);

const _twoEdits = MapFixStatus(
  lock: '',
  canScan: true,
  history: [
    MapFixHistoryEntry(
      at: '2026-11-18T15:42:07',
      kind: 'scan',
      radiusM: 2.0,
      added: 41,
      removed: 28,
    ),
    MapFixHistoryEntry(
      at: '2026-11-18T15:31:00',
      kind: 'erase',
      black: 19,
      gray: 3,
      rectCount: 3,
    ),
  ],
);

Widget _card({
  bool connected = true,
  MapFixStatus? status = _free,
  bool driving = false,
  bool busy = false,
  String note = '',
  VoidCallback? onUndo,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: MapFixCard(
          connected: connected,
          status: status,
          driving: driving,
          busy: busy,
          note: note,
          onErase: () {},
          onScan: () {},
          onUndo: onUndo ?? () {},
        ),
      ),
    ),
  );
}

// OutlinedButton.icon·FilledButton.icon 은 하위 타입을 만들므로 predicate 로 찾습니다.
ButtonStyleButton _button(WidgetTester tester, String text) {
  return tester.widget<ButtonStyleButton>(
    find
        .ancestor(
          of: find.text(text),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        )
        .first,
  );
}

MapFixResult _result(Map<String, Object?> result, {String message = ''}) =>
    MapFixResult(accepted: true, reason: '', message: message, result: result);

void main() {
  test('연결이 없으면 오프라인, 잠기면 주행 중, 아니면 가능', () {
    expect(mapFixStateWord(connected: false, status: _free), '오프라인');
    expect(mapFixStateWord(connected: true, status: _locked), '주행 중');
    expect(mapFixStateWord(connected: true, status: _free), '가능');
    // 목적지를 쥐고 있으면 로봇에 다시 묻지 않고도 주행 중입니다.
    expect(
      mapFixStateWord(connected: true, status: _free, driving: true),
      '주행 중',
    );
    // 아직 로봇에 묻지 않았으면 단어가 없습니다.
    expect(mapFixStateWord(connected: true, status: null), '');
    // 로봇 상태를 못 받아 잠긴 것은 주행 중이라고 하지 않습니다.
    expect(
      mapFixStateWord(
        connected: true,
        status: const MapFixStatus(lock: 'no_status', canScan: false),
      ),
      '확인 불가',
    );
  });

  testWidgets('평소에는 두 버튼이 켜져 있다', (tester) async {
    await tester.pumpWidget(_card());
    expect(_button(tester, '지우기').onPressed, isNotNull);
    expect(_button(tester, '부분 스캔').onPressed, isNotNull);
    expect(find.text(vicaKeepWords('변경된 곳만 지우거나 다시 스캔합니다')), findsOneWidget);
  });

  testWidgets('잠기면 두 버튼이 꺼진다', (tester) async {
    await tester.pumpWidget(_card(status: _locked));
    expect(_button(tester, '지우기').onPressed, isNull);
    expect(_button(tester, '부분 스캔').onPressed, isNull);
  });

  testWidgets('연결이 없거나 답을 못 받았거나 요청 중이면 두 버튼이 꺼진다', (tester) async {
    for (final card in [
      _card(connected: false),
      _card(status: null),
      _card(busy: true),
      _card(driving: true),
    ]) {
      await tester.pumpWidget(card);
      expect(_button(tester, '지우기').onPressed, isNull);
      expect(_button(tester, '부분 스캔').onPressed, isNull);
    }
  });

  testWidgets('주행 지도가 아니면 부분 스캔만 꺼지고 이유가 보인다', (tester) async {
    await tester.pumpWidget(_card(status: _otherMap));
    expect(_button(tester, '지우기').onPressed, isNotNull);
    expect(_button(tester, '부분 스캔').onPressed, isNull);
    expect(find.text(vicaKeepWords('주행 지도에서만 부분 스캔할 수 있습니다')), findsOneWidget);

    await tester.pumpWidget(_card());
    expect(find.text(vicaKeepWords('주행 지도에서만 부분 스캔할 수 있습니다')), findsNothing);
  });

  testWidgets('기록이 없으면 최근 수정 줄이 없다', (tester) async {
    await tester.pumpWidget(_card());
    expect(find.text('최근 수정'), findsNothing);
    expect(find.text('되돌리기'), findsNothing);
  });

  testWidgets('되돌리기는 맨 윗줄에만 있다', (tester) async {
    var undone = 0;
    await tester.pumpWidget(_card(status: _twoEdits, onUndo: () => undone++));

    expect(find.text('최근 수정'), findsOneWidget);
    expect(find.text(vicaKeepWords('부분 스캔 · 2 m')), findsOneWidget);
    expect(
      find.text(vicaKeepWords('11-18 15:42 · 새로 41칸 · 없어짐 28칸')),
      findsOneWidget,
    );
    expect(find.text(vicaKeepWords('지우기 · 3곳')), findsOneWidget);
    expect(
      find.text(vicaKeepWords('11-18 15:31 · 검은 칸 19개 · 회색 칸 3개')),
      findsOneWidget,
    );
    expect(find.text('되돌리기'), findsOneWidget);

    await tester.tap(find.text('되돌리기'));
    expect(undone, 1);
  });

  testWidgets('실패 문구가 있으면 칸에 보인다', (tester) async {
    await tester.pumpWidget(_card(note: '주행 중에는 지도를 수정할 수 없습니다.'));
    expect(find.text(vicaKeepWords('주행 중에는 지도를 수정할 수 없습니다.')), findsOneWidget);
  });

  test('끝 알림 — 적용됨·저장만 됨·미션 알림 덧붙임', () {
    // 적용됨(지우기).
    expect(
      mapFixDoneMessage(
        _result({'applied': true, 'mission_stale': false}),
        done: '지웠습니다.',
      ),
      '지웠습니다.',
    );
    // 적용됨(부분 스캔) — 같은 스캔으로 잰 수정 전·후가 붙습니다.
    expect(
      mapFixDoneMessage(
        _result({
          'applied': true,
          'mission_stale': false,
          'score_before': 62.0,
          'score_after': 91.4,
        }),
      ),
      '지도를 수정했습니다. 위치 맞춤 62 % → 91 %',
    );
    // 파일만 바뀜 — 로봇이 보낸 사유가 붙습니다.
    expect(
      mapFixDoneMessage(
        _result({
          'applied': false,
          'mission_stale': false,
        }, message: '다음에 이 지도로 주행할 때 적용됩니다.'),
        done: '지웠습니다.',
      ),
      '지웠습니다. 다음에 이 지도로 주행할 때 적용됩니다.',
    );
    // 미션이 켜져 있으면 줄을 바꿔 덧붙입니다.
    expect(
      mapFixDoneMessage(_result({'applied': true, 'mission_stale': true})),
      '지도를 수정했습니다.\n미션 매니저에는 반영되지 않았습니다. 주행을 껐다 켜면 반영됩니다.',
    );
  });
}
