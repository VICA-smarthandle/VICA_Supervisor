// 알림 및 로그 위쪽의 '오늘 N건' 숫자 줄과 시간대 막대(2026-11-17 사용자 채택, 캔버스 초안 ①).
//
// 앱 로그(SupervisorLog)는 분류·문장·시각만 있고 앱이 켜진 뒤 최근 100건만 메모리에
// 둡니다. 그래서 '오늘' 은 그 100건 가운데 오늘 날짜인 것만 셉니다. 막대는 지금 시각까지
// 최근 7시간, 한 칸이 1시간이고 분류별로 색을 쌓습니다.
import 'package:flutter/material.dart';

import '../core/log_filter.dart';
import '../models/supervisor_log.dart';
import 'vica_ui.dart';

/// 숫자 줄·막대에 나오는 분류와 순서. '전체' 는 분류가 아니고 '경비 기록' 은 앱 로그의 경보 줄을 셉니다.
const kLogSummaryFilters = [
  LogFilter.emergencyStop,
  LogFilter.connection,
  LogFilter.delivery,
  LogFilter.coordinateTransfer,
  LogFilter.patrol,
];

/// 막대 칸 수(시간). 폰 폭에서 칸마다 숫자가 읽히는 만큼입니다.
const kLogSummaryHours = 7;

String _shortLabel(LogFilter filter) => switch (filter) {
      LogFilter.connection => '연결',
      LogFilter.delivery => '배송',
      LogFilter.patrol => '경비',
      _ => filter.label,
    };

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// 오늘 기록의 분류별 수와 시간대 막대.
///
/// [filter] 가 '전체' 가 아니면 막대는 그 분류만 쌓습니다. [hour] 는 고른 시(0~23),
/// 막대를 누르면 [onHour] 로 알립니다(같은 칸을 다시 누르면 null). 숫자 칸을 누르면
/// [onFilter] 로 그 분류를 알립니다.
class LogTodaySummary extends StatelessWidget {
  const LogTodaySummary({
    super.key,
    required this.logs,
    required this.filter,
    required this.hour,
    required this.onHour,
    required this.onFilter,
    this.now,
  });

  final List<SupervisorLog> logs;
  final LogFilter filter;
  final int? hour;
  final ValueChanged<int?> onHour;
  final ValueChanged<LogFilter> onFilter;

  /// 지금 시각(시험용). 없으면 DateTime.now().
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final at = now ?? DateTime.now();
    final today = logs.where((log) => _sameDay(log.createdAt, at)).toList();
    final counts = {
      for (final f in kLogSummaryFilters)
        f: today.where((log) => log.filter == f).length,
    };
    final shown = filter == LogFilter.all
        ? today
        : today.where((log) => log.filter == filter).toList();
    final first = at.hour - kLogSummaryHours + 1;
    final hours = [
      for (var h = first < 0 ? 0 : first; h <= at.hour; h++) h,
    ];
    final selectedCount = hour == null
        ? 0
        : shown.where((log) => log.createdAt.hour == hour).length;

    return VicaCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  '오늘 ${today.length}건',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
              const Flexible(
                child: Text(
                  '앱이 켜진 뒤 · 최근 100건',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: VicaColors.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < kLogSummaryFilters.length; i++) ...[
                  if (i > 0)
                    const VerticalDivider(
                        width: 1, thickness: 1, color: VicaColors.border),
                  Expanded(
                    child: _CountButton(
                      filter: kLogSummaryFilters[i],
                      count: counts[kLogSummaryFilters[i]]!,
                      selected: filter == kLogSummaryFilters[i],
                      onTap: () => onFilter(kLogSummaryFilters[i]),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Expanded(
                // 2026-11-17 사용자: 막대가 덮는 범위를 제목에 적는다(오늘 전체가 아님).
                child: Text(
                  '최근 $kLogSummaryHours시간',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                ),
              ),
              if (hour != null)
                Flexible(
                  child: Text(
                    '$hour시 · $selectedCount건 선택됨',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: VicaColors.primaryDark,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _HourBars(
            hours: hours,
            logs: shown,
            selected: hour,
            onTap: (h) => onHour(h == hour ? null : h),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              for (final f in kLogSummaryFilters)
                if (filter == LogFilter.all || filter == f)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: vicaLogColor(f),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _shortLabel(f),
                        style: const TextStyle(
                            fontSize: 11, color: VicaColors.muted),
                      ),
                    ],
                  ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CountButton extends StatelessWidget {
  const _CountButton({
    required this.filter,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final LogFilter filter;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = _shortLabel(filter);
    return Semantics(
      button: true,
      selected: selected,
      label: '$label $count건',
      excludeSemantics: true,
      child: PressScale(child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          decoration: selected
              ? BoxDecoration(
                  color: VicaColors.accentTint,
                  borderRadius: BorderRadius.circular(10),
                )
              : null,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '$count',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                    color: count == 0
                        ? VicaColors.textTertiary
                        : vicaLogTextColor(filter),
                  ),
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.25,
                  color: VicaColors.muted,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      )),
    );
  }
}

/// 시간대 막대. 칸마다 분류별 수를 아래부터 쌓고 위에 합계를 적습니다.
class _HourBars extends StatelessWidget {
  const _HourBars({
    required this.hours,
    required this.logs,
    required this.selected,
    required this.onTap,
  });

  final List<int> hours;
  final List<SupervisorLog> logs;
  final int? selected;
  final ValueChanged<int> onTap;

  static const _maxBar = 96.0;

  @override
  Widget build(BuildContext context) {
    final byHour = {
      for (final h in hours)
        h: {
          for (final f in kLogSummaryFilters)
            f: logs
                .where((log) => log.createdAt.hour == h && log.filter == f)
                .length,
        },
    };
    final totals = {
      for (final h in hours) h: byHour[h]!.values.fold(0, (a, b) => a + b)
    };
    final most = totals.values.fold(0, (a, b) => a > b ? a : b);
    final unit = most == 0 ? 0.0 : _maxBar / most;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final h in hours)
          Expanded(
            child: Semantics(
              button: true,
              selected: selected == h,
              label: '$h시 ${totals[h]}건',
              excludeSemantics: true,
              child: PressScale(child: InkWell(
                onTap: () => onTap(h),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${totals[h]}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: totals[h] == 0
                              ? VicaColors.textTertiary
                              : VicaColors.muted,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(6)),
                          border: selected == h
                              ? Border.all(
                                  color: VicaColors.primaryDark, width: 2)
                              : null,
                        ),
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(5)),
                          child: Column(
                            children: [
                              // 위에서부터 그리므로 순서를 뒤집어 첫 분류가 맨 아래에 옵니다.
                              for (final f in kLogSummaryFilters.reversed)
                                if (byHour[h]![f]! > 0)
                                  Container(
                                    height: byHour[h]![f]! * unit,
                                    color: vicaLogColor(f),
                                  ),
                              if (totals[h] == 0)
                                Container(height: 2, color: VicaColors.border),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$h시',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: selected == h
                              ? VicaColors.primaryDark
                              : VicaColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              )),
            ),
          ),
      ],
    );
  }
}
