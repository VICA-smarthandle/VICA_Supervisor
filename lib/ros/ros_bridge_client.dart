// 이 파일은 rosbridge WebSocket 연결, topic 구독, std_msgs/String JSON publish를 담당합니다.
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

// rosbridge call_service 응답. result=false 이면 서비스 호출 자체가 실패한 것이고,
// values 에는 서비스가 돌려준 필드(std_srvs/Trigger 라면 success, message)가 담긴다.
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

  // 기존 channel을 확실히 닫고 새 WebSocket 연결을 하나만 생성합니다.
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

  // 화면이나 앱이 연결을 해제할 때 subscription과 channel을 함께 정리합니다.
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

  // rosbridge subscribe 명령을 보내고 topic별 handler를 등록합니다.
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

  // rosbridge 에 발행할 토픽의 타입을 미리 알립니다.
  //
  // publish op 자체는 타입을 받지 않습니다. 그래프에 이미 같은 토픽의 발행자가
  // 있으면 rosbridge 가 타입을 알아내지만, 매핑 중에는 /cmd_vel_req 를 아무도
  // 발행하지 않으므로(Nav2 가 꺼져 있다) 미리 advertise 해야 합니다.
  void advertise({required String topic, required String type}) {
    _send({
      'op': 'advertise',
      'topic': topic,
      'type': type,
    });
  }

  void unadvertise(String topic) {
    _send({
      'op': 'unadvertise',
      'topic': topic,
    });
  }

  // 임의 타입 메시지를 발행합니다. advertise 를 먼저 해 두어야 합니다.
  void publishMessage({
    required String topic,
    required Map<String, Object?> message,
  }) {
    _send({
      'op': 'publish',
      'topic': topic,
      'msg': message,
    });
  }

  // std_msgs/String의 data 필드에 JSON 문자열을 넣어서 publish합니다.
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

  // rosbridge call_service 로 서비스를 호출하고 응답을 Future 로 돌려줍니다.
  // 채널이 없거나 timeout 이면 예외를 던집니다.
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
