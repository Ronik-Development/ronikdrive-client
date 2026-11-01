import 'signup_session.dart';
import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../analytics/growth_analytics.dart';
import '../analytics/signup_completion_reconciliation.dart';
import 'account_identity.dart';
import 'account_registration_service.dart';
import 'login_password_vault.dart';
import 'password_sign_in.dart';
import '../home/download_page.dart';
import '../legal/legal_documents_page.dart';
import '../security/encryption_service.dart';
import '../security/encryption_setup_service.dart';
import '../shared/app_page_title.dart';
import 'account_environment.dart';
import '../shared/adaptive_choice_control.dart';

typedef LoginGrowthEventRecorder =
    Future<void> Function({
      required GrowthEvent event,
      required GrowthSource source,
      required GrowthEventProperties properties,
    });

typedef LoginStandardEncryptionPreparer =
    Future<bool> Function({
      required String uid,
      required String email,
      required String password,
    });

typedef LoginAccountRegistrationProvisioner =
    Future<void> Function({
      required String username,
      required String legalVersion,
      required String legalAcceptedAt,
      required bool productUpdatesOptIn,
      required bool recoveryEmailProvided,
      required String createdAt,
    });

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.auth,
    required this.firestore,
    this.initialRegisterMode = false,
    this.completeSetupMode = false,
    this.initialEnvironment = AccountEnvironment.personal,
    this.allowRegistration = true,
    this.attribution = const GrowthAttribution(
      source: GrowthSource.product,
      channel: GrowthChannel.product,
      entryPage: GrowthEntryPage.home,
    ),
    this.signupPlacement = GrowthPlacement.unknown,
    this.signupCtaPlacement = GrowthCtaPlacement.unknown,
    this.growthEventRecorder,
    this.signupCompletionReconciler,
    this.standardEncryptionPreparer,
    this.accountRegistrationProvisioner,
  });

  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final bool initialRegisterMode;
  final bool completeSetupMode;
  final AccountEnvironment initialEnvironment;
  final bool allowRegistration;
  final GrowthAttribution attribution;
  final GrowthPlacement signupPlacement;
  final GrowthCtaPlacement signupCtaPlacement;
  final LoginGrowthEventRecorder? growthEventRecorder;
  final SignupCompletionReconciler? signupCompletionReconciler;
  final LoginStandardEncryptionPreparer? standardEncryptionPreparer;
  final LoginAccountRegistrationProvisioner? accountRegistrationProvisioner;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final GrowthAnalytics _growthAnalytics = GrowthAnalytics();
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  late bool _isRegisterMode;
  late AccountEnvironment _environment;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _acceptedTermsAndUse = false;
  bool _acknowledgedPrivacyAndPolicies = false;
  bool _productUpdatesOptIn = false;
  bool _signupStartedRecorded = false;
  String? _completionAuthEmail;

  bool get _hasRequiredLegalConsent =>
      !_isRegisterMode ||
      (_acceptedTermsAndUse && _acknowledgedPrivacyAndPolicies);

  @override
  void initState() {
    super.initState();
    _environment = widget.initialEnvironment;
    _isRegisterMode = widget.allowRegistration && widget.initialRegisterMode;
    if (widget.completeSetupMode) {
      _completionAuthEmail = widget.auth.currentUser?.email;
      if (isUsernameOnlyAuthEmail(_completionAuthEmail)) {
        _usernameController.text = _completionAuthEmail!.split('@').first;
      } else {
        _emailController.text = _completionAuthEmail ?? '';
      }
    }
    if (_isRegisterMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _recordSignupStarted();
        }
      });
    }
    unawaited(_loadSavedLoginEmail());
  }

  void _recordGrowth(
    GrowthEvent event, {
    GrowthEventProperties properties = const GrowthEventProperties(),
  }) {
    // Keep development and automated test traffic out of production metrics.
    final injectedRecorder = widget.growthEventRecorder;
    if (!kReleaseMode && injectedRecorder == null) {
      return;
    }
    if (injectedRecorder != null) {
      unawaited(
        injectedRecorder(
          event: event,
          source: widget.attribution.source,
          properties: properties,
        ),
      );
      return;
    }
    unawaited(
      _growthAnalytics.record(
        event: event,
        source: widget.attribution.source,
        properties: properties,
      ),
    );
  }

  void _recordSignupStarted() {
    if (_signupStartedRecorded) {
      return;
    }
    _signupStartedRecorded = true;
    _recordGrowth(
      GrowthEvent.signupStarted,
      properties: GrowthEventProperties(
        authMethod: GrowthAuthMethod.emailPassword,
        placement: widget.signupPlacement,
        channel: widget.attribution.channel,
        entryPage: widget.attribution.entryPage,
        ctaPlacement: widget.signupCtaPlacement,
      ),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _displayNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isLoading) return;
    final messenger = ScaffoldMessenger.of(context);
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (!_hasRequiredLegalConsent) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Review and accept the legal documents to continue.'),
        ),
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
    });

    final username = normalizeAccountUsername(_usernameController.text);
    final displayName = _displayNameController.text.trim();
    final identifier = _emailController.text.trim();
    // Passwords are opaque values; trimming would lock out existing users whose
    // password intentionally starts or ends with whitespace.
    final password = _passwordController.text;
    final legalAcceptedAt = DateTime.now().toUtc().toIso8601String();

    try {
      AccountEnvironmentStore.instance.prepareSignIn(_environment);
      if (_isRegisterMode) {
        final recoveryEmail = identifier.toLowerCase();
        final authEmail = _completionAuthEmail ?? (recoveryEmail.isEmpty
            ? usernameOnlyAuthEmail(username)
            : recoveryEmail);
        final signup = await createOrResumeSignup(
          auth: widget.auth,
          firestore: widget.firestore,
          email: authEmail,
          password: password,
        );
        final credential = signup.credential;
        LoginPasswordVault.instance.store(email: authEmail, password: password);
        final createdUser = credential.user;
        if (createdUser != null) {
          final accountCreatedAt = createdUser.metadata.creationTime;
          final normalizedAccountCreatedAt =
              (accountCreatedAt ?? DateTime.now()).toUtc().toIso8601String();
          final signupCompletionReconciler =
              widget.signupCompletionReconciler ??
              SignupCompletionReconciler.runtimeDefault;
          if (signupCompletionReconciler != null && accountCreatedAt != null) {
            // Persist the outcome before profile/encryption provisioning. The
            // marker remains recoverable even if either setup step fails.
            await signupCompletionReconciler.rememberPending(
              accountCreatedAt: accountCreatedAt,
              channel: widget.attribution.channel,
              entryPage: widget.attribution.entryPage,
              ctaPlacement: widget.signupCtaPlacement,
              authMethod: GrowthAuthMethod.emailPassword,
            );
          }
          await AccountEnvironmentStore.instance.saveForUser(
            uid: createdUser.uid,
            environment: _environment,
          );
          await createdUser.updateDisplayName(
            displayName.isNotEmpty ? displayName : username,
          );

          final authedUser = await _ensureAuthenticatedSession(createdUser.uid);
          final activeUser = authedUser ?? createdUser;

          try {
            await _registerAccountProfile(
              username: username,
              legalAcceptedAt: legalAcceptedAt,
              productUpdatesOptIn:
                  recoveryEmail.isNotEmpty && _productUpdatesOptIn,
              recoveryEmailProvided: recoveryEmail.isNotEmpty,
              createdAt: normalizedAccountCreatedAt,
            );
          } on AccountRegistrationException {
            if (kDebugMode) {
              debugPrint('Workspace profile provisioning was unavailable.');
            }
            var profileWasCommitted = false;
            try {
              final profile = await widget.firestore
                  .collection('users')
                  .doc(activeUser.uid)
                  .get();
              profileWasCommitted =
                  profile.exists &&
                  (profile.data()?['username'] as String?)?.toLowerCase() ==
                      username;
            } catch (_) {
              profileWasCommitted = false;
            }
            if (!profileWasCommitted) {
              try {
                if (signup.created) await activeUser.delete();
                await widget.auth.signOut();
              } catch (_) {
                // A later retry remains safe because registration is
                // idempotent for the same authenticated user and username.
              }
              LoginPasswordVault.instance.clear();
              rethrow;
            }
          }

          final encryptionReady = await _prepareStandardEncryptionKey(
            uid: activeUser.uid,
            email: authEmail,
            password: password,
          );

          if (signupCompletionReconciler != null && accountCreatedAt != null) {
            unawaited(
              signupCompletionReconciler.reconcile(
                authenticatedAccountCreatedAt:
                    activeUser.metadata.creationTime ?? accountCreatedAt,
                tokenProvider: activeUser.getIdToken,
                profileReady: () async => true,
              ),
            );
          }

          messenger.showSnackBar(
            SnackBar(
              content: Text(
                encryptionReady
                    ? 'Account created. Welcome to RonikCloud, ${displayName.isNotEmpty ? displayName : username}!'
                    : 'Account created. Your workspace is finishing setup; uploads may need one retry.',
              ),
            ),
          );
          if (mounted && Navigator.canPop(context)) {
            Navigator.pop(context);
          }
        }
      } else {
        final authEmail = authEmailForLoginIdentifier(identifier);
        await _signInWithPassword(email: authEmail, password: password);
      }
    } on AccountRegistrationException catch (error) {
      AccountEnvironmentStore.instance.cancelPreparedSignIn();
      messenger.showSnackBar(
        SnackBar(content: Text(_mapRegistrationError(error))),
      );
    } on FirebaseAuthException catch (error) {
      AccountEnvironmentStore.instance.cancelPreparedSignIn();
      LoginPasswordVault.instance.clear();
      messenger.showSnackBar(SnackBar(content: Text(_mapErrorMessage(error))));
    } on FirebaseException catch (error) {
      AccountEnvironmentStore.instance.cancelPreparedSignIn();
      messenger.showSnackBar(
        SnackBar(content: Text(_mapFirestoreError(error))),
      );
    } catch (_) {
      AccountEnvironmentStore.instance.cancelPreparedSignIn();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Something went wrong. Please try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadSavedLoginEmail() async {
    final restored = await LoginPasswordVault.instance.restoreCredentials();
    final restoredEmail = restored.email;

    if (!mounted) {
      return;
    }

    setState(() {
      if (!_isRegisterMode &&
          _emailController.text.trim().isEmpty &&
          restoredEmail != null &&
          restoredEmail.isNotEmpty) {
        _emailController.text = isUsernameOnlyAuthEmail(restoredEmail)
            ? restoredEmail.split('@').first
            : restoredEmail;
      }
    });
  }

  Future<void> _signInWithPassword({
    required String email,
    required String password,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final credential = await _traceLoginStage(
      'authenticate',
      () => signInWithPassword(
        auth: widget.auth,
        email: email,
        password: password,
      ),
    );
    LoginPasswordVault.instance.store(email: email, password: password);

    final signedInUser = credential.user;
    if (signedInUser == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Login failed. Please try again.')),
      );
      LoginPasswordVault.instance.clear();
      await widget.auth.signOut();
      return;
    }

    await _traceLoginStage(
      'save-environment',
      () => AccountEnvironmentStore.instance.saveForUser(
        uid: signedInUser.uid,
        environment: _environment,
      ),
    );

    // Authentication has succeeded. Best-effort key preparation must not keep
    // the pushed login route covering the workspace indefinitely while offline.
    await _traceLoginStage(
      'refresh-session',
      () => _ensureAuthenticatedSession(signedInUser.uid).timeout(
        const Duration(seconds: 10),
        onTimeout: () => widget.auth.currentUser,
      ),
    );
    final encryptionReady = await _traceLoginStage(
      'prepare-encryption',
      () => _prepareStandardEncryptionKey(
        uid: signedInUser.uid,
        email: email,
        password: password,
      ).timeout(const Duration(seconds: 15), onTimeout: () => false),
    );

    if (widget.auth.currentUser?.uid != signedInUser.uid) return;
    if (!encryptionReady && mounted) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Signed in. File encryption is still locked; unlock it in your workspace when the connection is available.',
          ),
        ),
      );
    }

    if (credential.additionalUserInfo?.isNewUser ?? false) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Welcome back. Your workspace is ready.')),
      );
    }

    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  // Local debug diagnostics only. Never log arguments, account identifiers,
  // exception messages, tokens, or passwords. Keep the actual future intact:
  // timing out authentication does not cancel the native sign-in operation.
  Future<T> _traceLoginStage<T>(
    String stage,
    Future<T> Function() operation,
  ) async {
    if (!kDebugMode) return operation();
    final clock = Stopwatch()..start();
    debugPrint('[login-flow] $stage/start');
    final warning = Timer(const Duration(seconds: 20), () {
      debugPrint('[login-flow] $stage/still-pending');
    });
    try {
      final result = await operation();
      debugPrint('[login-flow] $stage/complete ${clock.elapsedMilliseconds}ms');
      return result;
    } catch (_) {
      debugPrint('[login-flow] $stage/failed ${clock.elapsedMilliseconds}ms');
      rethrow;
    } finally {
      warning.cancel();
    }
  }

  Future<void> _sendResetLink() async {
    final identifier = _emailController.text.trim();
    final messenger = ScaffoldMessenger.of(context);

    if (identifier.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Enter your email to receive a reset link.'),
        ),
      );
      return;
    }
    if (!identifier.contains('@')) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Username-only accounts do not have email recovery. Contact support if you are locked out.',
          ),
        ),
      );
      return;
    }

    try {
      await widget.auth.sendPasswordResetEmail(email: identifier);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Password reset link sent. Check your inbox.'),
        ),
      );
    } on FirebaseAuthException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(_mapErrorMessage(error))));
    }
  }

  String _mapErrorMessage(FirebaseAuthException error) {
    switch (error.code) {
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'The sign-in details could not be verified. If you registered with an email, use that email instead of your username. Check your password and try again.';
      case 'invalid-email':
        return 'That email or username looks incorrect. Please check and try again.';
      case 'weak-password':
        return 'Choose a stronger password with at least 12 characters.';
      case 'email-already-in-use':
        return 'This email or username is already registered. Try logging in instead.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      case 'network-request-failed':
        return 'Could not reach the sign-in service. Check your connection and try again.';
      case 'user-disabled':
        return 'This account is disabled. Contact support for help.';
      case 'operation-not-allowed':
        return 'Password sign-in is unavailable. Contact support for help.';
      case 'unknown-error':
      case 'auth-service-unavailable':
        return 'The sign-in service could not complete the request. Please retry. If it continues, contact support.';
      default:
        return 'Authentication failed. (${error.code})';
    }
  }

  Future<User?> _waitForAuthenticatedUser(String uid) async {
    for (var attempt = 0; attempt < 25; attempt++) {
      final currentUser = widget.auth.currentUser;
      if (currentUser?.uid == uid) {
        return currentUser;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return widget.auth.currentUser;
  }

  Future<User?> _ensureAuthenticatedSession(String uid) async {
    User? user = widget.auth.currentUser;
    if (user?.uid != uid) {
      user = await _waitForAuthenticatedUser(uid);
    }
    if (user == null || user.uid != uid) {
      return user;
    }

    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        await user!.getIdToken(true);
        await Future<void>.delayed(Duration(milliseconds: 200 * (attempt + 1)));
        final refreshed = widget.auth.currentUser;
        if (refreshed?.uid == uid) {
          return refreshed;
        }
        return user;
      } catch (_) {
        await Future<void>.delayed(Duration(milliseconds: 250 * (attempt + 1)));
        final next = widget.auth.currentUser;
        if (next?.uid == uid) {
          user = next!;
        }
      }
    }
    return user;
  }

  Future<void> _registerAccountProfile({
    required String username,
    required String legalAcceptedAt,
    required bool productUpdatesOptIn,
    required bool recoveryEmailProvided,
    required String createdAt,
  }) async {
    final injectedProvisioner = widget.accountRegistrationProvisioner;
    final provisioner =
        injectedProvisioner ??
        ({
          required String username,
          required String legalVersion,
          required String legalAcceptedAt,
          required bool productUpdatesOptIn,
          required bool recoveryEmailProvided,
          required String createdAt,
        }) => AccountRegistrationService.forApp(widget.auth.app).register(
          username: username,
          legalVersion: legalVersion,
          legalAcceptedAt: legalAcceptedAt,
          productUpdatesOptIn: productUpdatesOptIn,
          recoveryEmailProvided: recoveryEmailProvided,
          createdAt: createdAt,
        );
    AccountRegistrationException? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await provisioner(
          username: username,
          legalVersion: LegalDocuments.legalVersion,
          legalAcceptedAt: legalAcceptedAt,
          productUpdatesOptIn: productUpdatesOptIn,
          recoveryEmailProvided: recoveryEmailProvided,
          createdAt: createdAt,
        );
        return;
      } on AccountRegistrationException catch (error) {
        lastError = error;
        final retryable = const {
          'aborted',
          'deadline-exceeded',
          'internal',
          'unavailable',
        }.contains(error.code);
        if (!retryable || attempt == 2) {
          rethrow;
        }
        await Future<void>.delayed(Duration(milliseconds: 250 * (attempt + 1)));
      }
    }
    throw lastError ??
        const AccountRegistrationException(
          'unavailable',
          'Account setup could not be completed.',
        );
  }

  Future<bool> _prepareStandardEncryptionKey({
    required String uid,
    required String email,
    required String password,
  }) async {
    final injectedPreparer = widget.standardEncryptionPreparer;
    if (injectedPreparer != null) {
      return injectedPreparer(uid: uid, email: email, password: password);
    }
    try {
      await _ensureAuthenticatedSession(uid);
      final setupService = EncryptionSetupService.forApp(widget.auth.app);
      final salt = await setupService.ensureStandardEncryptionSalt();
      final key = await EncryptionService.instance.deriveKey(
        password: password,
        salt: salt,
      );
      final keyString = base64Encode(await key.extractBytes());
      // A timed-out preparation may finish later, after sign-out/account switch.
      if (widget.auth.currentUser?.uid != uid) return false;
      LoginPasswordVault.instance.storeStandardEncryptionKey(
        email: email,
        key: keyString,
        salt: salt,
      );
      return true;
    } catch (_) {
      if (kDebugMode) {
        debugPrint('Standard encryption setup during sign-in was unavailable.');
      }
      return false;
    }
  }

  String _mapFirestoreError(FirebaseException error) {
    switch (error.code) {
      case 'permission-denied':
        return 'We couldn\'t save your workspace profile. Check your Firestore rules.';
      case 'unavailable':
        return 'Cloud Firestore is temporarily unavailable. Please try again shortly.';
      default:
        return 'Saving your workspace profile failed. (${error.code})';
    }
  }

  String _mapRegistrationError(AccountRegistrationException error) {
    switch (error.code) {
      case 'already-exists':
        return 'That username is already taken. Choose another one.';
      case 'invalid-argument':
        return error.message;
      case 'failed-precondition':
        return 'This account profile is already registered. Sign in instead.';
      default:
        return 'Your secure account was created, but profile setup is still retrying. Keep this page open and try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: () => Navigator.pop(context),
              )
            : null,
      ),
      extendBodyBehindAppBar: true,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: 24,
              vertical:
                  _isRegisterMode && MediaQuery.sizeOf(context).width >= 1000
                  ? 12
                  : 32,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth:
                    _isRegisterMode && MediaQuery.sizeOf(context).width >= 1000
                    ? 1000
                    : 480,
              ),
              child: _buildFormCard(),
            ),
          ),
        ),
      ),
    ).withAppPageTitle(
      _isRegisterMode ? 'Create Account | RonikCloud' : 'Sign In | RonikCloud',
    );
  }

  void _setMode(bool value) {
    if (value && !widget.allowRegistration) {
      return;
    }
    if (_isRegisterMode == value) {
      return;
    }
    setState(() {
      _isRegisterMode = value;
      if (!_isRegisterMode) {
        _usernameController.clear();
        _displayNameController.clear();
        _acceptedTermsAndUse = false;
        _acknowledgedPrivacyAndPolicies = false;
        _productUpdatesOptIn = false;
      }
    });
    if (!value) {
      unawaited(_loadSavedLoginEmail());
    } else {
      _recordSignupStarted();
    }
  }

  void _setEnvironment(AccountEnvironment environment) {
    if (_environment == environment) {
      return;
    }
    setState(() {
      _environment = environment;
    });
    unawaited(_loadSavedLoginEmail());
  }

  Widget _buildFormCard() {
    final theme = Theme.of(context);
    final canSubmit = !_isLoading && _hasRequiredLegalConsent;
    final children = <Widget>[
      Text(
        widget.completeSetupMode ? 'Finish account setup' : _isRegisterMode
            ? _environment == AccountEnvironment.business
                  ? 'Create your Business account'
                  : 'Create your RonikCloud account'
            : _environment == AccountEnvironment.business
            ? 'Business sign in'
            : 'Welcome back',
        style: theme.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        widget.completeSetupMode ? 'Confirm your password and account details to activate your 1 GB workspace. No purchase is needed.' : _isRegisterMode
            ? _environment == AccountEnvironment.business
                  ? 'Choose a unique username, subscribe to Business, then set up your company workspace.'
                  : 'Start with 1 GB free. Choose a username and password. No card is required; recovery email is optional.'
            : _environment == AccountEnvironment.business
            ? 'Use your company credentials to open the company workspace.'
            : 'Sign in with your email and password to access your files.',
        style: theme.textTheme.bodyMedium,
      ),
      const SizedBox(height: 24),
      if (!widget.completeSetupMode) _AccountEnvironmentSelector(
        environment: _environment,
        enabled: !_isLoading,
        onChanged: _setEnvironment,
      ),
      if (widget.allowRegistration && !widget.completeSetupMode) ...[
        const SizedBox(height: 16),
        _ModeSelector(
          isRegister: _isRegisterMode,
          onChanged: _isLoading ? null : _setMode,
        ),
      ],
      const SizedBox(height: 24),
      Form(
        key: _formKey,
        child: Column(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: _isRegisterMode
                  ? Column(
                      key: const ValueKey('registerFields'),
                      children: [
                        TextFormField(
                          controller: _usernameController,
                          readOnly: widget.completeSetupMode && isUsernameOnlyAuthEmail(_completionAuthEmail),
                          textCapitalization: TextCapitalization.none,
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          onFieldSubmitted: (_) {
                            FocusScope.of(context).nextFocus();
                          },
                          decoration: const InputDecoration(
                            labelText: 'Unique username',
                            hintText: 'natal_fern',
                          ),
                          validator: (value) => _isRegisterMode
                              ? validateAccountUsername(value)
                              : null,
                        ),
                        const SizedBox(height: 20),
                        TextFormField(
                          controller: _displayNameController,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          onFieldSubmitted: (_) {
                            FocusScope.of(context).nextFocus();
                          },
                          decoration: const InputDecoration(
                            labelText: 'Display name (optional)',
                            hintText: 'Natal Fern',
                          ),
                          validator: (value) =>
                              (value ?? '').trim().length > 120
                              ? 'Display name must be 120 characters or fewer.'
                              : null,
                        ),
                        const SizedBox(height: 20),
                      ],
                    )
                  : const SizedBox(key: ValueKey('loginFieldsGap')),
            ),
            if (!widget.completeSetupMode || !isUsernameOnlyAuthEmail(_completionAuthEmail)) TextFormField(
              controller: _emailController,
              readOnly: widget.completeSetupMode,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              onFieldSubmitted: (_) {
                FocusScope.of(context).nextFocus();
              },
              decoration: InputDecoration(
                labelText: widget.completeSetupMode ? 'Account email' : _isRegisterMode
                    ? 'Recovery email (optional)'
                    : 'Email or username',
                hintText: _isRegisterMode
                    ? 'Leave blank to use only your username'
                    : 'name@company.com or natal_fern',
              ),
              validator: (value) {
                final trimmed = value?.trim() ?? '';
                if (_isRegisterMode && trimmed.isEmpty) {
                  return null;
                }
                if (trimmed.isEmpty) {
                  return 'Enter your email or username.';
                }
                if (_isRegisterMode &&
                    (!trimmed.contains('@') || !trimmed.contains('.'))) {
                  return 'Enter a valid email address.';
                }
                if (!_isRegisterMode &&
                    !trimmed.contains('@') &&
                    validateAccountUsername(trimmed) != null) {
                  return 'Enter a valid email or username.';
                }
                return null;
              },
            ),
            if (_isRegisterMode && !widget.completeSetupMode) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'If you add an email, use that email to sign in. Without email, a lost password cannot be reset by email. A file recovery kit does not reset your account password.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
            const SizedBox(height: 20),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              textInputAction: _isRegisterMode
                  ? TextInputAction.done
                  : TextInputAction.go,
              onFieldSubmitted: (_) {
                if (!_isLoading) {
                  unawaited(_submit());
                }
              },
              decoration: InputDecoration(
                labelText: 'Password',
                hintText: '••••••••',
                suffixIcon: IconButton(
                  tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Enter your password.';
                }
                if (_isRegisterMode && value.length < 12) {
                  return 'Use at least 12 characters for a new password.';
                }
                return null;
              },
            ),
          ],
        ),
      ),
      if (_isRegisterMode) ...[
        const SizedBox(height: 16),
        _LegalConsentBox(
          acceptedTermsAndUse: _acceptedTermsAndUse,
          acknowledgedPrivacyAndPolicies: _acknowledgedPrivacyAndPolicies,
          enabled: !_isLoading,
          onAcceptedTermsAndUseChanged: (value) {
            setState(() {
              _acceptedTermsAndUse = value;
            });
          },
          onAcknowledgedPrivacyAndPoliciesChanged: (value) {
            setState(() {
              _acknowledgedPrivacyAndPolicies = value;
            });
          },
          productUpdatesOptIn: _productUpdatesOptIn,
          onProductUpdatesOptInChanged: (value) {
            setState(() {
              _productUpdatesOptIn = value;
            });
          },
          onOpenDocument: _openLegalDocument,
        ),
      ],
      if (!_isRegisterMode) ...[
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _isLoading ? null : _sendResetLink,
            child: const Text('Forgot your password?'),
          ),
        ),
      ],
      const SizedBox(height: 8),
      Text(
        _isRegisterMode
            ? 'Your legal acceptance is recorded with your account.'
            : 'By logging in, you continue under the current Terms of Service and Privacy Policy.',
        style: theme.textTheme.bodySmall,
      ),
      const SizedBox(height: 24),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: canSubmit ? _submit : null,
          child: _isLoading
              ? SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      theme.colorScheme.primary,
                    ),
                  ),
                )
              : Text(widget.completeSetupMode ? 'Finish setup' : _isRegisterMode ? 'Create account' : 'Login'),
        ),
      ),
      if (widget.completeSetupMode) TextButton(
        onPressed: _isLoading ? null : () async {
          LoginPasswordVault.instance.clear();
          await widget.auth.signOut();
        },
        child: const Text('Sign out'),
      ),
      if (widget.allowRegistration && !widget.completeSetupMode) ...[
        const SizedBox(height: 10),
        Center(
          child: TextButton.icon(
            onPressed: _isLoading
                ? null
                : () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) =>
                            DownloadPage(attribution: widget.attribution),
                      ),
                    );
                  },
            icon: const Icon(Icons.download_outlined),
            label: const Text('Download app for your device'),
          ),
        ),
      ],
      const SizedBox(height: 18),
      Center(
        child: Text(
          'Need help? Contact support@ronikcloud.com.',
          style: theme.textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ),
    ];
    final wide = _isRegisterMode && MediaQuery.sizeOf(context).width >= 1000;
    final formIndex = children.indexWhere((child) => child is Form);
    if (wide) {
      for (var i = 0; i < children.length; i++) {
        final child = children[i];
        if (child is SizedBox && child.height != null) {
          children[i] = SizedBox(height: child.height! / 3);
        }
      }
    }
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(wide ? 16 : 24),
        child: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: children.take(formIndex + 1).toList(),
                    ),
                  ),
                  const SizedBox(width: 32),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: children.skip(formIndex + 1).toList(),
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
      ),
    );
  }

  void _openLegalDocument(LegalDocument document) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => LegalDocumentPage(document: document),
      ),
    );
  }
}

class _AccountEnvironmentSelector extends StatelessWidget {
  const _AccountEnvironmentSelector({
    required this.environment,
    required this.enabled,
    required this.onChanged,
  });

  final AccountEnvironment environment;
  final bool enabled;
  final ValueChanged<AccountEnvironment> onChanged;

  @override
  Widget build(BuildContext context) {
    return AdaptiveChoiceControl<AccountEnvironment>(
      labels: const {
        AccountEnvironment.personal: 'Personal',
        AccountEnvironment.business: 'Business',
      },
      selected: environment,
      onChanged: enabled ? onChanged : null,
    );
  }
}

class _LegalConsentBox extends StatelessWidget {
  const _LegalConsentBox({
    required this.acceptedTermsAndUse,
    required this.acknowledgedPrivacyAndPolicies,
    required this.enabled,
    required this.onAcceptedTermsAndUseChanged,
    required this.onAcknowledgedPrivacyAndPoliciesChanged,
    required this.productUpdatesOptIn,
    required this.onProductUpdatesOptInChanged,
    required this.onOpenDocument,
  });

  final bool acceptedTermsAndUse;
  final bool acknowledgedPrivacyAndPolicies;
  final bool enabled;
  final bool productUpdatesOptIn;
  final ValueChanged<bool> onAcceptedTermsAndUseChanged;
  final ValueChanged<bool> onAcknowledgedPrivacyAndPoliciesChanged;
  final ValueChanged<bool> onProductUpdatesOptInChanged;
  final ValueChanged<LegalDocument> onOpenDocument;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
        color: colorScheme.surfaceContainerLow,
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: acceptedTermsAndUse,
              onChanged: enabled
                  ? (value) => onAcceptedTermsAndUseChanged(value ?? false)
                  : null,
              title: const Text(
                'I agree to the Terms of Service and Acceptable Use Policy.',
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: acknowledgedPrivacyAndPolicies,
              onChanged: enabled
                  ? (value) =>
                        onAcknowledgedPrivacyAndPoliciesChanged(value ?? false)
                  : null,
              title: const Text(
                'I acknowledge the Privacy Policy, Cancellation and Refund Policy, Data Retention Policy, and Subprocessors list.',
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: productUpdatesOptIn,
              onChanged: enabled
                  ? (value) => onProductUpdatesOptInChanged(value ?? false)
                  : null,
              title: const Text(
                'Send me product updates, release notes, and service news.',
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 4,
                children: [
                  _LegalLinkButton(
                    label: 'Terms of Service',
                    document: LegalDocuments.terms,
                    onOpenDocument: onOpenDocument,
                  ),
                  _LegalLinkButton(
                    label: 'Privacy Policy',
                    document: LegalDocuments.privacy,
                    onOpenDocument: onOpenDocument,
                  ),
                  _LegalLinkButton(
                    label: 'Acceptable Use',
                    document: LegalDocuments.acceptableUse,
                    onOpenDocument: onOpenDocument,
                  ),
                  _LegalLinkButton(
                    label: 'Cancellation and Refund',
                    document: LegalDocuments.cancellationRefund,
                    onOpenDocument: onOpenDocument,
                  ),
                  _LegalLinkButton(
                    label: 'Data Retention',
                    document: LegalDocuments.dataRetention,
                    onOpenDocument: onOpenDocument,
                  ),
                  _LegalLinkButton(
                    label: 'Subprocessors',
                    document: LegalDocuments.subprocessors,
                    onOpenDocument: onOpenDocument,
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

class _LegalLinkButton extends StatelessWidget {
  const _LegalLinkButton({
    required this.label,
    required this.document,
    required this.onOpenDocument,
  });

  final String label;
  final LegalDocument document;
  final ValueChanged<LegalDocument> onOpenDocument;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => onOpenDocument(document),
      child: Text(label),
    );
  }
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.isRegister, required this.onChanged});
  final bool isRegister;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => AdaptiveChoiceControl<bool>(
    labels: const {false: 'Login', true: 'Create account'},
    selected: isRegister,
    onChanged: onChanged,
  );
}
