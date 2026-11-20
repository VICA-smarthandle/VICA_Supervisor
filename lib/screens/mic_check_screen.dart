// 이 파일은 로봇의 마이크 점검기(`MicCheckController`)와 이어진 전체 화면 '마이크 점검'을 그립니다.
// 위에서 아래로 단계 → 실시간 → 최근 10초 → 실시간 판정 → 진행 순입니다(캔버스 107·108).
// 넓은 창(폭 600 이상)에서는 왼쪽(단계·실시간·최근 10초·판정)과 오른쪽(진행·결과표·값 고치기) 두 칸입니다.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/layout_breakpoints.dart';
import '../models/mic_check.dart';
import '../providers/supervisor_provider.dart';
import '../services/mic_check_controller.dart';
import '../widgets/mic_check/event_list.dart';
import '../widgets/mic_check/live_card.dart';
import '../widgets/mic_check/progress_card.dart';
import '../widgets/mic_check/recent_graph.dart';
import '../widgets/mic_check/result_card.dart';
import '../widgets/mic_check/sheets.dart';
import '../widgets/mic_check/step_card.dart';
import '../widgets/mic_check/values_card.dart';
import '../widgets/vica_ui.dart';

/// 끊겨 보내지 못했을 때 띄우는 안내.
const kMicSendFailed = '연결이 끊겨 보내지 못했습니다 · 다시 붙은 뒤 누르세요';

class MicCheckScreen extends StatefulWidget {
  const MicCheckScreen({super.key, required this.controller, this.supervisor});

  final MicCheckController controller;

  /// 모드 상태(`modeStatus.micCheck`)를 보고 점검기가 스스로 끝났는지 알아냅니다. 안 주면 Provider 에서 찾고,
  /// 그것도 없으면 이 감시만 하지 않습니다.
  final SupervisorProvider? supervisor;

  @override
  State<MicCheckScreen> createState() => _MicCheckScreenState();
}

class _MicCheckScreenState extends State<MicCheckScreen> {
  StreamSubscription<String>? _toasts;
  SupervisorProvider? _supervisor;

  // 이 화면이 '끝내기'로 점검기를 내리는 중이면 모드 상태 변화를 '스스로 끝남'으로 보지 않습니다.
  bool _finishing = false;
  bool _wasActive = false;

  // '저장'을 눌러 save_preview 를 기다리는 중일 때만 도착한 미리보기를 시트로 띄웁니다(예전 것은 무시).
  bool _awaitPreview = false;
  MicCheckSavePreview? _lastPreview;

  @override
  void initState() {
    super.initState();
    _toasts = widget.controller.toasts.listen(_snack);
    _lastPreview = widget.controller.savePreview;
    widget.controller.addListener(_onController);
    _supervisor = widget.supervisor ?? _findSupervisor();
    _wasActive = _supervisor?.modeStatus?.micCheckActive ?? false;
    _supervisor?.addListener(_onMode);
  }

  SupervisorProvider? _findSupervisor() {
    try {
      return context.read<SupervisorProvider>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  @override
  void dispose() {
    _toasts?.cancel();
    widget.controller.removeListener(_onController);
    _supervisor?.removeListener(_onMode);
    super.dispose();
  }

  // 점검기가 준비 중에 죽는 등 이 화면 밖에서 끝났을 때(켜짐 → inactive·failed) 화면이 멈춰 있지 않게 닫습니다.
  void _onMode() {
    final m = _supervisor?.modeStatus;
    if (m == null) return;
    final active = m.micCheckActive;
    final ended = m.micCheck == 'inactive' || m.micCheck == 'failed';
    if (_wasActive && ended && !_finishing && mounted) {
      _snack('점검기가 끝났습니다');
      Navigator.of(context).pop(false);
    }
    _wasActive = active;
  }

  void _onController() {
    final p = widget.controller.savePreview;
    if (!_awaitPreview || p == null || identical(p, _lastPreview)) return;
    _lastPreview = p;
    _awaitPreview = false;
    _confirmSave(p);
  }

  Future<void> _confirmSave(MicCheckSavePreview p) async {
    if (await showMicSaveSheet(context, p) && mounted) _send('save');
  }

  Future<void> _confirmRestore() async {
    if (await showMicRestoreSheet(context) && mounted) _send('restore');
  }

  // '끝내기': 확인 → finish 를 보내고 닫습니다. 끊겨 못 보내면 모드 노드에 점검기 내리기를 대신 요청합니다.
  Future<void> _confirmFinish() async {
    if (!await showMicFinishSheet(context) || !mounted) return;
    _finishing = true;
    // 준비 중(status 없음)에는 점검기가 명령을 처리하지 않습니다. 바로 내립니다(칩은 이미 .env 값).
    if (widget.controller.status == null || !widget.controller.send('finish')) {
      await _supervisor?.stopMicCheck();
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  // 끊긴 동안 누른 버튼은 조용히 버리지 않고 안내합니다.
  bool _send(String cmd, [Map<String, Object?> args = const {}]) {
    final ok = widget.controller.send(cmd, args);
    if (!ok) _snack(kMicSendFailed);
    return ok;
  }

  bool _sendValues(String cmd, [Map<String, Object?> args = const {}]) {
    final ok = _send(cmd, args);
    if (ok && cmd == 'save_preview') _awaitPreview = true;
    return ok;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VicaColors.background,
      appBar: AppBar(
        title: const Text('마이크 점검'),
        actions: [
          TextButton(
            key: const ValueKey('mic_check_finish'),
            onPressed: _confirmFinish,
            child: const Text('끝내기'),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) => LayoutBuilder(builder: (context, c) {
          final pad = VicaBreakpoints.horizontalPadding(c.maxWidth);
          final compact = VicaBreakpoints.isCompact(c.maxWidth);
          final left = _leftCards();
          final right = _rightCards();
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(pad, 12, pad, 28),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: VicaBreakpoints.contentMaxWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(),
                    if (compact)
                      ...[...left, ...right]
                    else
                      Row(
                        key: const ValueKey('mic_check_columns'),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              key: const ValueKey('mic_check_left'),
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: left,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              key: const ValueKey('mic_check_right'),
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: right,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _header() {
    final c = widget.controller;
    final st = c.status;
    final Widget chip;
    if (st == null) {
      chip = const _HeadChip('● 칩 확인 중', VicaColors.muted);
    } else if (st.chipOk) {
      chip = const _HeadChip('● 칩 정상', VicaColors.green);
    } else {
      chip = const _HeadChip('● 칩 문제', VicaColors.red);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (st != null && st.place.isNotEmpty)
                Text(st.place, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              c.connected
                  ? const _HeadChip('● 연결됨', VicaColors.green)
                  : const _HeadChip('● 끊김 · 다시 붙는 중', VicaColors.red),
              chip,
            ],
          ),
          if (st != null && !st.chipOk)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                '칩에 값을 쓰지 못해 시작하지 않습니다 · 끝내기 뒤 다시 시작하세요',
                style: TextStyle(color: VicaColors.red, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _leftCards() {
    final c = widget.controller;
    final st = c.status;
    if (st == null) {
      return const [
        VicaCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('준비 중', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              SizedBox(height: 6),
              Text('모델 올리는 중 · 1~2분', style: TextStyle(color: VicaColors.muted)),
            ],
          ),
        ),
      ];
    }
    final listen = st.values['listen_min_rms'];
    return [
      MicStepCard(status: st, frame: c.frame, busy: c.busy, onSend: _send),
      MicLiveCard(status: st, frame: c.frame),
      MicRecentGraph(
        rms: c.rmsHistory,
        wake: c.wakeHistory,
        listenMin: listen is num ? listen.toDouble() : null,
      ),
      MicEventList(events: c.events),
    ];
  }

  // 진행 → 결과표(채점이 있을 때) → 값 고치기 순입니다(캔버스 109).
  List<Widget> _rightCards() {
    final c = widget.controller;
    final st = c.status;
    if (st == null) return const [];
    return [
      MicProgressCard(status: st, frame: c.frame, onSend: _send),
      if (c.results != null) MicResultCard(results: c.results!, busy: c.busy != null),
      MicValuesCard(status: st, onSend: _sendValues, onRestore: _confirmRestore),
    ];
  }
}

class _HeadChip extends StatelessWidget {
  const _HeadChip(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color)),
      );
}
