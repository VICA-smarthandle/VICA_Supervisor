// 이 파일은 마이크 점검 화면의 '값 고치기' 카드(캔버스 109)를 그립니다.
// 슬라이더 6개(수음 최소~"멈춰" 한 조각 문턱)와 단추 묶음 3개(AGC 목표·AGC 최대 증폭·에코 지우기),
// 그 아래 '다시 채점'·'저장'·'원래대로'. 슬라이더는 놓을 때, 단추는 누를 때 `set` 을 보냅니다.
// 값은 점검기가 다시 보내는 status 가 정본이고, 끌고 있는 동안만 화면이 임시로 들고 있습니다.
import 'package:flutter/material.dart';

import '../../models/mic_check.dart';
import '../vica_ui.dart';

/// 보냈으면 true, 끊겨 못 보냈으면 false.
typedef MicSendOk = bool Function(String cmd, [Map<String, Object?> args]);

/// 슬라이더 순서(옛 페이지 `CTL`).
const kMicSliderKeys = [
  'listen_min_rms',
  'short_answer_min_rms',
  'approach_min_rms',
  'band_min',
  'wake_threshold',
  'emergency_single',
];

/// 값이 null(.env 에 줄 없음)일 때 보여 주는 뜻(옛 페이지 `NONE`).
const kMicNone = {
  'approach_min_rms': '줄 없음 · 수음 최소 따름',
  'band_min': '꺼짐',
  'agc_max_gain': '줄 없음 · 칩 공장값',
};

/// 에코 단추 짧은 문구(캔버스 109). 그 밖의 키는 점검기가 준 문구를 씁니다.
/// 2026-11-21 점검기 선택지 확대: 약(0.5·켜짐)·최대(3.0·켜짐)도 같은 꼴로 줄입니다.
const _echoShort = {'weak': '약', 'mid': '중간', 'strong': '센', 'max': '최대', 'factory': '공장값'};

bool _same(Object? a, Object? b) {
  if (a is num && b is num) return (a - b).abs() < 1e-9;
  return a == b;
}

String _fmtTh(double v) {
  if (v >= 0.1) return v.toStringAsFixed(2);
  final s = v.toStringAsFixed(4);
  return s.endsWith('0') ? s.substring(0, s.length - 1) : s;
}

String _fmtNum(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

int _decimals(double step) {
  var d = 0;
  var s = step;
  while (d < 4 && (s - s.roundToDouble()).abs() > 1e-9) {
    s *= 10;
    d++;
  }
  return d;
}

class MicValuesCard extends StatefulWidget {
  const MicValuesCard({super.key, required this.status, required this.onSend, required this.onRestore});

  final MicCheckStatus status;
  final MicSendOk onSend;

  /// '원래대로' — 확인 시트는 화면이 띄웁니다.
  final VoidCallback onRestore;

  @override
  State<MicValuesCard> createState() => _MicValuesCardState();
}

class _MicValuesCardState extends State<MicValuesCard> {
  // 끌고 있는 슬라이더의 임시 값. 점검기가 새 status 를 보내면 비웁니다.
  final Map<String, double> _local = {};

  @override
  void didUpdateWidget(MicValuesCard old) {
    super.didUpdateWidget(old);
    if (!identical(old.status, widget.status)) _local.clear();
  }

  MicCheckStatus get _st => widget.status;

  Object? _value(String k) => _local.containsKey(k) ? _local[k] : _st.values[k];

  double? _num(String k) {
    final v = _value(k);
    return v is num ? v.toDouble() : null;
  }

  String _show(String k, double? v) {
    if (v == null) return kMicNone[k] ?? '';
    return (k.endsWith('rms') || k == 'band_min') ? _fmtTh(v) : v.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final short = _num('short_answer_min_rms');
    final listen = _num('listen_min_rms');
    final k = _st.shortOverListen;
    final bad = short != null && listen != null && short < listen * k - 1e-9;
    final need = k == 1.0 ? '수음 최소 이상' : '수음 최소의 ${_fmtNum(k)}배 이상';
    return VicaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('값 고치기', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          for (final key in kMicSliderKeys)
            if (_st.ranges.containsKey(key)) ...[
              _slider(key),
              if (key == 'short_answer_min_rms') _line(need),
              if (key == 'short_answer_min_rms' && bad)
                _line(
                  '짧은 답 최소는 $need이어야 합니다. 이대로는 저장할 수 없습니다.',
                  color: VicaColors.red,
                ),
              if (key == 'emergency_single' && (_num(key) ?? 1) < 0.5 - 1e-9)
                _line('0.50 아래입니다. 다른 말에 멈춰가 잘못 걸릴 수 있으니 결과표의 오발동 줄을 꼭 보세요.',
                    color: VicaColors.warning),
            ],
          _agc(),
          _gain(),
          _echo(),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('mic_check_rejudge'),
                  onPressed: () => widget.onSend('rejudge'),
                  child: const Text('다시 채점'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  key: const ValueKey('mic_check_save'),
                  onPressed: bad ? null : () => widget.onSend('save_preview'),
                  child: const Text('저장'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('mic_check_restore'),
                  onPressed: widget.onRestore,
                  child: const Text('원래대로'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _line(String text, {Color color = VicaColors.muted}) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: TextStyle(fontSize: 12, color: color)),
      );

  Widget _head(String k, String valueText, bool changed) {
    return Row(
      children: [
        Expanded(child: Text(_st.names[k] ?? k, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
        if (changed)
          const Padding(
            padding: EdgeInsets.only(right: 6),
            child: Text('바뀜', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: VicaColors.warning)),
          ),
        Text(valueText, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
      ],
    );
  }

  Widget _slider(String k) {
    final r = _st.ranges[k]!;
    final v = _num(k);
    final env = _st.envValues[k];
    final changed = !_same(_value(k), env);
    // 값이 null 이면 막대는 실제로 쓰이는 값에 둡니다(접근 대답 최소는 수음 최소, 대역 관문 끔은 맨 왼쪽).
    final eff = v ?? (k == 'approach_min_rms' ? (_num('listen_min_rms') ?? r.min) : r.min);
    final d = _decimals(r.step);
    final n = ((r.max - r.min) / r.step).round();
    final envText = env is num ? _show(k, env.toDouble()) : (kMicNone[k] ?? '');
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _head(k, _show(k, v), changed),
          Slider(
            key: ValueKey('mic_check_slider_$k'),
            value: eff.clamp(r.min, r.max),
            min: r.min,
            max: r.max,
            divisions: n > 0 ? n : null,
            onChanged: (x) => setState(() => _local[k] = x),
            onChangeEnd: (x) {
              if (!widget.onSend('set', {'key': k, 'value': x})) setState(_local.clear);
            },
          ),
          Text(
            '${_st.envKeys[k] ?? k}${changed ? ' · .env $envText' : ''} · '
            '${r.min.toStringAsFixed(d)}~${r.max.toStringAsFixed(d)}',
            style: const TextStyle(fontSize: 11, color: VicaColors.muted),
          ),
        ],
      ),
    );
  }

  Widget _seg(String k, List<(Object, String)> options, bool Function(Object) selected, String valueText, bool changed,
      String envKey) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _head(k, valueText, changed),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final (value, label) in options)
                ChoiceChip(
                  key: ValueKey('mic_check_${k}_${value is double ? _fmtNum(value) : value}'),
                  label: Text(label),
                  selected: selected(value),
                  onSelected: (_) => widget.onSend('set', {'key': k, 'value': value}),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(envKey, style: const TextStyle(fontSize: 11, color: VicaColors.muted)),
        ],
      ),
    );
  }

  Widget _agc() {
    final v = _num('agc');
    final env = _st.envValues['agc'];
    return _seg(
      'agc',
      [for (final a in _st.agcChoices) (a, a.toStringAsFixed(3))],
      (o) => v != null && _same(o, v),
      v == null ? '' : v.toStringAsFixed(3),
      !_same(_value('agc'), env),
      _st.envKeys['agc'] ?? 'agc',
    );
  }

  Widget _gain() {
    final raw = _num('agc_max_gain');
    final eff = raw ?? _st.gainFactory; // 줄 없음 = 점검기가 칩에 공장값을 씁니다.
    String label(double g) => '×${_fmtNum(g)}';
    return _seg(
      'agc_max_gain',
      [for (final g in _st.gainChoices) (g, label(g))],
      (o) => _same(o, eff),
      raw == null ? '${label(_st.gainFactory)} (${kMicNone['agc_max_gain']})' : label(raw),
      !_same(_value('agc_max_gain'), _st.envValues['agc_max_gain']),
      _st.envKeys['agc_max_gain'] ?? 'agc_max_gain',
    );
  }

  Widget _echo() {
    final cur = _value('echo');
    String label(String key) => _echoShort[key] ?? _st.echoChoices[key] ?? key;
    return _seg(
      'echo',
      [for (final key in _st.echoChoices.keys) (key, label(key))],
      (o) => o == cur,
      cur is String ? label(cur) : '',
      cur != _st.envValues['echo'],
      _st.envKeys['echo'] ?? 'echo',
    );
  }
}
