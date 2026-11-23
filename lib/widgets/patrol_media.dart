import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../models/patrol.dart';
import '../providers/settings_provider.dart';
import '../services/patrol_log_loader.dart';
import 'patrol_ui.dart';
import 'vica_ui.dart';

/// 영상 한 편을 재생하는 것. mp4 와 사진 넘기기가 같은 모양입니다.
abstract class PatrolClipPlayer implements Listenable {
  Duration get duration;
  Duration get position;
  bool get playing;
  double get aspectRatio;
  Future<void> play();
  Future<void> pause();
  Future<void> seekTo(Duration position);
  Widget buildView(BuildContext context);
  void dispose();
}

/// 영상을 여는 함수. 못 열면 [PatrolClipFailure] 를 던집니다(null 은 까닭 모름). 시험은 가짜 재생기를 끼웁니다.
typedef PatrolClipOpener = Future<PatrolClipPlayer?> Function(
  String baseUrl,
  PatrolRecord record,
);

/// mp4 를 먼저 열고, 안 되면 사진 넘기기로 엽니다. 둘 다 안 되면 까닭을 던집니다.
Future<PatrolClipPlayer?> openPatrolClip(
  String baseUrl,
  PatrolRecord record, {
  PatrolLogLoader loader = const PatrolLogLoader(),
}) async {
  final controller = VideoPlayerController.networkUrl(
    PatrolLogLoader.clipUri(baseUrl, record.clipId),
  );
  PatrolClipFailure failure;
  try {
    await controller.initialize().timeout(kPatrolClipOpenTimeout);
    return _VideoClipPlayer(controller);
  } on TimeoutException {
    failure = const PatrolClipFailure(PatrolClipFailureKind.timeout);
  } on PlatformException catch (error) {
    failure =
        PatrolClipFailure(PatrolClipFailureKind.browser, code: error.code);
  } catch (_) {
    failure = const PatrolClipFailure(PatrolClipFailureKind.browser);
  }
  unawaited(controller.dispose().catchError((Object _) {}));
  final set = await loader.loadFrames(baseUrl, record.clipId);
  if (set != null) {
    return PatrolFramesPlayer(set.frames, fps: set.fps);
  }
  if (await loader.clipExists(baseUrl, record.clipId) == false) {
    throw const PatrolClipFailure(PatrolClipFailureKind.missing);
  }
  throw failure;
}

class _VideoClipPlayer implements PatrolClipPlayer {
  _VideoClipPlayer(this._controller);

  final VideoPlayerController _controller;

  @override
  Duration get duration => _controller.value.duration;

  @override
  Duration get position => _controller.value.position;

  @override
  bool get playing => _controller.value.isPlaying;

  @override
  double get aspectRatio {
    final ratio = _controller.value.aspectRatio;
    return ratio.isFinite && ratio > 0 ? ratio : 4 / 3;
  }

  @override
  Future<void> play() async {
    if (position >= duration && duration > Duration.zero) {
      await _controller.seekTo(Duration.zero);
    }
    await _controller.play();
  }

  @override
  Future<void> pause() => _controller.pause();

  @override
  Future<void> seekTo(Duration position) => _controller.seekTo(position);

  @override
  Widget buildView(BuildContext context) => VideoPlayer(_controller);

  @override
  void addListener(VoidCallback listener) => _controller.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _controller.removeListener(listener);

  @override
  void dispose() => unawaited(_controller.dispose());
}

/// 사진 묶음을 [fps] 장씩 넘겨 보입니다(mp4 가 없는 장면).
class PatrolFramesPlayer extends ChangeNotifier implements PatrolClipPlayer {
  PatrolFramesPlayer(this.frames, {double fps = kPatrolDefaultFps})
      : fps = fps.isFinite && fps > 0 ? fps : kPatrolDefaultFps;

  final List<Uri> frames;
  final double fps;

  int _index = 0;
  Timer? _timer;

  int get index => _index;

  /// 사진 [count] 장이 차지하는 시간.
  Duration _span(int count) =>
      Duration(microseconds: (count * 1000000 / fps).round());

  @override
  Duration get duration => _span(frames.length);

  @override
  Duration get position => _span(_index);

  @override
  bool get playing => _timer != null;

  @override
  double get aspectRatio => 4 / 3;

  @override
  Future<void> play() async {
    if (playing || frames.isEmpty) {
      return;
    }
    if (_index >= frames.length - 1) {
      _index = 0;
    }
    _timer = Timer.periodic(_span(1), (_) {
      if (_index >= frames.length - 1) {
        _stop();
      } else {
        _index += 1;
      }
      notifyListeners();
    });
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    _stop();
    notifyListeners();
  }

  @override
  Future<void> seekTo(Duration position) async {
    if (frames.isEmpty) {
      return;
    }
    _index = (position.inMicroseconds * fps / 1000000)
        .round()
        .clamp(0, frames.length - 1);
    notifyListeners();
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  Widget buildView(BuildContext context) {
    if (frames.isEmpty) {
      return const SizedBox.shrink();
    }
    return Image.network(
      frames[_index].toString(),
      fit: BoxFit.contain,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
    );
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }
}

/// 영상 창을 띄웁니다. [opener] 는 시험용입니다.
Future<void> showPatrolClip(
  BuildContext context,
  PatrolRecord record, {
  PatrolClipOpener? opener,
}) {
  final baseUrl = context.read<SettingsProvider>().settings.mapHttpBaseUrl;
  return showVicaDialog<void>(
    context: context,
    builder: (_) => PatrolClipDialog(
      record: record,
      baseUrl: baseUrl,
      opener: opener ?? openPatrolClip,
    ),
  );
}

/// 불 켜짐 사진 창을 띄웁니다.
Future<void> showPatrolPhoto(
  BuildContext context, {
  required String title,
  required String photo,
}) {
  final baseUrl = context.read<SettingsProvider>().settings.mapHttpBaseUrl;
  return showVicaDialog<void>(
    context: context,
    builder: (_) => _MediaFrame(
      title: title,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: ColoredBox(
            color: PatrolColors.videoScreen,
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: Image.network(
                PatrolLogLoader.photoUri(baseUrl, photo).toString(),
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) =>
                    const _MediaMessage('사진을 불러오지 못했습니다.'),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class PatrolClipDialog extends StatefulWidget {
  const PatrolClipDialog({
    super.key,
    required this.record,
    required this.baseUrl,
    required this.opener,
  });

  final PatrolRecord record;
  final String baseUrl;
  final PatrolClipOpener opener;

  @override
  State<PatrolClipDialog> createState() => _PatrolClipDialogState();
}

class _PatrolClipDialogState extends State<PatrolClipDialog> {
  PatrolClipPlayer? _player;
  PatrolClipFailure? _failure;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    PatrolClipPlayer? player;
    PatrolClipFailure? failure;
    try {
      player = await widget.opener(widget.baseUrl, widget.record);
    } on PatrolClipFailure catch (error) {
      failure = error;
    } catch (_) {
      player = null;
    }
    if (player == null) {
      failure ??= const PatrolClipFailure(PatrolClipFailureKind.browser);
    }
    if (!mounted) {
      player?.dispose();
      return;
    }
    player?.addListener(_onTick);
    setState(() {
      _player = player;
      _failure = failure;
      _loading = false;
    });
    unawaited(player?.play());
  }

  void _onTick() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _player?.removeListener(_onTick);
    _player?.dispose();
    super.dispose();
  }

  void _seekBy(int seconds) {
    final player = _player;
    if (player == null) {
      return;
    }
    final target = player.position + Duration(seconds: seconds);
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > player.duration ? player.duration : target);
    unawaited(player.seekTo(clamped));
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    final record = widget.record;
    final total = player?.duration ?? Duration.zero;
    final position = player?.position ?? Duration.zero;
    final totalSec = total.inMilliseconds / 1000;
    final detect = record.detectSec;
    final lastSeen = record.lastSeenSec;
    double? fraction(double? seconds) => seconds == null || totalSec <= 0
        ? null
        : (seconds / totalSec).clamp(0.0, 1.0);

    return _MediaFrame(
      title: record.mediaTitle,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: ColoredBox(
            color: PatrolColors.videoScreen,
            child: AspectRatio(
              aspectRatio: player?.aspectRatio ?? 4 / 3,
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    )
                  : player == null
                      ? _ClipFailureView(
                          failure: _failure ??
                              const PatrolClipFailure(
                                  PatrolClipFailureKind.browser),
                          url: PatrolLogLoader.clipUri(
                            widget.baseUrl,
                            record.clipId,
                          ).toString(),
                        )
                      : player.buildView(context),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _SeekBar(
          fraction: totalSec <= 0
              ? 0
              : (position.inMilliseconds / total.inMilliseconds)
                  .clamp(0.0, 1.0),
          detect: fraction(detect),
          lastSeen: fraction(lastSeen),
          onSeek: player == null || totalSec <= 0
              ? null
              : (value) => unawaited(
                    player.seekTo(
                      Duration(
                        milliseconds: (total.inMilliseconds * value).round(),
                      ),
                    ),
                  ),
        ),
        const SizedBox(height: 6),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 8,
          runSpacing: 2,
          children: [
            _TimeLabel(patrolDuration(position.inSeconds)),
            if (detect != null && totalSec > 0)
              _TimeLabel(
                '감지 ${patrolDuration(detect)}',
                color: PatrolColors.videoDetectMark,
              ),
            if (lastSeen != null && totalSec > 0)
              _TimeLabel('마지막 감지 ${patrolDuration(lastSeen)}'),
            _TimeLabel(patrolDuration(total.inSeconds)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _RoundButton(
              label: '-10',
              tooltip: '10초 뒤로',
              onPressed: player == null ? null : () => _seekBy(-10),
            ),
            const SizedBox(width: 20),
            Tooltip(
              message: player?.playing ?? false ? '멈춤' : '재생',
              child: SizedBox(
                width: 60,
                height: 60,
                child: PressScale(
                    child: FilledButton(
                  onPressed: player == null
                      ? null
                      : () => unawaited(
                            player.playing ? player.pause() : player.play(),
                          ),
                  style: FilledButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(60, 60),
                    disabledBackgroundColor:
                        Colors.white.withValues(alpha: 0.12),
                  ),
                  child: Icon(
                    player?.playing ?? false ? Icons.pause : Icons.play_arrow,
                    size: 28,
                    color: Colors.white,
                  ),
                )),
              ),
            ),
            const SizedBox(width: 20),
            _RoundButton(
              label: '+10',
              tooltip: '10초 앞으로',
              onPressed: player == null ? null : () => _seekBy(10),
            ),
          ],
        ),
      ],
    );
  }
}

/// 영상·사진 창의 어두운 틀: 머리(제목 + 닫기) 아래에 내용.
class _MediaFrame extends StatelessWidget {
  const _MediaFrame({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: PatrolColors.videoFrame,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 2),
                      child: Text(
                        patrolKeepWords(title),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  PressScale(
                      child: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: '닫기',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.12),
                      minimumSize: const Size(40, 40),
                    ),
                    icon:
                        const Icon(Icons.close, size: 18, color: Colors.white),
                  )),
                ],
              ),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

/// 영상 창 검은 화면의 실패 문구 + 주소 + 주소 복사(2026-11-17).
class _ClipFailureView extends StatefulWidget {
  const _ClipFailureView({required this.failure, required this.url});

  final PatrolClipFailure failure;
  final String url;

  @override
  State<_ClipFailureView> createState() => _ClipFailureViewState();
}

class _ClipFailureViewState extends State<_ClipFailureView> {
  bool _copied = false;

  Future<void> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: widget.url));
    } catch (_) {
      return;
    }
    if (mounted) {
      setState(() => _copied = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(color: PatrolColors.videoLabel, fontSize: 13);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              patrolKeepWords(patrolClipFailureText(widget.failure)),
              textAlign: TextAlign.center,
              style: style,
            ),
            if (widget.failure.showsUrl) ...[
              const SizedBox(height: 10),
              SelectableText(
                widget.url,
                textAlign: TextAlign.center,
                style: style.copyWith(fontSize: 12),
              ),
              const SizedBox(height: 8),
              PressScale(
                  child: OutlinedButton.icon(
                onPressed: () => unawaited(_copy()),
                icon: Icon(_copied ? Icons.check : Icons.copy, size: 16),
                label: Text(_copied ? '복사했습니다' : '주소 복사'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: PatrolColors.videoLabel,
                  side: const BorderSide(color: PatrolColors.videoLabel),
                ),
              )),
            ],
          ],
        ),
      ),
    );
  }
}

class _MediaMessage extends StatelessWidget {
  const _MediaMessage(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          vicaKeepWords(text),
          textAlign: TextAlign.center,
          style: const TextStyle(color: PatrolColors.videoLabel, fontSize: 13),
        ),
      ),
    );
  }
}

class _TimeLabel extends StatelessWidget {
  const _TimeLabel(this.text, {this.color = PatrolColors.videoLabel});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: TextStyle(color: color, fontSize: 11));
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.label,
    required this.tooltip,
    required this.onPressed,
  });

  final String label;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 48,
        height: 48,
        child: PressScale(
            child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: 0.12),
            foregroundColor: Colors.white,
            disabledForegroundColor: Colors.white.withValues(alpha: 0.4),
            shape: const CircleBorder(),
            padding: EdgeInsets.zero,
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        )),
      ),
    );
  }
}

/// 재생 줄. 채워진 길이·손잡이와, 감지 순간(붉은 눈금)·마지막 감지(회색 눈금)를 그립니다.
class _SeekBar extends StatelessWidget {
  const _SeekBar({
    required this.fraction,
    required this.detect,
    required this.lastSeen,
    required this.onSeek,
  });

  final double fraction;
  final double? detect;
  final double? lastSeen;
  final ValueChanged<double>? onSeek;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        void seekAt(Offset local) =>
            onSeek?.call((local.dx / width).clamp(0.0, 1.0));
        Widget mark(double at, Color color) => Positioned(
              left: (width * at - 1).clamp(0.0, width - 2),
              top: 5,
              child: Container(width: 2, height: 14, color: color),
            );
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: onSeek == null ? null : (d) => seekAt(d.localPosition),
          onHorizontalDragUpdate:
              onSeek == null ? null : (d) => seekAt(d.localPosition),
          child: SizedBox(
            height: 24,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 9,
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: PatrolColors.videoTrack,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  top: 9,
                  child: Container(
                    width: width * fraction,
                    height: 6,
                    decoration: BoxDecoration(
                      color: PatrolColors.videoProgress,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                if (detect != null) mark(detect!, PatrolColors.videoDetectMark),
                if (lastSeen != null)
                  mark(lastSeen!, PatrolColors.videoLastMark),
                Positioned(
                  left: (width * fraction - 7).clamp(0.0, width - 14),
                  top: 5,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
