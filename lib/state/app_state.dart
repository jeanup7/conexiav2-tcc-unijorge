import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/api_client.dart';
import '../models/models.dart';
import '../repositories/social_repository.dart';

class AppState extends ChangeNotifier {
  AppState({ApiClient? api, FlutterSecureStorage? storage})
      : api = api ?? ApiClient(), storage = storage ?? const FlutterSecureStorage() {
    social = SocialRepository(this.api);
    this.api.renewSession = refresh;
  }
  final ApiClient api;
  final FlutterSecureStorage storage;
  late final SocialRepository social;
  Account? account;
  String? _refresh;
  Future<bool>? _refreshing;
  bool loading = true;
  String? error;
  Future<void> initialize() async {
    try {
      // On web keep credentials in memory; localStorage is not a secure vault.
      if (!kIsWeb) _refresh = await storage.read(key: 'conexia.refresh');
      if (_refresh != null) await refresh();
    } catch (_) { error = 'Não foi possível restaurar a sessão. Entre novamente.'; }
    loading = false;
    notifyListeners();
  }
  Future<void> _session(Map<String, dynamic> result) async {
    api.accessToken = result['accessToken'] as String;
    _refresh = result['refreshToken'] as String;
    if (!kIsWeb) await storage.write(key: 'conexia.refresh', value: _refresh);
    account = Account.fromJson(result['user'] as Map<String, dynamic>);
    notifyListeners();
  }
  Future<void> login(String email, String password) async {
    await _session(await api.request('POST', '/auth/login', {'email': email, 'password': password}));
  }
  Future<bool> refresh() => _refreshing ??= _renew().whenComplete(() => _refreshing = null);
  Future<bool> _renew() async {
    if (_refresh == null) return false;
    try {
      await _session(await api.request('POST', '/auth/refresh', {'refreshToken': _refresh}, false));
      return true;
    } on ApiException catch (e) {
      if (e.status == 401) await clearSession();
      return false;
    }
  }
  Future<void> reloadAccount() async {
    account = Account.fromJson(await api.request('GET', '/me'));
    notifyListeners();
  }
  Future<void> logout() async {
    // Do not pretend server revocation succeeded when offline.
    await api.request('POST', '/auth/logout');
    await clearSession();
  }
  Future<void> clearSession() async {
    account = null; api.accessToken = null; _refresh = null;
    if (!kIsWeb) await storage.delete(key: 'conexia.refresh');
    notifyListeners();
  }
  @override
  void dispose() { api.close(); super.dispose(); }
}
