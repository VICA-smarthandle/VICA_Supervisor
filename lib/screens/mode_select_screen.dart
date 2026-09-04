// 이 파일은 로그인 직후 어떤 일을 하러 왔는지 고르는 화면입니다.
//
// 화면을 고르는 것일 뿐이지만, 여기서 젯슨의 스택 상태를 함께 보여줍니다.
// 중복 실행이 이 프로젝트에서 실제로 회차를 날린 사고이고(2026-08-11 20:07),
// 지금까지는 그 상태가 되어도 아무도 알려주지 않았기 때문입니다.
//
// 연결이 안 돼 있어도 들어갈 수 있게 둡니다. 모드 전환은 앱 화면만 바꾸는 일이라
// 막아서 얻는 안전이 없고, 막으면 연결이 안 되는 상황에서 사람이 갇힙니다.
// 대신 "확인 불가"임을 숨기지 않습니다.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_mode.dart';
import '../core/layout_breakpoints.dart';
import '../models/stack_status.dart';
import '../providers/app_mode_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/supervisor_provider.dart';
import 'settings_screen.dart';
import '../ros/ros_bridge_client.dart';
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
  }

  @override
  Widget build(BuildContext context) {
    final supervisor = context.watch<SupervisorProvider>();
    final connected =
        supervisor.connectionState == RosConnectionState.connected;
    final status = supervisor.stackStatus;
    final username = context.watch<AuthProvider>().currentUsername ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('모드를 선택해주세요'),
        actions: [
          IconButton(
            onPressed: supervisor.stackStatusLoading
                ? null
                : () => supervisor.refreshStackStatus(),
            icon: const Icon(Icons.refresh),
            tooltip: '로봇 상태 다시 확인',
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
          title: '$username 님, 모드를 선택해주세요',
          children: [
            const VicaRosConnectionTile(),
            if (status != null && (status.duplicated || status.conflicting))
              _ConflictNotice(status: status),
            if (!connected) const _UnknownNotice(),
            const SizedBox(height: 4),
            LayoutBuilder(
              builder: (context, constraints) {
                final cards = [
                  _ModeCard(
                    mode: AppMode.drive,
                    state: _driveState(status),
                  ),
                  _ModeCard(
                    mode: AppMode.mapping,
                    state: _mappingState(status),
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
  _CardState _driveState(StackStatus? status) {
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

  _CardState _mappingState(StackStatus? status) {
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
    if (status.nav2Running) {
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
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({required this.mode, required this.state});

  final AppMode mode;
  final _CardState state;

  @override
  Widget build(BuildContext context) {
    final enabled = state.enabled;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Material(
        color: VicaColors.card,
        // 본문 카드(12)보다 크게 두어 '더 큰 면'으로 읽히게 합니다.
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: enabled
              ? () => context.read<AppModeProvider>().select(mode)
              : null,
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
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: VicaColors.softBlue,
                    borderRadius: BorderRadius.circular(12),
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
      ),
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
              'ROS 에 연결하지 않아 로봇 상태를 확인할 수 없습니다. '
              '모드 선택은 가능하지만 중복 실행 여부는 확인되지 않은 상태입니다.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
