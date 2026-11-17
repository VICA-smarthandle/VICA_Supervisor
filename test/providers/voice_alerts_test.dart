// 음성 연결 알림(2026-11-16 목업 D·E): 번호로 한 번만, 연결 직후 첫 상태는 기록만.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vica_supervisor/core/log_filter.dart';
import 'package:vica_supervisor/providers/supervisor_provider.dart';

Map<String, Object?> status(double epoch, List<(int, String, String)> events) => {
      'mode': 'drive',
      'state': 'running',
      'voice_events_epoch': epoch,
      'voice_events': [
        for (final (id, kind, text) in events) {'id': id, 'at': 1794825000.0 + id, 'kind': kind, 'text': text},
      ],
    };

List<String> voiceLogs(SupervisorProvider s) => s.logs
    .where((log) => log.filter == LogFilter.connection && log.message.startsWith('음성: '))
    .map((log) => log.message)
    .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('연결 직후 첫 상태의 알림은 기록만 하고 띄우지 않는다', () {
    final s = SupervisorProvider();
    s.handleModeStatusForTest(status(1, [(1, 'external_ok', '외부 API 연결 성공')]));

    expect(voiceLogs(s), hasLength(1));
    expect(voiceLogs(s).single, startsWith('음성: 외부 API 연결 성공 ('));
    expect(s.takeVoiceAlerts(), isEmpty);
    expect(s.lastVoiceEvent?.kind, 'external_ok');
  });

  test('그 뒤 새 번호는 띄우고, 같은 번호는 다시 남기지 않는다', () {
    final s = SupervisorProvider();
    s.handleModeStatusForTest(status(1, [(1, 'external_ok', '외부 API 연결 성공')]));
    final seq = s.voiceAlertSeq;
    s.handleModeStatusForTest(status(1, [
      (1, 'external_ok', '외부 API 연결 성공'),
      (2, 'external_fallback', '외부 API 연결 실패 → 로컬 API 로 전환'),
    ]));
    s.handleModeStatusForTest(status(1, [
      (1, 'external_ok', '외부 API 연결 성공'),
      (2, 'external_fallback', '외부 API 연결 실패 → 로컬 API 로 전환'),
    ]));

    expect(s.voiceAlertSeq, seq + 1);
    expect(s.takeVoiceAlerts().map((e) => e.id), [2]);
    expect(s.takeVoiceAlerts(), isEmpty, reason: '꺼내면 비운다');
    expect(voiceLogs(s), hasLength(2));
  });

  test('모드 노드가 다시 뜨면(epoch 바뀜) 번호 1 부터 다시 받는다', () {
    final s = SupervisorProvider();
    s.handleModeStatusForTest(status(1, [(1, 'external_ok', '외부 API 연결 성공'), (2, 'local_fail', '로컬 API 연결 실패')]));
    s.handleModeStatusForTest(status(2, [(1, 'local_ok', '로컬 API 연결 성공')]));

    expect(s.takeVoiceAlerts().map((e) => e.kind), ['local_ok']);
    expect(voiceLogs(s), hasLength(3));
  });
}
