import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../core/destination_categories.dart';
import '../models/location_point.dart';
import '../providers/settings_provider.dart';
import '../providers/supervisor_provider.dart';
import '../widgets/map_canvas.dart';
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
  static const _yawDirectionOptions = ['앞', '뒤', '우측', '좌측'];

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
    final previewLocation =
        draft ?? (map == null ? null : _previewLocation(map.mapId));

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
              draftLocation: previewLocation,
              onTapMap: (ros) async {
                supervisor.setDraftLocation(null);
                _resetLocationInput();
                setState(() => _pickedRos = ros);
                await _showLocationInfoSheet(
                  context,
                  supervisor,
                  map.mapId,
                  locations,
                );
                if (mounted) {
                  _clearPickedLocation();
                }
              },
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
        ],
      ],
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
    _unavailableReasonController.text = draft.unavailableReason;
    setState(() {
      _editingLocationId = draft.locationId;
      _category1 = draft.category1.isEmpty ? null : draft.category1;
      _category2 = draft.category2.isEmpty ? null : draft.category2;
      _authorization = draft.authorization;
      _isApproachable = draft.isApproachable;
      _yawDirection = _directionFromYaw(draft.yaw);
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

  String _directionFromYaw(double yaw) {
    final normalized = yaw % 360.0;
    final degrees = normalized < 0 ? normalized + 360.0 : normalized;
    if (degrees >= 45 && degrees < 135) {
      return '앞';
    }
    if (degrees >= 135 && degrees < 225) {
      return '좌측';
    }
    if (degrees >= 225 && degrees < 315) {
      return '뒤';
    }
    return '우측';
  }

  double _yawFromDirection(String direction) {
    switch (direction) {
      case '앞':
        return 90;
      case '뒤':
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
