// 이 파일은 '로봇 끄기'입니다 — 확인 창과 종료 중 화면(2026-11-18 사용자 결정, 목업 '로봇 끄기 A'·
// 확인 창·'끄는 중 → 전원을 꺼도 됩니다', 문구는 추천안).
//
// 누르면 젯슨 모드 노드(/vica/mode/shutdown)가 일회성 유닛으로 주행 묶음 → 기본 묶음 → sync →
// 시스템 종료를 합니다. 모드 노드와 rosbridge 도 내려가므로 앱은 끝까지 지켜볼 수 없습니다.
// 그래서 이 화면은 보이는 사실로만 단계를 그립니다:
//   - 주행 끄기:    모드 상태가 주행 꺼짐이거나 연결이 끊김
//   - 모터·센서 끄기: 연결이 끊김(rosbridge 도 기본 묶음이라 마지막 쪽에 내려간다)
//   - 시스템 종료:   연결이 끊긴 뒤 30초 — 앱은 젯슨이 다 꺼졌는지 직접 알 수 없다
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/supervisor_provider.dart';
import '../ros/ros_bridge_client.dart';
import '../widgets/vica_ui.dart';

/// 연결이 끊긴 뒤 '전원을 꺼도 됩니다'까지 기다리는 시간. 젯슨 시스템 종료는 보통 이 안에 끝난다.
const Duration kShutdownSettle = Duration(seconds: 30);

/// 확인 창 → 로봇 끄기 요청 → 종료 중 화면. 거절되면(움직이는 중 등) 이유를 띄웁니다.
Future<void> confirmAndShutdownRobot(BuildContext context) async {
  final confirmed = await showVicaConfirm(
    context,
    icon: Icons.power_settings_new,
    iconColor: VicaColors.red,
    title: '로봇을 끌까요?',
    body: '모든 기능을 끄고 시스템을 종료합니다.\n'
        '다시 쓰려면 전원을 껐다 켜세요. 움직이는 중에는 끌 수 없습니다.',
    confirmLabel: '로봇 끄기',
    danger: true,
  );
  if (!confirmed || !context.mounted) {
    return;
  }
  final (ok, message) = await context.read<SupervisorProvider>().robotShutdown();
  if (!context.mounted) {
    return;
  }
  if (!ok) {
    await showVicaNotice(
      context,
      icon: Icons.error_outline,
      iconColor: VicaColors.red,
      title: '로봇을 끄지 못했습니다',
      body: message,
    );
    return;
  }
  await Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const RobotShutdownScreen()),
  );
}

class RobotShutdownScreen extends StatefulWidget {
  const RobotShutdownScreen({super.key, this.now});

  /// 시험용 시계. 없으면 DateTime.now.
  final DateTime Function()? now;

  @override
  State<RobotShutdownScreen> createState() => _RobotShutdownScreenState();
}

class _RobotShutdownScreenState extends State<RobotShutdownScreen> {
  late final DateTime _openedAt = _now();
  DateTime? _lostAt;
  Timer? _ticker;

  DateTime _now() => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    // 걸린 초와 30초 기다림을 1 s 마다 다시 그립니다.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final supervisor = context.watch<SupervisorProvider>();
    final connected = supervisor.connectionState == RosConnectionState.connected;
    if (!connected) {
      _lostAt ??= _now();
    }
    final driveOff = !connected || !(supervisor.modeStatus?.driveOn ?? false);
    final lostFor = _lostAt == null ? null : _now().difference(_lostAt!);
    final done = lostFor != null && lostFor >= kShutdownSettle;

    _StepState stateOf({required bool finished, required bool started}) =>
        finished ? _StepState.done : (started ? _StepState.current : _StepState.todo);

    return Scaffold(
      appBar: AppBar(title: const Text('로봇 끄기')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          children: [
            VicaCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '종료 중',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      if (!done)
                        Text(
                          '${_now().difference(_openedAt).inSeconds}초',
                          style: const TextStyle(fontSize: 12, color: VicaColors.muted),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _StepRow(
                    label: '주행 끄기',
                    state: stateOf(finished: driveOff, started: true),
                  ),
                  _StepRow(
                    label: '모터·센서 끄기',
                    state: stateOf(finished: !connected, started: driveOff),
                  ),
                  _StepRow(
                    label: '시스템 종료',
                    hint: '연결이 끊기고 30초 뒤 완료',
                    state: stateOf(finished: done, started: !connected),
                  ),
                ],
              ),
            ),
            if (done) ...[
              const SizedBox(height: 14),
              const _DoneCard(),
            ],
          ],
        ),
      ),
    );
  }
}

enum _StepState { done, current, todo }

class _StepRow extends StatelessWidget {
  const _StepRow({required this.label, required this.state, this.hint = ''});

  final String label;
  final _StepState state;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final Widget mark = switch (state) {
      _StepState.done => const CircleAvatar(
          radius: 10,
          backgroundColor: VicaColors.primary,
          child: Icon(Icons.check, size: 14, color: Colors.white),
        ),
      _StepState.current => const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      _StepState.todo => Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: VicaColors.border, width: 2),
          ),
        ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          mark,
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                text: label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: state == _StepState.current ? FontWeight.w700 : FontWeight.w500,
                  color: state == _StepState.todo ? VicaColors.muted : VicaColors.text,
                ),
                children: [
                  if (hint.isNotEmpty && state == _StepState.current)
                    TextSpan(
                      text: '  $hint',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: VicaColors.muted),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DoneCard extends StatelessWidget {
  const _DoneCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2EC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: VicaColors.green, width: 2),
      ),
      child: const Column(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: VicaColors.green,
            child: Icon(Icons.check, size: 28, color: Colors.white),
          ),
          SizedBox(height: 8),
          Text(
            '전원을 꺼도 됩니다',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF2F5A3C)),
          ),
          SizedBox(height: 4),
          Text('종료가 끝났습니다.', style: TextStyle(fontSize: 13, color: Color(0xFF3B6E4A))),
        ],
      ),
    );
  }
}
