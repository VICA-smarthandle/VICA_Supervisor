import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/location_point.dart';
import '../providers/settings_provider.dart';
import '../providers/supervisor_provider.dart';
import '../widgets/initial_pose_card.dart';
import '../widgets/drive_control_bar.dart';
import '../widgets/drive_map_canvas.dart';
import '../widgets/map_canvas.dart';
import '../widgets/map_picker.dart';
import '../widgets/vica_ui.dart';

class MapLocationsScreen extends StatefulWidget {
  const MapLocationsScreen({super.key});

  @override
  State<MapLocationsScreen> createState() => _MapLocationsScreenState();
}

class _MapLocationsScreenState extends State<MapLocationsScreen> {
  bool _picking = false;
  Offset? _picked;
  PoseDirection? _direction = PoseDirection.right;

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
    final paused = supervisor.navigationPaused;
    final driving = drivingGoal.isNotEmpty && !paused;

    return VicaPage(
      title: '원격 주행',
      children: [
        MapPickerRow(
          supervisor: supervisor,
          settings: settings,
          map: map,
          label: '지도 선택',
          onChanged: (value) {
            if (value != supervisor.selectedMapId) {
              setState(() => _picked = null);
              supervisor.clearPoseCheck();
            }
            supervisor.selectMap(settings, value);
          },
          refreshIcon: Icons.refresh,
          refreshLabel: const Text('새로고침'),
        ),
        const SizedBox(height: 18),
        if (map == null)
          const NoMapCard()
        else ...[
          DriveMapCanvas(
            map: map,
            settings: settings,
            supervisor: supervisor,
            locations: locations,
            selectedLocationId: _picking ? null : supervisor.selectedLocationId,
            showLocationLabels: !_picking,
            pickedLocation: _picking && _picked != null
                ? LocationPoint(
                    locationId: '_initial_pose',
                    mapId: map.mapId,
                    name: '선택 위치',
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
                    label: '확인된 위치',
                  )
                : null,
            scanHits: supervisor.poseCheck?.scanHits.isNotEmpty == true
                ? supervisor.poseCheck!.scanHits
                : supervisor.committedScanHits,
            onTapMap: _picking ? _onTapMap : null,
            onSelectLocation: _picking
                ? null
                : (location) => supervisor.selectLocation(location.locationId),
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
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
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
                    vicaKeepWords(vicaBreakAtSentences(
                      paused
                          ? '$drivingGoal(으)로 가던 중 일시정지했습니다. 다시 출발하거나 취소할 수 있습니다.'
                          : '$drivingGoal(으)로 주행 중입니다.',
                    )),
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
                  DriveControlBar(
                    supervisor: supervisor,
                    paused: paused,
                    cancelLabel: '주행 취소',
                    cancelTitle: '주행 취소',
                    cancelBody: '진행 중인 주행을 취소합니다. 목적지는 지워지며 다시 요청해야 합니다.',
                    keepLabel: '계속 주행',
                  ),
                ],
                if (supervisor.homeBelongsTo(map.mapId) &&
                    supervisor.home != null) ...[
                  const SizedBox(height: 10),
                  const Divider(height: 20),
                  OutlinedButton.icon(
                    onPressed: driving || paused
                        ? null
                        : () => _confirmReturnHome(context, supervisor),
                    icon: const Icon(Icons.home_outlined),
                    label: Text(
                      driving || paused ? '주행 중에는 홈으로 부를 수 없습니다' : '홈으로 복귀',
                    ),
                  ),
                  if (!supervisor.home!.visitedOk) ...[
                    const SizedBox(height: 6),
                    Text(
                      vicaKeepWords(vicaBreakAtSentences(
                        '홈에 아직 가 본 적이 없습니다. 지도 설정 화면에서 확인해주세요.',
                      )),
                      style: const TextStyle(
                          color: VicaColors.muted, fontSize: 12),
                    ),
                  ],
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
    if (supervisor.poseCheck == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _commitPose(SupervisorProvider supervisor) async {
    final result = supervisor.poseCheck;
    if (result == null || !result.ok) {
      return;
    }
    final settings = context.read<SettingsProvider>().settings;
    final confirmed = await showVicaConfirm(
      context,
      icon: Icons.gps_fixed,
      title: '초기 위치 확정',
      body: '로봇이 여기 있다고 알려 줍니다.\n'
          '(${result.x.toStringAsFixed(2)}, ${result.y.toStringAsFixed(2)}) '
          '${result.yawDegrees.round()}° · 일치도 ${result.score.round()}%\n\n'
          '잘못 잡으면 로봇이 엉뚱한 곳으로 갑니다. 지도 위 화살표가 실제 로봇 위치와 같은지 확인하세요.',
      confirmLabel: '확정',
    );
    if (!confirmed || !mounted) {
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
    supervisor.clearPoseCheck();
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _enterPosePicking(SupervisorProvider supervisor) async {
    await supervisor.refreshStackStatus();
    if (!mounted) {
      return;
    }
    final fresh = supervisor.stackStatus;
    if (fresh != null && !fresh.nav2Running) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('주행(Nav2)이 꺼져 있습니다. 확인해주세요.')),
      );
      return;
    }
    supervisor.discardPoseCheck(supervisor.poseCheck);
    setState(() => _picking = true);
  }

  Widget _initialPoseEntry(
    BuildContext context,
    SupervisorProvider supervisor,
    bool busyDriving,
  ) {
    final stack = supervisor.stackStatus;
    final nav2Down = stack != null && !stack.nav2Running;
    final blocked = busyDriving
        ? '주행 중에는 초기 위치를 변경할 수 없습니다. 변경하시려면 주행을 멈추세요.'
        : (nav2Down ? '주행(Nav2)이 꺼져 있습니다. 확인해주세요.' : '');
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
            vicaKeepWords(vicaBreakAtSentences(
              blocked.isEmpty
                  ? 'Nav2 를 켠 직후에는 로봇이 자기 위치를 모릅니다. 초기위치를 설정해주세요.'
                  : blocked,
            )),
            style: const TextStyle(color: VicaColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed:
                blocked.isEmpty ? () => _enterPosePicking(supervisor) : null,
            icon: const Icon(Icons.add_location_alt_outlined),
            label: const Text('초기 위치 잡기'),
          ),
        ],
      ),
    );
  }

  /// 로봇을 홈으로 부릅니다. **관리자 전용 경로입니다.**
  static Future<void> _confirmReturnHome(
    BuildContext context,
    SupervisorProvider supervisor,
  ) async {
    final settings = context.read<SettingsProvider>().settings;
    final confirmed = await showVicaConfirm(
      context,
      icon: Icons.home_outlined,
      title: '홈으로 복귀',
      body: '로봇이 홈 위치로 이동합니다. '
          '경로에 사람과 장애물이 없는지 확인하세요.',
      confirmLabel: '복귀 시작',
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    final message = await supervisor.returnHome(settings);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  static Future<void> _requestDrive(
    BuildContext context,
    SupervisorProvider supervisor,
    LocationPoint location,
  ) async {
    final settings = context.read<SettingsProvider>().settings;
    final confirmed = await showVicaConfirm(
      context,
      icon: Icons.navigation_outlined,
      title: '원격 주행 요청',
      body: '${location.name}(으)로 주행을 요청합니다. '
          '로봇 주변에 사람과 장애물이 없는지 확인하세요.',
      confirmLabel: '주행 요청',
    );
    if (!confirmed || !context.mounted) {
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
