// 이 파일은 '지도 부분 지우기' 화면입니다(목업 76·77).
//
// 지도에서 실제로 없어진 장애물(검은 칸)과 회색 점을 사각형으로 표시해 한 번에 지웁니다.
// 사각형을 그릴 때마다 로봇(map_fix_node)이 그 안의 칸 수를 세어 돌려주고, [지우기]를 눌러
// 확인해야 지도 파일이 바뀝니다. 지운 것은 지도 설정의 '최근 수정'에서 되돌릴 수 있습니다.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/map_fix.dart';
import '../models/vica_map.dart';
import '../providers/settings_provider.dart';
import '../providers/supervisor_provider.dart';
import '../widgets/map_canvas.dart';
import '../widgets/map_fix_card.dart';
import '../widgets/map_fix_overlay.dart';
import '../widgets/map_work_layout.dart';
import '../widgets/vica_ui.dart';

/// 사각형을 받아 주지 않는 사유. 이때는 방금 그린 사각형을 뺍니다.
const _rectProblems = {'bad_rect', 'too_small', 'too_many', 'out_of_map'};

class MapEraseScreen extends StatefulWidget {
  const MapEraseScreen({super.key, required this.map});

  /// 지울 지도. 지웠으면 로봇의 응답([MapFixResult])을 들고 닫힙니다.
  final VicaMap map;

  @override
  State<MapEraseScreen> createState() => _MapEraseScreenState();
}

class _MapEraseScreenState extends State<MapEraseScreen> {
  final List<MapFixRect> _rects = [];
  MapFixEraseCount? _count;
  Offset? _dragStart;
  Offset? _dragEnd;
  bool _counting = false;
  bool _erasing = false;
  String _note = '';

  // true 면 [지도 이동] — 드래그·두 손가락이 지도 이동·확대·축소입니다. false(처음 값)면
  // [구역 표시] — 드래그가 사각형 그리기이고 지도는 움직이지 않습니다(목업 96, 11-19 사용자).
  // 폰에서는 지도 한 칸(5 cm)이 1 px 이 안 돼, 확대한 뒤 그려야 작은 점을 고를 수 있습니다.
  bool _moving = false;

  // 늦게 온 옛 응답이 새 목록의 칸 수를 덮지 않게 합니다.
  int _countSeq = 0;

  String get _mapId => widget.map.mapId;

  MapFixRect? get _draft {
    final start = _dragStart;
    final end = _dragEnd;
    return start == null || end == null
        ? null
        : MapFixRect.fromCorners(start, end);
  }

  void _setMoving(bool moving) {
    if (moving == _moving) {
      return;
    }
    setState(() {
      _moving = moving;
      // 그리던 사각형은 버립니다(손을 떼기 전에 바꾼 경우).
      _dragStart = null;
      _dragEnd = null;
    });
  }

  void _panStart(Offset ros) {
    if (_erasing || _moving) {
      return;
    }
    setState(() {
      _dragStart = ros;
      _dragEnd = ros;
    });
  }

  void _panUpdate(Offset ros) {
    if (_dragStart == null) {
      return;
    }
    setState(() => _dragEnd = ros);
  }

  void _panEnd() {
    final rect = _draft;
    setState(() {
      _dragStart = null;
      _dragEnd = null;
    });
    // 손가락이 스친 정도(한 변 5 cm 미만)는 사각형으로 치지 않습니다.
    if (rect == null ||
        rect.width < kMapFixMinRectM ||
        rect.height < kMapFixMinRectM) {
      return;
    }
    if (_rects.length >= kMapFixMaxRects) {
      setState(() => _note = '한 번에 $kMapFixMaxRects곳까지 지울 수 있습니다.');
      return;
    }
    setState(() => _rects.add(rect));
    _recount(addedLast: true);
  }

  void _remove(int index) {
    setState(() {
      _rects.removeAt(index);
      _note = '';
    });
    _recount();
  }

  /// 지금 목록 전체로 칸 수를 다시 셉니다.
  Future<void> _recount({bool addedLast = false}) async {
    final seq = ++_countSeq;
    if (_rects.isEmpty) {
      setState(() {
        _count = null;
        _counting = false;
      });
      return;
    }
    setState(() => _counting = true);
    final reply = await context.read<SupervisorProvider>().mapFix(
      _mapId,
      'erase_count',
      args: {'rects': _rects.map((rect) => rect.toJson()).toList()},
    );
    if (!mounted || seq != _countSeq) {
      return;
    }
    setState(() {
      _counting = false;
      if (reply.accepted) {
        _count = MapFixEraseCount.fromResult(reply.result);
        _note = '';
        return;
      }
      _note = reply.message;
      if (addedLast && _rectProblems.contains(reply.reason)) {
        // 방금 그린 사각형이 문제입니다(지도 밖 등). 그것만 빼면 앞서 센 값이 그대로 맞습니다.
        _rects.removeLast();
      } else {
        _count = null;
      }
    });
  }

  Future<void> _erase() async {
    final count = _count;
    if (count == null || _rects.isEmpty) {
      return;
    }
    final confirmed = await showVicaConfirm(
      context,
      icon: Icons.cleaning_services_outlined,
      iconColor: VicaColors.red,
      title: vicaKeepWords('선택한 구역을 지울까요?'),
      body: '실제로 없는 장애물인지 다시 확인하세요.',
      rows: [
        VicaDialogRow(label: '구역', value: '${_rects.length}곳'),
        VicaDialogRow(label: '검은 칸', value: '${count.black}개'),
        VicaDialogRow(label: '회색 칸', value: '${count.gray}개'),
      ],
      confirmLabel: '지우기',
      danger: true,
    );
    if (!confirmed || !mounted) {
      return;
    }
    setState(() => _erasing = true);
    final reply = await context.read<SupervisorProvider>().mapFix(
      _mapId,
      'erase',
      args: {'rects': _rects.map((rect) => rect.toJson()).toList()},
    );
    if (!mounted) {
      return;
    }
    if (reply.accepted) {
      Navigator.of(context).pop(reply);
      return;
    }
    // 거절되면(주행이 시작됨 등) 그린 것을 둔 채 남아 사유를 보입니다.
    setState(() {
      _erasing = false;
      _note = reply.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final supervisor = context.watch<SupervisorProvider>();
    final settings = context.watch<SettingsProvider>().settings;
    // 목록이 새로 오면(그림 버전 등) 최신 값을 씁니다.
    final map = supervisor.maps.firstWhere(
      (candidate) => candidate.mapId == _mapId,
      orElse: () => widget.map,
    );
    final draft = _draft;
    return Scaffold(
      appBar: AppBar(title: const Text('지도 부분 지우기')),
      body: SafeArea(
        child: MapWorkLayout(
          children: [
            ResponsiveMapFrame(
              map: map,
              child: MapCanvas(
                map: map,
                settings: settings,
                locations: const [],
                robot: supervisor.primaryRobot,
                // [구역 표시]일 때만 드래그가 사각형 그리기입니다. 그동안 지도 이동·확대는
                // 잠기고, [지도 이동]으로 바꾸면 풀립니다. 그려 둔 사각형은 그대로 남습니다.
                keepoutEditMode: !_moving,
                onKeepoutPanStart: _panStart,
                onKeepoutPanUpdate: _panUpdate,
                onKeepoutPanEnd: _panEnd,
                overlayBuilder: (toPixel) =>
                    mapFixEraseOverlay(toPixel, rects: _rects, draft: draft),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: MapFixChoiceButton(
                    label: '구역 표시',
                    selected: !_moving,
                    onTap: _erasing ? null : () => _setMoving(false),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: MapFixChoiceButton(
                    label: '지도 이동',
                    selected: _moving,
                    onTap: _erasing ? null : () => _setMoving(true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            MapFixHint(
              _moving ? '지도를 움직이거나 확대·축소할 수 있습니다.' : '지울 곳을 드래그해서 표시하세요',
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
                          vicaKeepWords('고른 구역'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Text(
                        '${_rects.length}곳',
                        style: const TextStyle(
                          fontSize: 13,
                          color: VicaColors.muted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (var i = 0; i < _rects.length; i++) _row(i),
                  if (_rects.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    _total(),
                  ],
                  if (_note.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      vicaKeepWords(vicaBreakAtSentences(_note)),
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.45,
                        color: VicaColors.red,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  VicaButtonRow(
                    foldWidth: 240,
                    children: [
                      PressScale(
                        child: FilledButton(
                          onPressed: (_rects.isEmpty ||
                                  _count == null ||
                                  _counting ||
                                  _erasing)
                              ? null
                              : _erase,
                          child: Text(_erasing ? '지우는 중...' : '지우기'),
                        ),
                      ),
                      VicaCancelButton(
                        onPressed:
                            _erasing ? null : () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 사각형 한 줄 — 번호 · 크기 · 칸 수 · 빼기.
  Widget _row(int index) {
    final counts = _count?.rects;
    // 칸 수는 목록과 길이가 맞을 때만 씁니다(다시 세는 동안은 크기만 보입니다).
    final counted =
        counts != null && counts.length == _rects.length ? counts[index] : null;
    final width = counted?.wM ?? _rects[index].width;
    final height = counted?.hM ?? _rects[index].height;
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: VicaColors.border)),
      ),
      child: Row(
        children: [
          MapFixNumberDot(number: index + 1),
          const SizedBox(width: 10),
          Expanded(
            // 한 줄에 들어가면 크기는 왼쪽·칸 수는 오른쪽, 좁으면 칸 수가 아래 줄로 내려갑니다.
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              children: [
                Text(
                  '${width.toStringAsFixed(1)} × ${height.toStringAsFixed(1)} m',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (counted != null)
                  Text(
                    vicaKeepWords(
                      '검은 칸 ${counted.black} · 회색 칸 ${counted.gray}',
                    ),
                    style: const TextStyle(
                      fontSize: 12,
                      color: VicaColors.muted,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: _erasing ? null : () => _remove(index),
            tooltip: '${index + 1}번 구역 빼기',
            icon: const Icon(Icons.close, size: 18),
            color: kMapFixEraseColor,
          ),
        ],
      ),
    );
  }

  Widget _total() {
    final count = _count;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: VicaColors.surfaceSunken,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: VicaColors.border),
      ),
      child: Row(
        children: [
          const Text(
            '합계',
            style: TextStyle(fontSize: 14, color: VicaColors.muted),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              vicaKeepWords(
                count == null || _counting
                    ? '세는 중...'
                    : '검은 칸 ${count.black}개 · 회색 칸 ${count.gray}개',
              ),
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
