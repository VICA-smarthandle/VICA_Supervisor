import '../core/log_filter.dart';

class SupervisorLog {
  const SupervisorLog({
    required this.id,
    required this.filter,
    required this.message,
    required this.createdAt,
  });

  final String id;
  final LogFilter filter;
  final String message;
  final DateTime createdAt;
}
