import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/core/app_settings.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';

import '../ros/fake_ros_socket.dart';

const _settings = AppSettings();

void main() {
  late FakeRosServer server;

  setUp(() => server = FakeRosServer());

  String send(
    Future<String> Function(SupervisorProvider, AppSettings) command,
    String service,
    Map<String, Object?> values,
  ) {
    late String message;
    fakeAsync((async) {
      final provider = SupervisorProvider(rosChannelConnector: server.connect);
      provider.connect(_settings);
      async.flushMicrotasks();
      command(provider, _settings).then((value) => message = value);
      async.flushMicrotasks();
      expect(server.last.answer(service, values), isTrue);
      async.flushMicrotasks();
      provider.dispose();
      async.flushMicrotasks();
    });
    return message;
  }

  group('수락이면 앱 문구', () {
    test('일시정지', () {
      final message = send(
        (p, s) => p.pauseNavigation(s),
        _settings.missionPauseService,
        {'accepted': true, 'message': 'pause 요청을 처리했습니다.'},
      );
      expect(message, '주행을 일시정지했습니다.');
    });

    test('다시 출발', () {
      final message = send(
        (p, s) => p.resumeNavigation(s),
        _settings.missionResumeService,
        {'accepted': true, 'message': 'resume 요청을 처리했습니다.'},
      );
      expect(message, '다시 출발합니다.');
    });

    test('취소', () {
      final message = send(
        (p, s) => p.cancelDestination(s),
        _settings.missionCancelService,
        {'accepted': true, 'message': 'cancel 요청을 처리했습니다.'},
      );
      expect(message, '주행을 취소했습니다.');
    });
  });

  group('거부면 사유', () {
    test('아는 사유는 한국어로 옮긴다', () {
      final message = send(
        (p, s) => p.pauseNavigation(s),
        _settings.missionPauseService,
        {'accepted': false, 'message': 'pause 요청 거부: not_navigating'},
      );
      expect(message, '지금은 주행 중이 아닙니다.');
    });

    test('사유가 비었으면 거부되었다고만 말한다', () {
      final message = send(
        (p, s) => p.resumeNavigation(s),
        _settings.missionResumeService,
        {'accepted': false, 'message': ''},
      );
      expect(message, '요청이 거부되었습니다.');
    });
  });
}
