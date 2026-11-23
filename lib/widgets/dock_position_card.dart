import 'package:flutter/material.dart';

import '../models/dock_state.dart';
import 'vica_ui.dart';

/// '지도에서 지정'이 어디까지 왔는가(목업 89·90·90′).
enum DockPickStage {
  /// 지정하는 중이 아닙니다.
  none,

  /// 1 / 2 — 도크 구조물을 누를 차례
  dock,

  /// 2 / 2 — 도크 앞쪽을 누를 차례
  front,

  /// 두 점을 다 눌렀습니다 — 도크 앞 1 m 지점 미리보기
  preview,
}

class DockPositionCard extends StatelessWidget {
  const DockPositionCard({
    super.key,
    required this.spot,
    required this.busy,
    required this.canSendRobot,
    required this.blockedReason,
    required this.onSave,
    required this.onTryDock,
    required this.onDelete,
    this.onStartMapPick,
    this.pickStage = DockPickStage.none,
    this.onPickAgain,
    this.onPickCancel,
    this.onPickSave,
    this.locked = false,
  });

  final DockSpot? spot;
  final bool busy;

  /// 보고 있는 지도가 주행 지도가 아니라 도크를 다룰 수 없습니다 — 버튼을 전부 잠급니다.
  final bool locked;

  /// 로봇을 움직여도 되는가(도킹해 보기). 저장은 움직이지 않아 막지 않습니다.
  final bool canSendRobot;
  final String blockedReason;

  /// '도크 인식해서 저장'
  final VoidCallback onSave;
  final VoidCallback onTryDock;
  final VoidCallback onDelete;

  /// '지도에서 지정' — 1 / 2 로 들어갑니다.
  final VoidCallback? onStartMapPick;

  final DockPickStage pickStage;

  /// '다시 지정' — 1 / 2 로 돌아갑니다.
  final VoidCallback? onPickAgain;
  final VoidCallback? onPickCancel;

  /// '이 자리로 저장'
  final VoidCallback? onPickSave;

  /// 버튼을 누를 수 없는가 — 일하는 중이거나 다른 지도를 보고 있습니다.
  bool get _off => busy || locked;

  @override
  Widget build(BuildContext context) {
    if (pickStage != DockPickStage.none) {
      return _pickBody(context);
    }
    final saved = spot;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: saved == null ? _emptyBody() : _savedBody(saved),
    );
  }

  List<Widget> _emptyBody() {
    return [
      Text(
        vicaKeepWords('충전하러 들어가는 자리 · 지도당 1개'),
        style: const TextStyle(color: VicaColors.muted, fontSize: 13),
      ),
      const SizedBox(height: 12),
      _Box(
        icon: Icons.info_outline,
        text: vicaKeepWords('미지정 · 도킹 시작 버튼이 나오지 않습니다.'),
      ),
      const SizedBox(height: 12),
      _Method(
        title: '도크 직접 인식',
        body: '정확히 세울 필요 없습니다. 도크를 보고만 있으면 라이다로 찾아 자동으로 맞춥니다.',
        button: PressScale(
            child: FilledButton(
          onPressed: _off ? null : onSave,
          child: Text(busy ? '도크 찾는 중…' : '도크 인식해서 저장'),
        )),
      ),
      const SizedBox(height: 12),
      _Method(
        title: '지도에서 도크 지정',
        body: '지도에서 도크와 도크 앞쪽을 차례로 누르면 도크 앞 1 m 지점을 자동으로 잡습니다.',
        button: PressScale(
            child: OutlinedButton(
          onPressed: _off ? null : onStartMapPick,
          style:
              OutlinedButton.styleFrom(foregroundColor: VicaColors.primaryDark),
          child: const Text('지도에서 지정'),
        )),
      ),
    ];
  }

  List<Widget> _savedBody(DockSpot saved) {
    final refined = saved.refinedText;
    return [
      _Summary(spot: saved),
      if (!saved.visitedOk) ...[
        const SizedBox(height: 12),
        _Box(
          icon: Icons.error_outline,
          text: saved.mapPicked
              ? vicaKeepWords('처음 도킹 시 로봇이 도크 앞 1 m로 가서 라이다로 도크를 찾아 들어갑니다. '
                  '성공하면 라이다로 잰 값으로 도크 위치를 고쳐 저장합니다.')
              : vicaKeepWords('아직 도킹해 보지 않음 · 아래 도킹해 보기'),
          warn: true,
        ),
      ] else if (refined != null) ...[
        const SizedBox(height: 12),
        _Box(
            icon: Icons.check_circle_outline,
            text: vicaKeepWords(refined),
            sunken: true),
      ],
      const SizedBox(height: 14),
      if (!canSendRobot && blockedReason.isNotEmpty) ...[
        _Box(icon: Icons.lock_outline, text: vicaKeepWords(blockedReason)),
        const SizedBox(height: 12),
      ],
      PressScale(
          child: FilledButton.icon(
        onPressed: _off || !canSendRobot ? null : onTryDock,
        icon: const Icon(Icons.power),
        label: Text(saved.visitedOk ? '도킹해 보기(다시 확인)' : '도킹해 보기'),
      )),
      const SizedBox(height: 10),
      _Pair(
        left: _HalfButton(
          label: busy ? '도크 찾는 중…' : '도크 인식해서 다시 저장',
          onPressed: _off ? null : onSave,
        ),
        right: _HalfButton(
          label: '지도에서 다시 지정',
          onPressed: _off ? null : onStartMapPick,
        ),
      ),
      const SizedBox(height: 10),
      PressScale(
          child: OutlinedButton.icon(
        onPressed: _off ? null : onDelete,
        icon: const Icon(Icons.delete_outline, size: 18),
        label: const Text('도크 위치 지우기'),
      )),
    ];
  }

  Widget _pickBody(BuildContext context) {
    final preview = pickStage == DockPickStage.preview;
    final again = PressScale(
        child: OutlinedButton(
      onPressed: busy ? null : onPickAgain,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      child: Text(vicaKeepWords('다시 지정'), textAlign: TextAlign.center),
    ));
    final cancel = PressScale(
        child: OutlinedButton(
      onPressed: busy ? null : onPickCancel,
      child: const Text('취소'),
    ));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          vicaKeepWords('도크 위치 — 지도에서 지정'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 10),
        _PickBanner(
          step: switch (pickStage) {
            DockPickStage.dock => '1 / 2',
            DockPickStage.front => '2 / 2',
            _ => null,
          },
          text: switch (pickStage) {
            DockPickStage.dock => '지도에서 도크 구조물을 눌러 주세요.',
            DockPickStage.front => '도크 앞쪽을 눌러 주세요.',
            _ => '도크 앞 1 m 지점을 자동으로 잡았습니다.',
          },
        ),
        if (preview) ...[
          const SizedBox(height: 10),
          Text(
            vicaKeepWords('방향은 두 번째로 누른 쪽입니다. 처음 도킹 시 라이다로 다시 정확히 맞춥니다.'),
            style: const TextStyle(
                color: VicaColors.muted, fontSize: 12, height: 1.5),
          ),
        ],
        const SizedBox(height: 12),
        switch (pickStage) {
          DockPickStage.dock => cancel,
          DockPickStage.front => _Pair(left: again, right: cancel, gap: 10),
          _ => _Pair(
              left: again,
              right: PressScale(
                  child: FilledButton(
                onPressed: _off ? null : onPickSave,
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                child: Text(vicaKeepWords('이 자리로 저장'),
                    textAlign: TextAlign.center),
              )),
              gap: 10,
            ),
        },
      ],
    );
  }
}

/// 저장 방법 하나 — 굵은 제목 · 설명 · 버튼(목업 84 의 묶음).
class _Method extends StatelessWidget {
  const _Method(
      {required this.title, required this.body, required this.button});

  final String title;
  final String body;
  final Widget button;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1, color: VicaColors.border),
        const SizedBox(height: 10),
        Text(
          vicaKeepWords(title),
          style: const TextStyle(
            color: VicaColors.text,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          vicaKeepWords(body),
          style: const TextStyle(
              color: VicaColors.muted, fontSize: 12, height: 1.5),
        ),
        const SizedBox(height: 8),
        button,
      ],
    );
  }
}

/// 두 버튼을 한 줄에 반씩 놓고 높이를 맞춥니다. 한쪽 글자만 두 줄로 접혀도 나란합니다.
class _Pair extends StatelessWidget {
  const _Pair({required this.left, required this.right, this.gap = 8});

  final Widget left;
  final Widget right;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: left),
          SizedBox(width: gap),
          Expanded(child: right),
        ],
      ),
    );
  }
}

/// 한 줄에 반씩 놓는 테두리 버튼. 글자가 길어 좌우 여백을 줄이고 띄어쓰기에서만 접습니다.
class _HalfButton extends StatelessWidget {
  const _HalfButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return PressScale(
        child: OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: VicaColors.primaryDark,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
      child: Text(vicaKeepWords(label), textAlign: TextAlign.center),
    ));
  }
}

/// 지도에서 지정하는 동안의 어두운 안내 띠 — 작은 '1 / 2' 와 지금 할 일.
class _PickBanner extends StatelessWidget {
  const _PickBanner({required this.step, required this.text});

  final String? step;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: VicaColors.text,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (step != null) ...[
            Text(
              step!,
              style: const TextStyle(color: Color(0xFFD9D5CC), fontSize: 12),
            ),
            const SizedBox(height: 4),
          ],
          Text(
            vicaKeepWords(text),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.spot});

  final DockSpot spot;

  @override
  Widget build(BuildContext context) {
    String f(double v, int digits) =>
        v.toStringAsFixed(digits).replaceFirst('-', '−');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: VicaColors.accentTint,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            vicaKeepWords('도크 앞 1 m  x ${f(spot.stagingX, 2)}   '
                'y ${f(spot.stagingY, 2)}   '
                '방향 ${f(spot.yawDeg, 0)}°'),
            style: const TextStyle(
              color: VicaColors.muted,
              fontSize: 13,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  spot.visitedOk ? Icons.check_circle : Icons.error_outline,
                  size: 14,
                  color: spot.visitedOk ? VicaColors.green : VicaColors.warning,
                ),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  vicaKeepWords(spot.statusLine),
                  style: const TextStyle(color: VicaColors.muted, fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({
    required this.icon,
    required this.text,
    this.warn = false,
    this.sunken = false,
  });

  final IconData icon;
  final String text;
  final bool warn;

  /// 회색 칸(목업 91 '도킹했습니다. …'). 경고도 안내도 아닌 지난 일의 기록입니다.
  final bool sunken;

  @override
  Widget build(BuildContext context) {
    final color = warn
        ? VicaColors.warning
        : sunken
            ? VicaColors.text
            : VicaColors.muted;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: warn
            ? VicaColors.warning.withValues(alpha: 0.12)
            : sunken
                ? VicaColors.background
                : VicaColors.accentTint,
        borderRadius: BorderRadius.circular(9),
        border: warn
            ? Border.all(color: VicaColors.warning.withValues(alpha: 0.35))
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: warn ? color : VicaColors.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(color: color, fontSize: 12.5, height: 1.5)),
          ),
        ],
      ),
    );
  }
}
