// 금지구역 칸의 '주행 중 편집 잠금'을 고정합니다.
//
// 로봇이 목적지를 쥔 동안(주행·일시정지) 편집을 시작해 봐야 적용이 미뤄집니다.
// 그 사실을 버튼 자리에서 미리 알리는 것이 이 잠금입니다. 반대로 **이미 편집
// 중이던 사람은 계속할 수 있어야** 합니다 — 그리는 도중 음성으로 주행이 시작될
// 수 있고, 그때의 안전은 젯슨 쪽 유예 판정(keepout_mask.hold_apply)이 맡습니다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart'
    show KeepoutSaveState;
import 'package:vica_supervisor/widgets/keepout_card.dart';

Widget _card({required bool drivingHold, bool editing = false}) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: KeepoutCard(
          zones: const [],
          selectedZoneId: null,
          editing: editing,
          state: editing ? KeepoutSaveState.editing : KeepoutSaveState.idle,
          message: '',
          maskApplied: false,
          connected: true,
          drivingHold: drivingHold,
          onStartEdit: () {},
          onCancel: () {},
          onSave: () {},
          onDeleteSelected: () {},
          onClearAll: () {},
          onReload: () {},
          onSelect: (_) {},
        ),
      ),
    ),
  );
}

FilledButton _filledButtonWithText(WidgetTester tester, String text) {
  // FilledButton.icon 은 FilledButton 의 하위 타입을 만들므로 byType 대신
  // predicate 로 찾습니다.
  return tester.widget<FilledButton>(
    find
        .ancestor(
          of: find.text(text),
          matching: find.byWidgetPredicate((w) => w is FilledButton),
        )
        .first,
  );
}

void main() {
  testWidgets('평소에는 편집 시작이 열려 있다', (tester) async {
    await tester.pumpWidget(_card(drivingHold: false));
    expect(
      _filledButtonWithText(tester, '금지구역 편집').onPressed,
      isNotNull,
    );
    expect(find.text('주행 중 · 편집 잠김'), findsNothing);
  });

  testWidgets('목적지가 살아 있으면 편집 시작이 잠기고 이유가 보인다',
      (tester) async {
    await tester.pumpWidget(_card(drivingHold: true));
    expect(
      _filledButtonWithText(tester, '금지구역 편집').onPressed,
      isNull,
    );
    expect(find.text('주행 중 · 편집 잠김'), findsOneWidget);
    expect(
      find.textContaining('주행이 끝나면 열립니다'),
      findsOneWidget,
    );
  });

  testWidgets('이미 편집 중이면 주행이 시작돼도 저장할 수 있다', (tester) async {
    await tester.pumpWidget(_card(drivingHold: true, editing: true));
    expect(_filledButtonWithText(tester, '저장').onPressed, isNotNull);
  });
}
