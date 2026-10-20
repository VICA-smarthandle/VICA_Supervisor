import 'package:flutter/foundation.dart';

import '../core/app_mode.dart';

class AppModeProvider extends ChangeNotifier {
  AppMode? _mode;

  /// null 이면 아직 고르지 않은 상태이고 모드 선택 화면을 보여줍니다.
  AppMode? get mode => _mode;

  bool get isSelected => _mode != null;

  void select(AppMode next) {
    if (_mode == next) {
      return;
    }
    _mode = next;
    notifyListeners();
  }

  /// 모드 선택 화면으로 돌아갑니다. 전환해도 되는 상태인지는 호출하는 쪽이 판정합니다
  void clear() {
    if (_mode == null) {
      return;
    }
    _mode = null;
    notifyListeners();
  }
}
