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

class _EventHistory extends StatelessWidget {
  const _EventHistory({required this.events});

  final List<RobotEvent> events;

  @override
  Widget build(BuildContext context) {
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
                for (final event in events)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          event.transition == FaultTransition.cleared
                              ? Icons.check_circle_outline
                              : event.fault.severity.icon,
                          size: 18,
                          color: event.transition == FaultTransition.cleared
                              ? VicaColors.green
                              : event.fault.severity.color,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${event.fault.componentLabelText} · '
                                '${event.transition.label}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700),
                              ),
                              Text(
                                event.fault.detail.isEmpty
                                    ? event.fault.faultCode
                                    : event.fault.detail,
                                style: const TextStyle(
                                    color: VicaColors.muted, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatTime(event.receivedAt),
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
