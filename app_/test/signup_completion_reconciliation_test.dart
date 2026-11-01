import 'dart:async';
import 'dart:convert';

import 'package:cloud_storage/src/analytics/growth_analytics.dart';
import 'package:cloud_storage/src/analytics/signup_completion_reconciliation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const attribution = (
    channel: GrowthChannel.linkedin,
    entryPage: GrowthEntryPage.secureCloudStorage,
    ctaPlacement: GrowthCtaPlacement.hero,
    authMethod: GrowthAuthMethod.emailPassword,
  );
  final createdAt = DateTime.utc(2026, 8, 12, 10, 11, 12, 345);

  late SharedPreferences preferences;
  late SharedPreferencesPendingSignupCompletionStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    preferences = await SharedPreferences.getInstance();
    store = SharedPreferencesPendingSignupCompletionStore(
      preferencesLoader: () async => preferences,
    );
  });

  Future<bool> remember(SignupCompletionReconciler reconciler) {
    return reconciler.rememberPending(
      accountCreatedAt: createdAt,
      channel: attribution.channel,
      entryPage: attribution.entryPage,
      ctaPlacement: attribution.ctaPlacement,
      authMethod: attribution.authMethod,
    );
  }

  test(
    'persists one bounded marker containing only fixed privacy-safe fields',
    () async {
      final reconciler = SignupCompletionReconciler(
        store: store,
        retryDelays: const <Duration>[],
        submitter:
            ({
              required idToken,
              required channel,
              required entryPage,
              required ctaPlacement,
              required authMethod,
            }) async => AuthenticatedSignupCompletionResult.retryable,
      );

      expect(await remember(reconciler), isTrue);
      final encoded = preferences.getString(
        pendingSignupCompletionPreferenceKey,
      );
      expect(encoded, isNotNull);
      expect(encoded!.length, lessThanOrEqualTo(512));
      final marker = jsonDecode(encoded) as Map<String, dynamic>;
      expect(marker, <String, dynamic>{
        'schema_version': 1,
        'channel': 'linkedin',
        'entry_page': 'secure_cloud_storage',
        'cta_placement': 'hero',
        'auth_method': 'email_password',
        'account_created_at': '2026-08-12T10:11:12.345Z',
      });
      for (final forbidden in <String>[
        '"uid":',
        '"email":',
        '"token":',
        '"source":',
        '"raw_utm":',
        '"url":',
        '"session_id":',
      ]) {
        expect(encoded.toLowerCase(), isNot(contains(forbidden)));
      }
    },
  );

  test(
    'a different authenticated account creation time cannot inherit marker',
    () async {
      var submitCalls = 0;
      final reconciler = SignupCompletionReconciler(
        store: store,
        retryDelays: const <Duration>[],
        submitter:
            ({
              required idToken,
              required channel,
              required entryPage,
              required ctaPlacement,
              required authMethod,
            }) async {
              submitCalls += 1;
              return AuthenticatedSignupCompletionResult.confirmed;
            },
      );
      await remember(reconciler);

      await reconciler.reconcile(
        authenticatedAccountCreatedAt: createdAt.add(
          const Duration(milliseconds: 1),
        ),
        tokenProvider: () async => 'token-for-another-account',
      );

      expect(submitCalls, 0);
      expect(await store.read(), isNotNull);
    },
  );

  test(
    'write false falls back to one volatile marker and clears on proof',
    () async {
      final controlledStore = _ControlledPendingStore(writeResult: false);
      var submitCalls = 0;
      final reconciler = SignupCompletionReconciler(
        store: controlledStore,
        retryDelays: const <Duration>[],
        submitter:
            ({
              required idToken,
              required channel,
              required entryPage,
              required ctaPlacement,
              required authMethod,
            }) async {
              submitCalls += 1;
              return AuthenticatedSignupCompletionResult.confirmed;
            },
      );

      expect(await remember(reconciler), isFalse);
      expect(controlledStore.persisted, isNull);
      await reconciler.reconcile(
        authenticatedAccountCreatedAt: createdAt,
        tokenProvider: () async => 'firebase-token',
      );
      await reconciler.reconcile(
        authenticatedAccountCreatedAt: createdAt,
        tokenProvider: () async => 'firebase-token',
      );

      expect(submitCalls, 1);
      expect(controlledStore.clearCalls, 1);
    },
  );

  test(
    'thrown writes and reads use the volatile marker for this process',
    () async {
      final controlledStore = _ControlledPendingStore(
        throwOnWrite: true,
        throwOnRead: true,
      );
      var submitCalls = 0;
      final reconciler = SignupCompletionReconciler(
        store: controlledStore,
        retryDelays: const <Duration>[],
        submitter:
            ({
              required idToken,
              required channel,
              required entryPage,
              required ctaPlacement,
              required authMethod,
            }) async {
              submitCalls += 1;
              return AuthenticatedSignupCompletionResult.confirmed;
            },
      );

      expect(await remember(reconciler), isFalse);
      await reconciler.reconcile(
        authenticatedAccountCreatedAt: createdAt,
        tokenProvider: () async => 'firebase-token',
      );
      await reconciler.reconcile(
        authenticatedAccountCreatedAt: createdAt,
        tokenProvider: () async => 'firebase-token',
      );

      expect(submitCalls, 1);
    },
  );

  test(
    'old persistent account cannot block a matching volatile account',
    () async {
      final oldCreatedAt = createdAt.subtract(const Duration(days: 1));
      final oldPending = PendingSignupCompletion(
        channel: GrowthChannel.reddit,
        entryPage: GrowthEntryPage.home,
        ctaPlacement: GrowthCtaPlacement.direct,
        authMethod: GrowthAuthMethod.emailPassword,
        accountCreatedAt: oldCreatedAt,
      );
      final controlledStore = _ControlledPendingStore(
        writeResult: false,
        persisted: oldPending,
      );
      PendingSignupCompletion? submitted;
      final reconciler = SignupCompletionReconciler(
        store: controlledStore,
        retryDelays: const <Duration>[],
        submitter:
            ({
              required idToken,
              required channel,
              required entryPage,
              required ctaPlacement,
              required authMethod,
            }) async {
              submitted = PendingSignupCompletion(
                channel: channel,
                entryPage: entryPage,
                ctaPlacement: ctaPlacement,
                authMethod: authMethod,
                accountCreatedAt: createdAt,
              );
              return AuthenticatedSignupCompletionResult.confirmed;
            },
      );

      expect(await remember(reconciler), isFalse);
      await reconciler.reconcile(
        authenticatedAccountCreatedAt: createdAt,
        tokenProvider: () async => 'firebase-token',
      );

      expect(submitted, isNotNull);
      expect(submitted!.channel, attribution.channel);
      expect(submitted!.accountCreatedAt, createdAt);
      expect(controlledStore.persisted, same(oldPending));
    },
  );

  test(
    'volatile mismatch is retained and never submitted to another account',
    () async {
      final controlledStore = _ControlledPendingStore(writeResult: false);
      var submitCalls = 0;
      final reconciler = SignupCompletionReconciler(
        store: controlledStore,
        retryDelays: const <Duration>[],
        submitter:
            ({
              required idToken,
              required channel,
              required entryPage,
              required ctaPlacement,
              required authMethod,
            }) async {
              submitCalls += 1;
              return AuthenticatedSignupCompletionResult.confirmed;
            },
      );
      await remember(reconciler);

      await reconciler.reconcile(
        authenticatedAccountCreatedAt: createdAt.add(
          const Duration(milliseconds: 1),
        ),
        tokenProvider: () async => 'other-account-token',
      );
      expect(submitCalls, 0);
      await reconciler.reconcile(
        authenticatedAccountCreatedAt: createdAt,
        tokenProvider: () async => 'firebase-token',
      );
      expect(submitCalls, 1);
    },
  );

  test(
    'unconfirmed server outcomes never clear the volatile fallback',
    () async {
      final controlledStore = _ControlledPendingStore(writeResult: false);
      var result = AuthenticatedSignupCompletionResult.retryable;
      var submitCalls = 0;
      final reconciler = SignupCompletionReconciler(
        store: controlledStore,
        retryDelays: const <Duration>[],
        submitter:
            ({
              required idToken,
              required channel,
              required entryPage,
              required ctaPlacement,
              required authMethod,
            }) async {
              submitCalls += 1;
              return result;
            },
      );
      await remember(reconciler);

      await reconciler.reconcile(
        authenticatedAccountCreatedAt: createdAt,
        tokenProvider: () async => 'firebase-token',
      );
      await reconciler.reconcile(
        authenticatedAccountCreatedAt: createdAt,
        tokenProvider: () async => 'firebase-token',
      );
      expect(submitCalls, 2);
      expect(controlledStore.clearCalls, 0);

      result = AuthenticatedSignupCompletionResult.confirmed;
      await reconciler.reconcile(
        authenticatedAccountCreatedAt: createdAt,
        tokenProvider: () async => 'firebase-token',
      );
      await reconciler.reconcile(
        authenticatedAccountCreatedAt: createdAt,
        tokenProvider: () async => 'firebase-token',
      );
      expect(submitCalls, 3);
      expect(controlledStore.clearCalls, 1);
    },
  );

  test(
    'retries with short bounded backoff and clears after confirmed success',
    () async {
      var submitCalls = 0;
      final delays = <Duration>[];
      final reconciler = SignupCompletionReconciler(
        store: store,
        retryDelays: const <Duration>[
          Duration(milliseconds: 250),
          Duration(milliseconds: 750),
        ],
        delay: (duration) async => delays.add(duration),
        submitter:
            ({
              required idToken,
              required channel,
              required entryPage,
              required ctaPlacement,
              required authMethod,
            }) async {
              submitCalls += 1;
              expect(idToken, 'firebase-token');
              expect(channel, attribution.channel);
              expect(entryPage, attribution.entryPage);
              expect(ctaPlacement, attribution.ctaPlacement);
              expect(authMethod, attribution.authMethod);
              return submitCalls == 3
                  ? AuthenticatedSignupCompletionResult.confirmed
                  : AuthenticatedSignupCompletionResult.retryable;
            },
      );
      await remember(reconciler);

      await reconciler.reconcile(
        authenticatedAccountCreatedAt: createdAt,
        tokenProvider: () async => 'firebase-token',
      );

      expect(submitCalls, 3);
      expect(delays, const <Duration>[
        Duration(milliseconds: 250),
        Duration(milliseconds: 750),
      ]);
      expect(await store.read(), isNull);
    },
  );

  test(
    'blank tokens and profile-not-ready outcomes retain the marker',
    () async {
      var submitCalls = 0;
      var readinessChecks = 0;
      final reconciler = SignupCompletionReconciler(
        store: store,
        retryDelays: const <Duration>[Duration.zero, Duration.zero],
        delay: (_) async {},
        submitter:
            ({
              required idToken,
              required channel,
              required entryPage,
              required ctaPlacement,
              required authMethod,
            }) async {
              submitCalls += 1;
              return AuthenticatedSignupCompletionResult.confirmed;
            },
      );
      await remember(reconciler);

      await reconciler.reconcile(
        authenticatedAccountCreatedAt: createdAt,
        tokenProvider: () async => 'firebase-token',
        profileReady: () async {
          readinessChecks += 1;
          return false;
        },
      );
      expect(readinessChecks, 3);
      expect(submitCalls, 0);
      expect(await store.read(), isNotNull);

      await reconciler.reconcile(
        authenticatedAccountCreatedAt: createdAt,
        tokenProvider: () async => '   ',
      );
      expect(submitCalls, 0);
      expect(await store.read(), isNotNull);
    },
  );

  test('network-like submitter failures retain the marker', () async {
    var submitCalls = 0;
    final reconciler = SignupCompletionReconciler(
      store: store,
      retryDelays: const <Duration>[Duration.zero, Duration.zero],
      delay: (_) async {},
      submitter:
          ({
            required idToken,
            required channel,
            required entryPage,
            required ctaPlacement,
            required authMethod,
          }) async {
            submitCalls += 1;
            throw StateError('offline');
          },
    );
    await remember(reconciler);

    await reconciler.reconcile(
      authenticatedAccountCreatedAt: createdAt,
      tokenProvider: () async => 'firebase-token',
    );

    expect(submitCalls, 3);
    expect(await store.read(), isNotNull);
  });

  test(
    'overlapping startup and registration calls never submit concurrently',
    () async {
      final firstSubmission = Completer<AuthenticatedSignupCompletionResult>();
      var activeSubmissions = 0;
      var maximumActiveSubmissions = 0;
      var submitCalls = 0;
      final reconciler = SignupCompletionReconciler(
        store: store,
        retryDelays: const <Duration>[],
        submitter:
            ({
              required idToken,
              required channel,
              required entryPage,
              required ctaPlacement,
              required authMethod,
            }) async {
              submitCalls += 1;
              activeSubmissions += 1;
              maximumActiveSubmissions =
                  activeSubmissions > maximumActiveSubmissions
                  ? activeSubmissions
                  : maximumActiveSubmissions;
              final result = submitCalls == 1
                  ? await firstSubmission.future
                  : AuthenticatedSignupCompletionResult.confirmed;
              activeSubmissions -= 1;
              return result;
            },
      );
      await remember(reconciler);

      final startup = reconciler.reconcile(
        authenticatedAccountCreatedAt: createdAt,
        tokenProvider: () async => 'firebase-token',
      );
      await Future<void>.delayed(Duration.zero);
      final registration = reconciler.reconcile(
        authenticatedAccountCreatedAt: createdAt,
        tokenProvider: () async => 'firebase-token',
      );
      expect(identical(startup, registration), isTrue);
      expect(submitCalls, 1);

      firstSubmission.complete(AuthenticatedSignupCompletionResult.retryable);
      await startup;

      expect(submitCalls, 2);
      expect(maximumActiveSubmissions, 1);
      expect(await store.read(), isNull);
    },
  );

  test('runtime default is disabled in debug and test builds', () {
    expect(SignupCompletionReconciler.runtimeDefault, isNull);
  });
}

class _ControlledPendingStore implements PendingSignupCompletionStore {
  _ControlledPendingStore({
    this.writeResult = true,
    this.throwOnWrite = false,
    this.throwOnRead = false,
    this.persisted,
  });

  final bool writeResult;
  final bool throwOnWrite;
  final bool throwOnRead;
  PendingSignupCompletion? persisted;
  int clearCalls = 0;

  @override
  Future<bool> clearIfMatches(PendingSignupCompletion candidate) async {
    clearCalls += 1;
    if (persisted?.hasSamePayload(candidate) != true) {
      return false;
    }
    persisted = null;
    return true;
  }

  @override
  Future<PendingSignupCompletion?> read() async {
    if (throwOnRead) {
      throw StateError('read failed');
    }
    return persisted;
  }

  @override
  Future<bool> write(PendingSignupCompletion candidate) async {
    if (throwOnWrite) {
      throw StateError('write failed');
    }
    if (writeResult) {
      persisted = candidate;
    }
    return writeResult;
  }
}
