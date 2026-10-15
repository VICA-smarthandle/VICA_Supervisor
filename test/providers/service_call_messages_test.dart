// 미션·지도·홈 서비스를 부른 뒤 화면에 돌려주는 문구와 알림 기록을 고정합니다.
//
// 여덟 자리(목적지 요청·대기 장소 가보기·홈 복귀·지도 이름 바꾸기·지도 삭제·홈 저장·홈 삭제·
// 매핑 시작/종료)가 같은 틀을 손으로 반복하고 있었습니다(검토 35bc1d0 D3). 틀을 하나로
// 모으면서 자리마다 다른 기본 문구·실패 머리말·부수 효과가 그대로인지 잠급니다.
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/core/app_settings.dart';
import 'package:vica_supervisor/core/log_filter.dart';
import 'package:vica_supervisor/models/home_position.dart';
import 'package:vica_supervisor/models/location_point.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';

import '../ros/fake_ros_socket.dart';

const _settings = AppSettings();

const _place = LocationPoint(
  locationId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  mapId: 'm1',
  name: '화장실',
  x: 1,
  y: 2,
  yaw: 0,
);

void main() {
  late FakeRosServer server;

  setUp(() => server = FakeRosServer());

  /// 연결한 provider 로 [call] 을 부르고, 미션이 [service] 에 [values] 로 답한 뒤의 결과.
  /// [result] 가 false 면 rosbridge 가 서비스 호출 자체를 실패로 돌려준 경우입니다.
  (String, SupervisorProvider) run(
    Future<String> Function(SupervisorProvider) call,
    String service,
    Map<String, Object?> values, {
    bool result = true,
    void Function(SupervisorProvider)? whilePending,
    void Function(SupervisorProvider)? before,
  }) {
    late String message;
    late SupervisorProvider provider;
    fakeAsync((async) {
      provider = SupervisorProvider(rosChannelConnector: server.connect);
      provider.connect(_settings);
      async.flushMicrotasks();
      before?.call(provider);
      call(provider).then((value) => message = value);
      async.flushMicrotasks();
      whilePending?.call(provider);
      expect(server.last.answer(service, values, result: result), isTrue);
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 30));
    });
    return (message, provider);
  }

  String lastLog(SupervisorProvider provider) {
    final log = provider.logs.first;
    expect(log.filter, LogFilter.coordinateTransfer);
    return log.message;
  }

  test('연결이 없으면 부르지 않고 연결 안 됨이라고 답한다', () async {
    final provider = SupervisorProvider();
    for (final call in <Future<String> Function()>[
      () => provider.requestDestination(_settings, _place),
      () => provider.returnHome(_settings),
      () => provider.renameMap(_settings, 'm1', '1층'),
      () => provider.deleteMap(_settings, 'm1', deleteDestinations: false),
      () => provider.saveHome(_settings,
          mapId: 'm1', x: 0, y: 0, yawDeg: 0, source: HomeSource.mapPick),
      () => provider.deleteHome(_settings, 'm1'),
      () => provider.startMapping(_settings),
      () => provider.pauseNavigation(_settings),
    ]) {
      expect(await call(), 'ROS Bridge에 연결되지 않았습니다.');
    }
    expect(provider.homeBusy, isFalse);
    expect(provider.logs, isEmpty);
  });

  group('목적지 요청', () {
    test('로봇 문구를 그대로 보이고 기록한다', () {
      final (message, provider) = run(
        (p) => p.requestDestination(_settings, _place),
        _settings.missionRequestService,
        {'accepted': true, 'message': '목적지 요청을 수락했습니다: 화장실'},
      );
      expect(message, '목적지 요청을 수락했습니다: 화장실');
      expect(lastLog(provider), message);
    });

    test('문구가 비면 수락·거부 기본 문구', () {
      expect(
        run((p) => p.requestDestination(_settings, _place),
            _settings.missionRequestService, {'accepted': true}).$1,
        '주행 요청을 수락했습니다.',
      );
      expect(
        run((p) => p.requestDestination(_settings, _place),
            _settings.missionRequestService, {'accepted': false}).$1,
        '주행 요청이 거부되었습니다.',
      );
    });

    test('대기 장소 가보기는 busy_navigating 을 따로 읽는다', () {
      final (message, _) = run(
        (p) => p.requestWaitSpot(_settings, _place),
        _settings.missionWaitSpotService,
        {'accepted': false, 'message': '대기 장소 가보기 거부: busy_navigating'},
      );
      expect(message, '안내 중이거나 사용자를 기다리는 중이라 지금은 가볼 수 없습니다.');
    });

    test('호출이 실패하면 머리말을 붙여 기록한다', () {
      final (message, provider) = run(
        (p) => p.requestDestination(_settings, _place),
        _settings.missionRequestService,
        {},
        result: false,
      );
      expect(message, startsWith('Mission Manager 목적지 요청 실패: '));
      expect(lastLog(provider), message);
    });
  });

  group('홈 복귀', () {
    test('거부 사유를 한국어로 옮긴다', () {
      final (message, _) = run(
        (p) => p.returnHome(_settings),
        _settings.missionReturnHomeService,
        {'accepted': false, 'message': '홈 복귀 거부: no_home'},
      );
      expect(message, '홈 위치가 지정되지 않았습니다. 지도 설정 화면에서 먼저 지정하세요.');
    });

    test('문구가 비면 기본 문구, 실패면 머리말', () {
      expect(
        run((p) => p.returnHome(_settings), _settings.missionReturnHomeService,
            {'accepted': true}).$1,
        '홈으로 복귀합니다.',
      );
      expect(
        run((p) => p.returnHome(_settings), _settings.missionReturnHomeService,
                {},
                result: false)
            .$1,
        startsWith('홈 복귀 요청 실패: '),
      );
    });
  });

  group('지도 이름 바꾸기·삭제', () {
    test('이름 바꾸기 기본 문구와 실패 머리말', () {
      expect(
        run((p) => p.renameMap(_settings, 'm1', '1층'),
            _settings.renameMapService, {'accepted': true}).$1,
        '이름을 바꿨습니다.',
      );
      expect(
        run((p) => p.renameMap(_settings, 'm1', '1층'),
            _settings.renameMapService, {'accepted': false}).$1,
        '이름 바꾸기가 거부되었습니다.',
      );
      expect(
        run((p) => p.renameMap(_settings, 'm1', '1층'),
                _settings.renameMapService, {},
                result: false)
            .$1,
        startsWith('이름 바꾸기 요청 실패: '),
      );
    });

    test('지운 지도를 고른 채로 두지 않는다', () {
      final (message, provider) = run(
        (p) => p.deleteMap(_settings, 'm2', deleteDestinations: true),
        _settings.deleteMapService,
        {'accepted': true},
        before: (p) {
          p.handleMapListForTest({
            'maps': [
              {'map_id': 'm1', 'map_name': '1층'},
              {'map_id': 'm2', 'map_name': '2층'},
            ],
          });
          p.selectMap(_settings, 'm2');
        },
      );
      expect(message, '지도가 삭제되었습니다.');
      // 고른 지도가 비면 목록의 첫 지도로 돌아갑니다(로봇이 새 목록을 보내기 전).
      expect(provider.selectedMap?.mapId, 'm1');
    });

    test('삭제 거부·실패 문구', () {
      expect(
        run((p) => p.deleteMap(_settings, 'm1', deleteDestinations: false),
            _settings.deleteMapService, {'accepted': false}).$1,
        '삭제가 거부되었습니다.',
      );
      expect(
        run((p) => p.deleteMap(_settings, 'm1', deleteDestinations: false),
                _settings.deleteMapService, {},
                result: false)
            .$1,
        startsWith('지도 삭제 요청 실패: '),
      );
    });
  });

  group('홈 저장·삭제', () {
    test('저장하는 동안 홈 칸을 잠그고, 수락이면 홈을 바꾼다', () {
      bool? busyWhileCalling;
      final (message, provider) = run(
        (p) => p.saveHome(_settings,
            mapId: 'm1',
            x: 1.5,
            y: 2.5,
            yawDeg: 90,
            source: HomeSource.mapPick),
        _settings.homeSaveService,
        {'accepted': true, 'message': '홈을 저장했습니다.'},
        whilePending: (p) => busyWhileCalling = p.homeBusy,
      );
      expect(busyWhileCalling, isTrue);
      expect(provider.homeBusy, isFalse);
      expect(message, '홈을 저장했습니다.');
      expect(provider.home?.x, 1.5);
      expect(provider.homeBelongsTo('m1'), isTrue);
    });

    test('저장 문구가 비었을 때의 기본 문구(지금 그대로)와 실패 머리말', () {
      // 기본 문구가 '삭제'로 되어 있는 것은 고치지 않았습니다 — 저장용 기존 문구가
      // 없어 사용자 결정 대기입니다(로봇은 늘 문구를 실어 보냅니다).
      expect(
        run(
          (p) => p.saveHome(_settings,
              mapId: 'm1', x: 0, y: 0, yawDeg: 0, source: HomeSource.mapPick),
          _settings.homeSaveService,
          {'accepted': true},
        ).$1,
        '홈 위치가 삭제되었습니다.',
      );
      final (failed, provider) = run(
        (p) => p.saveHome(_settings,
            mapId: 'm1', x: 0, y: 0, yawDeg: 0, source: HomeSource.mapPick),
        _settings.homeSaveService,
        {},
        result: false,
      );
      expect(failed, startsWith('홈 저장 실패: '));
      expect(provider.homeBusy, isFalse);
      expect(provider.home, isNull);
    });

    test('삭제하면 홈을 비운다', () {
      bool? busyWhileCalling;
      final (message, provider) = run(
        (p) => p.deleteHome(_settings, 'm1'),
        _settings.homeDeleteService,
        {'accepted': true},
        whilePending: (p) => busyWhileCalling = p.homeBusy,
      );
      expect(busyWhileCalling, isTrue);
      expect(provider.homeBusy, isFalse);
      expect(message, '홈 위치가 삭제되었습니다.');
      expect(provider.home, isNull);
      expect(lastLog(provider), message);
      expect(
        run((p) => p.deleteHome(_settings, 'm1'), _settings.homeDeleteService,
            {'accepted': false}).$1,
        '홈 위치 삭제가 거부되었습니다.',
      );
      expect(
        run((p) => p.deleteHome(_settings, 'm1'), _settings.homeDeleteService,
                {},
                result: false)
            .$1,
        startsWith('홈 삭제 실패: '),
      );
    });
  });

  group('매핑 시작·종료', () {
    test('문구가 비면 기본 문구, 있으면 그대로, 실패면 머리말', () {
      expect(
        run((p) => p.startMapping(_settings), _settings.mappingStartService,
            {'success': true}).$1,
        '매핑을 시작했습니다.',
      );
      expect(
        run((p) => p.stopMapping(_settings), _settings.mappingStopService,
            {'success': false, 'message': '매핑 중이 아닙니다'}).$1,
        '매핑 중이 아닙니다',
      );
      expect(
        run((p) => p.stopMapping(_settings), _settings.mappingStopService, {},
                result: false)
            .$1,
        startsWith('매핑 요청 실패: '),
      );
    });
  });
}
