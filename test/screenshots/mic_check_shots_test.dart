import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vica_supervisor/app.dart' show vicaTheme;
import 'package:vica_supervisor/models/mic_check.dart';
import 'package:vica_supervisor/models/mode_status.dart';
import 'package:vica_supervisor/models/stack_status.dart';
import 'package:vica_supervisor/providers/app_mode_provider.dart';
import 'package:vica_supervisor/providers/auth_provider.dart';
import 'package:vica_supervisor/providers/settings_provider.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';
import 'package:vica_supervisor/screens/mic_check_screen.dart';
import 'package:vica_supervisor/screens/mode_select_screen.dart';
import 'package:vica_supervisor/services/mic_check_controller.dart';
import 'package:vica_supervisor/widgets/drive_nodes_card.dart';
import 'package:vica_supervisor/widgets/mic_check_entry.dart';

final String? _outDir = Platform.environment['VICA_SHOTS_DIR'];

class _Fake extends MicCheckController {
  _Fake() : super(uri: Uri.parse('ws://h:8770/ws'));
  final StreamController<String> _t = StreamController<String>.broadcast();
  @override
  Stream<String> get toasts => _t.stream;
  @override
  bool send(String cmd, [Map<String, Object?> args = const {}]) => true;
  void push({MicCheckResults? results, MicCheckSavePreview? savePreview}) {
    if (results != null) this.results = results;
    if (savePreview != null) this.savePreview = savePreview;
    notifyListeners();
  }
}

class _NoopController extends MicCheckController {
  _NoopController(Uri uri) : super(uri: uri);
  @override
  void start() {}
}

class _Sup extends SupervisorProvider {
  void injectStack(StackStatus? s) => setStackStatusForTest(s);
  void injectMode(ModeStatus? s) => setModeStatusForTest(s);
  @override
  String get connectedUrl => 'ws://10.0.0.5:9090';
  @override
  Future<(bool, String)> startMicCheck() async => (true, '');
}

const _progress = {
  'quiet': ['pass'],
  'call': ['pass', 'pass', 'pass', 'warn', 'warn'],
  'answer': ['pass', 'pass', 'pass', 'pass'],
  'stop': ['pass', 'pass', 'pass', 'pass', 'pass'],
  'robot': ['pass'],
  'far': ['pass', 'pass'],
  'near': ['pass', 'warn', 'fail'],
};

MicCheckStatus _status({
  String key = 'call',
  int no = 3,
  String name = '호출',
  String say = '“비카야” — 한 박자 쉬고 — “화장실로 가자”',
  int rep = 2,
  int reps = 5,
  bool robot = false,
  Map<String, Object?> progress = const {},
}) =>
    MicCheckStatus.fromJson({
      'place': 'vica_map_0630',
      'step': {
        'key': key,
        'no': no,
        'of': 9,
        'name': name,
        'say': say,
        'rep': rep,
        'reps': reps,
        'seconds': 6.0,
        'recording': false,
        'robot': robot
      },
      'steps': [
        {'key': 'quiet', 'name': '조용히', 'need': 1},
        {'key': 'call', 'name': '호출', 'need': 5},
        {'key': 'answer', 'name': '짧은 답', 'need': 4},
        {'key': 'stop', 'name': '멈춰', 'need': 5},
        {'key': 'robot', 'name': '로봇 말하기', 'need': 1},
        {'key': 'far', 'name': '먼 대답', 'need': 2},
        {'key': 'near', 'name': '옆사람', 'need': 3},
      ],
      'progress': progress,
      'values': {
        'listen_min_rms': 0.027,
        'short_answer_min_rms': 0.027,
        'approach_min_rms': 0.006,
        'band_min': 0.01,
        'wake_threshold': 0.7,
        'emergency_single': 0.5,
        'agc': 0.007,
        'agc_max_gain': 4.0,
        'echo': 'strong',
      },
      'env_values': {
        'listen_min_rms': 0.024,
        'short_answer_min_rms': 0.02,
        'approach_min_rms': 0.006,
        'band_min': 0.01,
        'wake_threshold': 0.7,
        'emergency_single': 0.5,
        'agc': 0.007,
        'agc_max_gain': 4.0,
        'echo': 'strong',
      },
      'ranges': {
        'listen_min_rms': [0.002, 0.1, 0.0005],
        'short_answer_min_rms': [0.002, 0.1, 0.001],
        'approach_min_rms': [0.001, 0.08, 0.0005],
        'band_min': [0.0005, 0.03, 0.0005],
        'wake_threshold': [0.3, 0.95, 0.01],
        'emergency_single': [0.3, 0.9, 0.01],
      },
      'names': {
        'listen_min_rms': '수음 최소',
        'short_answer_min_rms': '짧은 답 최소',
        'approach_min_rms': '접근 대답 최소',
        'band_min': '말소리 대역 최소',
        'wake_threshold': '호출 문턱',
        'emergency_single': '“멈춰” 한 조각 문턱',
        'agc': 'AGC 목표',
        'agc_max_gain': 'AGC 최대 증폭',
        'echo': '에코 지우기',
      },
      'env_keys': {
        'listen_min_rms': 'VICA_LISTEN_MIN_RMS',
        'short_answer_min_rms': 'VICA_SHORT_ANSWER_MIN_RMS',
        'approach_min_rms': 'VICA_APPROACH_MIN_RMS',
        'band_min': 'VICA_LISTEN_BAND_MIN',
        'wake_threshold': 'VICA_WAKE_THRESHOLD',
        'emergency_single': 'VICA_EMERGENCY_SINGLE_FRAME',
        'agc': 'VICA_MIC_AGC_DESIRED',
        'agc_max_gain': 'VICA_MIC_AGC_MAX_GAIN',
        'echo': 'VICA_MIC_GAMMA_ETAIL',
      },
      'agc_choices': [0.003, 0.005, 0.007, 0.01, 0.014, 0.02],
      'gain_choices': [1.0, 2.0, 4.0, 8.0, 16.0, 31.6],
      'echo_choices': {
        'weak': '약 (0.5·켜짐)',
        'mid': '중간 (1.0·켜짐)',
        'strong': '센 (1.5·켜짐)',
        'max': '최대 (3.0·켜짐)',
        'factory': '공장값 (1.0·꺼짐)',
      },
      'gain_factory': 31.6,
      'short_over_listen': 1.0,
      'chip_ok': true,
      'noise_at_check': 0.0017,
    });

MicCheckFrame _frame({double? recLeft}) => MicCheckFrame.fromJson({
      'rms': 0.061,
      'wake': 0.84,
      'stop': 0.08,
      'robot': false,
      'muted': false,
      'state': 'listening',
      'vad': true,
      'noise': 0.0017,
      if (recLeft != null) 'rec_left': recLeft,
    });

MicCheckResults _results() => MicCheckResults.fromJson({
      'title': '고친 뒤 다시',
      'overall': 'fail',
      'stale': true,
      'rows': [
        {
          'key': 'noise',
          'name': '잡음 바닥',
          'grade': 'pass',
          'detail': '0.0017 · 수음 최소까지 14.0배',
          'todo': ''
        },
        {
          'key': 'call',
          'name': '“비카야” 쉬고 “화장실로 가자” ×3',
          'grade': 'pass',
          'detail': '3/3 · 가장 낮은 점수 0.99',
          'todo': ''
        },
        {
          'key': 'run',
          'name': '“비카야화장실로가자” 이어서 ×2 (참고)',
          'grade': 'warn',
          'detail': '0/2 · 가장 낮은 점수 0.47 · 호출 놓침',
          'todo': '쉬지 않고 말하면 지금 귀는 목적지를 놓칩니다. 시연 때는 “비카야” 뒤 “네?”를 듣고 말하세요.'
        },
        {
          'key': 'answer',
          'name': '“그래”·“아니” ×4',
          'grade': 'pass',
          'detail': '4/4 · 가장 작은 소리 0.045 (짧은 답 최소의 2.2배)',
          'todo': ''
        },
        {
          'key': 'stop',
          'name': '“멈춰” ×5',
          'grade': 'pass',
          'detail': '5/5',
          'todo': ''
        },
        {
          'key': 'robot',
          'name': '로봇 혼자 말하기',
          'grade': 'pass',
          'detail': '자기 반응 0회 · 로봇 목소리 0.004 (지난 점검 0.005)',
          'todo': ''
        },
        {
          'key': 'far',
          'name': '먼 대답 “그래”·“아니” ×2 (1~1.5 m)',
          'grade': 'pass',
          'detail': '2/2 · 가장 작은 소리 0.0166 (접근 대답 최소 0.0060)',
          'todo': ''
        },
        {
          'key': 'near',
          'name': '옆사람 잡담 ×3 (1~3 m)',
          'grade': 'fail',
          'detail':
              "질문 창 통과 1/3 · 접근 창 통과 2/3 · 옆사람 최대 0.0489 · 사용자 최소 0.0446 (-0.8 dB) · 먼 대답 최소 0.0166 (-9.4 dB) · 받아쓰기 '지금부터 시작합니다. 잡음 테스트.'",
          'todo':
              '옆사람 말이 질문 창에 들어갑니다. 수음 최소를 올리거나 최대 증폭을 낮추세요(증폭을 낮추면 접근 대답 최소·대역 최소도 함께 낮춰야 합니다).'
        },
        {
          'key': 'cross',
          'name': '오발동',
          'grade': 'pass',
          'detail': '0회',
          'todo': ''
        },
      ],
    });

const _preview = MicCheckSavePreview(
  lines: [
    'VICA_LISTEN_MIN_RMS=0.027  # 11-21 vica_map_0630 점검에서 바꿈 (전 0.024)',
    'VICA_SHORT_ANSWER_MIN_RMS=0.027  # 11-21 vica_map_0630 점검에서 바꿈 (전 0.02)',
  ],
  backupDir: '/home/ji_w/vica_data/mic_checks/env_backups',
);

final _boundary = GlobalKey();

Future<void> _load(String family, List<Future<ByteData>> data) async {
  final l = FontLoader(family);
  for (final d in data) {
    l.addFont(d);
  }
  await l.load();
}

Future<void> _shoot(WidgetTester tester, String name) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.runAsync(() async {
    final b =
        _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: 2);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    await File('$_outDir/$name.png').writeAsBytes(bytes.buffer.asUint8List());
  });
}

void _size(WidgetTester tester, double w, double h) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(w, h);
  addTearDown(tester.view.resetPhysicalSize);
}

Widget _wrap(Widget app) => RepaintBoundary(key: _boundary, child: app);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final skip = _outDir == null ? 'VICA_SHOTS_DIR 없음' : null;

  setUpAll(() async {
    if (_outDir == null) return;
    Directory(_outDir!).createSync(recursive: true);
    await _load('NanumGothic', [
      rootBundle.load('assets/fonts/NanumGothic.ttf'),
      rootBundle.load('assets/fonts/NanumGothicBold.ttf'),
    ]);
    for (final f in ['Roboto', 'monospace']) {
      await _load(f, [
        rootBundle.load('assets/fonts/NanumGothic.ttf'),
        rootBundle.load('assets/fonts/NanumGothicBold.ttf'),
      ]);
    }
    final root = Platform.environment['FLUTTER_ROOT'] ??
        '/home/ji_w/development/flutter';
    final bytes = File(
            '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
        .readAsBytesSync();
    await _load('MaterialIcons', [Future.value(ByteData.sublistView(bytes))]);
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<_Fake> mic(
    WidgetTester tester,
    String name, {
    double width = 390,
    double height = 2600,
    void Function(_Fake)? setup,
    Future<void> Function(WidgetTester, _Fake)? after,
  }) async {
    _size(tester, width, height);
    final c = _Fake()..connected = true;
    addTearDown(c.dispose);
    setup?.call(c);
    await tester.pumpWidget(_wrap(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: vicaTheme(),
        home: MicCheckScreen(controller: c))));
    await tester.pump();
    if (after != null) await after(tester, c);
    await _shoot(tester, name);
    return c;
  }

  Future<void> tapKey(WidgetTester t, String k) async {
    final f = find.byKey(ValueKey(k));
    await t.ensureVisible(f);
    await t.tap(f);
    await t.pumpAndSettle();
  }

  group('점검 화면', () {
    testWidgets('01', skip: skip != null, (t) async {
      await mic(t, '01_점검_준비중',
          height: 900, setup: (c) => c.prep = '젯슨이 준비하는 중입니다(모델 올리기 1~2분)…');
    });
    testWidgets('02', skip: skip != null, (t) async {
      await mic(t, '02_점검_단계_녹음전', setup: (c) {
        c.status = _status(progress: _progress);
        c.frame = _frame();
      });
    });
    testWidgets('03', skip: skip != null, (t) async {
      await mic(t, '03_점검_녹음중', setup: (c) {
        c.status = _status(progress: _progress);
        c.frame = _frame(recLeft: 4.2);
      });
    });
    testWidgets('04', skip: skip != null, (t) async {
      await mic(t, '04_점검_로봇말하기', setup: (c) {
        c.status = _status(
            key: 'robot',
            no: 6,
            name: '로봇 혼자 말하기',
            say: '로봇이 혼자 말합니다 · 말하지 마세요',
            rep: 0,
            reps: 1,
            robot: true,
            progress: _progress);
        c.frame = _frame();
      });
    });
    void result(String name, {double width = 390, double height = 3700}) =>
        testWidgets(name, skip: skip != null, (t) async {
          await mic(t, name, width: width, height: height, setup: (c) {
            c.status = _status(
                key: 'result',
                no: 9,
                name: '결과표',
                say: '',
                rep: 0,
                reps: 0,
                progress: _progress);
            c.frame = _frame();
            c.results = _results();
          });
        });
    result('05_점검_결과표_값고치기');
    testWidgets('06', skip: skip != null, (t) async {
      await mic(t, '06_시트_저장미리보기', height: 1000, setup: (c) {
        c.status = _status(
            key: 'result',
            no: 9,
            name: '결과표',
            say: '',
            rep: 0,
            reps: 0,
            progress: _progress);
        c.frame = _frame();
        c.results = _results();
      }, after: (t, c) async {
        await tapKey(t, 'mic_check_save');
        c.push(savePreview: _preview);
        await t.pumpAndSettle();
      });
    });
    testWidgets('07', skip: skip != null, (t) async {
      await mic(t, '07_시트_원래대로',
          height: 1000,
          setup: (c) {
            c.status = _status(
                key: 'result',
                no: 9,
                name: '결과표',
                say: '',
                rep: 0,
                reps: 0,
                progress: _progress);
            c.frame = _frame();
            c.results = _results();
          },
          after: (t, c) => tapKey(t, 'mic_check_restore'));
    });
    testWidgets('08', skip: skip != null, (t) async {
      await mic(t, '08_시트_끝내기',
          height: 1000,
          setup: (c) {
            c.status = _status(
                key: 'result',
                no: 9,
                name: '결과표',
                say: '',
                rep: 0,
                reps: 0,
                progress: _progress);
            c.frame = _frame();
            c.results = _results();
          },
          after: (t, c) => tapKey(t, 'mic_check_finish'));
    });
    testWidgets('09', skip: skip != null, (t) async {
      await mic(t, '09_점검_연결끊김', setup: (c) {
        c.connected = false;
        c.status = _status(progress: _progress);
        c.frame = _frame();
      });
    });
    testWidgets('10', skip: skip != null, (t) async {
      await mic(t, '10_점검_넓은화면', width: 1280, height: 1800, setup: (c) {
        c.status = _status(
            key: 'result',
            no: 9,
            name: '결과표',
            say: '',
            rep: 0,
            reps: 0,
            progress: _progress);
        c.frame = _frame();
        c.results = _results();
      });
    });
  });

  ModeStatus drive(
          {String detector = 'active',
          String voice = 'active',
          String micCheck = 'none'}) =>
      ModeStatus(
        mode: 'drive',
        state: ModeState.running,
        nav2: 'active',
        detector: detector,
        voice: voice,
        voiceChoice: VoiceChoice.local,
        micCheck: micCheck,
      );

  Future<void> card(WidgetTester t, String name, ModeStatus st,
      {bool tapEntry = false}) async {
    _size(t, 390, 1100);
    final sup = _Sup()..setModeStatusForTest(st);
    micCheckControllerFactory = _NoopController.new;
    await t.pumpWidget(_wrap(MultiProvider(
      providers: [
        ChangeNotifierProvider<SupervisorProvider>.value(value: sup),
        ChangeNotifierProvider(create: (_) => AppModeProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: vicaTheme(),
          home: const Scaffold(
              body: SingleChildScrollView(child: DriveNodesCard()))),
    )));
    await t.pump();
    if (tapEntry) {
      await t.tap(find.byKey(const ValueKey('mic_check_entry_button')));
      await t.pumpAndSettle();
    }
    await _shoot(t, name);
  }

  group('주행 설정 칸', () {
    testWidgets(
        '11', skip: skip != null, (t) => card(t, '11_주행설정_음성켜짐', drive()));
    testWidgets(
        '12',
        skip: skip != null,
        (t) => card(t, '12_주행설정_음성꺼짐', drive(voice: 'inactive')));
    testWidgets(
        '13',
        skip: skip != null,
        (t) => card(
            t,
            '13_주행설정_점검중',
            drive(
                voice: 'inactive', detector: 'inactive', micCheck: 'active')));
    testWidgets(
        '14',
        skip: skip != null,
        (t) =>
            card(t, '14_점검시작_확인창', drive(voice: 'inactive'), tapEntry: true));
  });

  Future<void> modeSel(WidgetTester t, String name, String micCheck) async {
    _size(t, 390, 1100);
    final sup = _Sup();
    micCheckControllerFactory = _NoopController.new;
    await t.pumpWidget(_wrap(MultiProvider(
      providers: [
        ChangeNotifierProvider<SupervisorProvider>.value(value: sup),
        ChangeNotifierProvider<AppModeProvider>.value(value: AppModeProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
      ],
      child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: vicaTheme(),
          home: const ModeSelectScreen()),
    )));
    await t.pump();
    sup.injectStack(const StackStatus(nodes: [], odomPublishers: []));
    sup.injectMode(
        ModeStatus(mode: 'idle', state: ModeState.idle, micCheck: micCheck));
    await t.pump();
    await _shoot(t, name);
  }

  group('모드 선택', () {
    testWidgets(
        '15', skip: skip != null, (t) => modeSel(t, '15_모드선택_평소', 'none'));
    testWidgets(
        '16', skip: skip != null, (t) => modeSel(t, '16_모드선택_점검중', 'active'));
  });
}
