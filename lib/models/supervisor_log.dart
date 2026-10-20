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
