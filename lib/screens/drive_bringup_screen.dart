// 이 파일은 주행 묶음(Nav2·미션·손잡이·감시·위치 확인)이 켜지고 꺼지는 동안 보는 화면입니다.
//
// 2026-11-16 목업 ②~⑤·⑥(https://claude.ai/artifact/6mjrRCwgM71mNV3WaWJQgt). 젯슨의 모드
// 노드가 2 s 마다 내는 /vica/mode_status 만 보고 그립니다 — 앱이 상태를 따로 쥐지 않습니다.
// 그래서 이 화면을 닫았다 다시 열어도, 다른 기기에서 열어도 같은 것을 봅니다.
//
// 이 화면이 하는 일은 셋입니다.
//   - 켜는 중: 단계 표시. 끄기를 누르면 모드 노드가 다 뜬 뒤로 예약합니다(뜨는 도중에 끄면
//     노드가 강제 종료되기 쉽다 — 11-16 실기). 예약 중 '주행 계속'은 예약 취소입니다.
//   - 초기 위치 대기: 원격 주행 탭의 초기 위치 카드로 보냅니다(그 카드는 그대로 씁니다).
//   - 지도로 바꾸기([thenMapping]): 다 꺼지면 지도 모드로 들어갑니다.
//   - 주행 끄기([stopOnly], 2026-11-17 대시보드 버튼): 다 꺼지면 모드 선택으로 돌아갑니다.
//   - 주행 지도 바꾸기([mapChange], 2026-11-17 목업 ⑤): 젯슨이 Nav2·미션·음성을 다시 띄우는 동안
//     진행을 보이고, 초기 위치 대기에 이르면 원격 주행 탭으로 보냅니다.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_mode.dart';
import '../models/mode_status.dart';
import '../providers/app_mode_provider.dart';
import '../providers/supervisor_provider.dart';
import '../widgets/vica_ui.dart';

class DriveBringupScreen extends StatefulWidget {
  const DriveBringupScreen({
    super.key,
    this.submode = DriveSubmode.guideDelivery,
    this.thenMapping = false,
    this.stopOnly = false,
    this.mapChange,
  });

  /// 다 켜진 뒤 처음 열 화면을 정합니다.
  final DriveSubmode submode;

  /// true 면 주행을 끄는 중이고, 다 꺼지면 지도 모드로 들어갑니다.
  final bool thenMapping;

  /// true 면 주행을 끄는 중이고(대시보드 '주행 끄기'), 다 꺼지면 모드 선택으로 돌아갑니다.
  /// 끄기 요청은 연 쪽이 이미 보냈습니다.
  final bool stopOnly;

  /// 주행 지도를 바꾸는 중이면 (바꾸기 전 이름, 바꾼 이름).
  final (String, String)? mapChange;

  @override
  State<DriveBringupScreen> createState() => _DriveBringupScreenState();
}

class _DriveBringupScreenState extends State<DriveBringupScreen> {
  final DateTime _openedAt = DateTime.now();
  Timer? _ticker;
  bool _busy = false;
  bool _left = false;

  /// 이 화면에서 끄기를 눌렀는가. 꺼지면(idle) 모드 선택으로 돌아갑니다.
  late bool _stopRequested = widget.thenMapping || widget.stopOnly;

  /// 지도 바꾸기: 유닛이 내려간 것을 봤는가. 요청 직후 상태가 아직 running 일 수 있어, 그 사이에
  /// 화면을 닫지 않게 합니다(젯슨이 2 s 마다 상태를 냄).
  bool _sawRestart = false;

  @override
  void initState() {
    super.initState();
    // 걸린 초를 1 s 마다 다시 그립니다. 상태 자체는 모드 노드가 2 s 마다 줍니다.
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

  /// 서비스를 부르고, 거부되면 [onRefused] 로 화면 표시를 되돌린 뒤 이유를 띄웁니다.
  Future<void> _run(
    Future<(bool, String)> Function() call, {
    VoidCallback? onRefused,
  }) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    final (ok, message) = await call();
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      if (!ok) {
        onRefused?.call();
      }
    });
    if (!ok) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  // 끄기. 거부되면(움직이는 중 등) '끄는 중'으로 남지 않게 되돌립니다.
  void _stop(SupervisorProvider supervisor) {
    setState(() => _stopRequested = true);
    _run(supervisor.driveStop, onRefused: () => _stopRequested = false);
  }

  bool _nav2Failed(ModeStatus status) =>
      status.nav2 == 'aborted' || status.nav2 == 'stalled';

  // 이 화면을 닫고 다음 화면으로. build 중에 부르면 안 되므로 프레임 뒤로 미룹니다.
  void _leave(void Function(AppModeProvider modes) then) {
    if (_left) {
      return;
    }
    _left = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final modes = context.read<AppModeProvider>();
      Navigator.of(context).pop();
      then(modes);
    });
  }

  @override
  Widget build(BuildContext context) {
    final supervisor = context.watch<SupervisorProvider>();
    final status = supervisor.modeStatus;

    if (status != null) {
      if (status.mode == 'idle' && _stopRequested) {
        _leave((modes) {
          if (widget.thenMapping) {
            modes.select(AppMode.mapping);
          } else if (widget.stopOnly) {
            modes.clear();
          }
        });
      } else if (status.state == ModeState.running && !_stopRequested && _restartSeen()) {
        _leave((modes) => modes.enterDrive(widget.submode));
      }
      if (status.state != ModeState.running) {
        _sawRestart = true;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.thenMapping
            ? '지도로 바꾸기'
            : widget.stopOnly
                ? '주행 끄기'
                : (widget.mapChange != null ? '지도 바꾸는 중' : '주행 시작')),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ListView(
                  children: _content(status),
                ),
              ),
              ..._actions(status),
            ],
          ),
        ),
      ),
    );
  }

  int get _elapsed => DateTime.now().difference(_openedAt).inSeconds;

  // 지도 바꾸기가 아니면 바로, 맞으면 유닛이 내려간 것을 본 뒤(늦어도 10 s 뒤)에 running 을 믿습니다.
  bool _restartSeen() => widget.mapChange == null || _sawRestart || _elapsed > 10;

  List<Widget> _content(ModeStatus? status) {
    if (status == null) {
      return const [
        _Banner(
          tone: _Tone.info,
          icon: Icons.help_outline,
          title: '주행 상태를 받지 못했습니다',
          body: '연결을 확인해 주세요.',
        ),
      ];
    }
    if (_stopRequested || status.state == ModeState.stopping) {
      if (status.stopPending) {
        return [
          _Banner(
            tone: _Tone.warning,
            icon: Icons.schedule,
            title: '끄기 예약',
            body: '준비가 끝나면 바로 끕니다(늦어도 ${status.stopInSec}초).',
          ),
          const SizedBox(height: 14),
          _StepsCard(title: '주행 준비 중', elapsed: _elapsed, steps: _steps(status, pendingStop: true)),
        ];
      }
      return [
        _StepsCard(
          title: '주행 끄는 중',
          elapsed: _elapsed,
          steps: [
            const _Step('주행 끄기', _StepState.current, 'Nav2·미션·스마트핸들·음성'),
            if (widget.thenMapping)
              const _Step('지도 그리기로', _StepState.todo, '다 꺼지면 넘어갑니다'),
            if (widget.stopOnly)
              const _Step('모드 선택으로', _StepState.todo, '다 꺼지면 돌아갑니다'),
          ],
          note: status.detail.isEmpty ? '5~15초 걸립니다.' : status.detail,
        ),
      ];
    }
    if (status.state == ModeState.error) {
      return [
        _Banner(
          tone: _Tone.danger,
          icon: Icons.error_outline,
          title: _nav2Failed(status) ? 'Nav2 시작 실패' : '주행 기능 오류',
          body: status.detail,
        ),
        const SizedBox(height: 14),
        // Nav2 다시 띄우기는 Nav2 만 다시 띄웁니다. 다른 유닛(미션 등)이 원인이면 소용없습니다.
        _HintCard(
          lines: _nav2Failed(status)
              ? const [
                  "'Nav2 다시 시작'을 누르세요.",
                  '안 되면 주행을 끄고 재부팅하세요.',
                ]
              : const [
                  '주행을 끄고 다시 켜세요.',
                  '안 되면 재부팅하세요.',
                ],
        ),
      ];
    }
    final ready = status.state == ModeState.needInitialPose;
    final change = widget.mapChange;
    if (change != null) {
      return [
        _MapFromTo(from: change.$1, to: change.$2),
        const SizedBox(height: 14),
        _StepsCard(
          title: ready ? '초기 위치를 잡아 주세요' : '지도 바꾸는 중',
          elapsed: ready ? null : _elapsed,
          steps: _mapSteps(status),
          note: '로봇은 움직이지 않음 · 약 1분',
        ),
      ];
    }
    return [
      _SubmodeChip(submode: widget.submode),
      const SizedBox(height: 14),
      _StepsCard(
        title: ready ? '초기 위치를 잡아 주세요' : '주행 준비 중',
        elapsed: ready ? null : _elapsed,
        steps: _steps(status),
        note: ready
            ? '위치를 잡으면 바로 주행할 수 있습니다.'
            : '90초 안에 준비되지 않으면 한 번 자동으로 다시 시작합니다.',
      ),
    ];
  }

  // 지도 바꾸기 단계(목업 ⑤). 파일은 요청 때 이미 썼습니다.
  List<_Step> _mapSteps(ModeStatus status) {
    final nav2Up = (status.nav2 == 'waiting_pose' || status.nav2 == 'active') && _sawRestart;
    final voiceUp = status.voice == 'active' && _sawRestart;
    return [
      const _Step('지도 기록', _StepState.done, ''),
      _Step('Nav2·미션 켜기', nav2Up ? _StepState.done : _StepState.current, ''),
      if (status.voice != 'none')
        _Step('음성 켜기', voiceUp ? _StepState.done : _StepState.current, ''),
      _Step(
        '초기 위치',
        status.state == ModeState.running && _sawRestart
            ? _StepState.done
            : (nav2Up ? _StepState.current : _StepState.todo),
        '',
      ),
    ];
  }

  List<_Step> _steps(ModeStatus status, {bool pendingStop = false}) {
    final nav2Up = status.nav2 == 'waiting_pose' || status.nav2 == 'active';
    return [
      _Step(
        '주행 켜기',
        status.driveOn ? _StepState.done : _StepState.current,
        'Nav2·미션·스마트핸들·음성',
      ),
      _Step(
        nav2Up ? 'Nav2 준비 완료' : 'Nav2 준비',
        nav2Up ? _StepState.done : _StepState.current,
        nav2Up ? '' : '15~40초',
      ),
      if (pendingStop)
        const _Step('끄기 (예약)', _StepState.todo, '')
      else
        _Step(
          '초기 위치 잡기',
          status.state == ModeState.running
              ? _StepState.done
              : (nav2Up ? _StepState.current : _StepState.todo),
          '',
        ),
    ];
  }

  List<Widget> _actions(ModeStatus? status) {
    final supervisor = context.read<SupervisorProvider>();
    if (status == null) {
      return const [];
    }
    if (status.stopPending) {
      return [
        PressScale(child: FilledButton(
          onPressed: _busy
              ? null
              : () {
                  // 모드 노드는 예약 중 켜기 요청을 '예약 취소'로 받습니다.
                  setState(() => _stopRequested = false);
                  _run(supervisor.driveStart, onRefused: () => _stopRequested = true);
                },
          child: const Text('끄기 취소'),
        )),
      ];
    }
    if (_stopRequested || status.state == ModeState.stopping) {
      return const [];
    }
    final stopButton = PressScale(child: OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: VicaColors.red,
        side: const BorderSide(color: VicaColors.red),
        minimumSize: const Size.fromHeight(46),
      ),
      onPressed: _busy ? null : () => _stop(supervisor),
      child: const Text('주행 끄기'),
    ));
    if (status.state == ModeState.error) {
      return [
        if (_nav2Failed(status)) ...[
          PressScale(child: FilledButton(
            onPressed: _busy ? null : () => _run(supervisor.nav2Restart),
            child: const Text('Nav2 다시 시작'),
          )),
          const SizedBox(height: 10),
        ],
        stopButton,
      ];
    }
    if (status.state == ModeState.needInitialPose) {
      return [
        PressScale(child: FilledButton(
          // 초기 위치 카드는 원격 주행 탭에 있습니다. 그 탭으로 들어갑니다.
          onPressed: () => _leave(
            (modes) => modes.enterDrive(widget.submode, landingTab: '원격 주행'),
          ),
          child: const Text('초기 위치 잡기'),
        )),
        const SizedBox(height: 10),
        stopButton,
      ];
    }
    return [stopButton];
  }
}

enum _StepState { done, current, todo }

class _Step {
  const _Step(this.label, this.state, this.hint);

  final String label;
  final _StepState state;
  final String hint;
}

class _MapFromTo extends StatelessWidget {
  const _MapFromTo({required this.from, required this.to});

  final String from;
  final String to;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: VicaColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: VicaColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '주행 지도',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: VicaColors.muted),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Flexible(
                child: Text(
                  from,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: VicaColors.textTertiary,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Icon(Icons.arrow_forward, size: 20, color: VicaColors.primary),
              ),
              Flexible(
                child: Text(
                  to,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: VicaColors.text),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepsCard extends StatelessWidget {
  const _StepsCard({
    required this.title,
    required this.steps,
    this.elapsed,
    this.note = '',
  });

  final String title;
  final List<_Step> steps;
  final int? elapsed;
  final String note;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: VicaColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: VicaColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: VicaColors.text,
                  ),
                ),
              ),
              if (elapsed != null)
                Text(
                  '$elapsed초',
                  style: const TextStyle(color: VicaColors.muted, fontSize: 13),
                ),
            ],
          ),
          const SizedBox(height: 16),
          for (final step in steps) ...[
            _StepRow(step: step),
            const SizedBox(height: 14),
          ],
          if (note.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: VicaColors.surfaceSunken,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                vicaKeepWords(note),
                style: const TextStyle(fontSize: 12, color: VicaColors.muted, height: 1.5),
              ),
            ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step});

  final _Step step;

  @override
  Widget build(BuildContext context) {
    final Widget mark = switch (step.state) {
      _StepState.done => Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(color: VicaColors.green, shape: BoxShape.circle),
          child: const Icon(Icons.check, size: 15, color: Colors.white),
        ),
      _StepState.current => Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: VicaColors.primary, width: 3),
          ),
        ),
      _StepState.todo => Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: VicaColors.borderStrong, width: 2),
          ),
        ),
    };
    final color = switch (step.state) {
      _StepState.done => VicaColors.text,
      _StepState.current => VicaColors.primary,
      _StepState.todo => VicaColors.muted,
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        mark,
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                step.label,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: color),
              ),
              if (step.hint.isNotEmpty)
                Text(step.hint, style: const TextStyle(fontSize: 12, color: VicaColors.muted)),
            ],
          ),
        ),
      ],
    );
  }
}

class _SubmodeChip extends StatelessWidget {
  const _SubmodeChip({required this.submode});

  final DriveSubmode submode;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: VicaColors.accentTint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(submode.icon, size: 20, color: VicaColors.primaryDark),
          const SizedBox(width: 10),
          Text(
            '${submode.title} 모드',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: VicaColors.primaryDark,
            ),
          ),
        ],
      ),
    );
  }
}

enum _Tone { info, warning, danger }

class _Banner extends StatelessWidget {
  const _Banner({
    required this.tone,
    required this.icon,
    required this.title,
    required this.body,
  });

  final _Tone tone;
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    // 배경은 옅게, 글자는 4.5:1 넘게 진하게(목업과 같은 값).
    final (background, border, ink) = switch (tone) {
      _Tone.info => (VicaColors.accentTint, VicaColors.border, VicaColors.text),
      _Tone.warning => (const Color(0xFFFBF3E6), const Color(0xFFE8D2AE), const Color(0xFF6B4A15)),
      _Tone.danger => (const Color(0xFFF8E9E6), const Color(0xFFE5BDB6), const Color(0xFF8A3529)),
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: ink, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ink)),
                if (body.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    vicaKeepWords(body),
                    style: TextStyle(fontSize: 13, color: ink, height: 1.5),
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

class _HintCard extends StatelessWidget {
  const _HintCard({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: VicaColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: VicaColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '이렇게 해 보세요',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: VicaColors.text),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < lines.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '${i + 1}. ${vicaKeepWords(lines[i])}',
                style: const TextStyle(fontSize: 14, color: VicaColors.text, height: 1.5),
              ),
            ),
        ],
      ),
    );
  }
}
