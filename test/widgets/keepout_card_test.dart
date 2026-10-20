import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart'
    show KeepoutSaveState;
import 'package:vica_supervisor/widgets/keepout_card.dart';
import 'package:vica_supervisor/widgets/vica_ui.dart';

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
          hasPending: false,
          onStartEdit: () {},
          onConfirmPending: () {},
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

  testWidgets('목적지가 살아 있으면 편집 시작이 잠기고 이유가 보인다', (tester) async {
    await tester.pumpWidget(_card(drivingHold: true));
    expect(
      _filledButtonWithText(tester, '금지구역 편집').onPressed,
      isNull,
    );
    expect(find.text('주행 중 · 편집 잠김'), findsOneWidget);
    expect(
      find.textContaining(vicaKeepWords('주행이 끝나면 열립니다')),
      findsOneWidget,
    );
  });

  testWidgets('이미 편집 중이면 주행이 시작돼도 저장할 수 있다', (tester) async {
    await tester.pumpWidget(_card(drivingHold: true, editing: true));
    expect(_filledButtonWithText(tester, '저장').onPressed, isNotNull);
  });
}
