import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:base32/base32.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../authentication/account_closure_dialog.dart';
import '../authentication/account_closure_request_service.dart';
import '../authentication/account_deletion_service.dart';
import '../authentication/biometric_auth_service.dart';
import '../authentication/login_password_vault.dart';
import '../authentication/two_factor_service.dart';
import '../security/encryption_recovery_kit.dart';
import '../shared/app_page_title.dart';
import '../shared/user_facing_client_failure.dart';
import '../storage/drive_repository.dart';
import '../storage/wasabi_storage_service.dart';
import 'encryption_recovery_panel.dart';

typedef ValidateRecoveryMaterial =
    Future<bool> Function(StandardEncryptionRecoveryMaterial material);
typedef ApplyRecoveryMaterial =
    Future<void> Function(StandardEncryptionRecoveryMaterial material);

class SecuritySettingsPage extends StatefulWidget {
  const SecuritySettingsPage({
    super.key,
    required this.user,
    required this.firestore,
    this.validateRecoveryMaterial,
    this.onRecoveryMaterialImported,
    this.onSecurityChanged,
    this.twoFactorApi,
  });

  final VoidCallback? onSecurityChanged;
  final User user;
  final FirebaseFirestore firestore;
  final TwoFactorApi? twoFactorApi;
  final ValidateRecoveryMaterial? validateRecoveryMaterial;
  final ApplyRecoveryMaterial? onRecoveryMaterialImported;

  @override
  State<SecuritySettingsPage> createState() => _SecuritySettingsPageState();
}

class _SecuritySettingsPageState extends State<SecuritySettingsPage> {
  late final TwoFactorApi _twoFactorApi;
  final BiometricSignInPreferenceStore _biometricPreferenceStore =
      BiometricSignInPreferenceStore.instance;
  bool _isLoading = true;
  bool _settingsLoadFailed = false;
  bool _is2FAEnabled = false;
  bool _biometricSignInEnabled = false;
  bool _biometricSignInSupported = false;
  bool _biometricBusy = false;
  bool _recoveryBusy = false;
  final EncryptionRecoveryKitService _recoveryKitService =
      EncryptionRecoveryKitService();

  @override
  void initState() {
    super.initState();
    _twoFactorApi =
        widget.twoFactorApi ??
        FirebaseTwoFactorApi.forApp(widget.firestore.app);
    _loadSecuritySettings();
  }

  Future<void> _loadSecuritySettings() async {
    if (mounted && !_isLoading) {
      setState(() => _isLoading = true);
    }
    try {
      final statusFuture = _twoFactorApi.fetchStatus();

      final status = await statusFuture;
      await _biometricPreferenceStore.setEnabledForEmail(
        widget.user.email,
        false,
      );
      if (mounted) {
        setState(() {
          _is2FAEnabled = status.enabled;
          _biometricSignInSupported = false;
          _biometricSignInEnabled = false;
          _settingsLoadFailed = false;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userFacingClientFailureMessage(
                UserFacingClientFailure.securitySettingsLoad,
              ),
            ),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () => unawaited(_loadSecuritySettings()),
            ),
          ),
        );
        setState(() {
          _isLoading = false;
          _settingsLoadFailed = true;
        });
      }
    }
  }

  Future<void> _setBiometricSignInEnabled(bool value) async {
    if (_biometricBusy || value == _biometricSignInEnabled) {
      return;
    }

    if (value && !_biometricSignInSupported) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Biometric sign-in is unavailable because RonikCloud no longer stores login passwords on this device.',
            ),
          ),
        );
      }
      return;
    }

    setState(() => _biometricBusy = true);
    try {
      await _biometricPreferenceStore.setEnabledForEmail(
        widget.user.email,
        value,
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _biometricSignInEnabled = value;
        _biometricBusy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value
                ? 'Biometric sign-in is enabled on this device.'
                : 'Biometric sign-in is turned off on this device.',
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userFacingClientFailureMessage(
                UserFacingClientFailure.biometricPreferenceUpdate,
              ),
            ),
          ),
        );
        setState(() => _biometricBusy = false);
      }
    }
  }

  Future<void> _disable2FA() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disable 2FA?'),
        content: const Text(
          'This will remove the extra layer of security from your account. Are you sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Disable'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    final code = await _promptForTwoFactorCode(title: 'Confirm disabling 2FA');
    if (code == null) {
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _twoFactorApi.verifyCode(code);
      await _twoFactorApi.disable();
      widget.onSecurityChanged?.call();
      if (mounted) {
        setState(() {
          _is2FAEnabled = false;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userFacingClientFailureMessage(
                UserFacingClientFailure.twoFactorDisable,
              ),
            ),
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<String?> _promptForTwoFactorCode({
    String title = 'Confirm 2FA code',
  }) async {
    final controller = TextEditingController();
    String? errorText;
    try {
      return await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(title),
            content: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: InputDecoration(
                labelText: 'Authenticator code',
                errorText: errorText,
              ),
              onSubmitted: (_) {
                final code = controller.text.trim();
                if (code.length == 6) {
                  Navigator.pop(context, code);
                  return;
                }
                setDialogState(() => errorText = 'Enter a 6-digit code');
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final code = controller.text.trim();
                  if (code.length != 6) {
                    setDialogState(() => errorText = 'Enter a 6-digit code');
                    return;
                  }
                  Navigator.pop(context, code);
                },
                child: const Text('Confirm'),
              ),
            ],
          ),
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  void _showSetupDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _Setup2FADialog(
        userEmail: widget.user.email,
        twoFactorApi: _twoFactorApi,
        onSuccess: () {
          widget.onSecurityChanged?.call();
          setState(() => _is2FAEnabled = true);
        },
      ),
    );
  }

  Future<void> _createRecoveryKit() async {
    if (_recoveryBusy) {
      return;
    }
    setState(() => _recoveryBusy = true);
    try {
      final accountPassword = await _verifySensitiveRecoveryAction(
        'Create encryption recovery kit',
      );
      if (accountPassword == null || !mounted) {
        return;
      }
      final encryptionSalt = await _loadStandardEncryptionSalt();
      final encodedKey = await LoginPasswordVault.instance
          .restoreStandardEncryptionKey(
            expectedEmail: widget.user.email,
            expectedSalt: encryptionSalt,
          );
      if (encodedKey == null || encodedKey.isEmpty) {
        _showMessage(
          'Unlock your encrypted workspace on this device first, then create the recovery kit.',
        );
        return;
      }
      final standardKey = base64Decode(encodedKey);
      if (standardKey.length != 32) {
        throw const EncryptionRecoveryKitException(
          EncryptionRecoveryKitFailure.invalidInput,
          'The device encryption key is invalid.',
        );
      }
      final recoveryPassphrase = await _promptNewRecoveryPassphrase(
        accountPassword: accountPassword,
      );
      if (recoveryPassphrase == null || !mounted) {
        return;
      }
      final environmentId = _environmentId();
      final material = StandardEncryptionRecoveryMaterial(
        accountUid: widget.user.uid,
        environmentId: environmentId,
        encryptionSalt: encryptionSalt,
        standardKey: standardKey,
        createdAt: DateTime.now().toUtc(),
      );
      final validate = widget.validateRecoveryMaterial;
      if (validate != null && !await validate(material)) {
        throw const EncryptionRecoveryKitException(
          EncryptionRecoveryKitFailure.authenticationFailed,
          'The current device key could not unlock the encrypted workspace.',
        );
      }
      final encodedKit = await _recoveryKitService.create(
        material: material,
        recoveryPassphrase: recoveryPassphrase,
      );
      if (!mounted) {
        return;
      }

      final box = context.findRenderObject() as RenderBox?;
      final origin = box == null
          ? null
          : (box.localToGlobal(Offset.zero) & box.size);
      await Share.shareXFiles(
        <XFile>[
          XFile.fromData(
            encodedKit,
            name: EncryptionRecoveryKitService.suggestedFileName,
            mimeType: 'application/json',
            length: encodedKit.length,
          ),
        ],
        text:
            'RonikCloud encryption recovery kit. Keep this file separate from its recovery passphrase.',
        sharePositionOrigin: origin,
      );
      _showMessage(
        'Recovery kit created. Keep the file and recovery passphrase separately.',
      );
    } on FirebaseAuthException catch (error) {
      _showMessage(_messageForRecentAuthFailure(error));
    } on EncryptionRecoveryKitException catch (error) {
      _showMessage(_messageForRecoveryKitFailure(error, restoring: false));
    } on FormatException {
      _showMessage('The device encryption key is damaged.');
    } catch (_) {
      _showMessage('Could not create the recovery kit.');
    } finally {
      if (mounted) {
        setState(() => _recoveryBusy = false);
      }
    }
  }

  Future<void> _restoreRecoveryKit() async {
    if (_recoveryBusy) {
      return;
    }
    setState(() => _recoveryBusy = true);
    try {
      final selection = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: true,
      );
      if (selection == null || selection.files.isEmpty || !mounted) {
        return;
      }
      final selected = selection.files.single;
      final encodedKit = selected.bytes;
      if (encodedKit == null ||
          encodedKit.isEmpty ||
          encodedKit.length > EncryptionRecoveryKitService.maximumKitBytes) {
        _showMessage('Choose a valid RonikCloud recovery-kit file.');
        return;
      }

      final accountPassword = await _verifySensitiveRecoveryAction(
        'Restore encryption recovery kit',
      );
      if (accountPassword == null || !mounted) {
        return;
      }
      final recoveryPassphrase = await _promptRecoveryPassphrase();
      if (recoveryPassphrase == null || !mounted) {
        return;
      }
      final encryptionSalt = await _loadStandardEncryptionSalt();
      final material = await _recoveryKitService.open(
        encodedKit: encodedKit,
        recoveryPassphrase: recoveryPassphrase,
        expectedAccountUid: widget.user.uid,
        expectedEnvironmentId: _environmentId(),
        expectedEncryptionSalt: encryptionSalt,
      );
      final validate = widget.validateRecoveryMaterial;
      if (validate != null && !await validate(material)) {
        throw const EncryptionRecoveryKitException(
          EncryptionRecoveryKitFailure.authenticationFailed,
          'This recovery kit could not unlock the encrypted workspace.',
        );
      }

      await LoginPasswordVault.instance.storeStandardEncryptionKeyPersisted(
        email: widget.user.email,
        key: base64Encode(material.standardKey),
        salt: material.encryptionSalt,
      );
      await widget.onRecoveryMaterialImported?.call(material);
      _showMessage(
        'Encryption access restored on this device. The kit and passphrase were not uploaded.',
      );
    } on FirebaseAuthException catch (error) {
      _showMessage(_messageForRecentAuthFailure(error));
    } on EncryptionRecoveryKitException catch (error) {
      _showMessage(_messageForRecoveryKitFailure(error, restoring: true));
    } catch (_) {
      _showMessage('Could not restore this recovery kit.');
    } finally {
      if (mounted) {
        setState(() => _recoveryBusy = false);
      }
    }
  }

  Future<String?> _verifySensitiveRecoveryAction(
    String title, {
    String twoFactorTitle = 'Confirm encryption recovery',
  }) async {
    final password = await _promptCurrentAccountPassword(title);
    if (password == null || password.isEmpty) {
      return null;
    }
    final email = widget.user.email?.trim();
    if (email == null || email.isEmpty) {
      throw FirebaseAuthException(
        code: 'missing-email',
        message: 'This account does not have a password sign-in email.',
      );
    }
    await widget.user.reauthenticateWithCredential(
      EmailAuthProvider.credential(email: email, password: password),
    );
    await widget.user.reload();
    await widget.user.getIdToken(true);
    if (_is2FAEnabled) {
      final code = await _promptForTwoFactorCode(title: twoFactorTitle);
      if (code == null) {
        return null;
      }
      await _twoFactorApi.verifyCode(code);
    }
    return password;
  }

  Future<String?> _promptCurrentAccountPassword(String title) async {
    final controller = TextEditingController();
    var obscure = true;
    try {
      return await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Confirm your current account password. It is used only for recent authentication and is not stored.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  obscureText: obscure,
                  autofillHints: const <String>[AutofillHints.password],
                  decoration: InputDecoration(
                    labelText: 'Current account password',
                    suffixIcon: IconButton(
                      tooltip: obscure ? 'Show password' : 'Hide password',
                      onPressed: () {
                        setDialogState(() => obscure = !obscure);
                      },
                      icon: Icon(
                        obscure ? Icons.visibility : Icons.visibility_off,
                      ),
                    ),
                  ),
                  onSubmitted: (_) {
                    if (controller.text.isNotEmpty) {
                      Navigator.pop(context, controller.text);
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (controller.text.isNotEmpty) {
                    Navigator.pop(context, controller.text);
                  }
                },
                child: const Text('Confirm'),
              ),
            ],
          ),
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<String?> _promptNewRecoveryPassphrase({
    required String accountPassword,
  }) async {
    final first = TextEditingController();
    final confirmation = TextEditingController();
    String? errorText;
    var obscure = true;
    try {
      return await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) {
            void submit() {
              final value = first.text;
              if (value.length <
                  EncryptionRecoveryKitService.minimumPassphraseLength) {
                setDialogState(() {
                  errorText =
                      'Use at least 16 characters or four random words.';
                });
                return;
              }
              if (value == accountPassword) {
                setDialogState(() {
                  errorText =
                      'Use a different passphrase from your account password.';
                });
                return;
              }
              if (value != confirmation.text) {
                setDialogState(() {
                  errorText = 'The recovery passphrases do not match.';
                });
                return;
              }
              Navigator.pop(context, value);
            }

            return AlertDialog(
              title: const Text('Protect your recovery kit'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Choose a separate passphrase that RonikCloud does not know. Store it separately from the kit. If both are lost, support cannot recover encrypted data.',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: first,
                      autofocus: true,
                      obscureText: obscure,
                      decoration: InputDecoration(
                        labelText: 'Recovery passphrase',
                        helperText:
                            'At least 16 characters; four words work well',
                        errorText: errorText,
                        suffixIcon: IconButton(
                          tooltip: obscure
                              ? 'Show passphrases'
                              : 'Hide passphrases',
                          onPressed: () {
                            setDialogState(() => obscure = !obscure);
                          },
                          icon: Icon(
                            obscure ? Icons.visibility : Icons.visibility_off,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: confirmation,
                      obscureText: obscure,
                      decoration: const InputDecoration(
                        labelText: 'Confirm recovery passphrase',
                      ),
                      onSubmitted: (_) => submit(),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: submit,
                  child: const Text('Create encrypted kit'),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      first.dispose();
      confirmation.dispose();
    }
  }

  Future<String?> _promptRecoveryPassphrase() async {
    final controller = TextEditingController();
    String? errorText;
    var obscure = true;
    try {
      return await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) {
            void submit() {
              if (controller.text.length <
                  EncryptionRecoveryKitService.minimumPassphraseLength) {
                setDialogState(() {
                  errorText = 'Enter the recovery passphrase for this kit.';
                });
                return;
              }
              Navigator.pop(context, controller.text);
            }

            return AlertDialog(
              title: const Text('Open recovery kit'),
              content: TextField(
                controller: controller,
                autofocus: true,
                obscureText: obscure,
                decoration: InputDecoration(
                  labelText: 'Recovery passphrase',
                  errorText: errorText,
                  suffixIcon: IconButton(
                    tooltip: obscure ? 'Show passphrase' : 'Hide passphrase',
                    onPressed: () {
                      setDialogState(() => obscure = !obscure);
                    },
                    icon: Icon(
                      obscure ? Icons.visibility : Icons.visibility_off,
                    ),
                  ),
                ),
                onSubmitted: (_) => submit(),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: submit,
                  child: const Text('Restore encryption access'),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<Uint8List> _loadStandardEncryptionSalt() async {
    final snapshot = await widget.firestore
        .collection('users')
        .doc(widget.user.uid)
        .get();
    final encoded = snapshot.data()?['encryptionSalt'];
    if (encoded is! String || encoded.trim().isEmpty) {
      throw const EncryptionRecoveryKitException(
        EncryptionRecoveryKitFailure.invalidInput,
        'Set up standard encryption in the workspace before using a recovery kit.',
      );
    }
    try {
      final salt = Uint8List.fromList(base64Decode(encoded.trim()));
      if (salt.length < 16) {
        throw const FormatException();
      }
      return salt;
    } on FormatException {
      throw const EncryptionRecoveryKitException(
        EncryptionRecoveryKitFailure.invalidInput,
        'The account encryption setup is invalid.',
      );
    }
  }

  String _environmentId() {
    final projectId = widget.firestore.app.options.projectId.trim();
    if (projectId.isEmpty) {
      throw const EncryptionRecoveryKitException(
        EncryptionRecoveryKitFailure.invalidInput,
        'The RonikCloud environment identity is unavailable.',
      );
    }
    return projectId;
  }

  String _messageForRecentAuthFailure(FirebaseAuthException error) {
    final code = error.code.toLowerCase();
    if (code == 'wrong-password' ||
        code == 'invalid-credential' ||
        code == 'invalid-login-credentials') {
      return 'The current account password was not accepted.';
    }
    return 'Recent account verification failed. Try again before managing recovery.';
  }

  String _messageForRecoveryKitFailure(
    EncryptionRecoveryKitException error, {
    required bool restoring,
  }) {
    if (!restoring) {
      return userFacingClientFailureMessage(
        UserFacingClientFailure.recoveryKitCreate,
      );
    }
    final failure = switch (error.failure) {
      EncryptionRecoveryKitFailure.invalidInput ||
      EncryptionRecoveryKitFailure.invalidFormat =>
        UserFacingClientFailure.recoveryKitInvalid,
      EncryptionRecoveryKitFailure.authenticationFailed =>
        UserFacingClientFailure.recoveryKitAuthentication,
      EncryptionRecoveryKitFailure.accountMismatch =>
        UserFacingClientFailure.recoveryKitAccountMismatch,
      EncryptionRecoveryKitFailure.environmentMismatch =>
        UserFacingClientFailure.recoveryKitEnvironmentMismatch,
      EncryptionRecoveryKitFailure.encryptionSaltMismatch =>
        UserFacingClientFailure.recoveryKitEncryptionMismatch,
    };
    return userFacingClientFailureMessage(failure);
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _deleteAccount() async {
    setState(() => _isLoading = true);
    Map<String, dynamic>? profileData;

    try {
      final doc = await widget.firestore
          .collection('users')
          .doc(widget.user.uid)
          .get();
      profileData = doc.data();
    } catch (_) {
      // The shared confirmation still explains permanent deletion when billing
      // status cannot be refreshed. The backend remains authoritative.
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }

    if (!mounted) {
      return;
    }

    final action = await showAccountClosureDialog(
      context: context,
      profileData: profileData,
    );

    if (action == AccountClosureAction.cancel) {
      return;
    }

    try {
      final verified = await _verifySensitiveRecoveryAction(
        action == AccountClosureAction.requestClosure
            ? 'Request account closure'
            : 'Delete account',
        twoFactorTitle: action == AccountClosureAction.requestClosure
            ? 'Confirm account closure request'
            : 'Confirm account deletion',
      );
      if (verified == null || !mounted) {
        return;
      }
    } on FirebaseAuthException catch (error) {
      _showMessage(_messageForRecentAuthFailure(error));
      return;
    } catch (_) {
      _showMessage('Could not confirm your identity. Try again.');
      return;
    }

    final auth = FirebaseAuth.instanceFor(app: widget.firestore.app);
    if (action == AccountClosureAction.requestClosure) {
      setState(() => _isLoading = true);
      try {
        final receipt = await AccountClosureRequestService(auth: auth).submit();
        if (!mounted) return;
        setState(() => _isLoading = false);
        await showAccountClosureRequestRecordedDialog(
          context: context,
          alreadyRequested: receipt.alreadyRequested,
          status: receipt.status,
          receiptUrl: receipt.receiptUrl,
        );
      } on AccountClosureRequestException catch (error) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        await showAccountClosureRequestFallbackDialog(
          context: context,
          message: error.message,
        );
      } catch (_) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        await showAccountClosureRequestFallbackDialog(
          context: context,
          message: 'The closure request could not be recorded.',
        );
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      final service = AccountDeletionService(
        auth: auth,
        firestore: widget.firestore,
        wasabiService: WasabiStorageService.fromEnvironment(),
        driveRepository: DriveRepository(firestore: widget.firestore),
      );

      await service.deleteAccount();
      await auth.signOut();

      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on AccountDeletionException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
        setState(() => _isLoading = false);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Account deletion did not finish. Sign-in was preserved, but some provider cleanup may already be complete. Retry, or contact support before uploading or purchasing again.',
            ),
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account Security')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _settingsLoadFailed
          ? Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 540),
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(24),
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: Theme.of(context).colorScheme.error,
                      size: 40,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      userFacingClientFailureMessage(
                        UserFacingClientFailure.securitySettingsLoad,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () => unawaited(_loadSecuritySettings()),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              children: [
                ListTile(
                  leading: const Icon(Icons.fingerprint),
                  title: const Text('Biometric Sign-In'),
                  subtitle: Text(
                    _biometricSignInSupported
                        ? _biometricSignInEnabled
                              ? 'Enabled on this device. You can use biometrics or Windows Hello on the login screen.'
                              : 'Off by default. Turn this on only if you want faster sign-in on this device.'
                        : 'Unavailable because RonikCloud no longer stores login passwords on this device.',
                  ),
                  trailing: Switch(
                    value: _biometricSignInEnabled,
                    onChanged: !_biometricSignInSupported || _biometricBusy
                        ? null
                        : (value) =>
                              unawaited(_setBiometricSignInEnabled(value)),
                  ),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.security),
                  title: const Text('Two-Factor Authentication'),
                  subtitle: Text(
                    _is2FAEnabled
                        ? 'Enabled. You will be asked for a code when signing in.'
                        : 'Disabled. Add an extra layer of security to your account.',
                  ),
                  trailing: Switch(
                    value: _is2FAEnabled,
                    onChanged: (value) {
                      if (value) {
                        _showSetupDialog();
                      } else {
                        _disable2FA();
                      }
                    },
                  ),
                ),
                const Divider(),
                EncryptionRecoveryPanel(
                  busy: _recoveryBusy,
                  onCreate: () => unawaited(_createRecoveryKit()),
                  onRestore: () => unawaited(_restoreRecoveryKit()),
                ),
                const Divider(),
                ListTile(
                  leading: Icon(
                    Icons.delete_forever,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(
                    selfServiceAccountDeletionEnabled
                        ? 'Delete account'
                        : 'Request account closure',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  subtitle: Text(
                    selfServiceAccountDeletionEnabled
                        ? 'Permanently remove your personal account and files; limited legal, security, billing, and organization records may remain.'
                        : 'Submit a verified support request. Your sign-in, access, data, and billing remain active until support confirms and performs closure.',
                  ),
                  onTap: _deleteAccount,
                ),
              ],
            ),
    ).withAppPageTitle('Account Security | RonikCloud');
  }
}

class _Setup2FADialog extends StatefulWidget {
  const _Setup2FADialog({
    required this.userEmail,
    required this.twoFactorApi,
    required this.onSuccess,
  });

  final String? userEmail;
  final TwoFactorApi twoFactorApi;
  final VoidCallback onSuccess;

  @override
  State<_Setup2FADialog> createState() => _Setup2FADialogState();
}

class _Setup2FADialogState extends State<_Setup2FADialog> {
  late final String _secret;
  final TextEditingController _codeController = TextEditingController();
  bool _verifying = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _secret = _generateSecret();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  String _generateSecret() {
    final random = Random.secure();
    final bytes = Uint8List(10);
    for (var index = 0; index < bytes.length; index++) {
      bytes[index] = random.nextInt(256);
    }
    return base32.encode(bytes).replaceAll('=', '');
  }

  String get _otpAuthUrl {
    final email = widget.userEmail ?? 'user@ronikdrive';
    const issuer = 'RonikCloud';
    return 'otpauth://totp/$issuer:$email?secret=$_secret&issuer=$issuer';
  }

  Future<void> _verifyAndEnable() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter a 6-digit code');
      return;
    }

    setState(() {
      _verifying = true;
      _error = null;
    });

    try {
      await widget.twoFactorApi.enable(secret: _secret, code: code);
      widget.onSuccess();
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = userFacingClientFailureMessage(
            UserFacingClientFailure.twoFactorEnable,
          );
          _verifying = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Setup 2FA'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Scan this QR code with your authenticator app (for example Google Authenticator or Authy).',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: 200,
              height: 200,
              child: QrImageView(data: _otpAuthUrl, version: QrVersions.auto),
            ),
            const SizedBox(height: 16),
            SelectableText(
              'Secret: $_secret',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: InputDecoration(
                labelText: 'Enter 6-digit code',
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _verifying ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _verifying ? null : _verifyAndEnable,
          child: _verifying
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Verify & Enable'),
        ),
      ],
    );
  }
}
