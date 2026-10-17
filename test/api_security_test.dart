import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:teste_app/core/api_client.dart';
import 'package:teste_app/models/models.dart';

void main() {
  test(
    'remote cleartext transport is rejected before sending credentials',
    () async {
      var sent = false;
      final api = ApiClient(
        baseUrl: 'http://example.com',
        client: MockClient((request) async {
          sent = true;
          return http.Response('{}', 200);
        }),
      );
      await expectLater(
        api.request('POST', '/auth/login', {'password': 'secret'}),
        throwsA(isA<ApiException>()),
      );
      expect(sent, false);
    },
  );
  test('expired access renews once and repeats with the new token', () async {
    var requests = 0, renewals = 0;
    final api = ApiClient(
      client: MockClient((request) async {
        requests++;
        if (requests == 1) {
          return http.Response('{"error":{"message":"expired"}}', 401);
        }
        expect(request.headers['Authorization'], 'Bearer new');
        return http.Response('{"id":"123"}', 200);
      }),
    );
    api.accessToken = 'old';
    api.renewSession = () async {
      renewals++;
      api.accessToken = 'new';
      return true;
    };
    expect((await api.request('GET', '/me'))['id'], '123');
    expect(requests, 2);
    expect(renewals, 1);
  });
  test('repeated unauthorized response cannot loop forever', () async {
    var renewals = 0;
    final api = ApiClient(
      client: MockClient(
        (_) async => http.Response('{"error":{"message":"expired"}}', 401),
      ),
    );
    api.renewSession = () async {
      renewals++;
      return true;
    };
    await expectLater(
      api.request('GET', '/me'),
      throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)),
    );
    expect(renewals, 1);
  });
  test('server error details are retained', () async {
    final api = ApiClient(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {'message': 'Contato não aprovado'},
          }),
          403,
        ),
      ),
    );
    await expectLater(
      api.request('POST', '/messages/x'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          'Contato não aprovado',
        ),
      ),
    );
  });
  test('minor activation requires independent guardian approval', () {
    final profile = <String, dynamic>{
      'id': '1',
      'name': 'Ana',
      'email': 'ana@example.com',
      'verified': 1,
      'approved': 0,
      'needsGuardian': true,
      'private': 1,
      'messages': 0,
    };
    expect(Account.fromJson(profile).active, false);
    profile['approved'] = 1;
    expect(Account.fromJson(profile).active, true);
    profile['verified'] = 0;
    expect(Account.fromJson(profile).active, false);
  });
}
