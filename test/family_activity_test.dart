import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:teste_app/core/api_client.dart';
import 'package:teste_app/state/app_state.dart';
import 'package:teste_app/screens/family_activity_screen.dart';
import 'package:teste_app/widgets/common.dart';

void main() {
  for (final parent in [true, false]) {
    testWidgets(
      'Family summary, history and discussion for ${parent ? 'guardian' : 'child'}',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        bool resolved = false;
        final state = AppState(
          api: ApiClient(
            client: MockClient((r) async {
              if (r.method == 'PATCH') {
                expect(r.url.path, '/family/discussions/topic');
                expect(jsonDecode(r.body)['state'], 'resolved');
                resolved = true;
                return http.Response('{}', 200);
              }
              expect(
                r.url.path,
                parent
                    ? '/guardian/children/child/activity'
                    : '/family/activity',
              );
              expect(r.url.queryParameters['days'], '7');
              return http.Response(
                jsonEncode({
                  'child': {'id': 'child', 'name': 'Ninja'},
                  'total': 1,
                  'notice': 'Ver não significa gostar.',
                  'categories': [
                    {'id': 'anime', 'name': 'Animes', 'count': 1},
                  ],
                  'history': [
                    {
                      'id': 'view',
                      'seenAt': 1700000000,
                      'category': 'anime',
                      'post': null,
                    },
                  ],
                  'discussions': [
                    {
                      'id': 'topic',
                      'requestedBy': 'child',
                      'state': resolved ? 'resolved' : 'open',
                      'post': null,
                    },
                  ],
                }),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
            }),
          ),
        );
        addTearDown(state.dispose);
        await tester.pumpWidget(
          AppScope(
            state: state,
            child: MaterialApp(
              home: FamilyActivityScreen(
                childId: parent ? 'child' : null,
                childName: 'Ninja',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Animes • 1'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Posts'));
        await tester.tap(find.text('Posts'));
        await tester.pumpAndSettle();
        expect(find.text('Publicação indisponível'), findsOneWidget);
        await tester.tap(find.text('Conversar'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Marcar como conversamos'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Marcar como conversamos'));
        await tester.pumpAndSettle();
        expect(resolved, true);
        await tester.scrollUntilVisible(find.text('Reabrir conversa'), 200);
        await tester.pumpAndSettle();
        expect(find.text('Reabrir conversa'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
