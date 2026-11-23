import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/home_position.dart' show kHomeUnvisitedText;
import '../models/location_point.dart';
import '../models/mission_activity.dart';
import '../models/mode_status.dart';
import '../models/stack_status.dart';
import '../providers/settings_provider.dart';
import '../providers/supervisor_provider.dart';
import '../widgets/initial_pose_card.dart';
import '../widgets/drive_control_bar.dart';
import '../widgets/drive_map_canvas.dart';
import '../widgets/drive_map_change.dart';
import '../widgets/manual_drive_card.dart';
import '../widgets/map_canvas.dart';
import '../widgets/map_fix_card.dart';
import '../widgets/map_picker.dart';
import '../widgets/map_work_layout.dart';
import '../widgets/vica_ui.dart';

const double _driveRowMinWidth = 330;

class MapLocationsScreen extends StatefulWidget {
  const MapLocationsScreen({super.key});

  @override
  State<MapLocationsScreen> createState() => _MapLocationsScreenState();
}

class _MapLocationsScreenState extends State<MapLocationsScreen> {
  bool _picking = false;
  Offset? _picked;
  PoseDirection? _direction = PoseDirection.right;

  bool _manual = false;

  /// 수동 주행을 열어 두는 미션 상태(mission_logic.State). 그 밖은 모두 막습니다.
  static const _manualIdleStates = {
    '',
    'idle',
    'none',
    'arrived',
    'failed',
    'estopped'
  };

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
    final activity = MissionActivity.of(robot);
    final busy = driving || paused || activity != null;
    final String? manualBlocked;
    if (robot == null) {
      manualBlocked = '로봇 상태를 받지 못해 쓸 수 없습니다.';
    } else if (busy ||
        robot.status == 'moving' ||
        supervisor.patrolPhase.active ||
        !_manualIdleStates.contains(robot.dialogState.trim())) {
      manualBlocked = kManualDriveBusyMessage;
    } else {
      manualBlocked = null;
    }

    return MapWorkLayout(
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
          showRefresh: false,
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = !constraints.maxWidth.isFinite ||
                    constraints.maxWidth < _driveRowMinWidth
                ? _driveRowMinWidth
                : constraints.maxWidth;
            return FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: width,
                child: Row(
                  children: [
                    MapRefreshButton(
                      supervisor: supervisor,
                      settings: settings,
                      map: map,
                      icon: Icons.refresh,
                      label: const Text('새로고침'),
                      inRow: true,
                    ),
                    const Spacer(),
                    for (final (label, manual) in const [
                      ('원격 주행', false),
                      ('수동 주행', true),
                    ]) ...[
                      if (manual) const SizedBox(width: 8),
                      MapFixChoiceButton(
                        label: label,
                        width: 92,
                        selected: _manual == manual,
                        onTap: () => setState(() {
                          _manual = manual;
                          if (_manual) {
                            _picking = false;
                            _picked = null;
                            supervisor.clearPoseCheck();
                          }
                        }),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 14),
        DriveMapBanner(viewedMapId: supervisor.selectedMapId),
        if (map == null) ...[
          const NoMapCard(),
          if (_manual) ...[
            const SizedBox(height: 20),
            ManualDriveCard(blockedMessage: manualBlocked),
          ],
        ] else ...[
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
          if (_manual)
            ManualDriveCard(blockedMessage: manualBlocked)
          else if (_picking)
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
            _initialPoseEntry(context, supervisor, busy),
          if (!_manual) const SizedBox(height: 20),
          if (!_manual)
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
                      PressScale(
                          child: OutlinedButton(
                        onPressed: null,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 36),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        child: Text('${locations.length}개'),
                      )),
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
                          color: selected
                              ? VicaColors.text
                              : VicaColors.primaryDark,
                          size: 18,
                        ),
                        label: Text(location.name),
                        onSelected: (_) =>
                            supervisor.selectLocation(location.locationId),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  if (activity != null && activity.lines.isNotEmpty) ...[
                    Text(
                      activity.lines
                          .map((line) =>
                              vicaKeepWords(vicaBreakAtSentences(line)))
                          .join('\n'),
                      style: const TextStyle(
                        color: VicaColors.muted,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ] else if (activity == null && (driving || paused)) ...[
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
                  ] else if (activity == null && supervisor.isDocked) ...[
                    Text(
                      '${vicaKeepWords('도크에 들어가 있습니다.')}\n'
                      '${vicaKeepWords('장소를 고르면 도크에서 먼저 나온 뒤 출발합니다.')}',
                      style: const TextStyle(
                        color: VicaColors.muted,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  PressScale(
                      child: FilledButton.icon(
                    onPressed: selected == null || busy
                        ? null
                        : () => _requestDrive(context, supervisor, selected),
                    icon: Icon(activity != null
                        ? _activityIcon(activity.kind)
                        : driving
                            ? Icons.directions_run
                            : Icons.navigation),
                    label: Text(activity?.lockedRequestLabel ??
                        (driving ? '주행 중' : '선택 장소로 주행 요청')),
                  )),
                  if (activity != null && activity.cancellable) ...[
                    const SizedBox(height: 10),
                    PressScale(
                        child: OutlinedButton.icon(
                      onPressed: () => _confirmActivityCancel(
                        context,
                        supervisor,
                        activity,
                      ),
                      icon: const Icon(Icons.cancel_outlined),
                      label: Text(activity.cancelLabel),
                    )),
                  ] else if (activity == null && (driving || paused)) ...[
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
                  if (activity == null || !activity.isDock)
                    ..._homeDockButtons(context, supervisor, map.mapId,
                        activity, driving, paused, busy),
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

  static bool _nav2Down(StackStatus? stack, ModeStatus? mode) {
    if (mode != null && mode.nav2Up) {
      return false;
    }
    return stack != null && !stack.nav2Running;
  }

  Future<void> _enterPosePicking(SupervisorProvider supervisor) async {
    await supervisor.refreshStackStatus();
    if (!mounted) {
      return;
    }
    if (_nav2Down(supervisor.stackStatus, supervisor.modeStatus)) {
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
    final nav2Down = _nav2Down(supervisor.stackStatus, supervisor.modeStatus);
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
          PressScale(
              child: OutlinedButton.icon(
            onPressed:
                blocked.isEmpty ? () => _enterPosePicking(supervisor) : null,
            icon: const Icon(Icons.add_location_alt_outlined),
            label: const Text('초기 위치 잡기'),
          )),
        ],
      ),
    );
  }

  static IconData _activityIcon(MissionActivityKind kind) => switch (kind) {
        MissionActivityKind.wait => Icons.hourglass_empty,
        MissionActivityKind.approach => Icons.person_outline,
        MissionActivityKind.firstGuide => Icons.record_voice_over_outlined,
        MissionActivityKind.dock => Icons.power,
        MissionActivityKind.undock => Icons.power_off,
      };

  /// 아래 홈·도킹 버튼. 둘 다 누를 수 있으면 한 줄에 반씩, 잠겼으면 잠긴 글자가 길어 한 줄씩.
  static List<Widget> _homeDockButtons(
    BuildContext context,
    SupervisorProvider supervisor,
    String mapId,
    MissionActivity? activity,
    bool driving,
    bool paused,
    bool busy,
  ) {
    final hasHome = supervisor.homeBelongsTo(mapId) && supervisor.home != null;
    final docked = supervisor.isDocked;
    final hasSpot = supervisor.dockSpotFor(mapId) != null;
    final resume = !docked && !busy && supervisor.canResumeUndock;
    final undockPaused = resume && supervisor.undockPaused;
    final showDock = (docked || hasSpot) && !undockPaused;
    if (!hasHome && !showDock && !resume) {
      return const [];
    }
    final lockedText =
        activity?.lockedRequestLabel ?? (driving || paused ? '주행 중' : '');
    final Widget? homeButton = hasHome
        ? PressScale(
            child: OutlinedButton.icon(
            onPressed:
                busy ? null : () => _confirmReturnHome(context, supervisor),
            icon: const Icon(Icons.home_outlined),
            label: Text(
              activity?.homeLockedLabel ??
                  (driving || paused ? '주행 중에는 홈으로 부를 수 없습니다' : '홈으로 복귀'),
            ),
          ))
        : null;
    Widget? dockButton;
    if (showDock) {
      dockButton = PressScale(
          child: docked
              ? OutlinedButton.icon(
                  onPressed:
                      busy ? null : () => _confirmUndock(context, supervisor),
                  icon: const Icon(Icons.power_off),
                  label: const Text('도크에서 나오기'),
                )
              : OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () => _confirmDockStart(context, supervisor),
                  icon: const Icon(Icons.power),
                  label: Text(busy ? '$lockedText에는 도킹을 시작할 수 없습니다' : '도킹 시작'),
                ));
    }
    final Widget? resumeButton = resume
        ? PressScale(
            child: OutlinedButton.icon(
            onPressed: () => _confirmUndockResume(context, supervisor),
            icon: const Icon(Icons.power_off),
            label: Text(undockPaused ? '도크에서 나오기 다시시작' : '도크에서 나오기'),
          ))
        : null;
    return [
      const SizedBox(height: 10),
      const Divider(height: 20),
      if (resumeButton != null && dockButton != null) ...[
        if (homeButton != null) ...[homeButton, const SizedBox(height: 10)],
        Row(
          children: [
            Expanded(child: dockButton),
            const SizedBox(width: 10),
            Expanded(child: resumeButton),
          ],
        ),
      ] else if (resumeButton != null && undockPaused) ...[
        if (homeButton != null) ...[homeButton, const SizedBox(height: 10)],
        resumeButton,
      ] else if (resumeButton != null) ...[
        if (homeButton != null)
          Row(
            children: [
              Expanded(child: homeButton),
              const SizedBox(width: 10),
              Expanded(child: resumeButton),
            ],
          )
        else
          resumeButton,
      ] else if (!busy && homeButton != null && dockButton != null)
        Row(
          children: [
            Expanded(child: homeButton),
            const SizedBox(width: 10),
            Expanded(child: dockButton),
          ],
        )
      else ...[
        if (homeButton != null) homeButton,
        if (homeButton != null && dockButton != null)
          const SizedBox(height: 10),
        if (dockButton != null) dockButton,
      ],
      if (hasHome &&
          supervisor.home!.warning(kHomeUnvisitedText).isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(
          vicaKeepWords(vicaBreakAtSentences(
            supervisor.home!.warning(kHomeUnvisitedText),
          )),
          style: const TextStyle(color: VicaColors.muted, fontSize: 12),
        ),
      ],
    ];
  }

  /// '도킹 시작' 확인(목업 73).
  static Future<void> _confirmDockStart(
    BuildContext context,
    SupervisorProvider supervisor,
  ) async {
    final settings = context.read<SettingsProvider>().settings;
    final confirmed = await showVicaConfirm(
      context,
      icon: Icons.power,
      title: '도킹 시작',
      body: '로봇이 도크 앞으로 이동한 뒤 도크에 들어갑니다.',
      confirmLabel: '시작',
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    final message = await supervisor.startDocking(settings);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// '도크에서 나오기' 확인(목업 67, 문구는 11-18 사용자 지정).
  static Future<void> _confirmUndock(
    BuildContext context,
    SupervisorProvider supervisor,
  ) async {
    final settings = context.read<SettingsProvider>().settings;
    final confirmed = await showVicaConfirm(
      context,
      icon: Icons.power_off,
      title: '도크에서 나오기',
      body: '로봇이 초음파를 켜고 약 70cm 후진 후 제자리 회전합니다. 회전 후 주행 모드로 전환됩니다.',
      confirmLabel: '나오기',
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    final message = await supervisor.undock(settings);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// 나오다 멈춘 자리에서 '도크에서 나오기'(2026-11-19 사용자) — 남은 동작만 이어서 합니다.
  static Future<void> _confirmUndockResume(
    BuildContext context,
    SupervisorProvider supervisor,
  ) async {
    final settings = context.read<SettingsProvider>().settings;
    final confirmed = await showVicaConfirm(
      context,
      icon: Icons.power_off,
      title: supervisor.undockPaused ? '도크에서 나오기 다시시작' : '도크에서 나오기',
      body: '멈춘 자리에서 남은 나오기 동작을 이어서 합니다.',
      confirmLabel: '나오기',
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    final message = await supervisor.undock(settings);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// '대기 취소'·'접근 취소' 확인(목업 44·45). 주행 취소 확인창과 같은 틀입니다.
  static Future<void> _confirmActivityCancel(
    BuildContext context,
    SupervisorProvider supervisor,
    MissionActivity activity,
  ) async {
    final confirmed = await showVicaConfirm(
      context,
      icon: Icons.stop_circle_outlined,
      iconColor: VicaColors.red,
      title: activity.cancelTitle,
      body: activity.cancelBody,
      cancelLabel: activity.keepLabel,
      confirmLabel: activity.confirmLabel,
      danger: true,
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    final now = MissionActivity.of(supervisor.primaryRobot);
    if (now == null || now.kind != activity.kind || !now.cancellable) {
      return;
    }
    await sendRobotCommand(
      context,
      activity.isDock
          ? supervisor.cancelDocking
          : activity.kind == MissionActivityKind.approach
              ? supervisor.cancelApproach
              : supervisor.cancelWait,
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
