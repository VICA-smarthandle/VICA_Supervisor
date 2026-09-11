import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

enum RosConnectionState {
  disconnected,
  connecting,
  connected,
  failed,
}

typedef RosTopicHandler = void Function(Map<String, Object?> message);
typedef RosStateHandler = void Function(
    RosConnectionState state, String detail);

class RosServiceResponse {
  const RosServiceResponse({required this.result, required this.values});

  final bool result;
  final Map<String, Object?> values;

  bool get success => values['success'] == true;
  bool get accepted => values['accepted'] == true;
  String get message => values['message'] as String? ?? '';
}

class RosBridgeClient {
  RosBridgeClient({required this.onState});

  final RosStateHandler onState;
  final Map<String, RosTopicHandler> _handlers = {};
  final Map<String, Completer<RosServiceResponse>> _pendingServiceCalls = {};
  int _serviceCallCounter = 0;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  RosConnectionState _state = RosConnectionState.disconnected;

  RosConnectionState get state => _state;

  Future<void> connect(String url) async {
    await close();
    _setState(RosConnectionState.connecting, 'ROS 연결 시도: $url');
    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      await _channel!.ready;
      _subscription = _channel!.stream.listen(
        _handleRawMessage,
        onDone: () => _setState(RosConnectionState.disconnected, 'ROS 연결 종료'),
        onError: (Object error) =>
            _setState(RosConnectionState.failed, 'ROS 연결 오류: $error'),
      );
      _setState(RosConnectionState.connected, 'ROS 연결 완료');
    } catch (error) {
      _setState(RosConnectionState.failed, 'ROS 연결 실패: $error');
      await close();
    }
  }

  Future<void> close() async {
    _failPendingServiceCalls();
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
    if (_state != RosConnectionState.disconnected) {
      _setState(RosConnectionState.disconnected, 'ROS 연결 해제');
    }
  }

  void subscribe({
    required String topic,
    required RosTopicHandler handler,
    String type = 'std_msgs/String',
  }) {
    _handlers[topic] = handler;
    _send({
      'op': 'subscribe',
      'topic': topic,
      'type': type,
    });
  }

  void unsubscribe(String topic) {
    _handlers.remove(topic);
    _send({
      'op': 'unsubscribe',
      'topic': topic,
    });
  }

  void publishJsonString({
    required String topic,
    required Map<String, Object?> payload,
  }) {
    _send({
      'op': 'publish',
      'topic': topic,
      'msg': {
        'data': jsonEncode(payload),
      },
    });
  }

  Future<RosServiceResponse> callService({
    required String service,
    String type = 'std_srvs/Trigger',
    Map<String, Object?> args = const {},
    Duration timeout = const Duration(seconds: 5),
  }) {
    if (_channel == null) {
      return Future.error(StateError('ROS Bridge에 연결되지 않았습니다.'));
    }
    final id = 'call_${_serviceCallCounter++}';
    final completer = Completer<RosServiceResponse>();
    _pendingServiceCalls[id] = completer;
    _send({
      'op': 'call_service',
      'id': id,
      'service': service,
      'type': type,
      'args': args,
    });
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pendingServiceCalls.remove(id);
        throw TimeoutException('서비스 응답 시간 초과: $service', timeout);
      },
    );
  }

  void _send(Map<String, Object?> command) {
    if (_channel == null) {
      return;
    }
    _channel!.sink.add(jsonEncode(command));
  }

  void _handleRawMessage(dynamic raw) {
    try {
      final decoded = jsonDecode(raw as String) as Map<String, Object?>;

      if (decoded['op'] == 'service_response') {
        _handleServiceResponse(decoded);
        return;
      }

      final topic = decoded['topic'] as String?;
      final msg = decoded['msg'];
      final handler = topic == null ? null : _handlers[topic];
      if (handler == null || msg is! Map<String, Object?>) {
        return;
      }

      final data = msg['data'];
      if (data is! String) {
        handler(msg);
        return;
      }

      final payload = jsonDecode(data) as Map<String, Object?>;
      handler(payload);
    } catch (error) {
      onState(RosConnectionState.connected, 'ROS 메시지 파싱 무시: $error');
    }
  }

  void _handleServiceResponse(Map<String, Object?> decoded) {
    final id = decoded['id'] as String?;
    if (id == null) {
      return;
    }
    final completer = _pendingServiceCalls.remove(id);
    if (completer == null || completer.isCompleted) {
      return;
    }
    final rawValues = decoded['values'];
    final values =
        rawValues is Map<String, Object?> ? rawValues : <String, Object?>{};
    completer.complete(
      RosServiceResponse(
        result: decoded['result'] == true,
        values: values,
      ),
    );
  }

  void _failPendingServiceCalls() {
    if (_pendingServiceCalls.isEmpty) {
      return;
    }
    final pending = Map.of(_pendingServiceCalls);
    _pendingServiceCalls.clear();
    for (final completer in pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('ROS 연결이 종료되었습니다.'));
      }
    }
  }

  void _setState(RosConnectionState next, String detail) {
    if (_state == next && detail.isEmpty) {
      return;
    }
    _state = next;
    onState(next, detail);
  }
}
