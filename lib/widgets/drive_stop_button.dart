import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/mode_status.dart';
import '../providers/supervisor_provider.dart';
import '../screens/drive_bringup_screen.dart';
import 'vica_ui.dart';

/// 지금 주행을 끌 수 있는가. 주행이 켜져 있고, 끄는 중·끄기 예약이 아닐 때.
bool canStopDrive(ModeStatus? status) =>
    status != null &&
    status.driveOn &&
    status.state != ModeState.stopping &&
    !status.stopPending;

/// 확인 창 → 끄기 요청 → 끄는 진행 화면. 거절되면 이유를 띄웁니다.
Future<void> confirmAndStopDrive(BuildContext context) async {
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
  if (!confirmed || !context.mounted) {
    return;
  }
  final (ok, message) = await context.read<SupervisorProvider>().driveStop();
  if (!context.mounted) {
    return;
  }
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

/// 넓은 화면 위쪽 막대의 '주행 끄기'. 주행이 꺼져 있으면 그리지 않습니다.
class DriveStopButton extends StatefulWidget {
  const DriveStopButton({super.key});

  @override
  State<DriveStopButton> createState() => _DriveStopButtonState();
}

class _DriveStopButtonState extends State<DriveStopButton> {
  bool _busy = false;

  Future<void> _press() async {
    setState(() => _busy = true);
    await confirmAndStopDrive(context);
    if (mounted) {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = context.watch<SupervisorProvider>().modeStatus;
    if (status == null || !status.driveOn) {
      return const SizedBox.shrink();
    }
    return PressScale(
        child: OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: VicaColors.red,
        side: const BorderSide(color: VicaColors.red, width: 1.5),
        minimumSize: const Size(0, 42),
        padding: const EdgeInsets.fromLTRB(12, 0, 16, 0),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
      ),
      onPressed: !_busy && canStopDrive(status) ? _press : null,
      icon: const Icon(Icons.power_settings_new, size: 18),
      label: const Text('주행 끄기'),
    ));
  }
}

/// 폰 위쪽 막대의 모드 버튼(목업 '폰 C'). 주행이 꺼져 있으면 지금처럼 ⇄ 아이콘 하나로 바로
class PhoneModeButton extends StatelessWidget {
  const PhoneModeButton({super.key, required this.onChangeMode});

  final VoidCallback onChangeMode;

  @override
  Widget build(BuildContext context) {
    final status = context.watch<SupervisorProvider>().modeStatus;
    if (status == null || !status.driveOn) {
      return PressScale(
          child: IconButton(
        onPressed: onChangeMode,
        icon: const Icon(Icons.swap_horiz),
        tooltip: '모드 바꾸기',
      ));
    }
    final stoppable = canStopDrive(status);
    return PopupMenuButton<_ModeMenu>(
      tooltip: '모드',
      position: PopupMenuPosition.under,
      onSelected: (choice) => switch (choice) {
        _ModeMenu.change => onChangeMode(),
        _ModeMenu.stop => confirmAndStopDrive(context),
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: _ModeMenu.change,
          height: 48,
          child: Row(
            children: [
              Icon(Icons.swap_horiz, size: 20, color: VicaColors.text),
              SizedBox(width: 10),
              Text('모드 바꾸기',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        PopupMenuItem(
          value: _ModeMenu.stop,
          enabled: stoppable,
          height: 48,
          child: Row(
            children: [
              Icon(Icons.power_settings_new,
                  size: 20,
                  color: stoppable ? VicaColors.red : VicaColors.muted),
              const SizedBox(width: 10),
              Text(
                stoppable ? '주행 끄기' : '주행 끄는 중',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: stoppable ? const Color(0xFFA8443A) : VicaColors.muted,
                ),
              ),
            ],
          ),
        ),
      ],
      child: Container(
        height: 40,
        padding: const EdgeInsets.fromLTRB(9, 0, 6, 0),
        decoration: BoxDecoration(
          color: VicaColors.surfaceSunken,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: VicaColors.border),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.swap_horiz, size: 18, color: VicaColors.text),
            SizedBox(width: 4),
            Text('모드',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: VicaColors.text)),
            Icon(Icons.arrow_drop_down, size: 20, color: VicaColors.text),
          ],
        ),
      ),
    );
  }
}

enum _ModeMenu { change, stop }
