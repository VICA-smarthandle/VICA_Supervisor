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

  /// 지도(위, 고정, 높이 약 3분의 1) + 설정 칸(아래, 따로 스크롤). 폰은 지도만 고정합니다.
  pinnedTop,
}

/// [MapWorkLayout] 이 지도 판으로 알아보게 감싸는 칸입니다. ResponsiveMapFrame 을 바로
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
  final String? title;
  final bool showTitleWhenWide;

  /// VicaPage 에 넘기던 것과 같은 목록입니다.
  final List<Widget> children;

  /// 창 크기로 배치를 고릅니다. 지도 모드는 미리보기를 단계 칸 밖으로 꺼낼지 먼저
  static MapWorkArrangement arrangementFor(
    BoxConstraints constraints, {
    double keyboard = 0,
  }) {
    final width = constraints.maxWidth;
    final height = constraints.maxHeight + keyboard;
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
    if (width < height &&
        width < VicaBreakpoints.compact &&
        height >= VicaBreakpoints.mapPinnedTopPhoneMinHeight) {
      return MapWorkArrangement.pinnedTop;
    }
    return MapWorkArrangement.stacked;
  }

  /// 열린 키보드 높이(논리 px). Scaffold 가 본문 MediaQuery 에서 키보드 높이를 지우므로
  static double keyboardInset(BuildContext context) {
    final view = View.maybeOf(context);
    if (view == null || view.devicePixelRatio <= 0) {
      return 0;
    }
    return view.viewInsets.bottom / view.devicePixelRatio;
  }

  static bool _isPhone(BoxConstraints constraints) =>
      constraints.maxWidth < VicaBreakpoints.compact;

  static double _contentWidth(double width) => math.min(
        width - VicaBreakpoints.horizontalPadding(width) * 2,
        VicaBreakpoints.contentMaxWidth,
      );

  static bool _isMap(Widget widget) =>
      widget is ResponsiveMapFrame ||
      widget is DriveMapCanvas ||
      widget is MapWorkMap;

  /// 지도 바로 뒤의 빈칸. 지금 배치에서 지도와 카드 사이를 띄우던 것이라 설정 칸
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
        final keyboard = keyboardInset(context);
        final arrangement = arrangementFor(constraints, keyboard: keyboard);
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
              : _isPhone(constraints)
                  ? _pinnedTopPhone(
                      context, constraints, keyboard, above, map, side)
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

  /// 폰 세로(A안): 지도만 고정하고, 지도 위 줄은 스크롤 칸 맨 위로 옮깁니다. 키보드가 열린
  Widget _pinnedTopPhone(
    BuildContext context,
    BoxConstraints constraints,
    double keyboard,
    List<Widget> above,
    Widget map,
    List<Widget> side,
  ) {
    final mapHeight = ((constraints.maxHeight + keyboard) / 3)
        .clamp(
          VicaBreakpoints.mapPinnedTopMinMapHeight,
          VicaBreakpoints.mapPinnedTopMaxMapHeight,
        )
        .toDouble();
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRect(
          child: AnimatedAlign(
            alignment: Alignment.topCenter,
            heightFactor: keyboard > 0 ? 0 : 1,
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: SizedBox(height: mapHeight, child: map),
            ),
          ),
        ),
        Expanded(child: _scrolling([...above, ...side], top: 8)),
      ],
    );
  }

  /// 설정 칸. 지금 배치(VicaPage)처럼 모든 칸을 한꺼번에 만듭니다 — 아래쪽 칸을 그때그때
  static Widget _scrolling(List<Widget> children, {double top = 0}) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(top: top, bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}
