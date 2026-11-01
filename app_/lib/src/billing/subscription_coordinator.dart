import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../shared/release_runtime_config.dart';
import '../authentication/signup_session.dart';

final ValueNotifier<bool> paymentProcessingNotifier = ValueNotifier<bool>(
  false,
);

class StripeCheckoutLaunch {
  const StripeCheckoutLaunch({
    this.checkoutUri,
    this.clientSecret,
    this.uiMode = 'hosted',
  });

  final Uri? checkoutUri;
  final String? clientSecret;
  final String uiMode;

  bool get isEmbedded => uiMode == 'embedded';
  bool get isCustom => uiMode == 'custom';
}

class SubscriptionCoordinator {
  SubscriptionCoordinator({
    required FirebaseFirestore firestore,
    required StripeCheckoutApi checkoutApi,
  }) : _firestore = firestore,
       _checkoutApi = checkoutApi;

  final FirebaseFirestore _firestore;
  final StripeCheckoutApi _checkoutApi;

  String? get checkoutServiceBaseUrl => _checkoutApi.checkoutServiceBaseUrl;

  Stream<SubscriptionState> watchSubscription(String uid) {
    final docRef = _firestore.collection('users').doc(uid);
    return _pollDocumentSnapshots(docRef).map(SubscriptionState.fromSnapshot);
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> _pollDocumentSnapshots(
    DocumentReference<Map<String, dynamic>> docRef, {
    Duration interval = const Duration(seconds: 4),
  }) {
    return Stream.multi((controller) {
      var cancelled = false;
      var loading = false;

      Future<void> emitSnapshot() async {
        if (cancelled || loading) {
          return;
        }
        loading = true;
        try {
          final snapshot = await docRef.get();
          if (!cancelled) {
            controller.add(snapshot);
          }
        } catch (error, stackTrace) {
          if (!cancelled) {
            controller.addError(error, stackTrace);
          }
        } finally {
          loading = false;
        }
      }

      unawaited(emitSnapshot());
      final timer = Timer.periodic(interval, (_) {
        unawaited(emitSnapshot());
      });

      controller.onCancel = () {
        cancelled = true;
        timer.cancel();
      };
    });
  }

  Future<Uri> startCheckout({
    required String uid,
    required String email,
    String? planTier,
    String? interval,
    String? idToken,
  }) async {
    final launch = await startCheckoutSession(
      uid: uid,
      email: email,
      planTier: planTier,
      interval: interval,
      idToken: idToken,
    );
    final checkoutUri = launch.checkoutUri;
    if (checkoutUri == null) {
      throw const StripeCheckoutException(
        'Stripe checkout URL was missing from the server response.',
      );
    }
    return checkoutUri;
  }

  Future<StripeCheckoutLaunch> startCheckoutSession({
    required String uid,
    required String email,
    String? planTier,
    String? interval,
    String? idToken,
    String? checkoutTheme,
    String uiMode = 'hosted',
    String? successUrl,
    String? cancelUrl,
  }) async {
    final normalizedTier = planTier?.trim();
    final normalizedInterval = interval?.trim();
    return _checkoutApi.createCheckoutSession(
      uid: uid,
      email: email,
      tier: normalizedTier == null || normalizedTier.isEmpty
          ? null
          : normalizedTier,
      interval: normalizedInterval == null || normalizedInterval.isEmpty
          ? null
          : normalizedInterval,
      idToken: idToken,
      checkoutTheme: checkoutTheme,
      uiMode: uiMode,
      successUrl: successUrl,
      cancelUrl: cancelUrl,
    );
  }
}

class SubscriptionState {
  SubscriptionState({
    required this.exists,
    required this.status,
    this.needsRegistrationCompletion = false,
    this.currentPeriodEnd,
    this.capacityLabel,
    this.cancelAtPeriodEnd = false,
    this.accountDeletionEligibleAt,
    this.dataDeletionEligibleAt,
    this.retentionNotice,
    this.primaryProvider,
    this.activeProviders = const <String>[],
  });

  factory SubscriptionState.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    final rawStatus =
        _coerceString(data?['subscriptionStatus'])?.toLowerCase() ?? 'pending';
    final currentPeriodEnd = _coerceDateTime(
      data?['currentPeriodEnd'] ?? data?['subscriptionEndDate'],
    );
    final capacity =
        _coerceString(data?['capacity']) ??
        _coerceString(data?['capacityLabel']);
    final accountDeletionEligibleAt = _coerceDateTime(
      data?['accountTerminationEligibleAt'] ??
          data?['accountDeletionEligibleAt'],
    );
    final dataDeletionEligibleAt = _coerceDateTime(
      data?['dataDeletionEligibleAt'],
    );

    return SubscriptionState(
      exists: snapshot.exists,
      needsRegistrationCompletion:
          snapshot.exists &&
          data != null &&
          isIncompleteRegistrationProfile(data),
      status: rawStatus,
      currentPeriodEnd: currentPeriodEnd,
      capacityLabel: capacity,
      cancelAtPeriodEnd: data?['cancelAtPeriodEnd'] == true,
      accountDeletionEligibleAt: accountDeletionEligibleAt,
      dataDeletionEligibleAt: dataDeletionEligibleAt,
      retentionNotice: _coerceString(data?['subscriptionRetentionNotice']),
      primaryProvider: _coerceString(data?['billingPrimaryProvider']),
      activeProviders: _coerceStringList(data?['billingProvidersActive']),
    );
  }

  final bool exists;
  final bool needsRegistrationCompletion;
  final String status;
  final DateTime? currentPeriodEnd;
  final String? capacityLabel;
  final bool cancelAtPeriodEnd;
  final DateTime? accountDeletionEligibleAt;
  final DateTime? dataDeletionEligibleAt;
  final String? retentionNotice;
  final String? primaryProvider;
  final List<String> activeProviders;

  static const _paidStatuses = {'active', 'billing_grace_period'};

  bool get isPaid => _paidStatuses.contains(status);
  bool get isFree => exists && status == 'free';
  bool get hasWorkspaceAccess => exists && (isPaid || isFree);
  bool get requiresPayment => !hasWorkspaceAccess;

  String get statusLabel => status.isEmpty
      ? 'Unknown'
      : status[0].toUpperCase() + status.substring(1).replaceAll('_', ' ');

  static String? _coerceString(Object? value) {
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    if (value == null) {
      return null;
    }
    final normalized = value.toString().trim();
    return normalized.isEmpty ? null : normalized;
  }

  static List<String> _coerceStringList(Object? value) {
    if (value is! Iterable) {
      return const <String>[];
    }
    return value
        .map(_coerceString)
        .whereType<String>()
        .toSet()
        .toList(growable: false);
  }

  static DateTime? _coerceDateTime(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    if (value is num) {
      final milliseconds = value > 100000000000
          ? value.toInt()
          : (value * 1000).round();
      return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
    }
    if (value is String) {
      final normalized = value.trim();
      if (normalized.isEmpty || normalized.toLowerCase() == 'pending') {
        return null;
      }
      return DateTime.tryParse(normalized);
    }
    return null;
  }
}

abstract class StripeCheckoutApi {
  const StripeCheckoutApi();

  String? get checkoutServiceBaseUrl;

  Future<StripeCheckoutLaunch> createCheckoutSession({
    required String uid,
    required String email,
    String? tier,
    String? interval,
    String? idToken,
    String? checkoutTheme,
    String uiMode = 'hosted',
    String? successUrl,
    String? cancelUrl,
  });
}

class HttpStripeCheckoutApi extends StripeCheckoutApi {
  static const String defaultPlanTier = 'pro';
  static const String defaultBillingInterval = 'monthly';

  HttpStripeCheckoutApi({
    required Uri apiBaseUrl,
    http.Client? httpClient,
    this.planTier = defaultPlanTier,
    this.billingInterval = defaultBillingInterval,
    String? projectId,
  }) : assert(
         apiBaseUrl.hasScheme &&
             (apiBaseUrl.isScheme('https') || apiBaseUrl.isScheme('http')),
         'apiBaseUrl must include an http or https scheme.',
       ),
       assert(planTier.isNotEmpty, 'planTier cannot be empty'),
       assert(billingInterval.isNotEmpty, 'billingInterval cannot be empty'),
       projectId = projectId ?? ReleaseRuntimeConfig.defaultWebProjectId,
       _baseUrl = _normalizeBaseUrl(apiBaseUrl),
       _client = httpClient ?? http.Client();

  final Uri _baseUrl;
  final http.Client _client;
  final String planTier;
  final String billingInterval;
  final String projectId;

  @override
  String get checkoutServiceBaseUrl =>
      _baseUrl.toString().replaceFirst(RegExp(r'/+$'), '');

  static Uri _normalizeBaseUrl(Uri baseUrl) {
    final normalizedPath = baseUrl.path.endsWith('/')
        ? baseUrl.path
        : '${baseUrl.path}/';
    return baseUrl.replace(path: normalizedPath);
  }

  @override
  Future<StripeCheckoutLaunch> createCheckoutSession({
    required String uid,
    required String email,
    String? tier,
    String? interval,
    String? idToken,
    String? checkoutTheme,
    String uiMode = 'hosted',
    String? successUrl,
    String? cancelUrl,
  }) async {
    final endpoint = _baseUrl.resolve('create-checkout-session');
    http.Response response;
    final effectiveTier = tier == null || tier.isEmpty ? planTier : tier;
    final effectiveInterval = interval == null || interval.isEmpty
        ? billingInterval
        : interval;

    final webAppUrl = ReleaseRuntimeConfig.resolveWebAppBaseUri(
      projectId: projectId,
    );
    final nativeRedirectUrl = ReleaseRuntimeConfig.resolveRedirectUri(
      projectId: projectId,
    );

    // We can't use dart:html here easily to get current location without conditional imports,
    // so we'll default to the known production URL for the web app.
    final String effectiveSuccessUrl = successUrl?.trim().isNotEmpty == true
        ? successUrl!.trim()
        : (kIsWeb ? webAppUrl.toString() : nativeRedirectUrl.toString());
    final String effectiveCancelUrl = cancelUrl?.trim().isNotEmpty == true
        ? cancelUrl!.trim()
        : (kIsWeb
              ? webAppUrl.toString()
              : ReleaseRuntimeConfig.defaultNativeCancelUrl);

    String? normalizedTheme;
    if (checkoutTheme != null) {
      final candidate = checkoutTheme.trim().toLowerCase();
      if (candidate == 'dark' || candidate == 'light') {
        normalizedTheme = candidate;
      }
    }
    final requestedUiMode = _normalizeUiMode(uiMode);

    try {
      response = await _client.post(
        endpoint,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'uid': uid,
          'tier': effectiveTier,
          'interval': effectiveInterval,
          'email': email,
          'successUrl': effectiveSuccessUrl,
          'cancelUrl': effectiveCancelUrl,
          'uiMode': requestedUiMode,
          if (normalizedTheme != null) 'theme': normalizedTheme,
          if (idToken != null && idToken.isNotEmpty) 'idToken': idToken,
        }),
      );
    } on Exception {
      throw const StripeCheckoutException(
        'Unable to reach the checkout service. Check your connection and try again.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StripeCheckoutException(
        'Checkout service responded with status ${response.statusCode}. Please try again.',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const StripeCheckoutException(
        'Checkout service returned an unexpected response. Please try again later.',
      );
    }

    if (decoded is! Map<String, dynamic>) {
      throw const StripeCheckoutException(
        'Checkout service response was not understood. Please try again later.',
      );
    }

    final dynamic urlValue = decoded['url'] ?? decoded['checkoutUrl'];
    final dynamic clientSecretValue = decoded['clientSecret'];
    final responseUiModeValue = (decoded['uiMode'] as String?)
        ?.trim()
        .toLowerCase();
    final resolvedUiMode = _normalizeUiMode(
      responseUiModeValue == null || responseUiModeValue.isEmpty
          ? requestedUiMode
          : responseUiModeValue,
    );

    Uri? checkoutUri;
    if (urlValue is String && urlValue.isNotEmpty) {
      checkoutUri = Uri.tryParse(urlValue);
      if (checkoutUri == null) {
        throw const StripeCheckoutException(
          'The secure checkout destination was invalid. Try again later.',
        );
      }
    }

    final clientSecret =
        clientSecretValue is String && clientSecretValue.isNotEmpty
        ? clientSecretValue
        : null;

    final requiresClientSecret =
        resolvedUiMode == 'embedded' || resolvedUiMode == 'custom';
    if (requiresClientSecret &&
        (clientSecret == null || clientSecret.isEmpty)) {
      throw const StripeCheckoutException(
        'Stripe checkout client secret is missing from the server response.',
      );
    }

    if (resolvedUiMode == 'hosted' && checkoutUri == null) {
      throw const StripeCheckoutException(
        'Stripe checkout URL was missing from the server response.',
      );
    }

    return StripeCheckoutLaunch(
      checkoutUri: checkoutUri,
      clientSecret: clientSecret,
      uiMode: resolvedUiMode,
    );
  }

  String _normalizeUiMode(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'embedded' || normalized == 'custom') {
      return normalized;
    }
    return 'hosted';
  }
}

class DisabledStripeCheckoutApi extends StripeCheckoutApi {
  const DisabledStripeCheckoutApi();

  @override
  Future<StripeCheckoutLaunch> createCheckoutSession({
    required String uid,
    required String email,
    String? tier,
    String? interval,
    String? idToken,
    String? checkoutTheme,
    String uiMode = 'hosted',
    String? successUrl,
    String? cancelUrl,
  }) {
    throw const StripeCheckoutException(
      'Stripe checkout is not configured. Provide a backend endpoint (for example, a Firebase Function) that creates checkout sessions and inject it into CloudStorageApp.',
    );
  }

  @override
  String? get checkoutServiceBaseUrl => null;
}

class StripeCheckoutException implements Exception {
  const StripeCheckoutException(this.message);

  final String message;

  @override
  String toString() => 'StripeCheckoutException';
}
