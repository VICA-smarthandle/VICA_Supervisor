import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/contact_phone.dart';
import '../models/delivery_job.dart';
import '../models/location_point.dart';
import '../providers/settings_provider.dart';
import '../providers/supervisor_provider.dart';
import '../widgets/drive_control_bar.dart';
import '../widgets/drive_map_canvas.dart';
import '../widgets/map_picker.dart';
import '../widgets/vica_ui.dart';

class DeliveryScreen extends StatefulWidget {
  const DeliveryScreen({super.key});

  @override
  State<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends State<DeliveryScreen> {
  String? _selectedId;
  bool _loaded = false;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    final supervisor = context.watch<SupervisorProvider>();

    final map = supervisor.selectedMap;
    final candidates = supervisor
        .locationsFor(map?.mapId)
        .where((location) => location.canReceiveDelivery)
        .toList(growable: false);
    final selected = _find(candidates, _selectedId);
    final job = supervisor.delivery;
    final busy = job != null && job.isActive;

    return VicaPage(
      title: '물류 배송',
      children: [
        MapPickerRow(
          supervisor: supervisor,
          settings: settings,
          map: map,
          label: '지도 선택',
          onChanged: (value) {
            setState(() => _selectedId = null);
            supervisor.selectMap(settings, value);
          },
          refreshIcon: Icons.refresh,
          refreshLabel: const Text('새로고침'),
        ),
        const SizedBox(height: 18),
        if (map == null)
          const NoMapCard()
        else ...[
          DriveMapCanvas(
            map: map,
            settings: settings,
            supervisor: supervisor,
            locations: candidates,
            selectedLocationId: _selectedId,
            onSelectLocation: busy
                ? null
                : (location) =>
                    setState(() => _selectedId = location.locationId),
          ),
          const SizedBox(height: 20),
          if (job != null) ...[
            _DeliveryStatusCard(job: job, supervisor: supervisor),
            const SizedBox(height: 20),
          ],
          _pickCard(context, supervisor, candidates, selected, busy),
        ],
      ],
    );
  }

  Widget _pickCard(
    BuildContext context,
    SupervisorProvider supervisor,
    List<LocationPoint> candidates,
    LocationPoint? selected,
    bool busy,
  ) {
    return VicaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '배송 받을 곳',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              OutlinedButton(
                onPressed: null,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: Text('${candidates.length}곳'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            vicaKeepWords(vicaBreakAtSentences(
              '연락처가 저장된 장소만 보입니다. 배송을 원하시는 장소는 연락처를 넣어주세요.',
            )),
            style: const TextStyle(color: VicaColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 14),
          if (candidates.isEmpty)
            const Text('연락처가 저장된 장소가 아직 없습니다.')
          else
            Wrap(
              spacing: 8,
              runSpacing: 10,
              children: candidates.map((location) {
                final isSelected = _selectedId == location.locationId;
                return ChoiceChip(
                  selected: isSelected,
                  avatar: Icon(
                    isSelected ? Icons.check_circle : Icons.local_shipping,
                    color:
                        isSelected ? VicaColors.text : VicaColors.primaryDark,
                    size: 18,
                  ),
                  label: Text(
                    '${location.name} · ${maskContactPhone(location.contactPhone)}',
                  ),
                  onSelected: busy
                      ? null
                      : (_) =>
                          setState(() => _selectedId = location.locationId),
                );
              }).toList(),
            ),
          const SizedBox(height: 14),
          CheckboxListTile(
            value: _loaded,
            onChanged: busy
                ? null
                : (value) => setState(() => _loaded = value ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('물건을 실었습니다'),
          ),
          const SizedBox(height: 6),
          FilledButton.icon(
            onPressed: selected == null || !_loaded || busy
                ? null
                : () => _confirmStart(context, supervisor, selected),
            icon: Icon(busy ? Icons.local_shipping : Icons.send),
            label: Text(busy ? '배송 중' : '배송 출발'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmStart(
    BuildContext context,
    SupervisorProvider supervisor,
    LocationPoint location,
  ) async {
    final settings = context.read<SettingsProvider>().settings;
    final confirmed = await showVicaConfirm(
      context,
      icon: Icons.play_arrow_outlined,
      title: '배송 출발',
      body: '${location.name}(으)로 물건을 보냅니다. '
          '도착하면 ${maskContactPhone(location.contactPhone)} 로 문자를 보냅니다.\n\n'
          '로봇 주변에 사람과 장애물이 없는지 확인하세요.',
      confirmLabel: '출발',
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    final message = await supervisor.startDelivery(settings, location);
    if (!context.mounted) {
      return;
    }
    if (supervisor.delivery?.isActive == true) {
      setState(() => _loaded = false);
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  static LocationPoint? _find(List<LocationPoint> locations, String? id) {
    for (final location in locations) {
      if (location.locationId == id) {
        return location;
      }
    }
    return null;
  }
}

/// 지금 배송의 상태 카드.
class _DeliveryStatusCard extends StatefulWidget {
  const _DeliveryStatusCard({required this.job, required this.supervisor});

  final DeliveryJob job;
  final SupervisorProvider supervisor;

  @override
  State<_DeliveryStatusCard> createState() => _DeliveryStatusCardState();
}

class _DeliveryStatusCardState extends State<_DeliveryStatusCard> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant _DeliveryStatusCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _syncTicker() {
    final needTicker = widget.job.isWaitingToReturn;
    if (needTicker && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() {});
        }
      });
    } else if (!needTicker && _ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }
  }

  String _remaining(DateTime returnAt) {
    final left = returnAt.difference(DateTime.now());
    final seconds = left.isNegative ? 0 : left.inSeconds;
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    return '$minutes:${rest.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    final supervisor = widget.supervisor;
    final paused = supervisor.navigationPaused;
    final phaseColor = switch (job.phase) {
      DeliveryPhase.driving => VicaColors.primaryDark,
      DeliveryPhase.arrived => VicaColors.green,
      DeliveryPhase.returning => VicaColors.primaryDark,
      DeliveryPhase.completed => VicaColors.green,
      DeliveryPhase.aborted => VicaColors.red,
      DeliveryPhase.unconfirmed => VicaColors.red,
    };
    final phaseText = switch (job.phase) {
      DeliveryPhase.driving => paused ? '일시정지' : '배송 중',
      DeliveryPhase.arrived => job.isWaitingToReturn
          ? '도착 · ${_remaining(job.returnAt!)} 뒤 홈 복귀'
          : '도착 · 문 앞 대기',
      DeliveryPhase.returning => paused ? '홈 복귀 일시정지' : '홈 복귀 중',
      DeliveryPhase.completed => '완료',
      DeliveryPhase.aborted => '중단',
      DeliveryPhase.unconfirmed => '확인 필요',
    };

    return VicaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.local_shipping, size: 20, color: phaseColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${job.destination.name} 배송',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                phaseText,
                style:
                    TextStyle(color: phaseColor, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '받는 번호 ${maskContactPhone(job.destination.contactPhone)} · '
            '발송 수단 ${supervisor.deliveryNotifierLabel}',
            style: const TextStyle(color: VicaColors.muted, fontSize: 13),
          ),
          if (job.phase == DeliveryPhase.aborted) ...[
            const SizedBox(height: 6),
            Text(
              vicaKeepWords(vicaBreakAtSentences(
                '문자를 보내지 않았습니다. 사유: ${job.abortReason}',
              )),
              style: const TextStyle(color: VicaColors.red, fontSize: 13),
            ),
          ],
          if (job.phase == DeliveryPhase.unconfirmed) ...[
            const SizedBox(height: 6),
            Text(
              vicaKeepWords(vicaBreakAtSentences(
                '${job.abortReason} 로봇이 문 앞에 있으면 "도착 처리"를, '
                '아니면 "지우기"를 누르세요.',
              )),
              style: const TextStyle(color: VicaColors.red, fontSize: 13),
            ),
          ],
          if (job.returnNote.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              vicaKeepWords(vicaBreakAtSentences('홈 복귀: ${job.returnNote}')),
              style: const TextStyle(color: VicaColors.red, fontSize: 13),
            ),
          ],
          const SizedBox(height: 12),
          switch (job.phase) {
            DeliveryPhase.driving => DriveControlBar(
                supervisor: supervisor,
                paused: paused,
                cancelLabel: '배송 취소',
                cancelTitle: '배송 취소',
                cancelBody: '진행 중인 배송을 취소합니다. 도착 문자는 보내지 않습니다.',
              ),
            DeliveryPhase.arrived => _arrivedButtons(context),
            DeliveryPhase.returning => DriveControlBar(
                supervisor: supervisor,
                paused: paused,
                cancelLabel: '복귀 취소',
                cancelTitle: '홈 복귀 취소',
                cancelBody: '홈 복귀를 취소합니다. 로봇은 그 자리에 섭니다.',
              ),
            DeliveryPhase.unconfirmed => _unconfirmedButtons(context),
            DeliveryPhase.completed ||
            DeliveryPhase.aborted =>
              _finishedButtons(),
          },
        ],
      ),
    );
  }

  Widget _arrivedButtons(BuildContext context) {
    final supervisor = widget.supervisor;
    final job = widget.job;
    final hasHome = supervisor.home != null;
    if (job.isWaitingToReturn) {
      return Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: hasHome
                  ? () =>
                      sendRobotCommand(context, supervisor.returnDeliveryNow)
                  : null,
              icon: const Icon(Icons.home),
              label: const Text('지금 복귀'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: supervisor.cancelDeliveryReturn,
              icon: const Icon(Icons.timer_off_outlined),
              label: const Text('복귀 취소'),
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: hasHome
                ? () => sendRobotCommand(context, supervisor.returnDeliveryNow)
                : null,
            icon: const Icon(Icons.home_outlined),
            label: Text(hasHome ? '홈으로 복귀' : '홈이 없습니다'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: supervisor.clearDelivery,
            icon: const Icon(Icons.check),
            label: const Text('지우기'),
          ),
        ),
      ],
    );
  }

  Widget _unconfirmedButtons(BuildContext context) {
    final supervisor = widget.supervisor;
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: () => sendRobotCommand(
                context, (_) => supervisor.confirmDeliveryArrival()),
            icon: const Icon(Icons.sms_outlined),
            label: const Text('도착 처리 · 문자'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: supervisor.clearDelivery,
            icon: const Icon(Icons.delete_outline),
            label: const Text('지우기'),
          ),
        ),
      ],
    );
  }

  Widget _finishedButtons() {
    return OutlinedButton.icon(
      onPressed: widget.supervisor.clearDelivery,
      icon: const Icon(Icons.check),
      label: const Text('배송 완료 · 지우기'),
    );
  }
}
