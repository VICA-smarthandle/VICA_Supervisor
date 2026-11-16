// 장소 이름 뒤에 붙는 조사를 받침에 맞춰 고릅니다(2026-11-14, 경비 화면).
//
// '화장실로'·'식당으로', '작업실을'·'입구를'처럼 이름이 문장 안에 들어가는 자리에 씁니다.
// 한글·숫자로 끝나면 맞는 쪽을 고르고, 영문자처럼 읽는 법을 모르는 글자로 끝나면
// 앱의 다른 화면과 같은 '(으)로'·'을(를)'을 돌려줍니다.

/// 이름 끝 글자의 받침. 모르면 null.
({bool hasFinal, bool rieul})? _finalOf(String word) {
  // 닫는 괄호·따옴표·공백은 건너뛰고 그 앞 글자를 봅니다('화장실(남)' → '남').
  final trimmed = word.replaceAll(RegExp('[\\s)\\]}"\'’”]+\$'), '');
  if (trimmed.isEmpty) {
    return null;
  }
  final code = trimmed.runes.last;
  if (code >= 0xAC00 && code <= 0xD7A3) {
    final jong = (code - 0xAC00) % 28;
    return (hasFinal: jong != 0, rieul: jong == 8);
  }
  // 숫자는 한자음으로 읽습니다: 영·일·이·삼·사·오·육·칠·팔·구.
  switch (String.fromCharCode(code)) {
    case '0' || '3' || '6':
      return (hasFinal: true, rieul: false);
    case '1' || '7' || '8':
      return (hasFinal: true, rieul: true);
    case '2' || '4' || '5' || '9':
      return (hasFinal: false, rieul: false);
  }
  return null;
}

/// '로' 또는 '으로'. 받침이 없거나 ㄹ 받침이면 '로'입니다.
String josaRo(String word) {
  final last = _finalOf(word);
  if (last == null) {
    return '(으)로';
  }
  return !last.hasFinal || last.rieul ? '로' : '으로';
}

/// '을' 또는 '를'.
String josaEulReul(String word) {
  final last = _finalOf(word);
  if (last == null) {
    return '을(를)';
  }
  return last.hasFinal ? '을' : '를';
}
