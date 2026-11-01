import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Resume only an authenticated account that never completed its profile.
/// Existing complete accounts must use sign-in; this never deletes an account.
Future<({UserCredential credential, bool created})> createOrResumeSignup({
  required FirebaseAuth auth,
  required FirebaseFirestore firestore,
  required String email,
  required String password,
}) async {
  try {
    return (
      credential: await auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      ),
      created: true,
    );
  } on FirebaseAuthException catch (error) {
    if (error.code != 'email-already-in-use') rethrow;
    final credential = await auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    final user = credential.user;
    try {
      final profile = user == null
          ? null
          : await firestore.collection('users').doc(user.uid).get();
      if (user == null ||
          (profile!.exists &&
              !isIncompleteRegistrationProfile(profile.data()!))) {
        throw FirebaseAuthException(code: 'email-already-in-use');
      }
      return (credential: credential, created: false);
    } catch (_) {
      await auth.signOut();
      rethrow;
    }
  }
}

bool isIncompleteRegistrationProfile(Map<String, dynamic> data) {
  const fields = {
    'encryptionSalt',
    'encryptionUpdatedAt',
    'profilePrivacyVersion',
    'createdAt',
    'currentPeriodEnd',
    'capacity',
    'subscriptionStatus',
    'appleAppAccountToken',
    'applePurchasePreparedAt',
    'usageBytes',
    'storageWriteSuspended',
    'storageInventory',
    'storageInventoryUpdatedAt',
    'usageBytesUpdatedAt',
    'email',
    'name',
    'displayName',
    'legalVersion',
    'termsAcceptedAt',
    'privacyAcknowledgedAt',
    'acceptableUseAcceptedAt',
    'cancellationRefundAcknowledgedAt',
    'dataRetentionAcknowledgedAt',
    'subprocessorsAcknowledgedAt',
    'legalAcceptanceSource',
    'productUpdatesOptIn',
    'productUpdatesSource',
    'productUpdatesOptInAt',
  };
  return data.keys.every(fields.contains) &&
      [null, '', 'pending'].contains(data['subscriptionStatus']) &&
      [null, '', 'pending'].contains(data['capacity']) &&
      [null, '', 'pending'].contains(data['currentPeriodEnd']);
}
