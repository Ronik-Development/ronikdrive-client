import 'package:cloud_storage/src/authentication/biometric_auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('BiometricSignInPreferenceStore', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('defaults to disabled', () async {
      final store = BiometricSignInPreferenceStore.instance;

      expect(await store.isEnabledForEmail('person@example.com'), isFalse);
    });

    test('stores preference per email and can disable it again', () async {
      final store = BiometricSignInPreferenceStore.instance;

      await store.setEnabledForEmail('person@example.com', true);
      await store.setEnabledForEmail('other@example.com', false);

      expect(await store.isEnabledForEmail('person@example.com'), isTrue);
      expect(await store.isEnabledForEmail('other@example.com'), isFalse);

      await store.setEnabledForEmail('person@example.com', false);

      expect(await store.isEnabledForEmail('person@example.com'), isFalse);
    });
  });
}
