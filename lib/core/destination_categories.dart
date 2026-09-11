class DestinationSubcategory {
  const DestinationSubcategory({required this.value, required this.label});

  final String value;
  final String label;
}

class DestinationCategory {
  const DestinationCategory({
    required this.value,
    required this.label,
    required this.subcategories,
  });

  final String value;
  final String label;
  final List<DestinationSubcategory> subcategories;
}

const destinationCategories = <DestinationCategory>[
  DestinationCategory(
    value: 'facility',
    label: '시설 공간',
    subcategories: [
      DestinationSubcategory(value: 'restroom', label: '화장실'),
      DestinationSubcategory(value: 'lobby', label: '로비'),
      DestinationSubcategory(value: 'entrance', label: '출입구'),
      DestinationSubcategory(value: 'elevator', label: '엘리베이터'),
      DestinationSubcategory(value: 'stairs', label: '계단'),
      DestinationSubcategory(value: 'auditorium', label: '대강당'),
      DestinationSubcategory(value: 'server_room', label: '서버실'),
      DestinationSubcategory(value: 'charging_station', label: '충전 위치'),
      DestinationSubcategory(value: 'waiting_area', label: '대기 위치'),
      DestinationSubcategory(value: 'emergency_exit', label: '비상구'),
      DestinationSubcategory(value: 'other', label: '기타 시설'),
    ],
  ),
  DestinationCategory(
    value: 'service',
    label: '안내·서비스 공간',
    subcategories: [
      DestinationSubcategory(value: 'information_center', label: '안내센터'),
      DestinationSubcategory(value: 'reception', label: '접수처'),
      DestinationSubcategory(value: 'admin_office', label: '행정실'),
      DestinationSubcategory(value: 'health_center', label: '보건실'),
      DestinationSubcategory(value: 'career_center', label: '취업지원센터'),
      DestinationSubcategory(value: 'library', label: '도서관'),
      DestinationSubcategory(value: 'customer_service', label: '고객지원센터'),
      DestinationSubcategory(value: 'other', label: '기타 서비스'),
    ],
  ),
  DestinationCategory(
    value: 'education',
    label: '교육 공간',
    subcategories: [
      DestinationSubcategory(value: 'classroom', label: '강의실'),
      DestinationSubcategory(value: 'lab', label: '연구실·실험실'),
      DestinationSubcategory(value: 'seminar_room', label: '세미나실'),
      DestinationSubcategory(value: 'lecture_hall', label: '대형 강의실'),
      DestinationSubcategory(value: 'reading_room', label: '열람실'),
      DestinationSubcategory(value: 'practice_room', label: '실습실'),
      DestinationSubcategory(value: 'study_room', label: '스터디룸'),
      DestinationSubcategory(value: 'other', label: '기타 교육 공간'),
    ],
  ),
  DestinationCategory(
    value: 'department',
    label: '부서·학과 공간',
    subcategories: [
      DestinationSubcategory(value: 'department_office', label: '학과 사무실'),
      DestinationSubcategory(value: 'division_office', label: '부서 사무실'),
      DestinationSubcategory(value: 'support_office', label: '행정지원실'),
      DestinationSubcategory(value: 'other', label: '기타 부서'),
    ],
  ),
  DestinationCategory(
    value: 'person',
    label: '인물·개인 공간',
    subcategories: [
      DestinationSubcategory(value: 'professor_office', label: '교수 사무실'),
      DestinationSubcategory(value: 'staff_office', label: '교직원 사무실'),
      DestinationSubcategory(value: 'researcher_office', label: '연구원 사무실'),
      DestinationSubcategory(value: 'counseling_office', label: '상담실'),
      DestinationSubcategory(value: 'private_lab', label: '개인 연구실'),
      DestinationSubcategory(value: 'other', label: '기타 개인 공간'),
    ],
  ),
  DestinationCategory(
    value: 'food',
    label: '식음료 공간',
    subcategories: [
      DestinationSubcategory(value: 'restaurant', label: '식당'),
      DestinationSubcategory(value: 'cafeteria', label: '학생식당·구내식당'),
      DestinationSubcategory(value: 'cafe', label: '카페'),
      DestinationSubcategory(value: 'convenience_store', label: '편의점'),
      DestinationSubcategory(value: 'snack_bar', label: '매점'),
      DestinationSubcategory(value: 'other', label: '기타 식음료'),
    ],
  ),
  DestinationCategory(
    value: 'other',
    label: '기타 공간',
    subcategories: [
      DestinationSubcategory(value: 'other', label: '기타 목적지'),
    ],
  ),
];

DestinationCategory? destinationCategoryByValue(String value) {
  for (final category in destinationCategories) {
    if (category.value == value) {
      return category;
    }
  }
  return null;
}

String destinationCategoryLabel(String value) {
  return destinationCategoryByValue(value)?.label ?? value;
}

String destinationSubcategoryLabel(String categoryValue, String value) {
  final category = destinationCategoryByValue(categoryValue);
  if (category == null) {
    return value;
  }
  for (final subcategory in category.subcategories) {
    if (subcategory.value == value) {
      return subcategory.label;
    }
  }
  return value;
}
