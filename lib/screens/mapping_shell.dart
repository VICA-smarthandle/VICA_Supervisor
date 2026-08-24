// 이 파일은 '지도' 모드의 껍데기입니다.
//
// 안쪽 4단계(준비 확인 -> 작성 중 -> 저장 -> 완료)는 다음 단계(A5)에서 채웁니다.
// 지금 비워 두지 않고 껍데기를 먼저 두는 이유는 두 가지입니다.
//   1. 모드를 골랐는데 아무 화면도 없으면 사람이 갇힙니다. 돌아갈 길이 필요합니다.
//   2. 무엇이 아직 없는지 화면이 스스로 말하게 두는 편이, 나중에 "왜 안 되지"를
//      찾는 것보다 낫습니다.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_mode_provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/ros_connection_tile.dart';
import '../widgets/vica_ui.dart';

class MappingShell extends StatelessWidget {
  const MappingShell({super.key});

  static const _steps = [
    ('준비 확인', '중복 실행·자이로 보정·bag 기록을 확인합니다'),
    ('작성 중', '지도 미리보기와 품질 숫자를 보며 로봇을 끌고 다닙니다'),
    ('저장', '지도 이름을 정합니다. 날짜는 자동으로 붙습니다'),
    ('완료', '현재 지도로 등록하고 목록을 새로고침합니다'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('지도'),
        actions: [
          TextButton.icon(
            onPressed: () => context.read<AppModeProvider>().clear(),
            icon: const Icon(Icons.swap_horiz),
            label: const Text('모드 바꾸기'),
          ),
          IconButton(
            onPressed: () => context.read<AuthProvider>().logout(),
            icon: const Icon(Icons.logout),
            tooltip: '로그아웃',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: VicaPage(
          title: '새 지도 그리기',
          subtitle: '아래 4단계로 진행합니다. 지금은 단계 구성만 있고 동작은 준비 중입니다.',
          children: [
            const VicaRosConnectionTile(),
            VicaCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < _steps.length; i++) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 26,
                          height: 26,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            color: VicaColors.softBlue,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(
                              color: VicaColors.primary,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _steps[i].$1,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _steps[i].$2,
                                style: const TextStyle(
                                  color: VicaColors.muted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (i < _steps.length - 1) const SizedBox(height: 16),
                  ],
                ],
              ),
            ),
            const VicaCard(
              child: Row(
                children: [
                  Icon(Icons.construction, color: VicaColors.muted, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '아직 지도를 그릴 수 없습니다. 매핑 실행·품질 표시·저장은 '
                      '다음 작업에서 붙습니다. 지금은 젯슨 터미널의 vica_map '
                      '레이아웃을 그대로 쓰세요.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
