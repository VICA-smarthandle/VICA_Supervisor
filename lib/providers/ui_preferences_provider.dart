import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UiPreferencesProvider extends ChangeNotifier {
  static const _sidebarExpandedKey = 'vica_sidebar_expanded';

  bool _sidebarExpanded = true;

  bool get sidebarExpanded => _sidebarExpanded;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _sidebarExpanded = prefs.getBool(_sidebarExpandedKey) ?? true;
  }

  Future<void> toggleSidebar() async {
    _sidebarExpanded = !_sidebarExpanded;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_sidebarExpandedKey, _sidebarExpanded);
  }
}
