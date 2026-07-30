// 이 파일은 대시보드 상단에 로봇의 최고 등급 결함을 한 줄로 보여주는 배너입니다.
//
// 상세는 시스템 진단 화면이 담당합니다. 여기서는 "지금 무엇이 가장 심각한가"만 알리고
// 탭하면 그 화면으로 보냅니다.
//
// 결함이 없거나 상태를 아직 못 받았으면 아무것도 그리지 않습니다. 빈 배너가 자리를
// 차지하면 정상 상태 화면이 지저분해집니다.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../providers/supervisor_provider.dart';
import 'vica_ui.dart';

class HealthBanner extends StatelessWidget {
  const HealthBanner({super.key, this.onTap});

  /// 탭하면 시스템 진단 화면으로 보냅니다. null이면 탭을 받지 않습니다.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final supervisor = context.watch<SupervisorProvider>();
    final settings = context.watch<SettingsProvider>().settings;
    final health = supervisor.health;

    if (health == null) {
      return const SizedBox.shrink();
    }

    // 모니터가 죽은 뒤 마지막 결함을 현재처럼 보여주지 않습니다. 대신 감시가 끊겼다는
    // 사실을 알립니다 — 그것 자체가 관리자가 알아야 할 정보입니다.
    if (health.isStale(Duration(seconds: settings.robotHealthTimeoutSeconds))) {
      return _Banner(
        color: VicaColors.muted,
        icon: Icons.cloud_off_outlined,
        title: '상태 감시 끊김',
        detail: '로봇 상태를 받지 못하고 있습니다. 아래 값은 현재 상태가 아닙니다.',
        onTap: onTap,
      );
    }

    final fault = health.primaryFault;
    if (fault == null) {
      return const SizedBox.shrink();
    }

    return _Banner(
      color: fault.severity.color,
      icon: fault.severity.icon,
      title: '${fault.severity.label} · ${fault.componentLabelText}',
      detail: fault.detail.isEmpty ? fault.faultCode : fault.detail,
      extraCount: health.activeFaultCount - 1,
      onTap: onTap,
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.color,
    required this.icon,
    required this.title,
    required this.detail,
    this.extraCount = 0,
    this.onTap,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String detail;
  final int extraCount;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        detail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (extraCount > 0) ...[
                        const SizedBox(height: 2),
                        Text(
                          '다른 결함 $extraCount건',
                          style: const TextStyle(
                              color: VicaColors.muted, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
                if (onTap != null)
                  const Icon(Icons.chevron_right, color: VicaColors.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
