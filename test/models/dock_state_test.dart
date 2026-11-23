import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/models/dock_state.dart';
import 'package:vica_supervisor/models/goal_event.dart';
import 'package:vica_supervisor/models/mission_activity.dart';
import 'package:vica_supervisor/models/robot_status.dart';

RobotStatus robot(String dialog) => RobotStatus.fromJson({
      'status': 'idle',
      'current_goal': '',
      'map_id': 'm1',
      'dialog_state': dialog,
    });

void main() {
  test('도킹 노드 상태 JSON 을 읽는다', () {
    final st = DockNodeState.fromMessage({
      'data': jsonEncode({
        'state': 'docked',
        'near_dock': true,
        'pose_init': 'pending',
        'last': {'action': 'dock', 'result': 'success', 'reason': ''},
      }),
    })!;
    expect(st.docked, isTrue);
    expect(st.nearDock, isTrue);
    expect(st.poseInitPending, isTrue);
    expect(st.lastAction, 'dock');
    expect(DockNodeState.fromMessage({'data': '깨진 글'}), isNull);
    expect(st.undockPending, isFalse);
    expect(st.canResumeUndock, isFalse);
  });

  test('나오다 멈춤(undock_pending)·도크 가까이면 나오기를 이어서 할 수 있다', () {
    DockNodeState st(Map<String, Object?> j) =>
        DockNodeState.fromMessage({'data': jsonEncode(j)})!;
    final pending =
        st({'state': 'idle', 'near_dock': false, 'undock_pending': true});
    expect(pending.undockPending, isTrue);
    expect(pending.canResumeUndock, isTrue);
    expect(st({'state': 'idle', 'near_dock': true}).canResumeUndock, isTrue);
    expect(st({'state': 'idle', 'near_dock': false}).canResumeUndock, isFalse);
    expect(
        st({'state': 'undocking', 'near_dock': true, 'undock_pending': true})
            .canResumeUndock,
        isFalse);
    expect(
        st({'state': 'docking', 'near_dock': true}).canResumeUndock, isFalse);
  });

  test('도크 위치 조회 응답을 읽는다', () {
    final spot = DockSpot.fromTriggerMessage(jsonEncode({
      'exists': true,
      'map_id': 'm1',
      'staging': {'x': 1.0, 'y': 2.0, 'yaw': 1.5708},
      'docked': {'x': 1.0, 'y': 2.86, 'yaw': 1.5708},
      'saved_at': '2026-11-18T21:00:00',
      'visited_ok': false,
    }))!;
    expect(spot.stagingY, 2.0);
    expect(spot.dockedY, 2.86);
    expect(spot.yawDeg.round(), 90);
    expect(spot.visitedOk, isFalse);
    expect(DockSpot.fromTriggerMessage('{"exists":false}'), isNull);
  });

  test('도크 위치 저장 결과 — 성공 알림과 실패 사유', () {
    final ok = DockRegisterResult.fromTrigger(true,
        '{"staging":{"x":1,"y":2,"yaw":0},"moved_cm":12.3,"turned_deg":-3.2}');
    expect(ok.ok, isTrue);
    expect(ok.savedText,
        '도크를 찾아 저장했습니다. 도크 앞 1 m 지점을 준비 위치로 잡았습니다(서 있던 자리에서 12 cm).');
    final nf = DockRegisterResult.fromTrigger(false, '{"reason":"not_found"}');
    expect(nf.ok, isFalse);
    expect(nf.reason, 'not_found');
  });

  test('도킹 중·나오는 중은 잠긴 버튼과 중지 버튼만(상태 줄 없음)', () {
    final dock = MissionActivity.of(robot(kDialogDocking))!;
    expect(dock.kind, MissionActivityKind.dock);
    expect(dock.lines, isEmpty);
    expect(dock.lockedRequestLabel, '도킹 중');
    expect(dock.cancelLabel, '도킹 중지');
    expect(dock.confirmLabel, '중지하기');
    expect(dock.cancelBody, "로봇이 그 자리에 멈춥니다. 다시 하려면 '도킹 시작'을 누르세요.");
    expect(dock.isDock, isTrue);
    final undock = MissionActivity.of(robot(kDialogUndocking))!;
    expect(undock.lockedRequestLabel, '나오는 중');
    expect(undock.cancelLabel, '나오기 중지');
    expect(undock.cancelBody, "로봇이 그 자리에 멈춥니다. 다시 하려면 '도크에서 나오기 다시시작'을 누르세요.");
    expect(MissionActivity.of(robot(kDialogDocked)), isNull);
  });

  test('도킹 실패는 팝업, 성공은 팝업 없음', () {
    GoalEvent ev(String kind, String reason) =>
        GoalEvent.fromJson({'event': kind, 'reason': reason}, id: 'x');
    final f = ev('dock_failed', 'not_found');
    expect(f.needsPopup, isTrue);
    expect(f.isFailure, isTrue);
    expect(f.title, '도킹하지 못했습니다');
    expect(f.description,
        '도크 앞에서 V자를 찾지 못했습니다.\n로봇은 도크 앞에서 기다리고 있습니다.\n구조물을 옮겼는지 확인해주세요.');
    final u = ev('undock_failed', 'blocked');
    expect(u.title, '도크에서 나오지 못했습니다');
    expect(u.description.split('\n').first, '뒤가 30초 넘게 막혀 도크에서 나오지 못했습니다.');
    expect(ev('dock_succeeded', '').needsPopup, isFalse);
    expect(ev('undock_succeeded', '').needsPopup, isFalse);
  });

  test('실제 앱 모양 — rosbridge 클라이언트가 data 를 풀어서 넘긴 맵도 읽는다(11-19 실기 버그)', () {
    final st = DockNodeState.fromMessage(jsonDecode(
            '{"state":"idle","job":"","phase":"","holding":false,"near_dock":true,"undock_pending":true,'
            '"attempt":1,"last":{"action":"undock","result":"failed","reason":"canceled","why":"사용자가 멈춤",'
            '"err_x_cm":0.00,"err_y_cm":0.00,"err_th_deg":0.00},"pose_init":"kept","seq":43}')
        as Map<String, Object?>)!;
    expect(st.state, 'idle');
    expect(st.nearDock, isTrue);
    expect(st.undockPending, isTrue);
    expect(st.canResumeUndock, isTrue);
    expect(st.lastAction, 'undock');
    expect(st.lastReason, 'canceled');
    expect(DockNodeState.fromMessage({'foo': 1}), isNull);
  });

  group('도크 위치 조회의 새 칸(source · refined)', () {
    Map<String, Object?> base() => {
          'exists': true,
          'map_id': 'm1',
          'staging': {'x': -5.9, 'y': 2.45, 'yaw': math.pi},
          'docked': {'x': -6.75, 'y': 2.45, 'yaw': math.pi},
          'saved_at': '2026-11-19T11:52:07',
          'visited_ok': false,
        };

    test('새 칸이 없으면(옛 노드) 도크 인식으로 저장한 것이고 고친 적이 없다', () {
      final spot = DockSpot.fromTriggerMessage(jsonEncode(base()))!;
      expect(spot.source, kDockSourceVDetect);
      expect(spot.mapPicked, isFalse);
      expect(spot.refined, isFalse);
      expect(spot.mapPickUnverified, isFalse);
      expect(spot.statusLine, '11-19 11:52 · 아직 확인 안 됨');
      expect(spot.refinedText, isNull);
    });

    test('지도에서 지정 · 아직 도킹해 보지 않음', () {
      final spot = DockSpot.fromTriggerMessage(
          jsonEncode({...base(), 'source': 'map_pick', 'refined': false}))!;
      expect(spot.mapPicked, isTrue);
      expect(spot.mapPickUnverified, isTrue);
      expect(spot.statusLine, '11-19 11:52 · 지도에서 지정한 자리 · 아직 확인 안 됨');
      expect(spot.refinedText, isNull);
    });

    test('처음 도킹에 성공해 고쳐 저장함 — 지정한 자리에서 / 저장한 자리에서', () {
      final fromMap = DockSpot.fromTriggerMessage(jsonEncode({
        ...base(),
        'saved_at': '2026-11-19T12:03:00',
        'visited_ok': true,
        'source': 'map_pick',
        'refined': true,
        'refined_from': 'map_pick',
        'refined_cm': 18.0,
        'refined_deg': 9.0,
      }))!;
      expect(fromMap.mapPickUnverified, isFalse);
      expect(fromMap.statusLine, '11-19 12:03 · 라이다로 맞춘 자리 · 가 본 자리');
      expect(fromMap.refinedText,
          '도킹했습니다. 라이다로 잰 값으로 도크 위치를 고쳐 저장했습니다(지정한 자리에서 18 cm · 9°).');
      final fromDetect = DockSpot.fromTriggerMessage(jsonEncode({
        ...base(),
        'visited_ok': true,
        'source': 'v_detect',
        'refined': true,
        'refined_from': 'v_detect',
        'refined_cm': 3.6,
        'refined_deg': -1.6,
      }))!;
      expect(fromDetect.refinedText,
          '도킹했습니다. 라이다로 잰 값으로 도크 위치를 고쳐 저장했습니다(저장한 자리에서 4 cm · 2°).');
      final plain = DockSpot.fromTriggerMessage(
          jsonEncode({...base(), 'visited_ok': true}))!;
      expect(plain.statusLine, '11-19 11:52 · 라이다로 맞춘 자리 · 가 본 자리');
      expect(plain.refinedText, isNull);
    });

    test(
        '범위 밖이라 로봇이 고쳐 저장한 자리(v_detect · refined_from map_pick)도 아직 확인 안 된 지정 자리다',
        () {
      final fixed = DockSpot.fromTriggerMessage(jsonEncode({
        ...base(),
        'source': 'v_detect',
        'refined': true,
        'refined_from': 'map_pick',
      }))!;
      expect(fixed.mapPicked, isFalse);
      expect(fixed.mapPickUnverified, isTrue);
      final visited = DockSpot.fromTriggerMessage(jsonEncode({
        ...base(),
        'visited_ok': true,
        'source': 'v_detect',
        'refined': true,
        'refined_from': 'map_pick',
      }))!;
      expect(visited.mapPickUnverified, isFalse);
      final detect = DockSpot.fromTriggerMessage(jsonEncode(
          {...base(), 'source': 'v_detect', 'refined_from': 'v_detect'}))!;
      expect(detect.mapPickUnverified, isFalse);
    });

    test('조회 응답이 어느 지도의 것인지 — 도크가 없으면 map_id 가 없다', () {
      expect(DockSpot.mapIdOfTriggerMessage(jsonEncode(base())), 'm1');
      expect(DockSpot.mapIdOfTriggerMessage('{"exists":false}'), '');
      expect(DockSpot.mapIdOfTriggerMessage('{"exists":false,"map_id":"m2"}'),
          'm2');
      expect(DockSpot.mapIdOfTriggerMessage('깨진 글'), '');
      expect(DockSpot.mapIdOfTriggerMessage(''), '');
    });

    test('저장 시각을 읽지 못하면 원문을 보인다', () {
      final spot = DockSpot.fromTriggerMessage(
          jsonEncode({...base(), 'saved_at': '어제'}))!;
      expect(spot.savedAtLabel, '어제');
    });
  });

  group('도크 인식 저장 응답', () {
    test('성공 — 옮긴 거리는 반올림한다', () {
      final ok = DockRegisterResult.fromTrigger(
          true,
          '{"staging":{"x":1,"y":2,"yaw":0},"moved_cm":6.0,"turned_deg":2.1,'
          '"bumper_to_apex_cm":102.9}');
      expect(ok.ok, isTrue);
      expect(ok.bumperToApexCm, 102.9);
      expect(ok.savedText,
          '도크를 찾아 저장했습니다. 도크 앞 1 m 지점을 준비 위치로 잡았습니다(서 있던 자리에서 6 cm).');
      expect(DockRegisterResult.fromTrigger(true, '{"moved_cm":6.5}').savedText,
          contains('서 있던 자리에서 7 cm'));
    });

    test('실패 사유 — not_found · unstable(숫자 셋) · no_amcl · write_failed · busy',
        () {
      expect(
          DockRegisterResult.fromTrigger(false, '{"reason":"not_found"}')
              .reason,
          'not_found');
      final u = DockRegisterResult.fromTrigger(false,
          '{"reason":"unstable","dist_m":2.6,"bearing_deg":20.0,"oblique_deg":50.0}');
      expect(u.ok, isFalse);
      expect(u.reason, 'unstable');
      expect(u.distM, 2.6);
      expect(u.bearingDeg, 20.0);
      expect(u.obliqueDeg, 50.0);
      expect(
          DockRegisterResult.fromTrigger(false, '{"reason":"no_amcl"}').reason,
          'no_amcl');
      expect(
          DockRegisterResult.fromTrigger(false, '{"reason":"write_failed"}')
              .reason,
          'write_failed');
      final busy = DockRegisterResult.fromTrigger(false, 'busy');
      expect(busy.reason, 'busy');
      expect(busy.driveOff, isFalse);
      expect(
          DockRegisterResult.fromTrigger(false, '{"reason":"not_found"}').distM,
          isNull);
    });

    test('서비스가 없으면 주행 꺼짐 — 연결 없음·시간 초과는 주행 꺼짐이 아니다', () {
      expect(DockRegisterResult.fromTrigger(false, 'call_failed').driveOff,
          isTrue);
      expect(DockRegisterResult.fromTrigger(false, '').driveOff, isTrue);
      final off = DockRegisterResult.fromTrigger(false, 'not_connected');
      expect(off.reason, 'not_connected');
      expect(off.driveOff, isFalse);
      expect(
          DockRegisterResult.fromTrigger(false, 'timeout').driveOff, isFalse);
      expect(isDockDriveOff('busy'), isFalse);
      expect(kDockNotConnectedText, 'ROS Bridge에 연결되지 않았습니다.');
    });
  });

  test('로봇에서 본 방향을 8방 말로 — 왼쪽이 +', () {
    expect(dockSideWord(0), '앞');
    expect(dockSideWord(45), '왼쪽 앞');
    expect(dockSideWord(90), '왼쪽');
    expect(dockSideWord(135), '왼쪽 뒤');
    expect(dockSideWord(180), '뒤');
    expect(dockSideWord(-180), '뒤');
    expect(dockSideWord(-135), '오른쪽 뒤');
    expect(dockSideWord(-90), '오른쪽');
    expect(dockSideWord(-45), '오른쪽 앞');
    expect(dockSideWord(22), '앞');
    expect(dockSideWord(23), '왼쪽 앞');
    expect(dockSideWord(-22), '앞');
    expect(dockSideWord(-23), '오른쪽 앞');
    expect(dockSideWord(158), '뒤');
    expect(dockSideWord(360 + 90), '왼쪽');
    expect(dockSideWord(-360 - 90), '오른쪽');
  });

  test('저장된 도크가 로봇의 어느 쪽 몇 m 인지(목업 86)', () {
    expect(
        savedDockHint(
            dockX: -1.6, dockY: 1.65, robotX: 0, robotY: 0, robotYawDeg: 0),
        '저장된 도크는 로봇의 왼쪽 뒤 약 2.3 m에 있습니다.');
    expect(
        savedDockHint(
            dockX: -2, dockY: 0, robotX: 0, robotY: 0, robotYawDeg: 90),
        '저장된 도크는 로봇의 왼쪽 약 2.0 m에 있습니다.');
    expect(
        savedDockHint(
            dockX: 3, dockY: 1, robotX: 1, robotY: 1, robotYawDeg: 180),
        '저장된 도크는 로봇의 뒤 약 2.0 m에 있습니다.');
    expect(
        savedDockHint(
            dockX: 1, dockY: -0.5, robotX: 1, robotY: 1, robotYawDeg: 360),
        '저장된 도크는 로봇의 오른쪽 약 1.5 m에 있습니다.');
  });

  test('지금 로봇에서 본 도크(목업 87) — 5° 안이면 정면', () {
    expect(dockSeenText(2.6, 20), '약 2.6 m 앞 · 왼쪽으로 20°');
    expect(dockSeenText(1.34, -12.4), '약 1.3 m 앞 · 오른쪽으로 12°');
    expect(dockSeenText(2.6, 4.9), '약 2.6 m 앞 · 정면');
    expect(dockSeenText(2.6, -4.9), '약 2.6 m 앞 · 정면');
    expect(dockSeenText(2.6, 5), '약 2.6 m 앞 · 왼쪽으로 5°');
  });

  test('인식이 불안정할 때의 안내 — 멀면 가까이, 아니고 옆이면 정면 쪽, 나머지는 물건 확인', () {
    const far = '도크 쪽으로 1 m쯤까지 가까이 옮긴 뒤\n다시 눌러 주세요.';
    const oblique = '도크를 옆에서 보고 있습니다. 도크 정면 쪽으로 옮긴 뒤 다시 눌러 주세요.';
    const blocked = '로봇과 도크 사이에 물건이 있는지 확인한 뒤 다시 눌러 주세요.';
    expect(dockUnstableAdvice(distM: 2.6, obliqueDeg: 50), far);
    expect(dockUnstableAdvice(distM: 2.01, obliqueDeg: 0), far);
    expect(dockUnstableAdvice(distM: 2.0, obliqueDeg: 50), oblique);
    expect(dockUnstableAdvice(distM: 1.2, obliqueDeg: -50), oblique);
    expect(dockUnstableAdvice(distM: 1.2, obliqueDeg: 45), blocked);
    expect(dockUnstableAdvice(distM: 1.0, obliqueDeg: 10), blocked);
    expect(dockUnstableAdvice(), blocked);
  });

  group('지도에서 지정한 두 점 → 방향·준비 위치', () {
    test('도크가 왼쪽 벽(−x)에 있고 앞쪽을 +x 에서 누르면 로봇은 −x 를 본다', () {
      const pick =
          DockMapPick(dock: Offset(-6.9, 2.45), front: Offset(-5.0, 2.45));
      expect(pick.fwdDeg.abs(), closeTo(180, 1e-9));
      expect(pick.staging.dx, closeTo(-6.9 + 1.151, 1e-9));
      expect(pick.staging.dy, closeTo(2.45, 1e-9));
    });

    test('도크가 위쪽(+y)이면 로봇은 +y(90°)를 보고, 준비 위치는 1.151 m 아래', () {
      const pick = DockMapPick(dock: Offset(1, 3), front: Offset(1, 2.5));
      expect(pick.fwdDeg, closeTo(90, 1e-9));
      expect(pick.staging.dx, closeTo(1, 1e-9));
      expect(pick.staging.dy, closeTo(3 - 1.151, 1e-9));
    });

    test('비스듬한 방향 — 준비 위치는 두 번째로 누른 쪽으로 1.151 m, 누른 거리와 무관', () {
      const near = DockMapPick(dock: Offset(0, 0), front: Offset(0.3, 0.3));
      const far = DockMapPick(dock: Offset(0, 0), front: Offset(4, 4));
      expect(near.fwdDeg, closeTo(-135, 1e-9));
      expect(far.fwdDeg, closeTo(-135, 1e-9));
      for (final pick in [near, far]) {
        expect(pick.staging.distance, closeTo(kDockStagingOffsetM, 1e-9));
        expect(pick.staging.dx, closeTo(1.151 / math.sqrt2, 1e-9));
        expect(pick.staging.dy, closeTo(1.151 / math.sqrt2, 1e-9));
      }
    });

    test('두 점이 0.30 m 보다 가까우면 방향으로 받지 않는다', () {
      expect(kDockMapPickMinGapM, 0.30);
      expect(DockMapPick.farEnough(const Offset(1, 1), const Offset(1.1, 1.1)),
          isFalse);
      expect(DockMapPick.farEnough(const Offset(1, 1), const Offset(1.2, 1)),
          isFalse);
      expect(DockMapPick.farEnough(const Offset(1, 1), const Offset(1.299, 1)),
          isFalse);
      expect(DockMapPick.farEnough(const Offset(1, 1), const Offset(1.301, 1)),
          isTrue);
      expect(DockMapPick.farEnough(const Offset(1, 1), const Offset(1, 2)),
          isTrue);
    });
  });

  group('도킹 실패 팝업 변형(목업 92)', () {
    GoalEvent ev(String kind, String reason) =>
        GoalEvent.fromJson({'event': kind, 'reason': reason}, id: 'x');

    test('지도에서 지정만 한 자리에서 도크를 못 찾으면 다시 잡기를 안내한다', () {
      for (final reason in ['not_found', 'out_of_range']) {
        final e = ev('dock_failed', reason).asDockFirstTry();
        expect(e.showsDockRedo, isTrue, reason: reason);
        expect(e.title, '도킹하지 못했습니다');
        expect(e.description, '도크를 찾지 못했습니다.\n로봇은 도크 앞에서 기다리고 있습니다.');
        expect(e.detailRows, isEmpty);
      }
      expect(GoalEvent.dockRedoLines, [
        '지정한 자리나 방향이 도크와 다를 수 있습니다.',
        '· 지도에서 도크를 다시 지정하거나',
        "· 로봇을 도크 앞에 세우고 '도크 인식해서 저장'을 눌러 주세요.",
      ]);
    });

    test('도크 앞까지 못 간 것(nav_failed)도 다시 잡기를 안내한다 — 첫 줄은 기존 문구 그대로', () {
      final e = ev('dock_failed', 'nav_failed').asDockFirstTry();
      expect(e.showsDockRedo, isTrue);
      expect(e.title, '도킹하지 못했습니다');
      expect(e.description, '도크 앞까지 가지 못했습니다.\n로봇은 그 자리에 멈춰 있습니다.');
      expect(e.description.split('\n').first,
          dockFailFirstLine('nav_failed', undock: false));
      expect(e.detailRows, isEmpty);
      final plain = ev('dock_failed', 'nav_failed');
      expect(plain.showsDockRedo, isFalse);
      expect(plain.description, e.description);
      expect(plain.detailRows, [('사유', 'nav_failed')]);
    });

    test('그 밖의 도킹 실패는 그대로다', () {
      final plain = ev('dock_failed', 'not_found');
      expect(plain.showsDockRedo, isFalse);
      expect(plain.description,
          '도크 앞에서 V자를 찾지 못했습니다.\n로봇은 도크 앞에서 기다리고 있습니다.\n구조물을 옮겼는지 확인해주세요.');
      expect(plain.detailRows, [('사유', 'not_found')]);
      final lost = ev('dock_failed', 'lost').asDockFirstTry();
      expect(lost.showsDockRedo, isFalse);
      expect(lost.description, '들어가는 중에 V자를 놓쳤습니다.\n로봇은 그 자리에 멈춰 있습니다.');
      expect(ev('undock_failed', 'not_found').asDockFirstTry().showsDockRedo,
          isFalse);
    });

    test('표시한 사본은 나머지 값을 그대로 둔다', () {
      final src = GoalEvent.fromJson({
        'event': 'dock_failed',
        'reason': 'not_found',
        'name': '도크',
        'location_id': '__dock__',
        'map_id': 'm1',
        'timestamp': '123',
      }, id: 'id-1');
      final copy = src.asDockFirstTry();
      expect(copy.id, 'id-1');
      expect(copy.kind, GoalEventKind.dockFailed);
      expect(copy.destinationName, '도크');
      expect(copy.locationId, '__dock__');
      expect(copy.mapId, 'm1');
      expect(copy.robotStamp, '123');
      expect(copy.dockFirstTry, isTrue);
      expect(src.dockFirstTry, isFalse);
    });
  });
}
