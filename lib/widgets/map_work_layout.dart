// 지도가 있는 화면의 배치(2026-11-09 사용자 요청·시안 승인).
//
// 넓은 가로 화면(태블릿 가로·노트북)은 지도를 왼쪽에 고정하고 설정 칸을 오른쪽에서 따로
// 스크롤합니다 — 지도가 본문 폭만큼 커져(최대 680px) 설정 칸이 화면 밖으로 밀리던 것을 막습니다.
// 세로로 든 태블릿은 지도를 위에 고정하고 높이를 화면의 약 3분의 1로 줄인 뒤 아래 칸만
// 스크롤합니다.
//
// 폰 세로(2026-11-19 사용자, 목업 RXMvVxPh A안)도 지도를 위에 고정합니다. 폰은 세로 태블릿과
// 두 가지가 다릅니다.
// - 지도만 고정합니다. 지도 위에 있던 줄(지도 고르기·안 맞음 띠·목적지/수동 버튼)은 스크롤 칸
//   맨 위로 옮깁니다. 같이 고정하면 고정 부분이 본문의 절반을 넘습니다.
// - 키보드가 열린 동안은 지도를 접습니다. 칸을 빼지 않고 높이만 0 으로 줄여서 입력 칸이
//   초점과 글을 잃지 않습니다. 배치도 키보드를 뺀 높이로 정해서 키보드 때문에 바뀌지 않습니다.
// 작은 폰(본문 < 560px)과 폰 가로는 지금처럼 위에서 아래로 쌓습니다(VicaPage 그대로).
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

  /// 지도(위, 고정, 높이 약 3분의 1) + 설정 칸(아래, 따로 스크롤). 폰은 지도만 고정합니다.
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
  ///
  /// [keyboard] 는 열린 키보드 높이([keyboardInset])입니다. 키보드가 본문을 줄여도 줄기 전
  /// 높이로 고릅니다 — 키보드 때문에 배치가 바뀌면 입력 칸이 초점을 잃고 키보드가 닫힙니다.
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
  /// 화면(View)에서 바로 읽습니다.
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
                  ? _pinnedTopPhone(context, constraints, keyboard, above, map, side)
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

  /// 폰 세로(A안): 지도만 고정하고, 지도 위 줄은 스크롤 칸 맨 위로 옮깁니다. 키보드가 열린
  /// 동안은 지도를 접습니다. 접어도 칸은 그대로 두고 보이는 높이만 0 으로 줄입니다(ClipRect +
  /// heightFactor) — 지도는 원래 크기로 그려진 채 잘려서 0 크기 배치를 겪지 않고, 접힌 지도는
  /// 눌리지도 않습니다.
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
        // 위 여백 8: 맨 위 칸이 지도 고르기 줄이면 그 떠 있는 이름표('지도 선택')가 칸 테두리
        // 위로 올라와 스크롤 칸 경계에 잘렸습니다(2026-11-19 캡처).
        Expanded(child: _scrolling([...above, ...side], top: 8)),
      ],
    );
  }

  /// 설정 칸. 지금 배치(VicaPage)처럼 모든 칸을 한꺼번에 만듭니다 — 아래쪽 칸을 그때그때
  /// 만들면 칸 안의 입력·선택이 스크롤할 때마다 처음으로 돌아갈 수 있습니다.
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
