import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_settings.dart';
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
    final robot = supervisor.primaryRobot;
    final drivingGoal = robot?.currentGoal.trim() ?? '';
    final paused = robot?.waitingReason.trim() == '일시정지';
    final driving = drivingGoal.isNotEmpty && !paused;

    return VicaPage(
      title: '원격 주행',
      children: [
        VicaFieldWithAction(
          actionWidth: 112,
          field: DropdownButtonFormField<String>(
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
          action: OutlinedButton.icon(
            onPressed: map == null
                ? null
                : () => supervisor.requestLocationList(settings, map.mapId),
            icon: const Icon(Icons.sync, size: 18),
            label: const Text('동기화', maxLines: 1),
          ),
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
                if (driving || paused) ...[
                  Text(
                    paused
                        ? '$drivingGoal(으)로 가던 중 일시정지했습니다. 다시 출발하거나 취소할 수 있습니다.'
                        : '$drivingGoal(으)로 주행 중입니다.',
                    style: const TextStyle(
                      color: VicaColors.muted,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                FilledButton.icon(
                  onPressed: selected == null || driving || paused
                      ? null
                      : () => _requestDrive(context, supervisor, selected),
                  icon: Icon(driving ? Icons.directions_run : Icons.navigation),
                  label: Text(driving ? '주행 중' : '선택 장소로 주행 요청'),
                ),
                if (driving || paused) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _sendMissionCommand(
                            context,
                            paused
                                ? supervisor.resumeNavigation
                                : supervisor.pauseNavigation,
                          ),
                          icon: Icon(
                            paused ? Icons.play_arrow : Icons.pause,
                          ),
                          label: Text(paused ? '다시 출발' : '일시정지'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _confirmCancel(context, supervisor),
                          icon: const Icon(Icons.cancel_outlined),
                          label: const Text('주행 취소'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  static Future<void> _sendMissionCommand(
    BuildContext context,
    Future<String> Function(AppSettings) send,
  ) async {
    final settings = context.read<SettingsProvider>().settings;
    final message = await send(settings);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  static Future<void> _confirmCancel(
    BuildContext context,
    SupervisorProvider supervisor,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('주행 취소'),
        content: const Text('진행 중인 주행을 취소합니다. 목적지는 지워지며 다시 요청해야 합니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('계속 주행'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('취소하기'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    await _sendMissionCommand(context, supervisor.cancelDestination);
  }

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
