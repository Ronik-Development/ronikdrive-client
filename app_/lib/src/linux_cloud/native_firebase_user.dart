part of 'native_firebase_auth.dart';

class _NativeUser extends UserPlatform {
  factory _NativeUser(NativeFirebaseAuth auth, NativeAuthIdentity identity) =>
      _NativeUser._(auth, _details(identity));
  _NativeUser._(this.nativeAuth, this._snapshot)
    : super(nativeAuth, _AppMultiFactor(nativeAuth), _snapshot);
  final NativeFirebaseAuth nativeAuth;
  final PigeonUserDetails _snapshot;
  NativeAuthSession get session => nativeAuth.session;
  static PigeonUserDetails _details(NativeAuthIdentity identity) {
    final data = identity.account;
    final providers = data['providerUserInfo'];
    return PigeonUserDetails(
      userInfo: PigeonUserInfo(
        uid: identity.uid,
        email: data['email'] as String?,
        displayName: data['displayName'] as String?,
        photoUrl: data['photoUrl'] as String?,
        phoneNumber: data['phoneNumber'] as String?,
        isAnonymous: false,
        isEmailVerified: data['emailVerified'] == true,
        creationTimestamp: int.tryParse('${data['createdAt']}'),
        lastSignInTimestamp: int.tryParse('${data['lastLoginAt']}'),
      ),
      providerData: providers is List
          ? providers
                .whereType<Map>()
                .map(
                  (p) => <Object?, Object?>{
                    'uid': p['rawId'] ?? identity.uid,
                    'providerId': p['providerId'],
                    'email': p['email'],
                    'displayName': p['displayName'],
                    'photoUrl': p['photoUrl'],
                    'phoneNumber': p['phoneNumber'],
                    'isAnonymous': false,
                    'isEmailVerified': data['emailVerified'] == true,
                  },
                )
                .toList()
          : [],
    );
  }

  @override
  Future<String?> getIdToken(bool forceRefresh) =>
      session.idToken(forUid: uid, forceRefresh: forceRefresh);
  @override
  Future<IdTokenResult> getIdTokenResult(bool forceRefresh) async {
    final token = await session.idToken(
      forUid: uid,
      forceRefresh: forceRefresh,
    );
    final claims = Map<String, dynamic>.from(
      jsonDecode(
            utf8.decode(
              base64Url.decode(base64Url.normalize(token.split('.')[1])),
            ),
          )
          as Map,
    );
    final firebase = claims['firebase'];
    int? millis(String key) =>
        claims[key] is int ? (claims[key] as int) * 1000 : null;
    return IdTokenResult(
      PigeonIdTokenResult(
        token: token,
        claims: Map<String?, Object?>.from(claims),
        expirationTimestamp: millis('exp'),
        authTimestamp: millis('auth_time'),
        issuedAtTimestamp: millis('iat'),
        signInProvider: firebase is Map
            ? firebase['sign_in_provider'] as String?
            : null,
        signInSecondFactor: firebase is Map
            ? firebase['sign_in_second_factor'] as String?
            : null,
      ),
    );
  }

  @override
  Future<void> reload() async {
    await session.reload(uid);
    _synchronize();
  }

  void _synchronize() {
    final identity = session.currentIdentity;
    if (identity == null || identity.uid != uid) return;
    final refreshed = _details(identity);
    _snapshot.userInfo = refreshed.userInfo;
    _snapshot.providerData = refreshed.providerData;
  }

  @override
  Future<UserCredentialPlatform> reauthenticateWithCredential(
    AuthCredential credential,
  ) async {
    if (credential is! EmailAuthCredential || credential.password == null) {
      throw FirebaseAuthException(code: 'operation-not-allowed');
    }
    final identity = await session.reauthenticate(
      uid,
      credential.email,
      credential.password!,
    );
    _synchronize();
    return _Credential(nativeAuth, _NativeUser(nativeAuth, identity));
  }

  Future<void> _update(Map<String, Object?> fields) async {
    await session.accountRequest(uid, 'update', {
      'returnSecureToken': true,
      ...fields,
    });
    await reload();
  }

  @override
  Future<void> updatePassword(String newPassword) =>
      _update({'password': newPassword});
  @override
  Future<void> updateEmail(String newEmail) => _update({'email': newEmail});
  @override
  Future<void> updateProfile(Map<String, String?> profile) => _update({
    if (profile['displayName'] != null) 'displayName': profile['displayName'],
    if (profile['photoURL'] != null) 'photoUrl': profile['photoURL'],
    if (profile.containsKey('displayName') && profile['displayName'] == null ||
        profile.containsKey('photoURL') && profile['photoURL'] == null)
      'deleteAttribute': [
        if (profile.containsKey('displayName') &&
            profile['displayName'] == null)
          'DISPLAY_NAME',
        if (profile.containsKey('photoURL') && profile['photoURL'] == null)
          'PHOTO_URL',
      ],
  });
  @override
  Future<void> sendEmailVerification(ActionCodeSettings? settings) async {
    await session.accountRequest(uid, 'sendOobCode', {
      'requestType': 'VERIFY_EMAIL',
      ...NativeFirebaseAuth._actionSettings(settings),
    });
  }

  @override
  Future<void> verifyBeforeUpdateEmail(
    String newEmail, [
    ActionCodeSettings? settings,
  ]) async {
    await session.accountRequest(uid, 'sendOobCode', {
      'requestType': 'VERIFY_AND_CHANGE_EMAIL',
      'newEmail': newEmail,
      ...NativeFirebaseAuth._actionSettings(settings),
    });
  }

  @override
  Future<void> delete() async {
    await session.accountRequest(uid, 'delete', {});
    await session.signOut();
  }
}

/// RonikCloud's second factor uses its existing callable services and rules.
/// Firebase-managed MFA is explicitly unsupported until a resolver is added;
/// never report an enrolled Firebase factor as absent or passed.
class _AppMultiFactor extends MultiFactorPlatform {
  _AppMultiFactor(super.auth);
  FirebaseAuthException get _unsupported => FirebaseAuthException(
    code: 'operation-not-allowed',
    message: 'Firebase-managed MFA is not available in this native adapter.',
  );
  @override
  Future<List<MultiFactorInfo>> getEnrolledFactors() async =>
      throw _unsupported;
  @override
  Future<MultiFactorSession> getSession() async => throw _unsupported;
  @override
  Future<void> enroll(
    MultiFactorAssertionPlatform assertion, {
    String? displayName,
  }) async => throw _unsupported;
  @override
  Future<void> unenroll({
    String? factorUid,
    MultiFactorInfo? multiFactorInfo,
  }) async => throw _unsupported;
}
