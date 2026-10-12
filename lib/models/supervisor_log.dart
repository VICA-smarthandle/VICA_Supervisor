// 이 파일은 앱 내부 알림과 ROS 이벤트 로그 데이터를 표현합니다.
import '../core/log_filter.dart';

class SupervisorLog {
  const SupervisorLog({
    required this.filter,
    required this.message,
    required this.createdAt,
  });

  final LogFilter filter;
  final String message;
  final DateTime createdAt;
}
