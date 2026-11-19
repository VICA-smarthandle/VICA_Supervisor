// 이 파일은 지도 설정 화면에 끼우는 '지도 수정' 칸 한 덩어리입니다(목업 75·82).
//
// 펼침 틀·로봇에 묻기·지우기/부분 스캔 화면 열기·되돌리기·끝 알림을 이 위젯이 다 맡습니다.
// 지도 설정 화면에는 위젯 하나만 끼우면 됩니다 — 그 화면의 칸 목록(_SettingsPanel)을 건드리지
// 않으려고 펼침 여부를 여기서 들고 있습니다. 다른 칸과 한 번에 하나만 펼쳐지는 규칙은
// [otherPanelOpen] · [onCloseOthers] 로 지킵니다.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/map_fix.dart';
import '../models/vica_map.dart';
import '../providers/settings_provider.dart';
import '../providers/supervisor_provider.dart';
import '../ros/ros_bridge_client.dart';
import '../screens/map_erase_screen.dart';
import '../screens/map_rescan_screen.dart';
import 'map_fix_card.dart';
import 'vica_ui.dart';

class MapFixPanel extends StatefulWidget {
  const MapFixPanel({
    super.key,
    required this.map,
    required this.otherPanelOpen,
    required this.onCloseOthers,
  });

  /// 지도 설정에서 보고 있는 지도.
  final VicaMap map;

  /// 지도 설정의 다른 칸이 펼쳐져 있는가. 그동안 이 칸은 접혀 있습니다.
  final bool otherPanelOpen;

  /// 펼쳐진 다른 칸을 접습니다(저장하지 않은 편집이 있으면 화면이 묻습니다).
  /// 다 접혔으면 true, 사용자가 남기로 했으면 false 입니다.
  final Future<bool> Function() onCloseOthers;

  @override
  State<MapFixPanel> createState() => _MapFixPanelState();
}

class _MapFixPanelState extends State<MapFixPanel> {
  bool _expanded = false;
  bool _busy = false;
  bool _wasDriving = false;
  String _note = '';

  @override
  void didUpdateWidget(MapFixPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.otherPanelOpen) {
      _expanded = false;
    }
    if (oldWidget.map.mapId != widget.map.mapId) {
      _note = '';
      if (_expanded) {
        _refresh();
      }
    }
  }

  Future<void> _toggle() async {
    if (_expanded) {
      setState(() => _expanded = false);
      return;
    }
    if (widget.otherPanelOpen && !await widget.onCloseOthers()) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _expanded = true);
    _refresh();
  }

  /// 잠금과 최근 수정을 로봇에 다시 묻습니다. 칸을 열 때와 수정이 끝날 때만 부릅니다.
  Future<void> _refresh() async {
    final supervisor = context.read<SupervisorProvider>();
    final reply = await supervisor.refreshMapFix(widget.map.mapId);
    if (!mounted) {
      return;
    }
    setState(() => _note = reply.accepted ? '' : reply.message);
  }

  void _toast(String message) {
    if (!mounted || message.trim().isEmpty) {
      return;
    }
    final lines = message
        .split('\n')
        .map((line) => vicaKeepWords(vicaBreakAtSentences(line)));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(lines.join('\n'))));
  }

  /// 지도 파일이 바뀐 뒤 — 기록과 지도 그림(그림 버전)을 다시 받습니다.
  void _afterChange() {
    final supervisor = context.read<SupervisorProvider>();
    supervisor.requestMapList(context.read<SettingsProvider>().settings);
    _refresh();
  }

  Future<void> _openErase() async {
    final result = await Navigator.of(context).push<MapFixResult>(
      MaterialPageRoute(builder: (_) => MapEraseScreen(map: widget.map)),
    );
    if (!mounted || result == null) {
      return;
    }
    _toast(mapFixDoneMessage(result, done: '지웠습니다.'));
    _afterChange();
  }

  Future<void> _openRescan() async {
    final result = await Navigator.of(context).push<MapFixResult>(
      MaterialPageRoute(builder: (_) => MapRescanScreen(map: widget.map)),
    );
    if (!mounted || result == null) {
      return;
    }
    _toast(mapFixDoneMessage(result));
    _afterChange();
  }

  Future<void> _undo() async {
    final confirmed = await showVicaConfirm(
      context,
      icon: Icons.undo,
      title: '마지막 수정을 되돌릴까요?',
      confirmLabel: '되돌리기',
      danger: true,
    );
    if (!confirmed || !mounted) {
      return;
    }
    setState(() => _busy = true);
    final reply = await context.read<SupervisorProvider>().mapFix(
          widget.map.mapId,
          'undo',
        );
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    if (!reply.accepted) {
      setState(() => _note = reply.message);
      _toast(reply.message);
      return;
    }
    _toast(mapFixDoneMessage(reply, done: '되돌렸습니다.'));
    _afterChange();
  }

  @override
  Widget build(BuildContext context) {
    final supervisor = context.watch<SupervisorProvider>();
    final connected =
        supervisor.connectionState == RosConnectionState.connected;
    final driving =
        (supervisor.primaryRobot?.currentGoal.trim() ?? '').isNotEmpty;
    // 주행이 끝난 것을 봤으면 잠금을 한 번 다시 묻습니다(주기적으로 묻지는 않습니다).
    if (_wasDriving && !driving && _expanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _refresh();
        }
      });
    }
    _wasDriving = driving;

    final status = supervisor.mapFixStatusFor(widget.map.mapId);
    // 접혀 있을 때는 로봇의 옛 답으로 '가능'이라 적지 않습니다. 끊김과 주행만 알립니다.
    final word = mapFixStateWord(
      connected: connected,
      status: _expanded ? status : null,
      driving: driving,
    );
    return VicaExpandPanel(
      title: '지도 수정',
      icon: Icons.auto_fix_high,
      summary: word,
      summaryColor: mapFixStateColor(word),
      expanded: _expanded,
      onTap: _toggle,
      child: MapFixCard(
        connected: connected,
        status: status,
        driving: driving,
        busy: _busy,
        note: _note,
        onErase: _openErase,
        onScan: _openRescan,
        onUndo: _undo,
      ),
    );
  }
}
