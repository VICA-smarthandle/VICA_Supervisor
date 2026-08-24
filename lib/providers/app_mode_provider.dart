// 이 파일은 지금 어느 모드에 들어와 있는지를 앱 전체에 알립니다.
//
// SharedPreferences 에 저장하지 않습니다. app_mode.dart 의 주석과 같은 이유입니다.
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
  /// — 판정 근거(StackStatus, 주행 여부 등)가 SupervisorProvider 에 있기 때문입니다.
  void clear() {
    if (_mode == null) {
      return;
    }
    _mode = null;
    notifyListeners();
  }
}
