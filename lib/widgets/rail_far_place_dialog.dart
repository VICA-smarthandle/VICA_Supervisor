// 새 장소가 레일에서 멀리 떨어져 있을 때 띄우는 팝업(레일 팝업 E, 2026-09-30 사용자 확정).
//
// 장소 저장 칸에서 저장한 직후에 뜹니다. 관리자는 그때 레일 칸이 아니라 장소 칸을
// 보고 있어서, 레일 칸 안의 경고를 볼 수 없습니다. 저장은 막지 않습니다 — 로봇은
// 그 장소에 레일 없이 자유주행으로 갑니다.
//
// 문구(사용자 확정): "새 장소 '…'이 레일에서 … m 떨어져 있습니다.
//                     레일 없이 자유주행함을 주의하세요."
// 버튼: [확인] [레일 편집]. 레일 편집은 true 를 돌려주고, 지도 설정 화면이 레일
// 칸을 펼칩니다.
import 'package:flutter/material.dart';

import 'vica_ui.dart';

/// 팝업 본문. 시험이 문구를 고정할 수 있게 함수로 둡니다.
String railFarPlaceMessage(String name, double meters) =>
    "새 장소 '$name'${subjectParticle(name)} 레일에서 "
    '${meters.toStringAsFixed(1)} m 떨어져 있습니다.\n'
    '레일 없이 자유주행함을 주의하세요.';

/// 이름 뒤 주격 조사. 끝 글자가 한글이면 받침으로 '이'/'가'를 고르고, 한글이
/// 아니면(숫자·영문) 읽는 법을 알 수 없어 '이(가)'로 둡니다.
String subjectParticle(String name) {
  final trimmed = name.trimRight();
  if (trimmed.isEmpty) {
    return '이(가)';
  }
  final code = trimmed.runes.last;
  if (code < 0xAC00 || code > 0xD7A3) {
    return '이(가)';
  }
  return (code - 0xAC00) % 28 == 0 ? '가' : '이';
}

class RailFarPlaceDialog extends StatelessWidget {
  const RailFarPlaceDialog({
    super.key,
    required this.name,
    required this.meters,
  });

  final String name;
  final double meters;

  @override
  Widget build(BuildContext context) {
    return VicaDialog(
      icon: Icons.warning_amber_rounded,
      iconColor: VicaColors.warning,
      title: '새 장소가 레일에서 떨어져 있습니다',
      body: railFarPlaceMessage(name, meters),
      actions: [
        VicaCancelButton(
          onPressed: () => Navigator.of(context).pop(false),
          label: '확인',
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('레일 편집'),
        ),
      ],
    );
  }
}
