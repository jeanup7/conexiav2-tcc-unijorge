import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:teste_app/core/api_client.dart';
import 'package:teste_app/screens/vision_screen.dart';
import 'package:teste_app/state/app_state.dart';
import 'package:teste_app/theme/app_theme.dart';
import 'package:teste_app/widgets/common.dart';

http.Response json(Object value, [int status = 200]) =>
    http.Response(jsonEncode(value), status);
Future<void> mount(WidgetTester tester, AppState state, Widget screen) async {
  tester.view.physicalSize = const Size(800, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    AppScope(
      state: state,
      child: MaterialApp(theme: conexiaTheme(), home: screen),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('disabled models explain availability without opening a camera', (
    tester,
  ) async {
    var requests = 0;
    final state = AppState(
      api: ApiClient(
        client: MockClient((r) async {
          requests++;
          expect(r.method, 'GET');
          return json({'enabled': false});
        }),
      ),
    );
    addTearDown(state.dispose);
    await mount(tester, state, const VisionScreen());
    expect(
      find.textContaining('Os modelos ainda não estão ativados'),
      findsOneWidget,
    );
    expect(find.text('Iniciar captura pela câmera'), findsNothing);
    expect(requests, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'camera capture requires explicit opt in and respects server denial',
    (tester) async {
      final bodies = <Map>[];
      final api = ApiClient(
        client: MockClient((r) async {
          if (r.method == 'GET') return json({'enabled': true});
          bodies.add(jsonDecode(r.body) as Map);
          return json({
            'error': {
              'message': 'Seu responsável precisa autorizar este experimento.',
            },
          }, 403);
        }),
      );
      final state = AppState(api: api);
      api.onForbidden = null;
      addTearDown(state.dispose);
      await mount(tester, state, const VisionScreen());
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Iniciar captura pela câmera'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Iniciar captura pela câmera'));
      await tester.tap(find.text('Iniciar captura pela câmera'));
      await tester.pumpAndSettle();
      expect(bodies.single, {'consent': true, 'consentVersion': visionVersion});
      expect(
        find.text('Seu responsável precisa autorizar este experimento.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'a late session response after leaving is cancelled without a camera',
    (tester) async {
      final response = Completer<http.Response>();
      final deleted = Completer<void>();
      final state = AppState(
        api: ApiClient(
          client: MockClient((r) async {
            if (r.method == 'POST') return response.future;
            if (r.method == 'DELETE') {
              deleted.complete();
              return json({'ok': true});
            }
            return json({'enabled': true});
          }),
        ),
      );
      addTearDown(state.dispose);
      await mount(tester, state, const VisionScreen());
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Iniciar captura pela câmera'));
      await tester.tap(find.text('Iniciar captura pela câmera'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      response.complete(
        json({
          'id': 'late',
          'challenge': ['front', 'left', 'right'],
        }),
      );
      await tester.runAsync(
        () => deleted.future.timeout(const Duration(seconds: 3)),
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('guardian consent can be revoked and does not approve age', (
    tester,
  ) async {
    var granted = false;
    final changes = <bool>[];
    final state = AppState(
      api: ApiClient(
        client: MockClient((r) async {
          if (r.method == 'POST') {
            final body = jsonDecode(r.body) as Map;
            expect(body['consentVersion'], visionVersion);
            granted = body['granted'] as bool;
            changes.add(granted);
          }
          return json({'granted': granted});
        }),
      ),
    );
    addTearDown(state.dispose);
    await mount(tester, state, const VisionConsentScreen(childId: 'child'));
    await tester.tap(find.text('Autorizar participação experimental'));
    await tester.pumpAndSettle();
    expect(find.text('Participação autorizada'), findsOneWidget);
    await tester.tap(find.text('Revogar e excluir resultados'));
    await tester.pumpAndSettle();
    expect(changes, [true, false]);
    expect(find.text('Participação não autorizada'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
