import 'package:firebase_auth/firebase_auth.dart';

/// A storage service keeps its original account even when Auth changes while a
/// token refresh is pending. Never fall back to a signed-out User object.
Future<String?> Function() accountBoundTokenProvider({
  required FirebaseAuth auth,
  required String uid,
}) => () async {
  final user = auth.currentUser;
  if (user == null || user.uid != uid) return null;
  final token = await user.getIdToken();
  return auth.currentUser?.uid == uid ? token : null;
};
