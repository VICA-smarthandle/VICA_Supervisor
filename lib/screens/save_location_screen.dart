import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../core/app_settings.dart';
import '../core/contact_phone.dart';
import '../core/location_edit.dart';
import '../core/wait_spot_geometry.dart';
import '../core/destination_categories.dart';
import '../models/home_position.dart';
import '../models/location_point.dart';
import '../models/pose_check_result.dart';
import '../models/vica_map.dart';
import '../providers/settings_provider.dart';
import '../providers/supervisor_provider.dart';
import '../ros/ros_bridge_client.dart';
import '../widgets/home_position_card.dart';
import '../widgets/initial_pose_card.dart' show PoseDirection;
import '../widgets/keepout_card.dart';
import '../widgets/map_canvas.dart';
import '../widgets/map_picker.dart';
import '../models/route_graph.dart' show kRailHandoffMeters;
import '../widgets/rail_card.dart';
import '../widgets/rail_far_place_dialog.dart';
import '../widgets/route_dialogs.dart';
import '../widgets/map_delete_card.dart';
import '../widgets/vica_ui.dart';
import '../widgets/wait_spot_overlay.dart';

/// 지도 설정 화면에서 한 번에 하나만 펼치는 칸입니다.
enum _SettingsPanel { none, location, home, keepout, rail, mapDelete }

class SaveLocationScreen extends StatefulWidget {
  const SaveLocationScreen({super.key});

  @override
  State<SaveLocationScreen> createState() => _SaveLocationScreenState();
}

class _SaveLocationScreenState extends State<SaveLocationScreen> {
  final _uuid = const Uuid();
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _aliasesController = TextEditingController();
  final _buildingController = TextEditingController();
  final _floorController = TextEditingController();
  final _ownerController = TextEditingController();
  final _contactPhoneController = TextEditingController();
  final _unavailableReasonController = TextEditingController();

  Offset? _pickedRos;
  String? _deleteTargetId;

  int _mapPickerResets = 0;

  _SettingsPanel _panel = _SettingsPanel.none;

  HomeCardMode _homeMode = HomeCardMode.idle;
  Offset? _homePicked;
  PoseDirection? _homeDirection;
  PoseCheckResult? _homeStanding;
  SupervisorProvider? _homeStandingFrom;
  bool _homeSending = false;
  String? _editingLocationId;
  LocationPoint? _editingSaved;
  String? _category1;
  String? _category2;
  String _authorization = 'public';
  bool _isApproachable = true;

  PoseDirection? _doorDirection;

  /// '위치 옮기기'(5 cm 패드)를 펼쳤는가.
  bool _moving = false;

  /// 정보 시트의 '바꾸기'로 돌아와 입구 방향 칸을 강조하는 중인가(목업 2′).
  bool _doorHighlight = false;

  LocationPoint? _waitFor;
  Offset? _waitPicked;
  PoseDirection? _waitExit;
  bool _waitMoving = false;

  /// 목록에서 고른 것이 대기 장소인가. 드롭다운 값은 목적지 id 이고, 대기 장소는
  static const _waitKeyPrefix = 'wait:';
  static const _moveStepM = 0.05;

  @override
  void dispose() {
    final standing = _homeStanding;
    final standingFrom = _homeStandingFrom;
    if (standing != null && standingFrom != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => standingFrom.discardPoseCheck(standing),
      );
    }
    _nameController.dispose();
    _aliasesController.dispose();
    _buildingController.dispose();
    _floorController.dispose();
    _ownerController.dispose();
    _contactPhoneController.dispose();
    _unavailableReasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    final supervisor = context.watch<SupervisorProvider>();
    final map = supervisor.selectedMap;
    final locations = supervisor.locationsFor(map?.mapId);
    final deleteTarget = _selectedLocation(locations);
    final draftAny = supervisor.draftLocation;
    final draft =
        draftAny != null && draftAny.mapId == map?.mapId ? draftAny : null;
    final pickedLocation =
        (draft != null || map == null) ? null : _previewLocation(map.mapId);
    final railEditing = map != null &&
        _panel == _SettingsPanel.rail &&
        supervisor.routeEditing &&
        supervisor.routeEditMapId == map.mapId;

    final locationOpen = _panel == _SettingsPanel.location;
    final waitFor = _waitFor;
    final selectedIsWait = locationOpen &&
        _isWaitKey(_deleteTargetId) &&
        deleteTarget?.waitSpot != null;
    final mask = map != null && (waitFor != null || selectedIsWait)
        ? supervisor.wallMaskFor(settings, map)
        : null;
    final waitMarks = [
      for (final location in locations)
        if (location.waitSpot != null &&
            location.locationId != waitFor?.locationId)
          MapWaitSpotMark(
            x: location.waitSpot!.x,
            y: location.waitSpot!.y,
            yawDeg: location.waitSpot!.yaw,
            destX: location.x,
            destY: location.y,
            highlighted: selectedIsWait &&
                location.locationId == deleteTarget?.locationId,
          ),
    ];
    MapRobotOutline? outline;
    if (waitFor != null && _waitPicked != null && _waitExit != null) {
      final yawDeg = _degFor(_waitExit!, settings);
      final gaps = mask == null
          ? null
          : measureWaitSpotGaps(mask, _waitPicked!.dx, _waitPicked!.dy, yawDeg);
      outline = MapRobotOutline(
        x: _waitPicked!.dx,
        y: _waitPicked!.dy,
        yawDeg: yawDeg,
        color: _levelColor(gaps?.worst ?? GapLevel.good),
        showExitLabel: true,
      );
    } else if (selectedIsWait) {
      final spot = deleteTarget!.waitSpot!;
      final gaps = mask == null
          ? null
          : measureWaitSpotGaps(mask, spot.x, spot.y, spot.yaw);
      outline = MapRobotOutline(
        x: spot.x,
        y: spot.y,
        yawDeg: spot.yaw,
        color: _levelColor(gaps?.worst ?? GapLevel.good),
      );
    }
    MapDoorArrow? doorArrow;
    if (_pickedRos != null && _doorDirection != null && draft == null) {
      doorArrow = MapDoorArrow(
        x: _pickedRos!.dx,
        y: _pickedRos!.dy,
        yawDeg: _degFor(_doorDirection!, settings),
      );
    } else if (waitFor != null && waitFor.doorYaw != null) {
      doorArrow =
          MapDoorArrow(x: waitFor.x, y: waitFor.y, yawDeg: waitFor.doorYaw!);
    } else if (locationOpen &&
        _pickedRos == null &&
        draft == null &&
        deleteTarget?.doorYaw != null) {
      doorArrow = MapDoorArrow(
        x: deleteTarget!.x,
        y: deleteTarget.y,
        yawDeg: deleteTarget.doorYaw!,
      );
    }

    return VicaPage(
      title: '지도 설정',
      children: [
        MapPickerRow(
          supervisor: supervisor,
          settings: settings,
          map: map,
          label: '지도 선택',
          dropdownKey: ValueKey('map-picker-$_mapPickerResets'),
          onChanged: (value) =>
              _changeMap(context, supervisor, settings, value),
          refreshIcon: Icons.refresh,
          refreshLabel: const Text('새로고침'),
        ),
        const SizedBox(height: 18),
        if (map == null)
          const NoMapCard()
        else ...[
          ResponsiveMapFrame(
            map: map,
            child: MapCanvas(
              map: map,
              settings: settings,
              locations: locations,
              draftLocation: draft,
              keepoutZones: supervisor.keepoutZonesFor(map.mapId),
              draftKeepoutZone: supervisor.draftKeepoutZone,
              selectedKeepoutZoneId: supervisor.selectedKeepoutZoneId,
              selectedLocationId:
                  locationOpen && _pickedRos == null && waitFor == null
                      ? deleteTarget?.locationId
                      : null,
              waitSpots: waitMarks,
              doorArrow: doorArrow,
              robotOutline: outline,
              ghostPoint: _editingSaved != null && _pickedRos != null
                  ? Offset(_editingSaved!.x, _editingSaved!.y)
                  : null,
              routeGraph:
                  railEditing ? null : supervisor.routeGraphFor(map.mapId),
              routeEditMode: railEditing,
              routeSketch: railEditing ? supervisor.routeSketch : null,
              routePreview: railEditing ? supervisor.routePreview : null,
              routeIssues:
                  railEditing ? supervisor.routeChecks.errors : const [],
              routeSelectedNode: supervisor.routeConnectFrom,
              onRouteDragStart: supervisor.routeDragStart,
              onRouteDragUpdate: supervisor.routeDragUpdate,
              onRouteDragEnd: supervisor.routeDragEnd,
              keepoutEditMode:
                  _panel == _SettingsPanel.keepout && supervisor.keepoutEditing,
              onKeepoutPanStart: supervisor.startKeepoutDrag,
              onKeepoutPanUpdate: supervisor.updateKeepoutDrag,
              onKeepoutPanEnd: () {
                final problem = supervisor.finishKeepoutDrag(map.mapId);
                if (problem != null) {
                  _showSnack(context, problem);
                }
              },
              onSelectKeepoutZone: supervisor.selectKeepoutZone,
              pickedLocation: _homeMode == HomeCardMode.picking
                  ? _homePickedMarker(map.mapId)
                  : waitFor != null
                      ? _waitPickedMarker(map.mapId)
                      : pickedLocation,
              poseArrow: _homeArrow(settings),
              homePoint: supervisor.homePointFor(map.mapId),
              onTapMap: (ros) {
                if (railEditing) {
                  supervisor.routeTap(ros);
                  return;
                }
                if (_homeMode == HomeCardMode.picking) {
                  setState(() => _homePicked = ros);
                  return;
                }
                if (_panel != _SettingsPanel.location) {
                  return;
                }
                if (_waitFor != null) {
                  setState(() => _waitPicked = ros);
                  return;
                }
                if (_editingSaved != null) {
                  setState(() => _pickedRos = ros);
                  return;
                }
                supervisor.setDraftLocation(null);
                _resetLocationInput();
                setState(() => _pickedRos = ros);
              },
            ),
          ),
          const SizedBox(height: 14),
          VicaExpandPanel(
            title: '장소 저장',
            icon: Icons.add_location_alt_outlined,
            summary: '${locations.length}개',
            expanded: _panel == _SettingsPanel.location,
            onTap: () =>
                _openPanel(context, supervisor, _SettingsPanel.location),
            child: _locationPanelBody(
              context,
              supervisor,
              settings,
              map.mapId,
              locations,
              draft,
              deleteTarget,
            ),
          ),
          VicaExpandPanel(
            title: '홈 위치',
            icon: Icons.home_outlined,
            summary:
                supervisor.homeBelongsTo(map.mapId) && supervisor.home != null
                    ? '지정됨'
                    : '없음',
            expanded: _panel == _SettingsPanel.home,
            onTap: () => _openPanel(context, supervisor, _SettingsPanel.home),
            child: HomePositionCard(
              framed: false,
              home:
                  supervisor.homeBelongsTo(map.mapId) ? supervisor.home : null,
              mode: _homeMode,
              busy: supervisor.homeBusy || _homeSending,
              picked: _homePicked,
              direction: _homeDirection,
              standingResult: _homeStanding,
              canSendRobot: _canSendRobot(supervisor),
              blockedReason: _blockedReason(supervisor),
              onStartPicking: () => setState(() {
                _dropHomeStanding(supervisor);
                _homeMode = HomeCardMode.picking;
                _homePicked = null;
                _homeDirection = null;
              }),
              onStartStanding: () => setState(() {
                _dropHomeStanding(supervisor);
                _homeMode = HomeCardMode.standing;
                _homePicked = null;
                _homeDirection = null;
              }),
              onDirection: (value) => setState(() => _homeDirection = value),
              onCheckStanding: () => _checkStandingHome(context, supervisor),
              onSave: () => _saveHome(context, supervisor, map.mapId, settings),
              onCancel: () => setState(() => _foldHomeWork(supervisor)),
              onGoHome: () => _goHome(context, supervisor),
              onDelete: () =>
                  _confirmDeleteHome(context, supervisor, map.mapId),
            ),
          ),
          VicaExpandPanel(
            title: '금지구역',
            icon: Icons.block_outlined,
            summary: '${supervisor.keepoutZonesFor(map.mapId).length}개',
            summaryColor: supervisor.keepoutEditing ? VicaColors.primary : null,
            expanded: _panel == _SettingsPanel.keepout,
            onTap: () =>
                _openPanel(context, supervisor, _SettingsPanel.keepout),
            child: KeepoutCard(
              zones: supervisor.keepoutZonesFor(map.mapId),
              selectedZoneId: supervisor.selectedKeepoutZoneId,
              editing: supervisor.keepoutEditing,
              drivingHold: (supervisor.primaryRobot?.currentGoal.trim() ?? '')
                  .isNotEmpty,
              state: supervisor.keepoutState,
              message: supervisor.keepoutMessage,
              maskApplied: supervisor.keepoutMaskApplied,
              connected:
                  supervisor.connectionState == RosConnectionState.connected,
              hasPending: supervisor.hasPendingKeepoutZone,
              onStartEdit: () => supervisor.enterKeepoutEdit(map.mapId),
              onConfirmPending: () =>
                  supervisor.confirmPendingKeepoutZone(map.mapId),
              onCancel: () => supervisor.cancelKeepoutEdit(map.mapId),
              onSave: () =>
                  _saveKeepout(context, supervisor, settings, map.mapId),
              onDeleteSelected: () =>
                  supervisor.deleteSelectedKeepoutZone(map.mapId),
              onClearAll: () => supervisor.clearKeepoutZones(map.mapId),
              onReload: () =>
                  supervisor.requestKeepoutList(settings, map.mapId),
              onSelect: supervisor.selectKeepoutZone,
            ),
          ),
          VicaExpandPanel(
            title: '레일',
            icon: Icons.alt_route,
            summary: _railSummary(supervisor, map.mapId),
            summaryColor: railEditing ? VicaColors.primary : null,
            expanded: _panel == _SettingsPanel.rail,
            onTap: () => _openPanel(context, supervisor, _SettingsPanel.rail),
            child: RailCard(
              info: supervisor.routeInfoFor(map.mapId),
              editing: railEditing,
              state: supervisor.routeState,
              message: supervisor.routeMessage,
              connected:
                  supervisor.connectionState == RosConnectionState.connected,
              drivingHold: (supervisor.primaryRobot?.currentGoal.trim() ?? '')
                  .isNotEmpty,
              sketch: supervisor.routeSketch,
              tool: supervisor.routeTool,
              checks: supervisor.routeChecks,
              onStartEdit: () => supervisor.enterRouteEdit(settings, map),
              onDraft: () => _railDraft(context, supervisor, settings, map),
              onReload: () {
                supervisor.requestRouteInfo(settings, map.mapId);
                supervisor.loadRouteGraph(settings, map.mapId);
              },
              onSave: () => _railSave(context, supervisor, settings, map),
              onCancel: supervisor.cancelRouteEdit,
              onTool: supervisor.setRouteTool,
            ),
          ),
          VicaExpandPanel(
            title: '지도 관리',
            icon: Icons.delete_outline,
            summary: '${supervisor.maps.length}개',
            expanded: _panel == _SettingsPanel.mapDelete,
            onTap: () =>
                _openPanel(context, supervisor, _SettingsPanel.mapDelete),
            child: const MapDeleteCard(framed: false),
          ),
        ],
      ],
    );
  }

  /// 칸을 펼치거나 접습니다. 한 번에 하나만 펼칩니다.
  Future<void> _openPanel(
    BuildContext context,
    SupervisorProvider supervisor,
    _SettingsPanel next,
  ) async {
    final target = _panel == next ? _SettingsPanel.none : next;

    if (_panel == _SettingsPanel.keepout &&
        target != _SettingsPanel.keepout &&
        supervisor.keepoutEditing) {
      if (!await _leaveKeepoutEdit(context, supervisor)) {
        return;
      }
    }

    if (_panel == _SettingsPanel.rail &&
        target != _SettingsPanel.rail &&
        supervisor.routeEditing) {
      if (!context.mounted || !await _leaveRailEdit(context, supervisor)) {
        return;
      }
    }
    if (target == _SettingsPanel.rail && context.mounted) {
      final settings = context.read<SettingsProvider>().settings;
      final mapId = supervisor.selectedMap?.mapId;
      if (mapId != null) {
        supervisor.requestRouteInfo(settings, mapId);
      }
    }

    setState(() {
      _panel = target;
      if (target != _SettingsPanel.location) {
        _foldLocationWork();
      }
      if (target != _SettingsPanel.home) {
        _foldHomeWork(supervisor);
      }
    });
  }

  /// 지도를 바꿉니다. 칸을 바꿀 때([_openPanel])와 같은 정리를 합니다.
  Future<void> _changeMap(
    BuildContext context,
    SupervisorProvider supervisor,
    AppSettings settings,
    String? mapId,
  ) async {
    if (mapId == supervisor.selectedMapId) {
      return;
    }
    var leave = true;
    final draft = supervisor.draftLocation;
    if (draft != null) {
      leave = await showVicaConfirm(
        context,
        icon: Icons.place_outlined,
        iconColor: VicaColors.warning,
        title: '저장하지 않은 장소가 있습니다',
        body: "'${draft.name}'을(를) 아직 ROS2에 저장하지 않았습니다. "
            '지도를 바꾸면 사라집니다.',
        cancelLabel: '남아서 저장',
        confirmLabel: '버리고 바꾸기',
        confirmIcon: Icons.delete_outline,
        danger: true,
      );
      if (!context.mounted) {
        return;
      }
    }
    if (leave && supervisor.keepoutEditing) {
      leave = await _leaveKeepoutEdit(context, supervisor);
    }
    if (leave && supervisor.routeEditing) {
      leave = context.mounted && await _leaveRailEdit(context, supervisor);
    }
    if (!mounted) {
      return;
    }
    if (!leave) {
      setState(() => _mapPickerResets += 1);
      return;
    }
    if (draft != null) {
      supervisor.setDraftLocation(null);
    }
    setState(() {
      _foldLocationWork();
      _foldHomeWork(supervisor);
      _deleteTargetId = null;
    });
    supervisor.selectMap(settings, mapId);
    if (_panel == _SettingsPanel.rail && mapId != null) {
      supervisor.requestRouteInfo(settings, mapId);
    }
  }

  /// 저장하지 않은 금지구역 편집을 두고 나가도 되는지 묻습니다. 나가면 편집을
  Future<bool> _leaveKeepoutEdit(
    BuildContext context,
    SupervisorProvider supervisor,
  ) async {
    final mapId = supervisor.selectedMap?.mapId;
    final leave = await showVicaConfirm(
      context,
      icon: Icons.shield_outlined,
      title: '저장하지 않은 금지구역이 있습니다',
      body: '편집을 취소하고 넘어갈까요?',
      cancelLabel: '계속 편집',
      confirmLabel: '편집 취소',
    );
    if (!leave) {
      return false;
    }
    if (mapId != null) {
      supervisor.cancelKeepoutEdit(mapId);
    }
    return true;
  }

  /// 레일 편집을 닫습니다. 바뀐 것이 있으면 먼저 묻습니다(팝업 A).
  Future<bool> _leaveRailEdit(
    BuildContext context,
    SupervisorProvider supervisor,
  ) async {
    if (supervisor.routeDirty && !await showRouteLeaveDialog(context)) {
      return false;
    }
    supervisor.cancelRouteEdit();
    return true;
  }

  void _foldLocationWork() {
    _pickedRos = null;
    _editingSaved = null;
    _resetLocationInput();
    _clearWaitPick();
  }

  void _foldHomeWork(SupervisorProvider supervisor) {
    _dropHomeStanding(supervisor);
    _homeMode = HomeCardMode.idle;
    _homePicked = null;
    _homeDirection = null;
  }

  void _dropHomeStanding(SupervisorProvider supervisor) {
    supervisor.discardPoseCheck(_homeStanding);
    _homeStanding = null;
  }

  String _railSummary(SupervisorProvider supervisor, String mapId) {
    if (supervisor.routeEditing && supervisor.routeEditMapId == mapId) {
      return '편집 중';
    }
    final info = supervisor.routeInfoFor(mapId);
    if (info == null) {
      return supervisor.routeGraphFor(mapId) == null ? '없음' : '있음';
    }
    if (!info.found) {
      return '없음';
    }
    final nodes = info.checks.summary.nodeCount;
    return info.status == 'apply_pending'
        ? '적용 대기 · 노드 $nodes'
        : '적용됨 · 노드 $nodes';
  }

  /// 자동 초안. 지금 레일이나 편집 중인 스케치가 있으면 먼저 묻습니다(팝업 B).
  Future<void> _railDraft(
    BuildContext context,
    SupervisorProvider supervisor,
    AppSettings settings,
    VicaMap map,
  ) async {
    final hasSomething = supervisor.routeInfoFor(map.mapId)?.found == true ||
        (supervisor.routeEditing && !supervisor.routeSketch.isEmpty);
    if (hasSomething && !await showRouteDraftDialog(context)) {
      return;
    }
    await supervisor.requestRouteDraft(settings, map);
  }

  Future<void> _railSave(
    BuildContext context,
    SupervisorProvider supervisor,
    AppSettings settings,
    VicaMap map, {
    bool overwrite = false,
  }) async {
    final outcome =
        await supervisor.saveRoute(settings, map.mapId, overwrite: overwrite);
    if (!context.mounted) {
      return;
    }
    switch (outcome) {
      case RouteSaveOutcome.saved:
        _showSnack(context, supervisor.routeMessage);
      case RouteSaveOutcome.conflict:
        final choice = await showRouteConflictDialog(context);
        if (!context.mounted || choice == null) {
          return;
        }
        if (choice == RouteConflictChoice.overwrite) {
          await _railSave(context, supervisor, settings, map, overwrite: true);
        } else {
          await supervisor.reloadRouteDiscardingEdits(settings, map);
        }
      case RouteSaveOutcome.checkFailed:
      case RouteSaveOutcome.failed:
        break;
    }
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _locationPanelBody(
    BuildContext context,
    SupervisorProvider supervisor,
    AppSettings settings,
    String mapId,
    List<LocationPoint> locations,
    LocationPoint? draft,
    LocationPoint? deleteTarget,
  ) {
    final waitFor = _waitFor;
    if (waitFor != null) {
      return _waitPickBody(context, supervisor, settings, waitFor);
    }
    if (draft == null && _pickedRos != null) {
      return _pickBody(context, supervisor, mapId, locations, settings);
    }
    final waitCount = locations.where((l) => l.waitSpot != null).length;
    final selectedIsWait =
        _isWaitKey(_deleteTargetId) && deleteTarget?.waitSpot != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (draft == null) ...[
          Text(
            vicaKeepWords(vicaBreakAtSentences(
              '지도를 눌러 저장할 위치를 찍으세요. 다시 누르면 점이 옮겨갑니다.',
            )),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 18),
          const Divider(height: 1, color: VicaColors.border),
          const SizedBox(height: 14),
        ],
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: 8,
          children: [
            Text(
              '저장된 장소 ${locations.length}개',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              '대기 장소 $waitCount개',
              style: const TextStyle(fontSize: 13, color: VicaColors.muted),
            ),
          ],
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: selectedIsWait
              ? '$_waitKeyPrefix${deleteTarget!.locationId}'
              : deleteTarget?.locationId,
          decoration: const InputDecoration(labelText: '장소 선택'),
          isExpanded: true,
          itemHeight: null,
          items: [
            for (final location in locations) ...[
              DropdownMenuItem(
                value: location.locationId,
                child: _LocationItem(location: location),
              ),
              if (location.waitSpot != null)
                DropdownMenuItem(
                  value: '$_waitKeyPrefix${location.locationId}',
                  child: _WaitItem(location: location),
                ),
            ],
          ],
          selectedItemBuilder: (context) => [
            for (final location in locations) ...[
              _selectedText(location.name),
              if (location.waitSpot != null)
                _selectedText('└ ${location.waitSpotName}'),
            ],
          ],
          onChanged: (value) => setState(() => _deleteTargetId = value),
        ),
        const SizedBox(height: 12),
        if (deleteTarget != null && selectedIsWait)
          ..._selectedWaitBody(context, supervisor, settings, deleteTarget)
        else if (deleteTarget != null)
          ..._selectedDestinationBody(
            context,
            supervisor,
            settings,
            deleteTarget,
            mapId,
            locations,
            draft,
          ),
        if (draft != null) ...[
          const SizedBox(height: 14),
          _DraftSummary(location: draft),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _editDraft(
              context,
              supervisor,
              draft,
              mapId,
              locations,
            ),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('임시 저장 장소 수정'),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: () => _saveDraftToRos(context, supervisor, settings),
            icon: const Icon(Icons.cloud_upload),
            label: const Text('ROS2에 장소 저장'),
          ),
        ],
      ],
    );
  }

  Widget _selectedText(String text) => Align(
        alignment: Alignment.centerLeft,
        child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
      );

  /// 목적지를 골랐을 때(목업 15): 위치·입구 방향·대기 장소 한눈에 + 수정·삭제.
  List<Widget> _selectedDestinationBody(
    BuildContext context,
    SupervisorProvider supervisor,
    AppSettings settings,
    LocationPoint target,
    String mapId,
    List<LocationPoint> locations,
    LocationPoint? draft,
  ) {
    final spot = target.waitSpot;
    return [
      _InfoBox(rows: [
        (
          '위치',
          'x ${_coord(target.x)} · y ${_coord(target.y)}',
          null,
        ),
        (
          '입구 방향',
          target.doorYaw == null
              ? '없음'
              : _directionLabel(
                  _directionFromYawDeg(target.doorYaw!, settings)),
          target.doorYaw == null ? VicaColors.warning : null,
        ),
        (
          '대기 장소',
          spot == null ? '없음' : '${target.waitSpotName} · ${spot.placePhrase}',
          null,
        ),
      ]),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: draft != null
                  ? null
                  : () => _editSavedLocation(context, target, settings),
              icon: const Icon(Icons.edit_location_alt_outlined),
              label: Text(vicaKeepWords('선택 장소 수정')),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () =>
                  _deleteDestination(context, supervisor, settings, target),
              icon: const Icon(Icons.delete_outline),
              label: Text(vicaKeepWords('선택 장소 삭제')),
            ),
          ),
        ],
      ),
      if (spot == null) ...[
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: target.doorYaw == null || draft != null
              ? null
              : () => _startWaitPick(target),
          style: OutlinedButton.styleFrom(
            foregroundColor: VicaColors.primaryDark,
            side: const BorderSide(color: VicaColors.primary),
          ),
          child: Text(vicaKeepWords('${target.name}에 대기 장소 추가')),
        ),
        if (target.doorYaw == null) ...[
          const SizedBox(height: 6),
          _hint('입구 방향이 없어 대기 장소를 정할 수 없습니다. '
              '선택 장소 수정에서 입구 방향을 먼저 정하세요.'),
        ],
      ],
      const SizedBox(height: 8),
      _hint("'선택 장소 수정'을 누르면 지도에서 위치와 입구 방향부터 고칩니다. "
          "그다음 '수정 내용 입력'으로 이름·분류를 고칩니다."),
    ];
  }

  /// 대기 장소를 골랐을 때(목업 6): 목적지·멘트 위치·나가는 방향·가장 가까운 벽 +
  List<Widget> _selectedWaitBody(
    BuildContext context,
    SupervisorProvider supervisor,
    AppSettings settings,
    LocationPoint target,
  ) {
    final spot = target.waitSpot!;
    final map = supervisor.selectedMap;
    final mask = map == null ? null : supervisor.wallMaskFor(settings, map);
    final gaps = mask == null
        ? null
        : measureWaitSpotGaps(mask, spot.x, spot.y, spot.yaw);
    final distance = _distance(target.x, target.y, spot.x, spot.y);
    final nearest = gaps?.nearestSide;
    return [
      _InfoBox(rows: [
        ('목적지', target.name, null),
        (
          '안내 멘트 위치',
          '${spot.placePhrase} · ${distance.toStringAsFixed(1)} m',
          null,
        ),
        (
          '나가는 방향',
          _directionLabel(_directionFromYawDeg(spot.yaw, settings)),
          null,
        ),
        (
          '가장 가까운 벽',
          nearest == null
              ? '잴 수 없음'
              : '${nearest.$1} ${formatGap(nearest.$2)} · '
                  '${_shortLevel(nearest.$3)}',
          nearest == null ? null : _levelTextColor(nearest.$3),
        ),
      ]),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: _canSendRobot(supervisor)
            ? () => _goTryWaitSpot(context, supervisor, settings, target)
            : null,
        icon: const Icon(Icons.near_me_outlined),
        label: Text(vicaKeepWords('대기 장소로 가보기 (확인용)')),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => _startWaitPick(target, keep: true),
              child: Text(vicaKeepWords('대기 장소 옮기기')),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton(
              onPressed: () =>
                  _removeWaitSpot(context, supervisor, settings, target),
              style: OutlinedButton.styleFrom(foregroundColor: VicaColors.red),
              child: Text(vicaKeepWords('대기 장소만 지우기')),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      _hint('이름·분류 같은 목적지 정보는 '
          "'${target.name}'${_objectParticle(target.name)} 골라서 고칩니다. "
          '대기 장소는 원격 주행 목록에 나오지 않습니다.'),
    ];
  }

  Widget _hint(String text) => Text(
        vicaKeepWords(text),
        style: const TextStyle(
          fontSize: 12,
          height: 1.5,
          color: VicaColors.muted,
        ),
      );

  /// 점을 찍었거나 기존 목적지를 고치는 중(목업 1·1′·2′·16·16′).
  Widget _pickBody(
    BuildContext context,
    SupervisorProvider supervisor,
    String mapId,
    List<LocationPoint> locations,
    AppSettings settings,
  ) {
    final picked = _pickedRos!;
    final editing = _editingSaved;
    final moved = editing == null
        ? null
        : movedFromOriginalText(
            editing.x,
            editing.y,
            picked.dx,
            picked.dy,
            upIsPlusY: settings.flipMapY,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (editing != null) ...[
          Row(
            children: [
              const _Badge(
                text: '수정 중',
                background: Color(0xFFFBF1E2),
                foreground: Color(0xFF7E5716),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  editing.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (_doorHighlight) ...[
          _NoticeBox(
            text: '방향을 선택 후 '
                '${editing == null ? '장소 정보 입력' : '수정 내용 입력'}을 누르세요. '
                '입력하신 정보는 남아있습니다.',
          ),
          const SizedBox(height: 12),
        ],
        _PositionStep(
          picked: picked,
          moving: _moving,
          movedText: moved,
          onStartMove: () => setState(() => _moving = true),
          onDoneMove: () => setState(() => _moving = false),
          onStep: (direction) => setState(
            () => _pickedRos = _stepped(picked, direction, settings),
          ),
          onRestore: editing == null
              ? null
              : () => setState(
                    () => _pickedRos = Offset(editing.x, editing.y),
                  ),
        ),
        const SizedBox(height: 12),
        _DirectionStep(
          title: '입구 방향 (지도 그림 기준)',
          selected: _doorDirection,
          collapsed: _moving,
          highlighted: _doorHighlight,
          onSelect: (direction) => setState(() => _doorDirection = direction),
        ),
        if (editing == null && !_doorHighlight && !_moving) ...[
          const SizedBox(height: 12),
          const _NoticeBox(
            text: '도착 시 안내할 입구의 방향입니다.\n'
                '물류배송 때는 로봇이 선택한 방향으로 정렬합니다',
            icon: false,
          ),
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: _doorDirection == null
                    ? null
                    : () => _showLocationInfoSheet(
                          context,
                          supervisor,
                          mapId,
                          locations,
                        ),
                child: Text(vicaKeepWords(
                  editing == null ? '장소 정보 입력' : '수정 내용 입력',
                )),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: _clearPickedLocation,
                child: Text(editing == null ? '선택 취소' : '수정 취소'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 대기 장소 찍기(목업 4·4′).
  Widget _waitPickBody(
    BuildContext context,
    SupervisorProvider supervisor,
    AppSettings settings,
    LocationPoint dest,
  ) {
    final picked = _waitPicked;
    final exit = _waitExit;
    final map = supervisor.selectedMap;
    final mask = map == null ? null : supervisor.wallMaskFor(settings, map);
    final maskFailed = map != null && supervisor.wallMaskFailed(map.mapId);
    final placement = picked == null || dest.doorYaw == null
        ? null
        : waitSpotPlacement(
            destX: dest.x,
            destY: dest.y,
            doorYawDeg: dest.doorYaw!,
            spotX: picked.dx,
            spotY: picked.dy,
          );
    final gaps = picked == null || exit == null || mask == null
        ? null
        : measureWaitSpotGaps(
            mask, picked.dx, picked.dy, _degFor(exit, settings));
    final wallBlocked = gaps != null &&
        (gaps.leftLevel == GapLevel.blocked ||
            gaps.rightLevel == GapLevel.blocked);
    final frontBlocked = gaps != null && gaps.frontLevel == GapLevel.blocked;
    final doorway = placement?.inDoorway ?? false;
    final canSave = picked != null &&
        exit != null &&
        placement != null &&
        !doorway &&
        (gaps != null ? gaps.worst != GapLevel.blocked : maskFailed);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '대기 장소 · ${dest.name}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        if (picked != null)
          _PositionStep(
            picked: picked,
            moving: _waitMoving,
            onStartMove: () => setState(() => _waitMoving = true),
            onDoneMove: () => setState(() => _waitMoving = false),
            onStep: (direction) => setState(
              () => _waitPicked = _stepped(picked, direction, settings),
            ),
          ),
        const SizedBox(height: 12),
        _DirectionStep(
          title: '나가는 방향 (지도 그림 기준)',
          selected: exit,
          collapsed: _waitMoving,
          onSelect: (direction) => setState(() => _waitExit = direction),
        ),
        if (placement != null) ...[
          const SizedBox(height: 12),
          _NoticeBox(
            title: '안내 멘트에 들어갈 위치',
            text: doorway
                ? '입구 앞'
                : '${waitPlacePhrase(placement.side!)} · '
                    '입구에서 ${placement.distance.toStringAsFixed(1)} m',
            icon: false,
            danger: doorway,
          ),
        ],
        if (picked != null && exit != null) ...[
          const SizedBox(height: 10),
          _GapBox(gaps: gaps, maskFailed: maskFailed),
        ],
        if (doorway || wallBlocked || frontBlocked) ...[
          const SizedBox(height: 10),
          _NoticeBox(
            danger: true,
            text: doorway
                ? '입구 앞은 사람이 드나드는 길입니다. 입구 옆이나 맞은편에 찍어 주세요.'
                : wallBlocked
                    ? '벽에서 7 cm 이상 떼어 찍어 주세요. 이보다 가까우면 경로 계획기가 '
                        '이 자리를 벽 속으로 봅니다.'
                    : '나가는 방향 바로 앞에 벽이 있습니다. 방향이나 자리를 바꿔 주세요.',
          ),
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: canSave
                    ? () => _saveWaitSpot(
                          context,
                          supervisor,
                          settings,
                          dest,
                          WaitSpot(
                            x: picked.dx,
                            y: picked.dy,
                            yaw: _degFor(exit, settings),
                            side: placement.side!,
                          ),
                        )
                    : null,
                child: Text(vicaKeepWords('대기 장소 저장')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(_clearWaitPick),
                child: const Text('취소'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  bool _isWaitKey(String? key) => key?.startsWith(_waitKeyPrefix) ?? false;

  void _clearWaitPick() {
    _waitFor = null;
    _waitPicked = null;
    _waitExit = null;
    _waitMoving = false;
  }

  /// 대기 장소 찍기를 시작합니다. [keep] 이면 지금 대기 장소에서 시작합니다(옮기기).
  void _startWaitPick(LocationPoint dest, {bool keep = false}) {
    final settings = context.read<SettingsProvider>().settings;
    final spot = keep ? dest.waitSpot : null;
    setState(() {
      _waitFor = dest;
      _waitPicked = spot == null ? null : Offset(spot.x, spot.y);
      _waitExit =
          spot == null ? null : _directionFromYawDeg(spot.yaw, settings);
      _waitMoving = false;
      _panel = _SettingsPanel.location;
    });
  }

  LocationPoint? _waitPickedMarker(String mapId) {
    final spot = _waitPicked;
    if (spot == null) {
      return null;
    }
    return LocationPoint(
      locationId: '_wait_pick',
      mapId: mapId,
      name: '대기 장소',
      x: spot.dx,
      y: spot.dy,
      yaw: 0,
    );
  }

  /// 대기 장소를 저장합니다. 목적지를 통째로 다시 보냅니다(같은 id 라 덮어씀).
  void _saveWaitSpot(
    BuildContext context,
    SupervisorProvider supervisor,
    AppSettings settings,
    LocationPoint dest,
    WaitSpot spot,
  ) {
    final (sent, _) =
        supervisor.saveLocation(settings, dest.copyWith(waitSpot: spot));
    if (!sent) {
      _showSnack(context, 'rosbridge 연결이 없어 대기 장소를 저장하지 못했습니다.');
      return;
    }
    setState(() {
      _clearWaitPick();
      _deleteTargetId = '$_waitKeyPrefix${dest.locationId}';
    });
    _showSnack(context, '${dest.waitSpotName}를 저장했습니다.');
  }

  Future<void> _removeWaitSpot(
    BuildContext context,
    SupervisorProvider supervisor,
    AppSettings settings,
    LocationPoint dest,
  ) async {
    final (sent, _) =
        supervisor.saveLocation(settings, dest.copyWith(clearWaitSpot: true));
    if (!sent) {
      _showSnack(context, 'rosbridge 연결이 없어 대기 장소를 지우지 못했습니다.');
      return;
    }
    setState(() => _deleteTargetId = dest.locationId);
    _showSnack(context, '${dest.waitSpotName}를 지웠습니다.');
  }

  WaitSpot? _resideWaitSpot(WaitSpot? spot, Offset dest, double doorDeg) {
    if (spot == null) {
      return null;
    }
    final side = waitSpotPlacement(
      destX: dest.dx,
      destY: dest.dy,
      doorYawDeg: doorDeg,
      spotX: spot.x,
      spotY: spot.y,
    ).side;
    if (side == null || side == spot.side) {
      return spot;
    }
    return WaitSpot(x: spot.x, y: spot.y, yaw: spot.yaw, side: side);
  }

  /// 대기 장소가 이 목적지의 입구 앞(사람이 드나드는 띠)에 놓였는가.
  bool _waitSpotInDoorway(LocationPoint dest) {
    final spot = dest.waitSpot;
    final door = dest.doorYaw;
    if (spot == null || door == null) {
      return false;
    }
    return waitSpotPlacement(
      destX: dest.x,
      destY: dest.y,
      doorYawDeg: door,
      spotX: spot.x,
      spotY: spot.y,
    ).inDoorway;
  }

  /// 목적지 삭제. 대기 장소가 있으면 함께 지워지므로 먼저 묻습니다(목업 7).
  Future<void> _deleteDestination(
    BuildContext context,
    SupervisorProvider supervisor,
    AppSettings settings,
    LocationPoint target,
  ) async {
    if (target.waitSpot != null) {
      final confirmed = await showVicaConfirm(
        context,
        icon: Icons.delete_outline,
        iconColor: VicaColors.red,
        title: '${target.name}${_objectParticle(target.name)} 지울까요?',
        body: '이 장소의 대기 장소도 함께 지워집니다.\n지운 뒤에는 되돌릴 수 없습니다.',
        rows: [
          VicaDialogRow(label: '장소', value: target.name),
          VicaDialogRow(label: '함께 지워짐', value: target.waitSpotName),
        ],
        confirmLabel: '둘 다 지우기',
        danger: true,
      );
      if (!confirmed || !context.mounted) {
        return;
      }
    }
    supervisor.deleteLocation(settings, target);
  }

  /// 대기 장소로 가보기(목업 9). 등록이 맞는지 확인하는 이동입니다.
  Future<void> _goTryWaitSpot(
    BuildContext context,
    SupervisorProvider supervisor,
    AppSettings settings,
    LocationPoint target,
  ) async {
    final spot = target.waitSpot!;
    final confirmed = await showVicaConfirm(
      context,
      icon: Icons.near_me_outlined,
      title: '대기 장소로 가보기',
      body: '등록이 맞는지 확인하는 이동입니다.',
      rows: [
        VicaDialogRow(label: '가는 곳', value: target.waitSpotName),
        VicaDialogRow(
          label: '나가는 방향',
          value: _directionLabel(_directionFromYawDeg(spot.yaw, settings)),
        ),
      ],
      content: const _NoticeBox(
        text: '로봇 주변이 비어 있는지 먼저 확인하세요. 안내 중에는 누를 수 없습니다.',
        warning: true,
      ),
      confirmLabel: '이동 시작',
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    final message = await supervisor.requestWaitSpot(settings, target);
    _toast(message);
  }

  /// 새 목적지를 젯슨에 저장한 직후 묻습니다(목업 3).
  Future<void> _askWaitSpot(BuildContext context, LocationPoint saved) async {
    final pick = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => VicaDialog(
        icon: Icons.place_outlined,
        title: '대기 장소도 지정할까요?',
        body: '목적지에서 조금 떨어져 대기할 장소입니다.\n저장하지 않으면 목적지에서 대기합니다.',
        rows: [VicaDialogRow(label: '장소', value: saved.name)],
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 4),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('대기 장소 찍기'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('지정하지 않기'),
            ),
          ],
        ),
      ),
    );
    if (pick == true && mounted) {
      _startWaitPick(saved);
    }
  }

  /// 대기 장소가 있는 목적지를 1 m 이상 옮겨 저장했을 때(목업 8).
  Future<void> _askRepickAfterMove(
    BuildContext context,
    LocationPoint before,
    LocationPoint after,
  ) async {
    final spot = after.waitSpot!;
    final moved = _distance(before.x, before.y, after.x, after.y);
    final repick = await showVicaConfirm(
      context,
      icon: Icons.open_with,
      title: '목적지를 ${moved.toStringAsFixed(1)} m 옮겼습니다',
      body: '대기 장소는 옛 자리에 그대로 남아 있습니다.\n새 목적지에 맞게 다시 찍을까요?',
      rows: [
        VicaDialogRow(label: '장소', value: after.name),
        VicaDialogRow(
          label: '대기 장소까지',
          value:
              '${_distance(before.x, before.y, spot.x, spot.y).toStringAsFixed(1)} m'
              ' → ${_distance(after.x, after.y, spot.x, spot.y).toStringAsFixed(1)} m',
        ),
        VicaDialogRow(
          label: '안내 멘트 위치',
          value: _waitSpotInDoorway(after)
              ? '입구 앞 · 다시 찍어 주세요'
              : spot.side == before.waitSpot?.side
                  ? '${spot.placePhrase} (그대로)'
                  : spot.placePhrase,
        ),
      ],
      cancelLabel: '그대로 두기',
      confirmLabel: '다시 찍기',
    );
    if (repick && mounted) {
      _startWaitPick(after, keep: true);
    }
  }

  double _degFor(PoseDirection direction, AppSettings settings) =>
      direction.yawFor(settings) * 180.0 / math.pi;

  /// 저장된 각도를 가장 가까운 화면 방향으로 되돌립니다. 지도 Y축 반전 설정을
  PoseDirection _directionFromYawDeg(double yawDeg, AppSettings settings) {
    var best = PoseDirection.right;
    var bestDiff = double.infinity;
    for (final direction in PoseDirection.values) {
      final diff =
          ((yawDeg - _degFor(direction, settings) + 540) % 360 - 180).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = direction;
      }
    }
    return best;
  }

  /// 5 cm 옮긴 자리. 화면 방향이 지도 좌표의 어느 쪽인지는 [PoseDirection] 이 압니다.
  Offset _stepped(Offset from, PoseDirection direction, AppSettings settings) {
    final yaw = direction.yawFor(settings);
    return Offset(
      from.dx + _moveStepM * math.cos(yaw),
      from.dy + _moveStepM * math.sin(yaw),
    );
  }

  double _distance(double ax, double ay, double bx, double by) =>
      math.sqrt((ax - bx) * (ax - bx) + (ay - by) * (ay - by));

  String _coord(double value) =>
      value.toStringAsFixed(2).replaceFirst('-', '−');

  Color _levelColor(GapLevel level) {
    switch (level) {
      case GapLevel.good:
        return VicaColors.primary;
      case GapLevel.caution:
        return VicaColors.warning;
      case GapLevel.blocked:
        return VicaColors.red;
    }
  }

  Color? _levelTextColor(GapLevel level) {
    switch (level) {
      case GapLevel.good:
        return null;
      case GapLevel.caution:
        return _warningText;
      case GapLevel.blocked:
        return _dangerText;
    }
  }

  String _shortLevel(GapLevel level) {
    switch (level) {
      case GapLevel.good:
        return '좋음';
      case GapLevel.caution:
        return '주의';
      case GapLevel.blocked:
        return '출발할 수 없음';
    }
  }

  /// 사각형 전체 목록을 젯슨에 저장합니다.
  Future<void> _saveKeepout(
    BuildContext context,
    SupervisorProvider supervisor,
    AppSettings settings,
    String mapId,
  ) async {
    final message = await supervisor.saveKeepoutZones(settings, mapId);
    if (!context.mounted) {
      return;
    }
    _showSnack(context, message);
  }

  /// 홈을 찍는 중일 때 지도에 보여줄 점.
  LocationPoint? _homePickedMarker(String mapId) {
    final spot = _homePicked;
    if (spot == null) {
      return null;
    }
    return LocationPoint(
      locationId: '_home_pick',
      mapId: mapId,
      name: '홈 후보',
      x: spot.dx,
      y: spot.dy,
      yaw: 0,
    );
  }

  /// 지도에 겹쳐 보여줄 방향 화살표.
  MapPoseArrow? _homeArrow(AppSettings settings) {
    if (_homeMode == HomeCardMode.picking) {
      final spot = _homePicked;
      final direction = _homeDirection;
      if (spot == null || direction == null) {
        return null;
      }
      return MapPoseArrow(
        x: spot.dx,
        y: spot.dy,
        yawDegrees: direction.yawFor(settings) * 180.0 / math.pi,
        label: '홈 방향',
      );
    }
    if (_homeMode == HomeCardMode.standing) {
      final result = _homeStanding;
      if (result == null) {
        return null;
      }
      return MapPoseArrow(
        x: result.x,
        y: result.y,
        yawDegrees: result.yawDegrees,
        label: '확인된 위치',
      );
    }
    return null;
  }

  /// 로봇을 움직여도 되는 상황인가.
  bool _canSendRobot(SupervisorProvider supervisor) {
    final robot = supervisor.primaryRobot;
    if (robot == null) {
      return false;
    }
    if (supervisor.emergencyOverlayVisible) {
      return false;
    }
    final driving = robot.currentGoal.trim().isNotEmpty;
    return !driving;
  }

  String _blockedReason(SupervisorProvider supervisor) {
    if (supervisor.primaryRobot == null) {
      return '로봇 상태를 받지 못했습니다. 연결을 확인하세요.';
    }
    if (supervisor.emergencyOverlayVisible) {
      return '비상정지 상태에서는 로봇을 움직일 수 없습니다.';
    }
    if (supervisor.primaryRobot!.currentGoal.trim().isNotEmpty) {
      return '안내 주행 중에는 홈을 다룰 수 없습니다. '
          '사용자가 핸들을 잡고 따라 걷는 중이라 방향을 바꾸면 위험합니다. '
          '먼저 주행을 취소하세요.';
    }
    return '';
  }

  Future<void> _checkStandingHome(
    BuildContext context,
    SupervisorProvider supervisor,
  ) async {
    final settings = context.read<SettingsProvider>().settings;
    final robot = supervisor.primaryRobot;
    if (robot == null) {
      _toast('로봇 위치를 받지 못했습니다.');
      return;
    }
    setState(() => _homeSending = true);
    final message = await supervisor.checkInitialPose(
      settings,
      x: robot.x,
      y: robot.y,
      yawHint: robot.yaw * math.pi / 180.0,
    );
    final result = supervisor.poseCheck;
    if (!mounted || _homeMode != HomeCardMode.standing) {
      supervisor.discardPoseCheck(result);
      if (mounted) {
        setState(() => _homeSending = false);
      }
      return;
    }
    setState(() {
      _homeStanding = result;
      _homeStandingFrom = supervisor;
      _homeSending = false;
    });
    if (supervisor.poseCheck == null) {
      _toast(message);
    }
  }

  Future<void> _saveHome(
    BuildContext context,
    SupervisorProvider supervisor,
    String mapId,
    AppSettings settings,
  ) async {
    double x;
    double y;
    double yawDeg;
    HomeSource source;
    double score = 0;

    if (_homeMode == HomeCardMode.picking) {
      final spot = _homePicked;
      final direction = _homeDirection;
      if (spot == null || direction == null) {
        return;
      }
      x = spot.dx;
      y = spot.dy;
      yawDeg = direction.yawFor(settings) * 180.0 / math.pi;
      source = HomeSource.mapPick;
    } else {
      final result = _homeStanding;
      if (result == null || !result.ok) {
        return;
      }
      x = result.x;
      y = result.y;
      yawDeg = result.yawDegrees;
      source = HomeSource.robotStanding;
      score = result.score;
    }

    final label = await _askHomeLabel(context);
    if (!mounted) {
      return;
    }

    final message = await supervisor.saveHome(
      settings,
      mapId: mapId,
      x: x,
      y: y,
      yawDeg: yawDeg,
      source: source,
      score: score,
      label: label ?? '',
    );
    if (!mounted) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _homeMode = HomeCardMode.idle;
        _homePicked = null;
        _homeDirection = null;
        _homeStanding = null;
      });
      supervisor.clearPoseCheck();
      _toast(message);
    });
  }

  /// 홈에 붙일 이름을 묻습니다. 비워도 됩니다 — 로봇은 쓰지 않습니다.
  Future<String?> _askHomeLabel(BuildContext context) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => VicaDialog(
        icon: Icons.home_outlined,
        title: '홈 이름',
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '예: 충전 스테이션 앞',
            helperText: '앱에서만 보이는 이름입니다. 비워도 됩니다.',
          ),
        ),
        actions: [
          VicaCancelButton(
            onPressed: () => Navigator.of(dialogContext).pop(''),
            label: '이름 없이 저장',
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 400), controller.dispose);
    return value;
  }

  Future<void> _goHome(
    BuildContext context,
    SupervisorProvider supervisor,
  ) async {
    final settings = context.read<SettingsProvider>().settings;
    final confirmed = await showVicaConfirm(
      context,
      icon: Icons.home_outlined,
      title: '홈으로 가보기',
      body: '로봇이 홈 위치로 이동합니다. '
          '경로에 사람과 장애물이 없는지 확인하세요.\n\n'
          '제대로 도착하면 이 홈은 "가 본 자리"로 기록됩니다.',
      confirmLabel: '이동 시작',
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    final message = await supervisor.returnHome(settings);
    if (context.mounted) {
      _toast(message);
    }
  }

  Future<void> _confirmDeleteHome(
    BuildContext context,
    SupervisorProvider supervisor,
    String mapId,
  ) async {
    final settings = context.read<SettingsProvider>().settings;
    final confirmed = await showVicaConfirm(
      context,
      icon: Icons.delete_outline,
      iconColor: VicaColors.red,
      title: '홈 지우기',
      body: '홈을 지우면 안내가 끝난 뒤 로봇이 자동으로 돌아가지 않습니다. '
          '안내 기능 자체는 그대로 동작합니다.',
      confirmLabel: '삭제',
      danger: true,
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    final message = await supervisor.deleteHome(settings, mapId);
    if (context.mounted) {
      _toast(message);
    }
  }

  /// 임시 저장 장소를 젯슨에 보냅니다. 보낸 장소가 레일에서
  Future<void> _saveDraftToRos(
    BuildContext context,
    SupervisorProvider supervisor,
    AppSettings settings,
  ) async {
    final draft = supervisor.draftLocation;
    final connected =
        supervisor.connectionState == RosConnectionState.connected;
    supervisor.saveDraftLocation(settings);
    _clearPickedLocation();
    if (draft == null || !connected) {
      return;
    }
    final meters =
        supervisor.routeGraphFor(draft.mapId)?.distanceTo(draft.x, draft.y);
    if (meters != null && meters > kRailHandoffMeters && context.mounted) {
      final editRail = await showDialog<bool>(
        context: context,
        builder: (_) => RailFarPlaceDialog(name: draft.name, meters: meters),
      );
      if (editRail == true && context.mounted) {
        if (_panel != _SettingsPanel.rail) {
          await _openPanel(context, supervisor, _SettingsPanel.rail);
        }
        return;
      }
    }
    if (context.mounted && draft.doorYaw != null) {
      await _askWaitSpot(context, draft);
    }
  }

  /// 결과 문구를 띄웁니다.
  void _toast(String message) {
    if (!mounted || message.trim().isEmpty) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _showLocationInfoSheet(
    BuildContext context,
    SupervisorProvider supervisor,
    String mapId,
    List<LocationPoint> locations,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final selectedCategory = _category1 == null
                ? null
                : destinationCategoryByValue(_category1!);
            return Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: DraggableScrollableSheet(
                expand: false,
                initialChildSize: 0.9,
                minChildSize: 0.5,
                maxChildSize: 0.96,
                builder: (context, scrollController) {
                  return DecoratedBox(
                    decoration: const BoxDecoration(
                      color: VicaColors.background,
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(22)),
                    ),
                    child: Form(
                      key: _formKey,
                      child: ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                        children: [
                          Center(
                            child: Container(
                              width: 44,
                              height: 4,
                              decoration: BoxDecoration(
                                color: VicaColors.muted,
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            _editingSaved == null ? '장소 정보 입력' : '장소 정보 수정',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (_editingSaved != null && _pickedRos != null) ...[
                            const SizedBox(height: 10),
                            VicaDialogRow(
                              label: '위치',
                              value: movedFromOriginalText(
                                _editingSaved!.x,
                                _editingSaved!.y,
                                _pickedRos!.dx,
                                _pickedRos!.dy,
                                upIsPlusY: context
                                    .read<SettingsProvider>()
                                    .settings
                                    .flipMapY,
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          _requiredTextField(
                            controller: _nameController,
                            label: '장소 이름',
                            hint: '예: 별빛관 1층 화장실',
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _aliasesController,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              labelText: '별칭',
                              hintText: '예: 별빛관 화장실, 1층 화장실, 화장실',
                              helperText: '쉼표 또는 줄바꿈으로 구분합니다.',
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  key:
                                      ValueKey('category1_${_category1 ?? ''}'),
                                  initialValue: _category1,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                      labelText: '상위 카테고리'),
                                  items: destinationCategories
                                      .map(
                                        (category) => DropdownMenuItem(
                                          value: category.value,
                                          child: Text(category.label),
                                        ),
                                      )
                                      .toList(),
                                  validator: (value) =>
                                      value == null ? '상위 카테고리를 선택하세요.' : null,
                                  onChanged: (value) {
                                    setSheetState(() {
                                      _category1 = value;
                                      _category2 = null;
                                      if (value != 'person') {
                                        _ownerController.clear();
                                      }
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  key: ValueKey(
                                    'category2_${_category1 ?? ''}_${_category2 ?? ''}',
                                  ),
                                  initialValue: _category2,
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    labelText: '세부 카테고리',
                                    helperText: selectedCategory == null
                                        ? '상위 카테고리를 먼저 선택하세요.'
                                        : null,
                                  ),
                                  items: selectedCategory?.subcategories
                                      .map(
                                        (subcategory) => DropdownMenuItem(
                                          value: subcategory.value,
                                          child: Text(subcategory.label),
                                        ),
                                      )
                                      .toList(),
                                  validator: (value) =>
                                      value == null ? '세부 카테고리를 선택하세요.' : null,
                                  onChanged: selectedCategory == null
                                      ? null
                                      : (value) => setSheetState(
                                          () => _category2 = value),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _requiredTextField(
                                  controller: _buildingController,
                                  label: '건물',
                                  hint: '예: starlight_building',
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextFormField(
                                  controller: _floorController,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          signed: true),
                                  decoration: const InputDecoration(
                                    labelText: '층',
                                    hintText: '예: 1 (지하는 -1)',
                                  ),
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return '층을 입력하세요.';
                                    }
                                    return int.tryParse(value.trim()) == null
                                        ? '층은 정수로 입력하세요.'
                                        : null;
                                  },
                                ),
                              ),
                            ],
                          ),
                          if (_category1 == 'person') ...[
                            const SizedBox(height: 10),
                            _requiredTextField(
                              controller: _ownerController,
                              label: '담당자 또는 공간 소유자',
                              hint: '예: 홍길동 교수',
                            ),
                          ],
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _contactPhoneController,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              labelText: '도착 문자 연락처 (선택)',
                              hintText: '예: 010-1234-5678 · 비우면 배송 대상 제외',
                            ),
                            validator: (value) =>
                                normalizeContactPhone(value ?? '') == null
                                    ? '휴대폰 번호 모양이 아닙니다 (010-0000-0000).'
                                    : null,
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            initialValue: _authorization,
                            decoration:
                                const InputDecoration(labelText: '접근 권한'),
                            items: const [
                              DropdownMenuItem(
                                value: 'public',
                                child: Text('공개 (public)'),
                              ),
                              DropdownMenuItem(
                                value: 'private',
                                child: Text('비공개 (private)'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setSheetState(() => _authorization = value);
                              }
                            },
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<bool>(
                            initialValue: _isApproachable,
                            decoration:
                                const InputDecoration(labelText: '로봇 접근 가능 여부'),
                            items: const [
                              DropdownMenuItem(
                                value: true,
                                child: Text('접근 가능 (true)'),
                              ),
                              DropdownMenuItem(
                                value: false,
                                child: Text('접근 불가 (false)'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value == null) {
                                return;
                              }
                              setSheetState(() {
                                _isApproachable = value;
                                if (value) {
                                  _unavailableReasonController.clear();
                                }
                              });
                            },
                          ),
                          if (!_isApproachable) ...[
                            const SizedBox(height: 10),
                            _requiredTextField(
                              controller: _unavailableReasonController,
                              label: '접근 불가 사유',
                              hint: '예: 계단만 있어 로봇이 접근할 수 없음',
                            ),
                          ],
                          const SizedBox(height: 10),
                          _DoorDirectionRow(
                            label: _doorDirection == null
                                ? '정하지 않음'
                                : _directionLabel(_doorDirection!),
                            onChange: () {
                              Navigator.of(sheetContext).pop();
                              setState(() {
                                _doorHighlight = true;
                                _moving = false;
                              });
                            },
                          ),
                          const SizedBox(height: 14),
                          FilledButton.icon(
                            onPressed: _pickedRos == null
                                ? null
                                : () {
                                    if (!(_formKey.currentState?.validate() ??
                                        false)) {
                                      return;
                                    }
                                    if (_editingSaved != null) {
                                      final before = _editingSaved!;
                                      final (merged, message) =
                                          _saveEditedToRos(
                                        supervisor,
                                        sheetContext
                                            .read<SettingsProvider>()
                                            .settings,
                                        mapId,
                                      );
                                      Navigator.of(sheetContext).pop();
                                      _showSnack(context, message);
                                      if (merged != null &&
                                          merged.waitSpot != null &&
                                          (_distance(before.x, before.y,
                                                      merged.x, merged.y) >=
                                                  1.0 ||
                                              _waitSpotInDoorway(merged))) {
                                        _askRepickAfterMove(
                                            this.context, before, merged);
                                      }
                                      return;
                                    }
                                    _saveDraft(supervisor, mapId);
                                    Navigator.of(sheetContext).pop();
                                  },
                            icon: Icon(
                              _editingSaved != null
                                  ? Icons.cloud_upload
                                  : _editingLocationId == null
                                      ? Icons.add_location_alt
                                      : Icons.save_outlined,
                            ),
                            label: Text(
                              _editingSaved != null
                                  ? 'ROS2에 수정 저장'
                                  : _editingLocationId == null
                                      ? '임시 저장'
                                      : '수정 내용 저장',
                            ),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: () => Navigator.of(sheetContext).pop(),
                            icon: const Icon(Icons.close),
                            label: const Text('취소'),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  TextFormField _requiredTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label, hintText: hint),
      validator: (value) =>
          value == null || value.trim().isEmpty ? '$label 항목을 입력하세요.' : null,
    );
  }

  LocationPoint? _previewLocation(String mapId) {
    final picked = _pickedRos;
    if (picked == null) {
      return null;
    }
    return LocationPoint(
      locationId: 'preview_location',
      mapId: mapId,
      name: '선택 위치',
      x: picked.dx,
      y: picked.dy,
      yaw: 0,
    );
  }

  LocationPoint? _selectedLocation(List<LocationPoint> locations) {
    if (locations.isEmpty) {
      return null;
    }
    final key = _isWaitKey(_deleteTargetId)
        ? _deleteTargetId!.substring(_waitKeyPrefix.length)
        : _deleteTargetId;
    for (final location in locations) {
      if (location.locationId == key) {
        return location;
      }
    }
    return locations.first;
  }

  void _saveDraft(
    SupervisorProvider supervisor,
    String mapId,
  ) {
    final point = _locationFromForm(mapId);
    if (point == null) {
      return;
    }
    supervisor.setDraftLocation(point);
  }

  /// 저장된 장소를 고친 것을 바로 ROS 에 보냅니다. 보냈으면 점과 폼을 정리합니다.
  (LocationPoint?, String) _saveEditedToRos(
    SupervisorProvider supervisor,
    AppSettings settings,
    String mapId,
  ) {
    final point = _locationFromForm(mapId);
    if (point == null) {
      return (null, '입력이 비어 저장하지 못했습니다.');
    }
    final merged = mergeEditedLocation(edited: point, original: _editingSaved);
    final (sent, message) = supervisor.saveLocation(settings, merged);
    if (sent) {
      _clearPickedLocation();
    }
    return (sent ? merged : null, message);
  }

  /// 폼에 적힌 것으로 장소 한 건을 만듭니다. 좌표나 분류가 없으면 null 입니다.
  LocationPoint? _locationFromForm(String mapId) {
    final picked = _pickedRos;
    final door = _doorDirection;
    if (picked == null ||
        door == null ||
        _category1 == null ||
        _category2 == null) {
      return null;
    }
    final name = _nameController.text.trim();
    final doorDeg = _degFor(door, context.read<SettingsProvider>().settings);
    return LocationPoint(
      locationId: _editingLocationId ?? _uuid.v4(),
      mapId: mapId,
      name: name,
      aliases: _parseAliases(name),
      category1: _category1!,
      category2: _category2!,
      building: _buildingController.text.trim(),
      floor: int.parse(_floorController.text.trim()),
      owner: _category1 == 'person' ? _ownerController.text.trim() : '',
      contactPhone: normalizeContactPhone(_contactPhoneController.text) ?? '',
      authorization: _authorization,
      isApproachable: _isApproachable,
      unavailableReason:
          _isApproachable ? '' : _unavailableReasonController.text.trim(),
      x: picked.dx,
      y: picked.dy,
      yaw: doorDeg,
      doorYaw: doorDeg,
      waitSpot: _resideWaitSpot(_editingSaved?.waitSpot, picked, doorDeg),
    );
  }

  void _editSavedLocation(
    BuildContext context,
    LocationPoint location,
    AppSettings settings,
  ) {
    _loadDraftIntoForm(location);
    setState(() {
      _editingSaved = location;
      _moving = false;
      _doorHighlight = false;
    });
  }

  Future<void> _editDraft(
    BuildContext context,
    SupervisorProvider supervisor,
    LocationPoint draft,
    String mapId,
    List<LocationPoint> locations,
  ) async {
    _loadDraftIntoForm(draft);
    await _showLocationInfoSheet(context, supervisor, mapId, locations);
    if (mounted) {
      _clearPickedLocation();
    }
  }

  void _loadDraftIntoForm(LocationPoint draft) {
    _nameController.text = draft.name;
    _aliasesController.text =
        draft.aliases.where((alias) => alias != draft.name).join(', ');
    _buildingController.text = draft.building;
    _floorController.text = draft.floor.toString();
    _ownerController.text = draft.owner;
    _contactPhoneController.text = formatContactPhone(draft.contactPhone);
    _unavailableReasonController.text = draft.unavailableReason;
    setState(() {
      _editingLocationId = draft.locationId;
      _category1 = draft.category1.isEmpty ? null : draft.category1;
      _category2 = draft.category2.isEmpty ? null : draft.category2;
      _authorization = draft.authorization;
      _isApproachable = draft.isApproachable;
      _doorDirection = draft.doorYaw == null
          ? null
          : _directionFromYawDeg(
              draft.doorYaw!,
              context.read<SettingsProvider>().settings,
            );
      _pickedRos = Offset(draft.x, draft.y);
    });
  }

  List<String> _parseAliases(String name) {
    final aliases = <String>{name};
    aliases.addAll(
      _aliasesController.text
          .split(RegExp(r'[,\n]'))
          .map((alias) => alias.trim())
          .where((alias) => alias.isNotEmpty),
    );
    return aliases.toList(growable: false);
  }

  void _resetLocationInput() {
    _nameController.clear();
    _aliasesController.clear();
    _buildingController.clear();
    _floorController.clear();
    _ownerController.clear();
    _contactPhoneController.clear();
    _unavailableReasonController.clear();
    _category1 = null;
    _category2 = null;
    _authorization = 'public';
    _isApproachable = true;
    _doorDirection = null;
    _moving = false;
    _doorHighlight = false;
    _editingLocationId = null;
  }

  void _clearPickedLocation() {
    _resetLocationInput();
    setState(() {
      _pickedRos = null;
      _editingSaved = null;
    });
  }
}

class _DraftSummary extends StatelessWidget {
  const _DraftSummary({required this.location});

  final LocationPoint location;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: VicaColors.accentTint,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('임시 저장된 장소', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text('이름: ${location.name}'),
          Text(
            '분류: ${destinationCategoryLabel(location.category1)} > '
            '${destinationSubcategoryLabel(location.category1, location.category2)}',
          ),
          if (location.aliases.isNotEmpty)
            Text('별칭: ${location.aliases.join(', ')}'),
          Text('건물/층: ${location.building} / ${location.floor}층'),
          Text('접근 권한: ${location.authorization}'),
          Text('로봇 접근: ${location.isApproachable}'),
          if (location.owner.isNotEmpty) Text('담당자: ${location.owner}'),
          if (location.canReceiveDelivery)
            Text('도착 문자: ${maskContactPhone(location.contactPhone)}'),
          if (location.unavailableReason.isNotEmpty)
            Text('접근 불가 사유: ${location.unavailableReason}'),
          Text(
            '좌표: x ${location.x.toStringAsFixed(3)}, '
            'y ${location.y.toStringAsFixed(3)}, '
            'yaw ${location.yaw.toStringAsFixed(2)}',
          ),
        ],
      ),
    );
  }
}

/// 화면 방향 글자. 목업의 '↓ 아래' 모양입니다.
String _directionLabel(PoseDirection direction) {
  switch (direction) {
    case PoseDirection.up:
      return '↑ 위';
    case PoseDirection.down:
      return '↓ 아래';
    case PoseDirection.left:
      return '← 왼쪽';
    case PoseDirection.right:
      return '→ 오른쪽';
  }
}

/// 이름 뒤 목적격 조사. rail_far_place_dialog.subjectParticle 과 같은 규칙입니다 —
String _objectParticle(String name) {
  final trimmed = name.trimRight();
  if (trimmed.isEmpty) {
    return '을(를)';
  }
  final code = trimmed.runes.last;
  if (code < 0xAC00 || code > 0xD7A3) {
    return '을(를)';
  }
  return (code - 0xAC00) % 28 == 0 ? '를' : '을';
}

const _warningTint = Color(0xFFFBF1E2);
const _warningText = Color(0xFF7E5716);
const _dangerTint = Color(0xFFFBEDEB);
const _dangerText = Color(0xFFA2463A);

class _Badge extends StatelessWidget {
  const _Badge({
    required this.text,
    this.background = VicaColors.accentTint,
    this.foreground = VicaColors.primaryDark,
    this.outlined = false,
  });

  final String text;
  final Color background;
  final Color foreground;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: outlined ? Colors.white : background,
        borderRadius: BorderRadius.circular(10),
        border: outlined ? Border.all(color: VicaColors.borderStrong) : null,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: outlined ? VicaColors.muted : foreground,
          fontWeight: outlined ? FontWeight.w400 : FontWeight.w700,
        ),
      ),
    );
  }
}

/// 목록의 목적지 한 줄. 빠진 것은 배지로 보입니다(목업 5).
class _LocationItem extends StatelessWidget {
  const _LocationItem({required this.location});

  final LocationPoint location;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              location.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          if (location.doorYaw == null) ...[
            const SizedBox(width: 6),
            const _Badge(
              text: '입구 방향 없음',
              background: _warningTint,
              foreground: _warningText,
            ),
          ],
          if (location.waitSpot == null) ...[
            const SizedBox(width: 6),
            const _Badge(text: '대기 장소 없음', outlined: true),
          ],
        ],
      ),
    );
  }
}

/// 목록의 대기 장소 한 줄 — 목적지 밑에 들여 씁니다(목업 5).
class _WaitItem extends StatelessWidget {
  const _WaitItem({required this.location});

  final LocationPoint location;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, top: 6, bottom: 6),
      child: Row(
        children: [
          const Text('└', style: TextStyle(color: VicaColors.textTertiary)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              location.waitSpotName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: VicaColors.muted),
            ),
          ),
          const SizedBox(width: 6),
          const _Badge(text: '대기'),
        ],
      ),
    );
  }
}

/// 고른 장소의 '라벨 …… 값' 묶음(목업 6·15).
class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.rows});

  final List<(String, String, Color?)> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: VicaColors.surfaceSunken,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: VicaColors.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rows[i].$1,
                  style: const TextStyle(fontSize: 13, color: VicaColors.muted),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    vicaKeepWords(rows[i].$2),
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: rows[i].$3 ?? VicaColors.text,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 안내 상자. 기본은 초록 바탕, [danger] 는 빨강, [warning] 은 주황입니다.
class _NoticeBox extends StatelessWidget {
  const _NoticeBox({
    required this.text,
    this.title,
    this.icon = true,
    this.danger = false,
    this.warning = false,
  });

  final String text;
  final String? title;
  final bool icon;
  final bool danger;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final background = danger
        ? _dangerTint
        : warning
            ? _warningTint
            : VicaColors.accentTint;
    final foreground = danger
        ? _dangerText
        : warning
            ? _warningText
            : VicaColors.primaryDark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon) ...[
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                danger || warning ? Icons.error_outline : Icons.info_outline,
                size: 18,
                color: foreground,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  Text(
                    title!,
                    style: TextStyle(fontSize: 12, color: foreground),
                  ),
                Text(
                  vicaKeepWords(text),
                  style: title != null
                      ? TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: foreground,
                        )
                      : TextStyle(
                          fontSize: 13,
                          height: 1.45,
                          color: foreground,
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 단계 표시 원 — 끝났으면 초록 체크, 아니면 번호.
class _StepMark extends StatelessWidget {
  const _StepMark({required this.done, this.number = ''});

  final bool done;
  final String number;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: done ? VicaColors.green : VicaColors.accentTint,
        shape: BoxShape.circle,
      ),
      child: done
          ? const Icon(Icons.check, size: 14, color: Colors.white)
          : Text(
              number,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: VicaColors.muted,
              ),
            ),
    );
  }
}

/// 위치 한 줄 + '위치 옮기기'(5 cm 패드). 목업 1·1′·4·16·16′.
class _PositionStep extends StatelessWidget {
  const _PositionStep({
    required this.picked,
    required this.moving,
    required this.onStartMove,
    required this.onDoneMove,
    required this.onStep,
    this.movedText,
    this.onRestore,
  });

  final Offset picked;
  final bool moving;
  final VoidCallback onStartMove;
  final VoidCallback onDoneMove;
  final ValueChanged<PoseDirection> onStep;

  /// 기존 목적지를 고치는 중이면 "원래 자리에서 오른쪽으로 0.25 m".
  final String? movedText;

  /// 기존 목적지를 고치는 중이면 '원래 자리로 되돌리기'.
  final VoidCallback? onRestore;

  String get _position {
    String f(double v) => v.toStringAsFixed(2).replaceFirst('-', '−');
    return '위치  x ${f(picked.dx)}   y ${f(picked.dy)}';
  }

  @override
  Widget build(BuildContext context) {
    if (!moving) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _StepMark(done: true),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_position, style: const TextStyle(fontSize: 13)),
                Text(
                  vicaKeepWords('위치 옮기기 선택 · 지도에서 선택'),
                  style: const TextStyle(fontSize: 12, color: VicaColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 30,
            child: FilledButton(
              onPressed: onStartMove,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 30),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                textStyle:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              child: const Text('위치 옮기기'),
            ),
          ),
        ],
      );
    }
    Widget pad(PoseDirection direction, String arrow, String label) {
      return SizedBox(
        height: 44,
        child: OutlinedButton(
          onPressed: () => onStep(direction),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 44),
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Semantics(
            label: label,
            child: Text(arrow, style: const TextStyle(fontSize: 16)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: VicaColors.primary, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const _StepMark(done: true),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_position, style: const TextStyle(fontSize: 13)),
                    if (movedText != null)
                      Text(
                        vicaKeepWords(movedText!),
                        style: const TextStyle(
                          fontSize: 12,
                          color: VicaColors.primaryDark,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(
                height: 32,
                child: FilledButton(
                  onPressed: onDoneMove,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: const Text('완료'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const SizedBox(width: 32),
              SizedBox(
                width: 150,
                child: Column(
                  children: [
                    Row(children: [
                      const Spacer(),
                      Expanded(child: pad(PoseDirection.up, '↑', '위로 5 cm')),
                      const Spacer(),
                    ]),
                    const SizedBox(height: 6),
                    Row(children: [
                      Expanded(
                          child: pad(PoseDirection.left, '←', '왼쪽으로 5 cm')),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Center(
                          child: Text(
                            '5 cm',
                            style: TextStyle(
                                fontSize: 12, color: VicaColors.muted),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                          child: pad(PoseDirection.right, '→', '오른쪽으로 5 cm')),
                    ]),
                    const SizedBox(height: 6),
                    Row(children: [
                      const Spacer(),
                      Expanded(child: pad(PoseDirection.down, '↓', '아래로 5 cm')),
                      const Spacer(),
                    ]),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  vicaKeepWords('한 번 누를 때 5 cm씩 옮깁니다. 지도에서 직접 선택도 가능합니다.'),
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: VicaColors.muted,
                  ),
                ),
              ),
            ],
          ),
          if (onRestore != null) ...[
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: onRestore,
              child: Text(vicaKeepWords('원래 자리로 되돌리기')),
            ),
          ],
        ],
      ),
    );
  }
}

/// 방향 4개 중 하나 고르기(입구 방향·나가는 방향). 목업 1·2′·4.
class _DirectionStep extends StatelessWidget {
  const _DirectionStep({
    required this.title,
    required this.selected,
    required this.onSelect,
    this.collapsed = false,
    this.highlighted = false,
  });

  final String title;
  final PoseDirection? selected;
  final ValueChanged<PoseDirection> onSelect;

  /// 위치 옮기기 중에는 한 줄로 접습니다(목업 1′).
  final bool collapsed;

  /// '바꾸기'로 돌아왔을 때 테두리로 강조합니다(목업 2′).
  final bool highlighted;

  static const _order = [
    PoseDirection.up,
    PoseDirection.down,
    PoseDirection.left,
    PoseDirection.right,
  ];

  @override
  Widget build(BuildContext context) {
    final choice = selected;
    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepMark(done: choice != null && !highlighted, number: '2'),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            vicaKeepWords(collapsed && choice != null
                ? '$title · ${_directionLabel(choice)}'
                : title),
            style: TextStyle(
              fontSize: 13,
              height: 1.6,
              fontWeight: highlighted ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
      ],
    );
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        if (!collapsed) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 32),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final direction in _order)
                  _DirectionChip(
                    label: _directionLabel(direction),
                    selected: direction == choice,
                    onPressed: () => onSelect(direction),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
    if (!highlighted) {
      return body;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: VicaColors.primary, width: 1.5),
      ),
      child: body,
    );
  }
}

class _DirectionChip extends StatelessWidget {
  const _DirectionChip({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          backgroundColor: selected ? VicaColors.accentTint : Colors.white,
          foregroundColor: selected ? VicaColors.primaryDark : VicaColors.text,
          side: BorderSide(
            color: selected ? VicaColors.primary : VicaColors.borderStrong,
          ),
          shape: const StadiumBorder(),
          textStyle: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
        child: Text(label),
      ),
    );
  }
}

/// 정보 시트의 입구 방향 줄 + '바꾸기'(목업 2·17).
class _DoorDirectionRow extends StatelessWidget {
  const _DoorDirectionRow({required this.label, required this.onChange});

  final String label;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: VicaColors.accentTint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: VicaColors.primary, width: 1.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.south, color: VicaColors.primaryDark, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vicaKeepWords('입구 방향 (앱의 지도 그림 기준)'),
                  style: const TextStyle(
                      fontSize: 12, color: VicaColors.primaryDark),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: VicaColors.primaryDark,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 36,
            child: OutlinedButton(
              onPressed: onChange,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                backgroundColor: Colors.white,
                foregroundColor: VicaColors.primaryDark,
                side: const BorderSide(color: VicaColors.primary),
              ),
              child: const Text('바꾸기'),
            ),
          ),
        ],
      ),
    );
  }
}

/// 몸 옆면·앞면과 벽 사이 간격(목업 4·4′). 7 cm 미만 빨강, 7~22 cm 주황, 그 위 초록.
class _GapBox extends StatelessWidget {
  const _GapBox({required this.gaps, required this.maskFailed});

  final WaitSpotGaps? gaps;
  final bool maskFailed;

  Color _dot(GapLevel level) {
    switch (level) {
      case GapLevel.good:
        return VicaColors.green;
      case GapLevel.caution:
        return VicaColors.warning;
      case GapLevel.blocked:
        return VicaColors.red;
    }
  }

  Color _textColor(GapLevel level) {
    switch (level) {
      case GapLevel.good:
        return const Color(0xFF3B6F49);
      case GapLevel.caution:
        return _warningText;
      case GapLevel.blocked:
        return _dangerText;
    }
  }

  Widget _row(String side, double meters, GapLevel level) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: _dot(level), shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        SizedBox(
            width: 44, child: Text(side, style: const TextStyle(fontSize: 13))),
        SizedBox(
          width: 64,
          child: Text(
            formatGap(meters),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(
          child: Text(
            gapLevelText(level),
            style: TextStyle(
              fontSize: 13,
              color: _textColor(level),
              fontWeight:
                  level == GapLevel.blocked ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final value = gaps;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: VicaColors.surfaceSunken,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: VicaColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '몸 옆면과 벽 사이 간격',
            style: TextStyle(fontSize: 12, color: VicaColors.muted),
          ),
          const SizedBox(height: 6),
          if (value == null)
            Text(
              vicaKeepWords(maskFailed
                  ? '지도 그림을 받지 못해 벽 간격을 잴 수 없습니다.'
                  : '지도 그림을 받는 중입니다.'),
              style: const TextStyle(fontSize: 13, color: VicaColors.muted),
            )
          else ...[
            _row('왼쪽', value.left, value.leftLevel),
            const SizedBox(height: 6),
            _row('오른쪽', value.right, value.rightLevel),
            const SizedBox(height: 6),
            _row('앞', value.front, value.frontLevel),
          ],
        ],
      ),
    );
  }
}
