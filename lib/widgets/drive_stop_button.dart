// 이 파일은 주행 묶음을 내리는 '주행 끄기' 버튼과, 원격 주행 탭 맨 위의 주행 상태 줄입니다.
//
// 2026-11-17 사용자 요청: 대시보드 '주행 설정' 카드 머리 줄(목업 ①)과 원격 주행 탭 맨 위
// (목업 '원격 주행 A') 두 곳. 같은 버튼·같은 확인 창·같은 동작이라 한 곳에 둡니다.
//
// 순서는 모드 선택의 '주행 끄고 지도로'와 같습니다: 확인 → /vica/mode/drive_stop →
// 끄는 진행 화면(DriveBringupScreen stopOnly) → 다 꺼지면 모드 선택. 움직이는 중이면 모드
// 노드가 거절하고, 그 이유를 알림 창으로 띄웁니다.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/mode_status.dart';
import '../providers/app_mode_provider.dart';
import '../providers/supervisor_provider.dart';
import '../screens/drive_bringup_screen.dart';
import 'vica_ui.dart';

class DriveStopButton extends StatefulWidget {
  const DriveStopButton({super.key});

  @override
  State<DriveStopButton> createState() => _DriveStopButtonState();
}

class _DriveStopButtonState extends State<DriveStopButton> {
  bool _busy = false;

  Future<void> _stopDrive(SupervisorProvider supervisor) async {
    final confirmed = await showVicaConfirm(
      context,
      icon: Icons.power_settings_new,
      iconColor: VicaColors.red,
      title: '주행을 끌까요?',
      body: 'Nav2·미션·스마트핸들·음성·카메라 감지를 끕니다. 모터·센서·앱 연결은 그대로입니다.\n'
          '5~15초 걸립니다. 로봇이 움직이는 중이면 끌 수 없습니다.',
      confirmLabel: '주행 끄기',
      danger: true,
    );
    if (!confirmed || !mounted || _busy) {
      return;
    }
    setState(() => _busy = true);
    final (ok, message) = await supervisor.driveStop();
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    if (!ok) {
      await showVicaNotice(
        context,
        icon: Icons.error_outline,
        iconColor: VicaColors.red,
        title: '주행을 끄지 못했습니다',
        body: message,
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const DriveBringupScreen(stopOnly: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final supervisor = context.watch<SupervisorProvider>();
    final status = supervisor.modeStatus;
    final enabled = !_busy &&
        status != null &&
        status.driveOn &&
        status.state != ModeState.stopping &&
        !status.stopPending;
    // 비상정지(위쪽 막대 빨강 채움)와 구별되게 테두리만 빨강입니다(목업 ①).
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: VicaColors.red,
        side: const BorderSide(color: VicaColors.red, width: 1.5),
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.fromLTRB(10, 0, 14, 0),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
      ),
      onPressed: enabled ? () => _stopDrive(supervisor) : null,
      icon: const Icon(Icons.power_settings_new, size: 18),
      label: const Text('주행 끄기'),
    );
  }
}

/// 원격 주행 탭 맨 위 줄: '주행 켜짐 · 안내·배송  [주행 끄기]'(목업 '원격 주행 A').
/// 모드 노드가 없거나 주행이 꺼져 있으면 그리지 않습니다.
class DriveStatusStrip extends StatelessWidget {
  const DriveStatusStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final status = context.watch<SupervisorProvider>().modeStatus;
    if (status == null || !status.driveOn) {
      return const SizedBox.shrink();
    }
    final submode = context.watch<AppModeProvider>().driveSubmode;
    final label = switch (status.state) {
      ModeState.starting => '주행 켜는 중',
      ModeState.stopping => '주행 끄는 중',
      _ => '주행 켜짐',
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: VicaColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: VicaColors.primary, width: 2),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(color: VicaColors.primary, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                text: label,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: VicaColors.text),
                children: [
                  TextSpan(
                    text: ' · ${submode.title}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: VicaColors.primaryDark),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          const DriveStopButton(),
        ],
      ),
    );
  }
}
