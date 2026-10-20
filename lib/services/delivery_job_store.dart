import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/delivery_job.dart';

abstract class DeliveryJobStore {
  Future<DeliveryJob?> load();

  /// null 이면 지웁니다.
  Future<void> save(DeliveryJob? job);
}

class SharedPreferencesDeliveryJobStore implements DeliveryJobStore {
  const SharedPreferencesDeliveryJobStore();

  static const _key = 'delivery_job';

  @override
  Future<DeliveryJob?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) {
        return null;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      return DeliveryJob.fromJson(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(DeliveryJob? job) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (job == null) {
        await prefs.remove(_key);
      } else {
        await prefs.setString(_key, jsonEncode(job.toJson()));
      }
    } catch (_) {}
  }
}

/// 시험용. 앱을 껐다 켠 상황을 "같은 저장소를 새 provider 에 넘기기"로 흉내 냅니다.
class MemoryDeliveryJobStore implements DeliveryJobStore {
  MemoryDeliveryJobStore([this.job]);

  DeliveryJob? job;
  int saves = 0;

  @override
  Future<DeliveryJob?> load() async => job;

  @override
  Future<void> save(DeliveryJob? job) async {
    this.job = job;
    saves += 1;
  }
}
