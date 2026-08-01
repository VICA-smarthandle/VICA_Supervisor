// 대시보드 지표 카드의 긴 라벨이 잘리지 않고 두 줄로 표시되는지 확인합니다.
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
  // 좁은 화면(2열)에서의 카드 폭을 재현한다.
  // 화면 360 - 좌우 여백 32 - 카드 간격 12 = 316, 2열이므로 158.
  const narrowCardWidth = 158.0;

  testWidgets('오류 라벨이 두 줄로 나뉘고 잘리지 않는다', (tester) async {
    // 한 줄짜리 라벨의 높이를 기준선으로 삼는다.
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
    // 3줄 이상으로 벌어지지 않는지도 확인한다.
    expect(paragraph.size.height, lessThan(singleLineHeight * 2.5));
  });
}
