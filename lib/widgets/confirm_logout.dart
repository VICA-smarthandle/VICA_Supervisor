// 로그아웃 한 벌. 주행 셸·지도 셸·모드 선택 세 곳이 같은 것을 씁니다.
//
// 종전에는 주행 셸만 한 번 묻고 ROS 연결을 끊었습니다. 지도 셸과 모드 선택은 누르자마자
// 로그아웃하고 연결을 남겨 둬서, 로그인 화면 뒤에서도 로봇 상태를 계속 받았습니다
// (검토 35bc1d0 B6). 문구와 순서는 주행 셸 것 그대로입니다.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/supervisor_provider.dart';
import 'vica_ui.dart';

/// 로그아웃할지 묻고, 그러면 ROS 연결을 끊은 뒤 로그아웃합니다.
Future<void> confirmLogout(BuildContext context) async {
  final shouldLogout = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => VicaDialog(
      icon: Icons.logout,
      title: '로그아웃',
      body: '로그아웃하면 다음 실행 시 로그인 화면이 표시됩니다.',
      actions: [
        VicaCancelButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          icon: const Icon(Icons.logout, size: 18),
          label: const Text('로그아웃'),
        ),
      ],
    ),
  );
  if (shouldLogout != true || !context.mounted) {
    return;
  }

  await context.read<SupervisorProvider>().disconnect();
  if (!context.mounted) {
    return;
  }
  await context.read<AuthProvider>().logout();
}
