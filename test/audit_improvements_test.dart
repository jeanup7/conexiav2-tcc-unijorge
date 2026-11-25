import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:teste_app/core/api_client.dart';
import 'package:teste_app/models/models.dart';
import 'package:teste_app/screens/inicio_screen.dart';
import 'package:teste_app/screens/social/messages_screen.dart';
import 'package:teste_app/state/app_state.dart';
import 'package:teste_app/theme/app_theme.dart';
import 'package:teste_app/widgets/common.dart';

import 'firebase_session_test.dart' show FakeAuth;

const account = Account(
  id: 'a',
  name: 'Adult',
  email: 'a@example.com',
  bio: '',
  verified: true,
  approved: true,
  needsGuardian: false,
  private: true,
  messages: true,
);
http.Response jsonResponse(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Widget app(AppState state, Widget screen) => AppScope(
  state: state,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: conexiaTheme(),
    home: screen,
  ),
);
Map<String, dynamic> message(String id, {bool incoming = false}) => {
  'id': id,
  'sender': incoming ? 'b' : 'a',
  'recipient': incoming ? 'a' : 'b',
  'text': id,
  'created': id == 'older' ? 1 : 2,
  'read': 0,
};
void main() {
  test(
    'feed keeps opaque cursor and accepts older numeric responses',
    () async {
      final state = AppState(
        api: ApiClient(
          client: MockClient((r) async {
            expect(r.url.queryParameters['cursor'], 'v1.cursor+with/chars');
            return jsonResponse({'items': [], 'nextCursor': 123});
          }),
        ),
      );
      addTearDown(state.dispose);
      final result = await state.social.feed(cursor: 'v1.cursor+with/chars');
      expect(result.cursor, '123');
    },
  );
  testWidgets('real tabs preserve feed and like does not reload it', (
    tester,
  ) async {
    int feeds = 0, stories = 0, likes = 0;
    final state = AppState(
      api: ApiClient(
        client: MockClient((r) async {
          if (r.url.path == '/posts') {
            feeds++;
            return jsonResponse({
              'items': [
                {
                  'id': 'post',
                  'user': 'a',
                  'text': 'Publicação preservada',
                  'author': {'name': 'Adult'},
                  'likes': 0,
                  'liked': false,
                },
              ],
              'nextCursor': null,
            });
          }
          if (r.url.path == '/stories') stories++;
          if (r.url.path == '/posts/post/like') {
            likes++;
            expect(jsonDecode(r.body)['liked'], true);
            return jsonResponse({'ok': true, 'liked': true, 'likes': 1});
          }
          return jsonResponse({'items': [], 'nextCursor': null});
        }),
      ),
    )..account = account;
    addTearDown(state.dispose);
    await tester.pumpWidget(app(state, const InicioScreen()));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Pesquisa'));
    await tester.tap(find.text('Pesquisa'));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Feed'));
    await tester.tap(find.text('Feed'));
    await tester.pumpAndSettle();
    expect(feeds, 1);
    await tester.ensureVisible(find.byTooltip('Dar impulso'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Dar impulso'));
    await tester.pumpAndSettle();
    expect(likes, 1);
    expect(feeds, 1);
    expect(stories, 1);
    expect(find.text('1'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('chat loads older history and can close during send', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    final state = AppState(
      api: ApiClient(
        client: MockClient((r) async {
          if (r.method == 'POST') return pending.future;
          final older = r.url.queryParameters.containsKey('cursor');
          if (older) expect(r.url.queryParameters['cursor'], 'v1.older');
          return jsonResponse({
            'items': [message(older ? 'older' : 'latest')],
            'nextCursor': older ? null : 'v1.older',
          });
        }),
      ),
    )..account = account;
    addTearDown(state.dispose);
    await tester.pumpWidget(
      app(state, const ChatScreen(id: 'b', name: 'Friend')),
    );
    await tester.pumpAndSettle();
    expect(find.text('latest'), findsOneWidget);
    await tester.tap(find.text('Carregar mensagens anteriores'));
    await tester.pumpAndSettle();
    expect(find.text('older'), findsOneWidget);
    expect(find.text('latest'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Sending');
    await tester.tap(find.byTooltip('Enviar mensagem'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(jsonResponse({'id': 'new'}));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
  testWidgets('chat acknowledges only displayed incoming messages', (
    tester,
  ) async {
    final receipts = <String>[];
    final state = AppState(
      api: ApiClient(
        client: MockClient((r) async {
          if (r.method == 'POST') {
            expect(r.url.path, '/messages/b/read');
            receipts.addAll((jsonDecode(r.body)['ids'] as List).cast<String>());
            return jsonResponse({'ok': true});
          }
          return jsonResponse({
            'items': [message('visible', incoming: true)],
            'nextCursor': null,
          });
        }),
      ),
    )..account = account;
    addTearDown(state.dispose);
    await tester.pumpWidget(
      app(state, const ChatScreen(id: 'b', name: 'Friend')),
    );
    await tester.pumpAndSettle();
    expect(receipts, isEmpty);
    await tester.pump(const Duration(milliseconds: 2500));
    await tester.pump();
    expect(receipts, ['visible']);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
  test(
    'Firebase logout clears local state without revoking other devices',
    () async {
      final auth = FakeAuth();
      final state = AppState(
        auth: auth,
        api: ApiClient(
          client: MockClient((r) async {
            fail('Device logout must not call global server revocation.');
          }),
        ),
      )..account = account;
      state.api.accessToken = 'old-token';
      addTearDown(state.dispose);
      expect(await state.logout(), isNull);
      expect(state.account, isNull);
      expect(state.api.accessToken, isNull);
      expect(auth.signedIn, false);
    },
  );
}
