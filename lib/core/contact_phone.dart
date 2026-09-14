// 이 파일은 물류 배송 도착 문자를 받을 연락처의 모양을 정합니다.
//
// 규칙은 ROS 쪽 vica_destination_manager/storage.py 의 normalize_contact_phone 과
// 같습니다. 파일에는 숫자만('01012345678') 남기고, 사람에게 보일 때만 하이픈을
// 붙이거나 가운데를 가립니다. 두 곳의 규칙이 다르면 앱은 통과시키고 로봇은
// 거부하는 번호가 생겨, 관리자는 저장이 됐다고 믿는데 파일에는 없게 됩니다.

/// 숫자만 남긴 뒤 국내 휴대폰 번호(010·011·016·017·018·019) 모양인지 봅니다.
final _mobilePattern = RegExp(r'^01[016789][0-9]{7,8}$');

/// 입력을 저장용 숫자 문자열로 바꿉니다.
///
/// 빈 입력은 `''` 입니다 — 연락처 없는 장소는 정상이고 배송 대상에서만 빠집니다.
/// 값이 있는데 휴대폰 번호가 아니면 `null` 을 돌려줍니다. 폼 validator 가 이 null
/// 을 보고 "휴대폰 번호 모양이 아닙니다"를 띄웁니다.
String? normalizeContactPhone(String input) {
  final text = input.trim();
  if (text.isEmpty) {
    return '';
  }
  // 'abc' 처럼 숫자가 하나도 없는 값을 빈 값으로 눙치면 오타가 조용히 사라집니다.
  // 무엇이든 적었으면 번호 모양이어야 합니다.
  final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
  return _mobilePattern.hasMatch(digits) ? digits : null;
}

/// 편집 칸에 보여줄 모양. `01012345678` → `010-1234-5678`.
///
/// 저장된 숫자열이 아닌 값(옛 파일의 이상한 값)은 손대지 않고 그대로 돌려줍니다.
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
///
/// 전화번호는 개인정보라 편집할 때 말고는 전체를 보이지 않습니다. 로그에는
/// 이것도 쓰지 말고 장소 이름만 남깁니다.
String maskContactPhone(String digits) {
  if (!_mobilePattern.hasMatch(digits)) {
    return digits.isEmpty ? '' : '****';
  }
  final head = digits.substring(0, 3);
  final tail = digits.substring(digits.length - 4);
  return '$head-****-$tail';
}
