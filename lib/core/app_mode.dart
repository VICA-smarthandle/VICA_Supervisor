// 이 파일은 앱이 어떤 일을 하러 들어왔는지를 나타내는 모드를 정의합니다.
//
// 모드는 앱 화면의 상태이지 로봇의 상태가 아닙니다. 여기서 '지도'를 골라도 젯슨에
// SLAM 스택이 뜨지는 않습니다. 로봇 쪽 배타 관계(SLAM 과 Nav2 는 둘 다
// wheel_ekf.launch.py 를 include 해서 동시에 뜨면 /odom 발행자가 둘이 된다)는
// StackStatus 가 따로 감시합니다.
//
// 저장하지 않습니다. 앱을 새로 열 때마다 다시 고릅니다 — 지난번에 매핑을 했다고
// 이번에도 매핑일 이유가 없고, 잘못된 모드로 자동 진입하는 편이 더 위험합니다.
import 'package:flutter/material.dart';

enum AppMode {
  drive(
    title: '주행',
    subtitle: '지도 설정·원격 주행 등 관리',
    // '원격 주행' 화면이 Icons.navigation 을 쓰므로 겹치지 않는 것으로 고릅니다.
    // 카드를 눌렀더니 같은 아이콘이 또 나오면 이동한 느낌이 들지 않습니다.
    icon: Icons.assistant_direction,
  ),
  mapping(
    title: '지도',
    subtitle: '새 지도 그리기',
    icon: Icons.map,
  );

  const AppMode({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;
}
