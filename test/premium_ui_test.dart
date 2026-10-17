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
      await tester.tap(find.text('Perfil'));
      await tester.pumpAndSettle();
      await capture(tester, 'profile');
      expect(find.textContaining('perfil de demonstração'), findsOneWidget);
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
      expect(find.text('Feed'), findsOneWidget);
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
