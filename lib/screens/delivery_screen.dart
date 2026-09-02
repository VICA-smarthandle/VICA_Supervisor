// 이 파일은 물류 배송 화면입니다. 원격 주행에 "도착하면 문자"를 얹은 것입니다.
//
// 주행 요청은 원격 주행과 같은 Mission Manager 서비스로 나가며 Safety 를
// 우회하지 않습니다. 이 화면이 원격 주행과 다른 것은 셋뿐입니다.
//   1. 연락처가 저장된 장소만 고를 수 있다.
//   2. 출발 전에 "물건을 실었다"를 한 번 확인한다 — 로봇은 적재 센서가 없어
//      물건이 있는지 모른다. 이 확인은 사람의 선언이다.
//   3. 도착하면 문자를 보내고 결과를 팝업으로 알린다.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_settings.dart';
import '../core/contact_phone.dart';
import '../models/delivery_job.dart';
import '../models/location_point.dart';
import '../providers/settings_provider.dart';
import '../providers/supervisor_provider.dart';
import '../widgets/map_canvas.dart';
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
                      child: Text(item.mapName),
                    ),
                  ),
                )
                .toList(),
            selectedItemBuilder: (context) => supervisor.maps
                .map(
                  (item) => Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      item.mapName,
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
                : () => supervisor.requestLocationList(settings, map.mapId),
            icon: const Icon(Icons.sync, size: 18),
            label: const Text('동기화', maxLines: 1),
          ),
        ),
        const SizedBox(height: 18),
        if (map == null)
          const VicaCard(child: Text('지도 목록을 먼저 불러오세요.'))
        else ...[
          ResponsiveMapFrame(
            map: map,
            child: MapCanvas(
              map: map,
              settings: settings,
              // 연락처 있는 장소만 그립니다. 지도에 보이는 것이 곧 고를 수 있는 것.
              locations: candidates,
              selectedLocationId: _selectedId,
              robot: supervisor.primaryRobot,
              keepoutZones: supervisor.keepoutZonesFor(map.mapId),
              onSelectLocation: busy
                  ? null
                  : (location) =>
                      setState(() => _selectedId = location.locationId),
            ),
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

/// 지금 배송의 상태 카드. 주행 중이면 일시정지·취소, 끝났으면 결과와 지우기.
class _DeliveryStatusCard extends StatelessWidget {
  const _DeliveryStatusCard({required this.job, required this.supervisor});

  final DeliveryJob job;
  final SupervisorProvider supervisor;

  @override
  Widget build(BuildContext context) {
    final paused = supervisor.navigationPaused;
    final phaseColor = switch (job.phase) {
      DeliveryPhase.driving => VicaColors.primaryDark,
      DeliveryPhase.arrived => VicaColors.green,
      DeliveryPhase.aborted => VicaColors.red,
    };
    final phaseText = switch (job.phase) {
      DeliveryPhase.driving => paused ? '일시정지' : '배송 중',
      DeliveryPhase.arrived => '도착 · 문자 ${job.notified ? '발송 처리됨' : '대기'}',
      DeliveryPhase.aborted => '중단',
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
          const SizedBox(height: 12),
          if (job.isActive)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _send(
                      context,
                      paused
                          ? supervisor.resumeNavigation
                          : supervisor.pauseNavigation,
                    ),
                    icon: Icon(paused ? Icons.play_arrow : Icons.pause),
                    label: Text(paused ? '다시 출발' : '일시정지'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _confirmCancel(context),
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('배송 취소'),
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                // 도착 뒤 복귀는 아직 관리자가 직접 부릅니다. 5분 대기와 출발지
                // 복귀는 다음 단계입니다.
                if (job.phase == DeliveryPhase.arrived &&
                    supervisor.home != null) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _send(context, supervisor.returnHome),
                      icon: const Icon(Icons.home_outlined),
                      label: const Text('홈으로 복귀'),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: supervisor.clearDelivery,
                    icon: const Icon(Icons.check),
                    label: const Text('배송 완료 · 지우기'),
                  ),
                ),
              ],
            ),
        ],
      ),
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

  Future<void> _confirmCancel(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('배송 취소'),
        content: const Text('진행 중인 배송 주행을 취소합니다. 도착 문자는 보내지 않습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('계속 배송'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('취소하기'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    await _send(context, supervisor.cancelDestination);
  }
}
