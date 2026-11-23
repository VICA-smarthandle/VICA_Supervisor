import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/location_point.dart';
import '../models/patrol.dart';
import '../models/vica_map.dart';
import '../providers/settings_provider.dart';
import '../providers/supervisor_provider.dart';
import 'map_canvas.dart';
import 'map_work_layout.dart';
import 'patrol_ui.dart';
import 'vica_ui.dart';

class PatrolRouteEditor extends StatefulWidget {
  const PatrolRouteEditor({
    super.key,
    required this.map,
    required this.saved,
    required this.onClose,
  });

  final VicaMap map;

  /// 지금 저장돼 있는 경로. 없으면 빈 경로입니다.
  final PatrolRoute saved;

  /// 뒤로·취소·저장 완료에서 불립니다.
  final VoidCallback onClose;

  @override
  State<PatrolRouteEditor> createState() => _PatrolRouteEditorState();
}

class _PatrolRouteEditorState extends State<PatrolRouteEditor> {
  late PatrolRouteDraft _draft = PatrolRouteDraft.from(widget.saved.ids);
  bool _saving = false;

  /// 이 지도의 저장 장소. build 가 채우고 이름 찾기가 씁니다.
  List<LocationPoint> _locations = const [];

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    final supervisor = context.watch<SupervisorProvider>();
    final map = widget.map;
    final locations = supervisor.locationsFor(map.mapId);
    _locations = locations;
    final dirty = !_draft.sameAs(widget.saved.ids);

    final marks = [
      for (final location in locations)
        PatrolPlaceMark(
          id: location.locationId,
          x: location.x,
          y: location.y,
          name: location.name,
          number: _draft.numberOf(location.locationId),
          style: _draft.shiftedFrom.containsKey(location.locationId)
              ? PatrolMarkStyle.shifted
              : PatrolMarkStyle.normal,
        ),
    ];

    return MapWorkLayout(
      children: [
        Row(
          children: [
            PressScale(
                child: IconButton(
              onPressed: _saving ? null : widget.onClose,
              icon: const Icon(Icons.chevron_left, size: 26),
              color: VicaColors.text,
              tooltip: '뒤로',
            )),
            Expanded(
              child: Text(
                '순찰 경로 편집',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            PressScale(
                child: OutlinedButton.icon(
              onPressed: widget.saved.isEmpty || _saving
                  ? null
                  : () => _confirmDelete(supervisor),
              style: patrolSmallButtonStyle(
                foreground: PatrolColors.intruderInk,
              ).copyWith(
                side: WidgetStateProperty.resolveWith(
                  (states) => BorderSide(
                    color: states.contains(WidgetState.disabled)
                        ? VicaColors.border
                        : PatrolColors.intruderSoftBorder,
                  ),
                ),
              ),
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('경로 삭제', style: patrolSmallButtonText),
            )),
          ],
        ),
        const SizedBox(height: 10),
        ResponsiveMapFrame(
          map: map,
          minHeight: 200,
          maxHeight: 420,
          child: MapCanvas(
            map: map,
            settings: settings,
            locations: locations,
            routeGraph: supervisor.routeGraphFor(map.mapId),
            showLocationLabels: false,
            onSelectLocation: _saving
                ? null
                : (location) => _toggle(location.locationId, location.name),
            overlayBuilder: (toPixel) => buildPatrolMapOverlay(
              toPixel,
              marks,
              showNames: true,
              onTap: _saving ? null : (id) => _toggle(id, _nameOf(id)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: VicaColors.accentTint,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: vicaKeepWords(
                    '장소를 누르면 맨 뒤에 번호가 붙습니다.\n'
                    '번호가 붙은 장소를 다시 누르거나 ',
                  ),
                ),
                const WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Icon(
                    Icons.close,
                    size: 14,
                    color: VicaColors.primaryDark,
                  ),
                ),
                TextSpan(
                  text: '\u2060${vicaKeepWords('를 누르면 빠지고, 뒤 번호가 하나씩 당겨집니다.')}',
                ),
              ],
            ),
            key: const ValueKey('patrol_route_hint'),
            style: const TextStyle(
              color: VicaColors.primaryDark,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 10),
        _orderCard(),
        if (dirty) ...[
          const Text(
            '저장하지 않은 변경이 있습니다.',
            textAlign: TextAlign.center,
            style: TextStyle(color: PatrolColors.shiftedInk, fontSize: 12),
          ),
          const SizedBox(height: 10),
        ],
        VicaButtonRow(
          foldWidth: 240,
          children: [
            PressScale(
                child: FilledButton(
              onPressed: dirty && !_saving ? () => _save(supervisor) : null,
              child: const Text('저장'),
            )),
            PressScale(
                child: OutlinedButton(
              onPressed: _saving ? null : widget.onClose,
              child: const Text('취소'),
            )),
          ],
        ),
      ],
    );
  }

  Widget _orderCard() {
    return VicaCard(
      padding: const EdgeInsets.only(top: 8),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(kVicaCardRadius - 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '순찰 순서 · 장소 ${_draft.length}곳',
                      style: const TextStyle(
                        color: VicaColors.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Text(
                    '마지막 다음엔 1번으로',
                    style: TextStyle(color: VicaColors.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            for (var i = 0; i < _draft.ids.length; i++)
              _orderRow(i, _draft.ids[i]),
          ],
        ),
      ),
    );
  }

  Widget _orderRow(int index, String id) {
    final name = _nameOf(id);
    final oldNumber = _draft.shiftedFrom[id];
    return Container(
      key: ValueKey('patrol_order_$id'),
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
        color: oldNumber == null ? null : PatrolColors.shiftedTint,
        border: const Border(top: BorderSide(color: VicaColors.surfaceSunken)),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: VicaColors.primary,
              shape: BoxShape.circle,
            ),
            child: Text(
              '${index + 1}',
              textScaler: TextScaler.noScaling,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(
                color: VicaColors.text,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (oldNumber != null)
            Text(
              '$oldNumber → ${index + 1}',
              style: const TextStyle(
                color: PatrolColors.shiftedInk,
                fontSize: 11,
              ),
            ),
          PressScale(
              child: IconButton(
            onPressed: _saving ? null : () => _toggle(id, name),
            icon: const Icon(Icons.close, size: 18),
            color: PatrolColors.intruderInk,
            tooltip: '$name 빼기',
          )),
        ],
      ),
    );
  }

  /// 장소 이름. 지워진 장소가 저장된 경로에 남아 있으면 저장 때의 이름을 씁니다.
  String _nameOf(String id) {
    for (final location in _locations) {
      if (location.locationId == id) {
        return location.name;
      }
    }
    final index = widget.saved.ids.indexOf(id);
    return index >= 0 && index < widget.saved.names.length
        ? widget.saved.names[index]
        : '';
  }

  void _toggle(String id, String name) {
    final removing = _draft.ids.contains(id);
    final next = _draft.toggled(id);
    setState(() => _draft = next);
    if (removing) {
      showPatrolToast(
        context,
        patrolRemovedNotice(name, shifted: next.shiftedFrom.isNotEmpty),
      );
    }
  }

  Future<void> _save(SupervisorProvider supervisor) async {
    if (_draft.ids.isEmpty) {
      await _confirmDelete(supervisor);
      return;
    }
    await _send(
      supervisor,
      _draft.ids,
      names: [for (final id in _draft.ids) _nameOf(id)],
    );
  }

  Future<void> _confirmDelete(SupervisorProvider supervisor) async {
    final confirmed = await showVicaConfirm(
      context,
      icon: Icons.delete_outline,
      iconColor: VicaColors.red,
      title: '순찰 경로를 지울까요?',
      body: '정해 둔 순서가 모두 지워집니다.\n저장된 장소는 지워지지 않습니다.',
      confirmLabel: '지우기',
      danger: true,
    );
    if (!confirmed || !mounted) {
      return;
    }
    await _send(supervisor, const []);
  }

  Future<void> _send(
    SupervisorProvider supervisor,
    List<String> ids, {
    List<String> names = const [],
  }) async {
    final settings = context.read<SettingsProvider>().settings;
    setState(() => _saving = true);
    final (accepted, message) = await supervisor.savePatrolRoute(
      settings,
      widget.map.mapId,
      ids,
      names: names,
    );
    if (!mounted) {
      return;
    }
    setState(() => _saving = false);
    showPatrolToast(context, message);
    if (accepted) {
      widget.onClose();
    }
  }
}
