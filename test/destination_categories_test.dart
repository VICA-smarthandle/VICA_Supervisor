import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/core/destination_categories.dart';

void main() {
  test('모든 상위 카테고리는 하나 이상의 세부 카테고리를 가진다', () {
    expect(destinationCategories, isNotEmpty);
    for (final category in destinationCategories) {
      expect(category.subcategories, isNotEmpty, reason: category.value);
      expect(
        category.subcategories.map((item) => item.value).toSet().length,
        category.subcategories.length,
        reason: '${category.value} 세부 값은 중복되면 안 됩니다.',
      );
    }
  });

  test('상위 분류에 맞는 세부 분류 이름을 찾는다', () {
    expect(destinationCategoryLabel('facility'), '시설 공간');
    expect(
      destinationSubcategoryLabel('facility', 'restroom'),
      '화장실',
    );
  });
}
