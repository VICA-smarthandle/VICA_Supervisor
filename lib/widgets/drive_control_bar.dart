import 'package:flutter/material.dart';

import 'vica_ui.dart';
import 'package:provider/provider.dart';

import '../core/app_settings.dart';
import '../providers/settings_provider.dart';
import '../providers/supervisor_provider.dart';

class DriveControlBar extends StatelessWidget {
  const DriveControlBar({
    super.key,
    required this.supervisor,
    required this.paused,
    required this.cancelTitle,
    required this.cancelBody,
    this.cancelLabel = '주행 취소',
    this.keepLabel = '계속',
  });

  final SupervisorProvider supervisor;

  /// 지금 일시정지인가. 화면이 provider 의 [SupervisorProvider.navigationPaused]
  final bool paused;

  /// 취소 버튼 글자. 원격 주행은 '주행 취소', 배송은 '배송 취소'·'복귀 취소'.
  final String cancelLabel;

  /// 취소 확인 팝업의 제목과 본문. 무엇이 사라지는지 화면이 말해 줍니다.
  final String cancelTitle;
  final String cancelBody;

  /// 확인 팝업에서 "그냥 두기" 버튼 글자.
  final String keepLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => sendRobotCommand(
              context,
              paused ? supervisor.resumeNavigation : supervisor.pauseNavigation,
            ),
            icon: Icon(paused ? Icons.play_arrow : Icons.pause),
            label: Text(paused ? '다시 출발' : '일시정지'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _confirmCancel(context),
            icon: const Icon(Icons.cancel_outlined),
            label: Text(cancelLabel),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmCancel(BuildContext context) async {
    final confirmed = await showVicaConfirm(
      context,
      icon: Icons.stop_circle_outlined,
      iconColor: VicaColors.red,
      title: cancelTitle,
      body: cancelBody,
      cancelLabel: keepLabel,
      confirmLabel: '취소하기',
      danger: true,
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    await sendRobotCommand(context, supervisor.cancelDestination);
  }
}

/// 로봇에 요청 하나를 보내고 돌아온 문구를 화면 아래 알림으로 띄웁니다.
Future<void> sendRobotCommand(
  BuildContext context,
  Future<String> Function(AppSettings) send,
) async {
  final settings = context.read<SettingsProvider>().settings;
  final message = await send(settings);
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}
