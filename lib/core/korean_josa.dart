/// 이름 끝 글자의 받침. 모르면 null.
({bool hasFinal, bool rieul})? _finalOf(String word) {
  final trimmed = word.replaceAll(RegExp('[\\s)\\]}"\'’”]+\$'), '');
  if (trimmed.isEmpty) {
    return null;
  }
  final code = trimmed.runes.last;
  if (code >= 0xAC00 && code <= 0xD7A3) {
    final jong = (code - 0xAC00) % 28;
    return (hasFinal: jong != 0, rieul: jong == 8);
  }
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
