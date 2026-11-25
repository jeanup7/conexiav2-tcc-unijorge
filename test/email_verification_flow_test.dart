import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:teste_app/core/api_client.dart';
import 'package:teste_app/models/models.dart';
import 'package:teste_app/screens/verification_screen.dart';
import 'package:teste_app/state/app_state.dart';
import 'package:teste_app/widgets/common.dart';

import 'firebase_session_test.dart' as fixture;

class EmailAuth extends fixture.FakeAuth {
  bool canVerify = false, failSend = false;
  int sends = 0;
  Completer<void>? sending;
  @override
  Future<void> reload() async {
    reloads++;
    verified = canVerify;
  }

  @override
  Future<void> sendVerification() async {
    sends++;
    if (failSend) {
      throw const ApiException('Não foi possível enviar a confirmação.');
    }
    await sending?.future;
  }
}

AppState makeState(EmailAuth auth) =>
    AppState(
        auth: auth,
        api: ApiClient(
          client: MockClient((request) async {
            expect(request.url.path, '/me');
            expect(
              request.headers['Authorization'],
              auth.verified ? 'Bearer verified-token' : 'Bearer pending-token',
            );
            return http.Response(
              jsonEncode(fixture.profile(auth.verified)),
              200,
            );
          }),
        ),
      )
      ..account = Account.fromJson(fixture.profile(false))
      ..loading = false;

Future<void> mount(WidgetTester tester, AppState state) async {
  await tester.pumpWidget(
    AppScope(
      state: state,
      child: MaterialApp(
        home: const VerificationScreen(),
        routes: {
          '/inicio': (_) => const Scaffold(body: Text('Verificação concluída')),
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'failed delivery is recoverable and a pending email never unlocks navigation',
    (tester) async {
      final auth = EmailAuth()..failSend = true;
      final state = makeState(auth);
      addTearDown(state.dispose);
      await mount(tester, state);
      await tester.tap(find.text('Enviar / reenviar confirmação'));
      await tester.pumpAndSettle();
      expect(
        find.text('Não foi possível enviar a confirmação.'),
        findsOneWidget,
      );
      expect(state.account!.verified, isFalse);
      auth.failSend = false;
      await tester.tap(find.text('Enviar / reenviar confirmação'));
      await tester.pumpAndSettle();
      expect(auth.sends, 2);
      expect(
        find.textContaining('Link de confirmação enviado.'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Já confirmei'));
      await tester.tap(find.text('Já confirmei'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('O e-mail ainda não foi confirmado.'),
        findsOneWidget,
      );
      expect(find.text('Verificação concluída'), findsNothing);
      auth.canVerify = true;
      await tester.tap(find.text('Já confirmei'));
      await tester.pumpAndSettle();
      expect(state.account!.verified, isTrue);
      expect(find.text('Verificação concluída'), findsOneWidget);
    },
  );

  test(
    'a late email send cannot report success in a different session',
    () async {
      final auth = EmailAuth()..sending = Completer<void>();
      final state = makeState(auth);
      addTearDown(state.dispose);
      final operation = state.sendVerificationEmail();
      final assertion = expectLater(operation, throwsA(isA<ApiException>()));
      await Future<void>.delayed(Duration.zero);
      state.api.invalidateSession();
      auth.sending!.complete();
      await assertion;
      expect(auth.sends, 1);
    },
  );

  testWidgets(
    'returning from the email app refreshes confirmation from Firebase',
    (tester) async {
      final auth = EmailAuth();
      final state = makeState(auth);
      addTearDown(state.dispose);
      await mount(tester, state);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      auth.canVerify = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.runAsync(() => state.reloadAccount());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(auth.reloads, 1);
      expect(state.account!.verified, isTrue);
      expect(find.textContaining('Operação cancelada'), findsNothing);
      expect(find.text('Verificação concluída'), findsOneWidget);
    },
  );
}
