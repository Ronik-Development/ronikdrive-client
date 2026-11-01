import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../privacy/local_private_cache.dart';
import 'business_recipient_trust.dart';

/// Share the serialized high-water mark between workspace and administration.
class BusinessRecipientTrustRuntime {
  static final Map<String, Future<BusinessRecipientTrust>> _stores = {};
  static Future<BusinessRecipientTrust> forApp(FirebaseApp app) {
    final auth = FirebaseAuth.instanceFor(app: app);
    final uid = auth.currentUser?.uid;
    if (uid == null) {
      throw const RecipientTrustException(
        'Sign in before verifying company keys.',
      );
    }
    final scope = app.options.projectId;
    final id = '$scope/$uid';
    // Forget inactive account instances; encrypted durable trust remains scoped.
    _stores.removeWhere((key, _) => key != id);
    return _stores.putIfAbsent(id, () async {
      final prefs = await SharedPreferences.getInstance();
      final marker =
          'business_trust_enrollment_v1_${crypto.sha256.convert(utf8.encode(id))}';
      return BusinessRecipientTrust(
        LocalPrivateCachePreferences(
          preferences: prefs,
          uid: uid,
          scope: scope,
        ),
        accountCurrent: () => auth.currentUser?.uid == uid,
        readEnrollmentMarker: () async => prefs.getString(marker),
        writeEnrollmentMarker: (hash) async {
          if (auth.currentUser?.uid != uid ||
              !await prefs.setString(marker, hash)) {
            throw const RecipientTrustException(
              'Company trust could not be saved for this account.',
            );
          }
        },
      );
    });
  }
}
