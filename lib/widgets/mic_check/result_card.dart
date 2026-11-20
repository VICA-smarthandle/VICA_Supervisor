// 이 파일은 마이크 점검 화면의 '결과표' 카드(캔버스 109)를 그립니다.
// 머리 칩(전체 판정 title), 값이 바뀌어 표가 낡았다는 안내, 줄마다 이름·판정·detail·고칠 일,
// '처음 값 결과 보기' 펼침, 채점 중 덮개를 보여 줍니다. 줄 이름·detail·todo 는 점검기가 보낸 그대로입니다.
import 'package:flutter/material.dart';

import '../../models/mic_check.dart';
import '../vica_ui.dart';

/// 줄 판정 문구(옛 페이지 `GN`).
const kMicGradeNames = {
  'pass': '합격',
  'warn': '주의',
  'fail': '불합격',
  'redo': '다시 녹음',
  'wait': '점검 중',
};

Color micGradeColor(String g) => switch (g) {
      'pass' => VicaColors.green,
      'warn' => VicaColors.warning,
      'fail' => VicaColors.red,
      _ => VicaColors.muted,
    };

class MicResultCard extends StatefulWidget {
  const MicResultCard({super.key, required this.results, required this.busy});

  final MicCheckResults results;

  /// 채점 중이면 비어 있지 않은 문구(덮개를 씌웁니다).
  final bool busy;

  @override
  State<MicResultCard> createState() => _MicResultCardState();
}

class _MicResultCardState extends State<MicResultCard> {
  bool _showFirst = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.results;
    final first = r.first;
    return Stack(
      children: [
        VicaCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('결과표', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: _Chip(r.title, micGradeColor(r.overall)),
              ),
              if (r.stale)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    '값이 바뀌었습니다 · 다시 채점하세요',
                    style: TextStyle(color: VicaColors.warning, fontWeight: FontWeight.w700),
                  ),
                ),
              const SizedBox(height: 4),
              for (final row in r.rows) _RowTile(row),
              if (first != null) ...[
                const SizedBox(height: 4),
                TextButton(
                  key: const ValueKey('mic_check_first_toggle'),
                  onPressed: () => setState(() => _showFirst = !_showFirst),
                  style: TextButton.styleFrom(alignment: Alignment.centerLeft, padding: EdgeInsets.zero),
                  child: Text('처음 값 결과 보기 ${_showFirst ? '▴' : '▾'}'),
                ),
                if (_showFirst)
                  Column(
                    key: const ValueKey('mic_check_first_rows'),
                    children: [for (final row in first) _RowTile(row, dim: true)],
                  ),
              ],
            ],
          ),
        ),
        if (widget.busy)
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                key: const ValueKey('mic_check_busy_cover'),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(kVicaCardRadius),
                ),
                child: const Text('다시 채점하는 중', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              ),
            ),
          ),
      ],
    );
  }
}

class _RowTile extends StatelessWidget {
  const _RowTile(this.row, {this.dim = false});
  final MicCheckRow row;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final color = micGradeColor(row.grade);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(row.name,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: dim ? VicaColors.muted : null)),
              ),
              Text(kMicGradeNames[row.grade] ?? row.grade,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color)),
            ],
          ),
          const SizedBox(height: 2),
          Text(row.detail, style: const TextStyle(fontSize: 13, color: VicaColors.muted)),
          if (row.todo.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(row.todo, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
      );
}
