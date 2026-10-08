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
                mapName: status != null &&
                        status.mapId == savedMapId &&
                        status.mapName.isNotEmpty
                    ? status.mapName
                    : savedMapId,
                // 바르게 세웠는지 결과 한 줄(2026-10-07, 목업 14번). 감독 노드가
                // 저장을 마치며 save_align 으로 보냅니다. 옛 노드면 없습니다.
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
    if (name.isEmpty) {
      // 감독 노드(plan_map_save)가 돌려줄 문구와 같습니다. 팝업을 띄우기 전에
      // 막아야 이름 없는 지도로 정렬 여부부터 묻는 일이 없습니다.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('지도 이름을 입력해 주세요.')),
      );
      return;
    }
    // 바르게 세워 저장할지 묻습니다(2026-10-07, 목업 13번). 기울기는 미리보기가
    // 저장 스크립트와 같은 계산으로 재 보냅니다. 못 쟀으면 그 줄만 숨습니다.
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
        builder: (dialogContext) => VicaDialog(
          icon: Icons.place_outlined,
          title: '매핑이 진행 중입니다',
          // 문장은 마침표에서 나뉘고 그 안은 어절 단위로 접힙니다(VicaDialog).
          body: '${status.state.label}입니다. '
              '모드를 바꾸면 종료·저장 버튼이 보이지 않을 수 있으니 '
              '먼저 저장하거나 종료해 주세요.',
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
            // 특정 모드의 절차를 지시하지 않는다 — 비상정지는 모드와 무관한
            // 안전 장치라, 여기서는 그 사실만 말한다 (2026-08-25 실기 피드백).
            // 마침표에서 줄을 나누고 그 안은 어절 단위로 접힌다(2026-09-15).
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
              // 좁은 창(320)에서 글자가 오른쪽으로 74px 넘쳤습니다(2026-09-15).
              // 남는 폭만 쓰고 줄을 바꾸게 합니다.
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
        // 사람만 할 수 있는 확인입니다. AGENTS.md 5절의 확인 요구가 근거이고,
        // 문구는 2026-08-25 실기 피드백으로 짧게 다듬었습니다. motor 를 여기서
        // 띄운다던 부제는 소유권이 터미네이터로 고정되며 사실이 아니게 되어
        // 뺐습니다.
        // Material 로 감싸는 이유: ListTile 은 잉크 효과를 가장 가까운 Material 에
        // 그리는데, 카드(VicaCard)가 색 있는 Container 라 그 사이에 Material 이
        // 없으면 효과가 카드 뒤에 숨습니다. Flutter 3.44 는 이를 assertion 으로
        // 잡아 이 화면의 위젯 시험 전부가 첫 프레임에서 죽었습니다(2026-09-04).
        // transparency 라 보이는 모양은 그대로입니다.
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
          // 두 문장이 띄어쓰기 없이 붙어 보였습니다(2026-09-15 검토). 마침표
          // 뒤에서 줄을 바꾸고, 그 안은 어절 단위로 접힙니다.
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
              // 로봇 위치는 미리보기 JSON 에 함께 실려 옵니다(map_preview_node 가
              // Cartographer 의 /tracked_pose 를 동봉). /robot_status 를 넘기면
              // 매핑 중엔 map_id 가 비어 그려지지 않고, 위치도 /odom 좌표라
              // 엉뚱한 자리에 찍힙니다(2026-09-04). poseArrow 는 지도 id 를 따지지
              // 않아 초기위치·홈 화면과 같은 방식으로 씁니다.
              poseArrow: preview.hasRobotPose
                  ? MapPoseArrow(
                      x: preview.robotX!,
                      y: preview.robotY!,
                      yawDegrees: preview.robotYaw!,
                      label: '로봇 위치',
                      // 회색 지도 위에서 잘 보이게 빨강(2026-09-15).
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
        // 버튼 둘을 위아래로 놓습니다(2026-09-14 시안). 전에는 Row 에 두었는데,
        // 버튼 테마의 최소 폭이 무한대라 Expanded 없이 놓인 '취소'가 "무한 폭"
        // 배치 오류를 내고 이 화면 전체가 그려지지도, 눌리지도 않았습니다.
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
            hintText: '예: 병원 2층',
            // 한글도 됩니다(2026-09-04). 파일·URL 에는 영문 id 만 들어가고 한글은
            // 표시 이름으로만 남습니다 — 규칙은 감독 노드(plan_map_save)가 정하고
            // 거부 사유는 저장 응답으로 옵니다.
            helperText: '이름 뒤에 날짜가 붙습니다.',
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          // 저장 중에는 막습니다. 누르면 정렬 팝업부터 뜨고 고른 뒤에야 감독
          // 노드가 거부해 한 단계를 헛걸음하게 됩니다(2026-10-07 검토).
          onPressed: status?.state == MappingState.saving ? null : onSave,
          icon: const Icon(Icons.save),
          label: const Text('저장'),
        ),
        // 노드가 보내는 상태 설명은 저장 중·오류일 때만 보입니다. 지도를 그리는
        // 중이라는 말은 이 단계에선 뻔한 소리라 뺐습니다(2026-09-15). 거부 사유는
        // 저장 응답이 상태 설명으로 오므로 그때는 그대로 보여야 합니다.
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

// ④ 완료.
class _DoneStep extends StatelessWidget {
  const _DoneStep({
    required this.mapId,
    required this.mapName,
    required this.onRefreshMaps,
    required this.onFinish,
    this.alignSentence,
  });

  final String mapId;
  // 사람이 적은 이름. 한글이면 id 와 다르므로 파일 이름을 한 줄 더 보여 줍니다 —
  // 터미네이터에서 지도를 고를 때 둘 다 통하지만, 로그·파일에는 id 만 보입니다.
  final String mapName;
  final VoidCallback onRefreshMaps;
  final VoidCallback onFinish;

  /// 바르게 세웠는지 결과 한 줄. 고른 버튼과 기울기에 따라 목업 14번의 셋
  /// (+ 벽 방향 못 찾음·실패) 중 하나입니다. null 이면 줄을 그리지 않습니다.
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
        // 왼쪽 글자가 두 줄이라 오른쪽 버튼도 같은 높이로 늘립니다.
        // Column 안의 Row 는 높이가 무한대라 stretch 만 주면 "무한 높이" 배치
        // 오류가 납니다(2026-09-15 실기). IntrinsicHeight 로 높이를 먼저 잽니다.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onRefreshMaps,
                  icon: const Icon(Icons.refresh),
                  // 폰 폭(360~412)에서는 한 줄에 못 들어가 '새로고' + '침'으로
                  // 엉뚱하게 접힙니다. 뜻 단위로 미리 줄을 바꿉니다(2026-09-15).
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

// ① 준비 확인의 매핑 안내(2026-10-08 사용자 확정, 목업 25').
//
// 소제목 두 개(굵게)와 그 아래 문장들. 줄은 사용자가 나눈 대로 문장마다 바꾸고,
// 한 문장 안에서는 화면 폭에 따라 띄어쓰기에서만 접힙니다(vicaKeepWords).
//
// 정렬 방향: Cartographer 는 '매핑 시작'을 누르는 순간 로봇(base_footprint)이 보던
// 방향을 지도의 가로축(+x)으로 잡고, 앱은 x 를 화면 오른쪽·y 를 위로 그립니다
// (map_coordinate.dart, flipMapY 기본값). 그래서 로봇이 내 오른쪽을 향하면 내 정면이
// 화면 위가 됩니다. 화살표는 미리보기가 처음 올 때(몇 초 뒤) 나타납니다.
//
// 주의할 점: 10-08 실기에서 제자리 반 바퀴 회전 중 위치추정이 15~20 cm 틀어져 벽이
// 두 줄로 그려졌습니다(실시간 맞추기 범위 ±10 cm 초과). 끊어서 돌고, 출발점으로
// 돌아와 끝내고(루프 클로저), 화살표가 벽 밖으로 튀면 그 회차는 버립니다.
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
/// 한가운데('미만|이면')면 줄 바꿈 금지 표시(\u2060)를 이어 붙여 거기서 끊기지 않게
/// 합니다 — vicaKeepWords 는 한 조각 안만 묶습니다. 굵은 곳은 목업 12·13번 그대로.
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

// ③ 저장 버튼을 누르면 뜨는 팝업(2026-10-07, 목업 13번).
//
// 정렬해서 저장 / 정렬하지 않고 저장 / 취소. 2° 미만이면 정렬을 골라도 젯슨이
// 돌리지 않고 그대로 저장합니다(vica_cartographer/map_align.py) — 막히는 면적이
// 각도에 비례해 조금 기운 지도는 돌려서 얻는 것보다 잃는 것이 크기 때문입니다.
// 원본은 젯슨에 숨겨 두지만 화면에는 쓰지 않습니다(사용자 결정, 10-07).
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
                // 목업 13번처럼 두 줄로 나누고 '2° 미만'만 굵게 씁니다.
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

// 팝업 위쪽의 그림: 기운 지도 → 화면과 나란한 지도. 목업 13번처럼 6° 로 고정해
// 그립니다 — 실제 각도는 아래 '지금 기울기' 줄이 숫자로 알려 줍니다.
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
