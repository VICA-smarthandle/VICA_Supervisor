import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/auth_config.dart';

class AuthProvider extends ChangeNotifier {
  static const _loginStateKey = 'vica_supervisor_is_logged_in';

  bool _isLoggedIn = false;

  bool get isLoggedIn => _isLoggedIn;
  String? get currentUsername => _isLoggedIn ? AuthConfig.adminUsername : null;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _isLoggedIn = prefs.getBool(_loginStateKey) ?? false;
  }

  Future<bool> login({
    required String username,
    required String password,
  }) async {
    final isValid = username == AuthConfig.adminUsername &&
        password == AuthConfig.adminPassword;
    if (!isValid) {
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_loginStateKey, true);
    _isLoggedIn = true;
    notifyListeners();
    return true;
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_loginStateKey);
    _isLoggedIn = false;
    notifyListeners();
  }
}
