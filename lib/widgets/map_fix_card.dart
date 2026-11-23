import 'package:flutter/material.dart';

import '../models/map_fix.dart';
import 'vica_ui.dart';

const kMapFixWordReady = '가능';
const kMapFixWordDriving = '주행 중';
const kMapFixWordOffline = '오프라인';
const kMapFixWordUnknown = '확인 불가';

/// 미션이 쉬는 상태(dialog_state). 이 밖이면 노드가 지도 수정을 잠급니다 — 노드의
const kMapFixIdleDialogStates = {
  '',
  'idle',
  'none',
  'arrived',
  'failed',
  'estopped'
};

/// 미션이 켜져 있어 미션은 옛 지도를 계속 쓸 때 끝 알림에 덧붙이는 말(2026-11-19 사용자 — 목업 99).
const kMapFixMissionStaleText =
    'Mission Manager에는 적용되지 않았습니다.\n주행을 껐다 켜면 적용됩니다.';

/// 칸 설명 줄(2026-11-19 사용자 수정 — 목업 94).
const kMapFixCardDescription = '선택한 곳을 지우거나 다시 스캔합니다';

/// 현재 지도가 아닌 지도를 보고 있을 때(부분 스캔만 꺼짐, 목업 94 ④).
const kMapFixNotCurrentMapText = '현재 지도가 아니면 부분 지우기만 가능합니다.';

/// 로봇 상태를 못 받아 잠겼을 때(목업 94 ③).
const kMapFixNoStatusText = '로봇 상태를 받지 못했습니다.';

/// 칸 머리에 보일 상태 단어. 아직 로봇에 묻지 않았으면 ''(표시 없음)입니다.
String mapFixStateWord({
  required bool connected,
  required MapFixStatus? status,
  bool driving = false,
}) {
  if (!connected) {
    return kMapFixWordOffline;
  }
  if (driving || status?.lock == 'busy_driving') {
    return kMapFixWordDriving;
  }
  if (status == null) {
    return '';
  }
  return status.locked ? kMapFixWordUnknown : kMapFixWordReady;
}

Color mapFixStateColor(String word) => switch (word) {
      kMapFixWordReady => VicaColors.green,
      kMapFixWordOffline => VicaColors.red,
      _ => VicaColors.muted,
    };

/// 수정이 끝났을 때의 알림 문구.
String mapFixDoneMessage(MapFixResult result, {String done = '지도를 수정했습니다.'}) {
  final before = result.scoreBefore;
  final after = result.scoreAfter;
  final String first;
  if (result.applied) {
    first = before != null && after != null
        ? '$done 위치 맞춤 ${mapFixPercent(before)} → ${mapFixPercent(after)}'
        : done;
  } else {
    first = result.message.isEmpty ? done : '$done ${result.message}';
  }
  return result.missionStale ? '$first\n$kMapFixMissionStaleText' : first;
}

class MapFixCard extends StatelessWidget {
  const MapFixCard({
    super.key,
    required this.connected,
    required this.status,
    required this.onErase,
    required this.onScan,
    required this.onUndo,
    this.driving = false,
    this.busy = false,
    this.note = '',
  });

  final bool connected;

  /// 로봇의 마지막 답(잠금·최근 수정). 아직 못 받았으면 null 이고 버튼이 꺼집니다.
  final MapFixStatus? status;

  /// 로봇이 목적지를 쥐고 있는가(/robot_status). true 면 노드에 다시 묻지 않고도 잠급니다.
  final bool driving;

  /// 요청을 보내고 답을 기다리는 중인가. 두 번 누르지 못하게 버튼을 끕니다.
  final bool busy;

  /// 마지막 요청이 실패했을 때 로봇이 보낸 문구.
  final String note;

  final VoidCallback onErase;
  final VoidCallback onScan;
  final VoidCallback onUndo;

  bool get _canEdit =>
      connected && !driving && !busy && status != null && !status!.locked;

  @override
  Widget build(BuildContext context) {
    final history = status?.history ?? const <MapFixHistoryEntry>[];
    final notDriveMap = status != null && !status!.isDriveMap;
    final noStatus = status?.lock == 'no_status';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          vicaKeepWords(kMapFixCardDescription),
          style: const TextStyle(
            fontSize: 13,
            color: VicaColors.muted,
            height: 1.5,
          ),
        ),
        for (final (show, text) in [
          (notDriveMap, kMapFixNotCurrentMapText),
          (noStatus, kMapFixNoStatusText),
        ])
          if (show) ...[
            const SizedBox(height: 6),
            Text(
              vicaKeepWords(text),
              style: const TextStyle(
                fontSize: 12.5,
                color: VicaColors.muted,
                height: 1.45,
              ),
            ),
          ],
        if (note.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            vicaKeepWords(vicaBreakAtSentences(note)),
            style: const TextStyle(
              fontSize: 12.5,
              color: VicaColors.red,
              height: 1.45,
            ),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: PressScale(
                child: OutlinedButton.icon(
                  onPressed: _canEdit ? onErase : null,
                  icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                  label: const Text('지우기'),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: PressScale(
                child: FilledButton.icon(
                  onPressed: (_canEdit && status!.canScan) ? onScan : null,
                  icon: const Icon(Icons.radar, size: 18),
                  label: const Text('부분 스캔'),
                ),
              ),
            ),
          ],
        ),
        if (history.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text(
            '최근 수정',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: VicaColors.muted,
            ),
          ),
          const SizedBox(height: 4),
          for (var i = 0; i < history.length; i++)
            _historyRow(history[i], newest: i == 0),
        ],
      ],
    );
  }

  Widget _historyRow(MapFixHistoryEntry entry, {required bool newest}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: VicaColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vicaKeepWords(entry.title),
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  vicaKeepWords(entry.detail),
                  style: const TextStyle(
                    fontSize: 12,
                    color: VicaColors.muted,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          if (newest) ...[
            const SizedBox(width: 8),
            PressScale(
              child: OutlinedButton(
                onPressed: _canEdit ? onUndo : null,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: const Text('되돌리기'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 지도 수정 화면의 고르기 단추 하나(범위 '1 m'·'2 m'·'3 m', 지우기의 '구역 표시'·'지도 이동').
class MapFixChoiceButton extends StatelessWidget {
  const MapFixChoiceButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.width,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: selected ? VicaColors.accentTint : VicaColors.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: selected ? VicaColors.primary : VicaColors.borderStrong,
              width: selected ? 2 : 1,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: width,
              height: 44,
              child: Center(
                child: Text(
                  vicaKeepWords(label),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                    color: selected ? VicaColors.primaryDark : VicaColors.text,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 지도 아래의 안내(옅은 청록 상자). 줄바꿈(\n)은 그대로 두고 줄 안에서는 어절 단위로 접힙니다.
class MapFixHint extends StatelessWidget {
  const MapFixHint(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: VicaColors.accentTint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text.split('\n').map(vicaKeepWords).join('\n'),
        style: const TextStyle(
          fontSize: 12.5,
          height: 1.45,
          color: VicaColors.primaryDark,
        ),
      ),
    );
  }
}
