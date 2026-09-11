enum LogFilter {
  all('전체'),
  emergencyStop('긴급 정지'),
  coordinateTransfer('좌표 전송'),
  connection('연결 상태');

  const LogFilter(this.label);

  final String label;
}
