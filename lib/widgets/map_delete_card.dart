// 이 파일은 저장된 지도를 지우는 카드입니다.
//
// **왜 별도 파일인가.** 지우는 일은 되돌릴 수 없어서 자리를 옮길 일이 생깁니다
// (설정 -> 장소 저장으로 한 번 옮겼습니다). 화면에 박아 두면 옮길 때마다 코드를
// 통째로 나르게 되므로 위젯으로 떼어 둡니다.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_settings.dart';
import '../providers/settings_provider.dart';
import '../providers/supervisor_provider.dart';
import 'vica_ui.dart';

// 저장된 지도를 지우는 자리입니다.
//
// **왜 설정 화면인가.** 되돌릴 수 없는 일이라 일상 흐름(장소 저장·원격 주행)에서
// 멀리 둡니다. "지도 한 장은 사람이 로봇을 끌고 다닌 시간"입니다
// (scripts/vica_map_save.sh 주석). 실수로 눌릴 자리에 두면 안 됩니다.
//
// 실제 검사는 노드가 합니다 — 이름 규칙, 지금 쓰는 지도인지, 파일이 있는지.
// 앱은 확인만 받습니다.
class MapDeleteCard extends StatefulWidget {
  const MapDeleteCard({super.key});

  @override
  State<MapDeleteCard> createState() => _MapDeleteCardState();
}

class _MapDeleteCardState extends State<MapDeleteCard> {
  String? _target;
  // 기본값을 false 로 둡니다. 같은 이름으로 다시 그릴 생각이면 목적지 카탈로그는
  // 남겨 두는 편이 낫습니다 — 장소를 다시 찍는 일이 더 번거롭습니다.
  bool _alsoDestinations = false;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    final supervisor = context.watch<SupervisorProvider>();
    final maps = supervisor.maps;
    final selected = maps.any((map) => map.mapId == _target) ? _target : null;

    return VicaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('지도 관리', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          const Text(
            '지운 지도는 되돌릴 수 없습니다. 지금 쓰는 지도는 지울 수 없습니다.',
            style: TextStyle(color: VicaColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          if (maps.isEmpty)
            const Text(
              '지도 목록이 비어 있습니다. 먼저 목록을 불러오세요.',
              style: TextStyle(fontSize: 12),
            )
          else ...[
            DropdownButtonFormField<String>(
              initialValue: selected,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '지울 지도'),
              items: maps
                  .map(
                    (map) => DropdownMenuItem(
                      value: map.mapId,
                      child: Text(
                        map.mapName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged:
                  _busy ? null : (value) => setState(() => _target = value),
            ),
            const SizedBox(height: 6),
            CheckboxListTile(
              value: _alsoDestinations,
              onChanged: _busy
                  ? null
                  : (value) =>
                      setState(() => _alsoDestinations = value ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              title: const Text(
                '이 지도에 저장한 장소도 함께 지웁니다',
                style: TextStyle(fontSize: 13),
              ),
              subtitle: const Text(
                '같은 이름으로 다시 그릴 생각이면 체크하지 마세요.',
                style: TextStyle(fontSize: 11, color: VicaColors.muted),
              ),
            ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: selected == null || _busy
                  ? null
                  : () => _confirmDelete(context, settings, selected),
              icon: const Icon(Icons.delete_forever_outlined),
              label: const Text('지도 삭제'),
              style: OutlinedButton.styleFrom(
                foregroundColor: VicaColors.red,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    AppSettings settings,
    String mapId,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('지도를 지웁니다'),
        content: Text(
          "'$mapId' 의 지도 파일을 지웁니다. 되돌릴 수 없습니다."
          "${_alsoDestinations ? '\n\n이 지도에 저장한 장소도 함께 사라집니다.' : ''}",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('그만두기'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: VicaColors.red),
            child: const Text('지우기'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }

    setState(() => _busy = true);
    final message = await context.read<SupervisorProvider>().deleteMap(
          settings,
          mapId,
          deleteDestinations: _alsoDestinations,
        );
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _target = null;
    });
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }
}
