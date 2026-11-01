import 'dart:async';
import 'dart:io';

import 'package:cloud_storage/app_theme.dart';
import 'package:cloud_storage/src/billing/apple_store_purchase_service.dart';
import 'package:cloud_storage/src/billing/apple_subscription_page.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  late ThemeData reviewTheme;

  setUpAll(() async {
    await _loadReviewFonts();
    reviewTheme = AppTheme.dark(platform: TargetPlatform.macOS);
    expect(GoogleFonts.config.allowRuntimeFetching, isFalse);
    expect(reviewTheme.platform, TargetPlatform.macOS);
    expect(reviewTheme.visualDensity, VisualDensity.compact);
    await GoogleFonts.pendingFonts();
    final interLicense = await LicenseRegistry.licenses.firstWhere(
      (entry) => entry.packages.contains('Inter'),
    );
    expect(
      interLicense.paragraphs.map((paragraph) => paragraph.text).join('\n'),
      contains('SIL OPEN FONT LICENSE Version 1.1'),
    );
  });

  for (final interval in const <String>['monthly', 'yearly']) {
    testWidgets('renders the $interval App Store subscription review image', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final purchaseApi = _ReviewPurchaseApi(_readyState());
      addTearDown(purchaseApi.close);
      const screenshotKey = Key('subscription-review-screenshot');

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('en', 'US'),
          supportedLocales: const <Locale>[Locale('en', 'US')],
          themeAnimationDuration: Duration.zero,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: TextScaler.noScaling,
            ),
            child: child!,
          ),
          theme: reviewTheme,
          home: RepaintBoundary(
            key: screenshotKey,
            child: AppleSubscriptionPage(
              auth: MockFirebaseAuth(),
              purchaseApi: purchaseApi,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      if (interval == 'yearly') {
        await tester.tap(find.text('Yearly'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      _expectReviewState(
        tester,
        screenshotKey: screenshotKey,
        interval: interval,
      );
      await expectLater(
        find.byKey(screenshotKey),
        matchesGoldenFile(_reviewGoldenPath(interval)),
      );
      await _tapPlanCtas(tester, purchaseApi);
      expect(
        purchaseApi.purchasedProductIds,
        interval == 'yearly'
            ? <String>[
                appleBasicYearlyProductId,
                appleProYearlyProductId,
                appleUltraYearlyProductId,
              ]
            : <String>[
                appleBasicMonthlyProductId,
                appleProMonthlyProductId,
                appleUltraMonthlyProductId,
              ],
      );
    });
  }

  test('uses Linux baselines only on Linux hosts', () {
    expect(
      _reviewGoldenPath('monthly', linux: true),
      endsWith('subscriptions-monthly-linux.png'),
    );
    expect(
      _reviewGoldenPath('monthly', linux: false),
      endsWith('subscriptions-monthly.png'),
    );
  });
}

String _reviewGoldenPath(String interval, {bool? linux}) {
  final platformSuffix = (linux ?? Platform.isLinux) ? '-linux' : '';
  return '../../branding/app-store/iap-review/en-US/'
      'subscriptions-$interval$platformSuffix.png';
}

void _expectReviewState(
  WidgetTester tester, {
  required Key screenshotKey,
  required String interval,
}) {
  final yearly = interval == 'yearly';
  expect(interval == 'monthly' || yearly, isTrue);
  for (final text in <String>[
    'RonikCloud Storage',
    'Sign out',
    'Choose encrypted storage for every workspace',
    'One subscription unlocks both Personal and Business modes. '
        'Your purchase is billed to your Apple Account.',
    'Monthly',
    'Yearly',
    'Basic',
    'Pro',
    'Ultra',
    '500 GB',
    '1 TB',
    '2 TB',
    '500 GB of encrypted cloud storage.',
    '1 TB of storage with collaboration features.',
    '2 TB with advanced retention and priority support.',
    'Subscribe to Basic',
    'Subscribe to Pro',
    'Subscribe to Ultra',
    'Restore Purchases',
    'Manage Apple subscriptions',
    'Request Apple refund',
    'Terms of Service',
    'Privacy Policy',
    'Subscriptions renew automatically unless canceled at least 24 hours '
        'before the end of the current period. Payment is charged to your '
        'Apple Account after confirmation.\n\n'
        'Apple handles payment details for App Store purchases; RonikCloud '
        'never receives or stores your full card number or security code. '
        'Deleting your RonikCloud account does not cancel your App Store '
        'subscription. Manage or cancel it with Apple before deleting your '
        'account. Refund requests are handled by Apple.',
  ]) {
    expect(
      find.text(text),
      findsOneWidget,
      reason: 'Missing review text: $text',
    );
  }

  final currentPrices = yearly
      ? const <String>[r'$25.00', r'$35.00', r'$60.00']
      : const <String>[r'$2.49', r'$3.49', r'$6.00'];
  final hiddenPrices = yearly
      ? const <String>[r'$2.49', r'$3.49', r'$6.00']
      : const <String>[r'$25.00', r'$35.00', r'$60.00'];
  for (final price in currentPrices) {
    expect(find.text(price), findsOneWidget);
  }
  for (final price in hiddenPrices) {
    expect(find.text(price), findsNothing);
  }
  expect(find.text(yearly ? 'per year' : 'per month'), findsNWidgets(3));
  expect(find.text(yearly ? 'per month' : 'per year'), findsNothing);

  final intervalControl = tester.widget<SegmentedButton<String>>(
    find.byType(SegmentedButton<String>),
  );
  expect(intervalControl.selected, <String>{interval});

  final screenshotRect = tester.getRect(find.byKey(screenshotKey));
  expect(screenshotRect.size, const Size(1440, 900));
  final cards = find.byType(Card);
  expect(cards, findsNWidgets(3));
  final cardRects = List<Rect>.generate(
    3,
    (index) => tester.getRect(cards.at(index)),
    growable: false,
  );
  expect(cardRects[0].left, lessThan(cardRects[1].left));
  expect(cardRects[1].left, lessThan(cardRects[2].left));
  for (var index = 0; index < cardRects.length; index += 1) {
    final rect = cardRects[index];
    expect(screenshotRect.contains(rect.topLeft), isTrue);
    expect(screenshotRect.contains(rect.bottomRight), isTrue);
    expect((rect.width - cardRects.first.width).abs(), lessThan(0.01));
    expect((rect.height - cardRects.first.height).abs(), lessThan(0.01));
    expect((rect.top - cardRects.first.top).abs(), lessThan(0.01));
    if (index > 0) {
      expect(cardRects[index - 1].overlaps(rect), isFalse);
    }
  }

  final ctaRects = <Rect>[
    for (final title in const <String>['Basic', 'Pro', 'Ultra'])
      tester.getRect(find.text('Subscribe to $title')),
  ];
  for (final rect in ctaRects) {
    expect((rect.top - ctaRects.first.top).abs(), lessThan(0.01));
  }
  for (final text in <String>[
    'Restore Purchases',
    'Manage Apple subscriptions',
    'Request Apple refund',
    'Terms of Service',
    'Privacy Policy',
    'Subscriptions renew automatically unless canceled at least 24 hours '
        'before the end of the current period. Payment is charged to your '
        'Apple Account after confirmation.\n\n'
        'Apple handles payment details for App Store purchases; RonikCloud '
        'never receives or stores your full card number or security code. '
        'Deleting your RonikCloud account does not cancel your App Store '
        'subscription. Manage or cancel it with Apple before deleting your '
        'account. Refund requests are handled by Apple.',
  ]) {
    final rect = tester.getRect(find.text(text));
    expect(screenshotRect.contains(rect.topLeft), isTrue);
    expect(screenshotRect.contains(rect.bottomRight), isTrue);
  }
}

Future<void> _tapPlanCtas(
  WidgetTester tester,
  _ReviewPurchaseApi purchaseApi,
) async {
  final before = purchaseApi.purchasedProductIds.length;
  for (final title in const <String>['Basic', 'Pro', 'Ultra']) {
    await tester.tap(find.text('Subscribe to $title'));
    await tester.pumpAndSettle();
  }
  expect(purchaseApi.purchasedProductIds, hasLength(before + 3));
}

Future<void> _loadReviewFonts() async {
  final appFonts = _findAppFontsDirectory();
  final sourceSans = FontLoader('Source Sans 3');
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    sourceSans.addFont(rootBundle.load('assets/fonts/SourceSans3-$weight.ttf'));
  }
  await sourceSans.load();
  await Future.wait(<Future<ByteData>>[
    _verifiedFontData(
      File('${appFonts.path}/Inter-Regular.ttf'),
      'ecdb53099b1a68cd24c6900ea5beeafec81bd3c8cb9d0f3c51b9986583ba3982',
    ),
    _verifiedFontData(
      File('${appFonts.path}/Inter-Medium.ttf'),
      '492dec3bc33255f9d81bd5fb18704ad72f96f9b9318e4171bc9f9be9dd4bf44b',
    ),
    _verifiedFontData(
      File('${appFonts.path}/Inter-SemiBold.ttf'),
      'd7ba633bab7f40576e539a7e934a1301d7618dceea59c743de477c2c493462fc',
    ),
    _verifiedFontData(
      File('${appFonts.path}/Inter-Bold.ttf'),
      'b7e339223d56e8c4210c86f1ba87b3d43d6c47e03956ea56f0a7a938ae61b2a3',
    ),
  ]);
  final materialFonts = _findMaterialFontsDirectory();
  final materialIcons = FontLoader('MaterialIcons')
    ..addFont(
      _verifiedFontData(
        File('${materialFonts.path}/MaterialIcons-Regular.otf'),
        'd9865b671a09d683d13a863089d8825e0f61a37696ce5d7d448bc8023aa62453',
      ),
    );
  await materialIcons.load();
}

Directory _findAppFontsDirectory() {
  for (final path in <String>['assets/fonts', 'app_/assets/fonts']) {
    final directory = Directory(path);
    if (directory.existsSync()) {
      return directory;
    }
  }
  throw StateError('Unable to locate the bundled application fonts.');
}

Directory _findMaterialFontsDirectory() {
  var directory = File(Platform.resolvedExecutable).parent;
  for (var index = 0; index < 8; index += 1) {
    final candidate = Directory(
      '${directory.path}/bin/cache/artifacts/material_fonts',
    );
    if (candidate.existsSync()) {
      return candidate;
    }
    directory = directory.parent;
  }
  throw StateError('Unable to locate the Flutter material font artifacts.');
}

Future<ByteData> _verifiedFontData(File file, String expectedSha256) async {
  final bytes = await file.readAsBytes();
  final actualSha256 = sha256.convert(bytes).toString();
  if (actualSha256 != expectedSha256) {
    throw StateError(
      'Review font integrity check failed for ${file.path}: $actualSha256',
    );
  }
  return ByteData.sublistView(bytes);
}

ApplePurchaseState _readyState() =>
    ApplePurchaseState(phase: ApplePurchasePhase.ready, products: _products());

List<AppleSubscriptionProduct> _products() {
  const prices = <String, String>{
    appleBasicMonthlyProductId: r'$2.49',
    appleBasicYearlyProductId: r'$25.00',
    appleProMonthlyProductId: r'$3.49',
    appleProYearlyProductId: r'$35.00',
    appleUltraMonthlyProductId: r'$6.00',
    appleUltraYearlyProductId: r'$60.00',
  };
  return appleProductCatalog.entries
      .map((entry) {
        final catalog = entry.value;
        return AppleSubscriptionProduct(
          id: entry.key,
          tier: catalog.tier,
          interval: catalog.interval,
          title: catalog.title,
          description: catalog.description,
          localizedPrice: prices[entry.key]!,
          rawPrice: double.parse(
            prices[entry.key]!.replaceAll(RegExp(r'[^0-9.]'), ''),
          ),
        );
      })
      .toList(growable: false);
}

class _ReviewPurchaseApi implements ApplePurchaseApi {
  _ReviewPurchaseApi(this._state);

  final StreamController<ApplePurchaseState> _controller =
      StreamController<ApplePurchaseState>.broadcast(sync: true);
  final ApplePurchaseState _state;
  final List<String> purchasedProductIds = <String>[];

  @override
  ApplePurchaseState get currentState => _state;

  @override
  Stream<ApplePurchaseState> get states => _controller.stream;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> purchase(String productId) async {
    purchasedProductIds.add(productId);
  }

  @override
  Future<void> restorePurchases() async {}

  @override
  Future<void> dispose() async {}

  Future<void> close() => _controller.close();
}
