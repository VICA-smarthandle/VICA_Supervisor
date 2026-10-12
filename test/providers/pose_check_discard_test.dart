// 채점 결과를 '그 결과만' 치우는 discardPoseCheck 를 고정합니다.
//
// 지도 설정의 홈 칸('여기가 맞는지 확인')은 원격 주행의 초기 위치 채점을 빌려
// 씁니다. 칸을 접을 때 결과를 남기면 원격 주행 화면이 그 점수·라이다 점을 보이고
// '확정'을 열어 둡니다(검토 35bc1d0 B4). 치울 때 확정 뒤 라이다 점까지 지우면
// 원격 주행 화면의 '반영 확인' 그림이 사라집니다.
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/core/app_settings.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';

import '../ros/fake_ros_socket.dart';

const _poseValues = <String, Object?>{
  'ok': true,
  'message': '잘 맞습니다',
  'score': 88.0,
  'x': 1.0,
  'y': 2.0,
  'yaw': 0.0,
  'hit_x': [1.0, 2.0],
  'hit_y': [3.0, 4.0],
};

void main() {
  late FakeRosServer server;

  setUp(() => server = FakeRosServer());

  // 연결한 provider 로 채점 한 번을 돌려 결과를 남깁니다.
  SupervisorProvider checked(FakeAsync async) {
    final provider = SupervisorProvider(rosChannelConnector: server.connect);
    provider.connect(const AppSettings());
    async.flushMicrotasks();
    provider.checkInitialPose(const AppSettings(), x: 1, y: 2);
    async.flushMicrotasks();
    server.last.answer('/vica/pose_check', _poseValues);
    async.flushMicrotasks();
    return provider;
  }

  test('지금 남아 있는 그 결과만 지운다', () {
    fakeAsync((async) {
      final provider = checked(async);
      final first = provider.poseCheck;
      expect(first, isNotNull);

      // 다른 결과(이미 지나간 것)를 치우라고 해도 지금 결과는 남습니다.
      provider.checkInitialPose(const AppSettings(), x: 1, y: 2);
      async.flushMicrotasks();
      server.last.answer('/vica/pose_check', _poseValues);
      async.flushMicrotasks();
      final second = provider.poseCheck;
      expect(identical(first, second), isFalse);

      provider.discardPoseCheck(first);
      expect(provider.poseCheck, same(second));

      provider.discardPoseCheck(second);
      expect(provider.poseCheck, isNull);

      provider.dispose();
      async.flushMicrotasks();
    });
  });

  test('확정 뒤 라이다 점은 건드리지 않는다', () {
    fakeAsync((async) {
      final provider = checked(async);
      provider.commitInitialPose(const AppSettings(), x: 1, y: 2, yaw: 0);
      async.flushMicrotasks();
      server.last.answer('/vica/pose_commit', {
        'accepted': true,
        'message': '반영했습니다',
        'hit_x': [5.0],
        'hit_y': [6.0],
      });
      async.flushMicrotasks();
      expect(provider.committedScanHits, hasLength(1));

      // 그다음 홈 칸이 채점을 빌려 쓰고 칸을 접습니다.
      provider.checkInitialPose(const AppSettings(), x: 1, y: 2);
      async.flushMicrotasks();
      server.last.answer('/vica/pose_check', _poseValues);
      async.flushMicrotasks();
      provider.discardPoseCheck(provider.poseCheck);

      expect(provider.poseCheck, isNull);
      expect(provider.committedScanHits, hasLength(1));

      provider.dispose();
      async.flushMicrotasks();
    });
  });
}
