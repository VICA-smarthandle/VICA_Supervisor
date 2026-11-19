import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/widgets/map_fix_overlay.dart';

void main() {
  test('미리보기 칸은 최소 6 px 로 그린다(11-19 실기: 2 px 라 안 보였다, 캔버스 102)', () {
    expect(kMapFixCellMinSide, 6);
    final tiny = mapFixVisibleCell(const Rect.fromLTWH(10, 20, 0.6, 0.6));
    expect(tiny.width, 6);
    expect(tiny.height, 6);
    expect(tiny.center, const Offset(10.3, 20.3));

    const big = Rect.fromLTWH(0, 0, 9, 9); // 확대하면 실제 크기 그대로
    expect(mapFixVisibleCell(big), big);
  });
}
