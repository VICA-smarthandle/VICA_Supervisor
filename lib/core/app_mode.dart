import 'package:flutter/material.dart';

enum AppMode {
  drive(
    title: '주행',
    subtitle: '안내·배송·경비',
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

/// 주행 모드 안에서 무슨 일을 하는지(2026-11-16 목업 '안 2' 채택).
enum DriveSubmode {
  guideDelivery(
    title: '안내·배송',
    subtitle: '길안내·물류배송 모드',
    icon: Icons.route,
  ),
  patrol(
    title: '경비',
    subtitle: '순찰 모드',
    icon: Icons.verified_user_outlined,
  );

  const DriveSubmode({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;
}
