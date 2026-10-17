import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:teste_app/core/api_client.dart';
import 'package:teste_app/screens/contact_requests_screen.dart';
import 'package:teste_app/state/app_state.dart';

import 'audit_improvements_test.dart' show app, account, jsonResponse;

void main() {
  test(
    'connection failure retries a creation with the same operation key',
    () async {
      final keys = <String?>[];
      final api = ApiClient(
        client: MockClient((r) async {
          keys.add(r.headers['Idempotency-Key']);
          if (keys.length == 1) throw http.ClientException('lost response');
          return jsonResponse({'id': 'created-once'});
        }),
      );
      addTearDown(api.close);
      expect(
        (await api.request('POST', '/posts', {'text': 'one'}))['id'],
        'created-once',
      );
      expect(keys, hasLength(2));
      expect(keys.first, isNotNull);
      expect(keys.first, keys.last);
    },
  );

  test(
    'manual retry after two lost responses preserves operation identity',
    () async {
      final keys = <String?>[];
      final api = ApiClient(
        client: MockClient((r) async {
          keys.add(r.headers['Idempotency-Key']);
          if (keys.length <= 2) throw http.ClientException('lost response');
          return jsonResponse({'id': 'created-once'});
        }),
      );
      addTearDown(api.close);
      await expectLater(
        api.request('POST', '/messages/target', {'text': 'one'}),
        throwsA(isA<ApiException>()),
      );
      await api.request('POST', '/messages/target', {'text': 'one'});
      expect(keys.toSet(), hasLength(1));
      await api.request('POST', '/messages/target', {'text': 'one'});
      expect(keys.last, isNot(keys.first));
    },
  );

  test(
    'wrong deletion password does not renew or sign out the session',
    () async {
      int cleared = 0, renewed = 0;
      final api = ApiClient(
        client: MockClient(
          (r) async => http.Response(
            jsonEncode({
              'error': {
                'message': 'Senha incorreta',
                'code': 'reauthentication_required',
              },
            }),
            401,
          ),
        ),
      );
      addTearDown(api.close);
      api.onUnauthorized = () async {
        cleared++;
      };
      api.renewSession = () async {
        renewed++;
        return true;
      };
      await expectLater(
        api.request('DELETE', '/me', {'password': 'wrong'}),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'reauthentication_required',
          ),
        ),
      );
      expect(cleared, 0);
      expect(renewed, 0);
    },
  );

  test('failed unauthenticated login is never retried automatically', () async {
    int requests = 0;
    final api = ApiClient(
      client: MockClient((r) async {
        requests++;
        throw http.ClientException('offline');
      }),
    );
    addTearDown(api.close);
    await expectLater(
      api.request('POST', '/auth/login', {'password': 'secret'}),
      throwsA(isA<ApiException>()),
    );
    expect(requests, 1);
  });

  testWidgets(
    'recipient can accept a minor request while family consent remains pending',
    (tester) async {
      int accepts = 0;
      final state = AppState(
        api: ApiClient(
          client: MockClient((r) async {
            if (r.method == 'POST') {
              accepts++;
              expect(jsonDecode(r.body)['target'], 'minor');
              return jsonResponse({'status': 'awaiting_guardian'});
            }
            return jsonResponse({
              'items': [
                {
                  'id': 'minor',
                  'requestId': 'request',
                  'name': 'Ninja',
                  'incoming': true,
                  'accepted': accepts > 0,
                  'requiresGuardian': true,
                },
              ],
            });
          }),
        ),
      )..account = account;
      addTearDown(state.dispose);
      await tester.pumpWidget(app(state, const ContactRequestsScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aceitar pedido'));
      await tester.pumpAndSettle();
      expect(accepts, 1);
      expect(find.text('Aceitar pedido'), findsNothing);
      expect(find.textContaining('aguardando autorizações'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('guardian can approve and later withdraw a connection', (
    tester,
  ) async {
    final decisions = <bool>[];
    final state = AppState(
      api: ApiClient(
        client: MockClient((r) async {
          if (r.method == 'PATCH') {
            expect(r.url.path, '/guardian/children/minor/contacts/request');
            decisions.add(jsonDecode(r.body)['approved'] as bool);
            return jsonResponse({
              'status': decisions.last ? 'approved' : 'cancelled',
            });
          }
          return jsonResponse({
            'items': decisions.length == 2
                ? []
                : [
                    {
                      'id': 'request',
                      'name': 'Friend',
                      'incoming': true,
                      'accepted': true,
                      'approved': decisions.isNotEmpty,
                      'status': decisions.isEmpty ? 'pending' : 'approved',
                    },
                  ],
          });
        }),
      ),
    )..account = account;
    addTearDown(state.dispose);
    await tester.pumpWidget(
      app(
        state,
        const ContactRequestsScreen(childId: 'minor', childName: 'Ninja'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Autorizar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retirar autorização'));
    await tester.pumpAndSettle();
    expect(decisions, [true, false]);
    expect(find.text('Friend'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
