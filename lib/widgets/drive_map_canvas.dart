// 이 파일은 주행 화면(원격 주행·물류 배송)의 지도를 한 모양으로 맞춥니다.
//
// 금지구역·홈·로봇 위치는 어느 주행 화면이든 같은 자리(provider)에서 같은 식으로
// 가져옵니다. 화면이 정하는 것은 "어떤 장소를 보일지"와 선택·터치뿐입니다 —
// 물류 배송은 연락처 있는 장소만 보이고(사용자 결정 2026-09-03), 원격 주행은
// 전부 보입니다. 지도 설정 화면은 금지구역을 그리는 그림판이라 MapCanvas 를
// 직접 쓰되, 홈·금지구역은 여기와 같은 provider 함수에서 받습니다.
//
// 이렇게 묶기 전에는 배송 화면에 홈이 없고 원격 주행에 금지구역이 없는 식으로
// 화면마다 하나씩 빠져 있었습니다(2026-09-03 실기).
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
        // 아래 둘이 "주행 화면이면 늘 보이는 것"입니다. 화면이 잊을 수 없게
        // 여기서 채웁니다.
        homePoint: supervisor.homePointFor(map.mapId),
        keepoutZones: supervisor.keepoutZonesFor(map.mapId),
        onTapMap: onTapMap,
        onSelectLocation: onSelectLocation,
      ),
    );
  }
}

/// 이 화면의 지도와 젯슨이 지금 달리는 지도(maps/CURRENT_MAP)가 다를 때 한 줄로
/// 알립니다. 터미네이터에서 지도를 잘못 띄웠을 때 앱에서 바로 보이게 하려는
/// 것입니다(2026-09-03 사용자 요청). 로봇이 아직 목록을 안 보냈으면 조용합니다.
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
          const Icon(Icons.warning_amber_rounded, size: 18, color: VicaColors.red),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '로봇은 지금 "$current" 지도로 달립니다. 이 화면의 "$shown" 과 다릅니다 — '
              '장소·홈이 로봇 위치와 어긋나 보일 수 있습니다.',
              style: const TextStyle(color: VicaColors.red, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
