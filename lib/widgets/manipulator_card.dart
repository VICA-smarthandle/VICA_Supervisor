// 물류 배송 화면의 '매니퓰레이터' 칸입니다(2026-11-25, 목업 112).
//
// [동작] 하나로 나노 로봇팔을 한 번 움직이고(/app/arm_demo → 중계 → 나노 /arm/demo),
// 응답 문장을 그대로 한 줄 남깁니다. 2026-11-25 사용자: "최대한 심플하게".
// 응답에 '홈 복귀 실패'가 있을 때만 [홈으로]가 보입니다(사용자 A안).
// 힘 빼기는 앱에 두지 않습니다 — 펴진 팔은 힘을 빼면 떨어집니다(현장에서 받친 채로만).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/supervisor_provider.dart';
import 'vica_ui.dart';

/// 나노 문장 중 사람이 팔을 봐야 하는 경우. arm_service.py safe_home()·estop_home() 의 꼬리입니다.
const String kManipulatorStuckMark = '홈 복귀 실패';

class ManipulatorCard extends StatelessWidget {
  const ManipulatorCard({super.key});

  @override
  Widget build(BuildContext context) {
    final supervisor = context.watch<SupervisorProvider>();
    final busy = supervisor.manipulatorBusy;
    final last = supervisor.manipulatorResult;
    final stuck = last != null && !last.ok && last.message.contains(kManipulatorStuckMark);

    return VicaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('매니퓰레이터', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: busy ? null : supervisor.runManipulator,
            icon: busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                : const Icon(Icons.play_arrow),
            label: Text(busy ? '동작 중…' : '동작'),
          ),
          if (last != null) ...[
            const SizedBox(height: 10),
            _ResultLine(result: last, stuck: stuck),
          ],
          if (stuck) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: busy ? null : supervisor.homeManipulator,
              icon: const Icon(Icons.home_outlined),
              label: const Text('홈으로'),
            ),
            const SizedBox(height: 6),
            const Text(
              '홈으로도 실패하면 현장에서 팔을 받친 뒤 힘 빼기(앱에서는 안 됨)',
              style: TextStyle(color: VicaColors.muted, fontSize: 12.5, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }
}

/// 마지막 응답 한 줄. 성공 초록, 홈 복귀 실패 빨강, 그 밖 노랑.
class _ResultLine extends StatelessWidget {
  const _ResultLine({required this.result, required this.stuck});

  final ManipulatorResult result;
  final bool stuck;

  @override
  Widget build(BuildContext context) {
    final color = result.ok
        ? VicaColors.green
        : stuck
            ? VicaColors.red
            : VicaColors.warning;
    final at = result.at;
    final time = '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: '$time ', style: const TextStyle(fontWeight: FontWeight.w700)),
          TextSpan(text: result.message),
        ]),
        style: const TextStyle(color: VicaColors.text, fontSize: 13, height: 1.5),
      ),
    );
  }
}
