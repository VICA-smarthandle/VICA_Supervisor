// 이 파일은 주행 중 조작 버튼 한 벌(일시정지·다시 출발·취소)입니다.
//
// 원격 주행과 물류 배송(배송 중·홈 복귀 중)이 같은 버튼을 씁니다. 화면마다 따로
// 그리면 문구·확인 절차·응답 처리가 조금씩 어긋나고, 한 곳을 고치면 다른 곳이
// 빠집니다(2026-09-03 통일). 일시정지·다시 출발은 되돌릴 수 있어 확인 없이
// 바로 보내고, 취소는 로봇이 서고 목적지가 사라지므로 한 번 묻습니다.
//
// 버튼이 부르는 것은 Mission Manager 의 service 셋뿐입니다. 홈 복귀 중의
// 일시정지·재개도 같은 service 로 나갑니다 — 미션이 복귀 중 일시정지를
// 허용하고(2026-09-03), 재개하면 복귀로 되돌아갑니다.
import 'package:flutter/material.dart';
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
  /// 를 넘깁니다 — 이 위젯이 직접 읽지 않는 이유는 시험에서 두 상태를 바로
  /// 만들기 위해서입니다.
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
            onPressed: () => _send(
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

  static Future<void> _send(
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

  Future<void> _confirmCancel(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(cancelTitle),
        content: Text(cancelBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(keepLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('취소하기'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    await _send(context, supervisor.cancelDestination);
  }
}
