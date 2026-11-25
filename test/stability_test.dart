import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:teste_app/core/api_client.dart';
import 'package:teste_app/main.dart';
import 'package:teste_app/models/models.dart';
import 'package:teste_app/screens/perfil_infantil_screen.dart';
import 'package:teste_app/screens/painel_responsavel_screen.dart';
import 'package:teste_app/screens/social/messages_screen.dart';
import 'package:teste_app/screens/social/feed_screen.dart';
import 'package:teste_app/screens/social/private_image.dart';
import 'package:teste_app/state/app_state.dart';
import 'package:teste_app/widgets/common.dart';
import 'package:teste_app/widgets/social/post_gallery.dart';
import 'package:teste_app/widgets/social/profile_avatar.dart';

import 'audit_improvements_test.dart' show account, app, jsonResponse;
import 'firebase_session_test.dart' show FakeAuth, profile;

class BrokenSignOut extends FakeAuth {
  @override
  Future<void> signOut() async => throw StateError('offline');
}

void main() {
  test('late account reload cannot restore a signed-out session', () async {
    final response = Completer<http.Response>();
    final started = Completer<void>();
    final state = AppState(
      auth: FakeAuth(),
      api: ApiClient(
        client: MockClient((r) {
          started.complete();
          return response.future;
        }),
      ),
    )..account = account;
    addTearDown(state.dispose);
    final loading = state.reloadAccount();
    final rejected = expectLater(loading, throwsA(isA<ApiException>()));
    await started.future;
    await state.clearSession();
    response.complete(jsonResponse(profile(true)));
    await rejected;
    expect(state.account, isNull);
    expect(state.api.accessToken, isNull);
  });

  test('old request never retries with the next account credentials', () async {
    final response = Completer<http.Response>();
    final started = Completer<void>();
    int requests = 0, renewals = 0;
    final api = ApiClient(
      client: MockClient((r) {
        requests++;
        started.complete();
        return response.future;
      }),
    )..accessToken = 'old';
    addTearDown(api.close);
    api.renewSession = () async {
      renewals++;
      return true;
    };
    final rejected = expectLater(
      api.request('POST', '/posts', {'text': 'old'}),
      throwsA(isA<ApiException>()),
    );
    await started.future;
    api.invalidateSession();
    api.accessToken = 'new';
    response.complete(http.Response('{}', 401));
    await rejected;
    expect(requests, 1);
    expect(renewals, 0);
    expect(api.accessToken, 'new');
  });

  test('SDK sign-out failure still clears account and access token', () async {
    final state = AppState(auth: BrokenSignOut())..account = account;
    state.api.accessToken = 'token';
    addTearDown(state.dispose);
    await state.clearSession();
    expect(state.account, isNull);
    expect(state.api.accessToken, isNull);
    expect(state.error, isNotNull);
  });

  test('dispose during session initialization ignores late results', () async {
    final response = Completer<http.Response>();
    final started = Completer<void>();
    final state = AppState(
      auth: FakeAuth(),
      api: ApiClient(
        client: MockClient((r) {
          started.complete();
          return response.future;
        }),
      ),
    );
    int changes = 0;
    state.addListener(() => changes++);
    final initialization = state.initialize();
    await started.future;
    state.dispose();
    response.complete(jsonResponse(profile(true)));
    await initialization;
    expect(changes, 0);
    expect(state.account, isNull);
  });

  testWidgets('loss of active access closes stacked social screens', (
    tester,
  ) async {
    final state = AppState(
      auth: FakeAuth()..active = false,
      api: ApiClient(
        client: MockClient(
          (r) async => r.url.path == '/me'
              ? jsonResponse({
                  ...profile(true),
                  'needsGuardian': true,
                  'approved': 0,
                })
              : jsonResponse({'items': []}),
        ),
      ),
    )..account = account;
    addTearDown(state.dispose);
    await tester.pumpWidget(ConexaoSeguraApp(state: state));
    await tester.pumpAndSettle();
    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Private chat')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await state.reloadAccount();
    await tester.pumpAndSettle();
    expect(find.text('Private chat'), findsNothing);
    expect(state.account!.active, false);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test(
    'repeated unauthorized response clears the session even with invalid JSON',
    () async {
      int requests = 0;
      final state = AppState(
        auth: FakeAuth(),
        api: ApiClient(
          client: MockClient((r) async {
            requests++;
            return http.Response('<html>unauthorized</html>', 401);
          }),
        ),
      )..account = account;
      addTearDown(state.dispose);
      await expectLater(
        state.api.request('GET', '/posts'),
        throwsA(isA<ApiException>()),
      );
      expect(requests, 2);
      expect(state.account, isNull);
    },
  );

  testWidgets('logout discards imperative private routes', (tester) async {
    final state = AppState(
      auth: FakeAuth()..active = false,
      api: ApiClient(
        client: MockClient((r) async => jsonResponse({'items': []})),
      ),
    )..account = account;
    addTearDown(state.dispose);
    await tester.pumpWidget(ConexaoSeguraApp(state: state));
    await tester.pumpAndSettle();
    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Private route')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Private route'), findsOneWidget);
    await state.clearSession();
    await tester.pumpAndSettle();
    expect(find.text('Private route'), findsNothing);
    expect(find.text('Entrar'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('stories failure does not hide successfully loaded posts', (
    tester,
  ) async {
    final state = AppState(
      api: ApiClient(
        client: MockClient((r) async {
          if (r.url.path == '/stories') return http.Response('{}', 500);
          return jsonResponse({
            'items': [
              {
                'id': 'post',
                'user': 'a',
                'text': 'Feed survives',
                'author': {'name': 'Adult'},
                'likes': 0,
                'liked': false,
              },
            ],
          });
        }),
      ),
    )..account = account;
    addTearDown(state.dispose);
    await tester.pumpWidget(app(state, const Scaffold(body: FeedScreen())));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Feed survives', findRichText: true),
      findsWidgets,
    );
    expect(find.textContaining('recortes'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('invalid base64 and corrupt avatar bytes have safe fallbacks', (
    tester,
  ) async {
    final state = AppState(
      api: ApiClient(
        client: MockClient(
          (r) async => jsonResponse({
            'data': r.url.path.endsWith('avatar')
                ? base64Encode([1, 2, 3])
                : 'not base64!!',
          }),
        ),
      ),
    );
    addTearDown(state.dispose);
    await tester.pumpWidget(
      app(
        state,
        const Scaffold(
          body: Column(
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: PrivateImage(media: 'invalid', height: 48),
              ),
              ProfileAvatar(media: 'avatar'),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    expect(find.byIcon(Icons.person_outline), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('gallery clamps selected page after removing photos', (
    tester,
  ) async {
    final photos = List.generate(
      3,
      (_) => const PostPhoto.asset('assets/demo/luffy.jpg'),
    );
    Widget gallery(int count) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 300,
          child: PostGallery(
            photos: photos.take(count).toList(),
            onDoubleTap: () {},
          ),
        ),
      ),
    );
    await tester.pumpWidget(gallery(3));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Próxima foto'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Próxima foto'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(gallery(2));
    await tester.pumpAndSettle();
    expect(find.text('2/2'), findsOneWidget);
    expect(find.byTooltip('Próxima foto'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile fits a short viewport with large system text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = AppState(
      api: ApiClient(
        client: MockClient((r) async => jsonResponse({'items': []})),
      ),
    )..account = account;
    addTearDown(state.dispose);
    await tester.pumpWidget(
      app(
        state,
        const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: PerfilInfantilScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('synchronous loader errors become retryable UI', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AsyncItems(
            load: () => throw StateError('load failed'),
            builder: (_, _) => const SizedBox(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tentar novamente'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    expect(find.text('Tentar novamente'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('family rebuild does not repeat status requests', (tester) async {
    int calls = 0;
    final state = AppState(
      auth: FakeAuth(),
      api: ApiClient(
        client: MockClient((r) async {
          if (r.url.path == '/me') {
            return jsonResponse({...profile(true), 'needsGuardian': true});
          }
          calls++;
          return jsonResponse({
            'childVerified': true,
            'guardianVerified': true,
            'approved': false,
          });
        }),
      ),
    )..account = Account.fromJson({...profile(true), 'needsGuardian': true});
    addTearDown(state.dispose);
    await tester.pumpWidget(app(state, const PainelResponsavelScreen()));
    await tester.pumpAndSettle();
    await state.reloadAccount();
    await tester.pumpAndSettle();
    expect(calls, 1);
    await tester.tap(find.byTooltip('Atualizar família'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sending during initial chat load queues a fresh fetch', (
    tester,
  ) async {
    final first = Completer<http.Response>();
    int gets = 0;
    final state = AppState(
      api: ApiClient(
        client: MockClient((r) async {
          if (r.method == 'POST') return jsonResponse({});
          if (++gets == 1) return first.future;
          return jsonResponse({
            'items': [
              {
                'id': 'sent',
                'sender': 'a',
                'recipient': 'b',
                'text': 'Sent during poll',
                'created': 1,
                'read': 0,
              },
            ],
          });
        }),
      ),
    )..account = account;
    addTearDown(state.dispose);
    await tester.pumpWidget(
      app(state, const ChatScreen(id: 'b', name: 'Friend')),
    );
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Sent during poll');
    await tester.tap(find.byTooltip('Enviar mensagem'));
    await tester.pump();
    first.complete(jsonResponse({'items': []}));
    await tester.pumpAndSettle();
    expect(gets, 2);
    expect(find.text('Sent during poll'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
