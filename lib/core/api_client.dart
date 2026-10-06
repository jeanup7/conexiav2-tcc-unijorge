import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  const ApiException(this.message, [this.status = 0]);
  final String message;
  final int status;
  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({http.Client? client, String? baseUrl})
      : client = client ?? http.Client(),
        baseUrl = baseUrl ?? const String.fromEnvironment('API_URL', defaultValue: 'http://127.0.0.1:8080');
  final http.Client client;
  final String baseUrl;
  String? accessToken;
  Future<bool> Function()? renewSession;
  Future<Map<String, dynamic>> request(String method, String path,
      [Map<String, dynamic>? data, bool retry = true]) async {
    final uri = Uri.parse('$baseUrl$path');
    if (uri.scheme != 'https' && !(uri.scheme == 'http' && const {'localhost', '127.0.0.1', '10.0.2.2'}.contains(uri.host))) {
      throw const ApiException('A conexão com o servidor deve usar HTTPS.');
    }
    try {
      final req = http.Request(method, uri);
      req.headers['Content-Type'] = 'application/json';
      if (accessToken != null) req.headers['Authorization'] = 'Bearer $accessToken';
      if (data != null) req.body = jsonEncode(data);
      final response = await client.send(req).then(http.Response.fromStream).timeout(const Duration(seconds: 20));
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 401 && retry && !path.startsWith('/auth/') && renewSession != null) {
        if (await renewSession!()) return request(method, path, data, false);
      }
      if (response.statusCode >= 400) {
        throw ApiException((decoded['error'] as Map?)?['message'] as String? ?? 'Não foi possível concluir.', response.statusCode);
      }
      return decoded;
    } on ApiException { rethrow; }
    catch (_) { throw const ApiException('Não foi possível conectar. Verifique se a API está em execução.'); }
  }
  void close() => client.close();
}
