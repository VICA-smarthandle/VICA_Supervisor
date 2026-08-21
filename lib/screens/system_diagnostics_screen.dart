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

    return VicaPage(
      title: '시스템 진단',
      subtitle: '로봇이 보고한 결함과 상태 변화입니다.',
      children: [
        if (!connected)
          VicaDisconnectedNotice(detail: supervisor.connectionDetail),
        _Summary(health: health, settings: settings, connected: connected),
        const SizedBox(height: 18),
        _ActiveFaults(health: health),
        const SizedBox(height: 18),
        _Readiness(health: health),
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
      return const VicaCard(
        child: Text(
          '아직 로봇 상태를 받지 못했습니다. '
          'robot_health_monitor_node가 실행 중인지 확인해 주세요.',
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
                '상태 감시가 ${settings.robotHealthTimeoutSeconds}초 넘게 갱신되지 '
                '않았습니다. 아래 값은 현재 상태가 아닙니다.',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
    }

    final state = current.state;
    return VicaCard(
      child: Row(
        children: [
          Icon(current.highestSeverity.icon, color: state.color, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.label,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: state.color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  current.activeFaultCount == 0
                      ? '활성 결함이 없습니다.'
                      : '활성 결함 ${current.activeFaultCount}건 · '
                          '최고 등급 ${current.highestSeverity.label}',
                  style: const TextStyle(color: VicaColors.muted),
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
        const _SectionTitle('활성 결함'),
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: VicaCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(severity.icon, color: severity.color, size: 20),
                const SizedBox(width: 8),
                StatusBadge(label: severity.label, color: severity.color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    fault.componentLabelText,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                if (fault.latched)
                  const StatusBadge(label: '래치', color: VicaColors.red),
              ],
            ),
            const SizedBox(height: 8),
            // 기계 판독 코드. 정비하는 사람이 문서·로그에서 찾을 때 씁니다.
            Text(
              fault.faultCode,
              style: const TextStyle(
                color: VicaColors.muted,
                fontSize: 12,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            if (fault.detail.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(fault.detail),
            ],
            const SizedBox(height: 8),
            Text(
              _metaLine(fault),
              style: const TextStyle(color: VicaColors.muted, fontSize: 12),
            ),
            if (fault.suggestedAction.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: VicaColors.softBlue,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.build_outlined,
                        size: 16, color: VicaColors.primaryDark),
                    const SizedBox(width: 8),
                    Expanded(child: Text(fault.suggestedAction)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _metaLine(RobotFault fault) {
    final time = _formatTime(fault.firstSeen);
    final parts = <String>['$time 발생'];
    if (fault.occurrenceCount > 1) {
      parts.add('${fault.occurrenceCount}회');
    }
    final duration = fault.duration;
    if (duration.inSeconds > 0) {
      parts.add('지속 ${_formatDuration(duration)}');
    }
    return parts.join(' · ');
  }
}

class _Readiness extends StatelessWidget {
  const _Readiness({required this.health});

  final RobotHealth? health;

  @override
  Widget build(BuildContext context) {
    final readiness = health?.readiness;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('부품 상태'),
        if (readiness == null || readiness.isEmpty)
          const VicaCard(child: Text('아직 부품 상태를 받지 못했습니다.'))
        else
          VicaCard(
            child: Column(
              children: [
                for (final entry in readiness.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: entry.value.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(componentLabel(entry.key))),
                        Text(
                          entry.value.label,
                          style: TextStyle(
                            color: entry.value.color,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                // "관측 불가"가 무슨 뜻인지 알려줍니다. 이 설명이 없으면 관리자가
                // 고장으로 오해하거나 반대로 정상으로 오해합니다.
                if (readiness.values.contains(ComponentReadiness.unknown)) ...[
                  const Divider(height: 20),
                  const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.help_outline,
                          size: 16, color: VicaColors.muted),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '관측 불가는 고장이 아니라 상태를 확인할 수단이 없다는 '
                          '뜻입니다. 정상이라고 볼 수 없습니다.',
                          style:
                              TextStyle(color: VicaColors.muted, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
      ],
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

class _EventHistory extends StatelessWidget {
  const _EventHistory({required this.events});

  final List<RobotEvent> events;

  @override
  Widget build(BuildContext context) {
    final groups = _groupConsecutive(events);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('상태 변화 이력'),
        if (events.isEmpty)
          const VicaCard(child: Text('기록된 상태 변화가 없습니다.'))
        else
          VicaCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Column(
              children: [
                for (final group in groups)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          group.latest.transition == FaultTransition.cleared
                              ? Icons.check_circle_outline
                              : group.latest.fault.severity.icon,
                          size: 18,
                          color:
                              group.latest.transition == FaultTransition.cleared
                                  ? VicaColors.green
                                  : group.latest.fault.severity.color,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${group.latest.fault.componentLabelText} · '
                                '${group.latest.transition.label}'
                                '${group.count > 1 ? '  ×${group.count}회' : ''}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700),
                              ),
                              Text(
                                group.latest.fault.detail.isEmpty
                                    ? group.latest.fault.faultCode
                                    : group.latest.fault.detail,
                                style: const TextStyle(
                                    color: VicaColors.muted, fontSize: 12),
                              ),
                              if (group.count > 1)
                                Text(
                                  '처음 ${_formatTime(group.first.receivedAt)}',
                                  style: const TextStyle(
                                      color: VicaColors.muted, fontSize: 11),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatTime(group.latest.receivedAt),
                          style: const TextStyle(
                              color: VicaColors.muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
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
