import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/supervisor_provider.dart';
import 'vica_ui.dart';

/// 감시 이름 → 묶음 이름. 이름은 생성기(vica_terminator_layout.py)의 guard 와 같습니다.
const Map<String, String> _groupOf = {
  'bt_navigator': 'Nav2',
  'planner_server': 'Nav2',
  'controller_serv': 'Nav2',
  'amcl': 'Nav2',
  'ekf_node': 'Nav2',
  'encoder_feedbac': 'Nav2',
  'cartographer_no': '지도 그리기',
  'cartographer_oc': '지도 그리기',
  'vica_mission_ma': '미션',
  'mission_manager': '미션',
  'turn_guide_node': '손잡이',
  'user_guidance_d': '손잡이',
  'robot_health_mo': '감시',
  'external_diagno': '감시',
  'aggregator_node': '감시',
  'pose_bootstrap_': '위치 확인',
  'vica_llm_node': '음성',
  'vica_tts_node': '음성',
  'llm': '음성',
  'vica_detector': '카메라 감지',
  'robot_state_pub': '로봇 모델',
  'joint_state_pub': '로봇 모델',
  'rplidar_node': '라이다',
  'emergency_stop_': 'Safety',
  'safety_supervis': 'Safety',
  'app_emergency_n': 'Safety',
  'mdrobot_can_ke': '모터',
  'keyboard_knob': '모터',
  'realsense2_came': '카메라',
  'imu_base_link_a': 'IMU',
  'mapping_supervi': '매핑 감독',
  'rosbridge_webso': 'rosbridge',
  'app': 'rosbridge',
  'mode': '모드 노드',
  'web': '웹',
};

/// 중복 목록을 묶음 이름으로 바꿉니다. 처음 나온 순서대로, 같은 묶음은 한 번만. 모르는 이름은 그대로.
List<String> duplicateGroups(List<String> names) {
  final groups = <String>[];
  for (final name in names) {
    final group = _groupOf[name] ?? name;
    if (!groups.contains(group)) {
      groups.add(group);
    }
  }
  return groups;
}

class DuplicateRunBanner extends StatelessWidget {
  const DuplicateRunBanner({super.key});

  static const _ink = Color(0xFF7A2E25);

  @override
  Widget build(BuildContext context) {
    final duplicated = context.select<SupervisorProvider, List<String>>(
        (s) => s.modeStatus?.duplicated ?? const []);
    if (duplicated.isEmpty) {
      return const SizedBox.shrink();
    }
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: const BoxDecoration(
          color: Color(0xFFFBEAE7),
          border: Border(bottom: BorderSide(color: Color(0xFFE8B9B1))),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(Icons.warning_amber_rounded,
                  size: 22, color: VicaColors.red),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    vicaKeepWords(
                        '중복 실행 중 · ${duplicateGroups(duplicated).join('·')}'),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800, color: _ink),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    vicaKeepWords('앱과 터미널에서 함께 실행됐으니 하나를 꺼 주세요.'),
                    style:
                        const TextStyle(fontSize: 12, height: 1.5, color: _ink),
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
