// 이 파일은 지도 설정에서 목적지·대기 장소를 다룰 때 지도 위에 겹쳐 그리는 것을
// 모읍니다(2026-10-07, 목업 1·4·5·6·16번).
//
//   대기 장소      작은 네모 + 나가는 방향 화살표 + 목적지와 잇는 점선
//   입구 방향      목적지 점에서 입구 쪽으로 뻗은 화살표와 '입구' 글자
//   로봇 윤곽      대기 장소를 찍을 때·골랐을 때만. 벽 간격 판정 색으로 칠합니다
//   원래 자리      기존 목적지를 옮기는 중일 때 회색 점선 원
//
// 방향은 각도를 화면 각도로 바꾸지 않고 지도 좌표 두 점을 픽셀로 옮겨 구합니다.
// 그러면 '지도 Y축 반전' 설정이 무엇이든 위치와 방향이 같은 규칙으로 그려집니다.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/wait_spot_geometry.dart';
import 'vica_ui.dart';

class MapWaitSpotMark {
  const MapWaitSpotMark({
    required this.x,
    required this.y,
    required this.yawDeg,
    required this.destX,
    required this.destY,
    this.highlighted = false,
  });

  final double x;
  final double y;
  final double yawDeg;
  final double destX;
  final double destY;
  final bool highlighted;
}

class MapDoorArrow {
  const MapDoorArrow({required this.x, required this.y, required this.yawDeg});

  final double x;
  final double y;
  final double yawDeg;
}

class MapRobotOutline {
  const MapRobotOutline({
    required this.x,
    required this.y,
    required this.yawDeg,
    this.color = VicaColors.primary,
    this.showExitLabel = false,
  });

  final double x;
  final double y;
  final double yawDeg;
  final Color color;

  /// 화살표 옆에 '나가는 방향' 글자를 붙이는가(찍는 중, 목업 4).
  final bool showExitLabel;
}

/// 지도 좌표 → 지도 픽셀(표시 배율 포함).
typedef MapToPixel = Offset Function(double x, double y);

class WaitSpotOverlayPainter extends CustomPainter {
  WaitSpotOverlayPainter({
    required this.toPixel,
    required this.scale,
    this.waitSpots = const [],
    this.doorArrow,
    this.robotOutline,
    this.ghostPoint,
  });

  final MapToPixel toPixel;

  /// 점·선 크기 배율(폰 앱 2/3). map_canvas 의 _markerScale 과 같은 값을 받습니다.
  final double scale;
  final List<MapWaitSpotMark> waitSpots;
  final MapDoorArrow? doorArrow;
  final MapRobotOutline? robotOutline;
  final Offset? ghostPoint;

  /// 지도 좌표 (x, y) 에서 yaw 쪽을 가리키는 화면 단위 벡터.
  Offset _screenDir(double x, double y, double yawDeg) {
    final yaw = yawDeg * math.pi / 180.0;
    final a = toPixel(x, y);
    final b = toPixel(x + math.cos(yaw), y + math.sin(yaw));
    final d = b - a;
    final len = d.distance;
    return len == 0 ? const Offset(1, 0) : d / len;
  }

  void _arrow(Canvas canvas, Offset from, Offset dir, double length,
      Color color, double width) {
    final tip = from + dir * length;
    canvas.drawLine(
      from,
      tip - dir * (5 * scale),
      Paint()
        ..color = color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
    final normal = Offset(-dir.dy, dir.dx);
    final head = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo((tip - dir * (7 * scale) + normal * (4.5 * scale)).dx,
          (tip - dir * (7 * scale) + normal * (4.5 * scale)).dy)
      ..lineTo((tip - dir * (7 * scale) - normal * (4.5 * scale)).dx,
          (tip - dir * (7 * scale) - normal * (4.5 * scale)).dy)
      ..close();
    canvas.drawPath(head, Paint()..color = color);
  }

  void _label(Canvas canvas, String text, Offset center, Color color,
      {double size = 10, FontWeight weight = FontWeight.w800}) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size * scale,
          fontWeight: weight,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    painter.paint(
        canvas, center - Offset(painter.width / 2, painter.height / 2));
  }

  void _dashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    final total = (b - a).distance;
    if (total == 0) {
      return;
    }
    final dir = (b - a) / total;
    const dash = 4.0;
    const gap = 4.0;
    var d = 0.0;
    while (d < total) {
      final end = math.min(d + dash, total);
      canvas.drawLine(a + dir * d, a + dir * end, paint);
      d = end + gap;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 1. 대기 장소: 점선 → 네모 → 나가는 화살표.
    for (final mark in waitSpots) {
      final spot = toPixel(mark.x, mark.y);
      final dest = toPixel(mark.destX, mark.destY);
      final color =
          mark.highlighted ? VicaColors.primaryDark : VicaColors.primary;
      _dashedLine(
        canvas,
        dest,
        spot,
        Paint()
          ..color = color
          ..strokeWidth = 1.2 * scale,
      );
      final half = (mark.highlighted ? 5.0 : 3.5) * scale;
      final rect =
          Rect.fromCenter(center: spot, width: half * 2, height: half * 2);
      canvas.drawRect(rect, Paint()..color = VicaColors.accentTint);
      canvas.drawRect(
        rect,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2 * scale,
      );
      _arrow(canvas, spot, _screenDir(mark.x, mark.y, mark.yawDeg), 14 * scale,
          color, 1.8 * scale);
    }

    // 2. 로봇 윤곽(찍는 중·고른 대기 장소).
    final outline = robotOutline;
    if (outline != null) {
      final yaw = outline.yawDeg * math.pi / 180.0;
      final c = math.cos(yaw);
      final s = math.sin(yaw);
      final path = Path();
      for (var i = 0; i < kBodyOutline.length; i++) {
        final (fx, fy) = kBodyOutline[i];
        final p =
            toPixel(outline.x + fx * c - fy * s, outline.y + fx * s + fy * c);
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      path.close();
      canvas.drawPath(
          path, Paint()..color = outline.color.withValues(alpha: 0.18));
      canvas.drawPath(
        path,
        Paint()
          ..color = outline.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 * scale,
      );
      final front =
          toPixel(outline.x + kBodyFrontM * c, outline.y + kBodyFrontM * s);
      final dir = _screenDir(outline.x, outline.y, outline.yawDeg);
      _arrow(canvas, front, dir, 16 * scale, outline.color, 2 * scale);
      // '대기' 글자는 몸통 가운데에서 화면 위쪽으로 조금 띄워 씁니다(목업 4·4′).
      final mid = toPixel(
        outline.x - (kBodyRearM - kBodyFrontM) / 2 * c,
        outline.y - (kBodyRearM - kBodyFrontM) / 2 * s,
      );
      _label(canvas, '대기', mid - Offset(0, 18 * scale), outline.color);
      if (outline.showExitLabel) {
        _label(
          canvas,
          '나가는 방향',
          front + dir * (34 * scale) + Offset(0, 10 * scale),
          VicaColors.textTertiary,
          size: 9,
          weight: FontWeight.w400,
        );
      }
    }

    // 3. 입구 방향 화살표.
    final door = doorArrow;
    if (door != null) {
      final from = toPixel(door.x, door.y);
      final dir = _screenDir(door.x, door.y, door.yawDeg);
      _arrow(
          canvas, from, dir, 20 * scale, VicaColors.primaryDark, 2.2 * scale);
      final label = TextPainter(
        text: TextSpan(
          text: '입구',
          style: TextStyle(
            color: VicaColors.primaryDark,
            fontSize: 10 * scale,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      final at =
          from + dir * (26 * scale) - Offset(label.width / 2, label.height / 2);
      label.paint(canvas, at);
    }

    // 4. 원래 자리(기존 목적지를 옮기는 중).
    final ghost = ghostPoint;
    if (ghost != null) {
      final center = toPixel(ghost.dx, ghost.dy);
      final paint = Paint()
        ..color = VicaColors.textTertiary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2 * scale;
      final r = 6 * scale;
      const steps = 12;
      for (var i = 0; i < steps; i += 2) {
        canvas.drawArc(Rect.fromCircle(center: center, radius: r),
            i * 2 * math.pi / steps, 2 * math.pi / steps, false, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant WaitSpotOverlayPainter old) => true;
}
