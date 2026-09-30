// 이 파일은 지도 설정 화면의 '레일' 칸을 그립니다(B단계, 2026-09-30 사용자 확정).
//
// 시안: https://claude.ai/artifact/HJoZLSx1qcNibuujqpbwZ1
// 자리는 금지구역 다음·지도 관리 위. 로봇이 따라 달리는 길(레일)의 상태를 보이고,
// 편집을 시작하는 곳입니다. 앱은 노드와 선(스케치)만 다루고, 코너 호·1 m 노드·양방향
// 주행·갈림길 벌점은 젯슨이 만듭니다.
import 'package:flutter/material.dart';

import '../models/route_edit.dart';
import '../providers/supervisor_provider.dart' show RouteEditState, RouteInfo;
import 'rail_far_place_dialog.dart' show railFarPlaceMessage;
import 'vica_ui.dart';

/// 확정 문구(2026-09-30).
const String kRailHelpIdle = '로봇이 따라 달리는 길입니다.';
const String kRailHelpEditing =
    '2개의 노드를 놓고 지정하고 그 사이 선을 이어줍니다. 노드를 길게 누르면 옮길 수 있습니다.';
const String kRailAutoNote = '코너 둥글리기, 1 m마다 노드 추가, 양방향 주행 부분은 로봇이 자동으로 설정합니다.';
const String kRailHoldMessage = '현재 주행 중이므로 적용이 불가합니다. 주행 완료 후 적용합니다.';

class RailCard extends StatelessWidget {
  const RailCard({
    super.key,
    required this.info,
    required this.editing,
    required this.state,
    required this.message,
    required this.connected,
    required this.drivingHold,
    required this.sketch,
    required this.tool,
    required this.checks,
    required this.onStartEdit,
    required this.onDraft,
    required this.onReload,
    required this.onSave,
    required this.onCancel,
    required this.onTool,
  });

  final RouteInfo? info;
  final bool editing;
  final RouteEditState state;
  final String message;
  final bool connected;

  /// 로봇이 목적지를 쥐고 있는가. true 면 편집 **시작**만 잠급니다(금지구역과 같은 규칙).
  final bool drivingHold;
  final RouteSketch sketch;
  final RouteEditTool tool;

  /// 편집 중 검사 결과(미리보기·저장 응답).
  final RouteChecks checks;

  final VoidCallback onStartEdit;
  final VoidCallback onDraft;
  final VoidCallback onReload;
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final ValueChanged<RouteEditTool> onTool;

  bool get _busy =>
      state == RouteEditState.saving || state == RouteEditState.drafting;
  bool get _hasRail => info?.found == true;

  @override
  Widget build(BuildContext context) {
    return editing ? _editingBody(context) : _idleBody(context);
  }

  // ── 평소 ────────────────────────────────────────────────────────────────

  Widget _idleBody(BuildContext context) {
    final summary = info?.checks.summary ?? const RouteSummary();
    final places = info?.checks.places ?? const <RoutePlace>[];
    final far = places.where((p) => p.far).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _help(kRailHelpIdle),
        const SizedBox(height: 12),
        _badgeRow(),
        if (_hasRail) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: _Fact(label: '노드', value: '${summary.nodeCount}개')),
              const SizedBox(width: 6),
              Expanded(
                child: _Fact(
                  label: '길이',
                  value: '${summary.lengthM.toStringAsFixed(1)} m',
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _Fact(label: '갈림길', value: '${summary.junctionCount}곳'),
              ),
            ],
          ),
        ],
        if (_hasRail && places.isNotEmpty) ...[
          const SizedBox(height: 10),
          ...places.map(_placeRow),
        ],
        if (info?.status == 'apply_pending') ...[
          const SizedBox(height: 10),
          _note(kRailHoldMessage, VicaColors.muted),
        ],
        for (final p in far) ...[
          const SizedBox(height: 8),
          _note(railFarPlaceMessage(p.name, p.distance), VicaColors.warning),
        ],
        if (message.isNotEmpty) ...[
          const SizedBox(height: 10),
          _message(),
        ],
        const SizedBox(height: 14),
        _idleButtons(),
      ],
    );
  }

  Widget _placeRow(RoutePlace place) {
    final String text;
    final Color color;
    if (place.far) {
      text = '레일에서 ${place.distance.toStringAsFixed(1)} m';
      color = VicaColors.warning;
    } else if (place.distance < 0.3) {
      text = '레일 위';
      color = VicaColors.green;
    } else {
      text = '레일 ${place.distance.toStringAsFixed(1)} m';
      color = VicaColors.green;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              place.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _idleButtons() {
    final canStart = connected && !drivingHold && !_busy;
    if (state == RouteEditState.drafting) {
      return const Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              '초안을 만들고 있습니다.',
              style: TextStyle(fontSize: 13, color: VicaColors.muted),
            ),
          ),
        ],
      );
    }
    if (!_hasRail) {
      // 레일이 없는 지도: 자동 초안을 크게(확정 2026-09-30).
      return Column(
        children: [
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: canStart ? onDraft : null,
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: const Text('자동 초안 만들기'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: canStart ? onStartEdit : null,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('직접 그리기'),
                ),
              ),
            ],
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
                onPressed: canStart ? onStartEdit : null,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('레일 편집'),
              ),
            ),
            const SizedBox(width: 10),
            // Expanded 없이 두면 버튼 테마 최소 폭(무한대) 때문에 화면이 깨집니다(2026-09-14).
            Expanded(
              child: OutlinedButton.icon(
                onPressed: connected && !_busy ? onReload : null,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('다시 불러오기'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: canStart ? onDraft : null,
                icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                label: const Text('자동 초안 새로 만들기'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── 편집 중 ─────────────────────────────────────────────────────────────

  Widget _editingBody(BuildContext context) {
    final errors = checks.errors;
    final warnings = checks.warnings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _help(kRailHelpEditing),
        const SizedBox(height: 12),
        _ToolBar(tool: tool, onTool: _busy ? null : onTool),
        const SizedBox(height: 12),
        Row(
          children: [
            Text(
              '노드 ${sketch.nodes.length} · 선 ${sketch.edges.length}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 10),
            if (errors.isNotEmpty)
              _Badge(text: '검사 ${errors.length}건', color: VicaColors.red)
            else
              const _Badge(text: '편집 중 · 저장 전', color: VicaColors.primary),
          ],
        ),
        const SizedBox(height: 10),
        _note(kRailAutoNote, VicaColors.primaryDark,
            tint: VicaColors.accentTint),
        if (errors.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (var i = 0; i < errors.length; i++) _issueRow(i + 1, errors[i]),
        ],
        for (final w in warnings) ...[
          const SizedBox(height: 8),
          _note(
            w.code == 'far_place'
                ? railFarPlaceMessage(w.name, (w.value ?? 0).toDouble())
                : w.message,
            VicaColors.warning,
          ),
        ],
        if (message.isNotEmpty) ...[
          const SizedBox(height: 10),
          _message(),
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed:
                    _busy || !connected || sketch.edges.isEmpty ? null : onSave,
                icon: state == RouteEditState.saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_upload_outlined),
                label: Text(
                  state == RouteEditState.saving ? '저장 중...' : '저장·적용',
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : onCancel,
                child: const Text('취소'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _busy || !connected ? null : onDraft,
            icon: const Icon(Icons.auto_awesome_outlined, size: 16),
            label: const Text('자동 초안으로 다시 시작'),
          ),
        ),
      ],
    );
  }

  Widget _issueRow(int number, RouteIssue issue) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: VicaColors.red,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              vicaKeepWords(vicaBreakAtSentences(issue.message)),
              style: const TextStyle(fontSize: 12.5, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }

  // ── 공통 ────────────────────────────────────────────────────────────────

  Widget _badgeRow() {
    final Widget badge;
    if (!connected) {
      badge = const _Badge(text: 'ROS 연결 없음', color: VicaColors.red);
    } else if (drivingHold && info?.status != 'apply_pending') {
      badge = const _Badge(text: '주행 중 · 편집 잠김', color: VicaColors.muted);
    } else if (!_hasRail) {
      badge = const _Badge(text: '레일 없음', color: VicaColors.muted);
    } else if (info?.status == 'apply_pending') {
      badge = const _Badge(text: '적용 대기 · 주행 끝나면', color: VicaColors.muted);
    } else {
      badge = const _Badge(text: '레일 적용됨', color: VicaColors.green);
    }
    return Row(children: [badge]);
  }

  Widget _help(String text) => Text(
        vicaKeepWords(vicaBreakAtSentences(text)),
        style:
            const TextStyle(fontSize: 13, color: VicaColors.muted, height: 1.5),
      );

  Widget _note(String text, Color color, {Color? tint}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: tint ?? color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          vicaKeepWords(vicaBreakAtSentences(text)),
          style: TextStyle(fontSize: 12.5, color: color, height: 1.45),
        ),
      );

  Widget _message() => Text(
        vicaKeepWords(vicaBreakAtSentences(message)),
        style: TextStyle(
          fontSize: 12.5,
          height: 1.45,
          color: state == RouteEditState.failed
              ? VicaColors.red
              : VicaColors.muted,
        ),
      );
}

class _ToolBar extends StatelessWidget {
  const _ToolBar({required this.tool, required this.onTool});

  final RouteEditTool tool;
  final ValueChanged<RouteEditTool>? onTool;

  static const _labels = {
    RouteEditTool.addNode: '노드 추가',
    RouteEditTool.connect: '선 잇기',
    RouteEditTool.erase: '지우기',
  };

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<RouteEditTool>(
      showSelectedIcon: false,
      segments: [
        for (final entry in _labels.entries)
          ButtonSegment(value: entry.key, label: Text(entry.value)),
      ],
      selected: {tool},
      onSelectionChanged:
          onTool == null ? null : (values) => onTool!(values.first),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: VicaColors.surfaceSunken,
        border: Border.all(color: VicaColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: VicaColors.textTertiary)),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
        ],
      ),
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
