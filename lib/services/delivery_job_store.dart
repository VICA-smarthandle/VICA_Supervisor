// 이 파일은 배송 한 건을 기기 저장소에 남기고 되살리는 문입니다.
//
// 배송은 **앱의 기억**이라 앱이 꺼지면 사라졌습니다. 관리자가 앱을 껐다 켜거나
// 다른 앱에 갔다 와도 "지금 305호로 가는 중, 도착하면 이 번호로 문자"를 이어
// 받으려면(2026-09-03 사용자 결정) 그 기억을 밖에 적어 둬야 합니다. 설정과
// 같은 저장소(shared_preferences)를 씁니다 — 새 패키지가 필요 없습니다.
//
// 저장소를 문(interface) 뒤에 둔 이유는 시험입니다. 시험은 메모리 저장소로
// "껐다 켠 뒤"를 그대로 흉내 냅니다.
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
      // 깨진 저장분은 없는 것으로 칩니다. 되살리지 못한 배송은 관리자가
      // 화면에서 새로 시작하면 됩니다 — 여기서 앱이 멈추는 것이 더 나쁩니다.
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
    } catch (_) {
      // 저장 실패는 배송 흐름을 막지 않습니다. 다음 전이에서 다시 씁니다.
    }
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
