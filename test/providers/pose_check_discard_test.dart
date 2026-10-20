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
