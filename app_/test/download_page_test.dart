import 'dart:async';
import 'dart:convert';

import 'package:cloud_storage/src/analytics/growth_analytics.dart';
import 'package:cloud_storage/src/home/download_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('every platform uses the measured API redirect with one channel', () {
    final apiBase = Uri.parse('https://api.example.test/');

    expect(
      downloadUriForPlatform(
        platform: 'windows',
        apiBaseUri: apiBase,
        channel: GrowthChannel.linkedin,
      ),
      Uri.parse('https://api.example.test/downloads/windows?channel=linkedin'),
    );
    expect(
      downloadUriForPlatform(
        platform: 'linux',
        apiBaseUri: apiBase,
        channel: GrowthChannel.organicSearch,
      ),
      Uri.parse(
        'https://api.example.test/downloads/linux?channel=organic_search',
      ),
    );
    expect(
      downloadUriForPlatform(
        platform: 'android',
        apiBaseUri: apiBase,
        channel: GrowthChannel.product,
      ),
      Uri.parse('https://api.example.test/downloads/android?channel=product'),
    );
    for (final platform in <String>[
      'windows',
      'linux',
      'android',
      'macos',
      'ios',
    ]) {
      final uri = downloadUriForPlatform(
        platform: platform,
        apiBaseUri: apiBase,
        channel: GrowthChannel.reddit,
      );
      expect(uri.path, '/downloads/$platform');
      expect(uri.queryParameters, <String, String>{'channel': 'reddit'});
      expect(uri.toString(), isNot(contains('utm_')));
      expect(uri.toString(), isNot(contains('referrer')));
    }
  });

  testWidgets('desktop download buttons fail closed when channel status fails', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final client = MockClient((request) async {
      if (request.url.path == '/downloads/latest/release-manifest.json') {
        return http.Response(
          jsonEncode(<String, Object>{'version': '1.0.4', 'buildNumber': 8}),
          200,
        );
      }
      return http.Response('Unavailable', 503);
    });

    await tester.pumpWidget(MaterialApp(home: DownloadPage(client: client)));
    await tester.pumpAndSettle();

    expect(find.text('Status unknown'), findsWidgets);
    expect(find.text('Retry availability'), findsOneWidget);
    expect(find.text('Join the tester program'), findsOneWidget);
    expect(
      find.text(
        'Could not check download availability. Check your connection and try again.',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('verified public build is published'),
      findsOneWidget,
    );

    final windowsButton = tester.widget<ButtonStyleButton>(
      find.byKey(const ValueKey<String>('Windows-download-action')),
    );
    final linuxButton = tester.widget<ButtonStyleButton>(
      find.byKey(const ValueKey<String>('Linux-download-action')),
    );
    final installerButton = tester.widget<ButtonStyleButton>(
      find.byKey(const ValueKey<String>('Windows-installer-action')),
    );
    expect(installerButton.onPressed, isNull);
    expect(windowsButton.onPressed, isNull);
    expect(linuxButton.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'failed availability check can recover without reopening the page',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var statusChecks = 0;
      String? launchedUrl;
      const launcherChannel = MethodChannel('plugins.flutter.io/url_launcher');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        launcherChannel,
        (call) async {
          if (call.method == 'launch') {
            launchedUrl = (call.arguments as Map)['url'] as String;
          }
          return true;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          launcherChannel,
          null,
        );
      });
      final client = MockClient((request) async {
        if (!request.url.path.endsWith('/downloads/status')) {
          return http.Response('{}', 404);
        }
        if (++statusChecks == 1) {
          return http.Response('Unavailable', 503);
        }
        return http.Response(
          jsonEncode({
            'platforms': {
              'windows': {'available': true},
              'linux': {'available': true},
              'android': {'available': false},
              'macos': {'available': false},
              'ios': {'available': false},
            },
          }),
          200,
        );
      });
      await tester.pumpWidget(MaterialApp(home: DownloadPage(client: client)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retry availability'));
      await tester.pumpAndSettle();
      expect(statusChecks, 2);
      expect(find.text('Retry availability'), findsNothing);
      expect(
        tester
            .widget<ButtonStyleButton>(
              find.byKey(const ValueKey<String>('Windows-download-action')),
            )
            .onPressed,
        isNotNull,
      );
      expect(
        tester
            .widget<ButtonStyleButton>(
              find.byKey(const ValueKey<String>('Linux-download-action')),
            )
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(
        find.byKey(const ValueKey<String>('Windows-installer-action')),
      );
      await tester.pumpAndSettle();
      expect(
        launchedUrl,
        'https://github.com/Ronik-Development/ronikcloud-releases/releases/latest/download/ronikcloud-windows-setup.exe',
      );
      expect(
        find.textContaining('This Windows release is unsigned'),
        findsOneWidget,
      );
    },
  );

  testWidgets('pending download status is described as checking', (
    tester,
  ) async {
    final status = Completer<http.Response>();
    final client = MockClient((request) async {
      return request.url.path.endsWith('/downloads/status')
          ? status.future
          : http.Response('{}', 404);
    });
    await tester.pumpWidget(MaterialApp(home: DownloadPage(client: client)));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Checking…'), findsWidgets);
    expect(find.text('Not available'), findsNothing);
    expect(find.text('Status unknown'), findsNothing);
    status.complete(http.Response('{}', 200));
    await tester.pumpAndSettle();
    expect(find.text('Retry availability'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
