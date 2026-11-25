import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:teste_app/core/api_client.dart';
import 'package:teste_app/firebase_options.dart';
import 'package:teste_app/main.dart';
import 'package:teste_app/repositories/firebase_auth_gateway.dart';
import 'package:teste_app/screens/seguranca_screen.dart';
import 'package:teste_app/screens/social/composer_screen.dart';
import 'package:teste_app/state/app_state.dart';

const guardianEmail = String.fromEnvironment('QA_GUARDIAN_EMAIL');
const childEmail = String.fromEnvironment('QA_CHILD_EMAIL');
const qaPassword = String.fromEnvironment('QA_PASSWORD');

Future<void> waitFor(WidgetTester tester, Finder finder) async {
  final end = DateTime.now().add(const Duration(seconds: 60));
  while (finder.evaluate().isEmpty && DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  expect(finder, findsWidgets);
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> login(WidgetTester tester, String email) async {
  await waitFor(tester, find.widgetWithText(TextFormField, 'E-mail'));
  await tester.enterText(find.widgetWithText(TextFormField, 'E-mail'), email);
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Senha'),
    qaPassword,
  );
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.ensureVisible(find.text('Entrar'));
  await tester.tap(find.text('Entrar'));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android Firebase: family pause, resume, publish and report', (
    tester,
  ) async {
    expect(
      const bool.fromEnvironment('QA_ISOLATED_DATABASE'),
      isTrue,
      reason: 'Use the isolated QA runner.',
    );
    expect(
      guardianEmail,
      isNotEmpty,
      reason: 'Supply QA credentials outside the repository.',
    );
    expect(childEmail, isNotEmpty);
    expect(qaPassword, isNotEmpty);
    expect(
      guardianEmail.endsWith('@example.com') &&
          childEmail.endsWith('@example.com'),
      isTrue,
    );
    final api = ApiClient();
    expect(
      {
        '127.0.0.1',
        'localhost',
        '10.0.2.2',
      }.contains(Uri.parse(api.baseUrl).host),
      isTrue,
    );
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    final firebase = FirebaseAuth.instance;
    expect(
      (await api.request('GET', '/health'))['isolatedIntegration'],
      isTrue,
    );
    await firebase.signOut();
    final state = AppState(api: api, auth: FirebaseAuthGateway(firebase));
    addTearDown(state.dispose);
    await tester.pumpWidget(ConexaoSeguraApp(state: state));
    await login(tester, guardianEmail);
    await waitFor(tester, find.byType(NavigationBar));
    final family =
        (await state.api.request('GET', '/guardian/children'))['items'] as List;
    final child = family.cast<Map<String, dynamic>>().singleWhere(
      (v) => v['email'] == childEmail,
    );
    final childId = child['id'] as String;
    final guardianId = state.account!.id;
    final title = 'Teste Android ${DateTime.now().microsecondsSinceEpoch}';
    unawaited(
      Navigator.of(tester.element(find.byType(NavigationBar)))
          .pushNamed<void>('/painel-responsavel'),
    );
    await waitFor(tester, find.text(childEmail));
    await tester.ensureVisible(find.text('Pausar acesso'));
    await tester.tap(find.text('Pausar acesso'));
    await waitFor(tester, find.text('Reativar acesso'));
    await state.logout();
    await login(tester, childEmail);
    await waitFor(tester, find.text('Ver situação do vínculo familiar'));
    expect(state.account!.active, isFalse);
    await expectLater(
      state.api.request('GET', '/posts'),
      throwsA(isA<ApiException>()),
    );
    await state.logout();
    await login(tester, guardianEmail);
    await waitFor(tester, find.byType(NavigationBar));
    await state.api.request('PATCH', '/guardian/children/$childId', {
      'state': 'active',
    });
    final reference = await state.api.request('POST', '/posts', {
      'text': title,
      'category': 'education',
    });
    await state.logout();
    await login(tester, childEmail);
    await waitFor(tester, find.byType(NavigationBar));
    expect(state.account!.id, childId);
    expect(state.account!.active, isTrue);
    final feed = (await state.api.request('GET', '/posts'))['items'] as List;
    expect(
      feed.any((v) => v['id'] == reference['id'] && v['user'] == guardianId),
      isTrue,
    );
    await tester.tap(find.byTooltip('Criar publicação'));
    await waitFor(tester, find.byType(ComposerScreen));
    await tester.enterText(
      find.byType(TextField).first,
      '$title publicado pelo menor',
    );
    await tester.scrollUntilVisible(
      find.text('Publicar'),
      240,
      scrollable: find
          .descendant(
            of: find.byType(ComposerScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Publicar'));
    await waitFor(tester, find.byType(NavigationBar));
    final report = await state.api.request('POST', '/reports', {
      'target': reference['id'],
      'reason': 'Relato fictício de integração Android',
      'category': 'other',
    });
    final navigator = Navigator.of(tester.element(find.byType(NavigationBar)));
    unawaited(
      navigator.push<void>(
        MaterialPageRoute<void>(builder: (_) => const ReportsScreen()),
      ),
    );
    await waitFor(tester, find.textContaining('Protocolo: ${report['id']}'));
    expect(find.textContaining('Aguardando análise'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await firebase.signOut();
  });
}
