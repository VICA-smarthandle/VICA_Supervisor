// 이 파일은 Nav2 초기 위치를 앱에서 잡는 3단계 화면입니다.
//
// **왜 필요한가.** Nav2 를 켜면 AMCL 은 자기가 어디 있는지 모릅니다. 지금까지는
// 젯슨 화면의 RViz 에서 2D Pose Estimate 로 찍어 줬습니다. 관리자 앱만 들고
// 현장에 나가면 그 일을 할 방법이 없습니다.
//
// **왜 확인과 확정을 나눴는가.** /initialpose 를 발행하는 순간 되돌릴 수
// 없습니다. 잘못 찍으면 로봇이 엉뚱한 곳에 있다고 믿고 주행을 시작합니다.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_settings.dart';
import '../models/pose_check_result.dart';
import 'vica_ui.dart';

/// 사람이 고르는 방향입니다. **지도 그림 기준**이지 로봇 몸 기준이 아닙니다.
///
/// 관리자는 지도 그림을 보고 있지 로봇에 붙어 있지 않습니다. 로봇 기준으로
/// 말하면 머릿속에서 한 번 돌려야 합니다.
enum PoseDirection {
  right('오른쪽', Icons.east),
  up('위', Icons.north),
  left('왼쪽', Icons.west),
  down('아래', Icons.south);

  const PoseDirection(this.label, this.icon);

  final String label;
  final IconData icon;

  /// 화면 방향을 ROS yaw(rad)로 바꿉니다.
  ///
  /// 지도 이미지는 flipMapY 가 true 면 위아래가 뒤집혀 그려집니다. 그때 화면의
  /// '위'는 ROS +y 지만, false 면 -y 입니다. 여기서 갈라 두지 않으면 위아래
  /// 버튼이 정확히 반대로 동작합니다.
  double yawFor(AppSettings settings) {
    final upIsPlusY = settings.flipMapY;
    switch (this) {
      case PoseDirection.right:
        return 0;
      case PoseDirection.left:
        return math.pi;
      case PoseDirection.up:
        return upIsPlusY ? math.pi / 2 : -math.pi / 2;
      case PoseDirection.down:
        return upIsPlusY ? -math.pi / 2 : math.pi / 2;
    }
  }
}

class InitialPoseCard extends StatelessWidget {
  const InitialPoseCard({
    super.key,
    required this.picked,
    required this.direction,
    required this.result,
    required this.busy,
    required this.onDirection,
    required this.onCheck,
    required this.onCommit,
    required this.onReset,
    required this.onClose,
  });

  /// 지도에서 짚은 자리(ROS 좌표)입니다. 아직 안 짚었으면 null 입니다.
  final Offset? picked;
  final PoseDirection? direction;
  final PoseCheckResult? result;
  final bool busy;
  final ValueChanged<PoseDirection?> onDirection;
  final VoidCallback onCheck;
  final VoidCallback onCommit;
  final VoidCallback onReset;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final spot = picked;
    return VicaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.my_location,
                  size: 20, color: VicaColors.primaryDark),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '초기 위치 잡기',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton(
                onPressed: busy ? null : onClose,
                child: const Text('닫기'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Nav2 를 켜면 로봇은 자기가 어디 있는지 모릅니다. 지도에서 지금 로봇이 서 있는 자리를 짚어 주세요.',
            style: TextStyle(color: VicaColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 16),
          _step(
            context,
            number: '1',
            title: spot == null
                ? '지도를 눌러 로봇이 있는 자리를 짚으세요'
                : '짚은 자리 (${spot.dx.toStringAsFixed(2)}, ${spot.dy.toStringAsFixed(2)})',
            done: spot != null,
          ),
          const SizedBox(height: 12),
          _step(
            context,
            number: '2',
            title: '로봇이 보는 쪽 (지도 그림 기준)',
            done: direction != null,
          ),
          const SizedBox(height: 8),
          // 4칸이면 충분합니다. 90도 단위 입력의 최대 오차 45도가 노드의 탐색
          // 창(+-45도)과 딱 맞물려 빈틈이 없습니다. 정밀한 각도는 노드가 1도
          // 간격으로 찾으므로 손가락으로 돌릴 필요가 없습니다.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...PoseDirection.values.map(
                (value) => ChoiceChip(
                  selected: direction == value,
                  avatar: Icon(value.icon, size: 18),
                  label: Text(value.label),
                  onSelected: busy ? null : (_) => onDirection(value),
                ),
              ),
              ChoiceChip(
                selected: direction == null,
                avatar: const Icon(Icons.help_outline, size: 18),
                label: const Text('모르겠음'),
                onSelected: busy ? null : (_) => onDirection(null),
              ),
            ],
          ),
          if (direction == null) ...[
            const SizedBox(height: 6),
            const Text(
              '방향을 모르면 360° 전부를 훑습니다. 느리고, 앞뒤가 같은 복도에서는 뒤집힌 자세와 구분하지 못합니다.',
              style: TextStyle(color: VicaColors.muted, fontSize: 12),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: spot == null || busy ? null : onCheck,
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.search),
            label: Text(busy ? '확인 중…' : '여기가 맞는지 확인'),
          ),
          if (result != null) ...[
            const SizedBox(height: 16),
            _Score(result: result!),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    // 확정 가능 여부는 **노드가 판정합니다.** 앱은 그 결과를
                    // 그대로 씁니다. 앱에서 다시 계산하면 두 기준이 갈립니다.
                    onPressed: result!.ok && !busy ? onCommit : null,
                    icon: const Icon(Icons.check),
                    label: const Text('이 위치로 확정'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : onReset,
                    icon: const Icon(Icons.refresh),
                    label: const Text('다시 짚기'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static Widget _step(
    BuildContext context, {
    required String number,
    required String title,
    required bool done,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? VicaColors.green : VicaColors.softBlue,
          ),
          child: done
              ? const Icon(Icons.check, size: 14, color: Colors.white)
              : Text(
                  number,
                  style: const TextStyle(
                    fontSize: 12,
                    color: VicaColors.primaryDark,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(title, style: const TextStyle(fontSize: 14)),
        ),
      ],
    );
  }
}

class _Score extends StatelessWidget {
  const _Score({required this.result});

  final PoseCheckResult result;

  @override
  Widget build(BuildContext context) {
    final color = switch (result.grade) {
      PoseGrade.good => VicaColors.green,
      PoseGrade.weak => Colors.orange,
      PoseGrade.bad => VicaColors.red,
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 68,
            height: 68,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 68,
                  height: 68,
                  child: CircularProgressIndicator(
                    value: (result.score / 100).clamp(0.0, 1.0),
                    strokeWidth: 6,
                    color: color,
                    backgroundColor: color.withValues(alpha: 0.15),
                  ),
                ),
                Text(
                  '${result.score.round()}%',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 문구는 노드가 만듭니다. 숫자가 아니라 **다음에 할 행동**으로
                // 씁니다 -- 관리자는 % 의 의미를 모릅니다.
                Text(
                  result.message,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  result.movedSummary,
                  style: const TextStyle(fontSize: 13, color: VicaColors.text),
                ),
                const SizedBox(height: 4),
                Text(
                  '유효 빔 ${result.usedBeams} / ${result.totalBeams}'
                  ' · 2등 차이 ${result.margin.round()} %p',
                  style: const TextStyle(fontSize: 12, color: VicaColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
