// 이 파일은 지도 설정 화면의 '금지구역' 칸을 그립니다.
//
// 로봇이 들어가지 않을 자리를 관리자가 사각형으로 그립니다. 원본 지도는 바뀌지
// 않고, 젯슨이 같은 크기의 마스크 파일을 따로 만들어 Nav2에 물립니다.
import 'package:flutter/material.dart';

import '../models/keepout_zone.dart';
import '../providers/supervisor_provider.dart' show KeepoutSaveState;
import 'vica_ui.dart';

class KeepoutCard extends StatelessWidget {
  const KeepoutCard({
    super.key,
    required this.zones,
    required this.selectedZoneId,
    required this.editing,
    required this.state,
    required this.message,
    required this.maskApplied,
    required this.connected,
    required this.drivingHold,
    required this.onStartEdit,
    required this.onCancel,
    required this.onSave,
    required this.onDeleteSelected,
    required this.onClearAll,
    required this.onReload,
    required this.onSelect,
  });

  final List<KeepoutZone> zones;
  final String? selectedZoneId;
  final bool editing;
  final KeepoutSaveState state;
  final String message;

  /// 젯슨에 마스크 파일이 있는가. 화면에 그려져 있다고 로봇이 지키는 것은
  /// 아니라서, 저장과 적용을 나눠 보여줍니다.
  final bool maskApplied;
  final bool connected;

  /// 로봇이 목적지를 쥐고 있는가(주행·일시정지). true면 편집 **시작**만
  /// 잠급니다 — 시작해 봐야 적용이 미뤄질 것을 버튼 자리에서 미리 알리는
  /// 안내장치입니다. 이미 편집 중이면 계속하게 둡니다: 그리는 도중 음성으로
  /// 주행이 시작될 수 있고, 그때는 저장 응답(busy_driving)과 젯슨 쪽 유예
  /// 판정(keepout_mask.hold_apply)이 안전을 맡습니다.
  final bool drivingHold;

  final VoidCallback onStartEdit;
  final VoidCallback onCancel;
  final VoidCallback onSave;
  final VoidCallback onDeleteSelected;
  final VoidCallback onClearAll;
  final VoidCallback onReload;
  final ValueChanged<String?> onSelect;

  bool get _saving => state == KeepoutSaveState.saving;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          editing
              ? '지도를 손가락으로 눌러 끌면 사각형이 그려집니다. 편집하는 동안 지도 이동과 확대는 잠깁니다.'
              : drivingHold
                  ? '로봇이 목적지로 가는 중에는 금지구역을 편집할 수 없습니다. 주행이 끝나면 열립니다.'
                  : '로봇이 들어가지 않을 자리입니다. 편집을 누르면 지도에 사각형을 그릴 수 있습니다.',
          style: const TextStyle(
              fontSize: 13, color: VicaColors.muted, height: 1.5),
        ),
        const SizedBox(height: 10),
        // 이 문장은 장식이 아닙니다. Nav2 는 금지구역에 여유(inflation)를 두지
        // 않습니다 — 로봇이 경계선에 몸을 딱 붙일 수 있습니다. 그 여유를 사람이
        // 그림으로 줘야 합니다.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: VicaColors.softBlue,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 16, color: VicaColors.primaryDark),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '로봇은 사각형 경계선까지 붙을 수 있습니다. 실제로 막고 싶은 범위보다 '
                  '20~30 cm 크게 그리세요.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: VicaColors.primaryDark,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _statusRow(context),
        if (zones.isNotEmpty) ...[
          const SizedBox(height: 12),
          ...zones.map((zone) => _zoneRow(context, zone)),
        ],
        if (message.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: state == KeepoutSaveState.failed
                  ? VicaColors.red
                  : VicaColors.muted,
            ),
          ),
        ],
        const SizedBox(height: 14),
        _buttons(context),
      ],
    );
  }

  Widget _statusRow(BuildContext context) {
    return Row(
      children: [
        Text(
          '구역 ${zones.length}개',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(width: 10),
        if (!connected)
          const _Badge(text: 'ROS 연결 없음', color: VicaColors.red)
        else if (editing)
          const _Badge(text: '편집 중 · 저장 전', color: VicaColors.primary)
        else if (drivingHold)
          const _Badge(text: '주행 중 · 편집 잠김', color: VicaColors.muted)
        else if (maskApplied)
          const _Badge(text: '로봇에 적용됨', color: VicaColors.green)
        else
          const _Badge(text: '적용 대기', color: VicaColors.muted),
      ],
    );
  }

  Widget _zoneRow(BuildContext context, KeepoutZone zone) {
    final selected = zone.zoneId == selectedZoneId;
    return InkWell(
      onTap: () => onSelect(selected ? null : zone.zoneId),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(
              selected ? Icons.check_box : Icons.crop_square,
              size: 18,
              color: selected ? VicaColors.red : VicaColors.muted,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                zone.name.isEmpty ? zone.zoneId : zone.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ),
            Text(
              '${zone.width.toStringAsFixed(2)} × ${zone.height.toStringAsFixed(2)} m',
              style: const TextStyle(fontSize: 12, color: VicaColors.muted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buttons(BuildContext context) {
    if (!editing) {
      return Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              // 주행·일시정지 중에는 시작을 잠급니다(drivingHold 주석 참고).
              onPressed: (connected && !drivingHold) ? onStartEdit : null,
              icon: const Icon(Icons.edit_outlined),
              label: Text(
                state == KeepoutSaveState.failed ? '다시 시도' : '금지구역 편집',
              ),
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: connected ? onReload : null,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('다시 불러오기'),
          ),
        ],
      );
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                // 저장 중에는 다시 누를 수 없습니다. 두 번 누르면 같은 요청이
                // 두 번 가고, 나중 응답이 먼저 온 응답을 덮습니다.
                onPressed: (_saving || !connected) ? null : onSave,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_upload_outlined),
                label: Text(_saving ? '저장 중...' : '저장'),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton(
              onPressed: _saving ? null : onCancel,
              child: const Text('취소'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: (_saving || selectedZoneId == null)
                    ? null
                    : onDeleteSelected,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('선택 삭제'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: (_saving || zones.isEmpty) ? null : onClearAll,
                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                label: const Text('전체 삭제'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
            fontSize: 11.5, fontWeight: FontWeight.w800, color: color),
      ),
    );
  }
}
