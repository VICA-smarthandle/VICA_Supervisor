import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/mic_check.dart';
import '../vica_ui.dart';

/// 점검기에 명령을 보내는 함수. 끊겨 보내지 못하면 화면이 스낵으로 알립니다.
typedef MicSend = void Function(String cmd, [Map<String, Object?> args]);

/// 6단계에서 로봇이 혼자 말하는 시간. 점검기는 남은 초를 보내지 않아 앱이 이 값에서 1 s 씩 셉니다.
const kMicRobotSeconds = 30;

class MicStepCard extends StatefulWidget {
  const MicStepCard({
    super.key,
    required this.status,
    required this.frame,
    required this.busy,
    required this.onSend,
  });

  final MicCheckStatus status;
  final MicCheckFrame? frame;
  final String? busy;
  final MicSend onSend;

  @override
  State<MicStepCard> createState() => _MicStepCardState();
}

class _MicStepCardState extends State<MicStepCard> {
  Timer? _timer;
  int _robotLeft = kMicRobotSeconds;

  @override
  void initState() {
    super.initState();
    _syncTimer(false);
  }

  @override
  void didUpdateWidget(MicStepCard old) {
    super.didUpdateWidget(old);
    _syncTimer(old.status.step.robot);
  }

  void _syncTimer(bool wasRobot) {
    final robot = widget.status.step.robot;
    if (robot && !wasRobot) {
      _robotLeft = kMicRobotSeconds;
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_robotLeft > 0) setState(() => _robotLeft--);
      });
    } else if (!robot) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.status.step;
    final chipOk = widget.status.chipOk;
    final recLeft = widget.frame?.recLeft;
    final recording = recLeft != null;

    return VicaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${st.no} / ${st.of} · ${st.name}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
              if (st.reps > 0)
                Text('${st.rep}/${st.reps}회',
                    style: const TextStyle(
                        color: VicaColors.muted, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          if (st.say.isNotEmpty)
            Text(st.say,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700, height: 1.4)),
          const SizedBox(height: 14),
          if (st.key == 'result')
            const _Note('점검이 끝났습니다', '아래 결과표를 보고 필요하면 값을 고치세요')
          else if (st.robot)
            _Progress(
                '로봇 말하는 중 · $_robotLeft초 남음', _robotLeft / kMicRobotSeconds)
          else if (st.key == 'robot')
            FilledButton(
              key: const ValueKey('mic_check_robot'),
              onPressed:
                  chipOk && !recording ? () => widget.onSend('robot') : null,
              child: const Text('로봇 말하기'),
            )
          else ...[
            if (recording)
              _Progress('녹음 중 · ${recLeft.toStringAsFixed(1)}초 남음',
                  st.seconds > 0 ? (recLeft / st.seconds).clamp(0.0, 1.0) : 0),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('mic_check_record'),
                    onPressed: chipOk && !recording
                        ? () => widget.onSend('record')
                        : null,
                    child: const Text('녹음 시작'),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  key: const ValueKey('mic_check_redo'),
                  style:
                      OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
                  onPressed: chipOk && !recording
                      ? () => widget.onSend('redo', {'step': st.key})
                      : null,
                  child: const Text('다시'),
                ),
              ],
            ),
            if (st.seconds > 0 && !recording) ...[
              const SizedBox(height: 8),
              Text('녹음 ${_sec(st.seconds)}초',
                  style:
                      const TextStyle(fontSize: 12, color: VicaColors.muted)),
            ],
          ],
          if (widget.busy != null) ...[
            const SizedBox(height: 10),
            Text(widget.busy!,
                style:
                    const TextStyle(fontSize: 13, color: VicaColors.warning)),
          ],
        ],
      ),
    );
  }

  static String _sec(double s) =>
      s == s.roundToDouble() ? s.toInt().toString() : s.toString();
}

class _Progress extends StatelessWidget {
  const _Progress(this.text, this.fraction);
  final String text;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(text,
              style: const TextStyle(
                  fontWeight: FontWeight.w800, color: VicaColors.primaryDark)),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 8,
              color: VicaColors.primary,
              backgroundColor: VicaColors.surfaceSunken,
            ),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.title, this.body);
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(body, style: const TextStyle(color: VicaColors.muted)),
      ],
    );
  }
}
