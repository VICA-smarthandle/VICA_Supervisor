// 지도에서 목적지 좌표를 선택하고 destinations.yaml 스키마에 맞는 정보를 입력합니다.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../core/app_settings.dart';
import '../core/destination_categories.dart';
import '../models/home_position.dart';
import '../models/location_point.dart';
import '../models/pose_check_result.dart';
import '../providers/settings_provider.dart';
import '../providers/supervisor_provider.dart';
import '../widgets/home_position_card.dart';
import '../widgets/initial_pose_card.dart' show PoseDirection;
import '../widgets/map_canvas.dart';
import '../widgets/map_delete_card.dart';
import '../widgets/vica_ui.dart';

class SaveLocationScreen extends StatefulWidget {
  const SaveLocationScreen({super.key});

  @override
  State<SaveLocationScreen> createState() => _SaveLocationScreenState();
}

class _SaveLocationScreenState extends State<SaveLocationScreen> {
  static const _compactDropdownDecoration = InputDecoration(
    labelText: '불러온 지도',
    isDense: true,
    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 9),
  );
  // 표시 문구만 바꾼 것입니다. 저장되는 값은 문자열이 아니라 각도(double)라
  // 기존에 저장된 장소는 손댈 필요가 없습니다. 다만 _yawFromDirection·
  // _directionFromYaw 와 반드시 함께 바꿔야 합니다 — 역변환이 이 목록에 없는
  // 문자열을 돌려주면 DropdownButtonFormField 가 그 자리에서 예외를 던집니다.
  static const _yawDirectionOptions = ['정면', '후면', '우측', '좌측'];

  final _uuid = const Uuid();
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _aliasesController = TextEditingController();
  final _buildingController = TextEditingController();
  final _floorController = TextEditingController();
  final _ownerController = TextEditingController();
  final _unavailableReasonController = TextEditingController();

  Offset? _pickedRos;
  String? _deleteTargetId;

  // ---- 홈 위치 ----------------------------------------------------------
  //
  // 홈 지정 중에는 지도 탭이 '장소 찍기'가 아니라 '홈 찍기'로 동작합니다.
  // 한 화면에서 두 가지를 찍으므로 지금 무엇을 찍는 중인지가 상태로 필요합니다.
  HomeCardMode _homeMode = HomeCardMode.idle;
  Offset? _homePicked;
  PoseDirection? _homeDirection;
  PoseCheckResult? _homeStanding;
  bool _homeSending = false;
  // 임시 저장 장소를 수정하는 중이면 그 id를 들고 있습니다. 새로 저장할 때 id가
  // 바뀌면 같은 장소가 둘로 늘어나므로, 수정 중에는 기존 id를 그대로 씁니다.
  String? _editingLocationId;
  String? _category1;
  String? _category2;
  String _authorization = 'public';
  bool _isApproachable = true;
  String _yawDirection = '우측';

  @override
  void dispose() {
    _nameController.dispose();
    _aliasesController.dispose();
    _buildingController.dispose();
    _floorController.dispose();
    _ownerController.dispose();
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
    final draft = supervisor.draftLocation;
    // 지도를 누르면 임시 저장 장소를 버리므로(사용자 결정 2026-08-21) 초록 점과
    // 주황 점이 동시에 뜨는 상태는 없습니다. draft 가 있으면 그쪽이 우선입니다.
    final pickedLocation =
        (draft != null || map == null) ? null : _previewLocation(map.mapId);

    return VicaPage(
      title: '장소 저장',
      children: [
        VicaFieldWithAction(
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
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('새로고침'),
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
              draftLocation: draft,
              // 홈을 찍는 중이면 그 점을 보여준다. 장소 찍기와 같은 주황 원이라
              // 관리자가 배울 것이 없다.
              pickedLocation: _homeMode == HomeCardMode.picking
                  ? _homePickedMarker(map.mapId)
                  : pickedLocation,
              // 방향을 고르면 화살표로 미리 보여준다. 어느 쪽을 보고 서게 될지
              // 글자('위')보다 그림이 빠르다.
              poseArrow: _homeArrow(settings),
              // 여기서 정보 입력 시트를 띄우지 않습니다. 누르자마자 시트가 덮으면
              // 점이 원하는 자리에 찍혔는지 볼 수가 없고, 시트를 닫으면 점까지
              // 사라져 처음부터 다시 해야 했습니다. 이제 누르는 것은 '점 옮기기'
              // 뿐이고, 시트는 아래 '장소 정보 입력' 버튼이 엽니다.
              onTapMap: (ros) {
                // 홈을 찍는 중이면 장소가 아니라 홈 좌표가 됩니다. 한 지도에서
                // 두 가지를 찍으므로 지금 무엇을 찍는 중인지로 갈라야 합니다.
                if (_homeMode == HomeCardMode.picking) {
                  setState(() => _homePicked = ros);
                  return;
                }
                // 임시 저장 장소를 버리는 것은 의도한 동작입니다. 최종 저장 전에
                // 다른 자리를 새로 찍었다면 그 장소가 더 이상 필요 없어진 것으로
                // 봅니다(사용자 판정 2026-08-21).
                supervisor.setDraftLocation(null);
                _resetLocationInput();
                setState(() => _pickedRos = ros);
              },
            ),
          ),
          // 찍은 점을 확인하고 정보 입력을 '시작'하는 칸입니다. draft 가 생기면
          // 아래 카드의 수정·저장 버튼이 그 역할을 이어받으므로 이 칸은 감춥니다.
          if (draft == null) ...[
            const SizedBox(height: 12),
            VicaCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _pickedRos == null
                        ? '지도를 눌러 저장할 위치를 찍으세요. 다시 누르면 점이 옮겨갑니다.'
                        : '선택 위치   x ${_pickedRos!.dx.toStringAsFixed(2)}   '
                            'y ${_pickedRos!.dy.toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _pickedRos == null
                              ? null
                              : () => _showLocationInfoSheet(
                                    context,
                                    supervisor,
                                    map.mapId,
                                    locations,
                                  ),
                          icon: const Icon(Icons.edit_location_alt_outlined),
                          label: const Text('장소 정보 입력'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton(
                        onPressed:
                            _pickedRos == null ? null : _clearPickedLocation,
                        child: const Text('선택 취소'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          VicaCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '저장 장소',
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
                DropdownButtonFormField<String>(
                  initialValue: deleteTarget?.locationId,
                  decoration: const InputDecoration(labelText: '장소 선택'),
                  // isExpanded가 없으면 드롭다운이 장소 이름의 원래 폭을 그대로
                  // 요구해 좁은 창에서 카드 밖으로 85px까지 삐져나갔습니다.
                  isExpanded: true,
                  items: locations
                      .map(
                        (location) => DropdownMenuItem(
                          value: location.locationId,
                          child: Text(
                            location.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _deleteTargetId = value),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: deleteTarget == null
                      ? null
                      : () => supervisor.deleteLocation(settings, deleteTarget),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('선택 장소 삭제'),
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
                      map.mapId,
                      locations,
                    ),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('임시 저장 장소 수정'),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: () => supervisor.saveDraftLocation(settings),
                    icon: const Icon(Icons.cloud_upload),
                    label: const Text('ROS2에 장소 저장'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          // 홈 지정은 장소 저장과 성질이 같은 일입니다 — 지도 좌표를 다루고,
          // 한 번 정하면 계속 쓰며, 가끔 고칩니다. 홈으로 '보내는' 일은
          // 로봇이 실제로 움직이므로 원격 주행 화면에 있습니다.
          HomePositionCard(
            home: supervisor.homeBelongsTo(map.mapId) ? supervisor.home : null,
            mode: _homeMode,
            busy: supervisor.homeBusy || _homeSending,
            picked: _homePicked,
            direction: _homeDirection,
            standingResult: _homeStanding,
            canSendRobot: _canSendRobot(supervisor),
            blockedReason: _blockedReason(supervisor),
            onStartPicking: () => setState(() {
              _homeMode = HomeCardMode.picking;
              _homePicked = null;
              _homeDirection = null;
              _homeStanding = null;
            }),
            onStartStanding: () => setState(() {
              _homeMode = HomeCardMode.standing;
              _homePicked = null;
              _homeDirection = null;
              _homeStanding = null;
            }),
            onDirection: (value) => setState(() => _homeDirection = value),
            onCheckStanding: () => _checkStandingHome(context, supervisor),
            onSave: () => _saveHome(context, supervisor, map.mapId, settings),
            onCancel: () => setState(() {
              _homeMode = HomeCardMode.idle;
              _homePicked = null;
              _homeDirection = null;
              _homeStanding = null;
            }),
            onGoHome: () => _goHome(context, supervisor),
            onDelete: () => _confirmDeleteHome(context, supervisor, map.mapId),
          ),
          const SizedBox(height: 12),
          // 지도 삭제는 목록 맨 아래에 둡니다. 되돌릴 수 없는 일이라 지도를
          // 고르는 자리(맨 위)에서 멀리 떼어 놓습니다.
          const MapDeleteCard(),
        ],
      ],
    );
  }

  // ------------------------------------------------------------------
  // 홈 위치
  // ------------------------------------------------------------------

  /// 홈을 찍는 중일 때 지도에 보여줄 점.
  ///
  /// 장소 찍기와 같은 `pickedLocation` 자리를 씁니다 — 한 화면에서 둘을 동시에
  /// 찍는 일은 없고(홈 모드에서는 지도 탭이 홈으로만 갑니다), 같은 모양으로
  /// 보여야 관리자가 새로 배울 것이 없습니다.
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
  ///
  /// 두 경우에 나옵니다.
  ///   - 홈을 찍는 중: 고른 방향을 미리 보여준다
  ///   - 선 자리를 확인한 뒤: 채점이 바로잡은 자세를 보여준다
  ///     (사람이 세운 자리와 다를 수 있어 "12 cm 옮겼습니다"가 눈으로 보인다)
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
        label: '찾아낸 자세',
      );
    }
    return null;
  }

  /// 로봇을 움직여도 되는 상황인가.
  ///
  /// 최종 판정은 Mission Manager 가 합니다. 여기서 미리 잠그는 것은 못 할
  /// 상황에서 버튼을 눌러 거부 메시지를 받는 대신 **이유를 먼저 보여주기**
  /// 위해서입니다.
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
    // 지금 AMCL 이 믿는 자리를 중심으로 채점합니다. 로봇이 실제로 그 방향을
    // 보고 있으므로 방향 힌트도 함께 줍니다 — 힌트가 있으면 후보가 크게 줄고
    // 대칭 복도에서 180도 뒤집힌 자세가 후보에 들어오지 않습니다.
    final message = await supervisor.checkInitialPose(
      settings,
      x: robot.x,
      y: robot.y,
      yawHint: robot.yaw * math.pi / 180.0,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _homeStanding = supervisor.poseCheck;
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
      // 저장하는 값은 로봇이 선 자리가 아니라 **채점이 바로잡은 자세**입니다.
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
    setState(() {
      _homeMode = HomeCardMode.idle;
      _homePicked = null;
      _homeDirection = null;
      _homeStanding = null;
    });
    supervisor.clearPoseCheck();
    _toast(message);
  }

  /// 홈에 붙일 이름을 묻습니다. 비워도 됩니다 — 로봇은 쓰지 않습니다.
  Future<String?> _askHomeLabel(BuildContext context) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('홈 이름'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '예: 충전 스테이션 앞',
            helperText: '앱에서만 보이는 이름입니다. 비워도 됩니다.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(''),
            child: const Text('이름 없이 저장'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value;
  }

  Future<void> _goHome(
    BuildContext context,
    SupervisorProvider supervisor,
  ) async {
    final settings = context.read<SettingsProvider>().settings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('홈으로 가보기'),
        content: const Text(
          '로봇이 홈 위치로 이동합니다.\n'
          '경로에 사람과 장애물이 없는지 확인하세요.\n\n'
          '제대로 도착하면 이 홈은 "가 본 자리"로 기록됩니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('이동 시작'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('홈 지우기'),
        content: const Text(
          '홈을 지우면 안내가 끝난 뒤 로봇이 자동으로 돌아가지 않습니다.\n'
          '안내 기능 자체는 그대로 동작합니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('그대로 두기'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('지우기'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    final message = await supervisor.deleteHome(settings, mapId);
    if (context.mounted) {
      _toast(message);
    }
  }

  /// 결과 문구를 띄웁니다.
  ///
  /// context 를 인자로 받지 않는 것은 이 함수가 대부분 await 뒤에 불리기
  /// 때문입니다. 그 사이에 화면이 사라졌을 수 있으므로 State 의 mounted 를
  /// 직접 보고 State 의 context 를 씁니다.
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
                            '장소 정보 입력',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 10),
                          if (_pickedRos != null)
                            Text(
                              '선택 좌표 x:${_pickedRos!.dx.toStringAsFixed(3)} '
                              'y:${_pickedRos!.dy.toStringAsFixed(3)}',
                            ),
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
                          DropdownButtonFormField<String>(
                            key: ValueKey('category1_${_category1 ?? ''}'),
                            initialValue: _category1,
                            decoration:
                                const InputDecoration(labelText: '상위 카테고리'),
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
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            key: ValueKey(
                              'category2_${_category1 ?? ''}_${_category2 ?? ''}',
                            ),
                            initialValue: _category2,
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
                                : (value) =>
                                    setSheetState(() => _category2 = value),
                          ),
                          const SizedBox(height: 10),
                          _requiredTextField(
                            controller: _buildingController,
                            label: '건물',
                            hint: '예: starlight_building',
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _floorController,
                            keyboardType: const TextInputType.numberWithOptions(
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
                          if (_category1 == 'person') ...[
                            const SizedBox(height: 10),
                            _requiredTextField(
                              controller: _ownerController,
                              label: '담당자 또는 공간 소유자',
                              hint: '예: 홍길동 교수',
                            ),
                          ],
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
                          DropdownButtonFormField<String>(
                            initialValue: _yawDirection,
                            decoration: const InputDecoration(
                              labelText: '도착 방향',
                              helperText: '저장 시 yaw 각도로 자동 변환됩니다.',
                            ),
                            items: _yawDirectionOptions
                                .map(
                                  (direction) => DropdownMenuItem(
                                    value: direction,
                                    child: Text(
                                      '$direction '
                                      '(${_yawFromDirection(direction).toStringAsFixed(0)}°)',
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setSheetState(() => _yawDirection = value);
                              }
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
                                    _saveDraft(supervisor, mapId);
                                    Navigator.of(sheetContext).pop();
                                  },
                            icon: Icon(
                              _editingLocationId == null
                                  ? Icons.add_location_alt
                                  : Icons.save_outlined,
                            ),
                            label: Text(
                              _editingLocationId == null
                                  ? '장소 임시 저장'
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
    for (final location in locations) {
      if (location.locationId == _deleteTargetId) {
        return location;
      }
    }
    return locations.first;
  }

  void _saveDraft(
    SupervisorProvider supervisor,
    String mapId,
  ) {
    final picked = _pickedRos;
    if (picked == null || _category1 == null || _category2 == null) {
      return;
    }
    final name = _nameController.text.trim();
    supervisor.setDraftLocation(
      LocationPoint(
        // 수정 중이면 기존 id를 유지해야 같은 장소로 갱신됩니다.
        locationId: _editingLocationId ?? _uuid.v4(),
        mapId: mapId,
        name: name,
        aliases: _parseAliases(name),
        category1: _category1!,
        category2: _category2!,
        building: _buildingController.text.trim(),
        floor: int.parse(_floorController.text.trim()),
        owner: _category1 == 'person' ? _ownerController.text.trim() : '',
        authorization: _authorization,
        isApproachable: _isApproachable,
        unavailableReason:
            _isApproachable ? '' : _unavailableReasonController.text.trim(),
        x: picked.dx,
        y: picked.dy,
        yaw: _yawFromDirection(_yawDirection),
        confirmPrompt: '$name으로 안내해드릴까요?',
        arrivalMessage: '$name 앞에 도착했습니다.',
      ),
    );
  }

  // 임시 저장된 장소를 다시 편집합니다. 입력 폼은 임시 저장 직후 비워지므로
  // 시트를 열기 전에 이전 값을 그대로 되돌려 놓습니다.
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
    // aliases에는 이름 자신도 들어 있으므로 입력란에는 나머지만 보여줍니다.
    _aliasesController.text =
        draft.aliases.where((alias) => alias != draft.name).join(', ');
    _buildingController.text = draft.building;
    _floorController.text = draft.floor.toString();
    _ownerController.text = draft.owner;
    _unavailableReasonController.text = draft.unavailableReason;
    setState(() {
      _editingLocationId = draft.locationId;
      _category1 = draft.category1.isEmpty ? null : draft.category1;
      _category2 = draft.category2.isEmpty ? null : draft.category2;
      _authorization = draft.authorization;
      _isApproachable = draft.isApproachable;
      _yawDirection = _directionFromYaw(draft.yaw);
      // 좌표가 있어야 시트의 저장 버튼이 활성화됩니다.
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
    _unavailableReasonController.clear();
    _category1 = null;
    _category2 = null;
    _authorization = 'public';
    _isApproachable = true;
    _yawDirection = '우측';
    _editingLocationId = null;
  }

  void _clearPickedLocation() {
    _resetLocationInput();
    setState(() => _pickedRos = null);
  }

  // _yawFromDirection의 역변환. 저장된 각도를 가장 가까운 방향으로 되돌립니다.
  String _directionFromYaw(double yaw) {
    final normalized = yaw % 360.0;
    final degrees = normalized < 0 ? normalized + 360.0 : normalized;
    if (degrees >= 45 && degrees < 135) {
      return '정면';
    }
    if (degrees >= 135 && degrees < 225) {
      return '좌측';
    }
    if (degrees >= 225 && degrees < 315) {
      return '후면';
    }
    return '우측';
  }

  double _yawFromDirection(String direction) {
    switch (direction) {
      case '정면':
        return 90;
      case '후면':
        return 270;
      case '좌측':
        return 180;
      case '우측':
      default:
        return 0;
    }
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
        color: VicaColors.softBlue,
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
