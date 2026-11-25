import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:teste_app/core/api_client.dart';
import 'package:teste_app/models/models.dart';
import 'package:teste_app/repositories/school_repository.dart';
import 'package:teste_app/screens/school_screen.dart';
import 'package:teste_app/state/app_state.dart';
import 'package:teste_app/theme/app_theme.dart';
import 'package:teste_app/widgets/common.dart';

const profile = {
  'id': 'parent',
  'name': 'Responsável',
  'email': 'p@example.com',
  'verified': 1,
  'approved': 1,
  'needsGuardian': false,
  'private': 1,
  'messages': 0,
};

AppState stateFor(Future<http.Response> Function(http.Request) respond) {
  final state =
      AppState(
          api: ApiClient(
            client: MockClient((request) async {
              if (request.url.path == '/me') {
                return http.Response(jsonEncode(profile), 200);
              }
              return respond(request);
            }),
          ),
        )
        ..account = Account.fromJson(profile)
        ..loading = false;
  return state;
}

Future<void> mount(WidgetTester tester, AppState state, Widget screen) async {
  await tester.pumpWidget(
    AppScope(
      state: state,
      child: MaterialApp(theme: conexiaTheme(), home: screen),
    ),
  );
  await tester.pumpAndSettle();
}

http.Response json(Object value, [int status = 200]) =>
    http.Response(jsonEncode(value), status);

void main() {
  testWidgets(
    'guardian invitation requires contact selection and explicit consent',
    (tester) async {
      SchoolData? sent;
      final state = stateFor((request) async {
        final path = request.url.path;
        if (path.endsWith('/privacy')) {
          return json({'mode': 'guardian_only', 'consentVersion': 'school-v1'});
        }
        if (path.endsWith('/audit')) return json({'items': []});
        if (path == '/school/tutor-candidates') {
          return json({
            'items': [
              {'id': 'tutor', 'name': 'Marcos'},
            ],
          });
        }
        if (request.method == 'POST') {
          sent = jsonDecode(request.body) as SchoolData;
          return json({'id': 'invite', 'state': 'pending'});
        }
        return json({'items': []});
      });
      addTearDown(state.dispose);
      await mount(
        tester,
        state,
        const SchoolFamilyScreen(childId: 'child', childName: 'Aluno'),
      );
      await tester.ensureVisible(find.text('Convidar tutor'));
      await tester.tap(find.text('Convidar tutor'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Enviar convite'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Marcos').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Enviar convite'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enviar convite'));
      await tester.pumpAndSettle();
      expect(sent, {
        'tutorId': 'tutor',
        'scope': 'summary',
        'consent': true,
        'consentVersion': 'school-v1',
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'minor sees access transparency without permission to change or invite',
    (tester) async {
      final methods = <String>[];
      final state = stateFor((request) async {
        methods.add(request.method);
        if (request.url.path.endsWith('/privacy')) {
          return json({'mode': 'shared', 'consentVersion': 'school-v1'});
        }
        if (request.url.path.endsWith('/audit')) {
          return json({
            'items': [
              {'event': 'activity.read', 'created': 1},
            ],
          });
        }
        return json({
          'items': [
            {'id': 'i', 'name': 'Tutor', 'state': 'active', 'scope': 'summary'},
          ],
        });
      });
      addTearDown(state.dispose);
      await mount(
        tester,
        state,
        const SchoolFamilyScreen(
          childId: 'child',
          childName: 'Aluno',
          readOnly: true,
        ),
      );
      expect(find.text('Convidar tutor'), findsNothing);
      expect(find.text('Revogar acesso'), findsNothing);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(find.text('Tutor'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Tutor consultou a atividade'),
        200,
      );
      expect(methods.every((m) => m == 'GET'), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'revoking a tutor requires confirmation and refreshes server state',
    (tester) async {
      var revoked = false;
      final state = stateFor((request) async {
        if (request.method == 'DELETE') {
          expect(request.url.path, '/school/children/child/tutors/i');
          revoked = true;
          return json({'state': 'revoked'});
        }
        if (request.url.path.endsWith('/privacy')) {
          return json({'mode': 'shared', 'consentVersion': 'school-v1'});
        }
        if (request.url.path.endsWith('/audit')) return json({'items': []});
        return json({
          'items': [
            {
              'id': 'i',
              'name': 'Tutor',
              'state': revoked ? 'revoked' : 'active',
              'scope': 'summary',
            },
          ],
        });
      });
      addTearDown(state.dispose);
      await mount(
        tester,
        state,
        const SchoolFamilyScreen(childId: 'child', childName: 'Aluno'),
      );
      await tester.scrollUntilVisible(find.text('Revogar acesso'), 220);
      await tester.ensureVisible(find.text('Revogar acesso'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Revogar acesso'));
      await tester.pumpAndSettle();
      expect(revoked, isFalse);
      await tester.tap(find.text('Revogar'));
      await tester.pumpAndSettle();
      expect(revoked, isTrue);
      expect(find.textContaining('Revogado'), findsOneWidget);
      expect(find.text('Revogar acesso'), findsNothing);
    },
  );

  testWidgets(
    'tutor accepts invitation then opens a restricted activity view',
    (tester) async {
      var accepted = false;
      final state = stateFor((request) async {
        if (request.method == 'POST') {
          expect(jsonDecode(request.body), {'accept': true});
          accepted = true;
          return json({'state': 'active'});
        }
        if (request.url.path == '/school/invitations') {
          return json({
            'items': accepted
                ? []
                : [
                    {
                      'id': 'i',
                      'guardian': 'Família',
                      'scope': 'summary',
                      'expires': 10000000,
                    },
                  ],
          });
        }
        if (request.url.path == '/school/students') {
          return json({
            'items': accepted
                ? [
                    {'id': 'c', 'name': 'Aluno', 'scope': 'summary'},
                  ]
                : [],
          });
        }
        return json({
          'child': {'id': 'c', 'name': 'Aluno'},
          'scope': 'summary',
          'categories': [
            {'category': 'education', 'count': 2},
          ],
          'total': 2,
          'notice': 'Somente categorias autorizadas.',
        });
      });
      addTearDown(state.dispose);
      await mount(tester, state, const SchoolHubScreen());
      await tester.tap(find.text('Aceitar'));
      await tester.pumpAndSettle();
      expect(accepted, isFalse);
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Aluno'));
      await tester.tap(find.text('Aluno'));
      await tester.pumpAndSettle();
      expect(find.text('2 registros no período'), findsOneWidget);
      expect(find.text('Registros recentes'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'revoked access removes previously loaded activity and permits retry',
    (tester) async {
      var allowed = true;
      final state = stateFor((request) async {
        if (!allowed) {
          return json({
            'error': {'message': 'Acompanhamento escolar não autorizado.'},
          }, 403);
        }
        return json({
          'child': {'id': 'c', 'name': 'Aluno privado'},
          'scope': 'summary',
          'categories': [],
          'total': 4,
          'notice': 'Aviso',
        });
      });
      addTearDown(state.dispose);
      await mount(tester, state, const SchoolActivityScreen(childId: 'c'));
      expect(find.text('Aluno privado'), findsOneWidget);
      allowed = false;
      await tester.tap(find.byTooltip('Atualizar acompanhamento'));
      await tester.pumpAndSettle();
      expect(find.text('Aluno privado'), findsNothing);
      expect(find.text('4 registros no período'), findsNothing);
      expect(find.text('Tentar novamente'), findsOneWidget);
      allowed = true;
      await tester.tap(find.text('Tentar novamente'));
      await tester.pumpAndSettle();
      expect(find.text('Aluno privado'), findsOneWidget);
    },
  );

  testWidgets(
    'school empty state and invitation remain usable with large text',
    (tester) async {
      tester.view.physicalSize = const Size(380, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = stateFor(
        (request) async => request.url.path.endsWith('/privacy')
            ? json({'mode': 'guardian_only', 'consentVersion': 'school-v1'})
            : json({'items': []}),
      );
      addTearDown(state.dispose);
      await tester.pumpWidget(
        AppScope(
          state: state,
          child: MaterialApp(
            theme: conexiaTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
            home: const SchoolFamilyScreen(childId: 'c', childName: 'Aluno'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Convidar tutor'), 180);
      await tester.tap(find.text('Convidar tutor'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Você ainda não tem contatos adultos'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
