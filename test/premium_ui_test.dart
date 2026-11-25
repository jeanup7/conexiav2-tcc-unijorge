import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:teste_app/core/api_client.dart';
import 'package:teste_app/screens/login_screen.dart';
import 'package:teste_app/screens/painel_responsavel_screen.dart';
import 'package:teste_app/screens/social/feed_preview_screen.dart';
import 'package:teste_app/screens/social/feed_screen.dart';
import 'package:teste_app/state/app_state.dart';
import 'package:teste_app/theme/app_theme.dart';
import 'package:teste_app/widgets/design_system.dart';
import 'package:teste_app/widgets/common.dart';
import 'package:teste_app/models/models.dart';
import 'package:teste_app/widgets/social/profile_heading.dart';

import 'audit_improvements_test.dart' show account, app, jsonResponse;

const boundaryKey = ValueKey('visual-capture');
Future<void> capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('CAPTURE_UI')) return;
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 80)),
  );
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(boundaryKey),
  );
  boundary.markNeedsPaint();
  await tester.pump();
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory(
      r'C:\Users\Pc\Documents\Codex\2026-10-06\lu\tmp\premium_visual',
    );
    await directory.create(recursive: true);
    await File('${directory.path}/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void viewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final font = FontLoader('Lato');
    for (final weight in ['Regular', 'Bold', 'Black']) {
      font.addFont(rootBundle.load('assets/fonts/Lato-$weight.ttf'));
    }
    await font.load();
    final material = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    final lucide = FontLoader('packages/lucide_icons_flutter/Lucide')
      ..addFont(
        rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
      );
    await Future.wait([material.load(), lucide.load()]);
  });
  testWidgets('dark feed preserves media and clear navigation', (tester) async {
    viewport(tester);
    final state = AppState(
      api: ApiClient(
        client: MockClient((_) async => throw StateError('Local preview')),
      ),
    );
    addTearDown(state.dispose);
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: AppScope(
          state: state,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: conexiaTheme(brightness: Brightness.dark),
            home: const FeedPreviewScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(NavigationBar))).brightness,
      Brightness.dark,
    );
    expect(find.byType(ColorFiltered), findsNothing);
    expect(find.byTooltip('Criar publicação'), findsOneWidget);
    await capture(tester, 'feed_dark');
    await tester.tap(find.text('Perfil'));
    await tester.pumpAndSettle();
    expect(find.text('Criar primeira publicação'), findsOneWidget);
    await capture(tester, 'profile_dark');
    await tester.tap(find.text('Criar primeira publicação'));
    await tester.pumpAndSettle();
    expect(find.text('Criar publicação'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
  testWidgets('recortes handle large captions, safe areas and expired pages', (
    tester,
  ) async {
    viewport(tester);
    tester.view.physicalSize = const Size(320, 720);
    final recortes = [
      Publication(
        id: 'first',
        userId: 'a',
        author: 'Autor do recorte',
        text: List.filled(25, 'Uma descoberta para compartilhar.').join(' '),
        likes: 0,
        liked: false,
        assetImage: 'assets/feed/luffy.jpg',
      ),
      const Publication(
        id: 'expired',
        userId: 'b',
        author: 'Outro autor',
        text: 'Conteúdo expirado',
        likes: 0,
        liked: false,
        expires: 1,
      ),
    ];
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          theme: conexiaTheme(),
          home: MediaQuery(
            data: const MediaQueryData(
              textScaler: TextScaler.linear(1.8),
              padding: EdgeInsets.only(top: 30, bottom: 20),
            ),
            child: StoryViewer(stories: recortes, initial: 0, preview: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Recortes'), findsOneWidget);
    expect(find.byType(SafeArea), findsWidgets);
    expect(tester.takeException(), isNull);
    await capture(tester, 'recorte');
    await tester.tap(find.byTooltip('Próximo recorte'));
    await tester.pumpAndSettle();
    expect(find.text('Este recorte expirou.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('empty profile CTA remains usable with enlarged text', (
    tester,
  ) async {
    viewport(tester);
    tester.view.physicalSize = const Size(320, 568);
    var created = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: conexiaTheme(brightness: Brightness.dark),
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
            child: SingleChildScrollView(
              child: FirstPublication(onCreate: () => created = true),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Criar primeira publicação'));
    await tester.tap(find.text('Criar primeira publicação'));
    expect(created, isTrue);
    expect(tester.takeException(), isNull);
  });
  testWidgets('mobile login remains scrollable with keyboard and large text', (
    tester,
  ) async {
    viewport(tester);
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: conexiaTheme(),
          home: const LoginScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await capture(tester, 'login');
    await tester.pumpWidget(
      MaterialApp(
        theme: conexiaTheme(),
        home: const MediaQuery(
          data: MediaQueryData(
            textScaler: TextScaler.linear(1.8),
            viewInsets: EdgeInsets.only(bottom: 280),
          ),
          child: LoginScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Entrar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();
    expect(find.text('Informe seu e-mail'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'mobile feed and profile keep navigation usable after restyling',
    (tester) async {
      viewport(tester);
      final state = AppState(
        api: ApiClient(
          client: MockClient(
            (r) async => throw StateError('Preview must stay local'),
          ),
        ),
      );
      addTearDown(state.dispose);
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: app(state, const FeedPreviewScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await capture(tester, 'feed');
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -420));
      await tester.pumpAndSettle();
      await capture(tester, 'post');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Perfil'));
      await tester.tap(find.text('Perfil'));
      await tester.pumpAndSettle();
      await capture(tester, 'profile');
      expect(find.text('publicações'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('family surface fits large text and exposes the child actions', (
    tester,
  ) async {
    viewport(tester);
    final state = AppState(
      api: ApiClient(
        client: MockClient(
          (r) async => jsonResponse({
            'items': [
              {
                'id': 'child',
                'childName': 'Nome privado',
                'name': 'Ninja',
                'email': 'child@example.com',
                'verified': 1,
                'needsNickname': false,
                'state': 'active',
              },
            ],
          }),
        ),
      ),
    )..account = account;
    addTearDown(state.dispose);
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: app(state, const PainelResponsavelScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await capture(tester, 'family');
    expect(find.text('Autorizar contatos'), findsOneWidget);
    await tester.pumpWidget(
      app(
        state,
        const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(1.8)),
          child: PainelResponsavelScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'narrow feed supports enlarged text without losing its controls',
    (tester) async {
      viewport(tester);
      tester.view.physicalSize = const Size(320, 720);
      final state = AppState(
        api: ApiClient(
          client: MockClient(
            (r) async => throw StateError('Preview stays local'),
          ),
        ),
      );
      addTearDown(state.dispose);
      await tester.pumpWidget(
        app(
          state,
          const MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(1.8)),
            child: FeedPreviewScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'Feed enlarged text');
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.textContaining('Explorar ·'), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text('Escolha seu caminho.'), findsNothing);
      await tester.ensureVisible(find.text('Perfil'));
      await tester.tap(find.text('Perfil'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'reduced motion uses static placeholders and ignores repeated busy taps',
    (tester) async {
      viewport(tester);
      int actions = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: conexiaTheme(),
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: Column(
                children: [
                  BusyButton(
                    label: 'Publicando…',
                    busy: true,
                    onPressed: () => actions++,
                  ),
                  const Expanded(child: ListSkeleton()),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Publicando…'));
      await tester.pumpAndSettle();
      expect(actions, 0);
      expect(tester.takeException(), isNull);
      // Feed loading must not issue fictitious post/media requests.
      final posts = Completer<Map<String, dynamic>>();
      final state = AppState(
        api: ApiClient(
          client: MockClient((r) async {
            expect(r.url.path, '/posts');
            await posts.future;
            return jsonResponse({'items': []});
          }),
        ),
      )..account = account;
      addTearDown(state.dispose);
      await tester.pumpWidget(
        app(
          state,
          const MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: Scaffold(body: FeedScreen(ownOnly: true)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Carregando publicações'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      posts.complete({});
      await tester.pump();
    },
  );
}
