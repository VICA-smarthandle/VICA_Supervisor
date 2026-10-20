/// 숫자만 남긴 뒤 국내 휴대폰 번호(010·011·016·017·018·019) 모양인지 봅니다.
final _mobilePattern = RegExp(r'^01[016789][0-9]{7,8}$');

/// 입력을 저장용 숫자 문자열로 바꿉니다.
String? normalizeContactPhone(String input) {
  final text = input.trim();
  if (text.isEmpty) {
    return '';
  }
  final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
  return _mobilePattern.hasMatch(digits) ? digits : null;
}

/// 편집 칸에 보여줄 모양. `01012345678` → `010-1234-5678`.
String formatContactPhone(String digits) {
  if (!_mobilePattern.hasMatch(digits)) {
    return digits;
  }
  final head = digits.substring(0, 3);
  final tail = digits.substring(digits.length - 4);
  final middle = digits.substring(3, digits.length - 4);
  return '$head-$middle-$tail';
}

/// 목록·요약처럼 그냥 보기만 하는 자리에 쓰는 모양. `010-****-5678`.
String maskContactPhone(String digits) {
  if (!_mobilePattern.hasMatch(digits)) {
    return digits.isEmpty ? '' : '****';
  }
  final head = digits.substring(0, 3);
  final tail = digits.substring(digits.length - 4);
  return '$head-****-$tail';
}
