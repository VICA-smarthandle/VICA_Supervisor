// rosbridge 를 띄우지 않고 WebSocket 끊김·연결 실패를 재현하는 가짜 소켓입니다.
import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// 열린 rosbridge 소켓 하나. 서버 쪽 사정은 시험이 [drop]·[fail] 로 정합니다.
class FakeRosSocket implements WebSocketChannel {
  FakeRosSocket({bool connectFails = false}) {
    if (connectFails) {
      connectFailed = true;
      _ready.completeError(StateError('connection refused'));
      // connect 가 기다리기 전에 실패가 나도 처리되지 않은 오류로 보지 않게 합니다.
      _ready.future.ignore();
    }
  }

  final _ready = Completer<void>();
  // onCancel 을 비워 두면 구독 취소가 root zone 의 이미 끝난 Future 를 돌려줘
  // fakeAsync 가 그 뒤를 진행시키지 못합니다. 같은 zone 의 Future 를 돌려주게 합니다.
  final _incoming = StreamController<dynamic>(onCancel: () async {});
  late final _FakeSink _sink = _FakeSink(this);

  /// 앱이 보낸 rosbridge 명령(JSON 해석본).
  final List<Map<String, Object?>> sent = [];
  bool sinkClosed = false;

  /// 연결 시도가 실패했는지. 실패한 소켓의 sink.close() 는 진짜 web_socket_channel 3.x 처럼
  /// 끝나지 않는다(안쪽 stream 을 아무도 듣지 않는다 — 2026-10-12 실측).
  bool connectFailed = false;

  /// 소켓이 열렸다고 알립니다.
  void open() => _ready.complete();

  /// 연결 시도가 실패했다고 알립니다.
  void failOpen() {
    connectFailed = true;
    _ready.completeError(StateError('connection refused'));
  }

  /// 서버가 소켓을 닫습니다(젯슨 rosbridge 종료·와이파이 끊김).
  Future<void> drop() => _incoming.close();

  /// 소켓에 오류가 납니다.
  void fail(Object error) => _incoming.addError(error);

  /// rosbridge 가 보낸 메시지 하나를 흘려 보냅니다.
  void receive(Map<String, Object?> message) =>
      _incoming.add(jsonEncode(message));

  /// 앱이 [service] 를 부른 가장 최근 요청에 응답합니다. 요청이 없으면 false.
  bool answer(
    String service,
    Map<String, Object?> values, {
    bool result = true,
  }) {
    for (final command in sent.reversed) {
      if (command['op'] == 'call_service' && command['service'] == service) {
        receive({
          'op': 'service_response',
          'id': command['id'],
          'result': result,
          'values': values,
        });
        return true;
      }
    }
    return false;
  }

  @override
  Future<void> get ready => _ready.future;

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  WebSocketSink get sink => _sink;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSink implements WebSocketSink {
  _FakeSink(this._socket);

  final FakeRosSocket _socket;

  @override
  void add(dynamic data) {
    _socket.sent.add(jsonDecode(data as String) as Map<String, Object?>);
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) {
    _socket.sinkClosed = true;
    if (_socket.connectFailed) {
      return Completer<void>().future; // 끝나지 않는다
    }
    return Future<void>.value();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 연결할 때마다 새 [FakeRosSocket] 을 내주고 기록합니다.
class FakeRosServer {
  FakeRosServer({this.autoOpen = true});

  /// true 면 소켓을 내주자마자 연다(연결 성공). false 면 시험이 직접 정합니다.
  bool autoOpen;

  /// true 면 다음 연결들이 모두 실패합니다.
  bool refuse = false;

  final List<FakeRosSocket> sockets = [];

  FakeRosSocket get last => sockets.last;

  WebSocketChannel connect(Uri uri) {
    final socket = FakeRosSocket(connectFails: refuse);
    if (!refuse && autoOpen) {
      socket.open();
    }
    sockets.add(socket);
    return socket;
  }
}
