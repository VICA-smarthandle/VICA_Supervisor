import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/services/mic_check_controller.dart';

import '../ros/fake_ros_socket.dart';

Map<String, Object?> _frame({Object? busy, double rms = 0.01}) => {
      'type': 'frame',
      'rms': rms,
      'wake': 0.1,
      'stop': 0.0,
      'robot': false,
      'muted': false,
      'state': 'listening',
      if (busy != null) 'busy': busy,
    };

void main() {
  test('uriFor 는 같은 host 에 8770 /ws 를 붙인다', () {
    expect(MicCheckController.uriFor('ws://192.168.0.10:9090'), Uri.parse('ws://192.168.0.10:8770/ws'));
  });

  test('status 를 받으면 채워지고 prep 이 지워진다', () {
    fakeAsync((async) {
      final server = FakeRosServer();
      final c = MicCheckController(uri: Uri.parse('ws://h:8770/ws'), connector: server.connect)..start();
      async.flushMicrotasks();
      expect(c.connected, isTrue);
      server.last.receive({'type': 'prep', 'text': '준비 중'});
      async.flushMicrotasks();
      expect(c.prep, '준비 중');
      server.last.receive({'type': 'status'});
      async.flushMicrotasks();
      expect(c.status, isNotNull);
      expect(c.prep, isNull);
      c.dispose();
    });
  });

  test('frame 130개 → 기록은 125개까지', () {
    fakeAsync((async) {
      final server = FakeRosServer();
      final c = MicCheckController(uri: Uri.parse('ws://h:8770/ws'), connector: server.connect)..start();
      async.flushMicrotasks();
      for (var i = 0; i < 130; i++) {
        server.last.receive(_frame(rms: i.toDouble()));
      }
      async.flushMicrotasks();
      expect(c.rmsHistory.length, kMicHistory);
      expect(c.wakeHistory.length, kMicHistory);
      expect(c.rmsHistory.last, 129.0);
      expect(c.rmsHistory.first, 5.0);
      c.dispose();
    });
  });

  test('채널이 닫히면 connected 거짓 → 2 s 뒤 다시 붙는다', () {
    fakeAsync((async) {
      final server = FakeRosServer();
      final c = MicCheckController(uri: Uri.parse('ws://h:8770/ws'), connector: server.connect)..start();
      async.flushMicrotasks();
      expect(server.sockets.length, 1);
      server.last.drop();
      async.flushMicrotasks();
      expect(c.connected, isFalse);
      async.elapse(const Duration(milliseconds: 1900));
      expect(server.sockets.length, 1);
      async.elapse(const Duration(milliseconds: 200));
      async.flushMicrotasks();
      expect(server.sockets.length, 2);
      expect(c.connected, isTrue);
      c.dispose();
    });
  });

  test('send: 끊겨 있으면 false, 붙어 있으면 JSON 명령', () {
    fakeAsync((async) {
      final server = FakeRosServer(autoOpen: false);
      final c = MicCheckController(uri: Uri.parse('ws://h:8770/ws'), connector: server.connect)..start();
      async.flushMicrotasks();
      expect(c.send('record'), isFalse);
      expect(server.last.sent, isEmpty);
      server.last.open();
      async.flushMicrotasks();
      expect(c.send('record'), isTrue);
      expect(c.send('set', {'key': 'band_min', 'value': 0.004}), isTrue);
      expect(server.last.sent, [
        {'cmd': 'record'},
        {'cmd': 'set', 'key': 'band_min', 'value': 0.004},
      ]);
      c.dispose();
    });
  });

  test('send: sink.add 가 예외를 던지면 false', () {
    fakeAsync((async) {
      final server = FakeRosServer();
      final c = MicCheckController(uri: Uri.parse('ws://h:8770/ws'), connector: server.connect)..start();
      async.flushMicrotasks();
      server.last.addThrows = true;
      expect(c.send('record'), isFalse);
      c.dispose();
    });
  });

  test('10 s 마다 ping', () {
    fakeAsync((async) {
      final server = FakeRosServer();
      final c = MicCheckController(uri: Uri.parse('ws://h:8770/ws'), connector: server.connect)..start();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 9));
      expect(server.last.sent, isEmpty);
      async.elapse(const Duration(seconds: 1));
      expect(server.last.sent, [
        {'cmd': 'ping'}
      ]);
      async.elapse(const Duration(seconds: 10));
      expect(server.last.sent.length, 2);
      c.dispose();
    });
  });

  test('toast 는 toasts 스트림으로', () {
    fakeAsync((async) {
      final server = FakeRosServer();
      final c = MicCheckController(uri: Uri.parse('ws://h:8770/ws'), connector: server.connect)..start();
      async.flushMicrotasks();
      final got = <String>[];
      c.toasts.listen(got.add);
      server.last.receive({'type': 'toast', 'text': '저장했습니다'});
      async.flushMicrotasks();
      expect(got, ['저장했습니다']);
      c.dispose();
    });
  });

  test('frame.busy 가 null 이 되면 busy 도 null', () {
    fakeAsync((async) {
      final server = FakeRosServer();
      final c = MicCheckController(uri: Uri.parse('ws://h:8770/ws'), connector: server.connect)..start();
      async.flushMicrotasks();
      server.last.receive(_frame(busy: '채점 중'));
      async.flushMicrotasks();
      expect(c.busy, '채점 중');
      server.last.receive(_frame());
      async.flushMicrotasks();
      expect(c.busy, isNull);
      c.dispose();
    });
  });

  test('event 는 새것 먼저·최대 50', () {
    fakeAsync((async) {
      final server = FakeRosServer();
      final c = MicCheckController(uri: Uri.parse('ws://h:8770/ws'), connector: server.connect)..start();
      async.flushMicrotasks();
      for (var i = 0; i < 55; i++) {
        server.last.receive({'type': 'event', 'title': 'e$i', 'grade': 'info'});
      }
      async.flushMicrotasks();
      expect(c.events.length, 50);
      expect(c.events.first.title, 'e54');
      c.dispose();
    });
  });
}
