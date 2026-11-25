import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:teste_app/core/api_client.dart';
import 'package:teste_app/screens/social/messages_screen.dart';
import 'package:teste_app/state/app_state.dart';
import 'package:teste_app/theme/appearance.dart';
import 'package:teste_app/theme/app_theme.dart';
import 'package:teste_app/widgets/social/conexia_compass.dart';

import 'audit_improvements_test.dart' show account, app, jsonResponse;

void main() {
  testWidgets(
    'conversation search filters locally and new conversation uses contacts',
    (tester) async {
      var requests = 0;
      final state = AppState(
        api: ApiClient(
          client: MockClient((r) async {
            requests++;
            return jsonResponse({
              'items': r.url.path == '/conversations'
                  ? [
                      {'id': 'a', 'name': 'Ana'},
                      {'id': 'b', 'name': 'Bruno'},
                    ]
                  : [
                      {'id': 'c', 'name': 'Camila', 'approved': 1},
                    ],
            });
          }),
        ),
      )..account = account;
      addTearDown(state.dispose);
      await tester.pumpWidget(
        app(state, const Scaffold(body: MessagesScreen())),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ana'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'bruno');
      await tester.pumpAndSettle();
      expect(find.text('Ana'), findsNothing);
      expect(find.text('Bruno'), findsOneWidget);
      expect(requests, 1);
      await tester.tap(find.byTooltip('Limpar busca'));
      await tester.tap(find.text('Nova conversa'));
      await tester.pumpAndSettle();
      expect(find.text('Camila'), findsOneWidget);
      expect(requests, 2);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'message header remains scrollable on narrow enlarged text screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = AppState(
        api: ApiClient(
          client: MockClient((_) async => jsonResponse({'items': []})),
        ),
      )..account = account;
      addTearDown(state.dispose);
      await tester.pumpWidget(
        app(
          state,
          const Scaffold(
            body: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(1.8)),
              child: MessagesScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('shortcuts switch directly without opening destination sheet', (
    tester,
  ) async {
    var index = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: ConexiaCompass(
            selectedIndex: 0,
            onDestinationSelected: (i) => index = i,
            destinations: const [
              NavigationDestination(icon: Icon(Icons.dashboard), label: 'Feed'),
              NavigationDestination(
                icon: Icon(Icons.forum),
                label: 'Mensagens',
              ),
              NavigationDestination(icon: Icon(Icons.person), label: 'Perfil'),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('Mensagens'));
    expect(index, 1);
    expect(find.text('Escolha seu caminho.'), findsNothing);
  });
  testWidgets('native theme changes preserve drafts without filtering media', (
    tester,
  ) async {
    Appearance.instance.value = false;
    addTearDown(() => Appearance.instance.value = false);
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      ValueListenableBuilder<bool>(
        valueListenable: Appearance.instance,
        builder: (_, dark, _) => MaterialApp(
          theme: conexiaTheme(),
          darkTheme: conexiaTheme(brightness: Brightness.dark),
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          home: Scaffold(body: TextField(controller: controller)),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Rascunho preservado');
    Appearance.instance.value = true;
    await tester.pump();
    expect(controller.text, 'Rascunho preservado');
    await tester.pumpAndSettle();
    expect(find.byType(ColorFiltered), findsNothing);
    expect(
      Theme.of(tester.element(find.byType(TextField))).brightness,
      Brightness.dark,
    );
    Appearance.instance.value = false;
    await tester.pump();
    expect(controller.text, 'Rascunho preservado');
  });
}
