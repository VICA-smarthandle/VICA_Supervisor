// 이 파일은 물류 배송 화면입니다. 원격 주행에 "도착하면 문자"를 얹은 것입니다.
//
// 주행 요청은 원격 주행과 같은 Mission Manager 서비스로 나가며 Safety 를
// 우회하지 않습니다. 이 화면이 원격 주행과 다른 것은 셋뿐입니다.
//   1. 연락처가 저장된 장소만 고를 수 있다.
//   2. 출발 전에 "물건을 실었다"를 한 번 확인한다 — 로봇은 적재 센서가 없어
//      물건이 있는지 모른다. 이 확인은 사람의 선언이다.
//   3. 도착하면 문자를 보내고 결과를 팝업으로 알린다.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_settings.dart';
import '../core/contact_phone.dart';
import '../models/delivery_job.dart';
import '../models/location_point.dart';
import '../providers/settings_provider.dart';
import '../providers/supervisor_provider.dart';
import '../widgets/drive_control_bar.dart';
import '../widgets/drive_map_canvas.dart';
import '../widgets/vica_ui.dart';

class DeliveryScreen extends StatefulWidget {
  const DeliveryScreen({super.key});

  @override
  State<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends State<DeliveryScreen> {
  // 원격 주행 화면과 선택을 공유하지 않습니다. 저쪽에서 고른 장소가 연락처가
  // 없는 곳일 수 있고, 배송 대상이 아닌 장소가 여기 '선택됨'으로 보이면
  // 관리자는 왜 출발 버튼이 잠겼는지 모릅니다.
  String? _selectedId;
  bool _loaded = false;

  static const _compactDropdownDecoration = InputDecoration(
    labelText: '지도 선택',
    isDense: true,
    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 9),
  );

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    final supervisor = context.watch<SupervisorProvider>();

    _scheduleDialogs(supervisor);

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
        VicaFieldWithAction(
          actionWidth: 112,
          field: DropdownButtonFormField<String>(
            initialValue: map?.mapId,
            decoration: _compactDropdownDecoration,
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
            onChanged: (value) {
              setState(() => _selectedId = null);
              supervisor.selectMap(settings, value);
            },
          ),
          action: OutlinedButton.icon(
            onPressed: map == null
                ? null
                // 장소·홈·금지구역을 함께 받습니다 — 원격 주행의 '동기화'와
                // 같은 뜻이어야 합니다.
                : () => supervisor.refreshMapData(settings, map.mapId),
            icon: const Icon(Icons.sync, size: 18),
            label: const Text('동기화', maxLines: 1),
          ),
        ),
        CurrentMapNotice(supervisor: supervisor, map: map),
        const SizedBox(height: 18),
        if (map == null)
          const VicaCard(child: Text('지도 목록을 먼저 불러오세요.'))
        else ...[
          // 홈·금지구역·로봇 위치는 주행 화면 공통으로 DriveMapCanvas 가 채웁니다.
          // 장소만 이 화면이 정합니다 — 연락처 있는 곳만. 지도에 보이는 것이
          // 곧 고를 수 있는 것(사용자 결정 2026-09-03).
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

  /// 팝업 두 종류를 한 프레임 뒤에 띄웁니다. build 중에 화면을 바꾸면 예외입니다.
  ///
  /// 주행 실패·취소 팝업은 원격 주행 화면과 같은 것을 씁니다. 관리자가 이 화면을
  /// 보고 있는데 실패가 저쪽 화면에서만 뜨면 배송이 조용히 사라진 것처럼 보입니다.
  void _scheduleDialogs(SupervisorProvider supervisor) {
    final notice = supervisor.pendingDeliveryNotice;
    final alert = supervisor.pendingGoalAlert;
    if (notice == null && alert == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (notice != null) {
        supervisor.consumeDeliveryNotice();
        _showNotice(notice);
      }
      if (alert != null) {
        supervisor.consumeGoalAlert();
        showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            icon: Icon(
              alert.isFailure ? Icons.error_outline : Icons.info_outline,
              color: alert.isFailure ? VicaColors.red : VicaColors.primaryDark,
            ),
            title: Text(alert.title),
            content: Text(alert.description),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('확인'),
              ),
            ],
          ),
        );
      }
    });
  }

  /// 도착 문자 결과. **안 갔으면 크게 알립니다** — 안 간 문자를 갔다고 믿고
  /// 자리를 뜨는 것이 이 기능의 가장 나쁜 실패입니다.
  void _showNotice(DeliveryNotice notice) {
    final sent = notice.result.sent;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          sent ? Icons.sms_outlined : Icons.sms_failed_outlined,
          color: sent ? VicaColors.green : VicaColors.red,
        ),
        title: Text(sent ? '도착 문자를 보냈습니다' : '도착 문자가 가지 않았습니다'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('받는 곳: ${notice.job.destination.name}'),
            Text(
              '받는 번호: ${maskContactPhone(notice.job.destination.contactPhone)}',
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: VicaColors.softBlue,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(notice.text),
            ),
            const SizedBox(height: 10),
            Text(
              notice.result.detail,
              style: TextStyle(
                color: sent ? VicaColors.muted : VicaColors.red,
                fontSize: 13,
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
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
                child: Text('${candidates.length}곳'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            '도착 문자 연락처가 저장된 장소만 보입니다. 없는 장소는 지도 설정에서 연락처를 넣으세요.',
            style: TextStyle(color: VicaColors.muted, fontSize: 13),
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
          // 로봇은 물건이 실렸는지 모릅니다(적재 센서 없음). 그래서 사람이
          // 선언합니다. 이 체크 없이 출발하면 빈 손으로 가서 "물건 왔습니다"
          // 문자가 나갈 수 있습니다.
          CheckboxListTile(
            value: _loaded,
            onChanged: busy ? null : (value) => setState(() => _loaded = value ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('물건을 실었습니다'),
          ),
          const SizedBox(height: 6),
          FilledButton.icon(
            // 요청 가능 여부(권한·접근성·E-stop·Nav2)는 Mission Manager가 판정합니다.
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('배송 출발'),
        content: Text(
          '${location.name}(으)로 물건을 보냅니다.\n'
          '도착하면 ${maskContactPhone(location.contactPhone)} 로 문자를 보냅니다.\n\n'
          '로봇 주변에 사람과 장애물이 없는지 확인하세요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('출발'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    final message = await supervisor.startDelivery(settings, location);
    if (!context.mounted) {
      return;
    }
    if (supervisor.delivery?.isActive == true) {
      // 다음 배송을 위해 적재 확인을 되돌립니다. 지난번 체크가 남아 있으면
      // 실지도 않은 물건을 실었다고 출발하게 됩니다.
      setState(() => _loaded = false);
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
///
/// 배송 중·홈 복귀 중이면 일시정지·다시 출발·취소(원격 주행과 같은 한 벌),
/// 도착하면 홈 복귀 카운트다운과 '지금 복귀'·'복귀 취소', 확인 필요면 '도착 처리'·
/// '지우기', 끝나면 지우기. 카운트다운 때문에 1초마다 다시 그립니다.
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

  // 남은 시간을 보여줄 때만 시계를 돌립니다. 그 밖에는 그릴 이유가 없습니다.
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
      DeliveryPhase.completed => '완료 · 홈 도착',
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
                style: TextStyle(color: phaseColor, fontWeight: FontWeight.w700),
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
              '문자를 보내지 않았습니다. 사유: ${job.abortReason}',
              style: const TextStyle(color: VicaColors.red, fontSize: 13),
            ),
          ],
          if (job.phase == DeliveryPhase.unconfirmed) ...[
            const SizedBox(height: 6),
            Text(
              '${job.abortReason} 로봇이 문 앞에 있으면 "도착 처리"를, '
              '아니면 "지우기"를 누르세요.',
              style: const TextStyle(color: VicaColors.red, fontSize: 13),
            ),
          ],
          if (job.returnNote.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '홈 복귀: ${job.returnNote}',
              style: const TextStyle(color: VicaColors.red, fontSize: 13),
            ),
          ],
          const SizedBox(height: 12),
          switch (job.phase) {
            // 배송 중과 홈 복귀 중은 원격 주행과 같은 버튼 한 벌을 씁니다.
            // 홈 복귀 중 일시정지·재개는 미션이 복귀로 되돌립니다(2026-09-03).
            DeliveryPhase.driving => DriveControlBar(
                supervisor: supervisor,
                paused: paused,
                cancelLabel: '배송 취소',
                cancelTitle: '배송 취소',
                cancelBody: '진행 중인 배송 주행을 취소합니다. 도착 문자는 보내지 않습니다.',
              ),
            DeliveryPhase.arrived => _arrivedButtons(context),
            DeliveryPhase.returning => DriveControlBar(
                supervisor: supervisor,
                paused: paused,
                cancelLabel: '복귀 취소',
                cancelTitle: '홈 복귀 취소',
                cancelBody: '홈으로 가던 주행을 취소합니다. 로봇은 그 자리에 섭니다.',
              ),
            DeliveryPhase.unconfirmed => _unconfirmedButtons(context),
            DeliveryPhase.completed || DeliveryPhase.aborted =>
              _finishedButtons(),
          },
        ],
      ),
    );
  }

  // 도착 뒤. 예정이 살아 있으면 '지금 복귀'·'복귀 취소', 취소했거나 거부됐으면
  // '홈으로 복귀'·'지우기'. 홈이 없으면 복귀 버튼 자체를 잠급니다.
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
                  ? () => _send(context, supervisor.returnDeliveryNow)
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
                ? () => _send(context, supervisor.returnDeliveryNow)
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

  // 앱이 꺼진 사이 주행이 끝났다. 앱은 결과를 모르므로 관리자가 로봇을 보고
  // 고른다. '도착 처리'는 문자를 보내고 복귀 시계를 건다.
  Widget _unconfirmedButtons(BuildContext context) {
    final supervisor = widget.supervisor;
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: () => _send(context, (_) => supervisor.confirmDeliveryArrival()),
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

  static Future<void> _send(
    BuildContext context,
    Future<String> Function(AppSettings) send,
  ) async {
    final settings = context.read<SettingsProvider>().settings;
    final message = await send(settings);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }
}
