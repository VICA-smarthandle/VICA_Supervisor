// 선 잇기가 벽을 가로지르는지 보는 판정을 고정합니다(사용자 결정 2026-09-30).
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/models/vica_map.dart';
import 'package:vica_supervisor/services/map_wall_mask.dart';

const _map = VicaMap(
  mapId: 'm',
  mapName: 'm',
  imageUrl: '/maps/m.png',
  resolution: 0.05,
  originX: 0,
  originY: 0,
  width: 40,
  height: 20,
);

/// 40x20 칸(2 m x 1 m). x 1.0 m 에 세로 벽 한 줄. 회색(미탐색) 칸도 하나.
MapWallMask _mask() {
  final rgba = Uint8List(40 * 20 * 4);
  for (var r = 0; r < 20; r++) {
    for (var c = 0; c < 40; c++) {
      final i = (r * 40 + c) * 4;
      final v = c == 20 ? 0 : (c == 5 && r == 10 ? 205 : 254);
      rgba[i] = rgba[i + 1] = rgba[i + 2] = v;
      rgba[i + 3] = 255;
    }
  }
  return MapWallMask.fromRgba(_map, 40, 20, rgba);
}

void main() {
  test('벽을 가로지르는 선은 잡는다', () {
    expect(_mask().crossesWall(const Offset(0.2, 0.5), const Offset(1.8, 0.5)),
        isTrue);
  });

  test('벽 한쪽에서만 움직이는 선은 통과', () {
    expect(_mask().crossesWall(const Offset(0.2, 0.5), const Offset(0.9, 0.2)),
        isFalse);
  });

  test('회색(미탐색)은 벽이 아니다 — 로봇 쪽 판정과 같은 기준', () {
    expect(_mask().wall[10 * 40 + 5], 0, reason: '회색 칸');
    expect(_mask().isWallAt(0.25, 0.45), isFalse);
  });

  test('지도 밖은 갈 수 없는 곳', () {
    expect(_mask().isWallAt(5, 5), isTrue);
  });
}
