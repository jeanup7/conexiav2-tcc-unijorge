import 'dart:async';

import '../repositories/child_registration.dart';
import '../repositories/firebase_auth_gateway.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/api_client.dart';
import '../models/models.dart';
import '../repositories/social_repository.dart';

class AppState extends ChangeNotifier {
  AppState({
    ApiClient? api,
    FlutterSecureStorage? storage,
    this.auth,
    this.childRegistration,
  }) : api = api ?? ApiClient(),
       storage = storage ?? const FlutterSecureStorage() {
    social = SocialRepository(this.api);
    this.api.renewSession = refresh;
    this.api.onUnauthorized = () async {
      final version = this.api.sessionVersion + 1;
      await clearSession();
      if (!_disposed && version == this.api.sessionVersion) {
        error = 'Sua sessão expirou. Entre novamente.';
        _notify();
      }
    };
    this.api.onForbidden = () async {
      try {
        await reloadAccount();
      } catch (_) {
        /* Original request displays its error. */
      }
    };
    final gateway = auth;
    if (gateway is AuthSessionEvents) {
      _identity = (gateway as AuthSessionEvents).identity;
      _authEvents = (gateway as AuthSessionEvents).identityChanges.listen((
        identity,
      ) {
        if (_disposed || _authenticating) return;
        if (account != null && identity != _identity) {
          unawaited(clearSession(signOut: false));
        }
        _identity = identity;
      });
    }
  }
  final AuthGateway? auth;
  final ChildRegistration? childRegistration;
  bool get usesFirebase => auth != null;
  final ApiClient api;
  final FlutterSecureStorage storage;
  late final SocialRepository social;
  Account? account;
  String? _refresh;
  Future<bool>? _refreshing;
  Future<void>? _initializing, _reloading;
  StreamSubscription<String?>? _authEvents;
  String? _identity;
  bool _disposed = false, _authenticating = false;
  Future<void> _authQueue = Future.value(), _storageQueue = Future.value();
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _check(int version) {
    if (_disposed) throw const ApiException('Operação cancelada.');
    api.checkSession(version);
  }

  Future<T> _auth<T>(int version, Future<T> Function() operation) {
    final pending = _authQueue.then((_) async {
      _check(version);
      return operation();
    });
    _authQueue = pending.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return pending;
  }

  Future<void> _persist(String? value, int version) {
    final pending = _storageQueue.then((_) async {
      if (kIsWeb || usesFirebase) return;
      if (value == null) {
        await storage.delete(key: 'conexia.refresh');
      } else {
        _check(version);
        await storage.write(key: 'conexia.refresh', value: value);
      }
    });
    _storageQueue = pending.catchError((Object _) {});
    return pending;
  }

  int _beginAuthentication() {
    if (_authenticating) {
      throw const ApiException('Aguarde a operação de acesso em andamento.');
    }
    _authenticating = true;
    api.invalidateSession();
    _refreshing = null;
    _reloading = null;
    account = null;
    _refresh = null;
    error = null;
    return api.sessionVersion;
  }

  void _rememberIdentity() {
    final gateway = auth;
    if (gateway is AuthSessionEvents) {
      _identity = (gateway as AuthSessionEvents).identity;
    }
  }

  bool loading = true;
  String? error;
  Future<void> initialize() => _initializing ??= _initialize();
  Future<void> _initialize() async {
    final version = api.sessionVersion;
    try {
      if (usesFirebase) {
        if (auth!.signedIn) {
          await _auth(version, () => auth!.reload());
          final access = await _auth(version, () => auth!.token(force: true));
          _check(version);
          api.accessToken = access;
          final profile = await api.request('GET', '/me');
          _check(version);
          account = Account.fromJson(profile);
          _rememberIdentity();
        }
      } else {
        // On web keep credentials in memory; localStorage is not a secure vault.
        if (!kIsWeb) {
          final saved = await storage.read(key: 'conexia.refresh');
          _check(version);
          _refresh = saved;
        }
        if (_refresh != null) await refresh();
      }
    } catch (_) {
      if (!_disposed && version == api.sessionVersion) {
        account = null;
        api.accessToken = null;
        error = 'Não foi possível restaurar a sessão. Entre novamente.';
      }
    }
    if (_disposed) return;
    loading = false;
    _notify();
  }

  Future<void> _session(Map<String, dynamic> result, int version) async {
    _check(version);
    api.accessToken = result['accessToken'] as String;
    _refresh = result['refreshToken'] as String;
    await _persist(_refresh, version);
    _check(version);
    account = Account.fromJson(result['user'] as Map<String, dynamic>);
    _notify();
  }

  Future<void> login(String email, String password) async {
    final version = _beginAuthentication();
    try {
      if (usesFirebase) {
        await _auth(version, () => auth!.login(email, password));
        final access = await _auth(version, () => auth!.token());
        _check(version);
        api.accessToken = access;
        try {
          final result = await api.request('POST', '/auth/firebase', {});
          _check(version);
          account = Account.fromJson(result['user'] as Map<String, dynamic>);
          _rememberIdentity();
          _notify();
        } catch (_) {
          if (!_disposed && version == api.sessionVersion) await clearSession();
          rethrow;
        }
        return;
      }
      await _session(
        await api.request('POST', '/auth/login', {
          'email': email,
          'password': password,
        }),
        version,
      );
    } catch (_) {
      if (!_disposed && version == api.sessionVersion) await clearSession();
      rethrow;
    } finally {
      if (!_disposed) _authenticating = false;
    }
  }

  Future<Map<String, dynamic>> register(Map<String, dynamic> data) async {
    final birth = DateTime.parse(data['birth'] as String);
    final now = DateTime.now();
    final years =
        now.year -
        birth.year -
        ((now.month < birth.month ||
                (now.month == birth.month && now.day < birth.day))
            ? 1
            : 0);
    if (years < 18) {
      throw const ApiException(
        'O responsável deve criar a conta do menor no painel da família.',
      );
    }
    if (!usesFirebase) return api.request('POST', '/auth/register', data);
    final version = _beginAuthentication();
    try {
      await _auth(
        version,
        () =>
            auth!.register(data['email'] as String, data['password'] as String),
      );
      final access = await _auth(version, () => auth!.token());
      _check(version);
      api.accessToken = access;
      final result = await api.request('POST', '/auth/firebase', {
        'name': data['name'],
        'birth': data['birth'],
        if (data['guardianEmail'] != null)
          'guardianEmail': data['guardianEmail'],
      });
      _check(version);
      account = Account.fromJson(result['user'] as Map<String, dynamic>);
      _rememberIdentity();
      _notify();
      // The verification screen sends the email explicitly and reports any failure.
      return result;
    } finally {
      if (!_disposed) _authenticating = false;
    }
  }

  Future<bool> createChild(Map<String, dynamic> data) async {
    final version = api.sessionVersion;
    if (childRegistration == null) {
      throw const ApiException('Cadastro Firebase de menores indisponível.');
    }
    return childRegistration!.create(
      data['email'] as String,
      data['password'] as String,
      (token) async {
        _check(version);
        await api.request('POST', '/guardian/children', {
          'childToken': token,
          'name': data['name'],
          'birth': data['birth'],
          'consent': true,
        });
      },
    );
  }

  Future<void> deleteAccount(String password) async {
    final version = api.sessionVersion;
    if (usesFirebase) {
      await _auth(version, () => auth!.reauthenticate(password));
      final access = await _auth(version, () => auth!.token(force: true));
      _check(version);
      api.accessToken = access;
    }
    await api.request(
      'DELETE',
      '/me',
      usesFirebase ? {} : {'password': password},
    );
    _check(version);
    await clearSession();
  }

  Future<bool> refresh() {
    final version = api.sessionVersion;
    return _refreshing ??= _renew().whenComplete(() {
      if (version == api.sessionVersion) _refreshing = null;
    });
  }

  Future<bool> _renew() async {
    final version = api.sessionVersion;
    if (usesFirebase) {
      try {
        final access = await _auth(version, () => auth!.token(force: true));
        _check(version);
        api.accessToken = access;
        return true;
      } catch (_) {
        return false;
      }
    }
    if (_refresh == null) return false;
    try {
      await _session(
        await api.request('POST', '/auth/refresh', {
          'refreshToken': _refresh,
        }, false),
        version,
      );
      return true;
    } on ApiException catch (e) {
      if (e.status == 401 && version == api.sessionVersion) {
        await clearSession();
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> reloadAccount() {
    final version = api.sessionVersion;
    return _reloading ??= _reloadAccount(version).whenComplete(() {
      if (version == api.sessionVersion) _reloading = null;
    });
  }

  Future<void> _reloadAccount(int version) async {
    if (usesFirebase) {
      try {
        await _auth(version, () => auth!.reload());
        final access = await _auth(version, () => auth!.token(force: true));
        _check(version);
        api.accessToken = access;
      } on ApiException catch (e) {
        if (e.status == 401 && version == api.sessionVersion) {
          await clearSession();
        }
        rethrow;
      }
    }
    final profile = await api.request('GET', '/me');
    _check(version);
    account = Account.fromJson(profile);
    _rememberIdentity();
    _notify();
  }

  Future<String?> logout() async {
    final version = api.sessionVersion;
    String? warning;
    try {
      // Firebase SDK signs out this device. Global revocation is a separate action.
      if (!usesFirebase) await api.request('POST', '/auth/logout');
    } catch (_) {
      warning = 'Você saiu deste dispositivo. Não foi possível confirmar o encerramento da sessão no servidor.';
    } finally {
      if (version == api.sessionVersion) await clearSession();
    }
    return warning ?? error;
  }

  Future<void> clearSession({bool signOut = true}) async {
    if (_disposed) return;
    api.invalidateSession();
    final version = api.sessionVersion;
    account = null;
    _refresh = null;
    _refreshing = null;
    _reloading = null;
    loading = false;
    error = null;
    _notify();
    try {
      if (usesFirebase && signOut) await _auth(version, () => auth!.signOut());
      await _persist(null, version);
    } catch (_) {
      if (!_disposed && version == api.sessionVersion) {
        error = 'O acesso local foi encerrado, mas não foi possível limpar a sessão salva. Tente sair novamente antes de fechar o aplicativo.';
        _notify();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _authEvents?.cancel();
    api.onUnauthorized = null;
    api.onForbidden = null;
    social.dispose();
    api.close();
    super.dispose();
  }
}
