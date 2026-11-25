import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:teste_app/core/api_client.dart';
import 'package:teste_app/main.dart';
import 'package:teste_app/repositories/child_registration.dart';
import 'package:teste_app/repositories/firebase_auth_gateway.dart';
import 'package:teste_app/screens/admin_screen.dart';
import 'package:teste_app/screens/denuncia_screen.dart';
import 'package:teste_app/screens/school_screen.dart';
import 'package:teste_app/screens/seguranca_screen.dart';
import 'package:teste_app/screens/social/composer_screen.dart';
import 'package:teste_app/state/app_state.dart';

import 'family_android_test.dart'
    show waitFor, login, guardianEmail, childEmail, qaPassword;

const project = String.fromEnvironment('QA_PROJECT_ID');
const adminEmail = String.fromEnvironment('QA_ADMIN_EMAIL');
const tutorEmail = String.fromEnvironment('QA_TUTOR_EMAIL');
const referencePost = String.fromEnvironment('QA_REFERENCE_POST');
const authHost = 'http://127.0.0.1:9099';

Future<void> reveal(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump(const Duration(milliseconds: 300));
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      180,
      scrollable: find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .first,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<String> confirmLocalEmail(String email) async {
  // These endpoints exist only in the Auth Emulator, not in Firebase production.
  final result = await http.get(
    Uri.parse('$authHost/emulator/v1/projects/$project/oobCodes'),
  );
  expect(result.statusCode, 200);
  final codes = (jsonDecode(result.body)['oobCodes'] as List)
      .where((c) => c['email'] == email && c['requestType'] == 'VERIFY_EMAIL')
      .toList();
  expect(codes, isNotEmpty);
  final code = codes.last['oobCode'] as String;
  final confirmation = await http.post(
    Uri.parse(
      '$authHost/identitytoolkit.googleapis.com/v1/accounts:update?key=fake-key',
    ),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'oobCode': code}),
  );
  expect(confirmation.statusCode, 200);
  return code;
}

Future<void> verifyThroughScreen(WidgetTester tester, String email) async {
  await waitFor(tester, find.text('Confirmar e-mail'));
  await tester.tap(find.text('Confirmar e-mail'));
  await waitFor(tester, find.text('Enviar / reenviar confirmação'));
  await tester.tap(find.text('Enviar / reenviar confirmação'));
  await waitFor(tester, find.textContaining('Link de confirmação enviado.'));
  await confirmLocalEmail(email);
  await tester.ensureVisible(find.text('Já confirmei'));
  await tester.tap(find.text('Já confirmei'));
}

void open(WidgetTester tester, Widget screen) {
  unawaited(
    Navigator.of(tester.element(find.byType(NavigationBar)))
        .push<void>(MaterialPageRoute<void>(builder: (_) => screen)),
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'MVP Android: two email confirmations, nickname, school access, moderation and deletion',
    (tester) async {
      expect(const bool.fromEnvironment('QA_ISOLATED_DATABASE'), isTrue);
      expect(const bool.fromEnvironment('QA_AUTH_EMULATOR'), isTrue);
      expect(project, 'demo-conexia-barema');
      for (final email in [guardianEmail, childEmail, adminEmail, tutorEmail]) {
        expect(email.endsWith('@example.test'), isTrue);
      }
      const options = FirebaseOptions(
        apiKey: 'fake-api-key',
        appId: '1:123456789:android:abcdef123456',
        messagingSenderId: '123456789',
        projectId: 'demo-conexia-barema',
      );
      final app = await Firebase.initializeApp(
        name: 'barema-onboarding',
        options: options,
      );
      final auth = FirebaseAuth.instanceFor(app: app);
      await auth.useAuthEmulator(
        '127.0.0.1',
        9099,
        automaticHostMapping: false,
      );
      await auth.signOut();
      final api = ApiClient();
      expect(Uri.parse(api.baseUrl).host, '127.0.0.1');
      final health = await api.request('GET', '/health');
      expect(health['authEmulator'], isTrue);
      expect(health['isolatedIntegration'], isTrue);
      final state = AppState(
        api: api,
        auth: FirebaseAuthGateway(auth),
        childRegistration: FirebaseChildRegistration(
          options: options,
          emulatorHost: '127.0.0.1',
        ),
      );
      addTearDown(state.dispose);
      await tester.pumpWidget(ConexaoSeguraApp(state: state));
      await waitFor(tester, find.text('Entrar'));
      await state.register({
        'name': 'Responsável QA',
        'email': guardianEmail,
        'password': qaPassword,
        'birth': '1990-01-01',
      });
      await waitFor(tester, find.text('Confirmar e-mail'));
      expect(state.account!.verified, isFalse);
      await expectLater(
        state.api.request('GET', '/posts'),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        state.createChild({
          'name': 'Criança QA',
          'email': childEmail,
          'password': qaPassword,
          'birth': '2014-01-01',
        }),
        throwsA(isA<ApiException>()),
      );
      await verifyThroughScreen(tester, guardianEmail);
      await waitFor(tester, find.byType(NavigationBar));
      expect(state.account!.verified, isTrue);
      final guardianId = state.account!.id;
      expect(
        await state.createChild({
          'name': 'Nome privado QA',
          'email': childEmail,
          'password': qaPassword,
          'birth': '2014-01-01',
        }),
        isTrue,
      );
      expect(state.account!.id, guardianId);
      expect(auth.currentUser!.email, guardianEmail);
      final children =
          (await state.api.request('GET', '/guardian/children'))['items']
              as List;
      final childId = children.single['id'] as String;
      expect(children.single['verified'], 0);
      expect(children.single['name'], 'Novo perfil');
      await state.logout();
      await login(tester, childEmail);
      await waitFor(tester, find.text('Confirmar e-mail'));
      expect(state.account!.active, isFalse);
      await expectLater(
        state.api.request('GET', '/posts'),
        throwsA(isA<ApiException>()),
      );
      await verifyThroughScreen(tester, childEmail);
      await waitFor(tester, find.byKey(const ValueKey('nickname')));
      expect(state.account!.verified, isTrue);
      expect(state.account!.active, isFalse);
      await tester.enterText(
        find.byKey(const ValueKey('nickname')),
        'Caderno QA',
      );
      await reveal(tester, find.text('Salvar apelido e entrar no feed'));
      await tester.tap(find.text('Salvar apelido e entrar no feed'));
      await waitFor(tester, find.byType(NavigationBar));
      expect(state.account!.id, childId);
      expect(state.account!.name, 'Caderno QA');
      expect(state.account!.private, isTrue);
      expect(state.account!.active, isTrue);
      debugPrint('QA: duas confirmações e apelido validados.');
      await tester.tap(find.byTooltip('Criar publicação'));
      await waitFor(tester, find.byType(ComposerScreen));
      await tester.enterText(
        find.byType(TextField).first,
        'Aprendendo com o Conexia no Android.',
      );
      await tester.scrollUntilVisible(
        find.text('Publicar'),
        220,
        scrollable: find
            .descendant(
              of: find.byType(ComposerScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('Publicar'));
      await waitFor(tester, find.byType(NavigationBar));
      final ownPosts =
          (await state.api.request('GET', '/posts?user=$childId'))['items']
              as List;
      expect(ownPosts.single['text'], 'Aprendendo com o Conexia no Android.');

      open(tester, const DenunciaScreen(target: referencePost));
      await waitFor(tester, find.text('Outro motivo'));
      await reveal(tester, find.text('Outro motivo'));
      await tester.tap(find.text('Outro motivo'));
      await reveal(tester, find.text('Registrar denúncia'));
      await tester.tap(find.text('Registrar denúncia'));
      await waitFor(tester, find.text('Denúncia registrada'));
      await tester.tap(find.text('Entendi'));
      await waitFor(tester, find.byType(NavigationBar));
      final reports =
          (await state.api.request('GET', '/reports'))['items'] as List;
      expect(reports.single['status'], 'pending');
      await state.logout();
      await login(tester, adminEmail);
      await waitFor(tester, find.byType(NavigationBar));
      expect(state.account!.isAdmin, isTrue);
      open(tester, const AdminScreen());
      await waitFor(tester, find.text('Visão geral'));
      await reveal(tester, find.text('Remover conteúdo'));
      await tester.tap(find.text('Remover conteúdo'));
      await waitFor(tester, find.text('Remover conteúdo denunciado?'));
      await tester.enterText(
        find.byType(TextField).last,
        'Remoção fictícia para validar o fluxo de moderação.',
      );
      await tester.tap(find.text('Confirmar'));
      await waitFor(tester, find.text('Decisão registrada.'));
      await waitFor(
        tester,
        find.descendant(
          of: find.byType(AdminScreen),
          matching: find.byType(ListView),
        ),
      );
      await reveal(tester, find.text('Conteúdo removido'));
      await state.logout();
      await login(tester, childEmail);
      await waitFor(tester, find.byType(NavigationBar));
      open(tester, const ReportsScreen());
      await waitFor(tester, find.textContaining('Conteúdo removido'));
      expect(find.textContaining('Remoção fictícia'), findsOneWidget);
      debugPrint('QA: denúncia, remoção e retorno ao denunciante validados.');
      await expectLater(
        state.api.request('GET', '/admin/summary'),
        throwsA(isA<ApiException>()),
      );

      // Create the approved adult connection before selecting the school tutor.
      await state.logout();
      await login(tester, guardianEmail);
      await waitFor(tester, find.byType(NavigationBar));
      final profiles =
          (await state.api.request('GET', '/profiles?q=Tutor'))['items']
              as List;
      final tutorId = profiles.single['id'] as String;
      await state.api.request('POST', '/contacts', {'target': tutorId});
      await state.logout();
      await login(tester, tutorEmail);
      await waitFor(tester, find.byType(NavigationBar));
      await state.api.request('POST', '/contacts/approve', {
        'target': guardianId,
      });
      await state.logout();
      await login(tester, guardianEmail);
      await waitFor(tester, find.byType(NavigationBar));
      open(
        tester,
        SchoolFamilyScreen(childId: childId, childName: 'Caderno QA'),
      );
      await waitFor(tester, find.text('Convidar tutor'));
      await reveal(tester, find.text('Convidar tutor'));
      await tester.tap(find.text('Convidar tutor'));
      await waitFor(tester, find.text('Contato adulto aprovado'));
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tutor QA').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Enviar convite'));
      await tester.tap(find.text('Enviar convite'));
      await waitFor(tester, find.textContaining('Aguardando aceite'));
      await reveal(tester, find.text('Compartilhar com tutores autorizados'));
      await tester.tap(find.text('Compartilhar com tutores autorizados'));
      await tester.pumpAndSettle();
      await state.logout();
      await login(tester, tutorEmail);
      await waitFor(tester, find.byType(NavigationBar));
      open(tester, const SchoolHubScreen());
      await waitFor(tester, find.text('Aceitar'));
      await tester.tap(find.text('Aceitar'));
      await waitFor(tester, find.text('Aceitar acompanhamento?'));
      await tester.tap(find.text('Confirmar'));
      await waitFor(tester, find.text('Caderno QA'));
      await tester.ensureVisible(find.text('Caderno QA'));
      await tester.tap(find.text('Caderno QA'));
      await waitFor(tester, find.text('Atividade escolar'));
      await waitFor(tester, find.textContaining('registros no período'));
      debugPrint('QA: convite, aceite e acompanhamento escolar validados.');
      expect(find.text('Aprendendo com o Conexia no Android.'), findsNothing);
      await expectLater(
        state.api.request('GET', '/messages/$childId'),
        throwsA(isA<ApiException>()),
      );
      await state.logout();
      await login(tester, guardianEmail);
      await waitFor(tester, find.byType(NavigationBar));
      final links =
          (await state.api.request(
                'GET',
                '/school/children/$childId/tutors',
              ))['items']
              as List;
      await state.api.request(
        'DELETE',
        '/school/children/$childId/tutors/${links.single['id']}',
      );
      await state.logout();
      await login(tester, tutorEmail);
      await waitFor(tester, find.byType(NavigationBar));
      expect(
        (await state.api.request('GET', '/school/students'))['items'],
        isEmpty,
      );
      await expectLater(
        state.api.request('GET', '/school/children/$childId/activity'),
        throwsA(isA<ApiException>()),
      );
      await state.logout();
      await login(tester, childEmail);
      await waitFor(tester, find.byType(NavigationBar));
      final exported = await state.api.request('GET', '/me/export');
      expect(exported['profile']['name'], 'Caderno QA');
      expect(exported.containsKey('password'), isFalse);
      await state.deleteAccount(qaPassword);
      await waitFor(tester, find.text('Entrar'));
      expect(state.account, isNull);
      await expectLater(
        FirebaseAuthGateway(auth).login(childEmail, qaPassword),
        throwsA(isA<ApiException>()),
      );
      debugPrint(
        'QA: revogação, exportação e exclusão local/Firebase validadas.',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await auth.signOut();
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
