// 도움 요청 팝업(관리자 호출, 2026-10-16 사용자 승인 — 앱 UI 사전확인 캔버스 보드 37).
//
// 안내 주행 중 사용자가 도움을 청하고 "직원의 도움이 필요하신가요?"에 "네"라고 하면 로봇이
// 멈추고 뜹니다. 틀은 주행 알림 팝업과 같습니다: 원 아이콘 → 제목 → 본문 세 줄 → 지도 → 위치·
// 요청 시각 칸 → '확인' 버튼 하나.
//
// help_id 하나에 팝업 하나입니다. 미션은 관리자가 확인할 때까지 10초마다 같은 요청을 다시
// 보내는데, 열린 팝업은 provider 의 activeHelp 를 보고 위치 칸만 바꿉니다. 같은 요청의 확인
// (다른 폰·웹에서 누른 것 포함)이나 취소가 오면 activeHelp 가 비고 팝업이 스스로 닫힙니다.
// 바깥을 누르거나 뒤로 가기로는 닫히지 않습니다 — 실수로 닫으면 같은 요청은 다시 뜨지 않습니다.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/vica_map.dart';
import '../providers/settings_provider.dart';
import '../providers/supervisor_provider.dart';
import 'map_canvas.dart';
import 'vica_ui.dart';

class HelpAlertDialog extends StatefulWidget {
  const HelpAlertDialog({super.key, required this.helpId});

  /// 이 팝업이 맡은 도움 요청. 다른 요청으로 바뀌면 이 팝업은 닫히고 셸이 새로 띄웁니다.
  final String helpId;

  @override
  State<HelpAlertDialog> createState() => _HelpAlertDialogState();
}

class _HelpAlertDialogState extends State<HelpAlertDialog> {
  /// 닫기를 한 번만 부르기 위한 표시(GoalAlertDialog 와 같은 까닭).
  bool _closing = false;
  bool _sending = false;

  @override
  Widget build(BuildContext context) {
    final supervisor = context.watch<SupervisorProvider>();
    final help = supervisor.activeHelp;

    if (help == null || help.helpId != widget.helpId) {
      if (!_closing) {
        _closing = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Navigator.of(context).pop();
          }
        });
      }
      return const SizedBox.shrink();
    }

    final map = _mapFor(supervisor, help.mapId);
    final settings = context.read<SettingsProvider>().settings;
    return PopScope(
      canPop: false,
      child: VicaDialog(
        icon: Icons.support_agent,
        iconColor: VicaColors.red,
        title: '도움 요청',
        body: '사용자가 직원의 도움을 요청했습니다.\n'
            '로봇은 그 자리에 멈춰 기다립니다.\n'
            '확인을 누르면 로봇이 관리자가 온다고 알립니다.',
        // 로봇 표시는 1초마다 오는 로봇 상태에서 그립니다(주행 화면과 같은 MapCanvas).
        content: map == null
            ? null
            : ResponsiveMapFrame(
                map: map,
                minHeight: 150,
                maxHeight: 220,
                child: MapCanvas(
                  map: map,
                  settings: settings,
                  locations: supervisor.locationsFor(map.mapId),
                  robot: supervisor.primaryRobot,
                  homePoint: supervisor.homePointFor(map.mapId),
                  keepoutZones: supervisor.keepoutZonesFor(map.mapId),
                ),
              ),
        rows: [
          if (help.place.isNotEmpty)
            VicaDialogRow(label: '위치', value: help.place),
          if (supervisor.helpRequestedAt.isNotEmpty)
            VicaDialogRow(label: '요청 시각', value: supervisor.helpRequestedAt),
        ],
        actions: [
          FilledButton(
            onPressed: _sending ? null : () => _acknowledge(supervisor),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  /// 확인을 로봇에 보냅니다. 받았거나 이미 끝난 요청이면 provider 가 activeHelp 를 비워 팝업이
  /// 스스로 닫히고, 연결이 없거나 거절이면 팝업은 남습니다. 어느 쪽이든 결과를 한 줄로 알립니다.
  Future<void> _acknowledge(SupervisorProvider supervisor) async {
    final messenger = ScaffoldMessenger.of(context);
    final settings = context.read<SettingsProvider>().settings;
    setState(() => _sending = true);
    final message = await supervisor.acknowledgeHelp(settings);
    if (mounted) {
      setState(() => _sending = false);
    }
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  /// 도움 요청이 온 지도. 앱이 그 지도를 모르면 지금 고른 지도, 그것도 없으면 지도 없이 보입니다.
  VicaMap? _mapFor(SupervisorProvider supervisor, String mapId) {
    for (final map in supervisor.maps) {
      if (map.mapId == mapId) {
        return map;
      }
    }
    return supervisor.selectedMap;
  }
}
