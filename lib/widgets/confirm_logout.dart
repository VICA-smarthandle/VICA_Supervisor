import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/supervisor_provider.dart';
import 'vica_ui.dart';

/// 로그아웃할지 묻고, 그러면 ROS 연결을 끊은 뒤 로그아웃합니다.
Future<void> confirmLogout(BuildContext context) async {
  final shouldLogout = await showVicaConfirm(
    context,
    icon: Icons.logout,
    title: '로그아웃',
    body: '로그아웃하면 다음 실행 시 로그인 화면이 표시됩니다.',
    confirmLabel: '로그아웃',
    confirmIcon: Icons.logout,
  );
  if (!shouldLogout || !context.mounted) {
    return;
  }

  await context.read<SupervisorProvider>().disconnect();
  if (!context.mounted) {
    return;
  }
  await context.read<AuthProvider>().logout();
}
