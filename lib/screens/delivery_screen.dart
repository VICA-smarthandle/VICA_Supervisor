// 이 파일은 물류 배송 화면입니다. 원격 주행에 "도착하면 문자"를 얹은 것입니다.
//
// 주행 요청은 원격 주행과 같은 Mission Manager 서비스로 나가며 Safety 를
// 우회하지 않습니다. 이 화면이 원격 주행과 다른 것은 셋뿐입니다.
//   1. 받는 번호가 있어야 출발한다. 2026-11-17(사용자 B안)부터 모든 장소를 고를 수 있고, 저장된
//      번호가 없거나 다른 번호로 보내려면 '받는 번호'에 직접 쓴다(이번 배송에만, 장소에 저장 안 함).
//   2. 출발 전에 "물건을 실었다"를 한 번 확인한다 — 로봇은 적재 센서가 없어
//      물건이 있는지 모른다. 이 확인은 사람의 선언이다.
//   3. 도착하면 문자를 보내고 결과를 팝업으로 알린다. 팝업은 이 화면이 아니라
//      앱 셸이 어느 화면에서든 띄운다(widgets/delivery_notice_dialog.dart).
//   4. 받는 분께 메시지를 남길 수 있다(2026-11-17 사용자 승인, 목업
//      https://claude.ai/artifact/VLLp435ov8Mo6BKQ6trZf8). 도착 문자에 실려 45자 안으로 나간다.
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
import '../widgets/map_work_layout.dart';
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

  /// 받는 분께 메시지. 출발하면 비웁니다(다음 배송에 남지 않게).
  final TextEditingController _note = TextEditingController();

  /// 받는 번호. 장소를 고르면 저장된 번호로 채우고, 바꾸면 이번 배송에만 씁니다.
  final TextEditingController _phone = TextEditingController();

  /// 직접 쓴 번호를 그 장소 연락처로 저장할지(2026-11-17 사용자 승인, 목업 ⑥). 기본은 저장 안 함.
  bool _saveContact = false;

  @override
  void dispose() {
    _note.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _pick(LocationPoint location) {
    _selectedId = location.locationId;
    _saveContact = false;
    _fitNote(location);
    _phone.text = location.contactPhone.isEmpty ? '' : formatContactPhone(location.contactPhone);
  }

  /// 쓴 번호를 숫자로. 비었거나 모양이 틀리면 null.
  String? get _typedPhone {
    final digits = normalizeContactPhone(_phone.text);
    return digits == null || digits.isEmpty ? null : digits;
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    final supervisor = context.watch<SupervisorProvider>();

    final map = supervisor.selectedMap;
    // 모든 장소(2026-11-17 B안). 번호가 없는 곳은 '받는 번호'에 쓰면 됩니다.
    final candidates = supervisor.locationsFor(map?.mapId).toList(growable: false);
    final selected = _find(candidates, _selectedId);
    final job = supervisor.delivery;
    final busy = job != null && job.isActive;

    // 넓은 화면은 지도 왼쪽 + 카드 오른쪽, 세로 태블릿·폰 세로는 지도 위 고정(map_work_layout.dart).
    // 본문 제목은 뺐습니다 — 제목줄과 같은 말입니다(2026-11-17 제목·문구 간결화, 사용자 승인).
    return MapWorkLayout(
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
          // 장소·홈·금지구역을 함께 받습니다 — 지도 설정·원격 주행의 '새로고침'과 같은
          // 버튼입니다(2026-10-12 사용자 결정으로 세 화면 글자를 맞춤).
          refreshIcon: Icons.refresh,
          refreshLabel: const Text('새로고침'),
        ),
        const SizedBox(height: 18),
        if (map == null)
          const NoMapCard()
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
            onSelectLocation: busy ? null : (location) => setState(() => _pick(location)),
          ),
          const SizedBox(height: 20),
          if (job != null) ...[
            _DeliveryStatusCard(job: job, supervisor: supervisor),
            const SizedBox(height: 20),
          ],
          _pickCard(context, supervisor, candidates, selected, busy),
          const SizedBox(height: 20),
          // 배송 관련은 이 탭에서 모두 관리합니다 — 지도 설정에서 연락처 칸을 뺐습니다(2026-11-17).
          _ContactsCard(
            locations: candidates,
            onEdit: (location) => _editContact(context, supervisor, location),
          ),
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
    // 2026-11-17 사용자 지시: 장소 칩 버튼들을 지우고 '배송 받을 곳'·'연락처'·'메시지' 세 칸으로 지정.
    return VicaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 누르면 목록, 글자를 치면 걸러지는 검색 드롭다운(2026-11-17 사용자, 목업 ⑧).
          DropdownMenu<String>(
            key: ValueKey('delivery-place-${selected?.locationId}'),
            initialSelection: selected?.locationId,
            enabled: !busy && candidates.isNotEmpty,
            expandedInsets: EdgeInsets.zero,
            label: const Text('배송 장소'), // 2026-11-17 사용자: '배송 받을 곳' → '배송 장소'
            hintText: candidates.isEmpty ? '장소 없음' : '장소 검색',
            leadingIcon: const Icon(Icons.search),
            enableFilter: true,
            requestFocusOnTap: true,
            menuHeight: 320,
            dropdownMenuEntries: [
              for (final location in candidates)
                DropdownMenuEntry<String>(
                  value: location.locationId,
                  label: location.name,
                  trailingIcon: Text(
                    location.canReceiveDelivery
                        ? maskContactPhone(location.contactPhone)
                        : '번호 없음',
                    style: TextStyle(
                      fontSize: 12,
                      color: location.canReceiveDelivery
                          ? VicaColors.muted
                          : const Color(0xFF8A5F1C),
                    ),
                  ),
                ),
            ],
            onSelected: (id) {
              final location = _find(candidates, id);
              if (location != null) {
                setState(() => _pick(location));
              }
            },
          ),
          const SizedBox(height: 14),
          _PhoneField(
            controller: _phone,
            saved: selected?.contactPhone ?? '',
            enabled: !busy && selected != null,
            onChanged: () => setState(() {}),
          ),
          if (selected != null &&
              _typedPhone != null &&
              _typedPhone != selected.contactPhone)
            CheckboxListTile(
              value: _saveContact,
              onChanged: busy ? null : (value) => setState(() => _saveContact = value ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              title: const Text('이 장소 연락처로 저장'),
            ),
          const SizedBox(height: 12),
          _NoteField(
            controller: _note,
            limit: deliveryNoteLimit(selected?.name ?? ''),
            enabled: !busy && selected != null,
            onChanged: () => setState(() {}),
          ),
          if (selected != null) ...[
            const SizedBox(height: 4),
            _SmsPreview(
              text: deliveryArrivalMessage(selected.name, note: _note.text),
            ),
          ],
          const SizedBox(height: 14),
          // 로봇은 물건이 실렸는지 모릅니다(적재 센서 없음). 그래서 사람이
          // 선언합니다. 이 체크 없이 출발하면 빈 손으로 가서 "물건 왔습니다"
          // 문자가 나갈 수 있습니다.
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
          PressScale(child: FilledButton.icon(
            // 요청 가능 여부(권한·접근성·E-stop·Nav2)는 Mission Manager가 판정합니다.
            onPressed: selected == null || !_loaded || busy || _typedPhone == null
                ? null
                : () => _confirmStart(context, supervisor, selected),
            icon: Icon(busy ? Icons.local_shipping : Icons.send),
            label: Text(busy ? '배송 중' : '배송 출발'),
          )),
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
    final note = deliveryNoteClean(_note.text);
    final phone = _typedPhone ?? '';
    // 직접 쓴 번호는 오타를 잡도록 전체를 보입니다. 저장된 번호 그대로면 지금처럼 가립니다.
    final typed = phone != location.contactPhone;
    final confirmed = await showVicaConfirm(
      context,
      icon: Icons.play_arrow_outlined,
      title: '${location.name}(으)로 배송 출발',
      rows: [
        VicaDialogRow(
          label: '문자',
          value: typed ? '${formatContactPhone(phone)} · 직접 입력' : maskContactPhone(phone),
        ),
        if (note.isNotEmpty) VicaDialogRow(label: '메시지', value: note),
      ],
      body: '로봇 주변 사람·장애물 확인',
      confirmLabel: '출발',
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    var message = await supervisor.startDelivery(settings, location, note: note, phone: phone);
    if (supervisor.delivery?.isActive == true && typed && _saveContact) {
      // 출발이 받아들여졌을 때만 장소에 저장합니다(거절된 배송의 번호를 남기지 않게).
      final (saved, saveMessage) =
          supervisor.saveLocation(settings, location.copyWith(contactPhone: phone));
      message = saved ? '$message · 연락처 저장' : '$message · $saveMessage';
    }
    if (!context.mounted) {
      return;
    }
    if (supervisor.delivery?.isActive == true) {
      // 다음 배송을 위해 적재 확인을 되돌립니다. 지난번 체크가 남아 있으면
      // 실지도 않은 물건을 실었다고 출발하게 됩니다. 메시지도 비웁니다.
      setState(() {
        _loaded = false;
        _note.clear();
        _phone.text = location.contactPhone.isEmpty ? '' : formatContactPhone(location.contactPhone);
      });
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // 다른 장소를 고르면 메시지 한도가 바뀝니다(장소 이름 길이). 넘친 끝은 자릅니다.
  void _fitNote(LocationPoint location) {
    final limit = deliveryNoteLimit(location.name);
    if (_note.text.length > limit) {
      _note.text = _note.text.substring(0, limit);
    }
  }

  /// 연락처 수정 창(목업 ⑦). 저장·지우기는 장소 저장 경로(/save_location)로 젯슨 장소 파일에 남습니다.
  Future<void> _editContact(
    BuildContext context,
    SupervisorProvider supervisor,
    LocationPoint location,
  ) async {
    final settings = context.read<SettingsProvider>().settings;
    // 창이 입력 칸 컨트롤러를 스스로 들고 정리합니다 — 닫히는 애니메이션 중에 버리면 오류가 납니다.
    final result = await showVicaDialog<String>(
      context: context,
      builder: (_) => _ContactEditDialog(location: location),
    );
    if (result == null || !context.mounted || result == location.contactPhone) {
      return;
    }
    final (ok, message) =
        supervisor.saveLocation(settings, location.copyWith(contactPhone: result));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? (result.isEmpty ? '${location.name} 연락처를 지웠습니다.' : '${location.name} 연락처를 저장했습니다.')
          : message),
    ));
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
      // 알림 기록(DeliveryPhase.label)과 같은 말(2026-10-12 사용자 결정).
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
          if (job.note.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              vicaKeepWords('메시지 · ${job.note}'),
              style: const TextStyle(
                  color: VicaColors.text, fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ],
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
            // 배송 중과 홈 복귀 중은 원격 주행과 같은 버튼 한 벌을 씁니다.
            // 홈 복귀 중 일시정지·재개는 미션이 복귀로 되돌립니다(2026-09-03).
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
            child: PressScale(child: FilledButton.icon(
              onPressed: hasHome
                  ? () =>
                      sendRobotCommand(context, supervisor.returnDeliveryNow)
                  : null,
              icon: const Icon(Icons.home),
              label: const Text('지금 복귀'),
            )),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: PressScale(child: OutlinedButton.icon(
              onPressed: supervisor.cancelDeliveryReturn,
              icon: const Icon(Icons.timer_off_outlined),
              label: const Text('복귀 취소'),
            )),
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: PressScale(child: OutlinedButton.icon(
            onPressed: hasHome
                ? () => sendRobotCommand(context, supervisor.returnDeliveryNow)
                : null,
            icon: const Icon(Icons.home_outlined),
            label: Text(hasHome ? '홈으로 복귀' : '홈이 없습니다'),
          )),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: PressScale(child: OutlinedButton.icon(
            onPressed: supervisor.clearDelivery,
            icon: const Icon(Icons.check),
            label: const Text('지우기'),
          )),
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
          child: PressScale(child: FilledButton.icon(
            onPressed: () => sendRobotCommand(
                context, (_) => supervisor.confirmDeliveryArrival()),
            icon: const Icon(Icons.sms_outlined),
            label: const Text('도착 처리 · 문자'),
          )),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: PressScale(child: OutlinedButton.icon(
            onPressed: supervisor.clearDelivery,
            icon: const Icon(Icons.delete_outline),
            label: const Text('지우기'),
          )),
        ),
      ],
    );
  }

  Widget _finishedButtons() {
    return PressScale(child: OutlinedButton.icon(
      onPressed: widget.supervisor.clearDelivery,
      icon: const Icon(Icons.check),
      label: const Text('배송 완료 · 지우기'),
    ));
  }
}

/// 받는 분께 메시지 칸. 한도는 장소 이름 길이에 따라 다릅니다([deliveryNoteLimit], 410호면 31).
class _NoteField extends StatelessWidget {
  const _NoteField({
    required this.controller,
    required this.limit,
    required this.enabled,
    required this.onChanged,
  });

  final TextEditingController controller;
  final int limit;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      maxLength: limit,
      minLines: 1,
      maxLines: 2,
      // 문자는 한 줄로 나갑니다. 줄바꿈은 받지 않습니다.
      keyboardType: TextInputType.text,
      textInputAction: TextInputAction.done,
      onChanged: (_) => onChanged(),
      decoration: const InputDecoration(
        labelText: '메시지 (선택)',
        hintText: '받는 분께 · 예: 서류 두 장입니다',
      ),
    );
  }
}

/// 도착 문자 미리보기. 실제로 나갈 본문 그대로입니다.
class _SmsPreview extends StatelessWidget {
  const _SmsPreview({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: VicaColors.surfaceSunken,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '도착 문자 미리보기',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: VicaColors.muted),
          ),
          const SizedBox(height: 4),
          Text(
            vicaKeepWords(text),
            style: const TextStyle(fontSize: 13, height: 1.5, color: VicaColors.text),
          ),
        ],
      ),
    );
  }
}

/// 받는 번호 칸(2026-11-17 B안). 저장된 번호가 있으면 채워 두고, 없으면 꼭 써야 합니다.
class _PhoneField extends StatelessWidget {
  const _PhoneField({
    required this.controller,
    required this.saved,
    required this.enabled,
    required this.onChanged,
  });

  final TextEditingController controller;

  /// 장소에 저장된 번호(숫자). 비면 번호 없는 장소.
  final String saved;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final digits = normalizeContactPhone(controller.text);
    final String helper;
    String? error;
    if (!enabled) {
      helper = '';
    } else if (controller.text.trim().isEmpty) {
      helper = '';
      error = saved.isEmpty ? '저장된 번호 없음 · 써 주세요(이번 배송만)' : '번호를 쓰세요';
    } else if (digits == null) {
      helper = '';
      error = '휴대폰 번호 모양이 아님';
    } else if (saved.isNotEmpty && digits == saved) {
      helper = '저장된 번호 · 바꾸면 이번 배송만';
    } else {
      helper = '직접 입력 · 이번 배송만 씀';
    }
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.phone,
      onChanged: (_) => onChanged(),
      decoration: InputDecoration(
        labelText: '연락처',
        hintText: '010-0000-0000',
        helperText: helper.isEmpty ? null : helper,
        errorText: error,
      ),
    );
  }
}

/// 연락처 관리(목업 ⑥). 장소마다 저장된 번호(가림) 또는 '없음'. 누르면 수정 창.
class _ContactsCard extends StatelessWidget {
  const _ContactsCard({required this.locations, required this.onEdit});

  final List<LocationPoint> locations;
  final ValueChanged<LocationPoint> onEdit;

  @override
  Widget build(BuildContext context) {
    return VicaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('연락처 관리', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          if (locations.isEmpty)
            const Text('장소가 아직 없습니다.', style: TextStyle(color: VicaColors.muted))
          else
            for (final (index, location) in locations.indexed) ...[
              if (index > 0) const Divider(height: 1),
              PressScale(child: InkWell(
                onTap: () => onEdit(location),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 52),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          location.name,
                          overflow: TextOverflow.ellipsis,
                          // 2026-11-17 사용자: 연락처 관리 글자를 조금 작게(15 → 14, 번호 13 → 12).
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700, color: VicaColors.text),
                        ),
                      ),
                      Text(
                        location.canReceiveDelivery ? maskContactPhone(location.contactPhone) : '없음',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: location.canReceiveDelivery ? FontWeight.w400 : FontWeight.w700,
                          color: location.canReceiveDelivery ? VicaColors.muted : const Color(0xFF8A5F1C),
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: VicaColors.muted),
                    ],
                  ),
                ),
              )),
            ],
        ],
      ),
    );
  }
}

/// 연락처 수정 창(목업 ⑦). 돌려주는 값: 저장할 숫자, 지우기면 '', 취소면 null.
class _ContactEditDialog extends StatefulWidget {
  const _ContactEditDialog({required this.location});

  final LocationPoint location;

  @override
  State<_ContactEditDialog> createState() => _ContactEditDialogState();
}

class _ContactEditDialogState extends State<_ContactEditDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.location.contactPhone.isEmpty
        ? ''
        : formatContactPhone(widget.location.contactPhone),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final digits = normalizeContactPhone(_controller.text);
    final valid = digits != null && digits.isNotEmpty;
    return VicaDialog(
      icon: Icons.contact_phone_outlined,
      title: '${widget.location.name} 연락처',
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.phone,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: '연락처',
          hintText: '010-0000-0000',
          errorText: _controller.text.trim().isNotEmpty && digits == null
              ? '휴대폰 번호 모양이 아님'
              : null,
        ),
      ),
      actions: [
        if (widget.location.contactPhone.isNotEmpty)
          PressScale(child: TextButton(
            onPressed: () => Navigator.of(context).pop(''),
            style: TextButton.styleFrom(foregroundColor: VicaColors.red),
            child: const Text('지우기'),
          )),
        VicaCancelButton(onPressed: () => Navigator.of(context).pop()),
        PressScale(child: FilledButton(
          onPressed: valid ? () => Navigator.of(context).pop(digits) : null,
          child: const Text('저장'),
        )),
      ],
    );
  }
}
