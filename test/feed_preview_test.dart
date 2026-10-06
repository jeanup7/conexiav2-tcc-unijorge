import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:teste_app/core/api_client.dart';
import 'package:teste_app/screens/social/feed_preview_screen.dart';
import 'package:teste_app/state/app_state.dart';
import 'package:teste_app/theme/app_theme.dart';
import 'package:teste_app/widgets/common.dart';

void main() {
  testWidgets('preview without login displays feed and likes without API calls', (tester) async {
    var requests = 0;
    final state = AppState(api: ApiClient(client: MockClient((_) async {
      requests++;
      return http.Response('{}', 500);
    })));
    addTearDown(state.dispose);
    await tester.pumpWidget(AppScope(
      state: state,
      child: MaterialApp(theme: conexiaTheme(), home: const FeedPreviewScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('PRÉVIA LOCAL'), findsOneWidget);
    expect(find.text('luffy'), findsWidgets);
    await tester.ensureVisible(find.byTooltip('Curtir').first);
    await tester.tap(find.byTooltip('Curtir').first);
    await tester.pumpAndSettle();
    expect(find.text('129 curtidas'), findsOneWidget);
    expect(requests, 0);
    expect(state.account, isNull);
    expect(tester.takeException(), isNull);
  });
}
