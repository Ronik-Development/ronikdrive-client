import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math' as math;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'checkout_webview_page.dart';
import 'checkout_plan_intent.dart';
import 'storage_upgrade_page.dart';

import '../authentication/account_identity.dart';
import '../authentication/login_page.dart';
import '../authentication/login_password_vault.dart';
import '../home/workspace_home_page.dart';
import '../security/encryption_setup_service.dart';
import '../shared/app_page_title.dart';
import '../shared/founding_user_perks.dart';
import '../shared/release_runtime_config.dart';
import '../shared/service_environment.dart';
import '../shared/user_facing_client_failure.dart';
import 'apple_subscription_page.dart';
import 'google_play_subscription_page.dart';
import 'google_play_purchase_service.dart';
import 'billing_channel.dart';
import 'subscription_coordinator.dart';
import 'web_checkout_launcher_stub.dart'
    if (dart.library.html) 'web_checkout_launcher_html.dart'
    as web_checkout_launcher;

const String _stripePaymentRetentionDisclosure =
    'Stripe securely handles payment details. RonikCloud never receives or '
    'stores your full card number or CVC. Auto-renewing subscriptions require '
    'Stripe to retain a reusable payment credential. If checkout is abandoned '
    'before confirmation, no RonikCloud subscription or charge is created. '
    'Stripe may still process the checkout session and any payment input under '
    'its privacy policy. Cancellation stops future renewal; '
    'deleting your RonikCloud account does not create a refund.';

bool _isRecoverableFirestoreSessionError(Object? error) {
  if (error is! FirebaseException) {
    return false;
  }

  final code = error.code.toLowerCase();
  if (code == 'permission-denied' || code == 'unauthenticated') {
    return true;
  }

  final message = error.message?.toLowerCase() ?? '';
  return message.contains('permission denied') ||
      message.contains('insufficient permissions') ||
      (message.contains('auth') && message.contains('token'));
}

Future<void> _refreshFirestoreSession({
  required FirebaseAuth auth,
  required User user,
}) async {
  final currentUser = auth.currentUser;
  if (currentUser == null || currentUser.uid != user.uid) {
    return;
  }

  try {
    await currentUser.getIdToken(true);
    await Future<void>.delayed(const Duration(milliseconds: 250));
  } catch (_) {
    // Let the caller surface the original error if refresh fails.
  }
}

class SubscriptionGate extends StatefulWidget {
  const SubscriptionGate({
    super.key,
    required this.auth,
    required this.user,
    required this.firestore,
    required this.subscriptionCoordinator,
    this.externalCheckoutEnabled = true,
    this.billingChannel,
    this.googlePlayPurchaseApi,
    this.paidWorkspaceBuilder,
    this.businessMode = false,
  });

  final FirebaseAuth auth;
  final User user;
  final FirebaseFirestore firestore;
  final SubscriptionCoordinator subscriptionCoordinator;
  final bool externalCheckoutEnabled;
  final BillingChannel? billingChannel;
  final GooglePlayPurchaseApi? googlePlayPurchaseApi;
  final Widget Function(SubscriptionState subscription)? paidWorkspaceBuilder;
  final bool businessMode;

  BillingChannel get resolvedBillingChannel =>
      billingChannel ??
      (externalCheckoutEnabled
          ? BillingChannel.stripe
          : BillingChannel.disabled);

  @override
  State<SubscriptionGate> createState() => _SubscriptionGateState();
}

class _SubscriptionGateState extends State<SubscriptionGate> {
  late Stream<SubscriptionState> _subscriptionStream;
  bool _isRecoveringSession = false;
  bool _didAttemptSessionRecovery = false;
  bool _openedRequestedUpgrade = false;

  @override
  void initState() {
    super.initState();
    _subscriptionStream = _createSubscriptionStream();
  }

  @override
  void didUpdateWidget(covariant SubscriptionGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.user.uid != oldWidget.user.uid ||
        widget.subscriptionCoordinator != oldWidget.subscriptionCoordinator) {
      _openedRequestedUpgrade = false;
      _isRecoveringSession = false;
      _didAttemptSessionRecovery = false;
      _subscriptionStream = _createSubscriptionStream();
    }
  }

  Stream<SubscriptionState> _createSubscriptionStream() {
    return (() async* {
      var didRetrySession = false;
      while (true) {
        try {
          yield* widget.subscriptionCoordinator.watchSubscription(
            widget.user.uid,
          );
          return;
        } on FirebaseException catch (error) {
          if (!didRetrySession && _isRecoverableFirestoreSessionError(error)) {
            didRetrySession = true;
            await _refreshFirestoreSession(
              auth: widget.auth,
              user: widget.user,
            );
            continue;
          }
          rethrow;
        }
      }
    })();
  }

  bool _isRecoverableSessionError(Object? error) {
    return _isRecoverableFirestoreSessionError(error);
  }

  String _buildErrorMessage(Object? error) {
    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
        case 'unauthenticated':
          if (_didAttemptSessionRecovery) {
            return 'RonikCloud could not restore the signed-in session automatically. Retry once more or sign out and sign in again.';
          }
          return 'RonikCloud could not verify the current signed-in session.';
        case 'unavailable':
          return userFacingClientFailureMessage(
            UserFacingClientFailure.subscriptionStatus,
          );
      }
    }

    return userFacingClientFailureMessage(
      UserFacingClientFailure.subscriptionStatus,
    );
  }

  void _retrySubscriptionStatus() {
    setState(() {
      _isRecoveringSession = false;
      _didAttemptSessionRecovery = false;
      _subscriptionStream = _createSubscriptionStream();
    });
  }

  Future<void> _recoverSession() async {
    if (_isRecoveringSession || _didAttemptSessionRecovery || !mounted) {
      return;
    }

    setState(() {
      _isRecoveringSession = true;
    });

    try {
      await _refreshFirestoreSession(auth: widget.auth, user: widget.user);
    } catch (_) {
      // If the refresh fails, the rebuilt stream below will surface the
      // original error with a clearer session-specific message.
    } finally {
      if (mounted) {
        setState(() {
          _isRecoveringSession = false;
          _didAttemptSessionRecovery = true;
          _subscriptionStream = _createSubscriptionStream();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SubscriptionState>(
      stream: _subscriptionStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting ||
            _isRecoveringSession) {
          return _SubscriptionLoadingView(
            message: _isRecoveringSession
                ? 'Restoring your workspace session...'
                : null,
          );
        }

        if (snapshot.hasError) {
          if (_isRecoverableSessionError(snapshot.error) &&
              !_didAttemptSessionRecovery) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _recoverSession();
            });
            return const _SubscriptionLoadingView(
              message: 'Restoring your workspace session...',
            );
          }

          return _SubscriptionErrorView(
            message: _buildErrorMessage(snapshot.error),
            onRetry: _retrySubscriptionStatus,
            onSignOut: () {
              LoginPasswordVault.instance.clear();
              widget.auth.signOut();
            },
          );
        }

        final subscription = snapshot.data;
        if (subscription == null) {
          return _SubscriptionLoadingView.withoutSpinner(
            onSignOut: () {
              LoginPasswordVault.instance.clear();
              widget.auth.signOut();
            },
          );
        }

        if (!subscription.exists) {
          return _ProfilePendingView(
            user: widget.user,
            firestore: widget.firestore,
            onSignOut: () {
              LoginPasswordVault.instance.clear();
              widget.auth.signOut();
            },
          );
        }

        if (!widget.businessMode &&
            widget.resolvedBillingChannel.allowsRegistration &&
            subscription.needsRegistrationCompletion) {
          return LoginPage(
            key: ValueKey('complete-setup-${widget.user.uid}'),
            auth: widget.auth,
            firestore: widget.firestore,
            initialRegisterMode: true,
            completeSetupMode: true,
          );
        }

        // Company billing is configured after creating the company. Do not
        // require an unrelated Personal subscription before that can happen.
        if (widget.businessMode &&
            widget.resolvedBillingChannel.usesStripe &&
            widget.paidWorkspaceBuilder != null) {
          return widget.paidWorkspaceBuilder!(subscription);
        }

        if (subscription.hasWorkspaceAccess &&
            (!widget.businessMode || subscription.isPaid)) {
          if (subscription.isFree &&
              !widget.businessMode &&
              widget.resolvedBillingChannel != BillingChannel.disabled &&
              !_openedRequestedUpgrade &&
              CheckoutPlanIntentStore.instance.pending != null) {
            _openedRequestedUpgrade = true;
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              if (!mounted) return;
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => StorageUpgradePage(
                    auth: widget.auth,
                    user: widget.user,
                    coordinator: widget.subscriptionCoordinator,
                    billingChannel: widget.resolvedBillingChannel,
                    initialSubscription: subscription,
                  ),
                ),
              );
              CheckoutPlanIntentStore.instance.clear();
            });
          }
          final builder = widget.paidWorkspaceBuilder;
          if (builder != null) {
            return builder(subscription);
          }
          return WorkspaceHomePage(
            auth: widget.auth,
            user: widget.user,
            firestore: widget.firestore,
            billingChannel: widget.resolvedBillingChannel,
          );
        }

        if (widget.resolvedBillingChannel.usesAppStore) {
          return AppleSubscriptionPage(auth: widget.auth);
        }
        if (widget.resolvedBillingChannel.usesGooglePlay) {
          return GooglePlaySubscriptionPage(
            key: ValueKey('play-subscriptions-${widget.user.uid}'),
            auth: widget.auth,
            purchaseApi: widget.googlePlayPurchaseApi,
          );
        }

        return SubscriptionPaywallPage(
          auth: widget.auth,
          user: widget.user,
          subscription: subscription,
          coordinator: widget.subscriptionCoordinator,
          externalCheckoutEnabled: widget.resolvedBillingChannel.usesStripe,
          businessMode: widget.businessMode,
        );
      },
    );
  }
}

class _SubscriptionLoadingView extends StatelessWidget {
  const _SubscriptionLoadingView({this.message});

  final String? message;

  factory _SubscriptionLoadingView.withoutSpinner({
    required VoidCallback onSignOut,
  }) {
    return _SubscriptionLoadingFallback(onSignOut: onSignOut);
  }

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
              'Preparing your workspace subscription…',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _SubscriptionLoadingFallback extends _SubscriptionLoadingView {
  const _SubscriptionLoadingFallback({required this.onSignOut});

  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'We are finalising your workspace profile…',
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'If this takes longer than a minute, sign out and sign back in to retry.',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: onSignOut,
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SubscriptionErrorView extends StatelessWidget {
  const _SubscriptionErrorView({
    required this.message,
    required this.onRetry,
    required this.onSignOut,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline,
                    color: theme.colorScheme.error,
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Billing status unavailable',
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
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: onSignOut,
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfilePendingView extends StatefulWidget {
  const _ProfilePendingView({
    required this.user,
    required this.firestore,
    required this.onSignOut,
  });

  final User user;
  final FirebaseFirestore firestore;
  final VoidCallback onSignOut;

  @override
  State<_ProfilePendingView> createState() => _ProfilePendingViewState();
}

class _ProfilePendingViewState extends State<_ProfilePendingView> {
  bool _isProvisioning = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _provisionUserDocumentIfMissing();
  }

  Future<void> _provisionUserDocumentIfMissing() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _isProvisioning = true;
      _errorMessage = null;
    });

    final email = widget.user.email?.trim() ?? '';
    if (email.isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isProvisioning = false;
        _errorMessage =
            'Your account email is unavailable, so profile provisioning cannot continue. Sign out and sign in again.';
      });
      return;
    }

    final doc = widget.firestore.collection('users').doc(widget.user.uid);
    final auth = FirebaseAuth.instanceFor(app: widget.firestore.app);
    final encryptionSetup = EncryptionSetupService.forApp(widget.firestore.app);
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await _refreshFirestoreSession(auth: auth, user: widget.user);

        final snapshot = await doc.get();
        if (snapshot.exists) {
          if (!mounted) {
            return;
          }
          setState(() {
            _isProvisioning = false;
            _errorMessage = null;
          });
          return;
        }

        await encryptionSetup.ensureStandardEncryptionSalt();

        final provisioned = await doc.get();
        if (!provisioned.exists) {
          throw const EncryptionSetupException(
            'The profile setup service completed without creating your profile. Please retry.',
          );
        }
        if (!mounted) {
          return;
        }
        setState(() {
          _isProvisioning = false;
          _errorMessage = null;
        });
        return;
      } on FirebaseException catch (error) {
        lastError = error;
        if (attempt < 2 && _isRecoverableFirestoreSessionError(error)) {
          continue;
        }
        break;
      } on EncryptionSetupException catch (error) {
        lastError = error;
        if (attempt < 2) {
          continue;
        }
        break;
      } catch (error) {
        lastError = error;
        break;
      }
    }

    if (!mounted) {
      return;
    }

    final error = lastError;
    setState(() {
      _isProvisioning = false;
      if (error is FirebaseException) {
        _errorMessage = _mapProvisioningError(error);
      } else if (error is EncryptionSetupException) {
        _errorMessage = userFacingClientFailureMessage(
          UserFacingClientFailure.profileProvisioning,
        );
      } else {
        _errorMessage = userFacingClientFailureMessage(
          UserFacingClientFailure.profileProvisioning,
        );
      }
    });
  }

  String _mapProvisioningError(FirebaseException error) {
    switch (error.code) {
      case 'permission-denied':
        return 'Your authenticated session could not be verified. Sign out and sign in again.';
      case 'unavailable':
        return userFacingClientFailureMessage(
          UserFacingClientFailure.profileProvisioning,
        );
      default:
        return userFacingClientFailureMessage(
          UserFacingClientFailure.profileProvisioning,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isError = _errorMessage != null;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isProvisioning)
                    const CircularProgressIndicator()
                  else if (isError)
                    Icon(
                      Icons.error_outline,
                      color: theme.colorScheme.error,
                      size: 42,
                    )
                  else
                    Icon(
                      Icons.hourglass_top_rounded,
                      color: theme.colorScheme.primary,
                      size: 38,
                    ),
                  const SizedBox(height: 16),
                  Text(
                    isError
                        ? 'Workspace profile provisioning failed'
                        : 'Creating your workspace profile...',
                    style: theme.textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _errorMessage ??
                        'We are storing your account details securely. This usually takes just a few seconds.',
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  if (isError)
                    FilledButton.icon(
                      onPressed: _provisionUserDocumentIfMissing,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Retry'),
                    ),
                  if (isError) const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: widget.onSignOut,
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SubscriptionPaywallPage extends StatefulWidget {
  const SubscriptionPaywallPage({
    super.key,
    required this.auth,
    required this.user,
    required this.subscription,
    required this.coordinator,
    this.externalCheckoutEnabled = true,
    this.businessMode = false,
  });

  final FirebaseAuth auth;
  final User user;
  final SubscriptionState subscription;
  final SubscriptionCoordinator coordinator;
  final bool externalCheckoutEnabled;
  final bool businessMode;

  @override
  State<SubscriptionPaywallPage> createState() =>
      _SubscriptionPaywallPageState();
}

enum BillingInterval { monthly, yearly }

extension on BillingInterval {
  String get shortLabel =>
      this == BillingInterval.monthly ? 'Monthly' : 'Yearly';

  String get termLabel =>
      this == BillingInterval.monthly ? 'per month' : 'per year';

  String get apiValue => this == BillingInterval.monthly ? 'monthly' : 'yearly';

  String get savingsBlurb => this == BillingInterval.yearly
      ? 'Two months free with annual billing'
      : 'Cancel anytime';
}

class _SubscriptionPlan {
  const _SubscriptionPlan({
    required this.tier,
    required this.title,
    required this.description,
    required this.monthlyPrice,
    required this.yearlyPrice,
    required this.features,
    this.highlight = false,
  });

  final String tier;
  final String title;
  final String description;
  final double monthlyPrice;
  final double yearlyPrice;
  final List<String> features;
  final bool highlight;

  double _priceFor(BillingInterval interval) =>
      interval == BillingInterval.monthly ? monthlyPrice : yearlyPrice;

  String priceLabel(BillingInterval interval) {
    final value = _priceFor(interval);
    final decimals = value % 1 == 0 ? 0 : 2;
    return '${String.fromCharCode(36)}${value.toStringAsFixed(decimals)}';
  }
}

const List<_SubscriptionPlan> _subscriptionPlans = [
  _SubscriptionPlan(
    tier: 'basic',
    title: 'Basic',
    description: 'For personal backups and private client delivery.',
    monthlyPrice: 2.5,
    yearlyPrice: 25,
    features: [
      '500 GB of client-side encrypted storage',
      'Protected share links and file requests',
      'Encrypted file and folder names',
    ],
  ),
  _SubscriptionPlan(
    tier: 'pro',
    title: 'Pro',
    description:
        'For active freelancers and small teams with larger file libraries.',
    monthlyPrice: 3.5,
    yearlyPrice: 35,
    highlight: true,
    features: [
      '1 TB of client-side encrypted storage',
      'Protected share links and file requests',
      'Encrypted collaboration tools',
    ],
  ),
  _SubscriptionPlan(
    tier: 'ultra',
    title: 'Ultra',
    description: 'For larger encrypted archives and frequent collaboration.',
    monthlyPrice: 6,
    yearlyPrice: 60,
    features: [
      '2 TB of client-side encrypted storage',
      'Protected share links and file requests',
      'Encrypted collaboration and cloud imports',
    ],
  ),
];

const List<_SubscriptionPlan> _businessSubscriptionPlans = [
  _SubscriptionPlan(
    tier: 'ultra',
    title: 'Business',
    description:
        'For a company workspace, administration, and protected team collaboration.',
    monthlyPrice: 6,
    yearlyPrice: 60,
    highlight: true,
    features: [
      '2 TB of client-side encrypted storage',
      'Company workspace and member administration',
      'Protected groups, permissions, and collaboration',
    ],
  ),
];

class _SubscriptionPaywallPageState extends State<SubscriptionPaywallPage> {
  bool _isProcessing = false;
  String? _errorMessage;
  BillingInterval _billingInterval = BillingInterval.monthly;
  late String _selectedTier;

  List<_SubscriptionPlan> get _availablePlans =>
      widget.businessMode ? _businessSubscriptionPlans : _subscriptionPlans;

  @override
  void initState() {
    super.initState();
    final pendingIntent = CheckoutPlanIntentStore.instance.take();
    final preferredPlan = _availablePlans.firstWhere(
      (plan) => pendingIntent == null
          ? plan.highlight
          : plan.tier == pendingIntent.tier,
      orElse: () => _availablePlans.first,
    );
    _selectedTier = preferredPlan.tier;
    if (pendingIntent?.interval == 'yearly') {
      _billingInterval = BillingInterval.yearly;
    }

    // Listen to global payment processing state (e.g. from deep link)
    paymentProcessingNotifier.addListener(_onGlobalProcessingChanged);
  }

  @override
  void dispose() {
    paymentProcessingNotifier.removeListener(_onGlobalProcessingChanged);
    super.dispose();
  }

  void _onGlobalProcessingChanged() {
    if (paymentProcessingNotifier.value) {
      if (mounted) {
        setState(() {
          _isProcessing = true;
          _errorMessage = null;
        });
      }
    }
  }

  bool get _supportsInAppCheckout {
    if (!widget.externalCheckoutEnabled) {
      return false;
    }
    if (kIsWeb) {
      return true;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return true;
      default:
        return false;
    }
  }

  Uri _resolveEmbeddedCheckoutBaseUri() {
    return ReleaseRuntimeConfig.resolveEmbeddedCheckoutPageUri(
      projectId: widget.auth.app.options.projectId,
    );
  }

  Uri _buildCheckoutReturnUri() {
    return ReleaseRuntimeConfig.resolvePaymentSuccessUri(
      projectId: widget.auth.app.options.projectId,
    );
  }

  Uri _buildEmbeddedCheckoutUri({
    required _SubscriptionPlan plan,
    required String email,
    required String checkoutTheme,
    String? uiMode,
    String? clientSecret,
    Uri? fallbackCheckoutUri,
  }) {
    final checkoutBaseUri = _resolveEmbeddedCheckoutBaseUri();
    final returnUri = _buildCheckoutReturnUri();

    final cancelUri = checkoutBaseUri.replace(
      queryParameters: {
        ...checkoutBaseUri.queryParameters,
        'tier': plan.tier,
        'interval': _billingInterval.apiValue,
        'email': email,
        'uid': widget.user.uid,
      },
    );

    final query = <String, String>{
      ...checkoutBaseUri.queryParameters,
      'tier': plan.tier,
      'interval': _billingInterval.apiValue,
      'email': email,
      'uid': widget.user.uid,
      'auto': '1',
      'theme': checkoutTheme,
      if (uiMode != null && uiMode.isNotEmpty) 'uiMode': uiMode,
      'returnUrl': returnUri.toString(),
      'cancelUrl': cancelUri.toString(),
    };

    final checkoutServiceBaseUrl = widget.coordinator.checkoutServiceBaseUrl;
    if (checkoutServiceBaseUrl != null && checkoutServiceBaseUrl.isNotEmpty) {
      query['checkoutBaseUrl'] = checkoutServiceBaseUrl;
    }
    if (clientSecret != null && clientSecret.isNotEmpty) {
      query['clientSecret'] = clientSecret;
    }
    if (fallbackCheckoutUri != null) {
      query['checkoutUrl'] = fallbackCheckoutUri.toString();
    }

    return checkoutBaseUri.replace(queryParameters: query);
  }

  Future<void> _startCheckoutForPlan(_SubscriptionPlan plan) async {
    if (_isProcessing) {
      return;
    }
    setState(() {
      _selectedTier = plan.tier;
    });
    await _startCheckout(plan: plan);
  }

  Future<void> _startCheckout({_SubscriptionPlan? plan}) async {
    if (_isProcessing || !widget.externalCheckoutEnabled) {
      return;
    }

    final selectedPlan =
        plan ??
        _availablePlans.firstWhere(
          (item) => item.tier == _selectedTier,
          orElse: () => _availablePlans.first,
        );

    final acceptedPerks = await _showFoundingUserPerksDialog(selectedPlan);
    if (!acceptedPerks || !mounted) {
      return;
    }

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      final authEmail = (widget.user.email ?? '').trim();
      final email = isUsernameOnlyAuthEmail(authEmail) ? '' : authEmail;
      final checkoutTheme = Theme.of(context).brightness == Brightness.dark
          ? 'dark'
          : 'light';
      final idToken = await widget.user.getIdToken();
      final returnUri = _buildCheckoutReturnUri();
      final launch = await widget.coordinator.startCheckoutSession(
        uid: widget.user.uid,
        email: email,
        planTier: selectedPlan.tier,
        interval: _billingInterval.apiValue,
        idToken: idToken,
        checkoutTheme: checkoutTheme,
        uiMode: ServiceEnvironmentConfig.current == ServiceEnvironment.staging
            ? 'hosted'
            : 'custom',
        successUrl: returnUri.toString(),
        cancelUrl: _resolveEmbeddedCheckoutBaseUri().toString(),
      );
      final checkoutUri =
          launch.clientSecret != null && launch.clientSecret!.isNotEmpty
          ? _buildEmbeddedCheckoutUri(
              plan: selectedPlan,
              email: email,
              checkoutTheme: checkoutTheme,
              uiMode: launch.uiMode,
              clientSecret: launch.clientSecret,
              fallbackCheckoutUri: launch.checkoutUri,
            )
          : launch.checkoutUri;
      if (checkoutUri == null) {
        throw const StripeCheckoutException(
          'Stripe checkout data was incomplete. Please retry in a moment.',
        );
      }
      if (!mounted) {
        return;
      }

      if (kIsWeb) {
        final launched = await web_checkout_launcher.launchCheckoutInWeb(
          checkoutUri,
        );
        if (!mounted) {
          return;
        }
        if (!launched) {
          setState(() {
            _isProcessing = false;
            _errorMessage =
                'Could not open embedded checkout in this browser tab. Refresh and try again.';
          });
          return;
        }
        paymentProcessingNotifier.value = true;
        return;
      }

      if (!_supportsInAppCheckout) {
        setState(() {
          _isProcessing = false;
          _errorMessage =
              'Embedded checkout is unavailable on this platform. Continue on Android, iOS, macOS, or Windows.';
        });
        return;
      }

      final result = await Navigator.of(context).push<CheckoutResult>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => CheckoutWebViewPage(
            checkoutUri: checkoutUri,
            successPathSuffixes: const [
              'redirect.html',
              'success',
              'completed',
              'payment-success',
              'ronikdrive://payment-success',
            ],
            cancelPathSuffixes: const [
              'cancel',
              'cancelled',
              'payment-cancel',
              'ronikdrive://payment-cancel',
            ],
          ),
        ),
      );
      if (!mounted) {
        return;
      }

      switch (result) {
        case CheckoutResult.success:
          setState(() {
            _isProcessing = true;
            _errorMessage = null;
          });
          paymentProcessingNotifier.value = true;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Checkout completed. Waiting for payment confirmation...',
              ),
            ),
          );
          break;
        case CheckoutResult.cancelled:
          setState(() {
            _isProcessing = false;
            _errorMessage =
                "Checkout cancelled. You can try again whenever you're ready.";
          });
          break;
        case CheckoutResult.dismissed:
        case null:
          setState(() {
            _isProcessing = false;
            _errorMessage =
                'Checkout closed before finishing. Tap any plan to resume.';
          });
          break;
      }
    } on StripeCheckoutException {
      setState(() {
        _isProcessing = false;
        _errorMessage = userFacingClientFailureMessage(
          UserFacingClientFailure.checkoutStart,
        );
      });
    } catch (_) {
      setState(() {
        _isProcessing = false;
        _errorMessage =
            'Starting the checkout session failed. Please try again.';
      });
    }
  }

  Future<bool> _showFoundingUserPerksDialog(_SubscriptionPlan plan) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Before ${plan.title} checkout'),
          content: const SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FoundingUserPerksPanel(
                  subtitle:
                      'Because you are joining during the first 100-user phase, these extras come before public rollout.',
                ),
                SizedBox(height: 18),
                Text(
                  'Payment and renewal',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 6),
                Text(_stripePaymentRetentionDisclosure),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Do not start recurring plan'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text('Accept renewal and continue'),
            ),
          ],
        );
      },
    );
    return result == true;
  }

  String? _formattedRenewalDate(DateTime? date) {
    if (date == null) {
      return null;
    }
    const monthNames = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final local = date.toLocal();
    final month = local.month >= 1 && local.month <= 12
        ? monthNames[local.month - 1]
        : local.month.toString();
    final day = local.day;
    final year = local.year;
    return '$month $day, $year';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authEmail = widget.user.email ?? '';
    final email = authEmail.isEmpty
        ? 'your account'
        : isUsernameOnlyAuthEmail(authEmail)
        ? authEmail.split('@').first
        : authEmail;
    final statusLabel = widget.subscription.statusLabel;
    final renewal = _formattedRenewalDate(widget.subscription.currentPeriodEnd);
    final capacity = widget.subscription.capacityLabel;
    final accountDeletionDate = _formattedRenewalDate(
      widget.subscription.accountDeletionEligibleAt,
    );
    final dataDeletionDate = _formattedRenewalDate(
      widget.subscription.dataDeletionEligibleAt,
    );
    final showRetentionWarning =
        widget.subscription.cancelAtPeriodEnd ||
        widget.subscription.retentionNotice != null ||
        accountDeletionDate != null ||
        dataDeletionDate != null;

    if (!widget.externalCheckoutEnabled) {
      return _ExistingSubscriberView(
        auth: widget.auth,
        email: email,
        statusLabel: statusLabel,
        renewal: renewal,
        capacity: capacity,
        showRetentionWarning: showRetentionWarning,
        retentionNotice: widget.subscription.retentionNotice,
        accountDeletionDate: accountDeletionDate,
        dataDeletionDate: dataDeletionDate,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Complete subscription setup'),
        actions: [
          TextButton.icon(
            onPressed: _isProcessing
                ? null
                : () {
                    LoginPasswordVault.instance.clear();
                    widget.auth.signOut();
                  },
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Sign out'),
          ),
        ],
      ),
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(color: theme.colorScheme.surface),
        child: Center(
          child: IgnorePointer(
            ignoring: _isProcessing,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1040),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.businessMode
                          ? 'Unlock RonikCloud Business'
                          : 'Choose your RonikCloud plan',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      widget.businessMode
                          ? 'Subscribe to create your company workspace, manage members, and use protected team collaboration. Stripe collects a billing email during checkout when your account is username-only.'
                          : 'Choose more storage with the same privacy protections. Stripe handles payment. Your existing files and encryption settings stay unchanged.',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 32),
                    if (_isProcessing) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: theme.colorScheme.primary),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                'Payment processing... Please wait while we confirm your subscription.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                setState(() {
                                  _isProcessing = false;
                                });
                                paymentProcessingNotifier.value = false;
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerLow.withValues(
                          alpha: 0.9,
                        ),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 28,
                            offset: const Offset(0, 18),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withValues(
                                  alpha: 0.08,
                                ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.verified_user_rounded,
                                    color: theme.colorScheme.primary,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Signed in as $email. Complete checkout to unlock encrypted storage and team sharing.',
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: theme.colorScheme.primary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                            const _StripePaymentDisclosure(),
                            const SizedBox(height: 24),
                            _BillingIntervalToggle(
                              interval: _billingInterval,
                              onChanged: (value) {
                                setState(() {
                                  _billingInterval = value;
                                });
                              },
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _billingInterval.savingsBlurb,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 24),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                const spacing = 20.0;
                                final width = constraints.maxWidth;
                                final columns = width >= 960
                                    ? 3
                                    : width >= 680
                                    ? 2
                                    : 1;
                                final rawWidth = columns == 1
                                    ? width
                                    : (width - spacing * (columns - 1)) /
                                          columns;
                                final cardWidth = columns == 1
                                    ? width
                                    : math.max(280.0, rawWidth);
                                return Wrap(
                                  spacing: spacing,
                                  runSpacing: spacing,
                                  children: _availablePlans.map((plan) {
                                    return SizedBox(
                                      width: cardWidth,
                                      child: _PlanCard(
                                        plan: plan,
                                        interval: _billingInterval,
                                        selected: plan.tier == _selectedTier,
                                        isProcessing: _isProcessing,
                                        onSelected: () {
                                          if (_isProcessing) {
                                            return;
                                          }
                                          setState(() {
                                            _selectedTier = plan.tier;
                                          });
                                        },
                                        onSubscribe: () =>
                                            _startCheckoutForPlan(plan),
                                      ),
                                    );
                                  }).toList(),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (!_supportsInAppCheckout) ...[
                      const SizedBox(height: 24),
                      const _ExternalCheckoutMessage(),
                    ],
                    const SizedBox(height: 28),
                    _SubscriptionStatusCard(
                      statusLabel: statusLabel,
                      renewal: renewal,
                      capacity: capacity,
                    ),
                    if (showRetentionWarning) ...[
                      const SizedBox(height: 16),
                      _RetentionWarningCard(
                        notice: widget.subscription.retentionNotice,
                        accountDeletionDate: accountDeletionDate,
                        dataDeletionDate: dataDeletionDate,
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      'Already paid? Keep this window open. We refresh your status automatically once Stripe confirms the payment.',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 24),
                    if (_errorMessage != null)
                      _CheckoutErrorBanner(message: _errorMessage!),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ).withAppPageTitle('Choose a Storage Plan | RonikCloud');
  }
}

class _StripePaymentDisclosure extends StatelessWidget {
  const _StripePaymentDisclosure();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.credit_card_off_outlined,
              color: theme.colorScheme.onSecondaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Payment details and renewal',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _stripePaymentRetentionDisclosure,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExistingSubscriberView extends StatelessWidget {
  const _ExistingSubscriberView({
    required this.auth,
    required this.email,
    required this.statusLabel,
    required this.renewal,
    required this.capacity,
    required this.showRetentionWarning,
    required this.retentionNotice,
    required this.accountDeletionDate,
    required this.dataDeletionDate,
  });

  final FirebaseAuth auth;
  final String email;
  final String statusLabel;
  final String? renewal;
  final String? capacity;
  final bool showRetentionWarning;
  final String? retentionNotice;
  final String? accountDeletionDate;
  final String? dataDeletionDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('RonikCloud account'),
        actions: [
          TextButton.icon(
            onPressed: () {
              LoginPasswordVault.instance.clear();
              auth.signOut();
            },
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Sign out'),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'An active subscription is required',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'This version provides access to existing RonikCloud accounts. In-app purchases are unavailable. Account access updates automatically when its status changes.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.verified_user_rounded,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Signed in as $email',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Subscription status refreshes automatically. If this account was just activated, keep the app open for a moment.',
                                style: theme.textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                _SubscriptionStatusCard(
                  statusLabel: statusLabel,
                  renewal: renewal,
                  capacity: capacity,
                  statusDescription:
                      'We check for subscription updates automatically. When this account becomes active, the workspace will unlock.',
                ),
                if (showRetentionWarning) ...[
                  const SizedBox(height: 16),
                  _RetentionWarningCard(
                    notice: retentionNotice,
                    accountDeletionDate: accountDeletionDate,
                    dataDeletionDate: dataDeletionDate,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RetentionWarningCard extends StatelessWidget {
  const _RetentionWarningCard({
    required this.notice,
    required this.accountDeletionDate,
    required this.dataDeletionDate,
  });

  final String? notice;
  final String? accountDeletionDate;
  final String? dataDeletionDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fallback = accountDeletionDate == null && dataDeletionDate == null
        ? 'If the subscription is not renewed, this account and its stored data may be permanently deleted after the retention period.'
        : 'If the subscription is not renewed, this account may be permanently deleted from $accountDeletionDate and stored data from $dataDeletionDate.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              notice?.trim().isNotEmpty == true ? notice!.trim() : fallback,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onErrorContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BillingIntervalToggle extends StatelessWidget {
  const _BillingIntervalToggle({
    required this.interval,
    required this.onChanged,
  });

  final BillingInterval interval;
  final ValueChanged<BillingInterval> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.35,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: BillingInterval.values.map((value) {
          final selected = value == interval;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(value.shortLabel),
              ),
              selected: selected,
              onSelected: (isSelected) {
                if (isSelected) {
                  onChanged(value);
                }
              },
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.interval,
    required this.selected,
    required this.onSelected,
    required this.onSubscribe,
    required this.isProcessing,
  });

  final _SubscriptionPlan plan;
  final BillingInterval interval;
  final bool selected;
  final VoidCallback onSelected;
  final VoidCallback onSubscribe;
  final bool isProcessing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final price = plan.priceLabel(interval);
    final term = interval.termLabel;
    final highlightColor = theme.colorScheme.primary;
    final foreground = selected
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: selected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.85)
            : theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: selected ? highlightColor : theme.colorScheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: selected ? 0.08 : 0.05),
            blurRadius: selected ? 32 : 24,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: isProcessing ? null : onSelected,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            plan.title,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: foreground,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            plan.description,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: selected
                          ? Icon(
                              Icons.check_circle,
                              color: highlightColor,
                              key: const ValueKey('selected'),
                            )
                          : Icon(
                              Icons.circle_outlined,
                              color: theme.colorScheme.outline,
                              key: const ValueKey('unselected'),
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text.rich(
                  TextSpan(
                    text: price,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      color: foreground,
                    ),
                    children: [
                      TextSpan(
                        text: ' $term',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                ...plan.features.map(
                  (feature) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.check_rounded,
                          size: 18,
                          color: highlightColor,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            feature,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: isProcessing ? null : onSubscribe,
                  child: isProcessing && selected
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          selected
                              ? 'Continue with ${plan.title}'
                              : 'Choose ${plan.title}',
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExternalCheckoutMessage extends StatelessWidget {
  const _ExternalCheckoutMessage();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: theme.colorScheme.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Embedded Stripe checkout is unavailable on this platform. Continue on Android, iOS, macOS, or Windows.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubscriptionStatusCard extends StatelessWidget {
  const _SubscriptionStatusCard({
    required this.statusLabel,
    required this.renewal,
    required this.capacity,
    this.statusDescription =
        'We check for updates automatically. As soon as Stripe confirms payment, this page will unlock your workspace.',
  });

  final String statusLabel;
  final String? renewal;
  final String? capacity;
  final String statusDescription;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Subscription status: $statusLabel',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(statusDescription, style: theme.textTheme.bodyMedium),
            if (renewal != null) ...[
              const SizedBox(height: 12),
              Text(
                'Current period ends on $renewal.',
                style: theme.textTheme.bodyMedium,
              ),
            ],
            if (capacity != null && capacity!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Workspace capacity: $capacity',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CheckoutErrorBanner extends StatelessWidget {
  const _CheckoutErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.24),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
