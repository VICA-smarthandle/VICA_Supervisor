// 이 파일은 rosbridge 주소, 지도 서버 주소, topic 이름, 동기화와 좌표 보정 설정을 편집합니다.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_settings.dart';
import '../providers/settings_provider.dart';
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
