import 'package:flutter/material.dart';

enum AppMode {
  drive(
    title: '주행',
    subtitle: '지도 설정·원격 주행 등 관리',
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
