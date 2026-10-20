import 'package:flutter/material.dart';

import '../core/app_settings.dart';
import '../models/location_point.dart';
import '../models/vica_map.dart';
import '../providers/supervisor_provider.dart';
import 'map_canvas.dart';
import 'vica_ui.dart';

class DriveMapCanvas extends StatelessWidget {
  const DriveMapCanvas({
    super.key,
    required this.map,
    required this.settings,
    required this.supervisor,
    required this.locations,
    this.selectedLocationId,
    this.onSelectLocation,
    this.onTapMap,
    this.pickedLocation,
    this.poseArrow,
    this.scanHits = const [],
    this.showLocationLabels = true,
  });

  final VicaMap map;
  final AppSettings settings;
  final SupervisorProvider supervisor;

  /// 이 화면이 보일 장소. 전체든 일부든 화면이 정합니다.
  final List<LocationPoint> locations;
  final String? selectedLocationId;
  final ValueChanged<LocationPoint>? onSelectLocation;

  /// 초기 위치 잡기처럼 지도 자체를 누르는 화면만 넘깁니다.
  final ValueChanged<Offset>? onTapMap;
  final LocationPoint? pickedLocation;
  final MapPoseArrow? poseArrow;
  final List<Offset> scanHits;

  /// 초기 위치를 찍는 동안 false. MapCanvas.showLocationLabels 참고.
  final bool showLocationLabels;

  @override
  Widget build(BuildContext context) {
    return ResponsiveMapFrame(
      map: map,
      child: MapCanvas(
        map: map,
        settings: settings,
        locations: locations,
        selectedLocationId: selectedLocationId,
        robot: supervisor.primaryRobot,
        pickedLocation: pickedLocation,
        poseArrow: poseArrow,
        scanHits: scanHits,
        homePoint: supervisor.homePointFor(map.mapId),
        keepoutZones: supervisor.keepoutZonesFor(map.mapId),
        routeGraph: supervisor.routeGraphFor(map.mapId),
        onTapMap: onTapMap,
        onSelectLocation: onSelectLocation,
        showLocationLabels: showLocationLabels,
      ),
    );
  }
}

/// 이 화면의 지도와 젯슨이 지금 달리는 지도(maps/CURRENT_MAP)가 다를 때 한 줄로
class CurrentMapNotice extends StatelessWidget {
  const CurrentMapNotice({
    super.key,
    required this.supervisor,
    required this.map,
  });

  final SupervisorProvider supervisor;
  final VicaMap? map;

  @override
  Widget build(BuildContext context) {
    final current = supervisor.currentMapId;
    final shown = map?.mapId;
    if (current.isEmpty || shown == null || shown == current) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded,
              size: 18, color: VicaColors.red),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              vicaKeepWords(vicaBreakAtSentences(
                '로봇은 지금 "$current" 지도로 주행합니다. 이 화면의 "$shown" 과 다릅니다 — '
                '장소·홈이 로봇 위치와 어긋나 보일 수 있습니다.',
              )),
              style: const TextStyle(color: VicaColors.red, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
