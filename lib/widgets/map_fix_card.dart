// 이 파일은 지도 설정 화면의 '지도 수정' 칸 내용을 그립니다(목업 75·82).
//
// 지도를 그린 뒤 고정 장애물이 바뀐 곳만 고칩니다 — 사각형으로 지우기, 로봇을 세워 두고
// 라이다로 다시 스캔하기(부분 스캔), 마지막 수정 되돌리기. 수정할 수 있는지는 젯슨의
// map_fix_node 가 정하고(주행·미션 중에는 잠김), 이 칸은 그 답을 보여 주기만 합니다.
import 'package:flutter/material.dart';

import '../models/map_fix.dart';
import 'vica_ui.dart';

const kMapFixWordReady = '가능';
const kMapFixWordDriving = '주행 중';
const kMapFixWordOffline = '오프라인';
const kMapFixWordUnknown = '확인 불가';

/// 미션이 켜져 있어 미션은 옛 지도를 계속 쓸 때 끝 알림에 덧붙이는 말(2026-11-19 사용자 — 목업 99).
///
/// 두 문장을 줄로 나눕니다. 뒤 문장이 짧아 [vicaBreakAtSentences] 가 앞 문장에 붙여 버리므로
/// 줄바꿈을 글자에 넣어 둡니다.
const kMapFixMissionStaleText =
    'Mission Manager에는 적용되지 않았습니다.\n주행을 껐다 켜면 적용됩니다.';

/// 칸 설명 줄(2026-11-19 사용자 수정 — 목업 94).
const kMapFixCardDescription = '선택한 곳을 지우거나 다시 스캔합니다';

/// 현재 지도가 아닌 지도를 보고 있을 때(부분 스캔만 꺼짐, 목업 94 ④).
const kMapFixNotCurrentMapText = '현재 지도가 아니면 부분 지우기만 가능합니다.';

/// 로봇 상태를 못 받아 잠겼을 때(목업 94 ③).
const kMapFixNoStatusText = '로봇 상태를 받지 못했습니다.';

/// 칸 머리에 보일 상태 단어. 아직 로봇에 묻지 않았으면 ''(표시 없음)입니다.
///
/// [driving] 은 앱이 이미 받고 있는 /robot_status 로 본 값입니다(목적지를 쥐고 있음). 잠금의
/// 주인은 노드지만, 칸을 연 뒤 주행이 시작된 것을 다시 묻지 않고도 바로 보이게 합니다.
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
///
/// Nav2 가 고친 지도를 읽었으면 [done] (부분 스캔이면 뒤에 '위치 맞춤 62 % → 91 %'),
/// 파일만 바뀌었으면 [done] 뒤에 로봇이 보낸 사유를 붙입니다. 미션이 켜져 있으면
/// 줄을 바꿔 [kMapFixMissionStaleText] 를 덧붙입니다.
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
    // 잠기지 않았는데 부분 스캔만 안 되면 현재(주행) 지도가 아닌 지도를 보고 있는 것입니다.
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
            // Expanded 가 없으면 버튼 테마의 최소 폭(무한대) 때문에 배치 오류가 납니다.
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
          // 되돌리기는 가장 최근 수정에만 있습니다 — 최근 것부터 차례로만 되돌립니다.
          if (newest) ...[
            const SizedBox(width: 8),
            PressScale(
              child: OutlinedButton(
                onPressed: _canEdit ? onUndo : null,
                // 버튼 테마의 최소 폭이 무한대(app.dart)라 줄 안에서는 폭을 풀어 줍니다.
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
///
/// 고른 것은 청록 테두리·옅은 청록 바탕, 아닌 것은 흰 바탕입니다(목업 78·96). [width] 가 없으면
/// 주어진 폭을 다 씁니다.
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
