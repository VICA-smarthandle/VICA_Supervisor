import 'dart:ui' show PointMode;

import 'package:flutter/foundation.dart' show kIsWeb, listEquals, mapEquals;
import 'package:flutter/material.dart';

import '../core/app_settings.dart';
import '../core/map_coordinate.dart';
import '../models/keepout_zone.dart';
import '../models/location_point.dart';
import '../models/route_edit.dart';
import '../models/robot_status.dart';
import '../models/route_graph.dart';
import '../models/vica_map.dart';
import 'vica_ui.dart';
import 'wait_spot_overlay.dart';

const double _markerScale = kIsWeb ? 1.0 : 2 / 3;

const double _markerSize = 5 * _markerScale;
const double _markerBorder = 1.0 * _markerScale;

const double _markerHitSize = 16;

class ResponsiveMapFrame extends StatelessWidget {
  const ResponsiveMapFrame({
    super.key,
    required this.map,
    required this.child,
    this.minHeight = 280,
    this.maxHeight = 680,
  });

  final VicaMap? map;
  final Widget child;
  final double minHeight;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mapWidth = map?.width.toDouble() ?? 4;
        final mapHeight = map?.height.toDouble() ?? 3;
        final aspectRatio =
            mapWidth > 0 && mapHeight > 0 ? mapWidth / mapHeight : 4 / 3;
        final preferredHeight = constraints.maxWidth / aspectRatio;
        final height = preferredHeight.clamp(minHeight, maxHeight).toDouble();

        return Container(
          height: height,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: VicaColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: VicaColors.border),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: child,
          ),
        );
      },
    );
  }
}

/// 지도 위에 그릴 자세 화살표입니다. 초기 위치 확인 결과를 보여줄 때 씁니다.
class MapPoseArrow {
  const MapPoseArrow({
    required this.x,
    required this.y,
    required this.yawDegrees,
    this.label = '',
    this.color = VicaColors.primaryDark,
  });

  final double x;
  final double y;
  final double yawDegrees;
  final String label;

  /// 화살표 색. 기본은 브랜드 진한색이고, 지도 그리는 중에는 회색 지도 위에서
  final Color color;
}

class MapCanvas extends StatelessWidget {
  const MapCanvas({
    super.key,
    required this.map,
    required this.settings,
    required this.locations,
    this.selectedLocationId,
    this.robot,
    this.draftLocation,
    this.pickedLocation,
    this.poseArrow,
    this.homePoint,
    this.scanHits = const [],
    this.onTapMap,
    this.onSelectLocation,
    this.keepoutZones = const [],
    this.draftKeepoutZone,
    this.selectedKeepoutZoneId,
    this.keepoutEditMode = false,
    this.onKeepoutPanStart,
    this.onKeepoutPanUpdate,
    this.onKeepoutPanEnd,
    this.onSelectKeepoutZone,
    this.routeGraph,
    this.showLocationLabels = true,
    this.routeEditMode = false,
    this.routeSketch,
    this.routePreview,
    this.routeIssues = const [],
    this.routeSelectedNode,
    this.onRouteDragStart,
    this.onRouteDragUpdate,
    this.onRouteDragEnd,
    this.waitSpots = const [],
    this.doorArrow,
    this.robotOutline,
    this.ghostPoint,
  });

  final VicaMap map;
  final AppSettings settings;
  final List<LocationPoint> locations;
  final String? selectedLocationId;
  final RobotStatus? robot;
  final LocationPoint? draftLocation;
  final LocationPoint? pickedLocation;
  final MapPoseArrow? poseArrow;

  /// 저장된 홈 위치(ROS 좌표). 없으면 null 이며 오류가 아닙니다.
  final Offset? homePoint;

  /// 초기 위치를 확인한 뒤 그 자세에서 본 라이다 점입니다(ROS 좌표).
  final List<Offset> scanHits;

  final ValueChanged<Offset>? onTapMap;
  final ValueChanged<LocationPoint>? onSelectLocation;

  final List<KeepoutZone> keepoutZones;
  final KeepoutZone? draftKeepoutZone;
  final String? selectedKeepoutZoneId;
  final bool keepoutEditMode;
  final ValueChanged<Offset>? onKeepoutPanStart;
  final ValueChanged<Offset>? onKeepoutPanUpdate;
  final VoidCallback? onKeepoutPanEnd;
  final ValueChanged<String?>? onSelectKeepoutZone;

  /// 로봇이 따라 달리는 레일(A단계, 2026-09-30). 금지구역처럼 어느 화면이든
  final RouteGraph? routeGraph;

  /// false 면 장소 점을 길게 눌러도 이름이 뜨지 않습니다. 초기 위치를 찍는
  final bool showLocationLabels;

  /// 레일 편집 중(2026-09-30). 금지구역 편집처럼 지도 이동·확대가 잠기고, 탭은
  final bool routeEditMode;

  /// 관리자 스케치(굵은 점과 선). 편집 중에만 넘깁니다.
  final RouteSketch? routeSketch;

  /// 로봇이 다듬은 모양(미리보기). 연한 굵은 선으로 스케치 아래에 깝니다.
  final RouteGraph? routePreview;

  /// 검사에서 걸린 자리. 빨간 번호로 찍고, 레일 칸 목록과 번호가 같습니다.
  final List<RouteIssue> routeIssues;

  /// 선 잇기에서 먼저 고른 노드.
  final int? routeSelectedNode;
  final ValueChanged<Offset>? onRouteDragStart;
  final ValueChanged<Offset>? onRouteDragUpdate;
  final VoidCallback? onRouteDragEnd;

  /// 대기 장소 표시(2026-10-07). 지도 설정 화면만 넘깁니다 — 원격 주행 지도에는
  final List<MapWaitSpotMark> waitSpots;

  /// 찍는 중이거나 고른 목적지의 입구 방향.
  final MapDoorArrow? doorArrow;

  /// 대기 장소를 찍는 중이거나 골랐을 때의 로봇 윤곽.
  final MapRobotOutline? robotOutline;

  /// 기존 목적지를 옮기는 중일 때 원래 자리(ROS 좌표).
  final Offset? ghostPoint;

  bool get _hasWaitOverlay =>
      waitSpots.isNotEmpty ||
      doorArrow != null ||
      robotOutline != null ||
      ghostPoint != null;

  String get _imageUrl {
    if (map.imageUrl.startsWith('http://') ||
        map.imageUrl.startsWith('https://')) {
      return map.imageUrl;
    }
    final base = settings.mapHttpBaseUrl.replaceAll(RegExp(r'/$'), '');
    final path =
        map.imageUrl.startsWith('/') ? map.imageUrl : '/${map.imageUrl}';
    return '$base$path';
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = _fitScale(
          constraints.maxWidth,
          constraints.maxHeight,
          map.width.toDouble(),
          map.height.toDouble(),
        );
        final displaySize = Size(map.width * scale, map.height * scale);
        return Center(
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 6,
            boundaryMargin: const EdgeInsets.all(80),
            panEnabled: !keepoutEditMode && !routeEditMode,
            scaleEnabled: !keepoutEditMode && !routeEditMode,
            child: GestureDetector(
              onTapUp: (details) {
                final ros = _rosFromLocal(details.localPosition, scale);
                if (keepoutEditMode) {
                  onSelectKeepoutZone?.call(_zoneAt(ros)?.zoneId);
                  return;
                }
                onTapMap?.call(ros);
              },
              onPanStart: keepoutEditMode
                  ? (details) => onKeepoutPanStart?.call(
                        _rosFromLocal(details.localPosition, scale),
                      )
                  : null,
              onPanUpdate: keepoutEditMode
                  ? (details) => onKeepoutPanUpdate?.call(
                        _rosFromLocal(details.localPosition, scale),
                      )
                  : null,
              onPanEnd: keepoutEditMode ? (_) => onKeepoutPanEnd?.call() : null,
              onLongPressStart: routeEditMode
                  ? (details) => onRouteDragStart?.call(
                        _rosFromLocal(details.localPosition, scale),
                      )
                  : null,
              onLongPressMoveUpdate: routeEditMode
                  ? (details) => onRouteDragUpdate?.call(
                        _rosFromLocal(details.localPosition, scale),
                      )
                  : null,
              onLongPressEnd:
                  routeEditMode ? (_) => onRouteDragEnd?.call() : null,
              child: SizedBox(
                width: displaySize.width,
                height: displaySize.height,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Image.network(
                        _imageUrl,
                        key: ValueKey(map.mapId),
                        fit: BoxFit.fill,
                        filterQuality: FilterQuality.medium,
                        gaplessPlayback: true,
                        errorBuilder: (context, error, stackTrace) {
                          return ColoredBox(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            child: const Center(child: Text('지도 이미지 로드 실패')),
                          );
                        },
                      ),
                    ),
                    ...keepoutZones.map(
                      (zone) => _KeepoutRect(
                        rect: _zoneRect(zone, scale),
                        selected: zone.zoneId == selectedKeepoutZoneId,
                      ),
                    ),
                    if (draftKeepoutZone != null)
                      _KeepoutRect(
                        rect: _zoneRect(draftKeepoutZone!, scale),
                        draft: true,
                      ),
                    if (routeGraph != null && !routeGraph!.isEmpty)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: RouteRailPainter.fromGraph(
                              routeGraph!,
                              (x, y) => _scaledOffset(x, y, scale),
                            ),
                          ),
                        ),
                      ),
                    if (routeEditMode)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: RouteSketchPainter.build(
                              sketch: routeSketch ?? RouteSketch.empty,
                              preview: routePreview,
                              issues: routeIssues,
                              selected: routeSelectedNode,
                              toPixel: (x, y) => _scaledOffset(x, y, scale),
                            ),
                          ),
                        ),
                      ),
                    if (scanHits.isNotEmpty)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: _ScanHitPainter(
                              points: scanHits
                                  .map((hit) =>
                                      _scaledOffset(hit.dx, hit.dy, scale))
                                  .toList(growable: false),
                            ),
                          ),
                        ),
                      ),
                    ...locations.map(
                      (location) => selectedLocationId == location.locationId
                          ? _SelectedLocationMarker(
                              offset:
                                  _scaledOffset(location.x, location.y, scale),
                              label: location.name,
                            )
                          : _Marker(
                              offset:
                                  _scaledOffset(location.x, location.y, scale),
                              label: showLocationLabels ? location.name : '',
                              color: Colors.blue,
                              size: _markerSize,
                              onTap: onSelectLocation == null
                                  ? null
                                  : () => onSelectLocation!(location),
                            ),
                    ),
                    if (_hasWaitOverlay)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: WaitSpotOverlayPainter(
                              toPixel: (x, y) => _scaledOffset(x, y, scale),
                              scale: _markerScale,
                              waitSpots: waitSpots,
                              doorArrow: doorArrow,
                              robotOutline: robotOutline,
                              ghostPoint: ghostPoint,
                            ),
                          ),
                        ),
                      ),
                    if (homePoint != null)
                      _Marker(
                        offset: _scaledOffset(
                          homePoint!.dx,
                          homePoint!.dy,
                          scale,
                        ),
                        label: '홈',
                        color: Colors.orange,
                        size: _markerSize,
                      ),
                    if (draftLocation != null &&
                        draftLocation!.mapId == map.mapId)
                      _Marker(
                        offset: _scaledOffset(
                          draftLocation!.x,
                          draftLocation!.y,
                          scale,
                        ),
                        label: '임시 저장',
                        color: Colors.green,
                        size: _markerSize,
                      ),
                    if (pickedLocation != null)
                      _Marker(
                        offset: _scaledOffset(
                          pickedLocation!.x,
                          pickedLocation!.y,
                          scale,
                        ),
                        label: '선택 위치',
                        color: Colors.deepOrange,
                        size: _markerSize,
                        filled: false,
                      ),
                    if (poseArrow != null)
                      _PoseArrowMarker(
                        offset: _scaledOffset(
                          poseArrow!.x,
                          poseArrow!.y,
                          scale,
                        ),
                        yaw: 90 - poseArrow!.yawDegrees + settings.yawOffset,
                        label: poseArrow!.label,
                        color: poseArrow!.color,
                      ),
                    if (robot != null && robot!.mapId == map.mapId)
                      _RobotMarker(
                        offset: _scaledOffset(robot!.x, robot!.y, scale),
                        yaw: 90 - robot!.yaw + settings.yawOffset,
                        label: robot!.robotName,
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  double _fitScale(
      double maxWidth, double maxHeight, double width, double height) {
    if (maxWidth.isInfinite || maxHeight.isInfinite) {
      return 1;
    }
    final widthScale = maxWidth / width;
    final heightScale = maxHeight / height;
    return widthScale < heightScale ? widthScale : heightScale;
  }

  Offset _rosFromLocal(Offset local, double displayScale) {
    return MapCoordinate.pixelToRos(
      map: map,
      pixel: Offset(local.dx / displayScale, local.dy / displayScale),
      flipY: settings.flipMapY,
      xOffset: settings.xOffset,
      yOffset: settings.yOffset,
      scale: settings.mapScale,
    );
  }

  /// 짚은 자리에 있는 금지구역. 겹쳐 있으면 작은 것을 고릅니다.
  KeepoutZone? _zoneAt(Offset ros) {
    KeepoutZone? found;
    for (final zone in keepoutZones) {
      if (!zone.contains(ros)) {
        continue;
      }
      if (found == null ||
          zone.width * zone.height < found.width * found.height) {
        found = zone;
      }
    }
    return found;
  }

  /// ROS 사각형을 화면 사각형으로 옮깁니다.
  Rect _zoneRect(KeepoutZone zone, double displayScale) {
    return Rect.fromPoints(
      _scaledOffset(zone.xMin, zone.yMin, displayScale),
      _scaledOffset(zone.xMax, zone.yMax, displayScale),
    );
  }

  Offset _scaledOffset(double x, double y, double displayScale) {
    final pixel = MapCoordinate.rosToPixel(
      map: map,
      x: x,
      y: y,
      flipY: settings.flipMapY,
      xOffset: settings.xOffset,
      yOffset: settings.yOffset,
      scale: settings.mapScale,
    );
    return Offset(pixel.dx * displayScale, pixel.dy * displayScale);
  }
}

class _SelectedLocationMarker extends StatelessWidget {
  const _SelectedLocationMarker({
    required this.offset,
    required this.label,
  });

  final Offset offset;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: offset.dx - 28,
      top: offset.dy - 28,
      width: 56,
      child: IgnorePointer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.black87,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const Icon(
              Icons.location_on,
              color: Colors.deepOrange,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

class _Marker extends StatelessWidget {
  const _Marker({
    required this.offset,
    required this.label,
    required this.color,
    required this.size,
    this.filled = true,
    this.onTap,
  });

  final Offset offset;
  final String label;
  final Color color;
  final double size;
  final bool filled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final hit = onTap == null ? size : _markerHitSize;
    final dot = DecoratedBox(
      decoration: BoxDecoration(
        color: filled ? color : Colors.white,
        shape: BoxShape.circle,
        border: Border.all(
          color: filled ? Colors.white : color,
          width: _markerBorder,
        ),
      ),
      child: SizedBox(width: size, height: size),
    );
    return Positioned(
      left: offset.dx - hit / 2,
      top: offset.dy - hit / 2,
      child: Tooltip(
        message: label,
        child: GestureDetector(
          onTap: onTap,
          behavior: onTap == null ? null : HitTestBehavior.opaque,
          child: SizedBox(
            width: hit,
            height: hit,
            child: Center(child: dot),
          ),
        ),
      ),
    );
  }
}

class _RobotMarker extends StatelessWidget {
  const _RobotMarker({
    required this.offset,
    required this.yaw,
    required this.label,
  });

  final Offset offset;
  final double yaw;
  final String label;

  @override
  Widget build(BuildContext context) {
    const markerSize = 7.0 * _markerScale;
    return Positioned(
      left: offset.dx - markerSize / 2,
      top: offset.dy - markerSize / 2,
      child: Tooltip(
        message: label,
        child: Transform.rotate(
          angle: yaw * 3.1415926535 / 180.0,
          child: const Icon(
            Icons.navigation,
            color: Colors.red,
            size: markerSize,
          ),
        ),
      ),
    );
  }
}

class _PoseArrowMarker extends StatelessWidget {
  const _PoseArrowMarker({
    required this.offset,
    required this.yaw,
    required this.label,
    required this.color,
  });

  final Offset offset;
  final double yaw;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    const markerSize = 10.0 * _markerScale;
    return Positioned(
      left: offset.dx - markerSize / 2,
      top: offset.dy - markerSize / 2,
      child: IgnorePointer(
        child: Tooltip(
          message: label,
          child: Transform.rotate(
            angle: yaw * 3.1415926535 / 180.0,
            child: Icon(
              Icons.navigation,
              color: color,
              size: markerSize,
            ),
          ),
        ),
      ),
    );
  }
}

/// 지도 위의 금지구역 사각형 하나입니다.
class _KeepoutRect extends StatelessWidget {
  const _KeepoutRect({
    required this.rect,
    this.selected = false,
    this.draft = false,
  });

  final Rect rect;
  final bool selected;
  final bool draft;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: IgnorePointer(
        child: CustomPaint(
          painter: _KeepoutPainter(selected: selected, draft: draft),
        ),
      ),
    );
  }
}

class _KeepoutPainter extends CustomPainter {
  const _KeepoutPainter({required this.selected, required this.draft});

  final bool selected;
  final bool draft;

  static const _color = VicaColors.red;
  static const _dash = 6.0;
  static const _gap = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    if (!draft) {
      canvas.drawRect(
        rect,
        Paint()..color = _color.withValues(alpha: 0.14),
      );
    }
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = selected ? 2.4 : 1.4
      ..color = _color;
    if (draft) {
      _paintDashed(canvas, rect, border);
    } else {
      canvas.drawRect(rect, border);
    }
    if (draft || selected) {
      _paintCorners(canvas, rect);
    }
  }

  void _paintDashed(Canvas canvas, Rect rect, Paint paint) {
    final corners = [
      rect.topLeft,
      rect.topRight,
      rect.bottomRight,
      rect.bottomLeft,
    ];
    for (var index = 0; index < corners.length; index++) {
      _paintDashedLine(
        canvas,
        corners[index],
        corners[(index + 1) % corners.length],
        paint,
      );
    }
  }

  void _paintDashedLine(Canvas canvas, Offset from, Offset to, Paint paint) {
    final total = (to - from).distance;
    if (total <= 0) {
      return;
    }
    final step = (to - from) / total;
    var walked = 0.0;
    while (walked < total) {
      final end = (walked + _dash).clamp(0.0, total).toDouble();
      canvas.drawLine(from + step * walked, from + step * end, paint);
      walked = end + _gap;
    }
  }

  void _paintCorners(Canvas canvas, Rect rect) {
    final fill = Paint()..color = _color;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white;
    for (final corner in [
      rect.topLeft,
      rect.topRight,
      rect.bottomRight,
      rect.bottomLeft,
    ]) {
      canvas.drawCircle(corner, 3.2, fill);
      canvas.drawCircle(corner, 3.2, ring);
    }
  }

  @override
  bool shouldRepaint(_KeepoutPainter old) =>
      old.selected != selected || old.draft != draft;
}

/// 레일(route graph)을 지도 위에 그립니다.
class RouteRailPainter extends CustomPainter {
  const RouteRailPainter({
    required this.segments,
    required this.keyPoints,
  });

  /// ROS 좌표 → 지도 픽셀 변환은 MapCanvas 가 하고, 여기는 픽셀만 받습니다.
  factory RouteRailPainter.fromGraph(
    RouteGraph graph,
    Offset Function(double x, double y) toPixel,
  ) {
    final pixels = <int, Offset>{
      for (final entry in graph.nodes.entries)
        entry.key: toPixel(entry.value.dx, entry.value.dy),
    };
    final segments = <Offset>[];
    for (final edge in graph.edges) {
      final a = pixels[edge.a];
      final b = pixels[edge.b];
      if (a == null || b == null) {
        continue;
      }
      segments
        ..add(a)
        ..add(b);
    }
    final keyIds = graph.keyNodeIds;
    return RouteRailPainter(
      segments: List.unmodifiable(segments),
      keyPoints: List.unmodifiable([
        for (final id in keyIds)
          if (pixels[id] != null) pixels[id]!,
      ]),
    );
  }

  /// [시작, 끝, 시작, 끝, ...] 짝으로 늘어놓은 선분.
  final List<Offset> segments;

  /// 점을 찍을 역(끝·갈림길).
  final List<Offset> keyPoints;

  static const Color color = VicaColors.primary;
  static const double railWidth = 1.0;
  static const double keyDotRadius = 1.1;
  static const double keyDotBorder = 0.7;

  @override
  void paint(Canvas canvas, Size size) {
    final rail = Paint()
      ..color = color
      ..strokeWidth = railWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawPoints(PointMode.lines, segments, rail);

    final fill = Paint()..color = Colors.white;
    final ring = Paint()
      ..color = color
      ..strokeWidth = keyDotBorder
      ..style = PaintingStyle.stroke;
    for (final point in keyPoints) {
      canvas.drawCircle(point, keyDotRadius, fill);
      canvas.drawCircle(point, keyDotRadius, ring);
    }
  }

  @override
  bool shouldRepaint(RouteRailPainter old) =>
      !listEquals(old.segments, segments) ||
      !listEquals(old.keyPoints, keyPoints);
}

/// 라이다 점을 지도 위에 찍습니다.
class _ScanHitPainter extends CustomPainter {
  const _ScanHitPainter({required this.points});

  final List<Offset> points;

  /// 산호빛 붉은색.
  static const Color _coral = Color(0xFFE06055);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _coral.withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;
    for (final point in points) {
      canvas.drawCircle(point, 0.8, paint);
    }
  }

  @override
  bool shouldRepaint(_ScanHitPainter old) => old.points != points;
}

/// 레일 편집 층(2026-09-30, B단계 시안 ③④).
class RouteSketchPainter extends CustomPainter {
  const RouteSketchPainter({
    required this.previewSegments,
    required this.sketchSegments,
    required this.nodes,
    required this.selected,
    required this.issues,
  });

  factory RouteSketchPainter.build({
    required RouteSketch sketch,
    required RouteGraph? preview,
    required List<RouteIssue> issues,
    required int? selected,
    required Offset Function(double x, double y) toPixel,
  }) {
    List<Offset> segs(Map<int, Offset> nodes, List<RouteEdge> edges) => [
          for (final e in edges)
            if (nodes[e.a] != null && nodes[e.b] != null) ...[
              toPixel(nodes[e.a]!.dx, nodes[e.a]!.dy),
              toPixel(nodes[e.b]!.dx, nodes[e.b]!.dy),
            ],
        ];
    return RouteSketchPainter(
      previewSegments:
          preview == null ? const [] : segs(preview.nodes, preview.edges),
      sketchSegments: segs(sketch.nodes, sketch.edges),
      nodes: {
        for (final entry in sketch.nodes.entries)
          entry.key: toPixel(entry.value.dx, entry.value.dy),
      },
      selected: selected,
      issues: [for (final i in issues) toPixel(i.x, i.y)],
    );
  }

  final List<Offset> previewSegments;
  final List<Offset> sketchSegments;
  final Map<int, Offset> nodes;
  final int? selected;
  final List<Offset> issues;

  static const double previewWidth = 3.2 * _markerScale;
  static const double sketchWidth = 2.0 * _markerScale;
  static const double nodeRadius = 4.5 * _markerScale;
  static const double issueRadius = 8.0 * _markerScale;

  @override
  void paint(Canvas canvas, Size size) {
    if (previewSegments.isNotEmpty) {
      canvas.drawPoints(
        PointMode.lines,
        previewSegments,
        Paint()
          ..color = VicaColors.primary.withValues(alpha: 0.3)
          ..strokeWidth = previewWidth
          ..strokeCap = StrokeCap.round,
      );
    }
    canvas.drawPoints(
      PointMode.lines,
      sketchSegments,
      Paint()
        ..color = VicaColors.primaryDark
        ..strokeWidth = sketchWidth
        ..strokeCap = StrokeCap.round,
    );
    final ring = Paint()
      ..color = VicaColors.primaryDark
      ..strokeWidth = 1.6 * _markerScale
      ..style = PaintingStyle.stroke;
    nodes.forEach((id, p) {
      canvas.drawCircle(
        p,
        nodeRadius,
        Paint()..color = id == selected ? VicaColors.primaryDark : Colors.white,
      );
      canvas.drawCircle(p, nodeRadius, ring);
    });
    for (var i = 0; i < issues.length; i++) {
      final p = issues[i];
      canvas.drawCircle(
        p,
        issueRadius,
        Paint()..color = VicaColors.red.withValues(alpha: 0.18),
      );
      canvas.drawCircle(
        p,
        issueRadius,
        Paint()
          ..color = VicaColors.red
          ..strokeWidth = 1.2 * _markerScale
          ..style = PaintingStyle.stroke,
      );
      final text = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: const TextStyle(
            color: VicaColors.red,
            fontSize: 9 * _markerScale + 2,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, p + Offset(issueRadius + 1, -text.height / 2));
    }
  }

  @override
  bool shouldRepaint(RouteSketchPainter old) =>
      !listEquals(old.previewSegments, previewSegments) ||
      !listEquals(old.sketchSegments, sketchSegments) ||
      !mapEquals(old.nodes, nodes) ||
      old.selected != selected ||
      !listEquals(old.issues, issues);
}
