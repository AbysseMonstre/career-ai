import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import '../models/models.dart';

/// Holds auth session and exposes the shared [ApiService].
class AppState extends ChangeNotifier {
  final ApiService api;
  AppUser? user;
  bool loading = true;
  bool onboarded = true;

  AppState({String? apiBaseUrl}) : api = ApiService(baseUrl: apiBaseUrl) {
    // When the server rejects a stored token, log out so the UI returns to the
    // auth screen instead of showing "invalid or expired token" on every action.
    api.onUnauthorized = () {
      if (user != null) logout();
    };
  }

  bool get isLoggedIn => user != null;

  Future<void> completeOnboarding() async {
    onboarded = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarded', true);
    notifyListeners();
  }

  Future<void> bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    onboarded = prefs.getBool('onboarded') ?? false;
    final token = prefs.getString('token');
    final id = prefs.getInt('uid');
    final email = prefs.getString('email');
    final name = prefs.getString('name');
    final role = prefs.getString('role');
    if (token != null && id != null && role != null) {
      api.setToken(token);
      user = AppUser(id: id, email: email ?? '', name: name ?? '', role: role);
    }
    loading = false;
    notifyListeners();
  }

  Future<void> _persist(String token, AppUser u) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
    await prefs.setInt('uid', u.id);
    await prefs.setString('email', u.email);
    await prefs.setString('name', u.name);
    await prefs.setString('role', u.role);
  }

  Future<void> login(String email, String password) async {
    final res = await api.login(email, password);
    api.setToken(res.token);
    user = res.user;
    await _persist(res.token, res.user);
    notifyListeners();
  }

  Future<void> register(String email, String password, String name, String role,
      {bool consent = false}) async {
    final res = await api.register(email, password, name, role, consent: consent);
    api.setToken(res.token);
    user = res.user;
    await _persist(res.token, res.user);
    notifyListeners();
  }

  Future<void> deleteAccount() async {
    await api.deleteAccount();
    await logout();
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    // Clear auth keys only — keep 'onboarded' so we don't replay the intro.
    for (final k in ['token', 'uid', 'email', 'name', 'role']) {
      await prefs.remove(k);
    }
    api.setToken(null);
    user = null;
    notifyListeners();
  }
}
