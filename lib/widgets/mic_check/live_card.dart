// 이 파일은 마이크 점검 화면의 '실시간' 카드(캔버스 108)를 그립니다.
// 소리 크기(로그 눈금)·"비카야" 점수·"멈춰" 점수 막대와 잡음 바닥을 보여 줍니다.
// 계산은 옛 점검 페이지(logPos·SPEAKING_STOP 0.35)와 같습니다.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/mic_check.dart';
import '../vica_ui.dart';

/// 소리 크기 막대의 로그 눈금 위치(0~1). 0.001 → 0, 1 → 1.
double micLogPos(double v) => ((math.log(math.max(v, 1e-4)) / math.ln10 + 3) / 3).clamp(0.0, 1.0);

/// 점수 막대(0~1 선형)의 위치.
double micLinPos(double v) => v.clamp(0.0, 1.0);

/// 로봇이 말하는 중 "멈춰" 에 쓰는 낮은 문턱.
const kMicSpeakingStop = 0.35;

double? _num(MicCheckStatus s, String k) {
  final v = s.values[k];
  return v is num ? v.toDouble() : null;
}

/// "비카야"·"멈춰" 상태 글자('걸림')를 붙잡아 두는 시간(옛 점검 페이지의 1.5 s 피크 유지).
const kMicPeakHold = Duration(milliseconds: 1500);

class MicLiveCard extends StatefulWidget {
  const MicLiveCard({super.key, required this.status, required this.frame, this.now = DateTime.now});

  final MicCheckStatus status;
  final MicCheckFrame? frame;

  /// 시험이 시계를 대신 줍니다.
  final DateTime Function() now;

  @override
  State<MicLiveCard> createState() => _MicLiveCardState();
}

class _MicLiveCardState extends State<MicLiveCard> {
  DateTime? _wakeOverAt;
  DateTime? _stopOverAt;
  MicCheckFrame? _seen;

  static bool _stopOver(MicCheckFrame f, double? th) =>
      (th != null && f.stop >= th) || (f.robot && f.stop >= kMicSpeakingStop);

  bool _held(DateTime? at, DateTime t) => at != null && t.difference(at) <= kMicPeakHold;

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    final f = widget.frame;
    final listen = _num(status, 'listen_min_rms');
    final short = _num(status, 'short_answer_min_rms');
    final wakeTh = _num(status, 'wake_threshold');
    final stopTh = _num(status, 'emergency_single');

    // 문턱을 넘은 프레임의 시각을 기억해 1.5 s 동안 '걸림' 을 유지합니다. 막대 채움은 순간값 그대로입니다.
    final t = widget.now();
    if (f != null && !identical(f, _seen)) {
      _seen = f;
      if (wakeTh != null && f.wake >= wakeTh) _wakeOverAt = t;
      if (_stopOver(f, stopTh)) _stopOverAt = t;
    }
    final wakeHeld = f != null && _held(_wakeOverAt, t);
    final stopHeld = f != null && _held(_stopOverAt, t);

    return VicaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('실시간', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
              Wrap(
                spacing: 6,
                children: [
                  if (f?.robot == true) const _Chip('로봇 말하는 중', VicaColors.warning),
                  _Chip('칩 사람 말', f?.vad == true ? VicaColors.primaryDark : VicaColors.textTertiary),
                  _Chip(f?.muted == true ? '마이크 닫힘' : '마이크 열림', VicaColors.muted),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Meter(
            label: '소리 크기',
            value: f?.rms,
            valueText: f?.rms.toStringAsFixed(4),
            state: f == null ? null : (listen != null && f.rms >= listen ? '수음 넘음' : '아래'),
            over: f != null && listen != null && f.rms >= listen,
            pos: micLogPos,
            lines: [
              if (listen != null) _Line(listen, '수음'),
              if (short != null) _Line(short, '짧은 답', color: VicaColors.warning),
            ],
            edge: const [_Tick(0.001, '0.001'), _Tick(0.1, '0.1'), _Tick(1, '1')],
          ),
          const SizedBox(height: 10),
          _NoiseRow(noise: f?.noise, listen: listen),
          const SizedBox(height: 14),
          _Meter(
            label: '“비카야”',
            value: f?.wake,
            valueText: f?.wake.toStringAsFixed(2),
            state: f == null ? null : (wakeHeld ? '걸림' : '아래'),
            over: f != null && wakeTh != null && f.wake >= wakeTh,
            pos: micLinPos,
            lines: [if (wakeTh != null) _Line(wakeTh, '문턱 ${wakeTh.toStringAsFixed(2)}')],
            edge: const [_Tick(0, '0'), _Tick(1, '1')],
          ),
          const SizedBox(height: 14),
          _Meter(
            label: '“멈춰”',
            value: f?.stop,
            valueText: f?.stop.toStringAsFixed(2),
            state: f == null ? null : (stopHeld ? '걸림' : '아래'),
            over: f != null && _stopOver(f, stopTh),
            pos: micLinPos,
            lines: [
              if (stopTh != null) _Line(stopTh, '문턱 ${stopTh.toStringAsFixed(2)}'),
              if (f?.robot == true) const _Line(kMicSpeakingStop, '0.35', dashed: true),
            ],
            edge: const [_Tick(0, '0'), _Tick(1, '1')],
          ),
        ],
      ),
    );
  }

}

class _Chip extends StatelessWidget {
  const _Chip(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
      );
}

class _NoiseRow extends StatelessWidget {
  const _NoiseRow({required this.noise, required this.listen});
  final double? noise;
  final double? listen;

  @override
  Widget build(BuildContext context) {
    final n = noise;
    final String chip;
    final Color color;
    if (n == null) {
      chip = '10초 모으는 중';
      color = VicaColors.muted;
    } else {
      final r = listen == null ? 99.0 : listen! / n;
      chip = r >= 2 ? '조용함' : '수음 최소까지 ${r.toStringAsFixed(1)}배';
      color = r >= 2 ? VicaColors.green : (r >= 1.3 ? VicaColors.warning : VicaColors.red);
    }
    return Row(
      children: [
        const Text('잡음 바닥', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(width: 8),
        Text(n == null ? '재는 중' : n.toStringAsFixed(4), style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 8),
        _Chip(chip, color),
      ],
    );
  }
}

class _Line {
  const _Line(this.at, this.label, {this.color = VicaColors.text, this.dashed = false});
  final double at;
  final String label;
  final Color color;
  final bool dashed;
}

class _Tick {
  const _Tick(this.at, this.label);
  final double at;
  final String label;
}

class _Meter extends StatelessWidget {
  const _Meter({
    required this.label,
    required this.value,
    required this.valueText,
    required this.state,
    required this.over,
    required this.pos,
    required this.lines,
    required this.edge,
  });

  final String label;
  final double? value;
  final String? valueText;
  final String? state;
  final bool over;
  final double Function(double) pos;
  final List<_Line> lines;
  final List<_Tick> edge;

  @override
  Widget build(BuildContext context) {
    final stateColor = over ? VicaColors.green : VicaColors.muted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            Text.rich(TextSpan(
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              children: [
                if (state != null) TextSpan(text: state, style: TextStyle(color: stateColor)),
                TextSpan(text: ' · ${valueText ?? '-'}'),
              ],
            )),
          ],
        ),
        const SizedBox(height: 6),
        LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth;
          return SizedBox(
            height: 14 + 18,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0, right: 0, top: 0, height: 14,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: Stack(children: [
                      Container(color: VicaColors.border),
                      FractionallySizedBox(
                        widthFactor: value == null ? 0 : pos(value!),
                        child: Container(color: over ? VicaColors.green : VicaColors.primary),
                      ),
                    ]),
                  ),
                ),
                for (final l in lines)
                  Positioned(
                    left: (pos(l.at) * w - 1).clamp(0.0, w - 2),
                    top: -3,
                    height: 20,
                    width: 2,
                    child: ColoredBox(color: l.dashed ? VicaColors.red : l.color),
                  ),
                for (final l in lines)
                  Positioned(
                    left: pos(l.at) * w,
                    top: 17,
                    child: FractionalTranslation(
                      translation: const Offset(-0.5, 0),
                      child: Text(l.label, style: const TextStyle(fontSize: 10, color: VicaColors.muted)),
                    ),
                  ),
                for (final t in edge)
                  Positioned(
                    left: pos(t.at) * w,
                    top: 17,
                    child: FractionalTranslation(
                      // 양 끝 눈금은 막대 안쪽으로 붙이고, 가운데 눈금은 가운데 정렬.
                      translation: Offset(pos(t.at) <= 0 ? 0 : (pos(t.at) >= 1 ? -1 : -0.5), 0),
                      child: Text(t.label, style: const TextStyle(fontSize: 10, color: VicaColors.textTertiary)),
                    ),
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
