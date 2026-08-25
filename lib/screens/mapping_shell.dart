// 이 파일은 '지도' 모드의 4단계 화면입니다.
//
// 단계를 나눈 이유는 화면을 예쁘게 만들려는 것이 아닙니다. 매핑은 시작하면
// 되돌릴 수 없는 일(사람이 로봇을 30분 끌고 다님)이고, 이 프로젝트는 그 30분을
// 실제로 여러 번 잃었습니다.
//
//   2026-08-11 20:07  스택이 두 벌 돌아 두 회차 유실
//   2026-08-12 오전   아홉 회차가 저장 실패로 사라짐
//   자이로 편향 -85 deg/hour  14.2분 주행이면 20도 — 회차의 유효·무효를 가른다
//
// 그래서 ①단계가 이 화면의 존재 이유입니다. 시작 버튼 앞에 문턱을 둡니다.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_settings.dart';
import '../models/mapping_status.dart';
import '../providers/app_mode_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/supervisor_provider.dart';
import 'settings_screen.dart';
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

  // 물리 E-stop 확인은 사람만 할 수 있습니다. AGENTS.md 5절이 요구하는 확인이라
  // 화면이 대신 체크해 주지 않습니다.
  bool _estopConfirmed = false;
  String _savedMapId = '';
  // '지도 작성 완료'를 눌렀는가. 감독 노드는 mapping 상태 그대로이므로(저장을
  // 불러야 saving 이 된다) ③ 저장 단계로 넘어가는 것은 화면만의 상태다.
  // 2026-08-25 실기: 이 상태가 없어서 버튼이 빈 setState 로 남았고, ③으로
  // 넘어갈 방법이 화면에 존재하지 않았다.
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
    // 저장은 젯슨에서 비동기로 돈다. 서비스 응답 직후에는 아직 '저장 중'이라
    // _save 의 일회성 검사로는 완료를 못 본다 (2026-08-25 실기: 저장은 됐는데
    // 화면이 ③에 갇힘). 그래서 상태가 갱신될 때마다 여기서 완료를 판정한다 —
    // 감독 노드가 저장을 마치면 detail 에 '저장 완료'와 map_id 를 실어 보낸다.
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
            onPressed: () => context.read<AuthProvider>().logout(),
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
              isLast: true,
              child: _DoneStep(
                mapId: savedMapId,
                onRefreshMaps: () => supervisor.requestMapList(settings),
                onFinish: () => _stop(context, settings, thenIdle: true),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -- 동작 ---------------------------------------------------------------

  Future<void> _start(BuildContext context, AppSettings settings) async {
    // 새 회차다. 지난 회차의 '지도 작성 완료' 상태가 남아 있으면 시작하자마자
    // 저장 단계로 건너뛴 것처럼 보인다.
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
    // 종료 전에 teleop 을 확실히 멈춥니다. 손을 떼면 어차피 멈추지만, 여기서
    // 명시적으로 0을 보내면 종료와 정지 사이가 벌어지지 않습니다.
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
    final message = await supervisor.saveMap(settings, name);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
    // 저장은 젯슨에서 따로 돕니다. 결과는 /vica/mapping_status 의 detail 로 오므로
    // 여기서 성공을 단정하지 않고, 상태가 알려줄 때 완료 단계로 넘어갑니다.
    final status = supervisor.mappingStatus;
    if (status != null && status.detail.contains('저장 완료') && mounted) {
      setState(() => _savedMapId = status.mapId);
    }
  }

  Future<void> _changeMode(BuildContext context, MappingStatus? status) async {
    // [A4] 매핑이 진행 중이면 나가지 못하게 합니다. 화면을 떠나면 종료·저장
    // 버튼에 손이 닿지 않고, 그 사이 로봇은 계속 그리고 있습니다.
    if (status != null && status.busy) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('매핑이 진행 중입니다'),
          content: Text(
            '${status.state.label} 상태입니다. 모드를 바꾸면 종료·저장 버튼에 '
            '닿을 수 없으니 먼저 저장하거나 종료해 주세요.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('확인'),
            ),
          ],
        ),
      );
      return;
    }
    context.read<AppModeProvider>().clear();
  }
}

// ---------------------------------------------------------------------------

class _Step extends StatelessWidget {
  const _Step({
    required this.index,
    required this.current,
    required this.title,
    required this.child,
    this.isLast = false,
  });

  final int index;
  final int current;
  final String title;
  final Widget child;
  final bool isLast;

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
                    color: done ? VicaColors.green : VicaColors.softBlue,
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

// 중앙 E-stop 래치를 앱에서 푸는 자리입니다.
//
// **왜 매핑 모드에 따로 필요한가.** 비상정지 오버레이는 주행 모드 화면(SupervisorShell)
// 에만 있습니다. 그런데 래치는 기동 직후 latched 로 시작하고, 풀지 않으면
// /cmd_vel_safe 가 나가지 않아 **로봇을 끌고 다닐 수 없습니다** — 지도 작성 자체가
// 시작되지 않습니다(vica_map 프로파일 설명).
//
// **순서가 있습니다.** 선행 조건이 safety 와 motor 입니다. /motor/can_ok 가 래치
// 원인의 하나라 motor node 가 없으면 motor_can_stale 이 남아 reset 이 거부됩니다.
// 고장이 아니라 설계입니다 — 동력 상태를 모르는 채로는 풀지 않습니다.
//
// 정본은 로그인한 관리자가 앱에서 하는 단일 reset 이고(AGENTS.md 4절), 이 버튼이
// 부르는 /app_estop_reset 이 바로 그 경로입니다.
class _EmergencyResetCard extends StatelessWidget {
  const _EmergencyResetCard();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    final supervisor = context.watch<SupervisorProvider>();
    final state = supervisor.emergencyStopState;

    // 걸려 있지 않으면 자리를 차지하지 않습니다.
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
            // 순서를 거꾸로 안내하면 안 된다. 해제는 motor 가 떠 있어야 되고,
            // motor 는 '매핑 시작'이 띄운다 — 2026-08-25 실기에서 이 문구가
            // "해제부터 하라"로 읽혀 관리자가 순환 잠금에 빠진 줄 알았다.
            supervisor.emergencyStopMessage.isEmpty
                ? '걸린 채로 두고 먼저 아래에서 매핑을 시작하세요. 모터가 떠야 '
                    '해제할 수 있고, 해제 전에는 바퀴가 돌지 않아 안전합니다.'
                : supervisor.emergencyStopMessage,
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
          const Text(
            '거부되면 아직 남은 원인이 있는 것입니다. safety 와 motor 가 먼저 떠 '
            '있어야 합니다 — /motor/can_ok 가 래치 원인의 하나라, 동력 상태를 모르는 '
            '채로는 풀지 않습니다.',
            style: TextStyle(fontSize: 11, color: VicaColors.muted),
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
        color: VicaColors.softBlue,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: VicaColors.border),
      ),
      child: const Row(
        children: [
          Icon(Icons.help_outline, color: VicaColors.muted, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'mapping_supervisor_node 에서 상태를 아직 받지 못했습니다. '
              '젯슨에서 그 노드가 실행 중인지 확인해 주세요.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

// ① 준비 확인 — 시작 버튼 앞의 문턱.
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
        '같은 노드가 두 번 떠 있습니다: ${status!.duplicated.join(", ")}',
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
                    blocker,
                    style: const TextStyle(fontSize: 12, color: VicaColors.red),
                  ),
                ),
              ],
            ),
          ),
        if (blockers.isEmpty)
          const Row(
            children: [
              Icon(Icons.check_circle_outline,
                  size: 16, color: VicaColors.green),
              SizedBox(width: 8),
              Text(
                '충돌 없음. 필요한 노드가 모두 떠 있습니다.',
                style: TextStyle(fontSize: 12, color: VicaColors.green),
              ),
            ],
          ),
        const SizedBox(height: 6),
        // 사람만 할 수 있는 확인입니다. AGENTS.md 5절이 요구합니다 —
        // "물리 E-stop과 즉시 전원 차단 수단을 확인한 경우에만".
        CheckboxListTile(
          value: estopConfirmed,
          onChanged: onEstopChanged,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
          title: const Text(
            '물리 비상정지 버튼과 전원 차단 수단을 확인했습니다',
            style: TextStyle(fontSize: 13),
          ),
          subtitle: const Text(
            '이 단계에서 바퀴가 도는 노드(motor)가 함께 뜹니다.',
            style: TextStyle(fontSize: 11, color: VicaColors.muted),
          ),
        ),
        const SizedBox(height: 6),
        FilledButton.icon(
          onPressed: canStart ? onStart : null,
          icon: const Icon(Icons.play_arrow),
          label: const Text('매핑 시작'),
        ),
        const SizedBox(height: 8),
        const Text(
          'd455(Docker)와 IMU 는 앱이 띄우지 않습니다. IMU 를 띄운 뒤 20초 동안 '
          '로봇을 완전히 세워 자이로 보정이 끝난 것을 확인하고 시작하세요.',
          style: TextStyle(fontSize: 11, color: VicaColors.muted),
        ),
      ],
    );
  }
}

// ② 작성 중 — 미리보기와 조작판.
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
          const Text(
            '아직 지도가 오지 않았습니다. 로봇을 조금 움직이면 그려지기 시작합니다.',
            style: TextStyle(fontSize: 12, color: VicaColors.muted),
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
              robot: supervisor.primaryRobot,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${preview.width}×${preview.height} 칸 · '
            '${(preview.bytes / 1024).toStringAsFixed(1)} KB · '
            '${preview.seq}회 갱신',
            style: const TextStyle(fontSize: 11, color: VicaColors.muted),
          ),
        ],
        const SizedBox(height: 12),
        TeleopPad(enabled: status?.state == MappingState.mapping),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: status?.canSave == true ? onGoSave : null,
                icon: const Icon(Icons.save_outlined),
                label: const Text('지도 작성 완료'),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton(
              onPressed: onStop,
              child: const Text('취소'),
            ),
          ],
        ),
      ],
    );
  }
}

// ③ 저장 — 이름은 사람이, 날짜는 로봇이.
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
            hintText: '예: lobby',
            // 스크립트가 ^[A-Za-z0-9_-]+$ 를 강제합니다. 저장 버튼을 누른 뒤에
            // 거부당하면 지도를 날리므로 여기서 미리 알려 줍니다.
            helperText: '영문·숫자·밑줄(_)·붙임표(-)만. 날짜는 자동으로 붙습니다.',
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: onSave,
          icon: const Icon(Icons.save),
          label: const Text('저장'),
        ),
        if (status != null && status!.detail.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            status!.detail,
            style: const TextStyle(fontSize: 12, color: VicaColors.muted),
          ),
        ],
        const SizedBox(height: 8),
        const Text(
          '저장은 젯슨에서 따로 돕니다. 최대 2분까지 걸릴 수 있고, 끝나면 위에 '
          '결과가 표시됩니다.',
          style: TextStyle(fontSize: 11, color: VicaColors.muted),
        ),
      ],
    );
  }
}

// ④ 완료.
class _DoneStep extends StatelessWidget {
  const _DoneStep({
    required this.mapId,
    required this.onRefreshMaps,
    required this.onFinish,
  });

  final String mapId;
  final VoidCallback onRefreshMaps;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$mapId 로 저장했습니다.',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onRefreshMaps,
                icon: const Icon(Icons.refresh),
                label: const Text('지도 목록 새로고침'),
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
      ],
    );
  }
}
