import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:teste_app/core/api_client.dart';
import 'package:teste_app/screens/admin_screen.dart';
import 'package:teste_app/screens/denuncia_screen.dart';
import 'package:teste_app/screens/seguranca_screen.dart';
import 'package:teste_app/state/app_state.dart';

import 'admin_screen_test.dart' show account;
import 'audit_improvements_test.dart' show app, jsonResponse;

void main() {
  testWidgets(
    'reporter refreshes a protocol and reads the moderation decision',
    (tester) async {
      var reads = 0;
      final state = AppState(
        api: ApiClient(
          client: MockClient((request) async {
            expect(request.url.path, '/reports');
            reads++;
            return jsonResponse({
              'items': [
                {
                  'id': 'protocol',
                  'reason': 'Contato indesejado',
                  'status': reads == 1 ? 'pending' : 'removed',
                  if (reads > 1)
                    'decisionReason': 'Mensagem analisada pela equipe.',
                  if (reads > 1) 'decidedAt': 1795000000,
                },
              ],
            });
          }),
        ),
      )..account = account(false);
      addTearDown(state.dispose);
      await tester.pumpWidget(app(state, const ReportsScreen()));
      await tester.pumpAndSettle();
      expect(find.textContaining('Aguardando análise'), findsOneWidget);
      await tester.tap(find.byTooltip('Atualizar denúncias'));
      await tester.pumpAndSettle();
      expect(reads, 2);
      expect(find.textContaining('Conteúdo removido'), findsOneWidget);
      expect(
        find.textContaining('Mensagem analisada pela equipe.'),
        findsOneWidget,
      );
      expect(find.textContaining('Decisão em:'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('report submits structured category for selected message', (
    tester,
  ) async {
    var submissions = 0;
    final state = AppState(
      api: ApiClient(
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/reports');
          final body = jsonDecode(request.body) as Map;
          expect(body['target'], 'message-id');
          expect(body['category'], 'threat');
          expect(body['notifyGuardian'], false);
          submissions++;
          return jsonResponse({'id': 'protocol-id', 'status': 'pending'});
        }),
      ),
    )..account = account(false);
    addTearDown(state.dispose);
    await tester.pumpWidget(
      app(state, const DenunciaScreen(target: 'message-id')),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Ameaça ou violência'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Ameaça ou violência'));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Registrar denúncia'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Registrar denúncia'));
    await tester.pumpAndSettle();
    expect(submissions, 1);
    expect(find.textContaining('Protocolo: protocol-id'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'account suspension requires a reason and explicit confirmation',
    (tester) async {
      var changes = 0;
      final state = AppState(
        api: ApiClient(
          client: MockClient((request) async {
            if (request.method == 'PATCH') {
              expect(request.url.path, '/admin/users/u');
              expect(jsonDecode(request.body), {
                'status': 'suspended',
                'reason': 'Revisão de segurança',
              });
              changes++;
              return jsonResponse({'ok': true});
            }
            return jsonResponse({
              'items': [
                {
                  'id': 'u',
                  'name': 'Conta de teste',
                  'email': 'u@example.com',
                  'status': changes == 0 ? 'active' : 'suspended',
                  'verified': 1,
                  'isAdmin': 0,
                },
              ],
            });
          }),
        ),
      )..account = account(true);
      addTearDown(state.dispose);
      await tester.pumpWidget(app(state, const AdminUsersScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Suspender conta'));
      await tester.pumpAndSettle();
      expect(changes, 0);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Confirmar'),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField), 'Revisão de segurança');
      await tester.pump();
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      expect(changes, 1);
      expect(find.byTooltip('Reativar conta'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
