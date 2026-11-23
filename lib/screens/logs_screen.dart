import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/log_filter.dart';
import '../models/patrol.dart';
import '../providers/settings_provider.dart';
import '../providers/supervisor_provider.dart';
import '../widgets/patrol_media.dart';
import '../widgets/log_summary.dart';
import '../widgets/patrol_ui.dart';
import '../widgets/vica_ui.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({
    super.key,
    this.initialFilter = LogFilter.all,
    this.clipOpener,
  });

  /// 처음 고를 분류. 경비 탭의 '경비 기록 N건'이 [LogFilter.patrol] 로 엽니다.
  final LogFilter initialFilter;

  /// 영상을 여는 함수(시험용). 없으면 실제 재생기를 씁니다.
  final PatrolClipOpener? clipOpener;

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  late LogFilter _filter = widget.initialFilter;

  int? _hour;
  final _chipScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    if (_filter == LogFilter.patrol) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _refreshPatrol();
        if (_chipScroll.hasClients) {
          _chipScroll.jumpTo(_chipScroll.position.maxScrollExtent);
        }
      });
    }
  }

  @override
  void dispose() {
    _chipScroll.dispose();
    super.dispose();
  }

  void _refreshPatrol() {
    final settings = context.read<SettingsProvider>().settings;
    unawaited(
      context.read<SupervisorProvider>().refreshPatrolRecords(settings),
    );
  }

  @override
  Widget build(BuildContext context) {
    final supervisor = context.watch<SupervisorProvider>();
    final patrol = _filter == LogFilter.patrol;
    final now = DateTime.now();
    final logs = supervisor.logs.where((log) {
      if (_filter != LogFilter.all && log.filter != _filter) {
        return false;
      }
      final hour = _hour;
      return hour == null ||
          (log.createdAt.hour == hour &&
              log.createdAt.year == now.year &&
              log.createdAt.month == now.month &&
              log.createdAt.day == now.day);
    }).toList();
    return VicaPage(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '알림 및 로그',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            PressScale(
                child: IconButton.outlined(
              onPressed: patrol
                  ? () => unawaited(_confirmClearPatrol(supervisor))
                  : () => supervisor.clearLogs(_filter),
              icon: const Icon(Icons.delete_sweep),
              tooltip: patrol
                  ? '경비 기록 삭제'
                  : (_filter == LogFilter.all ? '전체 삭제' : '필터 로그 삭제'),
            )),
          ],
        ),
        const SizedBox(height: 16),
        SingleChildScrollView(
          controller: _chipScroll,
          scrollDirection: Axis.horizontal,
          child: Row(
            children: LogFilter.values.map((filter) {
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  selected: _filter == filter,
                  avatar: _filter == filter
                      ? const Icon(Icons.check, size: 18)
                      : null,
                  label: Text(filter.label),
                  onSelected: (_) {
                    setState(() {
                      _filter = filter;
                      if (filter != LogFilter.all) {
                        _hour = null;
                      }
                    });
                    if (filter == LogFilter.patrol) {
                      _refreshPatrol();
                    }
                  },
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 18),
        if (_filter == LogFilter.all && supervisor.logs.isNotEmpty) ...[
          LogTodaySummary(
            logs: supervisor.logs,
            filter: _filter,
            hour: _hour,
            now: now,
            onHour: (hour) => setState(() => _hour = hour),
            onFilter: (filter) => setState(() {
              _filter = filter;
              _hour = null;
            }),
          ),
          if (_hour != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '$_hour시 기록',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: VicaColors.muted,
                      ),
                    ),
                  ),
                  PressScale(
                      child: TextButton(
                    onPressed: () => setState(() => _hour = null),
                    child: const Text('모든 시간'),
                  )),
                ],
              ),
            ),
        ],
        if (patrol)
          ..._patrolRecords(
            supervisor,
            context.watch<SettingsProvider>().settings.mapHttpBaseUrl,
          )
        else if (logs.isEmpty)
          const VicaCard(child: Text('표시할 로그가 없습니다.'))
        else
          ...logs.map((log) => VicaLogTile(log: log)),
      ],
    );
  }

  List<Widget> _patrolRecords(SupervisorProvider supervisor, String baseUrl) {
    final records = supervisor.patrolRecords;
    if (records == null) {
      return [
        if (supervisor.patrolRecordsLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          VicaCard(
            child: Text(
              supervisor.patrolRecordsFailed
                  ? patrolKeepWords(patrolRecordsFailedText(baseUrl))
                  : '표시할 로그가 없습니다.',
            ),
          ),
      ];
    }
    if (records.isEmpty) {
      return const [VicaCard(child: Text('표시할 로그가 없습니다.'))];
    }
    return [
      for (final record in records)
        PatrolRecordTile(
          record: record,
          onPlay: () => showPatrolClip(
            context,
            record,
            opener: widget.clipOpener,
          ),
          onPhoto: () => _openPhoto(record),
        ),
    ];
  }

  Future<void> _confirmClearPatrol(SupervisorProvider supervisor) async {
    final settings = context.read<SettingsProvider>().settings;
    final confirmed = await showVicaConfirm(
      context,
      icon: Icons.delete_outline,
      iconColor: VicaColors.red,
      title: kPatrolRecordsClearTitle,
      body: kPatrolRecordsClearBody,
      confirmLabel: '지우기',
      danger: true,
    );
    if (!confirmed || !mounted) {
      return;
    }
    final message = await supervisor.clearPatrolRecords(settings);
    if (!mounted) {
      return;
    }
    showPatrolToast(context, message);
  }

  void _openPhoto(PatrolRecord record) {
    unawaited(
      showPatrolPhoto(context, title: record.mediaTitle, photo: record.photo),
    );
  }
}
