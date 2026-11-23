enum LogFilter {
  all('전체'),
  emergencyStop('비상정지'),
  coordinateTransfer('지도 설정'),
  connection('연결 상태'),
  delivery('물류 배송'),
  patrol('경비 기록');

  const LogFilter(this.label);

  final String label;
}
