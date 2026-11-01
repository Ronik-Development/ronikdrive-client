import 'package:cloud_storage/src/billing/checkout_webview_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// The plugin's platform interface is used only to provide a test WebView.
// ignore: depend_on_referenced_packages
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

class _TestPlatform extends WebViewPlatform {
  late _TestController controller;
  late _TestNavigation delegate;
  bool failLoad = false;
  int loads = 0;

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) => controller = _TestController(params, this);

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => delegate = _TestNavigation(params);

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => _TestWidget(params);
}

class _TestController extends PlatformWebViewController {
  _TestController(super.params, this.owner) : super.implementation();
  final _TestPlatform owner;

  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}
  @override
  Future<void> setBackgroundColor(Color color) async {}
  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {}
  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    owner.loads++;
    if (owner.failLoad) throw PlatformException(code: 'unavailable');
    owner.delegate.finished(params.uri.toString());
  }
}

class _TestNavigation extends PlatformNavigationDelegate {
  _TestNavigation(super.params) : super.implementation();
  late PageEventCallback finished;
  late WebResourceErrorCallback resourceError;

  @override
  Future<void> setOnPageFinished(PageEventCallback callback) async {
    finished = callback;
  }

  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async {
    resourceError = callback;
  }

  @override
  Future<void> setOnPageStarted(PageEventCallback callback) async {}
  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback callback,
  ) async {}
  @override
  Future<void> setOnUrlChange(UrlChangeCallback callback) async {}
}

class _TestWidget extends PlatformWebViewWidget {
  _TestWidget(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  late _TestPlatform platform;
  setUp(() {
    platform = _TestPlatform();
    WebViewPlatform.instance = platform;
  });

  Widget checkout() => MaterialApp(
    home: CheckoutWebViewPage(
      checkoutUri: Uri.parse('https://checkout.example.test/session'),
      successPathSuffixes: const ['payment-success'],
      cancelPathSuffixes: const ['payment-cancel'],
    ),
  );

  testWidgets('an initial native load rejection is caught and can be retried', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    platform.failLoad = true;
    await tester.pumpWidget(checkout());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Retry'), findsOneWidget);
    platform.failLoad = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(platform.loads, 2);
    expect(find.text('Retry'), findsNothing);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('child-resource errors do not invalidate a loaded checkout', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(checkout());
    await tester.pumpAndSettle();
    platform.delegate.resourceError(
      const WebResourceError(
        errorCode: -2,
        description: 'private provider detail',
        isForMainFrame: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Checkout page failed to load'), findsNothing);
    platform.delegate.resourceError(
      const WebResourceError(
        errorCode: -2,
        description: 'private provider detail',
        isForMainFrame: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Checkout page failed to load'), findsOneWidget);
    expect(find.textContaining('private provider detail'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}
