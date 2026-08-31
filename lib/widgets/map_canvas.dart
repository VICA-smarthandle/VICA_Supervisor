// 이 파일은 지도 이미지, 저장된 장소 마커, 선택 마커, 현재 로봇 위치를 한 화면에 표시합니다.
import 'package:flutter/material.dart';

import '../core/app_settings.dart';
import '../core/map_coordinate.dart';
import '../models/keepout_zone.dart';
import '../models/location_point.dart';
import '../models/robot_status.dart';
import '../models/vica_map.dart';
import 'vica_ui.dart';

// 지도 위 점의 지름(px). 저장된 장소·임시 저장 장소·선택 위치가 같은 크기여야
// 색만으로 구분되고 크기 차이가 의미로 오해되지 않습니다.
// 7/8 -> 5 로 줄였습니다. 장소가 늘어나면 점이 서로 겹쳐 지도가 안 보였습니다.
const double _markerSize = 5;

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

        return SizedBox(
          height: height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: child,
          ),
        );
      },
    );
  }
}

/// 지도 위에 그릴 자세 화살표입니다. 초기 위치 확인 결과를 보여줄 때 씁니다.
///
/// 로봇 화살표(_RobotMarker)와 따로 두는 이유는 둘이 동시에 보여야 하기
/// 때문입니다. AMCL 이 아직 엉뚱한 곳을 가리키는 상태에서 "여기가 맞다"를
/// 고르는 화면이라, 지금 믿고 있는 자리와 새로 고른 자리가 같이 보여야 합니다.
class MapPoseArrow {
  const MapPoseArrow({
    required this.x,
    required this.y,
    required this.yawDegrees,
    this.label = '',
  });

  final double x;
  final double y;
  final double yawDegrees;
  final String label;
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
  });

  final VicaMap map;
  final AppSettings settings;
  final List<LocationPoint> locations;
  final String? selectedLocationId;
  final RobotStatus? robot;
  final LocationPoint? draftLocation;
  // 지도를 눌러 좌표만 찍어 둔 점입니다. 정보 입력을 마친 draftLocation과 달리
  // 아직 아무 내용도 없으므로 속을 비운 원으로 그려 한눈에 구분되게 합니다.
  final LocationPoint? pickedLocation;
  // 초기 위치 확인이 찾아낸 자세입니다. 사람이 짚은 점(pickedLocation)과 함께
  // 그려져야 얼마나 옮겨졌는지가 눈에 보입니다.
  final MapPoseArrow? poseArrow;
  final ValueChanged<Offset>? onTapMap;
  final ValueChanged<LocationPoint>? onSelectLocation;

  // 저장된 금지구역입니다. 편집 중이 아니어도 항상 보입니다 — 장소를 찍을 때
  // 로봇이 못 가는 자리를 알고 찍어야 하기 때문입니다.
  final List<KeepoutZone> keepoutZones;
  // 손가락을 끄는 동안의 미리보기입니다. 아직 목록에 없습니다.
  final KeepoutZone? draftKeepoutZone;
  final String? selectedKeepoutZoneId;
  // true 면 지도 이동·확대를 잠그고 드래그를 사각형 그리기에 씁니다.
  final bool keepoutEditMode;
  final ValueChanged<Offset>? onKeepoutPanStart;
  final ValueChanged<Offset>? onKeepoutPanUpdate;
  final VoidCallback? onKeepoutPanEnd;
  final ValueChanged<String?>? onSelectKeepoutZone;

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
            // 금지구역을 그리는 동안에는 확대·이동을 잠급니다. 켜 두면 손가락을
            // 끌 때 지도가 같이 움직여서, 사각형을 그리는 중인지 지도를 미는
            // 중인지 Flutter 가 갈라낼 수 없습니다.
            panEnabled: !keepoutEditMode,
            scaleEnabled: !keepoutEditMode,
            child: GestureDetector(
              // 이 GestureDetector 는 InteractiveViewer 의 **자식 안쪽**에
              // 있습니다. 그래서 details.localPosition 은 확대·이동이 이미
              // 되돌려진 '지도 그림 위의 좌표'입니다. TransformationController 로
              // 한 번 더 되돌리면 두 번 되돌려서 어긋납니다.
              onTapUp: (details) {
                final ros = _rosFromLocal(details.localPosition, scale);
                if (keepoutEditMode) {
                  // 편집 중에는 탭이 '사각형 고르기'입니다. 빈 곳을 누르면
                  // 선택이 풀립니다.
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
              child: SizedBox(
                width: displaySize.width,
                height: displaySize.height,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Image.network(
                        _imageUrl,
                        fit: BoxFit.fill,
                        filterQuality: FilterQuality.medium,
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
                    // 금지구역은 마커보다 **아래** 레이어입니다. 장소 마커와
                    // 로봇 화살표가 사각형에 가려지면 안 됩니다.
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
                              label: location.name,
                              color: Colors.blue,
                              size: _markerSize,
                              onTap: onSelectLocation == null
                                  ? null
                                  : () => onSelectLocation!(location),
                            ),
                    ),
                    if (draftLocation != null)
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

  // 지도 이미지가 화면 안에 들어오도록 초기 표시 크기를 계산합니다.
  double _fitScale(
      double maxWidth, double maxHeight, double width, double height) {
    if (maxWidth.isInfinite || maxHeight.isInfinite) {
      return 1;
    }
    final widthScale = maxWidth / width;
    final heightScale = maxHeight / height;
    return widthScale < heightScale ? widthScale : heightScale;
  }

  // 화면에서 짚은 자리를 ROS map 좌표로 옮깁니다. 장소 찍기와 사각형 그리기가
  // 같은 경로를 씁니다 — 둘이 다른 경로를 쓰면 어긋났을 때 어느 쪽이 맞는지
  // 알 수 없게 됩니다.
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
  ///
  /// flipY 때문에 y 의 위아래가 뒤집히므로 min/max 를 그대로 left/top 으로
  /// 쓰면 안 됩니다. Rect.fromPoints 가 두 점의 순서를 정리해 줍니다.
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
      // 핀 아이콘을 20 -> 16 으로 줄인 만큼(4px) 함께 내립니다. 이 값을 그대로 두면
      // 핀 끝이 실제 좌표보다 4px 위를 가리키게 됩니다.
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
  // false 면 속을 비우고 테두리만 그립니다. "좌표만 찍었고 아직 아무 정보도 없다"를
  // 색이 아니라 형태로 알리기 위한 것입니다.
  final bool filled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: offset.dx - size / 2,
      top: offset.dy - size / 2,
      child: Tooltip(
        message: label,
        child: GestureDetector(
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: filled ? color : Colors.white,
              shape: BoxShape.circle,
              // 지름 5 에서 1.4 는 점의 절반을 넘게 먹어 속이 안 보였습니다.
              border: Border.all(
                color: filled ? Colors.white : color,
                width: 1.0,
              ),
            ),
            child: SizedBox(width: size, height: size),
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
    const markerSize = 7.0;
    return Positioned(
      left: offset.dx - markerSize / 2,
      top: offset.dy - markerSize / 2,
      child: Tooltip(
        message: label,
        child: Transform.rotate(
          // ROS yaw는 y축이 위인 좌표계라 화면 좌표계에서는 회전 방향을 반대로 적용합니다.
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
  });

  final Offset offset;
  final double yaw;
  final String label;

  @override
  Widget build(BuildContext context) {
    // 로봇 화살표(7)보다 조금만 크게 둡니다. 지금 고르는 것이라 구분은 되어야
    // 하지만, 18 이었을 때 로봇 화살표와 균형이 안 맞아 보기 싫다는 실기
    // 피드백(2026-08-26)으로 줄였습니다.
    const markerSize = 10.0;
    return Positioned(
      left: offset.dx - markerSize / 2,
      top: offset.dy - markerSize / 2,
      child: IgnorePointer(
        child: Tooltip(
          message: label,
          child: Transform.rotate(
            // ROS yaw는 y축이 위인 좌표계라 화면에서는 회전 방향을 반대로 적용합니다.
            angle: yaw * 3.1415926535 / 180.0,
            child: const Icon(
              Icons.navigation,
              color: VicaColors.primaryDark,
              size: markerSize,
            ),
          ),
        ),
      ),
    );
  }
}

/// 지도 위의 금지구역 사각형 하나입니다.
///
/// 세 가지 모습이 있습니다.
///   그리는 중  점선 테두리 + 모서리 점 4개. **속은 채우지 않습니다** —
///              채우면 그 아래 지도가 가려져 어디까지 덮는지 모르고 그리게 됩니다.
///   저장된 것  옅은 빨강으로 채우고 실선 테두리.
///   고른 것    테두리를 굵게 하고 모서리에 점을 찍습니다.
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
      // 어느 사각형을 눌렀는지는 MapCanvas 가 좌표로 판정합니다. 이 위젯이
      // 탭을 가로채면 사각형 안에 있는 장소 마커를 누를 수 없게 됩니다.
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
  // 점선 한 칸과 사이 간격(px). 확대해도 사람이 점선으로 알아볼 크기입니다.
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
