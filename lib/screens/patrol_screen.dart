import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_settings.dart';
import '../models/location_point.dart';
import '../models/patrol.dart';
import '../models/vica_map.dart';
import '../providers/settings_provider.dart';
import '../providers/supervisor_provider.dart';
import '../ros/ros_bridge_client.dart';
import '../services/patrol_log_loader.dart';
import '../widgets/map_canvas.dart';
import '../widgets/map_picker.dart';
import '../widgets/map_work_layout.dart';
import '../widgets/patrol_media.dart';
import '../widgets/patrol_route_editor.dart';
import '../widgets/patrol_ui.dart';
import '../widgets/vica_ui.dart';

class PatrolScreen extends StatefulWidget {
  const PatrolScreen({super.key, this.onOpenRecords, this.clipOpener});

  /// '경비 기록 N건'을 눌렀을 때. 셸이 알림 및 로그의 '경비 기록' 분류로 보냅니다.
  final VoidCallback? onOpenRecords;

  /// 영상을 여는 함수(시험용). 없으면 실제 재생기를 씁니다.
  final PatrolClipOpener? clipOpener;

  @override
  State<PatrolScreen> createState() => _PatrolScreenState();
}

class _PatrolScreenState extends State<PatrolScreen> {
  bool _editing = false;

  /// 경로·장소·레일을 받아 둔 지도. 지도가 바뀌거나 다시 연결되면 새로 받습니다.
  String? _loadedFor;
  bool _recordsRequested = false;

  /// 명령을 보내고 응답을 기다리는 중(버튼 잠금).
  bool _busy = false;

  /// '영상 녹화 중 0:18'의 초를 넘기는 1초 박자. 녹화 중일 때만 돕니다.
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    final supervisor = context.watch<SupervisorProvider>();
    final connected =
        supervisor.connectionState == RosConnectionState.connected;
    final map = _patrolMap(supervisor);
    _ensureLoaded(supervisor, settings, connected ? map : null);

    final phase = supervisor.patrolPhase;
    final route = supervisor.patrolRouteFor(map?.mapId);
    if (!phase.stoppedByAlarm) {
      _syncTicker(false);
    }

    if (phase.active) {
      _editing = false;
    }
    if (_editing && map != null && route != null) {
      return PatrolRouteEditor(
        map: map,
        saved: route,
        onClose: () => setState(() => _editing = false),
      );
    }

    final List<Widget> body;
    if (phase.running) {
      body = _runningBody(supervisor, settings, map, route, phase);
    } else if (phase.active) {
      body = _stoppedBody(supervisor, settings, map, route, phase);
    } else {
      body = _offBody(supervisor, settings, map, route, connected);
    }
    return MapWorkLayout(
      children: [
        if (!connected)
          VicaDisconnectedNotice(detail: supervisor.connectionDetail),
        ...body,
      ],
    );
  }

  /// 순찰은 로봇이 지금 쓰는 지도에서 돕니다. 로봇이 아직 알리지 않았으면 고른 지도입니다.
  VicaMap? _patrolMap(SupervisorProvider supervisor) {
    final current = supervisor.currentMapId;
    for (final map in supervisor.maps) {
      if (map.mapId == current) {
        return map;
      }
    }
    return supervisor.selectedMap;
  }

  void _ensureLoaded(
    SupervisorProvider supervisor,
    AppSettings settings,
    VicaMap? map,
  ) {
    if (!_recordsRequested) {
      _recordsRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(supervisor.refreshPatrolRecords(settings));
        }
      });
    }
    final mapId = map?.mapId;
    if (mapId == _loadedFor) {
      return;
    }
    _loadedFor = mapId;
    if (mapId == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(supervisor.refreshPatrolRoute(settings, mapId));
      if (supervisor.locationsFor(mapId).isEmpty) {
        supervisor.requestLocationList(settings, mapId);
      }
      if (supervisor.routeGraphFor(mapId) == null) {
        unawaited(supervisor.loadRouteGraph(settings, mapId));
      }
    });
  }

  List<Widget> _offBody(
    SupervisorProvider supervisor,
    AppSettings settings,
    VicaMap? map,
    PatrolRoute? route,
    bool connected,
  ) {
    final count = supervisor.patrolRecords?.length;
    return [
      if (supervisor.primaryRobot != null)
        const VicaCard(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              _Dot(color: PatrolColors.offDot, size: 14),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _CardTitle('경비가 꺼져 있습니다'),
                    SizedBox(height: 2),
                    _Caption('손잡이 LED: 평소 색(하늘색)'),
                  ],
                ),
              ),
            ],
          ),
        ),
      if (map == null)
        const NoMapCard()
      else
        VicaCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(child: _CardTitle('순찰 경로')),
                  if (route != null) _CountPill('장소 ${route.length}곳'),
                ],
              ),
              if (route != null && route.summary.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  patrolKeepWords(route.summary),
                  style: const TextStyle(
                    color: VicaColors.text,
                    fontSize: 13,
                    height: 1.55,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              PressScale(
                  child: OutlinedButton(
                onPressed: route == null || _busy
                    ? null
                    : () => setState(() => _editing = true),
                style: patrolSmallButtonStyle(),
                child: const Text('경로 편집', style: patrolSmallButtonText),
              )),
            ],
          ),
        ),
      VicaCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _CardTitle('감시 항목'),
            const SizedBox(height: 5),
            for (final (kind, title, caption) in const [
              (PatrolAlarmKind.intruder, '사람 감지', '카메라 · 보이면 멈추고 경보'),
              (PatrolAlarmKind.light, '불 켜짐 확인', '밝기 대비로 판정'),
              (PatrolAlarmKind.sound, '큰 소리', '기준 이상이 0.5초 넘게 들리면'),
            ])
              _WatchRow(
                title: title,
                caption: caption,
                on: route?.watches(kind) ?? true,
                onChanged: !connected || route == null || _busy
                    ? null
                    : (on) => _setWatch(supervisor, settings, route, kind, on),
              ),
          ],
        ),
      ),
      PressScale(
          child: FilledButton.icon(
        onPressed: !connected || _busy
            ? null
            : () => _start(supervisor, settings, route),
        style: _bigButtonStyle,
        icon: const Icon(Icons.shield_outlined, size: 20),
        label: const Text('경비 시작', style: _bigButtonText),
      )),
      if (widget.onOpenRecords != null) ...[
        const SizedBox(height: 6),
        PressScale(
            child: InkWell(
          onTap: widget.onOpenRecords,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    count == null ? '경비 기록' : '경비 기록 $count건',
                    style: const TextStyle(
                      color: VicaColors.primaryDark,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: VicaColors.primaryDark,
                ),
              ],
            ),
          ),
        )),
        if (supervisor.patrolRecordsFailed)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _Caption(patrolRecordsFailedText(settings.mapHttpBaseUrl)),
          ),
      ],
    ];
  }

  List<Widget> _runningBody(
    SupervisorProvider supervisor,
    AppSettings settings,
    VicaMap? map,
    PatrolRoute? route,
    PatrolPhase phase,
  ) {
    final heading = patrolHeadingLine(
      supervisor.patrolFromName,
      supervisor.patrolWaypointName,
    );
    final started = supervisor.patrolStartedAt;
    final lap = supervisor.patrolLap;
    final detail = [
      if (started != null)
        '${started.hour.toString().padLeft(2, '0')}:'
            '${started.minute.toString().padLeft(2, '0')} 시작',
      if (lap > 0) '$lap바퀴째',
    ].join(' · ');
    final armed =
        phase == PatrolPhase.moving || supervisor.patrolWaypointIndex != null;
    return [
      _StatusCard(
        children: [
          const PatrolChip(
            label: '순찰 중',
            tint: PatrolColors.runningTint,
            ink: PatrolColors.runningInk,
            dot: PatrolColors.runningDot,
          ),
          if (heading.isNotEmpty) _Headline(heading),
          if (detail.isNotEmpty) _Caption(detail),
        ],
      ),
      if (map != null) ...[
        _map(supervisor, settings, map, route, faded: false),
        const SizedBox(height: 12),
      ],
      if (armed)
        const VicaCard(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '카메라',
                style: TextStyle(color: VicaColors.muted, fontSize: 13),
              ),
              Text(
                '정상',
                style: TextStyle(
                  color: VicaColors.primaryDark,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      VicaButtonRow(
        foldWidth: 240,
        children: [
          PressScale(
              child: OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () => _send(() => supervisor.pausePatrol(settings)),
            style: OutlinedButton.styleFrom(
              foregroundColor: VicaColors.primaryDark,
            ),
            icon: const Icon(Icons.pause, size: 18),
            label: const Text('일시정지'),
          )),
          PressScale(
              child: OutlinedButton.icon(
            onPressed: _busy ? null : () => _confirmStop(supervisor, settings),
            style: patrolDangerOutlineStyle(),
            icon: const Icon(Icons.cancel_outlined, size: 18),
            label: const Text('경비 종료'),
          )),
        ],
      ),
    ];
  }

  List<Widget> _stoppedBody(
    SupervisorProvider supervisor,
    AppSettings settings,
    VicaMap? map,
    PatrolRoute? route,
    PatrolPhase phase,
  ) {
    final alarm = phase.stoppedByAlarm ? supervisor.patrolAlarm : null;
    final palette = alarm == null ? null : PatrolPalette.of(alarm.kind);
    final record =
        alarm == null ? null : supervisor.patrolRecordFor(alarm.alarmId);
    final recording = alarm == null || (record?.clipReady ?? false)
        ? null
        : alarm.recordingSec(supervisor.patrolNow());
    _syncTicker(recording != null);

    return [
      _StatusCard(
        borderColor: palette?.softBorder,
        children: [
          if (alarm == null || palette == null)
            const PatrolChip(
              label: '일시정지',
              tint: VicaColors.accentTint,
              ink: VicaColors.primaryDark,
              dot: VicaColors.primary,
            )
          else
            PatrolChip(
              label: '일시정지 — ${alarm.kind.shortTitle}',
              tint: palette.tint,
              ink: palette.ink,
              dot: palette.border,
            ),
          if (alarm != null && alarm.acked) _Headline(alarm.kind.ackedHeadline),
          if (alarm != null && alarm.statusLine.isNotEmpty)
            _Caption(alarm.statusLine),
        ],
      ),
      if (map != null) ...[
        _map(supervisor, settings, map, route, faded: true),
        const SizedBox(height: 12),
      ],
      if (alarm != null && palette != null)
        ..._media(settings, alarm, palette, record, recording),
      PressScale(
          child: FilledButton.icon(
        onPressed:
            _busy ? null : () => _send(() => supervisor.resumePatrol(settings)),
        style: _bigButtonStyle,
        icon: const Icon(Icons.play_arrow, size: 22),
        label: const Text('순찰 재개', style: _bigButtonText),
      )),
      const SizedBox(height: 10),
      PressScale(
          child: OutlinedButton(
        onPressed: _busy ? null : () => _confirmStop(supervisor, settings),
        style: patrolDangerOutlineStyle(),
        child: const Text('경비 종료'),
      )),
    ];
  }

  /// 경보에 딸린 영상(사람·큰 소리) 또는 사진(불 켜짐) 칸. 없으면 아무것도 그리지 않습니다.
  List<Widget> _media(
    AppSettings settings,
    PatrolAlarm alarm,
    PatrolPalette palette,
    PatrolRecord? record,
    int? recording,
  ) {
    final baseUrl = settings.mapHttpBaseUrl;
    final notice = context.read<SupervisorProvider>().patrolRecordsFailed
        ? <Widget>[
            VicaCard(
              key: const ValueKey('patrol_media_notice'),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: _Caption(patrolRecordsFailedText(baseUrl)),
            ),
          ]
        : const <Widget>[];
    if (alarm.kind == PatrolAlarmKind.light) {
      if (alarm.photo.isEmpty) {
        return notice;
      }
      final title = [
        alarm.kind.shortTitle,
        if (alarm.place.isNotEmpty) alarm.place,
        if (alarm.clock.isNotEmpty) alarm.clock,
      ].join(' · ');
      return [
        VicaCard(
          padding: const EdgeInsets.all(8),
          child: Semantics(
            label: alarm.kind.shortTitle,
            button: true,
            child: PressScale(
                child: InkWell(
              key: const ValueKey('patrol_photo'),
              onTap: () =>
                  showPatrolPhoto(context, title: title, photo: alarm.photo),
              borderRadius: BorderRadius.circular(12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ColoredBox(
                  color: PatrolColors.videoScreen,
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(
                      PatrolLogLoader.photoUri(baseUrl, alarm.photo).toString(),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const Center(
                        child: Icon(
                          Icons.image_outlined,
                          color: PatrolColors.videoLabel,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            )),
          ),
        ),
        ...notice,
      ];
    }
    if (!alarm.kind.hasClip) {
      return const [];
    }
    if (record != null && record.clipReady) {
      return [
        VicaCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              _ClipThumb(
                poster: PatrolLogLoader.posterUri(baseUrl, record.clipId),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [
                        '영상 저장됨',
                        if (record.clipLength.isNotEmpty) record.clipLength
                      ].join(' '),
                      style: const TextStyle(
                        color: VicaColors.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (record.clipRange.isNotEmpty) _Caption(record.clipRange),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              PressScale(
                  child: OutlinedButton(
                onPressed: () => showPatrolClip(
                  context,
                  record,
                  opener: widget.clipOpener,
                ),
                style: patrolSmallButtonStyle(),
                child: const Text('영상 보기', style: patrolSmallButtonText),
              )),
            ],
          ),
        ),
      ];
    }
    if (recording != null) {
      return [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: PatrolRecordingStrip(seconds: recording, palette: palette),
        ),
        ...notice,
      ];
    }
    return notice;
  }

  /// 순찰 지도. 레일·저장 장소·로봇 위에 순찰 번호를 얹습니다. 순찰 중에는 다음 장소에
  Widget _map(SupervisorProvider supervisor, AppSettings settings, VicaMap map,
      PatrolRoute? route,
      {required bool faded}) {
    final locations = supervisor.locationsFor(map.mapId);
    final byId = <String, LocationPoint>{
      for (final location in locations) location.locationId: location,
    };
    final ids = route?.ids ?? const <String>[];
    final nextIndex = supervisor.patrolWaypointIndex;
    final marks = <PatrolPlaceMark>[];
    for (var i = 0; i < ids.length; i++) {
      final location = byId[ids[i]];
      if (location == null) {
        continue;
      }
      marks.add(
        PatrolPlaceMark(
          id: location.locationId,
          x: location.x,
          y: location.y,
          name: location.name,
          number: i + 1,
          style: faded
              ? PatrolMarkStyle.faded
              : (i == nextIndex
                  ? PatrolMarkStyle.next
                  : PatrolMarkStyle.normal),
        ),
      );
    }
    return ResponsiveMapFrame(
      map: map,
      minHeight: 200,
      maxHeight: 420,
      child: MapCanvas(
        map: map,
        settings: settings,
        locations: locations,
        robot: supervisor.primaryRobot,
        routeGraph: supervisor.routeGraphFor(map.mapId),
        overlayBuilder: (toPixel) => buildPatrolMapOverlay(toPixel, marks),
      ),
    );
  }

  void _syncTicker(bool needed) {
    if (needed == (_ticker != null)) {
      return;
    }
    _ticker?.cancel();
    _ticker = needed
        ? Timer.periodic(const Duration(seconds: 1), (_) {
            if (mounted) {
              setState(() {});
            }
          })
        : null;
  }

  Future<void> _start(
    SupervisorProvider supervisor,
    AppSettings settings,
    PatrolRoute? route,
  ) async {
    if (route != null && route.length < 2) {
      showPatrolToast(context, '순찰 지점이 2곳 이상이어야 경비를 시작할 수 있습니다.');
      return;
    }
    await _send(() => supervisor.startPatrol(settings));
  }

  /// 감시 항목 하나를 켜거나 끕니다. 받아들여지면 스위치가 바뀌는 것이 결과이고, 거절이면 한 줄을 띄웁니다.
  Future<void> _setWatch(
    SupervisorProvider supervisor,
    AppSettings settings,
    PatrolRoute route,
    PatrolAlarmKind kind,
    bool on,
  ) =>
      _send(() async {
        final (_, message) =
            await supervisor.setPatrolWatch(settings, route.mapId, kind, on);
        return message;
      });

  Future<void> _confirmStop(
    SupervisorProvider supervisor,
    AppSettings settings,
  ) async {
    final confirmed = await showVicaConfirm(
      context,
      icon: Icons.stop_circle_outlined,
      iconColor: VicaColors.red,
      title: '경비를 종료할까요?',
      body: '순찰을 멈추고 로봇이 홈으로 돌아갑니다.\n녹화 중인 영상은 끝까지 저장합니다.',
      cancelLabel: '계속 경비',
      confirmLabel: '경비 종료',
      danger: true,
    );
    if (!confirmed || !mounted) {
      return;
    }
    await _send(() => supervisor.stopPatrol(settings));
  }

  /// 명령 하나를 보내고 돌아온 문구를 화면 아래에 알립니다. 기다리는 동안 버튼을 잠급니다.
  Future<void> _send(Future<String> Function() call) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    final message = await call();
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    showPatrolToast(context, message);
  }

  static final ButtonStyle _bigButtonStyle = FilledButton.styleFrom(
    minimumSize: const Size.fromHeight(52),
  );

  /// 큰 버튼의 글자. ButtonStyle.textStyle 로 주면 테마 글꼴이 빠집니다
  static const TextStyle _bigButtonText =
      TextStyle(fontSize: 16, fontWeight: FontWeight.w800);
}

/// 상태 칸. 경보로 멈췄을 때는 그 종류의 색 테두리(2px)를 두릅니다.
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.children, this.borderColor});

  final List<Widget> children;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: VicaColors.card,
        border: Border.all(
          color: borderColor ?? VicaColors.border,
          width: borderColor == null ? 1 : 2,
        ),
        borderRadius: BorderRadius.circular(kVicaCardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _CardTitle extends StatelessWidget {
  const _CardTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: VicaColors.text,
        fontSize: 15,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      patrolKeepWords(text),
      style: const TextStyle(
        color: VicaColors.text,
        fontSize: 15,
        fontWeight: FontWeight.w800,
        height: 1.45,
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      patrolKeepWords(text),
      style: const TextStyle(color: VicaColors.muted, fontSize: 12),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// '장소 6곳' 같은 개수 알약.
class _CountPill extends StatelessWidget {
  const _CountPill(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 28),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        border: Border.all(color: VicaColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        style: const TextStyle(color: VicaColors.muted, fontSize: 12),
      ),
    );
  }
}

/// 감시 항목 한 줄: 이름·설명과 스위치. 줄 전체를 누르면 켜고 끕니다. [onChanged] 가 null 이면
class _WatchRow extends StatelessWidget {
  const _WatchRow({
    required this.title,
    required this.caption,
    required this.on,
    required this.onChanged,
  });

  final String title;
  final String caption;
  final bool on;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final change = onChanged;
    return Semantics(
      container: true,
      toggled: on,
      enabled: change != null,
      child: PressScale(
          child: InkWell(
        onTap: change == null ? null : () => change(!on),
        borderRadius: BorderRadius.circular(8),
        child: Opacity(
          opacity: change == null ? 0.5 : 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: VicaColors.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      _Caption(caption),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                PatrolSwitchMark(on: on),
              ],
            ),
          ),
        ),
      )),
    );
  }
}

/// 영상 칸 왼쪽의 작은 그림: 첫 장 위에 재생 표시.
class _ClipThumb extends StatelessWidget {
  const _ClipThumb({required this.poster});

  final Uri poster;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 64,
        height: 48,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: PatrolColors.videoScreen),
            Image.network(
              poster.toString(),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
            ),
            const Center(
              child: Icon(Icons.play_arrow, color: Colors.white, size: 22),
            ),
          ],
        ),
      ),
    );
  }
}
