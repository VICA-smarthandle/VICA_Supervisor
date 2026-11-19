// 이 파일은 로그인 직후 어떤 일을 하러 왔는지 고르는 화면입니다.
//
// 화면을 고르는 것일 뿐이지만, 여기서 젯슨의 스택 상태를 함께 보여줍니다.
// 중복 실행이 이 프로젝트에서 실제로 회차를 날린 사고이고(2026-08-11 20:07),
// 지금까지는 그 상태가 되어도 아무도 알려주지 않았기 때문입니다.
//
// 연결이 안 돼 있어도 들어갈 수 있게 둡니다. 모드 전환은 앱 화면만 바꾸는 일이라
// 막아서 얻는 안전이 없고, 막으면 연결이 안 되는 상황에서 사람이 갇힙니다.
// 대신 "확인 불가"임을 숨기지 않습니다.
//
// 2026-11-16 부팅 자동 기동: 젯슨에 모드 노드가 있으면(/vica/mode_status 가 오면) 주행
// 카드가 주행 묶음을 실제로 켭니다. 카드를 누르면 하위 모드 시트(안내·배송 / 경비, 목업
// '안 2')가 뜨고, 고르면 켜고 '주행 준비' 화면으로 갑니다. 주행이 켜진 채 지도 카드를 누르면
// 주행을 끌지 묻습니다. 모드 노드가 없으면(칸으로 띄우는 지금 방식) 예전처럼 화면만 바꿉니다.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_mode.dart';
import '../core/layout_breakpoints.dart';
import '../core/mode_contract.dart';
import '../models/mode_status.dart';
import '../models/stack_status.dart';
import '../providers/app_mode_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/supervisor_provider.dart';
import 'drive_bringup_screen.dart';
import 'robot_shutdown_screen.dart';
import 'settings_screen.dart';
import '../ros/ros_bridge_client.dart';
import '../widgets/confirm_logout.dart';
import '../widgets/drive_map_change.dart';
import '../widgets/ros_connection_tile.dart';
import '../widgets/vica_ui.dart';

/// 카드 하나가 지금 어떤 상태인지. 색·문구·진입 가능 여부를 함께 담습니다.
class _CardState {
  const _CardState({
    required this.color,
    required this.label,
    required this.enabled,
    this.hint = '',
  });

  final Color color;
  final String label;
  final bool enabled;
  final String hint;
}

class ModeSelectScreen extends StatefulWidget {
  const ModeSelectScreen({super.key});

  @override
  State<ModeSelectScreen> createState() => _ModeSelectScreenState();
}

class _ModeSelectScreenState extends State<ModeSelectScreen> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    // 화면이 뜨자마자 한 번 조회합니다. 연결이 없으면 provider 가 조용히 비웁니다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      context.read<SupervisorProvider>().refreshStackStatus();
    });
    // 열려 있는 동안 5 s 마다 다시 조회합니다(2026-11-18). 한 번만 조회하면, 주행을 막 끈 직후 노드
    // 목록에 남아 있던 Nav2(강제 종료된 노드는 20 s 남음, FastDDS 수명 측정)가 새로고침 전까지 굳었습니다.
    _poll = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) {
        return;
      }
      final supervisor = context.read<SupervisorProvider>();
      if (supervisor.connectionState == RosConnectionState.connected &&
          !supervisor.stackStatusLoading) {
        supervisor.refreshStackStatus();
      }
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final supervisor = context.watch<SupervisorProvider>();
    final connected =
        supervisor.connectionState == RosConnectionState.connected;
    final status = supervisor.stackStatus;
    final modeStatus = supervisor.modeStatus;
    final username = context.watch<AuthProvider>().currentUsername ?? '';

    return Scaffold(
      appBar: AppBar(
        // 2026-11-17 제목·문구 간결화(사용자 승인): 제목은 '모드 선택' 하나, 계정은 오른쪽 작은 글씨.
        // 2026-11-17 사용자: 처음 화면 제목은 앱 이름(로그인·브라우저 탭과 같은 이름).
        // 2026-11-17 사용자: 제목 옆에도 로고.
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            VicaLogo(size: 32),
            SizedBox(width: 10),
            Flexible(
              child: Text(
                'VICA_SUPERVISOR',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          if (username.isNotEmpty)
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 96),
                child: Text(
                  username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: VicaColors.muted),
                ),
              ),
            ),
          PressScale(child: IconButton(
            onPressed: supervisor.stackStatusLoading
                ? null
                : () => supervisor.refreshStackStatus(),
            icon: const Icon(Icons.refresh),
            tooltip: '로봇 상태 다시 확인',
          )),
          PressScale(child: IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
            ),
            icon: const Icon(Icons.settings_outlined),
            tooltip: '설정',
          )),
          PressScale(child: IconButton(
            onPressed: () => confirmLogout(context),
            icon: const Icon(Icons.logout),
            tooltip: '로그아웃',
          )),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: VicaPage(
          children: [
            const VicaRosConnectionTile(),
            if (status != null && (status.duplicated || status.conflicting))
              _ConflictNotice(status: status),
            if (!connected) const _UnknownNotice(),
            if (modeStatus != null &&
                !modeStatus.driveOn &&
                modeStatus.stopTimeouts.isNotEmpty)
              _StopWarningNotice(units: modeStatus.stopTimeouts),
            const DriveMapMismatchCard(),
            const SizedBox(height: 4),
            LayoutBuilder(
              builder: (context, constraints) {
                final driveState = _driveState(status, modeStatus);
                final mappingState = _mappingState(status, modeStatus);
                final cards = [
                  _ModeCard(
                    mode: AppMode.drive,
                    state: driveState,
                    onTap: driveState.enabled
                        ? () => _onDrive(context, modeStatus)
                        : null,
                  ),
                  _ModeCard(
                    mode: AppMode.mapping,
                    state: mappingState,
                    onTap: mappingState.enabled
                        ? () => _onMapping(context, modeStatus)
                        : null,
                  ),
                ];
                if (VicaBreakpoints.isCompact(constraints.maxWidth)) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      cards[0],
                      const SizedBox(height: 14),
                      cards[1],
                    ],
                  );
                }
                // ListView 안이라 세로가 무한이다. stretch 를 그냥 쓰면
                // "무한 높이로 늘려라"가 되어 레이아웃이 터진다. IntrinsicHeight 가
                // 두 카드 중 큰 쪽 높이를 먼저 재서 유한하게 만들어 준다.
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: cards[0]),
                      const SizedBox(width: 14),
                      Expanded(child: cards[1]),
                    ],
                  ),
                );
              },
            ),
            if (supervisor.stackStatusError.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                supervisor.stackStatusError,
                style: const TextStyle(color: VicaColors.muted, fontSize: 12),
              ),
            ],
            // 로봇 끄기(2026-11-18 사용자 결정, 목업 '로봇 끄기 A'): 모드 카드와 떨어진 맨 아래 한 줄.
            // 연결이 없으면 보낼 곳이 없어 막습니다.
            const SizedBox(height: 28),
            const Divider(height: 1),
            const SizedBox(height: 14),
            PressScale(child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: VicaColors.red,
                side: const BorderSide(color: VicaColors.red, width: 1.5),
                minimumSize: const Size.fromHeight(48),
                shape: const StadiumBorder(),
                textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
              onPressed: connected ? () => confirmAndShutdownRobot(context) : null,
              icon: const Icon(Icons.power_settings_new, size: 20),
              label: const Text('로봇 끄기'),
            )),
            const SizedBox(height: 6),
            const Text(
              '전원을 내리기 전에 누르세요',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: VicaColors.muted),
            ),
          ],
        ),
      ),
    );
  }

  // 매핑이 떠 있으면 주행으로 못 갑니다. 둘 다 wheel_ekf.launch.py 를 include 해서
  // 동시에 뜨면 /odom 발행자가 둘이 됩니다.
  // connected 를 다시 보지 않는 이유: 연결이 없으면 refreshStackStatus 가, 끊기면
  // _clearRobotRuntimeState 가 각각 status 를 비웁니다. 즉 status != null 은
  // "지금 연결 상태에서 실제로 조회에 성공했다"와 같습니다.
  _CardState _driveState(StackStatus? status, ModeStatus? mode) {
    if (status != null && status.duplicated) {
      return const _CardState(
        color: VicaColors.red,
        label: '이미 충돌 중',
        enabled: false,
        hint: '동일 노드가 동시에 실행되고 있습니다.',
      );
    }
    if (mode != null) {
      final modeCard = _driveStateFromMode(status, mode);
      if (modeCard != null) {
        return modeCard;
      }
    }
    if (status == null) {
      return const _CardState(
        color: VicaColors.muted,
        label: '확인 불가',
        enabled: true,
      );
    }
    if (status.duplicated) {
      return const _CardState(
        color: VicaColors.red,
        label: '이미 충돌 중',
        enabled: false,
        hint: '동일 노드가 동시에 실행되고 있습니다.',
      );
    }
    if (status.mappingRunning) {
      return const _CardState(
        color: VicaColors.red,
        label: '매핑 실행 중',
        enabled: false,
        hint: '매핑을 먼저 종료해야 합니다.',
      );
    }
    if (status.nav2Running) {
      return const _CardState(
        color: VicaColors.primary,
        label: '주행 노드 실행 중',
        enabled: true,
      );
    }
    return const _CardState(
      color: VicaColors.green,
      label: '준비됨',
      enabled: true,
    );
  }

  // 모드 노드가 있을 때 주행 카드. null 이면 예전 판정(노드 목록)으로 넘깁니다 —
  // 칸에서 띄운 Nav2 처럼 모드 노드가 모르는 경우입니다.
  _CardState? _driveStateFromMode(StackStatus? status, ModeStatus mode) {
    if (mode.mode == 'mapping' || (status?.mappingRunning ?? false)) {
      return const _CardState(
        color: VicaColors.red,
        label: '지도 그리는 중',
        enabled: false,
        hint: '지도 그리기를 먼저 끝내야 합니다.',
      );
    }
    if (mode.driveOn) {
      return switch (mode.state) {
        ModeState.starting => const _CardState(
            color: VicaColors.primary,
            label: '켜는 중',
            enabled: true,
          ),
        ModeState.stopping => const _CardState(
            color: VicaColors.warning,
            label: '끄는 중',
            enabled: true,
          ),
        ModeState.needInitialPose => const _CardState(
            color: VicaColors.primary,
            label: '켜져 있음 · 초기 위치 대기',
            enabled: true,
          ),
        ModeState.error => const _CardState(
            color: VicaColors.red,
            label: '기동 실패',
            enabled: true,
            hint: '눌러서 확인하세요.',
          ),
        _ => const _CardState(
            color: VicaColors.primary,
            label: '켜져 있음',
            enabled: true,
          ),
      };
    }
    // 칸·터미널에서 띄운 Nav2. 모드 노드가 pane_nodes 를 보내면 그것으로, 아니면 노드 목록으로 봅니다
    // (2026-11-18 B안 — 노드 목록은 강제 종료된 노드를 20 s 남겨 카드가 30 s 늦게 바뀌었습니다).
    if (_nav2Outside(status, mode)) {
      return const _CardState(
        color: VicaColors.primary,
        label: '주행 노드 실행 중',
        enabled: true,
      );
    }
    return const _CardState(
      color: VicaColors.muted,
      label: '꺼져 있음 · 켜는 데 약 40초',
      enabled: true,
    );
  }

  /// 유닛 밖(칸·터미널)에서 뜬 Nav2 가 있는가. 모드 노드가 알려 주면(pane_nodes) 그것을, 아니면 노드 목록을 봅니다.
  static bool _nav2Outside(StackStatus? status, ModeStatus? mode) =>
      mode?.paneNav2 ?? (status?.nav2Running ?? false);

  _CardState _mappingState(StackStatus? status, ModeStatus? mode) {
    if (status != null && status.duplicated) {
      return const _CardState(
        color: VicaColors.red,
        label: '이미 충돌 중',
        enabled: false,
        hint: '동일 노드가 동시에 실행되고 있습니다.',
      );
    }
    // 모드 노드가 켠 주행은 앱에서 끌 수 있습니다. 칸에서 띄운 Nav2 는 아래 예전 판정대로 막습니다.
    if (mode != null && mode.driveOn) {
      return mode.state == ModeState.stopping
          ? const _CardState(
              color: VicaColors.warning,
              label: '주행 끄는 중',
              enabled: false,
              hint: '다 꺼지면 고를 수 있습니다.',
            )
          : const _CardState(
              color: VicaColors.warning,
              label: '주행 켜짐',
              enabled: true,
              hint: '누르면 주행을 끄고 지도로 갑니다.',
            );
    }
    if (status == null) {
      return const _CardState(
        color: VicaColors.muted,
        label: '확인 불가',
        enabled: true,
      );
    }
    if (status.duplicated) {
      return const _CardState(
        color: VicaColors.red,
        label: '이미 충돌 중',
        enabled: false,
        hint: '동일 노드가 동시에 실행되고 있습니다.',
      );
    }
    if (_nav2Outside(status, mode)) {
      return const _CardState(
        color: VicaColors.red,
        label: 'Nav2 실행 중',
        enabled: false,
        hint: 'Nav2를 먼저 내려야 지도를 그릴 수 있습니다.',
      );
    }
    if (status.mappingRunning) {
      return const _CardState(
        color: VicaColors.primary,
        label: '작성 중',
        enabled: true,
      );
    }
    return const _CardState(
      color: VicaColors.green,
      label: '준비됨',
      enabled: true,
    );
  }

  // 주행 카드: 하위 모드를 고른 뒤, 모드 노드가 있으면 주행 묶음을 켜고 준비 화면으로 갑니다.
  Future<void> _onDrive(BuildContext context, ModeStatus? mode) async {
    final choice = await showDriveSubmodeSheet(context, voice: mode?.voiceChoice);
    if (choice == null || !context.mounted) {
      return;
    }
    final (submode, voice) = choice;
    final modes = context.read<AppModeProvider>();
    final supervisor = context.read<SupervisorProvider>();
    // 음성을 바꿨으면 켜기 전에 먼저 알립니다. 꺼져 있으면 젯슨이 다음 기동에 쓰고,
    // 떠 있으면 다시 띄웁니다(사용자 11-16: LOCAL / 외부 API 고르기).
    if (mode != null && voice != null && voice != mode.voiceChoice) {
      final (ok, message) = await supervisor.setVoice(voice);
      if (!context.mounted) {
        return;
      }
      if (!ok) {
        await showVicaNotice(
          context,
          icon: Icons.error_outline,
          iconColor: VicaColors.red,
          title: '음성을 바꾸지 못했습니다',
          body: message,
        );
        return;
      }
    }
    // 모드 노드가 없으면(칸으로 띄우는 방식) 화면만 바꿉니다. 이미 주행 중이어도 그렇습니다.
    if (mode == null || mode.state == ModeState.running) {
      modes.enterDrive(submode);
      return;
    }
    if (!mode.driveOn) {
      final (ok, message) = await supervisor.driveStart();
      if (!context.mounted) {
        return;
      }
      // 칸(터미널)에서 띄운 Nav2 면 모드 노드가 프로세스로 확인해 거절합니다 — 그때는 예전처럼 화면만
      // 바꿉니다. 노드 목록(/rosapi/nodes)으로는 정하지 않습니다: 강제 종료된 노드가 20 s 남아, 주행을
      // 막 끈 뒤 'Nav2 가 떠 있다'고 잘못 말합니다(2026-11-18 측정).
      if (!ok && message.startsWith(kPaneDriveRefusal)) {
        modes.enterDrive(submode);
        return;
      }
      if (!ok) {
        await showVicaNotice(
          context,
          icon: Icons.error_outline,
          iconColor: VicaColors.red,
          title: '주행을 켜지 못했습니다',
          body: message,
        );
        return;
      }
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DriveBringupScreen(submode: submode),
      ),
    );
  }

  // 지도 카드: 모드 노드가 켠 주행이 있으면 끌지 묻고, 다 꺼지면 지도로 갑니다.
  Future<void> _onMapping(BuildContext context, ModeStatus? mode) async {
    final modes = context.read<AppModeProvider>();
    if (mode == null || !mode.driveOn) {
      modes.select(AppMode.mapping);
      return;
    }
    final confirmed = await showVicaConfirm(
      context,
      icon: Icons.map,
      title: '주행을 끄고 지도 그리기로 갈까요?',
      body: 'Nav2·미션·손잡이를 끕니다. 보통 5~15초 걸리고, 다 꺼지면 지도 그리기 화면으로 '
          '갑니다. 로봇이 움직이는 중이면 끌 수 없습니다.',
      confirmLabel: '주행 끄고 지도로',
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    final (ok, message) = await context.read<SupervisorProvider>().driveStop();
    if (!context.mounted) {
      return;
    }
    if (!ok) {
      await showVicaNotice(
        context,
        icon: Icons.error_outline,
        iconColor: VicaColors.red,
        title: '주행을 끄지 못했습니다',
        body: message,
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const DriveBringupScreen(thenMapping: true),
      ),
    );
  }
}

/// 주행 하위 모드 시트(목업 '안 2', 2026-11-16 사용자 채택). 고르지 않고 닫으면 null.
///
/// [voice] 가 있으면(모드 노드가 있을 때) 음성 드롭다운을 함께 보이고(목업 A), 고른 음성을
/// 돌려줍니다. 없으면 음성 칸 없이 하위 모드만 고릅니다.
Future<(DriveSubmode, VoiceChoice?)?> showDriveSubmodeSheet(
  BuildContext context, {
  VoiceChoice? voice,
}) {
  var picked = voice;
  return showModalBottomSheet<(DriveSubmode, VoiceChoice?)>(
    context: context,
    backgroundColor: VicaColors.card,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      return StatefulBuilder(
        // 글자를 키운 좁은 폰에서는 지도 줄까지 더해 화면보다 길어집니다 — 스크롤되게 둡니다(11-17).
        builder: (sheetContext, setSheetState) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 2026-11-17 사용자 지시: '어떤 일을 할까요?' → '주행 모드 선택'.
                const Text(
                  '주행 모드 선택',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: VicaColors.text,
                  ),
                ),
                const SizedBox(height: 4),
                // 2026-11-17 제목·문구 간결화(사용자 승인).
                const Text(
                  '켜는 데 약 40초',
                  style: TextStyle(fontSize: 13, color: VicaColors.muted),
                ),
                const SizedBox(height: 14),
                if (picked != null) ...[
                  // 주행 지도(2026-11-17 목업 ①). 고르면 바로 젯슨에 보냅니다 — 꺼져 있으면 다음 주행부터.
                  const DriveMapRow(),
                  const SizedBox(height: 10),
                  _VoicePicker(
                    value: picked!,
                    onChanged: (choice) => setSheetState(() => picked = choice),
                  ),
                  const SizedBox(height: 10),
                ],
                for (final submode in DriveSubmode.values) ...[
                  _SubmodeButton(
                    submode: submode,
                    onTap: () => Navigator.of(sheetContext).pop((submode, picked)),
                  ),
                  const SizedBox(height: 10),
                ],
                PressScale(child: TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: const Text('닫기'),
                )),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _VoicePicker extends StatelessWidget {
  const _VoicePicker({required this.value, required this.onChanged});

  final VoiceChoice value;
  final ValueChanged<VoiceChoice> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: VicaColors.surfaceSunken,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: VicaColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.mic_none, color: VicaColors.primary, size: 22),
          const SizedBox(width: 12),
          const Expanded(
            // 2026-11-17 사용자: 주행 설정 카드와 같은 이름 '음성 LLM'.
            child: Text(
              '음성 LLM',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: VicaColors.text),
            ),
          ),
          // 폭 상한을 두고 그 안에서 줄인다 — 좁은 폰·큰 글자에서 넘치지 않게(11-16 APK 확인).
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: DropdownButton<VoiceChoice>(
              isExpanded: true,
              alignment: AlignmentDirectional.centerEnd,
              value: value,
              underline: const SizedBox.shrink(),
              borderRadius: BorderRadius.circular(12),
              onChanged: (choice) {
                if (choice != null) {
                  onChanged(choice);
                }
              },
              items: [
                for (final choice in VoiceChoice.values)
                  DropdownMenuItem(
                    value: choice,
                    // 오른쪽에 붙임(2026-11-17 사용자 지시).
                    alignment: AlignmentDirectional.centerEnd,
                    child: Text(
                      choice.label,
                      overflow: TextOverflow.ellipsis,
                      // 글자를 한 단계 줄임(2026-11-17 사용자 지시).
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
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

class _SubmodeButton extends StatelessWidget {
  const _SubmodeButton({required this.submode, required this.onTap});

  final DriveSubmode submode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(child: Material(
      color: VicaColors.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          decoration: BoxDecoration(
            border: Border.all(color: VicaColors.border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: VicaColors.accentTint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(submode.icon, size: 26, color: VicaColors.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      submode.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: VicaColors.text,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      vicaKeepWords(submode.subtitle),
                      style: const TextStyle(fontSize: 12, color: VicaColors.muted),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: VicaColors.muted),
            ],
          ),
        ),
      ),
    ));
  }
}

// 지난 주행 끄기에서 유닛이 시한을 넘겨 강제 종료됐습니다(모드 노드 stop_timeouts).
// 2026-11-16 앞 부팅에서 끄기가 61~72 s 로 굳었고 재부팅으로 풀렸습니다.
class _StopWarningNotice extends StatelessWidget {
  const _StopWarningNotice({required this.units});

  final List<String> units;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF7A4219);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFBEFE6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE9C7AE)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: ink, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '지난 주행 끄기가 늦었습니다',
                  style: TextStyle(fontWeight: FontWeight.w800, color: ink),
                ),
                const SizedBox(height: 4),
                Text(
                  vicaKeepWords(
                    '${units.map(modeUnitLabel).join(', ')} 이(가) 제때 끝나지 않아 강제 종료됐습니다. '
                    '되풀이되면 로봇을 재부팅하세요.',
                  ),
                  style: const TextStyle(fontSize: 12, color: ink, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({required this.mode, required this.state, this.onTap});

  final AppMode mode;
  final _CardState state;

  /// null 이면 눌러도 아무 일도 없습니다(막힌 카드).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = state.enabled;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: PressScale(child: Material(
        color: VicaColors.card,
        // 본문 카드(12)보다 크게 두어 '더 큰 면'으로 읽히게 합니다.
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: enabled ? onTap : null,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              border: Border.all(color: VicaColors.border),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 아이콘만 든 상자는 정원으로 둡니다(2026-09-14 시안). 원은 폭과
                // 높이가 같아야 찌그러지지 않으므로 여백 대신 크기를 고정합니다.
                Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(
                    color: VicaColors.accentTint,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(mode.icon, size: 28, color: VicaColors.primary),
                ),
                const SizedBox(height: 16),
                Text(
                  mode.title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: VicaColors.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  mode.subtitle,
                  style: const TextStyle(
                    color: VicaColors.muted,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: state.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        state.hint.isEmpty
                            ? state.label
                            : '${state.label} · ${state.hint}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: state.color,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (enabled)
                      const Icon(
                        Icons.arrow_forward,
                        size: 18,
                        color: VicaColors.muted,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      )),
    );
  }
}

// 이미 사고가 난 상태입니다. 지금까지는 아무도 알려주지 않았습니다.
class _ConflictNotice extends StatelessWidget {
  const _ConflictNotice({required this.status});

  final StackStatus status;

  @override
  Widget build(BuildContext context) {
    final lines = <String>[
      if (status.conflicting) 'Nav2 와 매핑이 동시에 떠 있습니다.',
      if (status.duplicatedNodeNames.isNotEmpty)
        '같은 노드가 중복으로 떠 있습니다: ${status.duplicatedNodeNames.join(", ")}',
      if (status.odomPublishers.length > 1)
        '/odom 발행자가 ${status.odomPublishers.length}개입니다.',
    ];
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
          const Row(
            children: [
              Icon(Icons.error_outline, color: VicaColors.red, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  '스택이 중복 실행 중입니다',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...lines.map(
            (line) => Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(line, style: const TextStyle(fontSize: 12)),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '이 상태로는 위치추정이 깨집니다. 실행 터미널에서 한쪽을 내린 뒤 '
            '다시 확인해 주세요.',
            style: TextStyle(color: VicaColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// "확인해보니 아무것도 없다"와 "확인을 못 한다"는 다릅니다. 섞으면 잘못된 안심을 줍니다.
class _UnknownNotice extends StatelessWidget {
  const _UnknownNotice();

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
              // 문장 끝에서 줄을 바꾸고(2026-09-14 규칙), 그 안은 어절 단위로
              // 폭에 맞춰 접힙니다. 글자는 그대로입니다.
              vicaKeepWords(vicaBreakAtSentences(
                // 2026-11-17 사용자: 온라인/오프라인 묶음.
                '오프라인 · 상태·중복 실행 확인 불가',
              )),
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
