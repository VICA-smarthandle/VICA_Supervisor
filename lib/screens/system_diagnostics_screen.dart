// 이 파일은 로봇의 활성 결함과 상태 변화 이력을 보여주는 화면입니다.
//
// /robot_status.error_reason은 문자열 한 줄만 담아 어느 부품이 왜 문제인지 알 수
// 없었습니다. 이 화면은 /robot/health와 /robot/events를 직접 구독해 컴포넌트·등급·
// 조치·발생시각·횟수·지속시간을 모두 보여줍니다.
//
// 문구는 로봇이 만들어 보냅니다. 앱은 표시만 합니다.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_settings.dart';
import '../core/fault_severity.dart';
import '../models/robot_event.dart';
import '../models/robot_fault.dart';
import '../models/robot_health.dart';
import '../providers/settings_provider.dart';
import '../providers/supervisor_provider.dart';
import '../ros/ros_bridge_client.dart';
import '../widgets/status_badge.dart';
import '../widgets/vica_ui.dart';

class SystemDiagnosticsScreen extends StatelessWidget {
  const SystemDiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final supervisor = context.watch<SupervisorProvider>();
    final settings = context.watch<SettingsProvider>().settings;
    final health = supervisor.health;
    final connected =
        supervisor.connectionState == RosConnectionState.connected;

    // 본문 제목·설명은 뺐습니다 — 제목줄에 이미 있습니다(2026-11-17 제목·문구 간결화, 사용자 승인).
    // 2026-11-17 사용자 채택 A안(캔버스 '시스템 진단 개선안'): 맨 위 한 줄 판정 → 항목 3칸 타일
    // (안 된 것 먼저) → 결함 → 최근 1시간. 할 일(suggested_action)은 보이지 않는다(사용자 요청).
    return VicaPage(
      children: [
        if (!connected)
          VicaDisconnectedNotice(detail: supervisor.connectionDetail),
        _Summary(health: health, settings: settings, connected: connected),
        const SizedBox(height: 14),
        _Readiness(health: health),
        const SizedBox(height: 18),
        _ActiveFaults(health: health),
        const SizedBox(height: 18),
        _EventHistory(events: supervisor.healthEvents),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.health,
    required this.settings,
    required this.connected,
  });

  final RobotHealth? health;
  final AppSettings settings;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final current = health;

    if (current == null) {
      return VicaCard(
        child: Text(
          // 안내문은 마침표에서 나누되 짧은 문장은 붙이고, 어절 단위로 접힙니다.
          vicaKeepWords(vicaBreakAtSentences(
            '아직 로봇 상태를 받지 못했습니다. '
            'robot_health_monitor_node가 실행 중인지 확인해 주세요.',
          )),
        ),
      );
    }

    // 모니터가 죽으면 마지막 상태를 현재로 보여주지 않습니다.
    final stale =
        current.isStale(Duration(seconds: settings.robotHealthTimeoutSeconds));
    if (stale && connected) {
      return VicaCard(
        child: Row(
          children: [
            const Icon(Icons.cloud_off_outlined, color: VicaColors.red),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                vicaKeepWords(vicaBreakAtSentences(
                  '상태 감시가 ${settings.robotHealthTimeoutSeconds}초 넘게 갱신되지 '
                  '않았습니다. 아래 값은 현재 상태가 아닙니다.',
                )),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
    }

    final state = current.state;
    final faults = current.activeFaults;
    final ready = current.readiness.values
        .where((r) => r == ComponentReadiness.ready)
        .length;
    // 가장 높은 등급의 결함 하나를 한 줄에 적습니다(예: 'LiDAR · 결함 2건').
    final top = faults.isEmpty
        ? null
        : (List.of(faults)
              ..sort((x, y) => y.severity.value.compareTo(x.severity.value)))
            .first;
    final sub = top == null
        ? '결함 없음 · ${current.readiness.length}개 중 $ready개 정상'
        : '${top.componentLabelText} · 결함 ${current.activeFaultCount}건';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: state.color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(kVicaCardRadius),
        border: Border.all(color: state.color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration:
                BoxDecoration(color: state.color, shape: BoxShape.circle),
            child: Icon(current.highestSeverity.icon,
                color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.label,
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    color: state.color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  style: const TextStyle(color: VicaColors.muted, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveFaults extends StatelessWidget {
  const _ActiveFaults({required this.health});

  final RobotHealth? health;

  @override
  Widget build(BuildContext context) {
    final faults = health?.activeFaults ?? const <RobotFault>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(faults.isEmpty ? '결함' : '결함 ${faults.length}건'),
        if (faults.isEmpty)
          const VicaCard(child: Text('현재 보고된 결함이 없습니다.'))
        else
          ...faults.map((fault) => _FaultCard(fault: fault)),
      ],
    );
  }
}

class _FaultCard extends StatelessWidget {
  const _FaultCard({required this.fault});

  final RobotFault fault;

  @override
  Widget build(BuildContext context) {
    final severity = fault.severity;
    final duration = fault.duration;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: VicaCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                StatusBadge(label: severity.label, color: severity.color),
                const SizedBox(width: 8),
                // 좁은 폰·큰 글씨에서는 '래치' 가 이름 아래로 내려갑니다(폭 320·배율 1.3 에서 4 px 넘침).
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        fault.componentLabelText,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                      if (fault.latched)
                        const StatusBadge(label: '래치', color: VicaColors.red),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                if (duration.inSeconds > 0)
                  Text(
                    '${_formatDuration(duration)}째',
                    style:
                        const TextStyle(color: VicaColors.muted, fontSize: 12),
                  ),
              ],
            ),
            if (fault.detail.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                vicaKeepWords(vicaBreakAtSentences(fault.detail)),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
            const SizedBox(height: 8),
            // 기계 판독 코드는 끝에 작게 둡니다 — 정비하는 사람이 문서·로그에서 찾을 때 씁니다.
            Text(
              _metaLine(fault),
              style: const TextStyle(
                color: VicaColors.textTertiary,
                fontSize: 11,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _metaLine(RobotFault fault) {
    final parts = <String>[];
    if (fault.occurrenceCount > 1) {
      parts.add('${fault.occurrenceCount}회');
    }
    parts.add('처음 ${_formatTime(fault.firstSeen)}');
    parts.add(fault.faultCode);
    return parts.join(' · ');
  }
}

/// 항목 타일 하나의 상태. 그 항목에 활성 결함이 있으면 결함 등급을, 없으면 준비 상태를 씁니다.
class _PartState {
  const _PartState(this.key, this.label, this.color, this.rank,
      {this.hollow = false});

  final String key;
  final String label;
  final Color color;

  /// 클수록 앞에 둡니다(안 된 것 먼저).
  final int rank;

  /// 관측 불가는 속이 빈 점 — 고장도 정상도 아님.
  final bool hollow;
}

class _Readiness extends StatelessWidget {
  const _Readiness({required this.health});

  final RobotHealth? health;

  @override
  Widget build(BuildContext context) {
    final readiness = health?.readiness;
    final faults = health?.activeFaults ?? const <RobotFault>[];

    final states = <_PartState>[];
    if (readiness != null) {
      for (final entry in readiness.entries) {
        final worst = faults
            .where((f) => f.component == entry.key)
            .fold<RobotFault?>(
                null,
                (a, f) =>
                    a == null || f.severity.value > a.severity.value ? f : a);
        if (worst != null) {
          states.add(_PartState(entry.key, worst.severity.label,
              worst.severity.color, 10 + worst.severity.value));
        } else {
          states.add(switch (entry.value) {
            ComponentReadiness.notReady =>
              _PartState(entry.key, entry.value.label, entry.value.color, 5),
            ComponentReadiness.unknown => _PartState(
                entry.key, entry.value.label, entry.value.color, 2,
                hollow: true),
            ComponentReadiness.ready =>
              _PartState(entry.key, entry.value.label, entry.value.color, 0),
          });
        }
      }
      // 안정 정렬: 같은 순위는 원래 순서(모터·안전 제어·…)를 지킵니다.
      final indexed = states.asMap().entries.toList()
        ..sort((x, y) {
          final byRank = y.value.rank.compareTo(x.value.rank);
          return byRank != 0 ? byRank : x.key.compareTo(y.key);
        });
      states
        ..clear()
        ..addAll(indexed.map((e) => e.value));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('항목별 상태'),
        if (readiness == null || readiness.isEmpty)
          const VicaCard(child: Text('아직 준비되지 않았습니다.'))
        else
          VicaCard(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    const gap = 6.0;
                    final width = (constraints.maxWidth - gap * 2) / 3;
                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        for (final part in states)
                          SizedBox(width: width, child: _PartTile(part: part)),
                      ],
                    );
                  },
                ),
                // "관측 불가"가 무슨 뜻인지 알려줍니다. 이 설명이 없으면 관리자가
                // 고장으로 오해하거나 반대로 정상으로 오해합니다.
                if (readiness.values.contains(ComponentReadiness.unknown)) ...[
                  const SizedBox(height: 10),
                  Text(
                    vicaKeepWords(vicaBreakAtSentences(
                      '관측 불가는 고장이 아니라 상태를 확인할 수단이 없다는 '
                      '뜻입니다. 정상은 아닙니다.',
                    )),
                    style:
                        const TextStyle(color: VicaColors.muted, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _PartTile extends StatelessWidget {
  const _PartTile({required this.part});

  final _PartState part;

  @override
  Widget build(BuildContext context) {
    final problem = part.rank > 0;
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: problem && !part.hollow
            ? part.color.withValues(alpha: 0.10)
            : (part.hollow ? VicaColors.surfaceSunken : Colors.white),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: problem ? part.color : VicaColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: part.hollow ? null : part.color,
                    shape: BoxShape.circle,
                    border: part.hollow
                        ? Border.all(color: part.color, width: 2)
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  componentLabel(part.key),
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800, height: 1.25),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            part.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: part.rank == 0 ? VicaColors.green : part.color,
            ),
          ),
        ],
      ),
    );
  }
}

// 같은 결함의 같은 전이가 연달아 들어온 구간입니다. 목록에서 지우지 않고 한 줄로
// 접기만 하므로 몇 번 있었는지, 언제부터인지가 그대로 남습니다.
//
// 로봇 쪽에서 이미 두 겹으로 줄이고 있습니다 — event_deduplicator 가 재알림 간격을
// 두고(reminder_interval_sec 300, latched 10), 임계값 근처에서 오르내리는 관측은
// clear_confirm_ticks 3 으로 해소를 확정 지연합니다. 이 접기는 그래도 남는 반복을
// 화면에서 정리하는 마지막 층입니다.
class _EventGroup {
  const _EventGroup({
    required this.latest,
    required this.first,
    required this.count,
  });

  final RobotEvent latest;
  final RobotEvent first;
  final int count;
}

List<_EventGroup> _groupConsecutive(List<RobotEvent> events) {
  final groups = <_EventGroup>[];
  for (final event in events) {
    final last = groups.isEmpty ? null : groups.last;
    final sameAsLast = last != null &&
        last.latest.fault.componentLabelText ==
            event.fault.componentLabelText &&
        last.latest.fault.faultCode == event.fault.faultCode &&
        last.latest.transition == event.transition;
    if (sameAsLast) {
      // events 는 최신순이므로 뒤에 오는 것이 더 오래된 항목입니다.
      groups[groups.length - 1] = _EventGroup(
        latest: last.latest,
        first: event,
        count: last.count + 1,
      );
    } else {
      groups.add(_EventGroup(latest: event, first: event, count: 1));
    }
  }
  return groups;
}

/// 상태 변화 이력. 기본은 최근 1시간, '이력 더 보기'로 앱에 남은 전부(최대 100건)를 봅니다.
///
/// 한 줄 = 시각 · 점(발생은 등급색, 해소는 속 빈 초록) · '발생 · LiDAR 주행 불가' · ×N(접은 수).
class _EventHistory extends StatefulWidget {
  const _EventHistory({required this.events});

  final List<RobotEvent> events;

  @override
  State<_EventHistory> createState() => _EventHistoryState();
}

class _EventHistoryState extends State<_EventHistory> {
  static const _recent = Duration(hours: 1);
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final since = DateTime.now().subtract(_recent);
    final recent =
        widget.events.where((e) => e.receivedAt.isAfter(since)).toList();
    final shown = _showAll ? widget.events : recent;
    final groups = _groupConsecutive(shown);
    final hidden = widget.events.length - recent.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(child: _SectionTitle(_showAll ? '상태 변화 이력' : '최근 1시간')),
            const Text(
              '● 발생  ○ 해소',
              style: TextStyle(color: VicaColors.muted, fontSize: 11),
            ),
          ],
        ),
        if (widget.events.isEmpty)
          const VicaCard(child: Text('기록된 상태 변화가 없습니다.'))
        else
          VicaCard(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (groups.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Text('최근 1시간 동안 바뀐 것이 없습니다.',
                        style: TextStyle(color: VicaColors.muted)),
                  ),
                for (final group in groups) _HistoryRow(group: group),
                if (hidden > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: OutlinedButton(
                      onPressed: () => setState(() => _showAll = !_showAll),
                      child: Text(_showAll ? '최근 1시간만' : '이력 더 보기 ($hidden건)'),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.group});

  final _EventGroup group;

  @override
  Widget build(BuildContext context) {
    final event = group.latest;
    final cleared = event.transition == FaultTransition.cleared;
    final color = cleared ? VicaColors.green : event.fault.severity.color;
    final text = cleared
        ? '${event.transition.label} · ${event.fault.componentLabelText}'
        : '${event.transition.label} · ${event.fault.componentLabelText} '
            '${event.fault.severity.label}';
    return Container(
      constraints: const BoxConstraints(minHeight: 40),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: VicaColors.border)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              _formatTime(event.receivedAt).substring(0, 5),
              style: const TextStyle(color: VicaColors.muted, fontSize: 12),
            ),
          ),
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: cleared ? null : color,
              shape: BoxShape.circle,
              border: cleared ? Border.all(color: color, width: 2) : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
          if (group.count > 1)
            Text(
              '×${group.count}',
              style: const TextStyle(color: VicaColors.muted, fontSize: 12),
            ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
      ),
    );
  }
}

String _formatTime(DateTime time) {
  final local = time.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  final second = local.second.toString().padLeft(2, '0');
  return '$hour:$minute:$second';
}

String _formatDuration(Duration duration) {
  if (duration.inHours > 0) {
    return '${duration.inHours}시간 ${duration.inMinutes % 60}분';
  }
  if (duration.inMinutes > 0) {
    return '${duration.inMinutes}분 ${duration.inSeconds % 60}초';
  }
  return '${duration.inSeconds}초';
}
