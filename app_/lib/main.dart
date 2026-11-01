import 'src/shared/desktop_window_frame.dart';
import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'l10n/app_localizations.dart';

import 'app_theme.dart';
import 'firebase_options.dart';
import 'src/authentication/auth_gate.dart';
import 'src/authentication/business_landing_page.dart';
import 'src/authentication/login_page.dart';
import 'src/authentication/two_factor_service.dart';
import 'src/billing/billing_channel.dart';
import 'src/billing/subscription_coordinator.dart';
import 'src/documentation/user_documentation_page.dart';
import 'src/home/download_page.dart';
import 'src/home/tester_access_page.dart';
import 'src/legal/legal_documents_page.dart';
import 'src/privacy/privacy_debug_logging.dart';
import 'src/share/password_share_page.dart';
import 'src/share/file_request_upload_page.dart';
import 'src/shared/app_error_reporter.dart';
import 'src/shared/background_service.dart';
import 'src/shared/configured_firestore.dart';
import 'src/shared/firebase_environment_bootstrap.dart';
import 'src/shared/notification_service.dart';
import 'src/shared/native_platform_support.dart';
import 'src/shared/native_cloud_registration.dart';
import 'src/shared/release_runtime_config.dart';
import 'src/shared/web_location.dart' as web_location;
import 'src/support/support_page.dart';
import 'src/theme/theme_controller.dart';

const bool _externalCheckoutEnabledByBuild = bool.fromEnvironment(
  'RONIKDRIVE_EXTERNAL_CHECKOUT_ENABLED',
  defaultValue: true,
);
const String _billingChannelValueByBuild = String.fromEnvironment(
  'RONIKDRIVE_BILLING_CHANNEL',
  defaultValue: '',
);

const String _envStripeCheckoutBaseUrl = String.fromEnvironment(
  'STRIPE_CHECKOUT_API_BASE_URL',
);
const String _envStripePlanTier = String.fromEnvironment(
  'STRIPE_CHECKOUT_PLAN_TIER',
);
const String _envStripeBillingInterval = String.fromEnvironment(
  'STRIPE_CHECKOUT_BILLING_INTERVAL',
);

Future<FirebaseApp> _initializeFirebase() async =>
    FirebaseEnvironmentBootstrap.initialize(
      productionDefaults: DefaultFirebaseOptions.currentPlatform,
    );

Future<void> main(List<String> args) async {
  final errorReporter = AppErrorReporter.instance;
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      registerNativeCloudForCurrentPlatform();
      installPrivacySafeDebugPrint();
      if (kIsWeb) {
        usePathUrlStrategy();
      }

      // Linux's registered user-token adapters supply the same cloud facade
      // as the other platforms' native Firebase plugins.
      if (!supportsCloudRuntime(
        isWeb: kIsWeb,
        platform: defaultTargetPlatform,
      )) {
        runApp(const UnsupportedNativePlatformApp());
        return;
      }
      await errorReporter.initializePrivacyPreferences();
      errorReporter.installHandlers();

      if (!kIsWeb && BackgroundService.isDesktopWorkerInvocation(args)) {
        await BackgroundService.runDesktopWorker(
          nativeDriveOnly: args.contains('--desktop-drive-worker'),
        );
        return;
      }

      final firebaseInitialization = _initializeFirebase();
      errorReporter.configure(firebaseAppFuture: firebaseInitialization);

      runApp(
        CloudStorageApp(
          firebaseAppFuture: firebaseInitialization,
          billingChannel: _billingChannelValueByBuild.isEmpty
              ? null
              : parseBillingChannel(
                  _billingChannelValueByBuild,
                  fallback: BillingChannel.disabled,
                ),
        ),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_initializeOptionalServices(errorReporter));
      });
    },
    (error, stack) {
      unawaited(
        errorReporter.recordError(
          error,
          stack,
          fatal: true,
          reason: 'run_zoned_guarded',
        ),
      );
      if (kDebugMode) {
        debugPrint('An unhandled application error was captured locally.');
      }
    },
  );
}

Future<void> _initializeOptionalServices(AppErrorReporter errorReporter) async {
  try {
    if (!kIsWeb) {
      await BackgroundService.startForegroundHeartbeat();
    }

    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      await NotificationService().initialize();
      await BackgroundService.initialize();
      await BackgroundService.registerPeriodicSync();
    } else if (!kIsWeb && BackgroundService.supportsDetachedDesktopWorker) {
      if (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux) {
        try {
          await NotificationService().initialize();
        } catch (error, stackTrace) {
          // An unavailable desktop notification service must not prevent the
          // independent, user-enabled backup worker from starting.
          unawaited(
            errorReporter.recordError(
              error,
              stackTrace,
              reason: 'desktop_notifications_initialization',
            ),
          );
        }
      }
      await BackgroundService.ensureDesktopWorkerRunning();
    }
  } catch (e, stackTrace) {
    unawaited(
      errorReporter.recordError(e, stackTrace, reason: 'app_initialization'),
    );
    if (kDebugMode) {
      debugPrint('Optional application services did not initialize.');
    }
  }
}

class CloudStorageApp extends StatefulWidget {
  const CloudStorageApp({
    super.key,
    this.firebaseApp,
    this.firebaseAppFuture,
    this.firebaseInitializer = _initializeFirebase,
    this.auth,
    this.firestore,
    this.checkoutApi,
    this.twoFactorApi,
    this.externalCheckoutEnabled = _externalCheckoutEnabledByBuild,
    this.billingChannel,
  }) : assert(
         firebaseApp == null || firebaseAppFuture == null,
         'Provide either firebaseApp or firebaseAppFuture, not both.',
       );

  final FirebaseApp? firebaseApp;
  final Future<FirebaseApp>? firebaseAppFuture;
  final Future<FirebaseApp> Function() firebaseInitializer;
  final FirebaseAuth? auth;
  final FirebaseFirestore? firestore;
  final StripeCheckoutApi? checkoutApi;
  final TwoFactorApi? twoFactorApi;
  final bool externalCheckoutEnabled;
  final BillingChannel? billingChannel;

  BillingChannel get resolvedBillingChannel =>
      billingChannel ??
      defaultBillingChannel(
        isWeb: kIsWeb,
        platform: defaultTargetPlatform,
        externalCheckoutEnabled: externalCheckoutEnabled,
      );

  @override
  State<CloudStorageApp> createState() => _CloudStorageAppState();
}

class _CloudStorageAppState extends State<CloudStorageApp> {
  late final ThemeController _themeController;
  late final ThemeData _lightTheme;
  late final ThemeData _darkTheme;
  late Future<FirebaseApp> _firebaseInitialization;
  late StripeCheckoutApi _resolvedCheckoutApi;
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _themeController = ThemeController.instance;
    _lightTheme = AppTheme.light();
    _darkTheme = AppTheme.dark();
    _firebaseInitialization = _resolveFirebaseInitialization();
    _resolvedCheckoutApi = _resolveCheckoutApi();
    if (kIsWeb) {
      _handleIncomingPaymentUri(Uri.base);
    }
    _initDeepLinks();
  }

  Future<void> _initDeepLinks() async {
    if (kIsWeb) {
      return;
    }

    _appLinks = AppLinks();

    // Check initial link
    try {
      final initialLink = await _appLinks.getInitialLink();
      if (mounted && initialLink != null) {
        _handleDeepLink(initialLink);
      }
    } catch (e, stackTrace) {
      unawaited(
        AppErrorReporter.instance.recordError(
          e,
          stackTrace,
          reason: 'deep_link_initialization',
        ),
      );
      // Ignore errors, especially MissingPluginException on some platforms/web contexts
      if (kDebugMode) {
        debugPrint('Initial deep-link handling was unavailable.');
      }
    }

    if (!mounted) return;
    // Subscribe to new links
    try {
      _linkSubscription = _appLinks.uriLinkStream.listen(
        (uri) {
          _handleDeepLink(uri);
        },
        onError: (err) {
          unawaited(
            AppErrorReporter.instance.recordError(
              err,
              StackTrace.current,
              reason: 'deep_link_stream',
            ),
          );
          if (kDebugMode) {
            debugPrint('The deep-link stream reported an unavailable event.');
          }
        },
      );
    } catch (e, stackTrace) {
      unawaited(
        AppErrorReporter.instance.recordError(
          e,
          stackTrace,
          reason: 'deep_link_subscription',
        ),
      );
      if (kDebugMode) {
        debugPrint('Deep-link monitoring could not be started.');
      }
    }
  }

  void _handleDeepLink(Uri uri) {
    if (kDebugMode) {
      debugPrint('A deep link was received and classified locally.');
    }

    _handleIncomingPaymentUri(uri);
  }

  void _handleIncomingPaymentUri(Uri uri) {
    if (_isPaymentSuccessLink(uri)) {
      if (kDebugMode) {
        debugPrint('Payment success link detected. Updating notifier.');
      }
      paymentProcessingNotifier.value = true;
      if (kIsWeb) {
        web_location.replaceCurrentUrl(_paymentReturnPath(uri));
      }
    }
  }

  String _paymentReturnPath(Uri uri) {
    final retainedQuery = Map<String, String>.from(uri.queryParameters)
      ..removeWhere((key, value) {
        final normalizedKey = key.trim().toLowerCase();
        final normalizedValue = value.trim().toLowerCase();
        return (normalizedKey == 'payment' ||
                normalizedKey == 'checkout' ||
                normalizedKey == 'stripe') &&
            normalizedValue == 'success';
      });
    final cleanUri = Uri(
      path: '/',
      queryParameters: retainedQuery.isEmpty ? null : retainedQuery,
    );
    return cleanUri.toString();
  }

  bool _isPaymentSuccessLink(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    final host = uri.host.toLowerCase();
    String normalizeSegment(String value) =>
        value.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '-');
    final firstPathSegment = uri.pathSegments.isEmpty
        ? ''
        : normalizeSegment(uri.pathSegments.first);
    final normalizedPath = uri.pathSegments.map(normalizeSegment).join('/');
    const successPaths = {
      'payment-success',
      'successful-payment',
      'success-payment',
      'checkout-success',
      'success',
      'completed',
      'sucessful-payment',
    };

    if (scheme == 'ronikdrive') {
      return successPaths.contains(normalizeSegment(host)) ||
          successPaths.contains(firstPathSegment) ||
          successPaths.contains(normalizedPath);
    }

    if (scheme == 'https' || scheme == 'http') {
      final paymentStatus =
          uri.queryParameters['payment'] ??
          uri.queryParameters['checkout'] ??
          uri.queryParameters['stripe'];
      return successPaths.contains(firstPathSegment) ||
          successPaths.contains(normalizedPath) ||
          paymentStatus?.toLowerCase() == 'success';
    }

    return false;
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CloudStorageApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.firebaseApp != oldWidget.firebaseApp ||
        widget.firebaseAppFuture != oldWidget.firebaseAppFuture ||
        widget.auth != oldWidget.auth) {
      _firebaseInitialization = _resolveFirebaseInitialization();
    }
    if (widget.checkoutApi != oldWidget.checkoutApi) {
      _resolvedCheckoutApi = _resolveCheckoutApi();
    }
  }

  Future<FirebaseApp> _resolveFirebaseInitialization() {
    final providedApp = widget.firebaseApp;
    if (providedApp != null) {
      return Future<FirebaseApp>.value(providedApp);
    }
    final providedFuture = widget.firebaseAppFuture;
    if (providedFuture != null) {
      return providedFuture;
    }

    final injectedAuth = widget.auth;
    if (injectedAuth != null) {
      return Future<FirebaseApp>.value(injectedAuth.app);
    }

    return Future<FirebaseApp>.sync(widget.firebaseInitializer);
  }

  void _retryFirebaseInitialization() {
    setState(() {
      _firebaseInitialization = Future<FirebaseApp>.sync(
        widget.firebaseInitializer,
      );
      // A synchronous failure can settle before the next frame attaches the
      // FutureBuilder. Keep that error handled while preserving it for the UI.
      _firebaseInitialization.ignore();
      AppErrorReporter.instance.configure(
        firebaseAppFuture: _firebaseInitialization,
      );
    });
  }

  StripeCheckoutApi _resolveCheckoutApi() {
    final injected = widget.checkoutApi;
    if (injected != null) {
      return injected;
    }
    return _createCheckoutApiFromEnvironment();
  }

  StripeCheckoutApi _createCheckoutApiFromEnvironment() {
    final baseOverride = _envStripeCheckoutBaseUrl.trim();
    if (baseOverride.toLowerCase() == 'disabled') {
      return const DisabledStripeCheckoutApi();
    }

    final baseUri =
        _parseCheckoutBaseUri(baseOverride) ??
        ReleaseRuntimeConfig.resolveCheckoutApiBaseUri();
    final planTierOverride = _envStripePlanTier.trim();
    final billingIntervalOverride = _envStripeBillingInterval.trim();

    return HttpStripeCheckoutApi(
      apiBaseUrl: baseUri,
      planTier: planTierOverride.isEmpty
          ? HttpStripeCheckoutApi.defaultPlanTier
          : planTierOverride,
      billingInterval: billingIntervalOverride.isEmpty
          ? HttpStripeCheckoutApi.defaultBillingInterval
          : billingIntervalOverride,
      projectId: DefaultFirebaseOptions.currentPlatform.projectId,
    );
  }

  Uri? _parseCheckoutBaseUri(String value) {
    if (value.isEmpty) {
      return null;
    }
    try {
      final parsed = Uri.parse(value);
      if (!parsed.hasScheme) {
        return null;
      }
      if (!parsed.isScheme('https') && !parsed.isScheme('http')) {
        return null;
      }
      return parsed;
    } on FormatException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = widget.auth;
    final firestore = widget.firestore;
    final checkoutApi = _resolvedCheckoutApi;

    if (auth != null) {
      assert(
        firestore != null,
        'When providing a FirebaseAuth instance, also provide a FirebaseFirestore instance.',
      );
      final coordinator = SubscriptionCoordinator(
        firestore: firestore!,
        checkoutApi: checkoutApi,
      );
      return ValueListenableBuilder<ThemeMode>(
        valueListenable: _themeController.listenable,
        builder: (context, mode, _) {
          return MaterialApp(
            title: 'RonikCloud',
            builder: (context, child) =>
                DesktopWindowFrame(child: child ?? const SizedBox.shrink()),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [
              Locale('en'), // English
              Locale('cs'), // Czech
            ],
            debugShowCheckedModeBanner: false,
            theme: _lightTheme,
            darkTheme: _darkTheme,
            themeMode: mode,
            onGenerateRoute: _generateRoute,
            home: AuthGate(
              auth: auth,
              firestore: firestore,
              subscriptionCoordinator: coordinator,
              twoFactorApi: widget.twoFactorApi,
              billingChannel: widget.resolvedBillingChannel,
            ),
          );
        },
      );
    }

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: _themeController.listenable,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'RonikCloud',
          builder: (context, child) =>
              DesktopWindowFrame(child: child ?? const SizedBox.shrink()),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('en'), // English
            Locale('cs'), // Czech
          ],
          debugShowCheckedModeBanner: false,
          theme: _lightTheme,
          darkTheme: _darkTheme,
          themeMode: mode,
          onGenerateRoute: _generateRoute,
          home: FutureBuilder<FirebaseApp>(
            future: _firebaseInitialization,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const _SplashScreen();
              }

              if (snapshot.hasError) {
                return _InitializationError(
                  message:
                      'RonikCloud could not start. Check your connection and try again.',
                  onRetry: _retryFirebaseInitialization,
                );
              }

              final firebaseApp = snapshot.data!;
              final firebaseAuth = FirebaseAuth.instanceFor(app: firebaseApp);
              final firebaseFirestore = ConfiguredFirestore.instanceFor(
                app: firebaseApp,
              );
              final coordinator = SubscriptionCoordinator(
                firestore: firebaseFirestore,
                checkoutApi: checkoutApi,
              );
              return AuthGate(
                auth: firebaseAuth,
                firestore: firebaseFirestore,
                subscriptionCoordinator: coordinator,
                twoFactorApi: widget.twoFactorApi,
                billingChannel: widget.resolvedBillingChannel,
              );
            },
          ),
        );
      },
    );
  }

  Route<dynamic>? _generateRoute(RouteSettings settings) {
    final rawName = settings.name?.trim();
    if (rawName == null || rawName.isEmpty || rawName == '/') {
      return null;
    }

    final uri = Uri.tryParse(rawName);
    final path = uri == null || uri.path.isEmpty ? rawName : uri.path;
    final segments = Uri.parse(path).pathSegments;
    if (path == '/business') {
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (pageContext) => BusinessLandingPage(
          openAccount: (environment, register) async {
            final auth =
                widget.auth ??
                FirebaseAuth.instanceFor(
                  app: await _firebaseInitialization.timeout(
                    const Duration(seconds: 20),
                  ),
                );
            final firestore =
                widget.firestore ??
                ConfiguredFirestore.instanceFor(app: auth.app);
            if (!pageContext.mounted) return;
            unawaited(
              Navigator.of(pageContext).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => LoginPage(
                    auth: auth,
                    firestore: firestore,
                    initialRegisterMode: register,
                    initialEnvironment: environment,
                    allowRegistration:
                        widget.resolvedBillingChannel.allowsRegistration,
                  ),
                ),
              ),
            );
          },
        ),
      );
    }
    if (segments.length == 2 && segments.first == 'share') {
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => PasswordSharePage(
          token: segments.last,
          linkFragment: uri?.fragment.isNotEmpty == true ? uri!.fragment : null,
        ),
      );
    }

    if (segments.length == 2 && segments.first == 'request') {
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => FileRequestUploadPage(token: segments.last),
      );
    }

    if (path == '/legal') {
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const LegalDocumentsIndexPage(),
      );
    }

    if (path == '/support') {
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const SupportPage(),
      );
    }

    if (path == '/docs') {
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) =>
            UserDocumentationPage(initialTopic: uri?.queryParameters['tab']),
      );
    }

    if (path == '/download') {
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => Title(
          title: 'Download RonikCloud | Current Apps and Install Options',
          color: const Color(0xFF1B48A5),
          child: const DownloadPage(),
        ),
      );
    }

    if (path == '/testers') {
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => Title(
          title: 'Join the RonikCloud Founding Beta | Become a Tester',
          color: const Color(0xFF1B48A5),
          child: TesterAccessPage(campaignUri: uri),
        ),
      );
    }

    final document = LegalDocuments.byRoute(path);
    if (document == null) {
      return null;
    }
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => LegalDocumentPage(document: document),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 18),
            Text(
              'Preparing your workspace…',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _InitializationError extends StatelessWidget {
  const _InitializationError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Card(
              margin: const EdgeInsets.all(24),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lock_outline,
                      color: theme.colorScheme.primary,
                      size: 42,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Your workspace is temporarily unavailable',
                      style: theme.textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      message,
                      style: theme.textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
