import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../analytics/signup_completion_reconciliation.dart';
import '../billing/billing_channel.dart';
import '../billing/subscription_coordinator.dart';
import '../shared/user_facing_client_failure.dart';
import '../storage/upload_coordinator.dart';
import 'account_environment.dart';
import 'account_identity_stream.dart';
import 'landing_page.dart';
import 'login_page.dart';
import 'two_factor_gate.dart';
import 'two_factor_service.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.auth,
    required this.firestore,
    required this.subscriptionCoordinator,
    required this.billingChannel,
    this.twoFactorApi,
    this.signupCompletionReconciler,
  });

  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final SubscriptionCoordinator subscriptionCoordinator;
  final BillingChannel billingChannel;
  final TwoFactorApi? twoFactorApi;
  final SignupCompletionReconciler? signupCompletionReconciler;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  final _authRechecks = StreamController<void>.broadcast();
  late Stream<User?> _authChanges;
  String? _signupReconciliationStartedForUid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authChanges = _authStream();
  }

  @override
  void didUpdateWidget(covariant AuthGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.auth != oldWidget.auth) {
      _authChanges = _authStream();
      _signupReconciliationStartedForUid = null;
    }
  }

  Stream<User?> _authStream() {
    final auth = widget.auth;
    return accountIdentityStream<User>(
      current: () => auth.currentUser,
      identity: (user) => user.uid,
      changes: auth.authStateChanges(),
      rechecks: _authRechecks.stream,
      bindAccount: UploadCoordinator.instance.bindAccount,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _authRechecks.add(null);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_authRechecks.close());
    super.dispose();
  }

  void _retryAuthConnection() {
    setState(() {
      _authChanges = _authStream();
    });
  }

  SignupCompletionReconciler? get _signupCompletionReconciler =>
      widget.signupCompletionReconciler ??
      SignupCompletionReconciler.runtimeDefault;

  void _startSignupCompletionReconciliation(User user) {
    final reconciler = _signupCompletionReconciler;
    if (reconciler == null || _signupReconciliationStartedForUid == user.uid) {
      return;
    }
    _signupReconciliationStartedForUid = user.uid;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        reconciler.reconcile(
          authenticatedAccountCreatedAt: user.metadata.creationTime,
          tokenProvider: () async {
            final currentUser = widget.auth.currentUser;
            if (currentUser?.uid != user.uid) {
              return null;
            }
            return currentUser!.getIdToken();
          },
          profileReady: () async {
            final currentUser = widget.auth.currentUser;
            if (currentUser?.uid != user.uid) {
              return false;
            }
            try {
              final profile = await widget.firestore
                  .collection('users')
                  .doc(user.uid)
                  .get();
              return profile.exists;
            } on Object {
              return false;
            }
          },
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingView();
        }

        if (snapshot.hasError) {
          return _ErrorView(onRetry: _retryAuthConnection);
        }

        final user = snapshot.data;
        if (user == null) {
          _signupReconciliationStartedForUid = null;
          if (!widget.billingChannel.allowsRegistration) {
            return LoginPage(
              auth: widget.auth,
              firestore: widget.firestore,
              allowRegistration: false,
              signupCompletionReconciler: widget.signupCompletionReconciler,
            );
          }
          return LandingPage(
            auth: widget.auth,
            firestore: widget.firestore,
            signupCompletionReconciler: widget.signupCompletionReconciler,
          );
        }

        _startSignupCompletionReconciliation(user);

        return _AccountEnvironmentGate(
          key: ValueKey<String>(user.uid),
          user: user,
          builder: (environment) => TwoFactorGate(
            auth: widget.auth,
            user: user,
            firestore: widget.firestore,
            subscriptionCoordinator: widget.subscriptionCoordinator,
            accountEnvironment: environment,
            twoFactorApi: widget.twoFactorApi,
            billingChannel: widget.billingChannel,
          ),
        );
      },
    );
  }
}

class _AccountEnvironmentGate extends StatefulWidget {
  const _AccountEnvironmentGate({
    super.key,
    required this.user,
    required this.builder,
  });

  final User user;
  final Widget Function(AccountEnvironment environment) builder;

  @override
  State<_AccountEnvironmentGate> createState() =>
      _AccountEnvironmentGateState();
}

class _AccountEnvironmentGateState extends State<_AccountEnvironmentGate> {
  late Future<AccountEnvironment> _environment;

  @override
  void initState() {
    super.initState();
    _environment = AccountEnvironmentStore.instance.resolveForUser(
      widget.user.uid,
    );
  }

  @override
  void didUpdateWidget(covariant _AccountEnvironmentGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.uid != widget.user.uid) {
      _environment = AccountEnvironmentStore.instance.resolveForUser(
        widget.user.uid,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AccountEnvironment>(
      future: _environment,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _LoadingView();
        }
        return widget.builder(snapshot.data ?? AccountEnvironment.personal);
      },
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

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
              'Connecting to your secure workspace...',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(32),
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
                    'We couldn\'t reach RonikCloud',
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    userFacingClientFailureMessage(
                      UserFacingClientFailure.authConnection,
                    ),
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
    );
  }
}
