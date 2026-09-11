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
