import 'package:flutter/material.dart';

import '../core/app_settings.dart';
import '../models/vica_map.dart';
import '../providers/supervisor_provider.dart';
import 'drive_map_canvas.dart';
import 'vica_ui.dart';

class MapPickerRow extends StatelessWidget {
  const MapPickerRow({
    super.key,
    required this.supervisor,
    required this.settings,
    required this.map,
    required this.label,
    required this.onChanged,
    required this.refreshIcon,
    required this.refreshLabel,
    this.actionWidth = 132,
    this.dropdownKey,
  });

  final SupervisorProvider supervisor;
  final AppSettings settings;

  /// 지금 보이는 지도. 지도 목록을 아직 못 받았으면 null 이고 버튼이 잠깁니다.
  final VicaMap? map;

  /// 드롭다운 칸의 이름(세 화면 모두 '지도 선택').
  final String label;

  /// 지도를 고르면 부릅니다. 지도를 바꾸는 일(selectMap)도 화면이 정합니다 — 지도
  final ValueChanged<String?> onChanged;

  final IconData refreshIcon;
  final Widget refreshLabel;
  final double actionWidth;

  /// 드롭다운을 다시 만들 때 바꿉니다(고른 값을 버리고 지금 지도로 되돌릴 때).
  final Key? dropdownKey;

  @override
  Widget build(BuildContext context) {
    final current = map;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        VicaFieldWithAction(
          actionWidth: actionWidth,
          field: DropdownButtonFormField<String>(
            key: dropdownKey,
            initialValue: current?.mapId,
            decoration: vicaCompactDropdownDecoration(label),
            isExpanded: true,
            itemHeight: null,
            items: supervisor.maps
                .map(
                  (item) => DropdownMenuItem(
                    value: item.mapId,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(item.displayName),
                    ),
                  ),
                )
                .toList(),
            selectedItemBuilder: (context) => supervisor.maps
                .map(
                  (item) => Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      item.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: onChanged,
          ),
          action: OutlinedButton.icon(
            onPressed: current == null
                ? null
                : () => supervisor.refreshMapData(settings, current.mapId),
            icon: Icon(refreshIcon, size: 18),
            label: refreshLabel,
          ),
        ),
        CurrentMapNotice(supervisor: supervisor, map: current),
      ],
    );
  }
}

/// 지도 목록을 아직 못 받았을 때 지도 자리에 놓는 칸.
class NoMapCard extends StatelessWidget {
  const NoMapCard({super.key});

  @override
  Widget build(BuildContext context) {
    return const VicaCard(child: Text('지도 목록을 먼저 불러오세요.'));
  }
}
