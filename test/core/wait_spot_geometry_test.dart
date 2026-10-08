// 대기 장소 계산(2026-10-07)을 고정합니다 — 입구 기준 방향 말, 벽 간격, 옮긴 거리 문장.
//
// **이 파일이 지키는 것**: 관리자가 화면에서 본 '입구 오른쪽'을 로봇이 그대로 말하므로
// 좌우가 뒤집히면 시각장애인이 반대쪽으로 갑니다. 그리고 벽에 너무 붙은 대기 장소는
// 경로 계획기가 벽 속으로 봐서 들어가지도 나오지도 못합니다.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/core/wait_spot_geometry.dart';
import 'package:vica_supervisor/models/vica_map.dart';
import 'package:vica_supervisor/services/map_wall_mask.dart';

const _map = VicaMap(
  mapId: 'm',
  mapName: 'm',
  imageUrl: '/maps/m.png',
  resolution: 0.05,
  originX: 0,
  originY: 0,
  width: 200,
  height: 100,
);

/// 10 m x 5 m, x 5.0 m 에 세로 벽 한 칸.
MapWallMask _wallAtX5() {
  final rgba = Uint8List(200 * 100 * 4);
  for (var r = 0; r < 100; r++) {
    for (var c = 0; c < 200; c++) {
      final i = (r * 200 + c) * 4;
      final v = c == 100 ? 0 : 254;
      rgba[i] = rgba[i + 1] = rgba[i + 2] = v;
      rgba[i + 3] = 255;
    }
  }
  return MapWallMask.fromRgba(_map, 200, 100, rgba);
}

WaitSpotPlacement _place(double x, double y, {double door = 270}) =>
    waitSpotPlacement(
      destX: 0,
      destY: 0,
      doorYawDeg: door,
      spotX: x,
      spotY: y,
    );

void main() {
  group('입구 기준 방향 — 입구 자신의 오른쪽·왼쪽(10-08 사용자 판정)', () {
    // 입구가 지도 아래(270°)면 입구는 지도 위를 보고 서 있고, 그 오른손은 지도
    // 오른쪽(+x)입니다.
    test('입구가 아래일 때 지도 왼쪽은 입구 왼쪽', () {
      expect(_place(-1.5, 0).side, 'left');
      expect(_place(1.5, 0).side, 'right');
    });

    test('run69 실기 두 곳 — 사회 복지창구는 입구 오른쪽, 남자 화장실은 입구 왼쪽', () {
      // map_1002_150946 에 저장된 값 그대로.
      final welfare = waitSpotPlacement(
        destX: 7.97,
        destY: -0.38,
        doorYawDeg: 0,
        spotX: 8.428,
        spotY: 0.672,
      );
      expect(welfare.side, 'right');
      final restroom = waitSpotPlacement(
        destX: 6.21,
        destY: -2.49,
        doorYawDeg: 270,
        spotX: 5.204,
        spotY: -2.434,
      );
      expect(restroom.side, 'left');
    });

    test('옆으로 0.5 m 미만이고 등 뒤면 맞은편', () {
      expect(_place(0, 1.5).side, 'across');
      expect(_place(0.3, 0.2).side, 'across');
    });

    test('옆으로 0.5 m 이상이면 멀리 등 뒤여도 오른쪽·왼쪽(문서 기준)', () {
      expect(_place(-0.8, 3).side, 'left');
    });

    test('옆 0.5 m 띠 안의 입구 쪽과 목적지 점 자체는 입구 안쪽 — 저장 불가', () {
      expect(_place(0, -0.8).inDoorway, isTrue);
      expect(_place(0.3, -2).inDoorway, isTrue);
      expect(_place(0, 0).inDoorway, isTrue);
    });

    test('입구가 오른쪽(0°)이면 지도 위(+y)가 입구 오른쪽', () {
      expect(_place(0, 1.5, door: 0).side, 'right');
      expect(_place(0, -1.5, door: 0).side, 'left');
    });

    test('거리는 목적지 점에서 잰다', () {
      expect(_place(-1.5, 0).distance, closeTo(1.5, 1e-9));
    });
  });

  group('몸 옆면과 벽 사이 간격', () {
    test('위(90°)를 보고 서면 오른쪽(+x)의 벽까지 잰다', () {
      // 기준점 x = 5.0 − 0.225 − 0.12 → 오른쪽 옆면에서 벽 칸 가장자리까지 약 0.10 m.
      final gaps = measureWaitSpotGaps(_wallAtX5(), 4.655, 2.5, 90);
      expect(gaps.right, closeTo(0.10, 0.05));
      expect(gaps.rightLevel, GapLevel.caution);
      expect(gaps.left, kGapScanMaxM);
      expect(gaps.worst, GapLevel.caution);
      expect(gaps.nearestSide.$1, '오른쪽');
    });

    test('옆면이 벽에서 7 cm 안이면 빨강', () {
      final gaps = measureWaitSpotGaps(_wallAtX5(), 4.73, 2.5, 90);
      expect(gaps.rightLevel, GapLevel.blocked);
      expect(gaps.worst, GapLevel.blocked);
    });

    test('나가는 방향 80 cm 안은 주의', () {
      // 앞면 x = 4.4 + 0.151 = 4.551, 벽 칸 가장자리까지 약 0.43 m.
      final gaps = measureWaitSpotGaps(_wallAtX5(), 4.4, 2.5, 0);
      expect(gaps.frontLevel, GapLevel.caution);
    });

    test('나가는 방향 30 cm 안에 벽이 있으면 빨강', () {
      // 앞면 x = 4.6 + 0.151 = 4.751, 벽 칸 가장자리 ≈ 4.975.
      final gaps = measureWaitSpotGaps(_wallAtX5(), 4.6, 2.5, 0);
      expect(gaps.frontLevel, GapLevel.blocked);
    });

    test('멀리 떨어지면 좋음, 몸 안에 벽이 있으면 전부 0', () {
      expect(
          measureWaitSpotGaps(_wallAtX5(), 2.0, 2.5, 90).worst, GapLevel.good);
      final inside = measureWaitSpotGaps(_wallAtX5(), 5.0, 2.5, 90);
      expect([inside.left, inside.right, inside.front], [0, 0, 0]);
    });

    test('글자 — cm·m·4 m 이상', () {
      expect(formatGap(0.12), '12 cm');
      expect(formatGap(1.84), '1.8 m');
      expect(formatGap(kGapScanMaxM), '4 m 이상');
      expect(gapLevelText(GapLevel.caution), '주의 · 벽과 가까움');
    });
  });

  group('옮긴 거리 문장(목업 16′)', () {
    test('화면 오른쪽으로 0.25 m', () {
      expect(
        movedFromOriginalText(3.21, -1.05, 3.46, -1.05, upIsPlusY: true),
        '원래 자리에서 오른쪽으로 0.25 m',
      );
    });

    test('Y축 반전이 꺼져 있으면 +y 가 화면 아래', () {
      expect(
        movedFromOriginalText(0, 0, 0, 0.3, upIsPlusY: false),
        '원래 자리에서 아래로 0.30 m',
      );
    });

    test('비스듬하면 둘을 함께, 거의 그대로면 그대로', () {
      expect(
        movedFromOriginalText(0, 0, 0.3, 0.3, upIsPlusY: true),
        '원래 자리에서 오른쪽 위로 0.42 m',
      );
      expect(
        movedFromOriginalText(0, 0, 0.005, 0, upIsPlusY: true),
        '원래 자리 그대로',
      );
    });
  });
}
