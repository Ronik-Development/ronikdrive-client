import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_storage/src/shared/app_page_title.dart';

void main() {
  testWidgets('page title wrapper publishes a privacy-safe browser title', (
    tester,
  ) async {
    const expectedTitle = 'Files | RonikCloud';
    final descriptions = <Map<dynamic, dynamic>>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemChrome.setApplicationSwitcherDescription') {
          descriptions.add(call.arguments as Map);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: const SizedBox().withAppPageTitle(expectedTitle)),
    );

    expect(descriptions.last['label'], expectedTitle);
    expect(
      descriptions.last['primaryColor'],
      const Color(0xFF1B48A5).toARGB32(),
    );
  });

  test('home title describes the public product', () {
    expect(ronikCloudHomeTitle, contains('Private Cloud Storage'));
    expect(ronikCloudHomeTitle, contains('Encrypted Sharing'));
  });

  testWidgets(
    'delayed covered page cannot replace Business title; pop restores home',
    (tester) async {
      const businessTitle = 'RonikCloud for Business | Choose Your Workspace';
      String? visibleTitle;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemChrome.setApplicationSwitcherDescription') {
            visibleTitle = (call.arguments as Map)['label'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final homeReady = ValueNotifier(false);
      addTearDown(homeReady.dispose);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          initialRoute: '/business',
          home: ValueListenableBuilder<bool>(
            valueListenable: homeReady,
            builder: (_, ready, _) => ready
                ? const Text(
                    'Home content',
                  ).withAppPageTitle(ronikCloudHomeTitle)
                : const SizedBox.shrink(),
          ),
          routes: {
            '/business': (_) =>
                const Text('Business content').withAppPageTitle(businessTitle),
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(visibleTitle, businessTitle);

      // Firebase initializes the retained home route beneath the public page.
      homeReady.value = true;
      await tester.pumpAndSettle();
      expect(visibleTitle, businessTitle);

      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(visibleTitle, ronikCloudHomeTitle);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('covering and restoring a route preserves its form state', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(
          body: TextField(),
        ).withAppPageTitle(ronikCloudHomeTitle),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Keep this draft');
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) =>
            const Scaffold(body: Text('Business')).withAppPageTitle('Business'),
      ),
    );
    await tester.pumpAndSettle();
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('Keep this draft'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
