// 이 파일은 지도 이미지, 저장된 장소 마커, 선택 마커, 현재 로봇 위치를 한 화면에 표시합니다.
import 'package:flutter/material.dart';

import '../core/app_settings.dart';
import '../core/map_coordinate.dart';
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
                        yaw: 90 -
                            poseArrow!.yawDegrees +
                            settings.yawOffset,
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
    // 로봇 화살표(7)보다 크게 둡니다. 지금 고르고 있는 것이라 눈에 먼저 들어와야 합니다.
    const markerSize = 18.0;
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
