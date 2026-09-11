import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/widgets/vica_ui.dart';

const _errorLabel = '오류/\n긴급 정지';

Future<RenderParagraph> _pumpCard(
  WidgetTester tester, {
  required String label,
  required double width,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            height: 116,
            child: VicaMetricCard(
              icon: Icons.warning,
              label: label,
              value: '0',
              color: Colors.red,
              labelMaxLines: 2,
              labelFontSize: 12,
            ),
          ),
        ),
      ),
    ),
  );
  return tester.renderObject<RenderParagraph>(find.text(label));
}

void main() {
  const narrowCardWidth = 158.0;

  testWidgets('오류 라벨이 두 줄로 나뉘고 잘리지 않는다', (tester) async {
    final singleLine = await _pumpCard(
      tester,
      label: '오류',
      width: narrowCardWidth,
    );
    final singleLineHeight = singleLine.size.height;

    final paragraph = await _pumpCard(
      tester,
      label: _errorLabel,
      width: narrowCardWidth,
    );

    expect(
      paragraph.didExceedMaxLines,
      isFalse,
      reason: '라벨이 2줄 안에 들어가지 못해 말줄임표로 잘렸습니다.',
    );
    expect(
      paragraph.size.height,
      greaterThan(singleLineHeight),
      reason: '개행이 적용되지 않아 한 줄로 표시되고 있습니다.',
    );
    expect(paragraph.size.height, lessThan(singleLineHeight * 2.5));
  });
}
