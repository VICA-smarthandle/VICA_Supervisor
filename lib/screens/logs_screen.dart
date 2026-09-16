// 이 파일은 전체, 긴급 정지, 좌표 전송, 연결 상태 로그 필터와 삭제 기능을 제공합니다.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/log_filter.dart';
import '../providers/supervisor_provider.dart';
import '../widgets/vica_ui.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  LogFilter _filter = LogFilter.all;

  @override
  Widget build(BuildContext context) {
    final supervisor = context.watch<SupervisorProvider>();
    final logs = _filter == LogFilter.all
        ? supervisor.logs
        : supervisor.logs.where((log) => log.filter == _filter).toList();
    return VicaPage(
      children: [
        // 제목 줄 오른쪽 끝에 삭제 버튼을 둡니다. 전에는 칩 줄 끝에 있어 마지막
        // 칩과 겹쳐 보였습니다(2026-09-15 실기).
        Row(
          children: [
            Expanded(
              child: Text(
                '알림 및 로그',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            IconButton.outlined(
              onPressed: () => supervisor.clearLogs(_filter),
              icon: const Icon(Icons.delete_sweep),
              tooltip: _filter == LogFilter.all ? '전체 삭제' : '필터 로그 삭제',
            ),
          ],
        ),
        const SizedBox(height: 16),
        SingleChildScrollView(
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
                  onSelected: (_) => setState(() => _filter = filter),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 18),
        if (logs.isEmpty)
          const VicaCard(child: Text('표시할 로그가 없습니다.'))
        else
          ...logs.map((log) => VicaLogTile(log: log)),
      ],
    );
  }
}
