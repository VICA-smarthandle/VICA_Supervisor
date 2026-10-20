import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_settings.dart';
import '../models/mapping_status.dart';
import '../providers/app_mode_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/supervisor_provider.dart';
import 'settings_screen.dart';
import '../widgets/confirm_logout.dart';
import '../widgets/map_canvas.dart';
import '../widgets/ros_connection_tile.dart';
import '../widgets/teleop_pad.dart';
import '../widgets/vica_ui.dart';

class MappingShell extends StatefulWidget {
  const MappingShell({super.key});

  @override
  State<MappingShell> createState() => _MappingShellState();
}

class _MappingShellState extends State<MappingShell> {
  final _nameController = TextEditingController();

  bool _estopConfirmed = false;
  String _savedMapId = '';
  bool _readyToSave = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  int _stepIndex(MappingStatus? status) {
    if (_savedMapId.isNotEmpty) {
      return 3;
    }
    switch (status?.state) {
      case MappingState.saving:
        return 2;
      case MappingState.mapping:
        return _readyToSave ? 2 : 1;
      case MappingState.starting:
        return 1;
      default:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    final supervisor = context.watch<SupervisorProvider>();
    final status = supervisor.mappingStatus;
    final savedMapId = _savedMapId.isNotEmpty
        ? _savedMapId
        : ((status?.detail.contains('저장 완료') ?? false) ? status!.mapId : '');
    final step = savedMapId.isNotEmpty ? 3 : _stepIndex(status);

    return Scaffold(
      appBar: AppBar(
        title: const Text('지도'),
        actions: [
          TextButton.icon(
            onPressed: () => _changeMode(context, status),
            icon: const Icon(Icons.swap_horiz),
            label: const Text('모드 바꾸기'),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
            ),
            icon: const Icon(Icons.settings_outlined),
            tooltip: '설정',
          ),
          IconButton(
            onPressed: () => confirmLogout(context),
            icon: const Icon(Icons.logout),
            tooltip: '로그아웃',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: VicaPage(
          title: '새 지도 그리기',
          children: [
            const VicaRosConnectionTile(),
            const _EmergencyResetCard(),
            if (status == null) const _WaitingForSupervisor(),
            _Step(
              index: 0,
              current: step,
              title: '준비 확인',
              child: _PrepareStep(
                status: status,
                estopConfirmed: _estopConfirmed,
                onEstopChanged: (value) =>
                    setState(() => _estopConfirmed = value ?? false),
                onStart: () => _start(context, settings),
              ),
            ),
            _Step(
              index: 1,
              current: step,
              title: '작성 중',
              child: _MappingStep(
                settings: settings,
                onStop: () => _stop(context, settings),
                onGoSave: () => setState(() => _readyToSave = true),
              ),
            ),
            _Step(
              index: 2,
              current: step,
              title: '저장',
              child: _SaveStep(
                controller: _nameController,
                status: status,
                onSave: () => _save(context, settings),
              ),
            ),
            _Step(
              index: 3,
              current: step,
              title: '완료',
              child: _DoneStep(
                mapId: savedMapId,
                mapName: status != null &&
                        status.mapId == savedMapId &&
                        status.mapName.isNotEmpty
                    ? status.mapName
                    : savedMapId,
                alignSentence: status != null && status.mapId == savedMapId
                    ? status.saveAlign?.sentence
                    : null,
                onRefreshMaps: () => supervisor.requestMapList(settings),
                onFinish: () => _stop(context, settings, thenIdle: true),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _start(BuildContext context, AppSettings settings) async {
    setState(() => _readyToSave = false);
    final message =
        await context.read<SupervisorProvider>().startMapping(settings);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _stop(
    BuildContext context,
    AppSettings settings, {
    bool thenIdle = false,
  }) async {
    final supervisor = context.read<SupervisorProvider>();
    supervisor.releaseTeleop();
    final message = await supervisor.stopMapping(settings);
    if (thenIdle && mounted) {
      setState(() {
        _savedMapId = '';
        _estopConfirmed = false;
        _readyToSave = false;
        _nameController.clear();
      });
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _save(BuildContext context, AppSettings settings) async {
    final name = _nameController.text.trim();
    final supervisor = context.read<SupervisorProvider>();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('지도 이름을 입력해 주세요.')),
      );
      return;
    }
    final choice = await showDialog<_SaveChoice>(
      context: context,
      builder: (_) => _SaveAlignDialog(
        name: name,
        tiltDeg: supervisor.mapPreview?.tiltDeg,
      ),
    );
    if (choice == null || choice == _SaveChoice.cancel || !context.mounted) {
      return;
    }
    final message = await supervisor.saveMap(
      settings,
      name,
      align: choice == _SaveChoice.align,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
    final status = supervisor.mappingStatus;
    if (status != null && status.detail.contains('저장 완료') && mounted) {
      setState(() => _savedMapId = status.mapId);
    }
  }

  Future<void> _changeMode(BuildContext context, MappingStatus? status) async {
    if (status != null && status.busy) {
      await showVicaNotice(
        context,
        icon: Icons.place_outlined,
        title: '매핑이 진행 중입니다',
        body: '${status.state.label}입니다. '
            '모드를 바꾸면 종료·저장 버튼이 보이지 않을 수 있으니 '
            '먼저 저장하거나 종료해 주세요.',
      );
      return;
    }
    context.read<AppModeProvider>().clear();
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.index,
    required this.current,
    required this.title,
    required this.child,
  });

  final int index;
  final int current;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final done = index < current;
    final active = index == current;
    final colour = done
        ? VicaColors.green
        : (active ? VicaColors.primary : VicaColors.muted);

    return Opacity(
      opacity: active || done ? 1 : 0.5,
      child: VicaCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: done ? VicaColors.green : VicaColors.accentTint,
                    shape: BoxShape.circle,
                  ),
                  child: done
                      ? const Icon(Icons.check, size: 15, color: Colors.white)
                      : Text(
                          '${index + 1}',
                          style: TextStyle(
                            color: colour,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: active ? VicaColors.text : VicaColors.muted,
                  ),
                ),
              ],
            ),
            if (active) ...[
              const SizedBox(height: 14),
              child,
            ],
          ],
        ),
      ),
    );
  }
}

class _EmergencyResetCard extends StatelessWidget {
  const _EmergencyResetCard();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    final supervisor = context.watch<SupervisorProvider>();
    final state = supervisor.emergencyStopState;

    if (state == EmergencyStopState.inactive) {
      return const SizedBox.shrink();
    }

    final busy = state == EmergencyStopState.releasing ||
        state == EmergencyStopState.activating;
    final label = switch (state) {
      EmergencyStopState.active => '비상정지가 걸려 있습니다',
      EmergencyStopState.releasing => '해제하는 중입니다',
      EmergencyStopState.releaseFailed => '해제하지 못했습니다',
      EmergencyStopState.activating => '비상정지를 거는 중입니다',
      EmergencyStopState.activationFailed => '비상정지에 실패했습니다',
      EmergencyStopState.inactive => '',
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: VicaColors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: VicaColors.red.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_rounded,
                  color: VicaColors.red, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            vicaKeepWords(vicaBreakAtSentences(
              supervisor.emergencyStopMessage.isEmpty
                  ? '해제 전에는 로봇이 움직이지 않습니다. 해제하려면 safety 와 '
                      'motor 가 먼저 떠 있어야 합니다.'
                  : supervisor.emergencyStopMessage,
            )),
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed:
                busy ? null : () => supervisor.resetEmergencyStop(settings),
            icon: const Icon(Icons.lock_open),
            label: Text(
              state == EmergencyStopState.releaseFailed
                  ? '해제 다시 시도'
                  : '비상정지 해제',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            vicaKeepWords(vicaBreakAtSentences(
              '거부되면 아직 남은 원인이 있는 것입니다. safety 와 motor 가 먼저 떠 '
              '있어야 합니다.',
            )),
            style: const TextStyle(fontSize: 11, color: VicaColors.muted),
          ),
        ],
      ),
    );
  }
}

class _WaitingForSupervisor extends StatelessWidget {
  const _WaitingForSupervisor();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: VicaColors.accentTint,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: VicaColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.help_outline, color: VicaColors.muted, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              vicaKeepWords(vicaBreakAtSentences(
                'mapping_supervisor_node 에서 상태를 아직 받지 못했습니다. '
                '노드가 실행 중인지 확인해 주세요.',
              )),
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrepareStep extends StatelessWidget {
  const _PrepareStep({
    required this.status,
    required this.estopConfirmed,
    required this.onEstopChanged,
    required this.onStart,
  });

  final MappingStatus? status;
  final bool estopConfirmed;
  final ValueChanged<bool?> onEstopChanged;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final blockers = <String>[
      if (status == null) '로봇 상태를 아직 받지 못했습니다.',
      if (status != null && status!.nav2Running)
        'Nav2 가 실행 중입니다. 동시에 뜨면 /odom 발행자가 둘이 되어 위치추정이 깨집니다.',
      if (status != null && status!.duplicated.isNotEmpty)
        '동일 노드가 동시에 떠 있습니다: ${status!.duplicated.join(", ")}',
      if (status != null && status!.prerequisitesMissing.isNotEmpty)
        '먼저 띄워야 할 것이 있습니다: ${status!.prerequisitesMissing.join(", ")}',
    ];
    final canStart =
        blockers.isEmpty && estopConfirmed && (status?.canStart ?? false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final blocker in blockers)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.block, size: 16, color: VicaColors.red),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    vicaKeepWords(vicaBreakAtSentences(blocker)),
                    style: const TextStyle(fontSize: 12, color: VicaColors.red),
                  ),
                ),
              ],
            ),
          ),
        if (blockers.isEmpty)
          Row(
            children: [
              const Icon(Icons.check_circle_outline,
                  size: 16, color: VicaColors.green),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  vicaKeepWords(vicaBreakAtSentences(
                    '충돌 없음. 필요한 노드가 모두 떠 있습니다.',
                  )),
                  style: const TextStyle(fontSize: 12, color: VicaColors.green),
                ),
              ),
            ],
          ),
        const SizedBox(height: 10),
        const _StartDirectionHint(),
        const SizedBox(height: 6),
        Material(
          type: MaterialType.transparency,
          child: CheckboxListTile(
            value: estopConfirmed,
            onChanged: onEstopChanged,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            title: Text(
              vicaKeepWords('비상시를 대비한 비상정지 버튼을 확인했습니다'),
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ),
        const SizedBox(height: 6),
        FilledButton.icon(
          onPressed: canStart ? onStart : null,
          icon: const Icon(Icons.play_arrow),
          label: const Text('매핑 시작'),
        ),
        const SizedBox(height: 8),
        Text(
          vicaKeepWords(vicaBreakAtSentences(
            'd455(Docker)와 IMU 는 앱이 실행하지 않습니다. '
            'IMU 를 띄운 뒤 20초 동안 로봇을 완전히 세워 자이로 보정이 끝난 것을 확인하고 시작하세요.',
          )),
          style: const TextStyle(fontSize: 11, color: VicaColors.muted),
        ),
      ],
    );
  }
}

class _MappingStep extends StatelessWidget {
  const _MappingStep({
    required this.settings,
    required this.onStop,
    required this.onGoSave,
  });

  final AppSettings settings;
  final VoidCallback onStop;
  final VoidCallback onGoSave;

  @override
  Widget build(BuildContext context) {
    final supervisor = context.watch<SupervisorProvider>();
    final preview = supervisor.mapPreview;
    final status = supervisor.mappingStatus;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (preview == null)
          Text(
            vicaKeepWords(vicaBreakAtSentences(
              '지도를 띄우는 중입니다. 로봇을 조금 움직이면 그려지기 시작합니다.',
            )),
            style: const TextStyle(fontSize: 12, color: VicaColors.muted),
          )
        else ...[
          ResponsiveMapFrame(
            map: preview.toVicaMap(),
            minHeight: 220,
            maxHeight: 420,
            child: MapCanvas(
              map: preview.toVicaMap(),
              settings: settings,
              locations: const [],
              poseArrow: preview.hasRobotPose
                  ? MapPoseArrow(
                      x: preview.robotX!,
                      y: preview.robotY!,
                      yawDegrees: preview.robotYaw!,
                      label: '로봇 위치',
                      color: VicaColors.red,
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${preview.width}×${preview.height} 칸 · '
            '${(preview.bytes / 1024).toStringAsFixed(1)} KB · '
            '${preview.seq}회 갱신'
            '${preview.hasRobotPose ? '' : ' · 로봇 위치 없음'}',
            style: const TextStyle(fontSize: 11, color: VicaColors.muted),
          ),
        ],
        const SizedBox(height: 12),
        TeleopPad(enabled: status?.state == MappingState.mapping),
        const SizedBox(height: 4),
        FilledButton.icon(
          onPressed: status?.canSave == true ? onGoSave : null,
          icon: const Icon(Icons.save_outlined),
          label: const Text('지도 작성 완료'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: onStop,
          child: const Text('취소'),
        ),
      ],
    );
  }
}

class _SaveStep extends StatelessWidget {
  const _SaveStep({
    required this.controller,
    required this.status,
    required this.onSave,
  });

  final TextEditingController controller;
  final MappingStatus? status;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '지도 이름',
            hintText: '예: 병원 2층',
            helperText: '이름 뒤에 날짜가 붙습니다.',
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: status?.state == MappingState.saving ? null : onSave,
          icon: const Icon(Icons.save),
          label: const Text('저장'),
        ),
        if (status != null &&
            status!.state != MappingState.mapping &&
            status!.detail.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            status!.detail,
            style: const TextStyle(fontSize: 12, color: VicaColors.muted),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          vicaKeepWords(vicaBreakAtSentences(
            '저장 중입니다. 최대 2분까지 걸릴 수 있고, 끝나면 위에 결과가 표시됩니다.',
          )),
          style: const TextStyle(fontSize: 11, color: VicaColors.muted),
        ),
      ],
    );
  }
}

class _DoneStep extends StatelessWidget {
  const _DoneStep({
    required this.mapId,
    required this.mapName,
    required this.onRefreshMaps,
    required this.onFinish,
    this.alignSentence,
  });

  final String mapId;
  final String mapName;
  final VoidCallback onRefreshMaps;
  final VoidCallback onFinish;

  /// 바르게 세웠는지 결과 한 줄. 고른 버튼과 기울기에 따라 목업 14번의 셋
  final String? alignSentence;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          vicaKeepWords('저장했습니다: $mapName'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        if (alignSentence != null) ...[
          const SizedBox(height: 4),
          Text(
            vicaKeepWords(alignSentence!),
            style: const TextStyle(fontSize: 13, color: VicaColors.muted),
          ),
        ],
        if (mapName != mapId) ...[
          const SizedBox(height: 4),
          Text(
            vicaKeepWords('파일 이름: $mapId'),
            style: const TextStyle(fontSize: 12, color: VicaColors.muted),
          ),
        ],
        const SizedBox(height: 10),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onRefreshMaps,
                  icon: const Icon(Icons.refresh),
                  label: const Text(
                    '지도 목록\n새로고침',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: onFinish,
                  child: const Text('매핑 종료'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StartDirectionHint extends StatelessWidget {
  const _StartDirectionHint();

  static const _sections = <(String, List<String>)>[
    (
      '매핑 시 정렬 방향',
      [
        '지도에서 위쪽(정면)으로 두고 싶은 방향을 바라보고 서서, '
            '로봇이 내 오른쪽을 향하게 두고 시작합니다.',
        '매핑을 시작해 로봇 화살표가 처음 나타날 때 오른쪽을 가리키면 '
            '맞게 선 것입니다.',
      ],
    ),
    (
      '매핑 시 주의할 점',
      [
        '제자리 회전은 90°씩 끊고, 사이마다 1~2초 멈추세요.',
        '출발한 자리로 돌아와 끝내세요(루프 클로저).',
        '빨간 화살표가 벽 밖으로 튀면 저장하지 말고 다시 그리세요.',
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: VicaColors.accentTint,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.explore_outlined,
              size: 18, color: VicaColors.primaryDark),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (index, (title, lines)) in _sections.indexed) ...[
                  if (index > 0) const SizedBox(height: 8),
                  Text(
                    vicaKeepWords(title),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: VicaColors.primaryDark,
                    ),
                  ),
                  for (final line in lines)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        vicaKeepWords(line),
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: VicaColors.primaryDark,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 굵은 조각이 섞인 안내문. 조각마다 vicaKeepWords 를 거치고, 조각 경계가 낱말
TextSpan _keepWordsSpans(List<(String, bool)> parts) {
  final spans = <TextSpan>[];
  var previous = '';
  for (final (text, bold) in parts) {
    var kept = vicaKeepWords(text);
    final joins = previous.isNotEmpty &&
        !RegExp(r'\s$').hasMatch(previous) &&
        !RegExp(r'^\s').hasMatch(text);
    if (joins) {
      kept = '\u2060$kept';
    }
    spans.add(TextSpan(
      text: kept,
      style: bold ? const TextStyle(fontWeight: FontWeight.w800) : null,
    ));
    previous = text;
  }
  return TextSpan(children: spans);
}

enum _SaveChoice { align, plain, cancel }

class _SaveAlignDialog extends StatelessWidget {
  const _SaveAlignDialog({required this.name, this.tiltDeg});

  final String name;

  /// 미리보기가 잰 지금 기울기. null 이면 '지금 기울기' 줄을 숨깁니다.
  final double? tiltDeg;

  @override
  Widget build(BuildContext context) {
    final tilt = tiltDeg;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                vicaKeepWords('지도를 바르게 세워 저장할까요?'),
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 14),
              const _AlignPreviewPicture(),
              const SizedBox(height: 14),
              _DialogLine(label: '지도 이름', value: name),
              if (tilt != null) ...[
                const SizedBox(height: 6),
                _DialogLine(
                  label: '지금 기울기',
                  value: '약 ${tilt.abs().toStringAsFixed(1)}°',
                ),
              ],
              const SizedBox(height: 14),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: VicaColors.accentTint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text.rich(
                  _keepWordsSpans(const [
                    ('벽이 화면과 나란해지도록 지도를 돌려 저장합니다.\n기울기가 ', false),
                    ('2° 미만', true),
                    ('이면 정렬을 눌러도 돌리지 않고 그대로 저장합니다.', false),
                  ]),
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.55,
                    color: VicaColors.primaryDark,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(_SaveChoice.align),
                  child: const Text('정렬해서 저장'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 48,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(_SaveChoice.plain),
                  child: const Text('정렬하지 않고 저장'),
                ),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => Navigator.of(context).pop(_SaveChoice.cancel),
                child: const Text(
                  '취소',
                  style: TextStyle(color: VicaColors.muted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogLine extends StatelessWidget {
  const _DialogLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 14, color: VicaColors.muted),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            vicaKeepWords(value),
            textAlign: TextAlign.end,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _AlignPreviewPicture extends StatelessWidget {
  const _AlignPreviewPicture();

  static const _mapFrame = Color(0xFFD9D5CC);
  static const _wall = Color(0xFF3A3C37);

  Widget _thumb({required double turnDegrees, required String label}) {
    return Semantics(
      label: label,
      image: true,
      child: Container(
        width: 120,
        height: 84,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _mapFrame,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Transform.rotate(
          angle: turnDegrees * 3.141592653589793 / 180,
          child: Container(
            width: 76,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: _wall, width: 3),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: VicaColors.surfaceSunken,
        border: Border.all(color: VicaColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _thumb(turnDegrees: 6, label: '지금: 약간 기울어진 지도'),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child:
                  Icon(Icons.arrow_forward, size: 20, color: VicaColors.muted),
            ),
            _thumb(turnDegrees: 0, label: '정렬 뒤: 화면과 나란한 지도'),
          ],
        ),
      ),
    );
  }
}
