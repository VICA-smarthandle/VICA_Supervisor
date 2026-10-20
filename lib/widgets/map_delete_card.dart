import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_settings.dart';
import '../models/vica_map.dart';
import '../providers/settings_provider.dart';
import '../providers/supervisor_provider.dart';
import 'vica_ui.dart';

class MapDeleteCard extends StatefulWidget {
  const MapDeleteCard({super.key, this.framed = true});

  /// 스스로 카드 테두리와 제목을 그릴지 여부입니다.
  final bool framed;

  @override
  State<MapDeleteCard> createState() => _MapDeleteCardState();
}

class _MapDeleteCardState extends State<MapDeleteCard> {
  String? _target;
  final _nameController = TextEditingController();
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
    final selectedMap = maps.where((map) => map.mapId == selected).firstOrNull;
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
        Text(
          vicaKeepWords(
            '삭제한 지도는 되돌릴 수 없습니다. 현재 주행하는 지도는 삭제할 수 없습니다.',
          ),
          style: const TextStyle(color: VicaColors.muted, fontSize: 12),
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
          TextField(
            controller: _nameController,
            enabled: selectedMap != null && !_busy,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: '표시 이름',
              helperText:
                  selectedMap == null ? '이름을 수정해 주세요.' : '다른 지도와 같은 이름은 안 됩니다.',
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
            ),
          ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
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
    final confirmed = await showVicaConfirm(
      context,
      icon: Icons.delete_outline,
      iconColor: VicaColors.red,
      title: '지도를 삭제합니다',
      body: "'$mapId'의 지도 파일과 금지구역·레일, 이 지도에 저장한 장소를 "
          '삭제합니다. 되돌릴 수 없습니다.',
      confirmLabel: '삭제',
      danger: true,
    );
    if (!confirmed || !context.mounted) {
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
