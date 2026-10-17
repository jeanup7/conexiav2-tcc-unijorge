import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:teste_app/core/api_client.dart';
import 'package:teste_app/repositories/firebase_auth_gateway.dart';
import 'package:teste_app/state/app_state.dart';

class FakeAuth implements AuthGateway {
  bool active = true;
  bool verified = false;
  int reloads = 0;
  bool reauthenticated = false;
  @override
  bool get signedIn => active;
  @override
  String get email => 'test@example.com';
  @override
  Future<void> register(String email, String password) async {
    active = true;
  }

  @override
  Future<void> login(String email, String password) async {
    active = true;
  }

  @override
  Future<String> token({bool force = false}) async =>
      verified ? 'verified-token' : 'pending-token';
  @override
  Future<void> reload() async {
    reloads++;
    verified = true;
  }

  @override
  Future<void> sendVerification() async {}
  @override
  Future<void> recover(String email) async {}
  @override
  Future<void> reauthenticate(String password) async {
    reauthenticated = true;
  }

  @override
  Future<void> signOut() async {
    active = false;
  }
}

Map<String, dynamic> profile(bool verified) => {
  'id': 'test',
  'name': 'Test',
  'email': 'test@example.com',
  'bio': '',
  'verified': verified ? 1 : 0,
  'approved': 0,
  'needsGuardian': false,
  'private': 1,
  'messages': 0,
};
void main() {
  test(
    'registration sends identity token and profile, never password to API',
    () async {
      final auth = FakeAuth();
      final state = AppState(
        auth: auth,
        api: ApiClient(
          client: MockClient((request) async {
            expect(request.url.path, '/auth/firebase');
            expect(request.headers['Authorization'], 'Bearer pending-token');
            final body = jsonDecode(request.body) as Map;
            expect(body.containsKey('password'), false);
            expect(body.containsKey('email_verified'), false);
            expect(body['birth'], '2000-01-01');
            return http.Response(jsonEncode({'user': profile(false)}), 200);
          }),
        ),
      );
      addTearDown(state.dispose);
      await state.register({
        'email': 'test@example.com',
        'password': 'secret long password',
        'name': 'Test',
        'birth': '2000-01-01',
      });
      expect(state.account!.verified, false);
    },
  );
  test(
    'already confirmed reloads Firebase and force refreshes token before API',
    () async {
      final auth = FakeAuth();
      final state = AppState(
        auth: auth,
        api: ApiClient(
          client: MockClient((request) async {
            expect(request.headers['Authorization'], 'Bearer verified-token');
            return http.Response(jsonEncode(profile(true)), 200);
          }),
        ),
      );
      addTearDown(state.dispose);
      await state.reloadAccount();
      expect(auth.reloads, 1);
      expect(state.account!.active, true);
    },
  );
  test(
    'deletion reauthenticates before deleting API profile and signs out',
    () async {
      final auth = FakeAuth();
      final state = AppState(
        auth: auth,
        api: ApiClient(
          client: MockClient((request) async {
            expect(auth.reauthenticated, true);
            expect(request.method, 'DELETE');
            expect(jsonDecode(request.body), isEmpty);
            return http.Response('{}', 200);
          }),
        ),
      );
      addTearDown(state.dispose);
      await state.deleteAccount('password');
      expect(auth.signedIn, false);
      expect(state.api.accessToken, isNull);
    },
  );
}
