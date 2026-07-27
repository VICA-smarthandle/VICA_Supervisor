// 이 파일은 원격 주행 화면으로, 지도별 장소 선택과 주행 요청을 담당합니다.
// 주행 요청은 Mission Manager service를 거치며 Safety 계층을 우회하지 않습니다.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/location_point.dart';
import '../providers/settings_provider.dart';
import '../providers/supervisor_provider.dart';
import '../widgets/map_canvas.dart';
import '../widgets/vica_ui.dart';

class MapLocationsScreen extends StatelessWidget {
  const MapLocationsScreen({super.key});

  static const _compactDropdownDecoration = InputDecoration(
    labelText: '지도 선택',
    isDense: true,
    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 9),
  );

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    final supervisor = context.watch<SupervisorProvider>();
    final map = supervisor.selectedMap;
    final locations = supervisor.locationsFor(map?.mapId);
    final selected = _selectedLocation(
      locations,
      supervisor.selectedLocationId,
    );
    // 주행 여부는 Mission Manager가 발행한 goal 이벤트가 /robot_status.current_goal로
    // 요약되어 들어온 값으로 판단합니다. 앱이 따로 추적하지 않습니다.
    final drivingGoal = supervisor.primaryRobot?.currentGoal.trim() ?? '';
    final driving = drivingGoal.isNotEmpty;

    return VicaPage(
      title: '원격 주행',
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: map?.mapId,
                decoration: _compactDropdownDecoration,
                isExpanded: true,
                itemHeight: null,
                items: supervisor.maps
                    .map(
                      (item) => DropdownMenuItem(
                        value: item.mapId,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(item.mapName),
                        ),
                      ),
                    )
                    .toList(),
                selectedItemBuilder: (context) => supervisor.maps
                    .map(
                      (item) => Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          item.mapName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) => supervisor.selectMap(settings, value),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 112,
              child: OutlinedButton.icon(
                onPressed: map == null
                    ? null
                    : () => supervisor.requestLocationList(settings, map.mapId),
                icon: const Icon(Icons.sync, size: 18),
                label: const Text('동기화', maxLines: 1),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (map == null)
          const VicaCard(child: Text('지도 목록을 먼저 불러오세요.'))
        else ...[
          ResponsiveMapFrame(
            map: map,
            child: MapCanvas(
              map: map,
              settings: settings,
              locations: locations,
              selectedLocationId: supervisor.selectedLocationId,
              robot: supervisor.primaryRobot,
              onSelectLocation: (location) =>
                  supervisor.selectLocation(location.locationId),
            ),
          ),
          const SizedBox(height: 20),
          VicaCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '저장 장소 목록',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    OutlinedButton(
                      onPressed: null,
                      child: Text('${locations.length}개'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 10,
                  children: locations.map((location) {
                    final selected =
                        supervisor.selectedLocationId == location.locationId;
                    return ChoiceChip(
                      selected: selected,
                      avatar: Icon(
                        selected ? Icons.check_circle : Icons.location_on,
                        color:
                            selected ? VicaColors.text : VicaColors.primaryDark,
                        size: 18,
                      ),
                      label: Text(location.name),
                      onSelected: (_) =>
                          supervisor.selectLocation(location.locationId),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                if (driving) ...[
                  Text(
                    '$drivingGoal(으)로 주행 중입니다. 도착하거나 취소되면 다시 요청할 수 있습니다.',
                    style: const TextStyle(
                      color: VicaColors.muted,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                FilledButton.icon(
                  // 요청 가능 여부(권한·접근성·E-stop·Nav2)는 Mission Manager가 판정합니다.
                  // 앱은 장소 선택 여부와 진행 중인 주행만 보고 버튼 상태를 정합니다.
                  onPressed: selected == null || driving
                      ? null
                      : () => _requestDrive(context, supervisor, selected),
                  icon: Icon(driving ? Icons.directions_run : Icons.navigation),
                  label: Text(driving ? '주행 중' : '선택 장소로 주행 요청'),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // 실제 로봇이 움직이므로 요청 전에 한 번 확인합니다.
  static Future<void> _requestDrive(
    BuildContext context,
    SupervisorProvider supervisor,
    LocationPoint location,
  ) async {
    final settings = context.read<SettingsProvider>().settings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('원격 주행 요청'),
        content: Text(
          '${location.name}(으)로 주행을 요청합니다.\n'
          '로봇 주변에 사람과 장애물이 없는지 확인하세요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('주행 요청'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    final message = await supervisor.requestDestination(settings, location);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  static LocationPoint? _selectedLocation(
    List<LocationPoint> locations,
    String? selectedId,
  ) {
    for (final location in locations) {
      if (location.locationId == selectedId) {
        return location;
      }
    }
    return null;
  }
}
