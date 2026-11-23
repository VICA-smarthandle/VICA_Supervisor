import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/mode_status.dart';
import '../providers/supervisor_provider.dart';
import '../screens/mic_check_screen.dart';
import '../services/mic_check_controller.dart';
import 'vica_ui.dart';

/// 시험에서 가짜 컨트롤러·화면으로 바꿔 끼우는 자리. 운영에서는 건드리지 않습니다.
@visibleForTesting
MicCheckController Function(Uri uri) micCheckControllerFactory =
    (uri) => MicCheckController(uri: uri);
@visibleForTesting
Widget Function(MicCheckController controller, SupervisorProvider supervisor)
    micCheckScreenBuilder = (controller, supervisor) =>
        MicCheckScreen(controller: controller, supervisor: supervisor);

/// 줄 아래 상태 글(캔버스 104 ①②④·105 ①②). `onModeSelect` 면 음성 켜짐 문구 없이 정지 문구만(105 ①).
(String, Color) micCheckStateText(ModeStatus status,
    {bool onModeSelect = false}) {
  if (status.micCheckActive) {
    return ('● 점검 중', VicaColors.primary);
  }
  if (!onModeSelect && status.voiceOn) {
    return ('음성을 끄면 시작', VicaColors.muted);
  }
  return ('약 12분 · 로봇 정지', VicaColors.muted);
}

/// '점검'(시작 확인 → 시작) 또는 '이어 하기'(이미 점검 중이면 화면만 다시 엽니다).
class MicCheckButton extends StatelessWidget {
  const MicCheckButton({super.key, required this.status, this.enabled = true});

  final ModeStatus status;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final resume = status.micCheckActive;
    return PressScale(
      child: FilledButton.tonal(
        key: const ValueKey('mic_check_entry_button'),
        style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
        onPressed: !enabled
            ? null
            : resume
                ? () => openMicCheck(context)
                : () => confirmAndStartMicCheck(context),
        child: Text(resume ? '이어 하기' : '점검'),
      ),
    );
  }
}

/// 시작 확인(캔버스 106 ①) → `startMicCheck()` → 받으면 노드 문구 스낵 + 점검 화면, 거절이면 '안 됐습니다: ' + 문구.
Future<void> confirmAndStartMicCheck(BuildContext context) async {
  final supervisor = context.read<SupervisorProvider>();
  final status = supervisor.modeStatus;
  final alsoDetector = status != null && status.driveOn && status.detectorOn;
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('마이크 점검을 시작할까요?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('약 12분 · 손잡이 자리에서 진행'),
          if (alsoDetector) const Text('카메라 감지도 끕니다'),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true), child: const Text('시작')),
      ],
    ),
  );
  if (go != true || !context.mounted) {
    return;
  }
  final messenger = ScaffoldMessenger.of(context);
  final (ok, message) = await supervisor.startMicCheck();
  if (!context.mounted) {
    return;
  }
  messenger
      .showSnackBar(SnackBar(content: Text(ok ? message : '안 됐습니다: $message')));
  if (ok) {
    await openMicCheck(context);
  }
}

/// 점검 화면을 엽니다. 컨트롤러는 여기서 만들고 화면이 닫힌 뒤 버립니다.
Future<void> openMicCheck(BuildContext context) async {
  final supervisor = context.read<SupervisorProvider>();
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  final controller = micCheckControllerFactory(
      MicCheckController.uriFor(supervisor.connectedUrl));
  controller.start();
  bool? finished;
  try {
    finished = await navigator.push<bool>(
      MaterialPageRoute<bool>(
          builder: (_) => micCheckScreenBuilder(controller, supervisor)),
    );
  } finally {
    controller.dispose();
  }
  if (finished == true) {
    final driveOn = supervisor.modeStatus?.driveOn ?? false;
    messenger.showSnackBar(
      SnackBar(
          content:
              Text(driveOn ? '점검을 끝냈습니다 · 음성 노드를 켜야 새 값이 적용됩니다' : '점검을 끝냈습니다')),
    );
  }
}
