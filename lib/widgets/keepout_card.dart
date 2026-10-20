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
    required this.hasPending,
    required this.onStartEdit,
    required this.onConfirmPending,
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
  final bool maskApplied;
  final bool connected;

  /// 로봇이 목적지를 쥐고 있는가(주행·일시정지). true면 편집 **시작**만
  final bool drivingHold;

  /// 그려 놓고 아직 '확정'하지 않은 사각형이 있는가. 드래그를 다시 하면 그
  final bool hasPending;

  final VoidCallback onStartEdit;
  final VoidCallback onConfirmPending;
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
          vicaKeepWords(vicaBreakAtSentences(
            editing
                ? '드래그해서 사각형을 그리세요. [금지구역 확정]을 누르면 목록에 들어갑니다. 편집 중에는 지도 이동, 확대가 잠깁니다.'
                : drivingHold
                    ? '로봇이 목적지로 가는 중에는 금지구역을 편집할 수 없습니다. 주행이 끝나면 열립니다.'
                    : '로봇이 주행하지 않을 구역입니다. 편집을 누르세요.',
          )),
          style: const TextStyle(
              fontSize: 13, color: VicaColors.muted, height: 1.5),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: VicaColors.accentTint,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline,
                  size: 16, color: VicaColors.primaryDark),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  vicaKeepWords(vicaBreakAtSentences(
                    '로봇은 금지구역의 경계선까지 붙을 수 있습니다. 실제로 막고 싶은 범위보다 '
                    '20~30 cm 크게 그리세요.',
                  )),
                  style: const TextStyle(
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
            vicaKeepWords(vicaBreakAtSentences(message)),
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
          const VicaStateBadge(text: 'ROS 연결 없음', color: VicaColors.red)
        else if (editing)
          const VicaStateBadge(text: '편집 중 · 저장 전', color: VicaColors.primary)
        else if (drivingHold)
          const VicaStateBadge(text: '주행 중 · 편집 잠김', color: VicaColors.muted)
        else if (maskApplied)
          const VicaStateBadge(text: '금지구역 적용됨', color: VicaColors.green)
        else
          const VicaStateBadge(text: '적용 대기', color: VicaColors.muted),
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
              onPressed: (connected && !drivingHold) ? onStartEdit : null,
              icon: const Icon(Icons.edit_outlined),
              label: Text(
                state == KeepoutSaveState.failed ? '다시 시도' : '금지구역 편집',
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: connected ? onReload : null,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('다시 불러오기'),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: (hasPending && !_saving) ? onConfirmPending : null,
                icon: const Icon(Icons.check, size: 18),
                label: const Text('금지구역 확정'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
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
            Expanded(
              child: OutlinedButton(
                onPressed: _saving ? null : onCancel,
                child: const Text('취소'),
              ),
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
