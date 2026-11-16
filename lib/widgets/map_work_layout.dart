// 지도가 있는 화면의 배치(2026-11-09 사용자 요청·시안 승인).
//
// 폰은 지금처럼 위에서 아래로 쌓습니다(VicaPage 그대로). 넓은 가로 화면(태블릿 가로·노트북)은
// 지도를 왼쪽에 고정하고 설정 칸을 오른쪽에서 따로 스크롤합니다 — 지도가 본문 폭만큼 커져
// (최대 680px) 설정 칸이 화면 밖으로 밀리던 것을 막습니다. 세로로 든 태블릿은 지도를 위에
// 고정하고 높이를 화면의 약 3분의 1로 줄인 뒤 아래 칸만 스크롤합니다.
//
// 이 위젯은 자리만 바꿉니다. 화면이 넘긴 children 을 그대로 쓰고, 그 안에서 지도 판
// (ResponsiveMapFrame · DriveMapCanvas · MapWorkMap)을 찾아 그 앞은 '지도 위', 뒤는 '설정 칸'에
// 놓습니다. 지도 판이 없으면(지도 목록을 아직 못 받은 때) 언제나 지금 배치입니다.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/layout_breakpoints.dart';
import 'drive_map_canvas.dart';
import 'map_canvas.dart';
import 'vica_ui.dart';

/// 지도 화면을 어떻게 놓을지.
enum MapWorkArrangement {
  /// 지금 배치. 제목 → 지도 위 칸 → 지도 → 설정 칸을 한 줄로 쌓고 함께 스크롤합니다.
  stacked,

  /// 지도(왼쪽, 고정) + 설정 칸(오른쪽, 따로 스크롤).
  sideBySide,

  /// 지도(위, 고정, 높이 약 3분의 1) + 설정 칸(아래, 따로 스크롤).
  pinnedTop,
}

/// [MapWorkLayout] 이 지도 판으로 알아보게 감싸는 칸입니다. ResponsiveMapFrame 을 바로
/// 넘기지 않는 화면(지도 모드의 미리보기처럼 지도 아래 글이 붙는 경우)이 씁니다.
class MapWorkMap extends StatelessWidget {
  const MapWorkMap({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

class MapWorkLayout extends StatelessWidget {
  const MapWorkLayout({
    super.key,
    this.title,
    this.showTitleWhenWide = false,
    required this.children,
  });

  /// 지금 배치의 본문 제목. 넓은 배치에서는 머리말(또는 AppBar)이 같은 제목을 이미
  /// 보여 주므로 빼고 그 높이를 지도에 줍니다. 머리말과 다른 제목이면
  /// [showTitleWhenWide] 로 지도 위에 남깁니다.
  final String? title;
  final bool showTitleWhenWide;

  /// VicaPage 에 넘기던 것과 같은 목록입니다.
  final List<Widget> children;

  /// 창 크기로 배치를 고릅니다. 지도 모드는 미리보기를 단계 칸 밖으로 꺼낼지 먼저
  /// 알아야 해서 공개합니다.
  static MapWorkArrangement arrangementFor(BoxConstraints constraints) {
    final width = constraints.maxWidth;
    final height = constraints.maxHeight;
    if (!width.isFinite || !height.isFinite) {
      return MapWorkArrangement.stacked;
    }
    if (width >= height &&
        _contentWidth(width) >= VicaBreakpoints.mapSideBySideMinWidth &&
        height >= VicaBreakpoints.mapSideBySideMinHeight) {
      return MapWorkArrangement.sideBySide;
    }
    if (width < height &&
        width >= VicaBreakpoints.compact &&
        width < VicaBreakpoints.medium &&
        height >= VicaBreakpoints.mapPinnedTopMinHeight) {
      return MapWorkArrangement.pinnedTop;
    }
    return MapWorkArrangement.stacked;
  }

  static double _contentWidth(double width) => math.min(
        width - VicaBreakpoints.horizontalPadding(width) * 2,
        VicaBreakpoints.contentMaxWidth,
      );

  static bool _isMap(Widget widget) =>
      widget is ResponsiveMapFrame ||
      widget is DriveMapCanvas ||
      widget is MapWorkMap;

  /// 지도 바로 뒤의 빈칸. 지금 배치에서 지도와 카드 사이를 띄우던 것이라 설정 칸
  /// 맨 위에서는 뺍니다.
  static bool _isGap(Widget widget) =>
      widget is SizedBox && widget.child == null;

  @override
  Widget build(BuildContext context) {
    final mapIndex = children.indexWhere(_isMap);
    if (mapIndex < 0) {
      return VicaPage(title: title, children: children);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final arrangement = arrangementFor(constraints);
        if (arrangement == MapWorkArrangement.stacked) {
          return VicaPage(title: title, children: children);
        }
        final above = [
          if (showTitleWhenWide && title != null) ...[
            Text(title!, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 20),
          ],
          ...children.take(mapIndex),
        ];
        final map = children[mapIndex];
        final side = children.skip(mapIndex + 1).skipWhile(_isGap).toList();
        final padding = VicaBreakpoints.horizontalPadding(constraints.maxWidth);
        return Padding(
          padding: EdgeInsets.fromLTRB(padding, 16, padding, 0),
          child: arrangement == MapWorkArrangement.sideBySide
              ? _sideBySide(constraints, above, map, side)
              : _pinnedTop(constraints, above, map, side),
        );
      },
    );
  }

  Widget _sideBySide(
    BoxConstraints constraints,
    List<Widget> above,
    Widget map,
    List<Widget> side,
  ) {
    final content = _contentWidth(constraints.maxWidth);
    final sideWidth = (content * VicaBreakpoints.mapSidePanelRatio)
        .clamp(
          VicaBreakpoints.mapSidePanelMinWidth,
          VicaBreakpoints.mapSidePanelMaxWidth,
        )
        .toDouble();
    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: content,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 지도는 남는 높이를 다 쓰고 움직이지 않습니다. ResponsiveMapFrame 이 폭으로
            // 정하던 높이는 여기서 받은 높이로 바뀌고, 지도 그림은 그 안에서 비율대로
            // 가운데 놓입니다(MapCanvas).
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [...above, Expanded(child: map)],
                ),
              ),
            ),
            const SizedBox(width: 20),
            SizedBox(width: sideWidth, child: _scrolling(side)),
          ],
        ),
      ),
    );
  }

  Widget _pinnedTop(
    BoxConstraints constraints,
    List<Widget> above,
    Widget map,
    List<Widget> side,
  ) {
    final mapHeight = (constraints.maxHeight / 3)
        .clamp(
          VicaBreakpoints.mapPinnedTopMinMapHeight,
          VicaBreakpoints.mapPinnedTopMaxMapHeight,
        )
        .toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...above,
        SizedBox(height: mapHeight, child: map),
        const SizedBox(height: 14),
        Expanded(child: _scrolling(side)),
      ],
    );
  }

  /// 설정 칸. 지금 배치(VicaPage)처럼 모든 칸을 한꺼번에 만듭니다 — 아래쪽 칸을 그때그때
  /// 만들면 칸 안의 입력·선택이 스크롤할 때마다 처음으로 돌아갈 수 있습니다.
  static Widget _scrolling(List<Widget> children) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}
