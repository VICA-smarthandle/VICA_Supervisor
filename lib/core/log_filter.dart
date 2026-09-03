// 이 파일은 알림 및 로그 화면에서 사용하는 필터 종류를 정의합니다.
enum LogFilter {
  all('전체'),
  emergencyStop('긴급 정지'),
  coordinateTransfer('좌표 전송'),
  connection('연결 상태'),
  // 물류 배송의 출발·도착·문자 발송 결과. 발송 기록은 폰 문자함에 남지 않아
  // (기본 문자앱이 아니면 못 씀) 이 로그가 유일한 기록입니다. 번호는 안 적습니다.
  delivery('물류 배송');

  const LogFilter(this.label);

  final String label;
}
