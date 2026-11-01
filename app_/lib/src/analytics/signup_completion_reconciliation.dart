import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'growth_analytics.dart';

const String pendingSignupCompletionPreferenceKey =
    'ronikcloud.growth.signup_completion.pending.v1';

typedef SignupCompletionTokenProvider = Future<String?> Function();
typedef SignupCompletionProfileReadiness = Future<bool> Function();
typedef SignupCompletionDelay = Future<void> Function(Duration duration);
typedef SignupCompletionSubmitter =
    Future<AuthenticatedSignupCompletionResult> Function({
      required String idToken,
      required GrowthChannel channel,
      required GrowthEntryPage entryPage,
      required GrowthCtaPlacement ctaPlacement,
      required GrowthAuthMethod authMethod,
    });

Future<void> _defaultSignupCompletionDelay(Duration duration) =>
    Future<void>.delayed(duration);

/// The single, bounded local retry marker for an account-signup outcome.
///
/// This value deliberately excludes account identifiers, email addresses,
/// tokens, sources, URLs, raw campaign values, and visitor/session identifiers.
/// The Firebase account creation instant is the only account-binding value the
/// marker retains.
class PendingSignupCompletion {
  const PendingSignupCompletion({
    required this.channel,
    required this.entryPage,
    required this.ctaPlacement,
    required this.authMethod,
    required this.accountCreatedAt,
  });

  static const int schemaVersion = 1;
  static const int maximumEncodedBytes = 512;

  final GrowthChannel channel;
  final GrowthEntryPage entryPage;
  final GrowthCtaPlacement ctaPlacement;
  final GrowthAuthMethod authMethod;
  final DateTime accountCreatedAt;

  DateTime get normalizedAccountCreatedAt =>
      DateTime.fromMillisecondsSinceEpoch(
        accountCreatedAt.toUtc().millisecondsSinceEpoch,
        isUtc: true,
      );

  Map<String, Object> toJson() => <String, Object>{
    'schema_version': schemaVersion,
    'channel': channel.wireName,
    'entry_page': entryPage.wireName,
    'cta_placement': ctaPlacement.wireName,
    'auth_method': authMethod.wireName,
    'account_created_at': normalizedAccountCreatedAt.toIso8601String(),
  };

  String encode() {
    final encoded = jsonEncode(toJson());
    if (encoded.length > maximumEncodedBytes) {
      throw StateError('The signup completion marker is not bounded.');
    }
    return encoded;
  }

  bool isForAccountCreatedAt(DateTime? creationTime) {
    if (creationTime == null) {
      return false;
    }
    return normalizedAccountCreatedAt.millisecondsSinceEpoch ==
        creationTime.toUtc().millisecondsSinceEpoch;
  }

  bool hasSamePayload(PendingSignupCompletion other) {
    return channel == other.channel &&
        entryPage == other.entryPage &&
        ctaPlacement == other.ctaPlacement &&
        authMethod == other.authMethod &&
        normalizedAccountCreatedAt.millisecondsSinceEpoch ==
            other.normalizedAccountCreatedAt.millisecondsSinceEpoch;
  }

  static PendingSignupCompletion? tryDecode(String? value) {
    if (value == null || value.isEmpty || value.length > maximumEncodedBytes) {
      return null;
    }
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map<String, dynamic> ||
          decoded.length != 6 ||
          decoded['schema_version'] != schemaVersion) {
        return null;
      }
      const expectedKeys = <String>{
        'schema_version',
        'channel',
        'entry_page',
        'cta_placement',
        'auth_method',
        'account_created_at',
      };
      if (decoded.keys.any((key) => !expectedKeys.contains(key))) {
        return null;
      }
      final channel = _growthChannelByWireName(decoded['channel']);
      final entryPage = _growthEntryPageByWireName(decoded['entry_page']);
      final ctaPlacement = _growthCtaPlacementByWireName(
        decoded['cta_placement'],
      );
      final authMethod = _growthAuthMethodByWireName(decoded['auth_method']);
      final timestamp = decoded['account_created_at'];
      if (channel == null ||
          entryPage == null ||
          ctaPlacement == null ||
          authMethod == null ||
          timestamp is! String) {
        return null;
      }
      final accountCreatedAt = DateTime.tryParse(timestamp);
      if (accountCreatedAt == null || !accountCreatedAt.isUtc) {
        return null;
      }
      final normalizedTimestamp = DateTime.fromMillisecondsSinceEpoch(
        accountCreatedAt.millisecondsSinceEpoch,
        isUtc: true,
      ).toIso8601String();
      if (timestamp != normalizedTimestamp) {
        return null;
      }
      return PendingSignupCompletion(
        channel: channel,
        entryPage: entryPage,
        ctaPlacement: ctaPlacement,
        authMethod: authMethod,
        accountCreatedAt: accountCreatedAt,
      );
    } on FormatException {
      return null;
    }
  }
}

GrowthChannel? _growthChannelByWireName(Object? value) {
  if (value is! String) return null;
  for (final candidate in GrowthChannel.values) {
    if (candidate.wireName == value) return candidate;
  }
  return null;
}

GrowthEntryPage? _growthEntryPageByWireName(Object? value) {
  if (value is! String) return null;
  for (final candidate in GrowthEntryPage.values) {
    if (candidate.wireName == value) return candidate;
  }
  return null;
}

GrowthCtaPlacement? _growthCtaPlacementByWireName(Object? value) {
  if (value is! String) return null;
  for (final candidate in GrowthCtaPlacement.values) {
    if (candidate.wireName == value) return candidate;
  }
  return null;
}

GrowthAuthMethod? _growthAuthMethodByWireName(Object? value) {
  if (value is! String) return null;
  for (final candidate in GrowthAuthMethod.values) {
    if (candidate.wireName == value) return candidate;
  }
  return null;
}

abstract class PendingSignupCompletionStore {
  Future<PendingSignupCompletion?> read();

  Future<bool> write(PendingSignupCompletion pending);

  Future<bool> clearIfMatches(PendingSignupCompletion pending);
}

class SharedPreferencesPendingSignupCompletionStore
    implements PendingSignupCompletionStore {
  SharedPreferencesPendingSignupCompletionStore({
    Future<SharedPreferences> Function()? preferencesLoader,
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _preferencesLoader;
  Future<void> _operationTail = Future<void>.value();

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _operationTail = _operationTail.then((_) async {
      try {
        completer.complete(await operation());
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  @override
  Future<PendingSignupCompletion?> read() => _serialized(() async {
    final preferences = await _preferencesLoader();
    return PendingSignupCompletion.tryDecode(
      preferences.getString(pendingSignupCompletionPreferenceKey),
    );
  });

  @override
  Future<bool> write(PendingSignupCompletion pending) => _serialized(() async {
    final preferences = await _preferencesLoader();
    return preferences.setString(
      pendingSignupCompletionPreferenceKey,
      pending.encode(),
    );
  });

  @override
  Future<bool> clearIfMatches(PendingSignupCompletion pending) =>
      _serialized(() async {
        final preferences = await _preferencesLoader();
        final current = PendingSignupCompletion.tryDecode(
          preferences.getString(pendingSignupCompletionPreferenceKey),
        );
        if (current == null || !current.hasSamePayload(pending)) {
          return false;
        }
        return preferences.remove(pendingSignupCompletionPreferenceKey);
      });
}

class SignupCompletionReconciler {
  SignupCompletionReconciler({
    required PendingSignupCompletionStore store,
    required SignupCompletionSubmitter submitter,
    SignupCompletionDelay delay = _defaultSignupCompletionDelay,
    List<Duration> retryDelays = const <Duration>[
      Duration(milliseconds: 250),
      Duration(milliseconds: 750),
    ],
  }) : _store = store,
       _submitter = submitter,
       _delay = delay,
       retryDelays = List<Duration>.unmodifiable(retryDelays) {
    if (retryDelays.length > 2 ||
        retryDelays.any(
          (duration) =>
              duration.isNegative || duration > const Duration(seconds: 2),
        )) {
      throw ArgumentError.value(
        retryDelays,
        'retryDelays',
        'At most two retry delays of no more than two seconds are allowed.',
      );
    }
  }

  static final SignupCompletionReconciler instance = SignupCompletionReconciler(
    store: SharedPreferencesPendingSignupCompletionStore(),
    submitter:
        ({
          required idToken,
          required channel,
          required entryPage,
          required ctaPlacement,
          required authMethod,
        }) => GrowthAnalytics().submitAuthenticatedSignupCompleted(
          idToken: idToken,
          channel: channel,
          entryPage: entryPage,
          ctaPlacement: ctaPlacement,
          authMethod: authMethod,
        ),
  );

  /// The production sender is unavailable to debug builds and widget tests.
  /// Tests that exercise reconciliation must inject their own reconciler.
  static SignupCompletionReconciler? get runtimeDefault =>
      kReleaseMode ? instance : null;

  final PendingSignupCompletionStore _store;
  final SignupCompletionSubmitter _submitter;
  final SignupCompletionDelay _delay;
  final List<Duration> retryDelays;

  // Exactly one privacy-safe fallback is retained in memory before attempting
  // persistence. If SharedPreferences rejects or throws, this still protects
  // the successful signup for the lifetime of the current process. Process
  // death after a failed persistent write cannot be recovered by this bounded
  // in-memory fallback; the successful product flow remains unaffected.
  PendingSignupCompletion? _volatilePending;
  Future<void>? _activeReconciliation;
  _SignupCompletionReconciliationRequest? _queuedRequest;

  Future<bool> rememberPending({
    required DateTime accountCreatedAt,
    required GrowthChannel channel,
    required GrowthEntryPage entryPage,
    required GrowthCtaPlacement ctaPlacement,
    required GrowthAuthMethod authMethod,
  }) async {
    final pending = PendingSignupCompletion(
      channel: channel,
      entryPage: entryPage,
      ctaPlacement: ctaPlacement,
      authMethod: authMethod,
      accountCreatedAt: accountCreatedAt,
    );
    _volatilePending = pending;
    try {
      return await _store.write(pending);
    } on Object {
      return false;
    }
  }

  /// Reconciles in the background with at most three attempts per request.
  ///
  /// Concurrent callers share one active operation. A single latest request is
  /// queued so a registration-time call can retry after an overlapping startup
  /// call without producing concurrent requests.
  Future<void> reconcile({
    required DateTime? authenticatedAccountCreatedAt,
    required SignupCompletionTokenProvider tokenProvider,
    SignupCompletionProfileReadiness? profileReady,
  }) {
    final request = _SignupCompletionReconciliationRequest(
      authenticatedAccountCreatedAt: authenticatedAccountCreatedAt,
      tokenProvider: tokenProvider,
      profileReady: profileReady,
    );
    final active = _activeReconciliation;
    if (active != null) {
      _queuedRequest = request;
      return active;
    }
    final operation = _drain(request);
    _activeReconciliation = operation;
    return operation;
  }

  Future<void> _drain(
    _SignupCompletionReconciliationRequest initialRequest,
  ) async {
    try {
      var request = initialRequest;
      while (true) {
        await _reconcileOnce(request);
        final queued = _queuedRequest;
        _queuedRequest = null;
        if (queued == null) {
          return;
        }
        request = queued;
      }
    } finally {
      _activeReconciliation = null;
    }
  }

  Future<void> _reconcileOnce(
    _SignupCompletionReconciliationRequest request,
  ) async {
    PendingSignupCompletion? persistentPending;
    try {
      persistentPending = await _store.read();
    } on Object {
      persistentPending = null;
    }
    final volatilePending = _volatilePending;
    final pending =
        persistentPending?.isForAccountCreatedAt(
              request.authenticatedAccountCreatedAt,
            ) ==
            true
        ? persistentPending
        : volatilePending?.isForAccountCreatedAt(
                request.authenticatedAccountCreatedAt,
              ) ==
              true
        ? volatilePending
        : null;
    if (pending == null) {
      return;
    }

    final maximumAttempts = retryDelays.length + 1;
    for (var attempt = 0; attempt < maximumAttempts; attempt += 1) {
      if (attempt > 0) {
        await _delay(retryDelays[attempt - 1]);
      }

      if (request.profileReady != null) {
        var ready = false;
        try {
          ready = await request.profileReady!();
        } on Object {
          ready = false;
        }
        if (!ready) {
          continue;
        }
      }

      String? token;
      try {
        token = await request.tokenProvider();
      } on Object {
        token = null;
      }
      if (token == null || token.trim().isEmpty) {
        continue;
      }

      AuthenticatedSignupCompletionResult result;
      try {
        result = await _submitter(
          idToken: token,
          channel: pending.channel,
          entryPage: pending.entryPage,
          ctaPlacement: pending.ctaPlacement,
          authMethod: pending.authMethod,
        );
      } on Object {
        result = AuthenticatedSignupCompletionResult.retryable;
      }
      if (result != AuthenticatedSignupCompletionResult.confirmed) {
        continue;
      }
      try {
        await _store.clearIfMatches(pending);
      } on Object {
        // A failed local delete remains safe and will be server-deduplicated on
        // the next startup. No product flow should fail because of analytics.
      }
      if (_volatilePending?.hasSamePayload(pending) == true) {
        _volatilePending = null;
      }
      return;
    }
  }
}

class _SignupCompletionReconciliationRequest {
  const _SignupCompletionReconciliationRequest({
    required this.authenticatedAccountCreatedAt,
    required this.tokenProvider,
    required this.profileReady,
  });

  final DateTime? authenticatedAccountCreatedAt;
  final SignupCompletionTokenProvider tokenProvider;
  final SignupCompletionProfileReadiness? profileReady;
}
