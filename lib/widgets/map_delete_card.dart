// 이 파일은 저장된 지도를 관리하는 카드입니다 — 표시 이름 바꾸기와 삭제.
//
// 이름 바꾸기(2026-09-04)는 maps/<id>.meta.json 한 줄을 고치는 일이라 파일·URL·
// 장소·금지구역은 그대로입니다. 삭제와 같은 카드에 두는 이유는 "지도에 손대는 일은
// 여기"라는 자리를 하나로 두기 위해서입니다.
//
// **왜 별도 파일인가.** 지우는 일은 되돌릴 수 없어서 자리를 옮길 일이 생깁니다
// (설정 -> 장소 저장으로 한 번 옮겼습니다). 화면에 박아 두면 옮길 때마다 코드를
// 통째로 나르게 되므로 위젯으로 떼어 둡니다.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_settings.dart';
import '../models/vica_map.dart';
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
  const MapDeleteCard({super.key, this.framed = true});

  /// 스스로 카드 테두리와 제목을 그릴지 여부입니다.
  ///
  /// 접히는 칸(VicaExpandPanel) 안에 들어갈 때는 false 로 둡니다 — 칸 머리에
  /// 이미 '지도 삭제'가 적혀 있어 제목이 두 번 보이고, 카드 안에 카드가
  /// 겹쳐 테두리가 이중이 됩니다. 홈 위치 칸과 같은 방식입니다.
  final bool framed;

  @override
  State<MapDeleteCard> createState() => _MapDeleteCardState();
}

class _MapDeleteCardState extends State<MapDeleteCard> {
  String? _target;
  // 표시 이름 입력칸. 지도를 고르면 지금 이름으로 채우고, 고친 뒤에만 버튼이 열립니다.
  final _nameController = TextEditingController();
  // 체크해야만 삭제 버튼이 열립니다(사용자 판정 2026-08-21). 선택지가 아니라
  // **확인 절차**입니다 — 지도를 지우면 그 지도의 장소도 함께 사라진다는 사실을
  // 사람이 알고 누르게 합니다.
  //
  // 지도만 지우고 장소를 남기는 길은 두지 않습니다. 남겨 두면 없는 지도를 가리키는
  // 카탈로그가 되고, 그 상태는 조용히 틀립니다.
  bool _alsoDestinations = false;
  bool _busy = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _pick(String? mapId, List<VicaMap> maps) {
    setState(() {
      _target = mapId;
      final map = maps.where((m) => m.mapId == mapId).firstOrNull;
      _nameController.text = map?.mapName ?? '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    final supervisor = context.watch<SupervisorProvider>();
    final maps = supervisor.maps;
    final selected = maps.any((map) => map.mapId == _target) ? _target : null;
    final selectedMap =
        maps.where((map) => map.mapId == selected).firstOrNull;
    final typedName = _nameController.text.trim();
    final canRename = selectedMap != null &&
        !_busy &&
        typedName.isNotEmpty &&
        typedName != selectedMap.mapName;

    final body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.framed) ...[
            Text('지도 관리', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
          ],
          const Text(
            '이름은 언제든 바꿀 수 있습니다. 파일 이름(id)과 저장한 장소는 그대로입니다. '
            '삭제한 지도는 되돌릴 수 없습니다. 현재 주행하는 지도는 삭제할 수 없습니다.',
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
              decoration: const InputDecoration(labelText: '지도'),
              items: maps
                  .map(
                    (map) => DropdownMenuItem(
                      value: map.mapId,
                      child: Text(
                        map.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _busy ? null : (value) => _pick(value, maps),
            ),
            const SizedBox(height: 10),
            // -- 이름 바꾸기 --------------------------------------------
            TextField(
              controller: _nameController,
              enabled: selectedMap != null && !_busy,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: '표시 이름',
                helperText: selectedMap == null
                    ? '위에서 지도를 고르면 지금 이름이 채워집니다.'
                    : '한글도 됩니다. 다른 지도와 같은 이름은 안 됩니다. '
                        '파일 이름: ${selectedMap.mapId}',
              ),
            ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: canRename
                  ? () => _rename(context, settings, selectedMap.mapId, typedName)
                  : null,
              icon: const Icon(Icons.drive_file_rename_outline),
              label: const Text('이름 바꾸기'),
            ),
            const Divider(height: 28),
            // -- 삭제 ------------------------------------------------------
            // Material 로 감싸는 이유: 카드(색 있는 Container) 안의 ListTile 은
            // Flutter 3.44 가 잉크 assertion 으로 잡는다(mapping_shell 과 같은 사정).
            Material(
              type: MaterialType.transparency,
              child: CheckboxListTile(
                value: _alsoDestinations,
                onChanged: _busy
                    ? null
                    : (value) =>
                        setState(() => _alsoDestinations = value ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                title: const Text(
                  '이 지도에 저장한 장소도 함께 삭제합니다',
                  style: TextStyle(fontSize: 13),
                ),
                subtitle: const Text(
                  '지도만 삭제하고 장소를 남길 수는 없습니다. 확인하셨으면 체크해 주세요.',
                  style: TextStyle(fontSize: 11, color: VicaColors.muted),
                ),
              ),
            ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              // 체크 없이는 열리지 않습니다. 되돌릴 수 없는 일이라 확인을
              // 한 번 더 받습니다.
              onPressed: selected == null || _busy || !_alsoDestinations
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
      );

    return widget.framed ? VicaCard(child: body) : body;
  }

  Future<void> _rename(
    BuildContext context,
    AppSettings settings,
    String mapId,
    String displayName,
  ) async {
    setState(() => _busy = true);
    final message = await context
        .read<SupervisorProvider>()
        .renameMap(settings, mapId, displayName);
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    AppSettings settings,
    String mapId,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('지도를 삭제합니다'),
        content: Text(
          "'$mapId'의 지도 파일과 이 지도에 저장한 장소를 삭제합니다.\n"
          '되돌릴 수 없습니다.',
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
