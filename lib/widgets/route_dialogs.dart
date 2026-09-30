// 레일 편집 팝업(2026-09-30 사용자 확정, 시안 https://claude.ai/artifact/Uj76d7tQa3kM1utzWt8h1J).
//
//   A  저장하지 않은 레일을 두고 넘어갈 때
//   B  자동 초안으로 다시 시작할 때(지금 편집이 지워진다)
//   D  저장은 됐는데 로봇에 적용하지 못했을 때(셸에서 어느 화면이든)
//   F  편집하는 동안 다른 곳에서 레일을 먼저 저장했을 때
//   (C 는 사용자가 뺐다. E 는 rail_far_place_dialog.dart, G 는 map_delete_card.dart)
import 'package:flutter/material.dart';

import 'vica_ui.dart';

/// 팝업 A. true 면 편집을 버리고 넘어간다.
Future<bool> showRouteLeaveDialog(BuildContext context) async {
  final leave = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => VicaDialog(
      icon: Icons.edit_road_outlined,
      title: '저장하지 않은 레일이 있습니다',
      body: '편집을 취소하고 넘어갈까요?',
      actions: [
        VicaCancelButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          label: '계속 편집',
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('편집 취소'),
        ),
      ],
    ),
  );
  return leave == true;
}

/// 팝업 B. true 면 초안을 만든다.
Future<bool> showRouteDraftDialog(BuildContext context) async {
  final go = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => VicaDialog(
      icon: Icons.auto_awesome_outlined,
      title: '자동 초안으로 다시 시작할까요?',
      body: '지금 편집 중인 노드와 선이 지워집니다.\n'
          '저장하기 전에는 로봇의 레일은 그대로입니다.',
      actions: [
        VicaCancelButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('초안 만들기'),
        ),
      ],
    ),
  );
  return go == true;
}

/// 팝업 D 본문(사용자 확정).
const String kRouteApplyFailedBody =
    '저장은 됐지만 로봇에 반영되지 않았습니다.\n로봇은 이전 레일로 주행합니다.';

/// 팝업 D. [reason] 은 로봇이 적어 보낸 문장입니다.
class RouteApplyFailedDialog extends StatelessWidget {
  const RouteApplyFailedDialog({super.key, required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    return VicaDialog(
      icon: Icons.error_outline,
      iconColor: VicaColors.red,
      title: '레일을 적용하지 못했습니다',
      body: kRouteApplyFailedBody,
      rows: [
        if (reason.trim().isNotEmpty) VicaDialogRow(label: '사유', value: reason),
      ],
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('확인'),
        ),
      ],
    );
  }
}

enum RouteConflictChoice { reload, overwrite }

/// 팝업 F.
Future<RouteConflictChoice?> showRouteConflictDialog(BuildContext context) {
  return showDialog<RouteConflictChoice>(
    context: context,
    builder: (dialogContext) => VicaDialog(
      icon: Icons.info_outline,
      title: '다른 곳에서 레일이 바뀌었습니다',
      body: '편집하는 동안 로봇의 레일이 새로 저장됐습니다.\n내 편집으로 덮어쓸까요?',
      actions: [
        VicaCancelButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(RouteConflictChoice.reload),
          label: '새 레일 불러오기',
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(RouteConflictChoice.overwrite),
          child: const Text('덮어쓰기'),
        ),
      ],
    ),
  );
}
