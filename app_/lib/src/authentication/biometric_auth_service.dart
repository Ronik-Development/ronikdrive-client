import 'package:shared_preferences/shared_preferences.dart';

class BiometricSignInPreferenceStore {
  BiometricSignInPreferenceStore._();

  static final BiometricSignInPreferenceStore instance =
      BiometricSignInPreferenceStore._();

  static const String _baseKey = 'ronikdrive_biometric_sign_in_enabled_v1';

  Future<bool> isEnabledForEmail(String? email) async {
    final scopedKey = _scopedKey(email);
    if (scopedKey == null) {
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(scopedKey) ?? false;
  }

  Future<void> setEnabledForEmail(String? email, bool enabled) async {
    final scopedKey = _scopedKey(email);
    if (scopedKey == null) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    if (enabled) {
      await prefs.setBool(scopedKey, true);
    } else {
      await prefs.remove(scopedKey);
    }
  }

  String? _scopedKey(String? email) {
    final normalizedEmail = _normalizeEmail(email);
    if (normalizedEmail == null) {
      return null;
    }
    final safeEmail = normalizedEmail.replaceAll(RegExp(r'[^a-z0-9]'), '_');
    return '${_baseKey}_$safeEmail';
  }

  String? _normalizeEmail(String? email) {
    if (email == null) {
      return null;
    }
    final trimmed = email.trim().toLowerCase();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
