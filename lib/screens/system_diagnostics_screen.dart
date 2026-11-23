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
        const SizedBox(height: 18),
        const _FrontUltrasonicCard(),
      ],
    );
  }
}

/// 전방 초음파 켜기·끄기(2026-11-18 사용자). 손잡이 드라이버(C++ 판)의
class _FrontUltrasonicCard extends StatelessWidget {
  const _FrontUltrasonicCard();

  String _distance(double? meters) {
    if (meters == null) {
      return '—';
    }
    if (meters.isInfinite) {
      return '없음';
    }
    return '${meters.toStringAsFixed(2)} m';
  }

  Future<void> _toggle(BuildContext context, bool on) async {
    final supervisor = context.read<SupervisorProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final error = await supervisor.setFrontUltrasonic(on);
    messenger.showSnackBar(SnackBar(
      content: Text(error ?? (on ? '전방 초음파를 켰습니다' : '전방 초음파를 껐습니다')),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final supervisor = context.watch<SupervisorProvider>();
    final on = supervisor.frontUltrasonicOn;
    final busy = supervisor.frontUltrasonicBusy;
    final detail = ValueListenableBuilder<int>(
      valueListenable: supervisor.frontRangeTick,
      builder: (context, _, __) {
        final String text;
        if (busy) {
          text = '바꾸는 중…';
        } else if (on == null) {
          text = '상태를 모릅니다 · 주행을 켜면 바꿀 수 있습니다';
        } else if (on) {
          text = '켜짐 · 왼쪽 ${_distance(supervisor.frontRange(0))} · '
              '오른쪽 ${_distance(supervisor.frontRange(1))}';
        } else {
          text = '꺼짐 · costmap 에 넣지 않음 · 주행 다시 켜면 켜짐';
        }
        return Text(
          text,
          style: const TextStyle(fontSize: 12.5, color: VicaColors.muted),
        );
      },
    );
    return VicaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '전방 초음파',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    detail,
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (on != null)
                VicaStateBadge(
                  text: on ? '켜짐' : '꺼짐',
                  color: on ? VicaColors.green : VicaColors.textTertiary,
                ),
              const SizedBox(width: 6),
              Semantics(
                label: '전방 초음파 켜기·끄기',
                child: Switch(
                  value: on ?? false,
                  activeThumbColor: VicaColors.card,
                  activeTrackColor: VicaColors.primary,
                  onChanged: on == null || busy
                      ? null
                      : (value) => _toggle(context, value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '초음파를 끄면 0.38 m보다 낮은 물체를 피하기 어렵습니다.',
            style: TextStyle(fontSize: 12.5, color: VicaColors.muted),
          ),
        ],
      ),
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
          vicaKeepWords(vicaBreakAtSentences(
            '아직 로봇 상태를 받지 못했습니다. '
            'robot_health_monitor_node가 실행 중인지 확인해 주세요.',
          )),
        ),
      );
    }

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
            if (fault.message.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                vicaKeepWords(vicaBreakAtSentences(fault.message)),
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: 8),
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
                    child: PressScale(
                        child: OutlinedButton(
                      onPressed: () => setState(() => _showAll = !_showAll),
                      child: Text(_showAll ? '최근 1시간만' : '이력 더 보기 ($hidden건)'),
                    )),
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
