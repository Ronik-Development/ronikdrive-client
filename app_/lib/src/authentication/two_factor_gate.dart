import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../billing/billing_channel.dart';
import '../billing/subscription_coordinator.dart';
import '../billing/subscription_gate.dart';
import '../business/business_workspace_page.dart';
import '../shared/user_facing_client_failure.dart';
import 'account_environment.dart';
import 'login_password_vault.dart';
import 'two_factor_service.dart';

class TwoFactorGate extends StatefulWidget {
  const TwoFactorGate({
    super.key,
    required this.auth,
    required this.user,
    required this.firestore,
    required this.subscriptionCoordinator,
    this.accountEnvironment = AccountEnvironment.personal,
    this.twoFactorApi,
    required this.billingChannel,
  });

  final FirebaseAuth auth;
  final User user;
  final FirebaseFirestore firestore;
  final SubscriptionCoordinator subscriptionCoordinator;
  final AccountEnvironment accountEnvironment;
  final TwoFactorApi? twoFactorApi;
  final BillingChannel billingChannel;

  @override
  State<TwoFactorGate> createState() => _TwoFactorGateState();
}

class _TwoFactorGateState extends State<TwoFactorGate> {
  late TwoFactorApi _twoFactorApi;
  final TextEditingController _codeController = TextEditingController();

  bool _loading = true;
  bool _verifying = false;
  String? _errorMessage;
  TwoFactorStatus _status = const TwoFactorStatus(
    enabled: false,
    verified: true,
  );

  @override
  void initState() {
    super.initState();
    _twoFactorApi =
        widget.twoFactorApi ?? FirebaseTwoFactorApi.forApp(widget.auth.app);
    _loadStatus();
  }

  @override
  void didUpdateWidget(covariant TwoFactorGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.user.uid != oldWidget.user.uid ||
        widget.twoFactorApi != oldWidget.twoFactorApi) {
      _twoFactorApi =
          widget.twoFactorApi ?? FirebaseTwoFactorApi.forApp(widget.auth.app);
      _codeController.clear();
      _loadStatus();
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  bool _isRecoverableSessionError(Object error) {
    if (error is FirebaseException) {
      final code = error.code.toLowerCase();
      if (code == 'permission-denied' || code == 'unauthenticated') {
        return true;
      }

      final message = error.message?.toLowerCase() ?? '';
      return message.contains('permission denied') ||
          message.contains('insufficient permissions') ||
          (message.contains('auth') && message.contains('token'));
    }

    if (error is TwoFactorException) {
      final message = error.message.toLowerCase();
      return message.contains('signed in') ||
          message.contains('authenticated session') ||
          message.contains('permission') ||
          (message.contains('auth') && message.contains('token'));
    }

    return false;
  }

  Future<void> _refreshSession() async {
    final currentUser = widget.auth.currentUser;
    if (currentUser == null || currentUser.uid != widget.user.uid) {
      return;
    }

    try {
      await currentUser.getIdToken(true);
      await Future<void>.delayed(const Duration(milliseconds: 250));
    } catch (_) {
      // Surface the original error if refreshing the token does not help.
    }
  }

  Future<void> _loadStatus() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        // Firebase refreshes expired tokens itself. Force a refresh only when
        // a request actually fails with a recoverable session error.
        if (attempt > 0) await _refreshSession();
        final requiresTwoFactor = await _requiresTwoFactorChallenge(
          treatPermissionDeniedAsSessionError: attempt == 0,
        );
        if (!requiresTwoFactor) {
          if (!mounted) {
            return;
          }
          setState(() {
            _status = const TwoFactorStatus(enabled: false, verified: true);
            _loading = false;
            _errorMessage = null;
          });
          return;
        }

        final status = await _twoFactorApi.fetchStatus();
        if (!mounted) {
          return;
        }
        setState(() {
          _status = status;
          _loading = false;
          _errorMessage = null;
        });
        return;
      } on TwoFactorException catch (error) {
        if (attempt < 2 && _isRecoverableSessionError(error)) {
          continue;
        }
        break;
      } on FirebaseException catch (error) {
        if (attempt < 2 && _isRecoverableSessionError(error)) {
          continue;
        }
        break;
      } catch (_) {
        break;
      }
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _loading = false;
      _errorMessage = userFacingClientFailureMessage(
        UserFacingClientFailure.twoFactorStatus,
      );
    });
  }

  Future<bool> _requiresTwoFactorChallenge({
    bool treatPermissionDeniedAsSessionError = false,
  }) async {
    try {
      final snapshot = await widget.firestore
          .collection('users')
          .doc(widget.user.uid)
          .get();
      final data = snapshot.data();
      return data?['twoFactorEnabled'] == true;
    } on FirebaseException catch (error) {
      // The Firestore rules intentionally deny reading the user document when
      // 2FA is enabled but the current session is not yet verified.
      if (error.code == 'permission-denied') {
        if (treatPermissionDeniedAsSessionError) {
          rethrow;
        }
        return true;
      }
      rethrow;
    }
  }

  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() {
        _errorMessage = 'Enter the 6-digit code from your authenticator app.';
      });
      return;
    }

    setState(() {
      _verifying = true;
      _errorMessage = null;
    });

    try {
      final status = await _twoFactorApi.verifyCode(code);
      if (!mounted) {
        return;
      }
      setState(() {
        _status = status;
        _verifying = false;
        _errorMessage = status.verified
            ? null
            : 'The verification code was rejected. Try a fresh code.';
      });
      if (!status.verified) {
        _codeController.clear();
      }
    } on TwoFactorException {
      if (!mounted) {
        return;
      }
      setState(() {
        _verifying = false;
        _errorMessage = userFacingClientFailureMessage(
          UserFacingClientFailure.twoFactorVerification,
        );
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _verifying = false;
        _errorMessage = userFacingClientFailureMessage(
          UserFacingClientFailure.twoFactorVerification,
        );
      });
    }
  }

  Future<void> _signOut() async {
    LoginPasswordVault.instance.clear();
    await widget.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const _TwoFactorLoadingView();
    }

    final errorMessage = _errorMessage;
    if (errorMessage != null && !_status.enabled) {
      return _TwoFactorErrorView(
        message: errorMessage,
        onRetry: _loadStatus,
        onSignOut: _signOut,
      );
    }

    if (!_status.enabled || _status.verified) {
      return SubscriptionGate(
        auth: widget.auth,
        user: widget.user,
        firestore: widget.firestore,
        subscriptionCoordinator: widget.subscriptionCoordinator,
        billingChannel: widget.billingChannel,
        businessMode: widget.accountEnvironment == AccountEnvironment.business,
        paidWorkspaceBuilder:
            widget.accountEnvironment == AccountEnvironment.business
            ? (_) => BusinessWorkspacePage(
                billingChannel: widget.billingChannel,
                auth: widget.auth,
                user: widget.user,
                firestore: widget.firestore,
              )
            : null,
      );
    }

    return _TwoFactorChallengeView(
      codeController: _codeController,
      errorMessage: _errorMessage,
      isVerifying: _verifying,
      onVerify: _verifyCode,
      onRefresh: _loadStatus,
      onSignOut: _signOut,
    );
  }
}

class _TwoFactorLoadingView extends StatelessWidget {
  const _TwoFactorLoadingView();

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
              'Checking account security...',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _TwoFactorErrorView extends StatelessWidget {
  const _TwoFactorErrorView({
    required this.message,
    required this.onRetry,
    required this.onSignOut,
  });

  final String message;
  final Future<void> Function() onRetry;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
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
                        size: 44,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Security check failed',
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
        ),
      ),
    );
  }
}

class _TwoFactorChallengeView extends StatelessWidget {
  const _TwoFactorChallengeView({
    required this.codeController,
    required this.errorMessage,
    required this.isVerifying,
    required this.onVerify,
    required this.onRefresh,
    required this.onSignOut,
  });

  final TextEditingController codeController;
  final String? errorMessage;
  final bool isVerifying;
  final Future<void> Function() onVerify;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Two-factor authentication required',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Enter the 6-digit code from your authenticator app to unlock your workspace.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: codeController,
                      enabled: !isVerifying,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      maxLength: 6,
                      decoration: InputDecoration(
                        labelText: 'Authentication code',
                        hintText: '123456',
                        errorText: errorMessage,
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: (_) {
                        if (!isVerifying) {
                          onVerify();
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: isVerifying ? null : onVerify,
                            child: isVerifying
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: theme.colorScheme.primary,
                                    ),
                                  )
                                : const Text('Verify'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: isVerifying ? null : onRefresh,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Refresh status'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton.icon(
                            onPressed: isVerifying ? null : onSignOut,
                            icon: const Icon(Icons.logout_rounded),
                            label: const Text('Sign out'),
                          ),
                        ),
                      ],
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
