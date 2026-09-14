// 연락처 모양 규칙을 고정합니다. ROS 쪽 storage.py normalize_contact_phone 과
// 같은 입력에 같은 답을 내야 합니다 — 한쪽만 통과시키면 관리자는 저장됐다고
// 믿는데 파일에는 없게 됩니다. (test_storage.py 의 표와 짝입니다.)
import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/core/contact_phone.dart';

void main() {
  group('normalizeContactPhone', () {
    test('하이픈·공백을 걷어내고 숫자만 남긴다', () {
      expect(normalizeContactPhone('010-1234-5678'), '01012345678');
      expect(normalizeContactPhone('010 1234 5678'), '01012345678');
      expect(normalizeContactPhone('01012345678'), '01012345678');
      expect(normalizeContactPhone('011-123-4567'), '0111234567');
    });

    test('빈 입력은 빈 값이다 — 연락처 없는 장소는 정상이다', () {
      expect(normalizeContactPhone(''), '');
      expect(normalizeContactPhone('   '), '');
    });

    test('휴대폰 번호가 아니면 null 로 거부한다', () {
      expect(normalizeContactPhone('02-123-4567'), isNull);
      expect(normalizeContactPhone('1234'), isNull);
      expect(normalizeContactPhone('0101234567890'), isNull);
      expect(normalizeContactPhone('abc'), isNull);
    });
  });

  test('formatContactPhone 은 편집용으로 하이픈을 붙인다', () {
    expect(formatContactPhone('01012345678'), '010-1234-5678');
    expect(formatContactPhone('0111234567'), '011-123-4567');
    expect(formatContactPhone(''), '');
  });

  test('maskContactPhone 은 가운데를 가린다', () {
    expect(maskContactPhone('01012345678'), '010-****-5678');
    expect(maskContactPhone(''), '');
    // 이상한 값은 통째로 가린다. 마스킹 함수가 개인정보를 흘리면 안 된다.
    expect(maskContactPhone('garbage'), '****');
  });
}
