import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';

import 'native_auth_session.dart';

part 'native_firebase_user.dart';

class NativeFirebaseAuth extends FirebaseAuthPlatform {
  NativeFirebaseAuth({required this.sessionFor, FirebaseApp? app})
    : super(appInstance: app);
  final NativeAuthSession Function(String appName) sessionFor;
  final Map<String, NativeFirebaseAuth> _delegates = {};
  String? _languageCode;
  NativeAuthSession get session => sessionFor(app.name);

  @override
  FirebaseAuthPlatform delegateFor({required FirebaseApp app}) =>
      _delegates.putIfAbsent(
        app.name,
        () => NativeFirebaseAuth(sessionFor: sessionFor, app: app),
      );
  @override
  FirebaseAuthPlatform setInitialValues({
    PigeonUserDetails? currentUser,
    String? languageCode,
  }) {
    if (languageCode != null) _languageCode = languageCode;
    return this;
  }

  @override
  UserPlatform? get currentUser {
    final identity = session.currentIdentity;
    return identity == null ? null : _NativeUser(this, identity);
  }

  @override
  String? get languageCode => _languageCode;
  @override
  Future<void> setLanguageCode(String? languageCode) async {
    if (languageCode != null &&
        !RegExp(r'^[A-Za-z0-9-]{1,35}$').hasMatch(languageCode)) {
      throw ArgumentError('Invalid language code.');
    }
    _languageCode = languageCode;
  }

  @override
  Future<void> useAuthEmulator(String host, int port) async {
    if (!const {'localhost', '127.0.0.1'}.contains(host) ||
        session.transport.emulatorPort != port) {
      throw FirebaseAuthException(
        code: 'operation-not-allowed',
        message:
            'Configure the loopback emulator before initializing native Firebase.',
      );
    }
  }

  Stream<UserPlatform?> _events() => Stream.multi((controller) {
    final subscription = session.changes.listen(
      (identity) =>
          controller.add(identity == null ? null : _NativeUser(this, identity)),
      onError: controller.addError,
      onDone: controller.close,
    );
    controller.add(currentUser);
    controller.onCancel = subscription.cancel;
  });
  @override
  Stream<UserPlatform?> authStateChanges() =>
      _events().distinct((a, b) => a?.uid == b?.uid);
  @override
  Stream<UserPlatform?> idTokenChanges() => _events();
  @override
  Stream<UserPlatform?> userChanges() => _events();

  void _validateTenant() {
    if (tenantId != null) {
      throw FirebaseAuthException(
        code: 'operation-not-allowed',
        message: 'This native client uses the application account project.',
      );
    }
  }

  @override
  Future<UserCredentialPlatform> signInWithEmailAndPassword(
    String email,
    String password,
  ) async {
    _validateTenant();
    return _Credential(
      this,
      _NativeUser(this, await session.signIn(email, password)),
    );
  }

  @override
  Future<UserCredentialPlatform> createUserWithEmailAndPassword(
    String email,
    String password,
  ) async {
    _validateTenant();
    return _Credential(
      this,
      _NativeUser(this, await session.createAccount(email, password)),
      isNewUser: true,
    );
  }

  @override
  Future<UserCredentialPlatform> signInWithCustomToken(String token) async {
    _validateTenant();
    return _Credential(
      this,
      _NativeUser(this, await session.signInWithCustomToken(token)),
    );
  }

  @override
  Future<UserCredentialPlatform> signInWithCredential(
    AuthCredential credential,
  ) {
    if (credential is EmailAuthCredential && credential.password != null) {
      return signInWithEmailAndPassword(credential.email, credential.password!);
    }
    throw FirebaseAuthException(
      code: 'operation-not-allowed',
      message: 'Use the account email and password to sign in.',
    );
  }

  @override
  Future<void> signOut() => session.signOut();
  @override
  Future<void> sendPasswordResetEmail(
    String email, [
    ActionCodeSettings? actionCodeSettings,
  ]) async {
    await session.transport.account('sendOobCode', {
      'requestType': 'PASSWORD_RESET',
      'email': email,
      ..._actionSettings(actionCodeSettings),
    }, languageCode: languageCode);
  }

  @override
  Future<void> confirmPasswordReset(String code, String newPassword) async {
    await session.transport.account('resetPassword', {
      'oobCode': code,
      'newPassword': newPassword,
    });
  }

  @override
  Future<String> verifyPasswordResetCode(String code) async {
    final response = await session.transport.account('resetPassword', {
      'oobCode': code,
    });
    final email = response['email'];
    if (email is! String) {
      throw FirebaseAuthException(code: 'invalid-action-code');
    }
    return email;
  }

  @override
  Future<void> applyActionCode(String code) async {
    await session.transport.account('update', {'oobCode': code});
  }

  @override
  Future<void> initializeRecaptchaConfig() async {}

  static Map<String, Object?> _actionSettings(ActionCodeSettings? settings) =>
      settings == null
      ? {}
      : {
          'continueUrl': settings.url,
          'canHandleCodeInApp': settings.handleCodeInApp,
          if (settings.iOSBundleId != null) 'iOSBundleId': settings.iOSBundleId,
          if (settings.androidPackageName != null)
            'androidPackageName': settings.androidPackageName,
          if (settings.androidPackageName != null)
            'androidInstallApp': settings.androidInstallApp,
          if (settings.androidMinimumVersion != null)
            'androidMinimumVersion': settings.androidMinimumVersion,
          if (settings.linkDomain != null) 'linkDomain': settings.linkDomain,
        };
}

class _Credential extends UserCredentialPlatform {
  _Credential(
    NativeFirebaseAuth auth,
    UserPlatform user, {
    bool isNewUser = false,
  }) : super(
         auth: auth,
         user: user,
         additionalUserInfo: AdditionalUserInfo(
           isNewUser: isNewUser,
           providerId: 'password',
         ),
       );
}
