import 'package:flutter/material.dart';

import '../core/app_settings.dart';
import '../core/map_coordinate.dart';
import '../models/location_point.dart';
import '../models/robot_status.dart';
import '../models/vica_map.dart';

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

class MapCanvas extends StatelessWidget {
  const MapCanvas({
    super.key,
    required this.map,
    required this.settings,
    required this.locations,
    this.selectedLocationId,
    this.robot,
    this.draftLocation,
    this.onTapMap,
    this.onSelectLocation,
  });

  final VicaMap map;
  final AppSettings settings;
  final List<LocationPoint> locations;
  final String? selectedLocationId;
  final RobotStatus? robot;
  final LocationPoint? draftLocation;
  final ValueChanged<Offset>? onTapMap;
  final ValueChanged<LocationPoint>? onSelectLocation;

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
            child: GestureDetector(
              onTapUp: onTapMap == null
                  ? null
                  : (details) {
                      final local = details.localPosition;
                      final pixel = Offset(local.dx / scale, local.dy / scale);
                      final ros = MapCoordinate.pixelToRos(
                        map: map,
                        pixel: pixel,
                        flipY: settings.flipMapY,
                        xOffset: settings.xOffset,
                        yOffset: settings.yOffset,
                        scale: settings.mapScale,
                      );
                      onTapMap!(ros);
                    },
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
                              size: 7,
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
                        label: '임시',
                        color: Colors.green,
                        size: 8,
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
      top: offset.dy - 32,
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
              size: 20,
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
    this.onTap,
  });

  final Offset offset;
  final String label;
  final Color color;
  final double size;
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
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.4),
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
