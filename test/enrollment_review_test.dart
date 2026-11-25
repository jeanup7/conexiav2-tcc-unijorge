import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:teste_app/core/api_client.dart';
import 'package:teste_app/models/models.dart';
import 'package:teste_app/screens/enrollment_review_screen.dart';
import 'package:teste_app/screens/inicio_screen.dart';
import 'package:teste_app/state/app_state.dart';
import 'package:teste_app/theme/app_theme.dart';
import 'package:teste_app/widgets/common.dart';

const profile = {
  'id': 'c',
  'name': 'Child',
  'email': 'c@example.test',
  'verified': 1,
  'approved': 0,
  'needsGuardian': true,
  'private': 1,
  'messages': 0,
  'reviewRequired': true,
  'enrollmentState': 'pending',
};
http.Response json(Object data, [int code = 200]) =>
    http.Response(jsonEncode(data), code);
AppState stateFor(
  Future<http.Response> Function(http.Request) respond, {
  bool admin = false,
}) {
  final state = AppState(api: ApiClient(client: MockClient(respond)))
    ..account = Account.fromJson({...profile, 'isAdmin': admin})
    ..loading = false;
  state.api.onForbidden = null;
  return state;
}

Future<void> mount(WidgetTester tester, AppState state, Widget child) async {
  tester.view.physicalSize = const Size(800, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    AppScope(
      state: state,
      child: MaterialApp(theme: conexiaTheme(), home: child),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'pending review cannot display social navigation or request the feed',
    (tester) async {
      var calls = 0;
      final state = stateFor((r) async {
        calls++;
        return json({});
      });
      addTearDown(state.dispose);
      await mount(tester, state, const InicioScreen());
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.text('Acompanhar revisão do cadastro'), findsOneWidget);
      expect(calls, 0);
    },
  );
  test('a forged approved flag cannot bypass the separate review state', () {
    expect(Account.fromJson({...profile, 'approved': 1}).active, isFalse);
    expect(
      Account.fromJson({
        ...profile,
        'approved': 1,
        'enrollmentState': 'approved',
      }).active,
      isTrue,
    );
  });
  testWidgets('guardian authorization is explicit and can be revoked', (
    tester,
  ) async {
    var granted = false;
    final changes = <bool>[];
    final state = stateFor((r) async {
      if (r.method == 'POST') {
        final body = jsonDecode(r.body) as Map;
        expect(body['consentVersion'], reviewVersion);
        granted = body['granted'] as bool;
        changes.add(granted);
      }
      return json({
        'authorized': granted,
        'state': 'not_submitted',
        'checks': {'childEmail': true, 'family': true},
        'history': [],
      });
    });
    addTearDown(state.dispose);
    await mount(
      tester,
      state,
      const EnrollmentReviewScreen(childId: 'child', childName: 'Aluno'),
    );
    await tester.ensureVisible(find.text('Autorizar armazenamento e revisão'));
    await tester.tap(find.text('Autorizar armazenamento e revisão'));
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    expect(changes, [true]);
    await tester.ensureVisible(find.text('Revogar e descartar captura'));
    await tester.tap(find.text('Revogar e descartar captura'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    expect(changes, [true, false]);
    expect(tester.takeException(), isNull);
  });
  testWidgets('capture cannot open before specific consent', (tester) async {
    final state = stateFor(
      (r) async => json({
        'authorized': false,
        'state': 'not_submitted',
        'checks': {'childEmail': true, 'family': true},
        'history': [],
      }),
    );
    addTearDown(state.dispose);
    await mount(tester, state, const EnrollmentReviewScreen());
    expect(find.text('Tirar foto para revisão'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('non administrator cannot load review queue', (tester) async {
    var calls = 0;
    final state = stateFor((r) async {
      calls++;
      return json({});
    });
    addTearDown(state.dispose);
    await mount(tester, state, const AdminEnrollmentScreen());
    expect(find.text('Acesso restrito à administração.'), findsOneWidget);
    expect(calls, 0);
  });
  testWidgets('correction requires a reason and explicit confirmation', (
    tester,
  ) async {
    Map? decision;
    final state = stateFor((r) async {
      if (r.method == 'POST') {
        decision = jsonDecode(r.body) as Map;
        return json({'state': 'correction'});
      }
      return json({
        'case': {'childName': 'Aluno', 'declaredAge': 12, 'state': 'pending'},
        'checks': {'childEmail': true, 'family': true},
        'hasPhoto': false,
        'history': [],
      });
    }, admin: true);
    addTearDown(state.dispose);
    await mount(tester, state, const AdminEnrollmentDetail(id: 'case'));
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Aprovar cadastro'),
          )
          .onPressed,
      isNull,
    );
    await tester.ensureVisible(find.text('Solicitar nova captura ou correção'));
    await tester.tap(find.text('Solicitar nova captura ou correção'));
    await tester.pumpAndSettle();
    expect(decision, isNull);
    expect(
      find.text('Explique a decisão com pelo menos 10 caracteres.'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byType(TextField),
      'Envie outra captura com melhor iluminação.',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Solicitar nova captura ou correção'));
    await tester.tap(find.text('Solicitar nova captura ou correção'));
    await tester.pumpAndSettle();
    expect(decision, isNull);
    await tester.tap(find.text('Confirmar decisão'));
    await tester.pumpAndSettle();
    expect(decision?['action'], 'correction');
    expect(tester.takeException(), isNull);
  });
}
