import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:teste_app/core/api_client.dart';
import 'package:teste_app/models/models.dart';
import 'package:teste_app/repositories/child_registration.dart';
import 'package:teste_app/state/app_state.dart';
import 'package:teste_app/screens/inicio_screen.dart';
import 'package:teste_app/widgets/common.dart';
import 'package:teste_app/theme/app_theme.dart';

class FakeChildRegistration implements ChildRegistration {
  int calls = 0;
  Completer<bool>? pending;
  @override
  Future<bool> create(
    String email,
    String password,
    Future<void> Function(String) save,
  ) async {
    calls++;
    await save('child-token');
    return pending == null ? true : await pending!.future;
  }
}

void main() {
  test(
    'guardian session remains intact and child password never goes to API',
    () async {
      final api = ApiClient(
        client: MockClient((r) async {
          expect(r.headers['Authorization'], 'Bearer guardian-token');
          if (r.method == 'GET') {
            return http.Response(
              jsonEncode({
                'id': 'parent',
                'name': 'Parent',
                'email': 'parent@example.com',
                'verified': 1,
                'approved': 1,
                'needsGuardian': false,
                'private': 1,
                'messages': 1,
              }),
              200,
            );
          }
          final body = jsonDecode(r.body) as Map;
          expect(body['childToken'], 'child-token');
          expect(body.containsKey('password'), false);
          expect(body['consent'], true);
          return http.Response('{}', 200);
        }),
      );
      api.accessToken = 'guardian-token';
      final state = AppState(
        api: api,
        childRegistration: FakeChildRegistration(),
      );
      addTearDown(state.dispose);
      expect(
        await state.createChild({
          'name': 'Child',
          'email': 'child@example.com',
          'password': 'secret child password',
          'birth': '2015-01-01',
        }),
        true,
      );
      expect(api.accessToken, 'guardian-token');
    },
  );
  test(
    'unverified, suspended and child accounts cannot start a child identity',
    () async {
      for (final flags in [
        {'verified': 0},
        {'accountStatus': 'suspended'},
        {'needsGuardian': true},
      ]) {
        final registration = FakeChildRegistration();
        final state = AppState(
          childRegistration: registration,
          api: ApiClient(
            client: MockClient((request) async {
              expect(request.method, 'GET');
              return http.Response(
                jsonEncode({
                  'id': 'p',
                  'name': 'Parent',
                  'email': 'p@example.com',
                  'verified': 1,
                  'approved': 1,
                  'private': 1,
                  'messages': 1,
                  'needsGuardian': false,
                  ...flags,
                }),
                200,
              );
            }),
          ),
        );
        await expectLater(
          state.createChild({
            'email': 'c@example.com',
            'password': 'a long password',
            'name': 'Child',
            'birth': '2015-01-01',
          }),
          throwsA(isA<ApiException>()),
        );
        expect(registration.calls, 0);
        state.dispose();
      }
    },
  );
  test('late child registration cannot succeed in another session', () async {
    final registration = FakeChildRegistration()..pending = Completer<bool>();
    final saved = Completer<void>();
    final api = ApiClient(
      client: MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'id': 'p',
              'name': 'Parent',
              'email': 'p@example.com',
              'verified': 1,
              'approved': 1,
              'private': 1,
              'messages': 1,
            }),
            200,
          );
        }
        saved.complete();
        return http.Response('{}', 200);
      }),
    );
    final state = AppState(api: api, childRegistration: registration);
    addTearDown(state.dispose);
    final operation = state.createChild({
      'email': 'c@example.com',
      'password': 'a long password',
      'name': 'Child',
      'birth': '2015-01-01',
    });
    final assertion = expectLater(operation, throwsA(isA<ApiException>()));
    await saved.future;
    await Future<void>.delayed(Duration.zero);
    api.invalidateSession();
    registration.pending!.complete(true);
    await assertion;
  });
  testWidgets('verified child selects nickname before feed becomes available', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState(
      api: ApiClient(
        client: MockClient((r) async {
          if (r.method == 'PATCH') {
            expect((jsonDecode(r.body) as Map)['name'], 'Ninja');
            return http.Response('{}', 200);
          }
          if (r.url.path == '/me') {
            return http.Response(
              jsonEncode({
                'id': 'child',
                'name': 'Ninja',
                'email': 'child@example.com',
                'bio': '',
                'verified': 1,
                'approved': 1,
                'needsGuardian': true,
                'needsNickname': false,
                'private': 1,
                'messages': 0,
              }),
              200,
            );
          }
          return http.Response('{"items":[],"nextCursor":null}', 200);
        }),
      ),
    );
    addTearDown(state.dispose);
    state.account = const Account(
      id: 'child',
      name: 'Novo perfil',
      email: 'child@example.com',
      bio: '',
      verified: true,
      approved: true,
      needsGuardian: true,
      needsNickname: true,
      private: true,
      messages: false,
    );
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(theme: conexiaTheme(), home: const InicioScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Como você quer aparecer no feed?'), findsOneWidget);
    expect(find.text('Entre ideias.'), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('nickname')), 'Ninja');
    await tester.tap(find.text('Salvar apelido e entrar no feed'));
    await tester.pumpAndSettle();
    expect(state.account!.name, 'Ninja');
    expect(state.account!.active, true);
    expect(find.text('Entre ideias.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
