// 이 파일은 지도 수정 화면이 지도 위에 얹는 그림입니다 — 지울 사각형, 스캔 반경 원, 변경된 칸.
//
// 전부 MapCanvas 의 overlayBuilder 로 들어갑니다. ROS 좌표를 지도 그림 위 자리로 바꾸는 함수
// (toPixel)를 받아 Positioned 위젯을 만들고, 지도와 함께 확대·이동됩니다. 손가락은 받지 않습니다.
import 'package:flutter/material.dart';

import '../models/map_fix.dart';
import 'vica_ui.dart';

typedef MapFixToPixel = Offset Function(double x, double y);

/// 지우기 표시색. 목업의 진한 빨강(#A2463A) — 흰 지도와 회색 미탐색 위에서 모두 보입니다.
const Color kMapFixEraseColor = Color(0xFFA2463A);

/// 새로 생긴 칸. 지도의 검은 벽과 구분되게 짙은 청록입니다.
const Color kMapFixAddedColor = Color(0xFF1F4A46);

/// 없어진 칸.
const Color kMapFixRemovedColor = VicaColors.degraded;

/// 지울 사각형들과 끄는 중인 사각형.
List<Widget> mapFixEraseOverlay(
  MapFixToPixel toPixel, {
  required List<MapFixRect> rects,
  MapFixRect? draft,
}) {
  Rect pixels(MapFixRect rect) => Rect.fromPoints(
        toPixel(rect.xMin, rect.yMin),
        toPixel(rect.xMax, rect.yMax),
      );
  return [
    for (final rect in rects)
      Positioned.fromRect(
        rect: pixels(rect),
        child: const IgnorePointer(
          child: CustomPaint(painter: _DashedRectPainter(kMapFixEraseColor)),
        ),
      ),
    if (draft != null)
      Positioned.fromRect(
        rect: pixels(draft),
        child: const IgnorePointer(
          child: CustomPaint(
            painter: _DashedRectPainter(kMapFixEraseColor, dashed: false),
          ),
        ),
      ),
    // 번호는 사각형 뒤에 그려 어느 사각형에도 가리지 않게 합니다.
    for (var i = 0; i < rects.length; i++)
      Positioned(
        left: pixels(rects[i]).left - MapFixNumberDot.mapSize / 2,
        top: pixels(rects[i]).top - MapFixNumberDot.mapSize / 2,
        child: IgnorePointer(
          child: MapFixNumberDot(number: i + 1, size: MapFixNumberDot.mapSize),
        ),
      ),
  ];
}

/// 번호 동그라미. 지도 위 사각형과 아래 목록 줄이 같은 번호를 씁니다.
class MapFixNumberDot extends StatelessWidget {
  const MapFixNumberDot({super.key, required this.number, this.size = 24});

  /// 지도 위에 놓을 때의 지름.
  static const double mapSize = 16;

  final int number;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: kMapFixEraseColor,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: Text(
        '$number',
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.5,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}

class _DashedRectPainter extends CustomPainter {
  const _DashedRectPainter(this.color, {this.dashed = true});

  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = color.withValues(alpha: 0.12));
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    if (!dashed) {
      canvas.drawRect(rect, stroke);
      return;
    }
    canvas.drawPath(_dash(Path()..addRect(rect)), stroke);
  }

  @override
  bool shouldRepaint(_DashedRectPainter old) =>
      old.color != color || old.dashed != dashed;
}

/// 선을 5 px 긋고 4 px 띄웁니다.
Path _dash(Path source, {double on = 5, double off = 4}) {
  final out = Path();
  for (final metric in source.computeMetrics()) {
    var at = 0.0;
    while (at < metric.length) {
      out.addPath(metric.extractPath(at, at + on), Offset.zero);
      at += on + off;
    }
  }
  return out;
}

/// 스캔 반경 원의 모양. 단계마다 다릅니다(목업 78·79·80).
enum MapFixCircleStyle {
  /// 범위를 고르는 중 — 옅은 청록 채움, 점선.
  range,

  /// 물러나기·스캔 중 — 주황 채움, 실선. '이 원 밖으로'.
  keepOut,

  /// 미리보기 — 채움 없이 가는 회색 점선.
  outline,
}

/// 로봇 자리([x], [y])를 중심으로 반경 [radiusM] 원과 글자.
List<Widget> mapFixRadiusOverlay(
  MapFixToPixel toPixel, {
  required double x,
  required double y,
  required double radiusM,
  required MapFixCircleStyle style,
  String label = '',
}) {
  final centre = toPixel(x, y);
  // 지도 설정의 배율·뒤집기가 그대로 들어가도록 좌표 두 개의 화면 거리로 반지름을 구합니다.
  final radius = (toPixel(x + radiusM, y) - centre).distance;
  if (radius <= 0) {
    return const [];
  }
  final keepOut = style == MapFixCircleStyle.keepOut;
  return [
    Positioned.fromRect(
      rect: Rect.fromCircle(center: centre, radius: radius),
      child: IgnorePointer(child: CustomPaint(painter: _CirclePainter(style))),
    ),
    if (label.isNotEmpty)
      Positioned(
        // 범위 글자는 원의 오른쪽 가장자리, '이 원 밖으로'는 로봇 아래에 둡니다.
        left: keepOut ? centre.dx - 60 : centre.dx + radius * 0.55,
        top: keepOut ? centre.dy + radius * 0.45 : centre.dy - 9,
        width: keepOut ? 120 : null,
        child: IgnorePointer(
          child: Align(
            alignment: keepOut ? Alignment.topCenter : Alignment.topLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                  color: keepOut
                      ? const Color(0xFF7A3F14)
                      : VicaColors.primaryDark,
                ),
              ),
            ),
          ),
        ),
      ),
  ];
}

class _CirclePainter extends CustomPainter {
  const _CirclePainter(this.style);

  final MapFixCircleStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final Color? fill = switch (style) {
      MapFixCircleStyle.range => VicaColors.primary.withValues(alpha: 0.10),
      MapFixCircleStyle.keepOut => VicaColors.degraded.withValues(alpha: 0.18),
      MapFixCircleStyle.outline => null,
    };
    if (fill != null) {
      canvas.drawOval(rect, Paint()..color = fill);
    }
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = style == MapFixCircleStyle.keepOut ? 2 : 1.5
      ..color = switch (style) {
        MapFixCircleStyle.range => VicaColors.primaryDark,
        MapFixCircleStyle.keepOut => const Color(0xFF9A5422),
        MapFixCircleStyle.outline => VicaColors.muted,
      };
    final path = Path()..addOval(rect.deflate(stroke.strokeWidth / 2));
    canvas.drawPath(
      style == MapFixCircleStyle.keepOut ? path : _dash(path),
      stroke,
    );
  }

  @override
  bool shouldRepaint(_CirclePainter old) => old.style != style;
}

/// 부분 스캔으로 변경된 칸. 칸 수가 많아도(최대 2000) 그림 한 장으로 그립니다.
List<Widget> mapFixCellsOverlay(
  MapFixToPixel toPixel, {
  required List<MapFixCell> cells,
  required double resolution,
}) {
  if (cells.isEmpty) {
    return const [];
  }
  final half = resolution / 2;
  final added = <Rect>[];
  final removed = <Rect>[];
  for (final cell in cells) {
    final rect = Rect.fromPoints(
      toPixel(cell.x - half, cell.y - half),
      toPixel(cell.x + half, cell.y + half),
    );
    (cell.added ? added : removed).add(rect);
  }
  return [
    Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _CellsPainter(added: added, removed: removed),
        ),
      ),
    ),
  ];
}

class _CellsPainter extends CustomPainter {
  const _CellsPainter({required this.added, required this.removed});

  final List<Rect> added;
  final List<Rect> removed;

  // 확대하지 않은 폰 화면에서는 한 칸(5 cm)이 1 px 이 안 됩니다. 이만큼은 키워 보이게 합니다.
  static const double _minSide = 2;

  static Rect _visible(Rect rect) => rect.shortestSide >= _minSide
      ? rect
      : Rect.fromCenter(
          center: rect.center,
          width: rect.width < _minSide ? _minSide : rect.width,
          height: rect.height < _minSide ? _minSide : rect.height,
        );

  @override
  void paint(Canvas canvas, Size size) {
    // 없어진 칸을 먼저 깔고 새로 생긴 칸을 위에 그립니다.
    final gone = Paint()..color = kMapFixRemovedColor.withValues(alpha: 0.55);
    for (final rect in removed) {
      canvas.drawRect(_visible(rect), gone);
    }
    final fresh = Paint()..color = kMapFixAddedColor;
    for (final rect in added) {
      canvas.drawRect(_visible(rect), fresh);
    }
  }

  @override
  bool shouldRepaint(_CellsPainter old) =>
      !identical(old.added, added) || !identical(old.removed, removed);
}
