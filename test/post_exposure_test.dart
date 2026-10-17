import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teste_app/widgets/social/post_exposure.dart';

void main() {
  testWidgets('Requires two continuous seconds and only records once', (
    tester,
  ) async {
    int calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              PostExposure(
                onDisplayed: () async {
                  calls++;
                },
                child: const SizedBox(height: 200),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1750));
    expect(calls, 0);
    await tester.pump(const Duration(milliseconds: 750));
    expect(calls, 1);
    await tester.pump(const Duration(seconds: 3));
    expect(calls, 1);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Offscreen and covered posts are not recorded', (tester) async {
    int calls = 0;
    final scroll = ScrollController();
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: Scaffold(
          body: ListView(
            controller: scroll,
            children: [
              const SizedBox(height: 900),
              PostExposure(
                onDisplayed: () async {
                  calls++;
                },
                child: const SizedBox(height: 200),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(calls, 0);
    scroll.jumpTo(800);
    await tester.pump(const Duration(milliseconds: 1000));
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Outra tela')),
      ),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(calls, 0);
    navigator.currentState!.pop();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 1000));
    expect(calls, 0);
    await tester.pump(const Duration(seconds: 2));
    expect(calls, 1);
    await tester.pumpWidget(const SizedBox());
    scroll.dispose();
  });
}
