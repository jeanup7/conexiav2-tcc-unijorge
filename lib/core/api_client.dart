import 'dart:convert';
import 'dart:async';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';

class ApiException implements Exception {
  const ApiException(this.message, [this.status = 0, this.code]);
  final String message;
  final int status;
  final String? code;
  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({http.Client? client, String? baseUrl})
    : client = client ?? http.Client(),
      baseUrl =
          baseUrl ??
          const String.fromEnvironment(
            'API_URL',
            defaultValue: 'http://127.0.0.1:8080',
          );
  final http.Client client;
  final String baseUrl;
  String? accessToken;
  Future<bool> Function()? renewSession;
  Future<void> Function()? onUnauthorized;
  Future<void> Function()? onForbidden;
  int sessionVersion = 0;
  bool _closed = false;
  final _pendingMutations = <String, ({String key, DateTime created})>{};
  final _random = Random.secure();

  void invalidateSession() {
    sessionVersion++;
    accessToken = null;
    _pendingMutations.clear();
  }

  void checkSession(int version) {
    if (_closed || version != sessionVersion) {
      throw const ApiException('Operação cancelada porque a sessão mudou.');
    }
  }

  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? data,
    bool retry = true,
    String? operationKey,
  ]) async {
    final parts = Uri.parse(path).path
        .split('/')
        .where((p) => p.isNotEmpty)
        .toList();
    final creation =
        method == 'POST' &&
        (const {
              '/posts',
              '/stories',
              '/media',
              '/reports',
              '/family/discussions',
            }.contains(path) ||
            (parts.length == 2 && parts.first == 'messages') ||
            (parts.length == 4 &&
                parts[0] == 'guardian' &&
                parts[1] == 'children' &&
                parts[3] == 'discussions'));
    final fingerprint = creation
        ? sha256
              .convert(utf8.encode(jsonEncode([method, path, data])))
              .toString()
        : null;
    _pendingMutations.removeWhere(
      (_, value) =>
          DateTime.now().difference(value.created) > const Duration(hours: 23),
    );
    final key =
        operationKey ??
        (creation
            ? _pendingMutations[fingerprint]?.key ??
                  base64UrlEncode(
                    List.generate(24, (_) => _random.nextInt(256)),
                  ).replaceAll('=', '')
            : null);
    if (fingerprint != null) {
      if (_pendingMutations.length >= 16 &&
          !_pendingMutations.containsKey(fingerprint)) {
        _pendingMutations.remove(_pendingMutations.keys.first);
      }
      _pendingMutations[fingerprint] = (
        key: key!,
        created: _pendingMutations[fingerprint]?.created ?? DateTime.now(),
      );
    }
    try {
      final result = await _request(
        method,
        path,
        data,
        retry,
        sessionVersion,
        key,
        true,
      );
      if (fingerprint != null && _pendingMutations[fingerprint]?.key == key) {
        _pendingMutations.remove(fingerprint);
      }
      return result;
    } on ApiException catch (error) {
      if (fingerprint != null && error.status >= 400 && error.status < 500) {
        _pendingMutations.remove(fingerprint);
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path,
    Map<String, dynamic>? data,
    bool retry,
    int version,
    String? operationKey,
    bool networkRetry,
  ) async {
    checkSession(version);
    final uri = Uri.parse('$baseUrl$path');
    if (uri.scheme != 'https' &&
        !(uri.scheme == 'http' &&
            const {'localhost', '127.0.0.1', '10.0.2.2'}.contains(uri.host))) {
      throw const ApiException('A conexão com o servidor deve usar HTTPS.');
    }
    try {
      final req = http.Request(method, uri);
      req.headers['Content-Type'] = 'application/json';
      if (operationKey != null) req.headers['Idempotency-Key'] = operationKey;
      if (accessToken != null) {
        req.headers['Authorization'] = 'Bearer $accessToken';
      }
      if (data != null) req.body = jsonEncode(data);
      final response = await client
          .send(req)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 20));
      checkSession(version);
      Map<String, dynamic>? decoded;
      try {
        final value = response.body.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(response.body);
        if (value is Map<String, dynamic>) decoded = value;
      } on FormatException {
        /* HTTP status still governs authentication. */
      }
      final errorBody = decoded?['error'];
      final rawCode = errorBody is Map ? errorBody['code'] : null;
      final code = rawCode is String ? rawCode : null;
      final invalidSession =
          response.statusCode == 401 && code != 'reauthentication_required';
      if (invalidSession &&
          retry &&
          !path.startsWith('/auth/') &&
          renewSession != null) {
        if (await renewSession!()) {
          checkSession(version);
          return await _request(
            method,
            path,
            data,
            false,
            version,
            operationKey,
            networkRetry,
          );
        }
      }
      checkSession(version);
      if (invalidSession && !path.startsWith('/auth/')) {
        await onUnauthorized?.call();
      }
      if (response.statusCode == 403 &&
          path != '/me' &&
          !path.startsWith('/auth/')) {
        await onForbidden?.call();
      }
      if (response.statusCode >= 400) {
        final error = decoded?['error'];
        final message = error is Map ? error['message'] : null;
        throw ApiException(
          message is String
              ? message
              : 'Não foi possível concluir (HTTP ${response.statusCode}).',
          response.statusCode,
          code,
        );
      }
      if (decoded == null) {
        throw const ApiException('Resposta inválida do servidor.', 502);
      }
      return decoded;
    } on ApiException {
      rethrow;
    } on TimeoutException {
      if (operationKey != null && networkRetry) {
        return _request(
          method,
          path,
          data,
          retry,
          version,
          operationKey,
          false,
        );
      }
      throw const ApiException(
        'O servidor demorou para responder. Tente novamente.',
      );
    } on http.ClientException {
      if (operationKey != null && networkRetry) {
        return _request(
          method,
          path,
          data,
          retry,
          version,
          operationKey,
          false,
        );
      }
      throw const ApiException(
        'Não foi possível conectar ao servidor. Confira sua conexão.',
      );
    } catch (_) {
      throw const ApiException(
        'Não foi possível conectar. Verifique se a API está em execução.',
      );
    }
  }

  void close() {
    _closed = true;
    invalidateSession();
    client.close();
  }
}
