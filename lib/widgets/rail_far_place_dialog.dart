import 'package:flutter/material.dart';

import 'vica_ui.dart';

/// 팝업 본문. 시험이 문구를 고정할 수 있게 함수로 둡니다.
String railFarPlaceMessage(String name, double meters) =>
    "새 장소 '$name'${subjectParticle(name)} 레일에서 "
    '${meters.toStringAsFixed(1)} m 떨어져 있습니다.\n'
    '레일 없이 자유주행함을 주의하세요.';

/// 이름 뒤 주격 조사. 끝 글자가 한글이면 받침으로 '이'/'가'를 고르고, 한글이
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
