// 화면 맨 위의 '지도 고르기' 줄. 원격 주행·물류 배송·지도 설정 세 화면이 같은 것을 씁니다.
//
// 지도 드롭다운과 그 옆 '다시 받기' 버튼, 그 아래 '로봇이 지금 다른 지도로 달린다' 안내
// (CurrentMapNotice) 한 묶음입니다. 세 화면에 손으로 같은 것을 짜 두었는데, 화면마다 다른
// 것은 드롭다운 글자·버튼 폭·버튼 아이콘과 글자·고른 뒤 할 일뿐입니다 — 그것만 받습니다.
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
  /// 설정은 하던 편집을 먼저 정리해야 합니다.
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
                // 장소·홈·금지구역·레일을 함께 받습니다. 종전에는 장소만 받아 이름과
                // 동작이 어긋났고, 홈은 이 버튼 말고는 수동 갱신 경로가 아예
                // 없었습니다(2026-09-02).
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
