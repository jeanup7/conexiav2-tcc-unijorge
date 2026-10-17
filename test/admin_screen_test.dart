import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:teste_app/core/api_client.dart';
import 'package:teste_app/models/models.dart';
import 'package:teste_app/screens/admin_screen.dart';
import 'package:teste_app/state/app_state.dart';
import 'package:teste_app/widgets/common.dart';

Account account(bool admin) => Account(
  id: 'a',
  name: 'Admin',
  email: 'a@example.com',
  bio: '',
  verified: true,
  approved: true,
  needsGuardian: false,
  private: true,
  messages: true,
  isAdmin: admin,
);

void main() {
  testWidgets('ordinary account cannot fetch administration', (tester) async {
    final state = AppState(
      api: ApiClient(
        client: MockClient((_) async {
          fail('Ordinary account must not request admin data');
        }),
      ),
    )..account = account(false);
    addTearDown(state.dispose);
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: const MaterialApp(home: AdminScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Acesso restrito à administração.'), findsOneWidget);
  });

  testWidgets('admin moderation requires confirmation and refreshes queue', (
    tester,
  ) async {
    var decisions = 0;
    final state = AppState(
      api: ApiClient(
        client: MockClient((request) async {
          Object response;
          if (request.url.path == '/admin/summary') {
            response = {
              'users': 4,
              'posts': 3,
              'familyLinks': 1,
              'pendingReports': decisions == 0 ? 1 : 0,
            };
          } else if (request.method == 'PATCH') {
            expect(request.url.path, '/admin/reports/r');
            expect(jsonDecode(request.body), {'action': 'dismiss'});
            decisions++;
            response = {'ok': true};
          } else {
            response = {
              'items': decisions == 0
                  ? [
                      {
                        'id': 'r',
                        'reason': 'Denúncia de teste',
                        'content': 'Post de teste',
                        'status': 'pending',
                        'targetType': 'post',
                      },
                    ]
                  : [],
            };
          }
          return http.Response(
            jsonEncode(response),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    )..account = account(true);
    addTearDown(state.dispose);
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: const MaterialApp(home: AdminScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Denúncia de teste'), findsOneWidget);
    await tester.tap(find.text('Arquivar'));
    await tester.pumpAndSettle();
    expect(decisions, 0);
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    expect(decisions, 1);
    expect(find.text('Nenhuma denúncia registrada.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
