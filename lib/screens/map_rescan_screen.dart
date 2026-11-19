// 이 파일은 '지도 다시 스캔하기' 화면입니다(목업 78~81).
//
// 로봇을 세워 둔 채 라이다로 주변(반경 1·2·3 m)을 다시 스캔해, 지도와 달라진 칸만 고칩니다.
// 순서는 로봇(map_fix_node)이 끌고 갑니다 — 자세 다시 맞춤 → 사람이 원 밖으로 물러나기 5초 →
// 스캔 5초 → 미리보기. 화면은 토픽 /vica/map_fix/state 의 단계(phase)를 그대로 보여 주고,
// [적용]을 눌러야 지도 파일이 바뀝니다.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/map_fix.dart';
import '../models/vica_map.dart';
import '../providers/settings_provider.dart';
import '../providers/supervisor_provider.dart';
import '../widgets/map_canvas.dart';
import '../widgets/map_fix_overlay.dart';
import '../widgets/map_work_layout.dart';
import '../widgets/vica_ui.dart';

/// 부분 스캔을 못 하는 사유를 사람 말로 바꿉니다(목업 81).
///
/// [ambiguous] 는 구분되지 않는 방향('forward' · 'lateral' · 'yaw')입니다. 아는 사유가 아니면
/// 로봇이 보낸 [message] 를 그대로 씁니다.
String mapFixFailText(
  String reason, {
  List<String> ambiguous = const [],
  String message = '',
}) {
  switch (reason) {
    case 'ambiguous':
      final where = mapFixAmbiguousWords(ambiguous);
      final yaw = where.remove('방향');
      final String what;
      if (where.isEmpty) {
        what = '방향을';
      } else if (yaw) {
        what = '${where.join(' · ')} 위치와 방향을';
      } else {
        what = '${where.join(' · ')} 위치를';
      }
      return '$what 구분할 수 없습니다. 모서리나 문틀이 보이는 곳으로 옮겨 주세요.';
    case 'low_match':
    case 'no_pose':
      return '지도와 라이다가 맞지 않습니다. 초기 위치를 다시 잡아 주세요.';
    case 'moved':
      return '로봇이 움직였습니다. 세운 뒤 다시 눌러 주세요.';
    case 'no_change':
      return '이 범위에서 변경된 곳을 찾지 못했습니다.';
    case 'busy_driving':
      return '주행 중에는 지도를 수정할 수 없습니다.';
  }
  return message.isEmpty ? '부분 스캔을 마치지 못했습니다.' : message;
}

/// 'forward' → '앞뒤', 'lateral' → '좌우', 'yaw' → '방향'. 모르는 값은 버립니다.
List<String> mapFixAmbiguousWords(List<String> ambiguous) => [
      if (ambiguous.contains('forward')) '앞뒤',
      if (ambiguous.contains('lateral')) '좌우',
      if (ambiguous.contains('yaw')) '방향',
    ];

class MapRescanScreen extends StatefulWidget {
  const MapRescanScreen({super.key, required this.map});

  /// 다시 스캔할 지도(주행 지도). 적용했으면 로봇의 응답([MapFixResult])을 들고 닫힙니다.
  final VicaMap map;

  @override
  State<MapRescanScreen> createState() => _MapRescanScreenState();
}

class _MapRescanScreenState extends State<MapRescanScreen> {
  late final SupervisorProvider _supervisor;
  double _radius = kMapFixDefaultRadius;
  MapFixScanCheck? _check;
  bool _checking = false;
  bool _busy = false;
  bool _failOpen = false;
  String _session = '';
  String _note = '';

  // 시작 요청은 통과했는데 첫 진행(토픽)이 아직 안 온 동안입니다. 노드는 0.5초마다 진행을
  // 보내므로 [_firstStateWait] 안에 안 오면 로봇 쪽이 멈춘 것으로 보고 범위 고르기로 돌아갑니다.
  bool _awaitingFirst = false;
  Timer? _firstStateTimer;
  static const _firstStateWait = Duration(seconds: 5);

  String get _mapId => widget.map.mapId;

  @override
  void initState() {
    super.initState();
    _supervisor = context.read<SupervisorProvider>();
    _supervisor.addListener(_onSupervisor);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      // 이 화면을 열기 전에 끝난 실패(다른 기기에서 돌린 스캔 등)는 지금 일이 아닙니다.
      // 알림으로 띄우지 않고 치웁니다.
      if (_scanOf(_supervisor)?.isFailed ?? false) {
        _supervisor.clearMapFixScan();
      }
      _runCheck();
    });
  }

  @override
  void dispose() {
    _firstStateTimer?.cancel();
    _supervisor.removeListener(_onSupervisor);
    super.dispose();
  }

  /// 이 지도의 진행만 봅니다(다른 지도의 세션이면 없는 것으로 칩니다).
  MapFixScanState? _scanOf(SupervisorProvider supervisor) {
    final scan = supervisor.mapFixScan;
    return scan == null || (scan.mapId.isNotEmpty && scan.mapId != _mapId)
        ? null
        : scan;
  }

  void _onSupervisor() {
    final scan = _scanOf(_supervisor);
    if (scan != null && _awaitingFirst && mounted) {
      // 첫 진행이 왔습니다. 이제부터 화면은 토픽의 단계만 따릅니다.
      _firstStateTimer?.cancel();
      setState(() => _awaitingFirst = false);
    }
    if (scan == null || !scan.isFailed || _failOpen || !mounted) {
      return;
    }
    _failOpen = true;
    // 알림(notifyListeners) 도중에는 창을 띄울 수 없어 한 박자 뒤에 띄웁니다.
    WidgetsBinding.instance.addPostFrameCallback((_) => _showFailed(scan));
    WidgetsBinding.instance.scheduleFrame();
  }

  Future<void> _showFailed(MapFixScanState scan) async {
    if (!mounted) {
      return;
    }
    final where = mapFixAmbiguousWords(scan.ambiguous);
    await showVicaNotice(
      context,
      icon: Icons.error_outline,
      iconColor: VicaColors.red,
      title: '여기서는 다시 스캔할 수 없습니다',
      body: mapFixFailText(scan.reason, ambiguous: scan.ambiguous),
      rows: [
        if (scan.score > 0)
          VicaDialogRow(label: '위치 맞춤', value: mapFixPercent(scan.score)),
        if (where.isNotEmpty)
          VicaDialogRow(label: '구분되지 않는 방향', value: where.join(' · ')),
      ],
    );
    _failOpen = false;
    if (!mounted) {
      return;
    }
    // 실패를 다 봤으니 치우고 범위 고르기로 돌아갑니다. 자세도 다시 확인합니다.
    setState(() => _session = '');
    _supervisor.clearMapFixScan();
    _runCheck();
  }

  /// 지금 스캔으로 자세만 다시 맞춰 '위치 맞춤 %'와 라이다 점을 받습니다.
  Future<void> _runCheck() async {
    if (_checking) {
      return;
    }
    setState(() {
      _checking = true;
      _note = '';
    });
    final reply = await _supervisor.mapFix(_mapId, 'scan_check');
    if (!mounted) {
      return;
    }
    setState(() {
      _checking = false;
      _check = reply.accepted ? MapFixScanCheck.fromResult(reply.result) : null;
      _note = reply.accepted
          ? ''
          : mapFixFailText(reply.reason, message: reply.message);
    });
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _note = '';
    });
    final reply = await _supervisor.mapFix(
      _mapId,
      'scan_start',
      args: {'radius_m': _radius},
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      if (reply.accepted) {
        _session = '${reply.result['session'] ?? ''}';
        // 응답보다 첫 진행이 먼저 와 있으면 기다릴 것이 없습니다.
        _awaitingFirst = _scanOf(_supervisor) == null;
      } else {
        _note = mapFixFailText(reply.reason, message: reply.message);
      }
    });
    if (_awaitingFirst) {
      _firstStateTimer?.cancel();
      _firstStateTimer = Timer(_firstStateWait, () {
        if (mounted && _awaitingFirst) {
          setState(() {
            _awaitingFirst = false;
            _session = '';
            _note = '로봇이 스캔 진행을 보내지 않습니다. 다시 눌러 주세요.';
          });
        }
      });
    }
  }

  /// 세션을 가리키는 요청(중지·적용·버리기)을 보냅니다.
  Future<MapFixResult> _sessionCall(
    String action,
    MapFixScanState? scan,
  ) async {
    setState(() {
      _busy = true;
      _note = '';
    });
    final session =
        (scan?.session.isNotEmpty ?? false) ? scan!.session : _session;
    final reply = await _supervisor.mapFix(
      _mapId,
      action,
      args: {'session': session},
    );
    if (mounted) {
      setState(() => _busy = false);
    }
    return reply;
  }

  Future<void> _stop(MapFixScanState? scan) async {
    final reply = await _sessionCall('scan_cancel', scan);
    if (!mounted) {
      return;
    }
    // 세션이 이미 끝났어도(no_session) 화면은 범위 고르기로 돌아갑니다.
    _firstStateTimer?.cancel();
    setState(() {
      _session = '';
      _awaitingFirst = false;
    });
    _supervisor.clearMapFixScan();
    if (!reply.accepted && reply.reason != 'no_session') {
      setState(() => _note = reply.message);
    }
  }

  Future<void> _apply(MapFixScanState scan) async {
    final reply = await _sessionCall('scan_apply', scan);
    if (!mounted) {
      return;
    }
    if (reply.accepted) {
      _supervisor.clearMapFixScan();
      Navigator.of(context).pop(reply);
      return;
    }
    setState(
      () => _note = mapFixFailText(reply.reason, message: reply.message),
    );
  }

  Future<void> _discard(MapFixScanState scan) async {
    await _sessionCall('scan_discard', scan);
    if (!mounted) {
      return;
    }
    setState(() => _session = '');
    _supervisor.clearMapFixScan();
  }

  @override
  Widget build(BuildContext context) {
    final supervisor = context.watch<SupervisorProvider>();
    final settings = context.watch<SettingsProvider>().settings;
    final map = supervisor.maps.firstWhere(
      (candidate) => candidate.mapId == _mapId,
      orElse: () => widget.map,
    );
    final live = _scanOf(supervisor);
    // 실패는 알림 창으로 보이고, 그 뒤의 화면은 범위 고르기입니다.
    final scan = (live?.isFailed ?? false) ? null : live;
    // 시작 요청은 통과했는데 첫 진행이 아직 안 온 짧은 동안도 진행 중으로 봅니다.
    final running = scan?.running ?? _awaitingFirst;
    final preview = scan?.isPreview ?? false;
    final robot = supervisor.primaryRobot;
    final radius = (scan != null && scan.radiusM > 0) ? scan.radiusM : _radius;

    return PopScope(
      // 스캔 중과 미리보기에서는 뒤로 갈 수 없습니다 — [중지]·[적용]·[버리기]로만 나갑니다.
      canPop: !running && !preview && !_busy,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !running && !preview,
          title: const Text('지도 다시 스캔하기'),
        ),
        body: SafeArea(
          child: MapWorkLayout(
            children: [
              ResponsiveMapFrame(
                map: map,
                child: MapCanvas(
                  map: map,
                  settings: settings,
                  locations: const [],
                  robot: robot,
                  // 확인한 자세에서 본 라이다 점은 범위를 고르는 동안만 보입니다.
                  scanHits: (running || preview)
                      ? const []
                      : (_check?.hits ?? const []),
                  overlayBuilder: (toPixel) => [
                    if (robot != null && robot.mapId == map.mapId)
                      ...mapFixRadiusOverlay(
                        toPixel,
                        x: robot.x,
                        y: robot.y,
                        radiusM: radius,
                        style: preview
                            ? MapFixCircleStyle.outline
                            : running
                                ? MapFixCircleStyle.keepOut
                                : MapFixCircleStyle.range,
                        label: preview
                            ? ''
                            : running
                                ? '이 원 밖으로'
                                : mapFixMetres(radius),
                      ),
                    if (preview)
                      ...mapFixCellsOverlay(
                        toPixel,
                        cells: scan!.cells,
                        resolution: map.resolution,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (preview)
                ..._previewBody(scan!)
              else if (running)
                ..._runningBody(scan, radius)
              else
                ..._rangeBody(robot == null ? null : robot.status != 'moving'),
            ],
          ),
        ),
      ),
    );
  }

  // ---- 범위 고르기(목업 78) ------------------------------------------------

  /// [stopped] 는 앱이 받은 로봇 상태로 본 값입니다(모르면 null). 정지 판정의 주인은 노드입니다.
  List<Widget> _rangeBody(bool? stopped) {
    final check = _check;
    return [
      VicaCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text('범위', style: Theme.of(context).textTheme.titleMedium),
            ),
            for (final choice in kMapFixRadii) ...[
              const SizedBox(width: 8),
              _RadiusChip(
                label: mapFixMetres(choice),
                selected: choice == _radius,
                onTap: _busy ? null : () => setState(() => _radius = choice),
              ),
            ],
          ],
        ),
      ),
      const _Hint('다시 스캔하고 싶은 곳에 비카를 두세요.\n범위가 작을수록 정확합니다.'),
      const SizedBox(height: 12),
      VicaCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CheckRow(ok: stopped, title: '로봇 정지'),
            const SizedBox(height: 12),
            _CheckRow(
              ok: check?.ok,
              title: _checking
                  ? '위치 맞춤 확인 중...'
                  : check == null
                      ? '위치 맞춤'
                      : '위치 맞춤 ${mapFixPercent(check.score)}',
              trailing: '지도와 라이다',
            ),
            if (check != null && !check.ok) ...[
              const SizedBox(height: 8),
              _noteText(
                mapFixFailText(check.reason, ambiguous: check.ambiguous),
              ),
            ],
            if (_note.isNotEmpty) ...[
              const SizedBox(height: 8),
              _noteText(_note),
            ],
            const SizedBox(height: 14),
            VicaButtonRow(
              foldWidth: 240,
              children: [
                if (check != null && check.ok)
                  PressScale(
                    child: FilledButton(
                      onPressed: (_busy || stopped == false) ? null : _start,
                      child: const Text('스캔 시작'),
                    ),
                  )
                else
                  // 자세가 안 맞으면 시작해도 바로 실패합니다. 로봇을 옮긴 뒤 다시 확인합니다.
                  PressScale(
                    child: FilledButton(
                      onPressed: _checking ? null : _runCheck,
                      child: const Text('다시 확인'),
                    ),
                  ),
                VicaCancelButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ],
        ),
      ),
    ];
  }

  // ---- 물러나기와 스캔(목업 79) --------------------------------------------

  List<Widget> _runningBody(MapFixScanState? scan, double radius) {
    final phase = scan?.phase ?? 'refine';
    final scanning = phase == 'scanning';
    final refined = phase != 'refine';
    return [
      VicaCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(
                    scanning ? '스캔 중' : '스캔 준비 중',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Text(
                  '범위 ${mapFixMetres(radius)}',
                  style: const TextStyle(fontSize: 13, color: VicaColors.muted),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (!refined)
              const Center(
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '${scan?.remainingS ?? 0}',
                    style: const TextStyle(
                      fontSize: 56,
                      height: 1.07,
                      fontWeight: FontWeight.w800,
                      color: VicaColors.primaryDark,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    scanning ? '초 남음' : '초 뒤 스캔',
                    style: const TextStyle(
                      fontSize: 15,
                      color: VicaColors.muted,
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 16),
            const Divider(height: 1, color: VicaColors.border),
            const SizedBox(height: 16),
            _StepRow(
              state: refined ? _StepState.done : _StepState.active,
              title: '위치 다시 맞춤',
              detail: refined && scan != null
                  ? '안 바뀐 벽에 맞춤 · ${_movedText(scan)}'
                  : '',
            ),
            const SizedBox(height: 14),
            _StepRow(
              state: scanning
                  ? _StepState.done
                  : refined
                      ? _StepState.active
                      : _StepState.waiting,
              title: '원 밖으로 물러나기',
              detail: '원 안에 있으면 지도에 찍힙니다',
            ),
            const SizedBox(height: 14),
            _StepRow(
              state: scanning ? _StepState.active : _StepState.waiting,
              title: '스캔 5초',
            ),
            if (_note.isNotEmpty) ...[
              const SizedBox(height: 12),
              _noteText(_note),
            ],
          ],
        ),
      ),
      PressScale(
        child: OutlinedButton(
          onPressed: _busy ? null : () => _stop(scan),
          style: OutlinedButton.styleFrom(
            foregroundColor: kMapFixEraseColor,
            side: const BorderSide(color: VicaColors.borderStrong),
          ),
          child: const Text('중지'),
        ),
      ),
    ];
  }

  /// '3 cm · 0.4° 옮김'.
  String _movedText(MapFixScanState scan) {
    final centimetres = (scan.movedM * 100).round();
    final degrees = scan.movedDeg.abs().toStringAsFixed(1);
    return '$centimetres cm · $degrees° 옮김';
  }

  // ---- 미리보기(목업 80) ----------------------------------------------------

  List<Widget> _previewBody(MapFixScanState scan) {
    return [
      Row(
        children: [
          Expanded(
            child: _LegendChip(
              color: kMapFixAddedColor,
              label: '새로 생김',
              count: '${scan.added}칸',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _LegendChip(
              color: kMapFixRemovedColor,
              label: '없어짐',
              count: '${scan.removed}칸',
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      VicaCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '위치 맞춤',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  vicaKeepWords('같은 스캔으로 잰 값'),
                  style: const TextStyle(fontSize: 12, color: VicaColors.muted),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _Score(
                  label: '수정 전',
                  value: mapFixPercent(scan.scoreBefore),
                  color: VicaColors.muted,
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14),
                  child: Icon(
                    Icons.arrow_forward,
                    size: 24,
                    color: VicaColors.muted,
                  ),
                ),
                _Score(
                  label: '수정 후',
                  value: mapFixPercent(scan.scoreAfter),
                  color: VicaColors.green,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              vicaKeepWords('다른 장애물이 찍혔으면 적용한 뒤 지우기로 지우세요.'),
              style: const TextStyle(
                fontSize: 13,
                height: 1.55,
                color: VicaColors.muted,
              ),
            ),
            if (_note.isNotEmpty) ...[
              const SizedBox(height: 8),
              _noteText(_note),
            ],
            const SizedBox(height: 14),
            VicaButtonRow(
              foldWidth: 240,
              children: [
                PressScale(
                  child: FilledButton(
                    onPressed: _busy ? null : () => _apply(scan),
                    child: Text(_busy ? '적용 중...' : '적용'),
                  ),
                ),
                VicaCancelButton(
                  label: '버리기',
                  onPressed: _busy ? null : () => _discard(scan),
                ),
              ],
            ),
          ],
        ),
      ),
    ];
  }

  Widget _noteText(String text) => Text(
        vicaKeepWords(vicaBreakAtSentences(text)),
        style: const TextStyle(
            fontSize: 12.5, height: 1.45, color: VicaColors.red),
      );
}

/// 지도 아래의 안내(옅은 청록 상자). 줄바꿈(\n)은 그대로 두고 줄 안에서는 어절 단위로 접힙니다.
class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: VicaColors.accentTint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text.split('\n').map(vicaKeepWords).join('\n'),
        style: const TextStyle(
          fontSize: 12.5,
          height: 1.45,
          color: VicaColors.primaryDark,
        ),
      ),
    );
  }
}

/// 범위 선택 단추 하나('1 m' · '2 m' · '3 m').
class _RadiusChip extends StatelessWidget {
  const _RadiusChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: selected ? VicaColors.accentTint : VicaColors.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: selected ? VicaColors.primary : VicaColors.borderStrong,
              width: selected ? 2 : 1,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 60,
              height: 44,
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                    color: selected ? VicaColors.primaryDark : VicaColors.text,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 준비 항목 한 줄. [ok] 가 true 면 초록 체크, false 면 주황 느낌표, null 이면 회색 빈 원입니다.
class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.ok, required this.title, this.trailing = ''});

  final bool? ok;
  final String title;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    final color = switch (ok) {
      true => VicaColors.green,
      false => VicaColors.degraded,
      null => VicaColors.borderStrong,
    };
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: ok == null
              ? null
              : Icon(
                  ok! ? Icons.check : Icons.priority_high,
                  size: 14,
                  color: Colors.white,
                ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            vicaKeepWords(title),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
        if (trailing.isNotEmpty)
          Text(
            vicaKeepWords(trailing),
            style: const TextStyle(fontSize: 12, color: VicaColors.muted),
          ),
      ],
    );
  }
}

enum _StepState { waiting, active, done }

/// 진행 단계 한 줄(끝남 · 지금 · 아직).
class _StepRow extends StatelessWidget {
  const _StepRow({required this.state, required this.title, this.detail = ''});

  final _StepState state;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final waiting = state == _StepState.waiting;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: state == _StepState.done ? VicaColors.primaryDark : null,
            border: state == _StepState.done
                ? null
                : Border.all(
                    color:
                        waiting ? VicaColors.borderStrong : VicaColors.primary,
                    width: waiting ? 2 : 3,
                  ),
          ),
          child: state == _StepState.done
              ? const Icon(Icons.check, size: 14, color: Colors.white)
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                vicaKeepWords(title),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: waiting ? FontWeight.w500 : FontWeight.w700,
                  color: waiting ? VicaColors.muted : VicaColors.text,
                ),
              ),
              if (detail.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  vicaKeepWords(detail),
                  style: const TextStyle(fontSize: 12, color: VicaColors.muted),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// 미리보기의 범례 한 칸('■ 새로 생김 41칸').
class _LegendChip extends StatelessWidget {
  const _LegendChip({
    required this.color,
    required this.label,
    required this.count,
  });

  final Color color;
  final String label;
  final String count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: VicaColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: VicaColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 14,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text.rich(
              TextSpan(
                text: '${vicaKeepWords(label)} ',
                children: [
                  TextSpan(
                    text: count,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// 위치 맞춤 값 하나('수정 전' / '62 %').
class _Score extends StatelessWidget {
  const _Score({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: VicaColors.muted),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }
}
