// 이 파일은 rosbridge 주소, 지도 서버 주소, topic 이름, 동기화와 좌표 보정 설정을 편집합니다.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_settings.dart';
import '../providers/settings_provider.dart';
import '../providers/supervisor_provider.dart';
import '../widgets/vica_ui.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late AppSettings _settings;
  final Map<String, TextEditingController> _controllers = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _settings = context.watch<SettingsProvider>().settings;
    _syncControllers(_settings);
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VicaPage(
      title: '설정',
      children: [
        const _MapMaintenanceCard(),
        VicaCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('계정 정보', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              TextField(
                readOnly: true,
                controller: TextEditingController(text: 'admin'),
                decoration: const InputDecoration(labelText: '관리자 정보'),
              ),
            ],
          ),
        ),
        VicaCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('네트워크 및 ROS',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              _Field(controller: _c('mapHttpBaseUrl'), label: '지도 이미지 URL'),
              _Field(controller: _c('rosBridgeUrl'), label: 'ROS Bridge 주소'),
            ],
          ),
        ),
        VicaCard(
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title:
                Text('고급 설정', style: Theme.of(context).textTheme.titleMedium),
            children: [
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('지도 목록 자동 요청'),
                value: _settings.autoRequestMapList,
                onChanged: (value) => setState(
                  () =>
                      _settings = _settings.copyWith(autoRequestMapList: value),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('장소 목록 자동 요청'),
                value: _settings.autoRequestLocationList,
                onChanged: (value) => setState(
                  () => _settings =
                      _settings.copyWith(autoRequestLocationList: value),
                ),
              ),
              _Field(
                  controller: _c('mapListRequestTopic'),
                  label: '지도 목록 요청 topic'),
              _Field(controller: _c('mapListTopic'), label: '지도 목록 topic'),
              _Field(
                  controller: _c('locationListRequestTopic'),
                  label: '장소 목록 요청 topic'),
              _Field(controller: _c('locationListTopic'), label: '장소 목록 topic'),
              _Field(controller: _c('saveLocationTopic'), label: '장소 저장 topic'),
              _Field(
                  controller: _c('deleteLocationRequestTopic'),
                  label: '장소 삭제 요청 topic'),
              _Field(
                controller: _c('missionRequestService'),
                label: '목적지 주행 요청 service',
              ),
              _Field(controller: _c('robotStatusTopic'), label: '로봇 상태 topic'),
              _Field(
                controller: _c('emergencyActivateService'),
                label: '비상정지 활성화 service',
              ),
              _Field(
                controller: _c('emergencyResetService'),
                label: '비상정지 해제 service',
              ),
              _Field(
                controller: _c('emergencyStateTopic'),
                label: '비상정지 상태 topic',
              ),
              _Field(
                controller: _c('emergencyServiceTimeoutSeconds'),
                label: '비상정지 응답 제한시간(초)',
                number: true,
              ),
              _Field(controller: _c('xOffset'), label: 'x 보정값', number: true),
              _Field(controller: _c('yOffset'), label: 'y 보정값', number: true),
              _Field(
                  controller: _c('yawOffset'), label: 'yaw 보정값', number: true),
              _Field(
                  controller: _c('mapScale'),
                  label: '지도 스케일 보정값',
                  number: true),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('지도 Y축 반전'),
                value: _settings.flipMapY,
                onChanged: (value) => setState(
                  () => _settings = _settings.copyWith(flipMapY: value),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save),
          label: const Text('저장'),
        ),
      ],
    );
  }

  TextEditingController _c(String key) => _controllers[key]!;

  void _syncControllers(AppSettings settings) {
    final values = {
      'rosBridgeUrl': settings.rosBridgeUrl,
      'mapHttpBaseUrl': settings.mapHttpBaseUrl,
      'mapListRequestTopic': settings.mapListRequestTopic,
      'mapListTopic': settings.mapListTopic,
      'locationListRequestTopic': settings.locationListRequestTopic,
      'locationListTopic': settings.locationListTopic,
      'saveLocationTopic': settings.saveLocationTopic,
      'deleteLocationRequestTopic': settings.deleteLocationRequestTopic,
      'missionRequestService': settings.missionRequestService,
      'robotStatusTopic': settings.robotStatusTopic,
      'emergencyActivateService': settings.emergencyActivateService,
      'emergencyResetService': settings.emergencyResetService,
      'emergencyStateTopic': settings.emergencyStateTopic,
      'emergencyServiceTimeoutSeconds':
          settings.emergencyServiceTimeoutSeconds.toString(),
      'xOffset': settings.xOffset.toString(),
      'yOffset': settings.yOffset.toString(),
      'yawOffset': settings.yawOffset.toString(),
      'mapScale': settings.mapScale.toString(),
    };
    for (final entry in values.entries) {
      _controllers.putIfAbsent(
        entry.key,
        () => TextEditingController(text: entry.value),
      );
      if (_controllers[entry.key]!.text.isEmpty) {
        _controllers[entry.key]!.text = entry.value;
      }
    }
  }

  // 입력된 문자열을 AppSettings로 변환해 저장합니다.
  Future<void> _save() async {
    final next = _settings.copyWith(
      rosBridgeUrl: _c('rosBridgeUrl').text.trim(),
      mapHttpBaseUrl: _c('mapHttpBaseUrl').text.trim(),
      mapListRequestTopic: _c('mapListRequestTopic').text.trim(),
      mapListTopic: _c('mapListTopic').text.trim(),
      locationListRequestTopic: _c('locationListRequestTopic').text.trim(),
      locationListTopic: _c('locationListTopic').text.trim(),
      saveLocationTopic: _c('saveLocationTopic').text.trim(),
      deleteLocationRequestTopic: _c('deleteLocationRequestTopic').text.trim(),
      missionRequestService: _c('missionRequestService').text.trim(),
      robotStatusTopic: _c('robotStatusTopic').text.trim(),
      emergencyActivateService: _c('emergencyActivateService').text.trim(),
      emergencyResetService: _c('emergencyResetService').text.trim(),
      emergencyStateTopic: _c('emergencyStateTopic').text.trim(),
      emergencyServiceTimeoutSeconds:
          int.tryParse(_c('emergencyServiceTimeoutSeconds').text.trim()) ?? 8,
      xOffset: double.tryParse(_c('xOffset').text.trim()) ?? 0,
      yOffset: double.tryParse(_c('yOffset').text.trim()) ?? 0,
      yawOffset: double.tryParse(_c('yawOffset').text.trim()) ?? 0,
      mapScale: double.tryParse(_c('mapScale').text.trim()) ?? 1,
    );
    await context.read<SettingsProvider>().update(next);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('설정을 저장했습니다.')),
      );
    }
  }
}

// 저장된 지도를 지우는 자리입니다.
//
// **왜 설정 화면인가.** 되돌릴 수 없는 일이라 일상 흐름(장소 저장·원격 주행)에서
// 멀리 둡니다. "지도 한 장은 사람이 로봇을 끌고 다닌 시간"입니다
// (scripts/vica_map_save.sh 주석). 실수로 눌릴 자리에 두면 안 됩니다.
//
// 실제 검사는 노드가 합니다 — 이름 규칙, 지금 쓰는 지도인지, 파일이 있는지.
// 앱은 확인만 받습니다.
class _MapMaintenanceCard extends StatefulWidget {
  const _MapMaintenanceCard();

  @override
  State<_MapMaintenanceCard> createState() => _MapMaintenanceCardState();
}

class _MapMaintenanceCardState extends State<_MapMaintenanceCard> {
  String? _target;
  // 기본값을 false 로 둡니다. 같은 이름으로 다시 그릴 생각이면 목적지 카탈로그는
  // 남겨 두는 편이 낫습니다 — 장소를 다시 찍는 일이 더 번거롭습니다.
  bool _alsoDestinations = false;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    final supervisor = context.watch<SupervisorProvider>();
    final maps = supervisor.maps;
    final selected = maps.any((map) => map.mapId == _target) ? _target : null;

    return VicaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('지도 관리', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          const Text(
            '지운 지도는 되돌릴 수 없습니다. 지금 쓰는 지도는 지울 수 없습니다.',
            style: TextStyle(color: VicaColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          if (maps.isEmpty)
            const Text(
              '지도 목록이 비어 있습니다. 먼저 목록을 불러오세요.',
              style: TextStyle(fontSize: 12),
            )
          else ...[
            DropdownButtonFormField<String>(
              initialValue: selected,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '지울 지도'),
              items: maps
                  .map(
                    (map) => DropdownMenuItem(
                      value: map.mapId,
                      child: Text(
                        map.mapName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged:
                  _busy ? null : (value) => setState(() => _target = value),
            ),
            const SizedBox(height: 6),
            CheckboxListTile(
              value: _alsoDestinations,
              onChanged: _busy
                  ? null
                  : (value) =>
                      setState(() => _alsoDestinations = value ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              title: const Text(
                '이 지도에 저장한 장소도 함께 지웁니다',
                style: TextStyle(fontSize: 13),
              ),
              subtitle: const Text(
                '같은 이름으로 다시 그릴 생각이면 체크하지 마세요.',
                style: TextStyle(fontSize: 11, color: VicaColors.muted),
              ),
            ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: selected == null || _busy
                  ? null
                  : () => _confirmDelete(context, settings, selected),
              icon: const Icon(Icons.delete_forever_outlined),
              label: const Text('지도 삭제'),
              style: OutlinedButton.styleFrom(
                foregroundColor: VicaColors.red,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    AppSettings settings,
    String mapId,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('지도를 지웁니다'),
        content: Text(
          "'$mapId' 의 지도 파일을 지웁니다. 되돌릴 수 없습니다."
          "${_alsoDestinations ? '\n\n이 지도에 저장한 장소도 함께 사라집니다.' : ''}",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('그만두기'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: VicaColors.red),
            child: const Text('지우기'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }

    setState(() => _busy = true);
    final message = await context.read<SupervisorProvider>().deleteMap(
          settings,
          mapId,
          deleteDestinations: _alsoDestinations,
        );
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _target = null;
    });
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.number = false,
  });

  final TextEditingController controller;
  final String label;
  final bool number;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}
