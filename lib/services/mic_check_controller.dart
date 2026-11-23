import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/mode_contract.dart';
import '../models/mic_check.dart';
import '../ros/ros_bridge_client.dart';

/// 소리 크기·호출 점수 그래프에 담는 점 수. 점검기 프레임이 80 ms 라 80 ms × 125 = 10 s(페이지 `HIST`).
const kMicHistory = 125;

/// 알림 목록 최대 개수.
const _kMaxEvents = 50;

class MicCheckController extends ChangeNotifier {
  MicCheckController({
    required this.uri,
    RosChannelConnector? connector,
    this.retry = const Duration(seconds: 2),
    this.ping = const Duration(seconds: 10),
  }) : _connector = connector ?? WebSocketChannel.connect;

  final Uri uri;
  final RosChannelConnector _connector;
  final Duration retry;
  final Duration ping;

  /// rosbridge 주소와 같은 host 의 점검기 주소.
  static Uri uriFor(String rosBridgeUrl, {int port = kMicCheckPort}) {
    final host = Uri.parse(rosBridgeUrl).host;
    return Uri(scheme: 'ws', host: host, port: port, path: '/ws');
  }

  bool connected = false;
  String? prep;
  MicCheckStatus? status;
  MicCheckFrame? frame;
  final List<double> rmsHistory = [];
  final List<double> wakeHistory = [];

  /// 새것이 앞.
  final List<MicCheckEvent> events = [];
  MicCheckResults? results;
  MicCheckSavePreview? savePreview;
  String? busy;

  final StreamController<String> _toasts = StreamController<String>.broadcast();
  Stream<String> get toasts => _toasts.stream;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _retryTimer;
  Timer? _pingTimer;
  bool _started = false;
  bool _disposed = false;

  void start() {
    if (_started || _disposed) return;
    _started = true;
    _connect();
  }

  Future<void> _connect() async {
    if (_disposed) return;
    final WebSocketChannel channel;
    try {
      channel = _connector(uri);
    } catch (_) {
      _scheduleRetry();
      return;
    }
    _channel = channel;
    try {
      await channel.ready;
    } catch (_) {
      if (_channel == channel) _lost();
      return;
    }
    if (_disposed || _channel != channel) return;
    _subscription = channel.stream.listen(
      _onRaw,
      onDone: () {
        if (_channel == channel) _lost();
      },
      onError: (Object _) {
        if (_channel == channel) _lost();
      },
    );
    connected = true;
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(ping, (_) => send('ping'));
    notifyListeners();
  }

  void _lost() {
    final channel = _channel;
    _channel = null;
    _subscription?.cancel();
    _subscription = null;
    _pingTimer?.cancel();
    _pingTimer = null;
    channel?.sink.close().ignore();
    if (connected) {
      connected = false;
      notifyListeners();
    }
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (_disposed) return;
    _retryTimer?.cancel();
    _retryTimer = Timer(retry, _connect);
  }

  /// 점검기에 명령을 보냅니다. 끊겨 있으면 보내지 않고 false(화면이 안내를 띄웁니다).
  bool send(String cmd, [Map<String, Object?> args = const {}]) {
    final channel = _channel;
    if (!connected || channel == null) return false;
    try {
      channel.sink.add(jsonEncode({'cmd': cmd, ...args}));
    } catch (_) {
      return false;
    }
    return true;
  }

  void _onRaw(dynamic raw) {
    if (raw is! String) return;
    final message = MicCheckMessage.parse(raw);
    if (message == null) return;
    switch (message) {
      case MicPrep(:final text):
        prep = text;
      case MicStatusMessage(:final status):
        this.status = status;
        prep = null;
      case MicFrameMessage(:final frame):
        this.frame = frame;
        _push(rmsHistory, frame.rms);
        _push(wakeHistory, frame.wake);
        final b = frame.busy;
        busy = (b == null || b.isEmpty) ? null : b;
      case MicEventMessage(:final event):
        events.insert(0, event);
        if (events.length > _kMaxEvents)
          events.removeRange(_kMaxEvents, events.length);
      case MicToast(:final text):
        _toasts.add(text);
      case MicBusy(:final text):
        busy = text.isEmpty ? null : text;
      case MicResultsMessage(:final results):
        this.results = results;
      case MicSavePreviewMessage(:final preview):
        savePreview = preview;
    }
    notifyListeners();
  }

  static void _push(List<double> list, double v) {
    list.add(v);
    if (list.length > kMicHistory)
      list.removeRange(0, list.length - kMicHistory);
  }

  @override
  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _pingTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close().ignore();
    _channel = null;
    _toasts.close();
    super.dispose();
  }
}
