// 이 파일은 앱에서 주행 지도를 바꾸는 화면 조각입니다(2026-11-17 사용자 승인, 목업
// https://claude.ai/artifact/URFB2xvqkfN36QyG11u5NF ①~⑦).
//
// 젯슨에서 지도는 maps/CURRENT_MAP 한 곳이 정하고 Nav2·미션·음성은 켜질 때 한 번 읽습니다. 그래서
// 앱은 모드 노드에 바꿀 지도만 보내고(/vica/mode/map_request), 젯슨이 파일을 쓰고 필요한 유닛을
// 다시 띄웁니다. 주행 중이면 로봇이 멈춰 대기 중이거나 일시정지 중일 때만 됩니다 — 안 되는 이유는
// 모드 상태의 map_change_block 이 알려 줍니다.
//
//   ① DriveMapRow           주행 시트의 '주행 지도' 줄
//   ② showDriveMapPicker    지도 고르기(준비 상태: 레일 · 금지구역 · 목적지 수)
//   ③⑥ DriveMapBanner       원격 주행·지도 설정에서 보는 지도 ≠ 주행 지도일 때 띠
//   ④ changeDriveMap        확인 창(일시정지 중이면 남은 안내·순찰 취소를 알림) → 요청 → ⑤ 진행 화면
//   ⑦ DriveMapMismatchCard  파일만 바뀌고 Nav2 는 옛 지도일 때
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/vica_map.dart';
import '../providers/app_mode_provider.dart';
import '../providers/supervisor_provider.dart';
import '../screens/drive_bringup_screen.dart';
import 'vica_ui.dart';

/// 지도 id 의 사람 이름. 목록에 없으면 id 그대로.
String driveMapName(SupervisorProvider supervisor, String mapId) {
  for (final map in supervisor.maps) {
    if (map.mapId == mapId) {
      return map.mapName;
    }
  }
  return mapId;
}

/// '11-16 20:30 · 레일 · 금지구역 · 목적지 4'. 모르는 칸은 뺍니다.
String driveMapReadiness(VicaMap map) {
  final parts = <String>[];
  final saved = DateTime.tryParse(map.savedAt);
  if (saved != null) {
    String two(int v) => v.toString().padLeft(2, '0');
    parts.add('${two(saved.month)}-${two(saved.day)} ${two(saved.hour)}:${two(saved.minute)}');
  }
  if (map.hasRoute) {
    parts.add('레일');
  }
  if (map.hasKeepout) {
    parts.add('금지구역');
  }
  if (map.destinationCount != null) {
    parts.add('목적지 ${map.destinationCount}');
  }
  return parts.join(' · ');
}

/// 지도를 [mapId] 로 바꿉니다. 주행 중이면 확인을 받고, 다시 띄우는 유닛이 있으면 진행 화면으로 갑니다.
Future<void> changeDriveMap(BuildContext context, String mapId) async {
  final supervisor = context.read<SupervisorProvider>();
  final status = supervisor.modeStatus;
  if (status == null) {
    await showVicaNotice(
      context,
      icon: Icons.help_outline,
      title: '모드 노드 없음',
      body: '로봇의 자동 기동(모드 노드)이 꺼져 있습니다.',
    );
    return;
  }
  final to = driveMapName(supervisor, mapId);
  final fromId = status.driveOn ? status.driveMapId : status.currentMapId;
  final from = driveMapName(supervisor, fromId);
  if (status.driveOn) {
    if (status.mapChangeBlock.isNotEmpty) {
      await showVicaNotice(
        context,
        icon: Icons.block,
        iconColor: VicaColors.warning,
        title: '지금은 못 바꿈',
        body: status.mapChangeBlock,
      );
      return;
    }
    final confirmed = await showVicaConfirm(
      context,
      icon: Icons.map_outlined,
      title: '주행 지도 바꾸기',
      content: _ConfirmContent(from: from, to: to, paused: status.paused),
      confirmLabel: status.paused ? '취소하고 바꾸기' : '바꾸기',
    );
    if (!confirmed || !context.mounted) {
      return;
    }
  }
  final (ok, message) = await supervisor.requestMapChange(mapId);
  if (!context.mounted) {
    return;
  }
  if (!ok) {
    await showVicaNotice(
      context,
      icon: Icons.error_outline,
      iconColor: VicaColors.red,
      title: '바꾸지 못함',
      body: message,
    );
    return;
  }
  final restarted = supervisor.modeStatus?.mapChange?.restarted ?? const <String>[];
  if (status.driveOn && restarted.isNotEmpty) {
    final submode = context.read<AppModeProvider>().driveSubmode;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DriveBringupScreen(submode: submode, mapChange: (from, to)),
      ),
    );
    return;
  }
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text('주행 지도 $to · $message')));
}

class _ConfirmContent extends StatelessWidget {
  const _ConfirmContent({required this.from, required this.to, required this.paused});

  final String from;
  final String to;
  final bool paused;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FromTo(from: from, to: to),
        if (paused) ...[
          const SizedBox(height: 10),
          const _Note(warning: true, text: '일시정지한 안내·순찰 취소'),
        ],
        const SizedBox(height: 10),
        const Text(
          'Nav2·미션·음성 재시작 · 약 1분',
          style: TextStyle(fontSize: 14, color: VicaColors.text),
        ),
        const SizedBox(height: 2),
        const Text(
          '끝나면 초기 위치 다시',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: VicaColors.text),
        ),
        const SizedBox(height: 6),
        const Text(
          '다음 주행·부팅에도 유지',
          style: TextStyle(fontSize: 12, color: VicaColors.muted),
        ),
      ],
    );
  }
}

class _FromTo extends StatelessWidget {
  const _FromTo({required this.from, required this.to});

  final String from;
  final String to;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: VicaColors.text);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: VicaColors.surfaceSunken,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Flexible(child: Text(from, style: style, overflow: TextOverflow.ellipsis)),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Icon(Icons.arrow_forward, size: 18, color: VicaColors.primary),
          ),
          Flexible(
            child: Text(
              to,
              overflow: TextOverflow.ellipsis,
              style: style.copyWith(color: VicaColors.primaryDark),
            ),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text, this.warning = false});

  final String text;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: warning ? const Color(0xFFFBF3E6) : VicaColors.surfaceSunken,
        borderRadius: BorderRadius.circular(10),
        border: warning ? Border.all(color: const Color(0xFFE8D2AE)) : null,
      ),
      child: Text(
        vicaKeepWords(text),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: warning ? const Color(0xFF6B4A15) : VicaColors.muted,
        ),
      ),
    );
  }
}

/// ① 주행 시트의 '주행 지도' 줄. 누르면 ② 목록을 띄우고 고른 지도로 바꿉니다.
class DriveMapRow extends StatelessWidget {
  const DriveMapRow({super.key});

  @override
  Widget build(BuildContext context) {
    final supervisor = context.watch<SupervisorProvider>();
    final status = supervisor.modeStatus;
    if (status == null) {
      return const SizedBox.shrink();
    }
    final id = status.driveOn ? status.driveMapId : status.currentMapId;
    VicaMap? map;
    for (final candidate in supervisor.maps) {
      if (candidate.mapId == id) {
        map = candidate;
      }
    }
    return PressScale(child: Material(
      color: VicaColors.surfaceSunken,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final picked = await showDriveMapPicker(context, currentMapId: id);
          if (picked == null || picked == id || !context.mounted) {
            return;
          }
          if (status.driveOn) {
            // 주행 중이면 확인 창·진행 화면으로 이어집니다. 주행 시트를 먼저 닫고, 시트 밑의
            // 내비게이터에서 이어 갑니다(진행 화면이 끝나면 주행 화면으로 들어가는데 시트가 남지 않게).
            final navigator = Navigator.of(context);
            final host = navigator.context;
            navigator.pop();
            await changeDriveMap(host, picked);
            return;
          }
          await changeDriveMap(context, picked);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: VicaColors.primary, width: 1.5),
          ),
          child: Row(
            children: [
              const Icon(Icons.map_outlined, color: VicaColors.primary, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '주행 지도',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: VicaColors.muted),
                    ),
                    Text(
                      map?.mapName ?? (id.isEmpty ? '없음' : id),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800, color: VicaColors.text),
                    ),
                    if (map != null && driveMapReadiness(map).isNotEmpty)
                      Text(
                        driveMapReadiness(map),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: VicaColors.muted),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // 2026-11-17 사용자: '바꾸기 >' → '변경 >'(확인 창의 '바꾸기' 버튼은 그대로).
              const Text(
                '변경',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: VicaColors.primaryDark),
              ),
              const Icon(Icons.chevron_right, color: VicaColors.primaryDark),
            ],
          ),
        ),
      ),
    ));
  }
}

/// ② 주행 지도 고르기. 고른 지도 id(바꾸지 않으면 null).
Future<String?> showDriveMapPicker(BuildContext context, {required String currentMapId}) {
  final supervisor = context.read<SupervisorProvider>();
  var picked = currentMapId;
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: VicaColors.card,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      final maps = supervisor.maps;
      return StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.8),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '주행 지도 고르기',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: VicaColors.text),
                  ),
                  const SizedBox(height: 4),
                  const Text('다음 주행에도 유지', style: TextStyle(fontSize: 13, color: VicaColors.muted)),
                  const SizedBox(height: 12),
                  if (maps.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('지도 목록 없음 · 지도 연결을 확인하세요',
                          style: TextStyle(color: VicaColors.muted)),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: maps.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, index) {
                          final map = maps[index];
                          return _PickerTile(
                            map: map,
                            selected: map.mapId == picked,
                            inUse: map.mapId == currentMapId,
                            onTap: () => setSheetState(() => picked = map.mapId),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 12),
                  PressScale(child: FilledButton(
                    onPressed: picked.isEmpty || picked == currentMapId
                        ? null
                        : () => Navigator.of(sheetContext).pop(picked),
                    child: Text(
                      picked == currentMapId ? '지도를 고르세요' : '${driveMapName(supervisor, picked)}로 정하기',
                      overflow: TextOverflow.ellipsis,
                    ),
                  )),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.map,
    required this.selected,
    required this.inUse,
    required this.onTap,
  });

  final VicaMap map;
  final bool selected;
  final bool inUse;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 목적지가 없는 지도는 고를 수는 있지만 안내 요청을 모두 거절합니다(미션). 미리 알립니다.
    final noDestination = map.destinationCount == 0;
    final readiness = noDestination ? '목적지 0 · 안내 불가' : driveMapReadiness(map);
    return PressScale(child: Material(
      color: noDestination ? const Color(0xFFFBF3E6) : (selected ? VicaColors.surfaceSunken : VicaColors.card),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? VicaColors.primary : (noDestination ? const Color(0xFFE8D2AE) : VicaColors.border),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: selected ? VicaColors.primary : VicaColors.muted,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            map.mapName,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w800, color: VicaColors.text),
                          ),
                        ),
                        if (inUse) ...[
                          const SizedBox(width: 8),
                          const _Badge('사용 중'),
                        ],
                      ],
                    ),
                    if (readiness.isNotEmpty)
                      Text(
                        readiness,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: noDestination ? FontWeight.w700 : FontWeight.w400,
                          color: noDestination ? const Color(0xFF6B4A15) : VicaColors.muted,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ));
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: VicaColors.accentTint,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: VicaColors.primaryDark),
      ),
    );
  }
}

/// ③⑥ 보고 있는 지도가 주행 지도와 다를 때 띠. 주행 중이 아니거나 같으면 그리지 않습니다.
class DriveMapBanner extends StatelessWidget {
  const DriveMapBanner({super.key, required this.viewedMapId});

  final String? viewedMapId;

  @override
  Widget build(BuildContext context) {
    final supervisor = context.watch<SupervisorProvider>();
    final status = supervisor.modeStatus;
    final viewed = viewedMapId;
    if (status == null || !status.driveOn || viewed == null || viewed.isEmpty) {
      return const SizedBox.shrink();
    }
    final driveMap = status.driveMapId;
    if (driveMap.isEmpty || driveMap == viewed) {
      return const SizedBox.shrink();
    }
    final blocked = status.mapChangeBlock;
    const ink = Color(0xFF6B4A15);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFBF3E6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8D2AE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text.rich(
            TextSpan(
              style: const TextStyle(fontSize: 13, height: 1.5, color: ink),
              children: [
                const TextSpan(text: '주행 지도 '),
                TextSpan(
                  text: driveMapName(supervisor, driveMap),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const TextSpan(text: ' · 로봇 위치 표시 안 함'),
              ],
            ),
          ),
          const SizedBox(height: 10),
          PressScale(child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: ink,
              side: BorderSide(color: blocked.isEmpty ? VicaColors.warning : VicaColors.border),
            ),
            onPressed: blocked.isEmpty ? () => changeDriveMap(context, viewed) : null,
            child: const Text('이 지도로 주행'),
          )),
          if (blocked.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              vicaKeepWords(blocked),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: ink),
            ),
          ],
        ],
      ),
    );
  }
}

/// ⑦ 파일(maps/CURRENT_MAP)만 바뀌고 떠 있는 Nav2·미션·음성은 옛 지도일 때.
class DriveMapMismatchCard extends StatelessWidget {
  const DriveMapMismatchCard({super.key});

  @override
  Widget build(BuildContext context) {
    final supervisor = context.watch<SupervisorProvider>();
    final status = supervisor.modeStatus;
    if (status == null || !status.driveOn || !status.mapMismatch) {
      return const SizedBox.shrink();
    }
    final running = status.driveMapId;
    final current = status.currentMapId;
    const ink = Color(0xFF6B4A15);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFBF3E6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8D2AE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '지도 불일치',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: ink),
          ),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              style: const TextStyle(fontSize: 13, height: 1.5, color: ink),
              children: [
                const TextSpan(text: '설정 '),
                TextSpan(
                  text: driveMapName(supervisor, current),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const TextSpan(text: ' · 실행 중 '),
                TextSpan(
                  text: driveMapName(supervisor, running),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: PressScale(child: OutlinedButton(
                  // 파일만 실행 중인 지도로 되돌립니다(다시 띄울 유닛이 없어 확인 창 없이).
                  onPressed: () => _revert(context, running),
                  child: const Text('되돌리기', overflow: TextOverflow.ellipsis),
                )),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: PressScale(child: FilledButton(
                  onPressed: status.mapChangeBlock.isEmpty ? () => _apply(context, current) : null,
                  child: Text(
                    '${driveMapName(supervisor, current)} 적용',
                    overflow: TextOverflow.ellipsis,
                  ),
                )),
              ),
            ],
          ),
          if (status.mapChangeBlock.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              vicaKeepWords(status.mapChangeBlock),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: ink),
            ),
          ],
        ],
      ),
    );
  }

  // 파일은 이미 [mapId] 다. 같은 지도로 요청하면 모드 노드가 어긋난 유닛만 다시 띄웁니다.
  Future<void> _apply(BuildContext context, String mapId) => changeDriveMap(context, mapId);

  Future<void> _revert(BuildContext context, String mapId) async {
    final supervisor = context.read<SupervisorProvider>();
    final (ok, message) = await supervisor.requestMapChange(mapId);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? '되돌림 · ${driveMapName(supervisor, mapId)}' : '안 됐습니다: $message'),
    ));
  }
}
