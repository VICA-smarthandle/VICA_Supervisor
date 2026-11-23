// 이 파일은 마이크 점검 화면의 확인 시트 3종(캔버스 110)을 그립니다.
// 저장(.env 에 쓸 줄 미리보기)·원래대로(백업 되돌리기)·끝내기. 눌러 확정하면 true, 취소·닫기는 false 입니다.
import 'package:flutter/material.dart';

import '../../models/mic_check.dart';
import '../vica_ui.dart';

Future<bool> _sheet(BuildContext context, {required String title, required List<Widget> body, required String ok}) async {
  final r = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: VicaColors.card,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            ...body,
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('mic_check_sheet_cancel'),
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('취소'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('mic_check_sheet_ok'),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(ok),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  return r == true;
}

const _note = TextStyle(fontSize: 13, color: VicaColors.muted);

/// '저장' 확인: 쓰기 전에 `.env` 에 쓸 줄을 보여 줍니다.
Future<bool> showMicSaveSheet(BuildContext context, MicCheckSavePreview preview) => _sheet(
      context,
      title: '.env 에 이렇게 씁니다',
      ok: '저장',
      body: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: VicaColors.surfaceSunken,
            borderRadius: BorderRadius.circular(kVicaFieldRadius),
          ),
          child: Text(
            preview.lines.join('\n'),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
        ),
        const SizedBox(height: 10),
        const Text('백업 뒤 저장 · 음성 노드를 다시 켜야 적용', style: _note),
      ],
    );

/// '원래대로' 확인.
Future<bool> showMicRestoreSheet(BuildContext context) => _sheet(
      context,
      title: '가장 최근 백업으로 되돌릴까요?',
      ok: '되돌리기',
      body: const [Text('마이크 값 10개만 · 음성 노드를 다시 켜야 적용', style: _note)],
    );

/// '끝내기' 확인.
Future<bool> showMicFinishSheet(BuildContext context) => _sheet(
      context,
      title: '점검을 끝낼까요?',
      ok: '끝내기',
      body: const [Text('칩을 .env 값으로 되돌리고 끝냅니다 · 기록은 젯슨에 남음', style: _note)],
    );
