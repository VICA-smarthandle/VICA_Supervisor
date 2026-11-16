// 이 파일은 지금 어느 모드에 들어와 있는지를 앱 전체에 알립니다.
//
// SharedPreferences 에 저장하지 않습니다. app_mode.dart 의 주석과 같은 이유입니다.
import 'package:flutter/foundation.dart';

import '../core/app_mode.dart';

class AppModeProvider extends ChangeNotifier {
  AppMode? _mode;
  DriveSubmode _driveSubmode = DriveSubmode.guideDelivery;
  String? _landingTab;

  /// null 이면 아직 고르지 않은 상태이고 모드 선택 화면을 보여줍니다.
  AppMode? get mode => _mode;

  bool get isSelected => _mode != null;

  /// 주행 모드에서 고른 일. 다음에 주행을 고를 때까지 유지합니다.
  DriveSubmode get driveSubmode => _driveSubmode;

  /// 주행 화면에 들어가며 처음 열 탭 제목('경비', '원격 주행' …). null 이면 대시보드.
  /// 주행 화면이 한 번 읽고 [takeLandingTab] 으로 비웁니다.
  String? get landingTab => _landingTab;

  void select(AppMode next) {
    if (_mode == next) {
      return;
    }
    _mode = next;
    notifyListeners();
  }

  /// 주행 모드로 들어갑니다. [landingTab] 이 없으면 하위 모드가 정한 탭을 엽니다.
  void enterDrive(DriveSubmode submode, {String? landingTab}) {
    _driveSubmode = submode;
    _landingTab =
        landingTab ?? (submode == DriveSubmode.patrol ? '경비' : null);
    _mode = AppMode.drive;
    notifyListeners();
  }

  /// 처음 열 탭을 한 번만 쓰도록 꺼내고 비웁니다(알림 없이 — 그리는 중에 부릅니다).
  String? takeLandingTab() {
    final tab = _landingTab;
    _landingTab = null;
    return tab;
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
