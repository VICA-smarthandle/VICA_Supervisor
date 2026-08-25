// 이 파일은 원격 주행 화면으로, 지도별 장소 선택과 주행 요청을 담당합니다.
// 주행 요청은 Mission Manager service를 거치며 Safety 계층을 우회하지 않습니다.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_settings.dart';
import '../models/location_point.dart';
import '../providers/settings_provider.dart';
import '../providers/supervisor_provider.dart';
import '../widgets/initial_pose_card.dart';
import '../widgets/map_canvas.dart';
import '../widgets/vica_ui.dart';

class MapLocationsScreen extends StatefulWidget {
  const MapLocationsScreen({super.key});

  @override
  State<MapLocationsScreen> createState() => _MapLocationsScreenState();
}

class _MapLocationsScreenState extends State<MapLocationsScreen> {
  // 초기 위치 잡기 중인지. 켜져 있을 때만 지도 탭이 '자리 짚기'로 동작합니다.
  // 평소에는 지도를 눌러도 아무 일이 없어야 합니다 -- 원격 주행 화면에서 실수로
  // 자세를 바꾸는 일을 막습니다.
  bool _picking = false;
  Offset? _picked;
  PoseDirection? _direction = PoseDirection.right;

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
    // 주행·일시정지 여부는 Mission Manager가 발행한 goal 이벤트가 /robot_status로
    // 요약되어 들어온 값으로 판단합니다. 앱이 따로 추적하지 않습니다.
    final robot = supervisor.primaryRobot;
    final drivingGoal = robot?.currentGoal.trim() ?? '';
    // 일시정지는 목적지를 기억한 채 멈춘 상태라 current_goal이 남아 있습니다.
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
              pickedLocation: _picking && _picked != null
                  ? LocationPoint(
                      locationId: '_initial_pose',
                      mapId: map.mapId,
                      name: '짚은 자리',
                      x: _picked!.dx,
                      y: _picked!.dy,
                      yaw: 0,
                    )
                  : null,
              poseArrow: _picking && supervisor.poseCheck != null
                  ? MapPoseArrow(
                      x: supervisor.poseCheck!.x,
                      y: supervisor.poseCheck!.y,
                      yawDegrees: supervisor.poseCheck!.yawDegrees,
                      label: '찾아낸 자세',
                    )
                  : null,
              onTapMap: _picking ? _onTapMap : null,
              onSelectLocation: (location) =>
                  supervisor.selectLocation(location.locationId),
            ),
          ),
          const SizedBox(height: 20),
          if (_picking)
            InitialPoseCard(
              picked: _picked,
              direction: _direction,
              result: supervisor.poseCheck,
              busy: supervisor.poseChecking,
              onDirection: (value) => setState(() {
                _direction = value;
                // 방향이 바뀌면 이전 점수는 다른 조건에서 잰 값입니다.
                supervisor.clearPoseCheck();
              }),
              onCheck: () => _checkPose(supervisor),
              onCommit: () => _commitPose(supervisor),
              onReset: () => setState(() {
                _picked = null;
                supervisor.clearPoseCheck();
              }),
              onClose: () => setState(() {
                _picking = false;
                _picked = null;
                supervisor.clearPoseCheck();
              }),
            )
          else
            _initialPoseEntry(context, supervisor, driving || paused),
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
                  // 요청 가능 여부(권한·접근성·E-stop·Nav2)는 Mission Manager가 판정합니다.
                  // 앱은 장소 선택 여부와 진행 중인 주행만 보고 버튼 상태를 정합니다.
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

  void _onTapMap(Offset ros) {
    setState(() => _picked = ros);
    // 자리를 새로 짚으면 이전 점수는 다른 자리의 값입니다. 남겨 두면 옛 %를 보고
    // 확정을 누르게 됩니다.
    context.read<SupervisorProvider>().clearPoseCheck();
  }

  Future<void> _checkPose(SupervisorProvider supervisor) async {
    final spot = _picked;
    if (spot == null) {
      return;
    }
    final settings = context.read<SettingsProvider>().settings;
    final message = await supervisor.checkInitialPose(
      settings,
      x: spot.dx,
      y: spot.dy,
      yawHint: _direction?.yawFor(settings),
    );
    if (!mounted) {
      return;
    }
    // 성공하면 점수 상자가 메시지를 보여준다. 실패(결과 없음)는 상자가 안 뜨니
    // 여기서 알리지 않으면 관리자에게 아무것도 안 보인다.
    if (supervisor.poseCheck == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  // 확정하면 AMCL 이 이 자세를 믿기 시작합니다. 되돌릴 수 없으므로 한 번 묻습니다.
  Future<void> _commitPose(SupervisorProvider supervisor) async {
    final result = supervisor.poseCheck;
    if (result == null || !result.ok) {
      return;
    }
    final settings = context.read<SettingsProvider>().settings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('초기 위치 확정'),
        content: Text(
          '로봇이 여기 있다고 알려 줍니다.\n'
          '(${result.x.toStringAsFixed(2)}, ${result.y.toStringAsFixed(2)}) '
          '${result.yawDegrees.round()}° · 일치도 ${result.score.round()}%\n\n'
          '잘못 잡으면 로봇이 엉뚱한 곳으로 갑니다. 지도 위 화살표가 실제 로봇 위치와 같은지 확인하세요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('확정'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final message = await supervisor.commitInitialPose(
      settings,
      x: result.x,
      y: result.y,
      yaw: result.yaw,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _picking = false;
      _picked = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // 들어가는 문. 주행 중에는 못 들어갑니다 -- 달리는 중에 AMCL 자세를 바꾸면
  // Nav2 가 지금 따라가던 경로를 엉뚱한 곳에서 이어가려 합니다.
  Widget _initialPoseEntry(
    BuildContext context,
    SupervisorProvider supervisor,
    bool busyDriving,
  ) {
    final stack = supervisor.stackStatus;
    final nav2Down = stack != null && !stack.nav2Running;
    final blocked = busyDriving
        ? '주행 중에는 초기 위치를 바꿀 수 없습니다. 먼저 주행을 멈추세요.'
        : (nav2Down ? '주행(Nav2)이 꺼져 있습니다. 먼저 시작하세요.' : '');
    return VicaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.my_location,
                  size: 20, color: VicaColors.primaryDark),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '초기 위치',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            blocked.isEmpty
                ? 'Nav2 를 켠 직후에는 로봇이 자기 위치를 모릅니다. 지도에서 짚어 알려 주세요.'
                : blocked,
            style: const TextStyle(color: VicaColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: blocked.isEmpty
                ? () => setState(() => _picking = true)
                : null,
            icon: const Icon(Icons.add_location_alt_outlined),
            label: const Text('초기 위치 잡기'),
          ),
        ],
      ),
    );
  }

  // 일시정지와 다시 출발은 되돌릴 수 있어 확인 없이 바로 보냅니다.
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

  // 취소는 진행하던 안내가 사라지므로 한 번 확인합니다.
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
