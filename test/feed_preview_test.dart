import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:teste_app/core/api_client.dart';
import 'package:teste_app/screens/social/feed_preview_screen.dart';
import 'package:teste_app/screens/social/composer_screen.dart';
import 'package:teste_app/state/app_state.dart';
import 'package:teste_app/theme/app_theme.dart';
import 'package:teste_app/widgets/common.dart';

void main() {
  testWidgets(
    'preview without login displays feed and likes without API calls',
    (tester) async {
      var requests = 0;
      final state = AppState(
        api: ApiClient(
          client: MockClient((_) async {
            requests++;
            return http.Response('{}', 500);
          }),
        ),
      );
      addTearDown(state.dispose);
      await tester.pumpWidget(
        AppScope(
          state: state,
          child: MaterialApp(
            theme: conexiaTheme(),
            home: const FeedPreviewScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('PRÉVIA LOCAL'), findsOneWidget);
      expect(find.text('luffy'), findsWidgets);
      await tester.ensureVisible(find.byTooltip('Curtir').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Curtir').first);
      await tester.pumpAndSettle();
      expect(find.text('129 curtidas'), findsOneWidget);
      expect(requests, 0);
      expect(state.account, isNull);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('navigation, avatar profile and carousel keep local state', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState(
      api: ApiClient(
        client: MockClient((_) async {
          fail('A prévia não deve chamar a API');
        }),
      ),
    );
    addTearDown(state.dispose);
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(
          theme: conexiaTheme(),
          home: const FeedPreviewScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final avatar = find.byKey(const ValueKey('profile-preview-luffy'));
    await tester.ensureVisible(avatar);
    await tester.pumpAndSettle();
    await tester.tap(avatar);
    await tester.pumpAndSettle();
    expect(find.text('1 publicações • perfil de demonstração'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Próxima foto').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Próxima foto').first);
    await tester.pumpAndSettle();
    expect(find.text('2/2'), findsOneWidget);
    await tester.tap(find.text('Pesquisa'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'peter');
    await tester.pumpAndSettle();
    expect(find.text('peter.parker'), findsOneWidget);
    expect(find.text('luffy'), findsNothing);
    await tester.tap(find.text('Criar'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Meu carrossel');
    for (final asset in ['luffy.jpg', 'peter_parker.jpg']) {
      final item = find.byKey(ValueKey('select-assets/feed/$asset'));
      await tester.scrollUntilVisible(
        item,
        200,
        scrollable: find
            .descendant(
              of: find.byType(ComposerScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(item);
      await tester.pumpAndSettle();
    }
    await tester.scrollUntilVisible(
      find.text('Publicar na prévia'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ComposerScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Publicar na prévia'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Perfil'));
    await tester.pumpAndSettle();
    expect(find.text('1 publicações • perfil de demonstração'), findsOneWidget);
    expect(find.byIcon(Icons.collections), findsOneWidget);
    await tester.tap(find.text('Feed'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Meu carrossel'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
