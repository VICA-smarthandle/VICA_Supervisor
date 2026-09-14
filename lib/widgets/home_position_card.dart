// 이 파일은 지도별 홈 위치를 정하고 확인하는 카드입니다.
//
// **홈은 목적지가 아닙니다.** 사용자가 "홈으로 가줘"라고 말할 수 있는 장소가
// 아니라, 안내가 끝난 뒤 로봇이 스스로 돌아가는 자리입니다. 그래서 장소 목록과
// 따로 관리하고, 홈으로 보내는 것도 관리자만 할 수 있습니다.
//
// **두 가지 지정 방식을 함께 두는 이유.** 서로 다른 축에서 강합니다.
//
//   실제 자리에서   방향이 정확하다. 위치는 AMCL 을 믿어야 한다
//                  (복도에서 앞뒤로 밀려 있어도 점수가 거의 안 깎인다)
//   지도에서 찍기   위치가 사람 의도 그대로다. 방향은 90도 단위로 거칠다
//
// 그래서 경쟁이 아니라 한 흐름으로 잇습니다 —
// 지도에서 대충 찍고 → 가보고 → 도착한 자리에서 정밀하게 확정.
import 'package:flutter/material.dart';

import '../models/home_position.dart';
import '../models/pose_check_result.dart';
import 'initial_pose_card.dart' show PoseDirection;
import 'teleop_pad.dart';
import 'vica_ui.dart';

/// '아직 확인 안 됨' 경고에 쓰는 색입니다.
///
/// VicaColors 에 경고색이 없습니다. 여기서만 쓰는 값이라 전역 팔레트를 늘리지
/// 않고 파일 안에 둡니다. 다른 화면에서도 필요해지면 그때 옮깁니다.
const Color _warnColor = Color(0xFFA8730F);

/// 카드가 지금 무엇을 하고 있는가.
enum HomeCardMode {
  /// 저장된 홈을 보여주는 평상시 상태입니다.
  idle,

  /// 지도를 눌러 좌표를 찍는 중입니다.
  picking,

  /// 로봇이 선 자리를 채점해 확인하는 중입니다.
  standing,
}

class HomePositionCard extends StatelessWidget {
  const HomePositionCard({
    super.key,
    required this.home,
    required this.mode,
    required this.busy,
    required this.picked,
    required this.direction,
    required this.standingResult,
    required this.canSendRobot,
    required this.blockedReason,
    required this.onStartPicking,
    required this.onStartStanding,
    required this.onDirection,
    required this.onCheckStanding,
    required this.onSave,
    required this.onCancel,
    required this.onGoHome,
    required this.onDelete,
    this.framed = true,
  });

  /// 저장된 홈. 아직 지정하지 않았으면 null 이며 오류가 아닙니다.
  final HomePosition? home;

  final HomeCardMode mode;
  final bool busy;

  /// 지도에서 짚은 자리(ROS 좌표). picking 모드에서만 씁니다.
  final Offset? picked;

  /// 지도 그림 기준 방향. picking 모드에서만 씁니다.
  final PoseDirection? direction;

  /// 로봇이 선 자리를 채점한 결과. standing 모드에서만 씁니다.
  final PoseCheckResult? standingResult;

  /// 로봇을 움직이는 버튼(가보기·끌고 다니기)을 열어도 되는가.
  ///
  /// 판정은 Mission Manager 가 하지만, 아예 못 할 상황에서 버튼을 눌러
  /// 거부 메시지를 받는 것보다 잠가 두고 이유를 보여주는 편이 낫습니다.
  final bool canSendRobot;

  /// 잠근 이유. [canSendRobot] 이 false 일 때만 씁니다.
  final String blockedReason;

  final VoidCallback onStartPicking;
  final VoidCallback onStartStanding;
  final ValueChanged<PoseDirection?> onDirection;
  final VoidCallback onCheckStanding;
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final VoidCallback onGoHome;
  final VoidCallback onDelete;

  /// 스스로 카드 테두리와 제목을 그릴지 여부입니다.
  ///
  /// 접히는 칸(VicaExpandPanel) 안에 넣을 때는 false 로 둡니다. 테두리 안에
  /// 테두리가 또 생기고 제목이 두 번 보입니다.
  final bool framed;

  @override
  Widget build(BuildContext context) {
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 접히는 칸 안에 들어갈 때는 제목을 그리지 않습니다. 칸 머리에 이미
        // '홈 위치'가 적혀 있어 같은 말이 두 번 보입니다.
        if (framed) ...[
          Row(
            children: [
              const Icon(Icons.home_outlined,
                  size: 20, color: VicaColors.primaryDark),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '홈 위치',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (mode != HomeCardMode.idle)
                TextButton(
                  onPressed: busy ? null : onCancel,
                  child: const Text('취소'),
                ),
            ],
          ),
          const SizedBox(height: 4),
        ],
        const Text(
          '안내가 끝나면 로봇이 이 자리로 돌아옵니다. 지도당 하나만 설정 가능합니다.',
          style: TextStyle(color: VicaColors.muted, fontSize: 13),
        ),
        const SizedBox(height: 14),
        ..._body(context),
      ],
    );
    return framed ? VicaCard(child: body) : body;
  }

  List<Widget> _body(BuildContext context) {
    switch (mode) {
      case HomeCardMode.picking:
        return _pickingBody(context);
      case HomeCardMode.standing:
        return _standingBody(context);
      case HomeCardMode.idle:
        return _idleBody(context);
    }
  }

  // ------------------------------------------------------------------
  // 평상시 — 저장된 홈 보여주기
  // ------------------------------------------------------------------

  List<Widget> _idleBody(BuildContext context) {
    final saved = home;
    if (saved == null) {
      return [
        const _InfoBox(
          icon: Icons.info_outline,
          text: '아직 지정되지 않았습니다. 지정하지 않아도 안내는 정상 동작하며, 자동 복귀만 꺼집니다.',
        ),
        const SizedBox(height: 14),
        _pickButtons(context),
      ];
    }

    return [
      _SavedHomeSummary(home: saved),
      if (!saved.visitedOk) ...[
        const SizedBox(height: 12),
        const _WarnBox(
          text: '아직 가 본 적이 없습니다. 좌표를 정한 것과 그 자리에 실제로 갈 수 있는 것은 '
              '다른 사실입니다. 아래 \'홈으로 가보기\'로 한 번 확인하세요.',
        ),
      ],
      const SizedBox(height: 14),
      if (!canSendRobot && blockedReason.isNotEmpty) ...[
        _InfoBox(icon: Icons.lock_outline, text: blockedReason),
        const SizedBox(height: 12),
      ],
      FilledButton.icon(
        onPressed: busy || !canSendRobot ? null : onGoHome,
        icon: const Icon(Icons.navigation_outlined),
        label: Text(saved.visitedOk ? '홈으로 주행(다시 확인)' : '홈으로 주행'),
      ),
      const SizedBox(height: 10),
      _pickButtons(context, relabel: true),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: busy ? null : onDelete,
        icon: const Icon(Icons.delete_outline, size: 18),
        label: const Text('홈 지우기'),
      ),
    ];
  }

  Widget _pickButtons(BuildContext context, {bool relabel = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: busy ? null : onStartPicking,
          icon: const Icon(Icons.touch_app_outlined, size: 18),
          label: Text(relabel ? '지도에서 다시 선택' : '지도에서 선택'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: busy ? null : onStartStanding,
          icon: const Icon(Icons.adjust, size: 18),
          label: Text(relabel ? '지금 위치로 갱신' : '지금 로봇이 있는 위치로'),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------
  // 지도에서 찍기
  // ------------------------------------------------------------------

  List<Widget> _pickingBody(BuildContext context) {
    final spot = picked;
    return [
      const _InfoBox(
        icon: Icons.touch_app_outlined,
        text: '지도에서 홈 위치를 선택하고, 로봇이 바라볼 방향을 고르세요. '
            '저장한 뒤 \'홈으로 주행\'으로 실제로 갈 수 있는지 확인합니다.',
      ),
      const SizedBox(height: 14),
      _Step(
        number: '1',
        title: spot == null
            ? '지도에서 홈 위치를 선택하세요'
            : '선택한 위치 (${spot.dx.toStringAsFixed(2)}, ${spot.dy.toStringAsFixed(2)})',
        done: spot != null,
      ),
      const SizedBox(height: 12),
      _Step(
        number: '2',
        title: '로봇이 바라볼 방향 (지도 그림 기준)',
        done: direction != null,
      ),
      const SizedBox(height: 8),
      _DirectionButtons(
        selected: direction,
        enabled: !busy,
        onSelected: onDirection,
      ),
      const SizedBox(height: 14),
      FilledButton.icon(
        onPressed: busy || spot == null || direction == null ? null : onSave,
        icon: const Icon(Icons.save_outlined),
        label: const Text('이 자리를 홈으로 저장'),
      ),
    ];
  }

  // ------------------------------------------------------------------
  // 로봇이 선 자리로
  // ------------------------------------------------------------------

  List<Widget> _standingBody(BuildContext context) {
    final result = standingResult;
    return [
      const _InfoBox(
        icon: Icons.adjust,
        text: '로봇을 홈으로 쓸 자리에 세운 뒤 확인을 누르세요. 라이다가 보는 것과 지도를 '
            '맞춰 점수를 냅니다. 저장되는 값은 로봇이 선 자리가 아니라 그 채점이 '
            '바로잡은 자세입니다.',
      ),
      const SizedBox(height: 14),
      if (!canSendRobot && blockedReason.isNotEmpty) ...[
        _InfoBox(icon: Icons.lock_outline, text: blockedReason),
        const SizedBox(height: 12),
      ] else ...[
        TeleopPad(enabled: !busy && canSendRobot),
        const SizedBox(height: 12),
      ],
      OutlinedButton.icon(
        onPressed: busy ? null : onCheckStanding,
        icon: const Icon(Icons.search),
        label: Text(result == null ? '여기가 맞는지 확인' : '다시 확인'),
      ),
      if (result != null) ...[
        const SizedBox(height: 12),
        _ScoreBox(result: result),
        const SizedBox(height: 12),
        FilledButton.icon(
          // 확정 가능 여부는 앱이 판정하지 않습니다. 노드가 보낸 ok 를 그대로
          // 씁니다 — 앱에서 다시 계산하면 두 기준이 갈립니다.
          onPressed: busy || !result.ok ? null : onSave,
          icon: const Icon(Icons.save_outlined),
          label: const Text('이 자리를 홈으로 저장'),
        ),
      ],
    ];
  }
}

// ----------------------------------------------------------------------
// 조각들
// ----------------------------------------------------------------------

class _SavedHomeSummary extends StatelessWidget {
  const _SavedHomeSummary({required this.home});

  final HomePosition home;

  @override
  Widget build(BuildContext context) {
    final name = home.label.isEmpty ? '홈' : home.label;
    final saved = home.savedAtLabel;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: VicaColors.softBlue,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (home.hasScore)
                Text(
                  '점수 ${home.score.toStringAsFixed(0)}%',
                  style: const TextStyle(
                    color: VicaColors.primaryDark,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'x ${home.x.toStringAsFixed(2)}   '
            'y ${home.y.toStringAsFixed(2)}   '
            '방향 ${home.yaw.toStringAsFixed(0)}°',
            style: const TextStyle(
              color: VicaColors.muted,
              fontSize: 13,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                home.visitedOk ? Icons.check_circle : Icons.error_outline,
                size: 14,
                color: home.visitedOk ? VicaColors.green : _warnColor,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  home.visitedOk
                      ? '$saved · ${home.source.label} · 가 본 자리'
                      : '$saved · ${home.source.label} · 아직 확인 안 됨',
                  style: const TextStyle(
                    color: VicaColors.muted,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScoreBox extends StatelessWidget {
  const _ScoreBox({required this.result});

  final PoseCheckResult result;

  @override
  Widget build(BuildContext context) {
    final grade = result.grade;
    final color = switch (grade) {
      PoseGrade.good => VicaColors.green,
      PoseGrade.weak => _warnColor,
      PoseGrade.bad => VicaColors.red,
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: VicaColors.softBlue,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${result.score.toStringAsFixed(0)}%',
                style: TextStyle(
                  color: color,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  result.message,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '유효 빔 ${result.usedBeams}/${result.totalBeams} · '
            '2등 차이 ${result.margin.toStringAsFixed(0)} %p · '
            '${(result.movedM * 100).toStringAsFixed(0)} cm, '
            '${result.movedDeg.toStringAsFixed(0)}° 바로잡음',
            style: const TextStyle(color: VicaColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _DirectionButtons extends StatelessWidget {
  const _DirectionButtons({
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final PoseDirection? selected;
  final bool enabled;
  final ValueChanged<PoseDirection?> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: PoseDirection.values.map((direction) {
        return ChoiceChip(
          selected: selected == direction,
          // 체크표시를 끄지 않으면 화살표 아이콘과 겹쳐 둘 다 못 읽는다.
          // 선택 여부는 칩 배경색으로 이미 드러난다. 초기 위치 카드와 같은 방식.
          showCheckmark: false,
          avatar: Icon(direction.icon, size: 18),
          label: Text(direction.label),
          onSelected: enabled ? (_) => onSelected(direction) : null,
        );
      }).toList(),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.title,
    required this.done,
  });

  final String number;
  final String title;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: done ? VicaColors.green : VicaColors.softBlue,
            shape: BoxShape.circle,
          ),
          child: done
              ? const Icon(Icons.check, size: 14, color: Colors.white)
              : Text(
                  number,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: VicaColors.muted,
                  ),
                ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(title, style: const TextStyle(fontSize: 13)),
        ),
      ],
    );
  }
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: VicaColors.softBlue,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: VicaColors.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: VicaColors.muted, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _WarnBox extends StatelessWidget {
  const _WarnBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _warnColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: _warnColor.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 16, color: _warnColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}
