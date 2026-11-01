import 'package:cloud_storage/src/authentication/account_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('username-only identities use a stable reserved auth email', () {
    expect(normalizeAccountUsername('  New_User-7 '), 'new_user-7');
    expect(
      usernameOnlyAuthEmail('New_User-7'),
      'new_user-7@users.ronikcloud.invalid',
    );
    expect(
      authEmailForLoginIdentifier('New_User-7'),
      'new_user-7@users.ronikcloud.invalid',
    );
    expect(
      isUsernameOnlyAuthEmail('new_user-7@users.ronikcloud.invalid'),
      true,
    );
  });

  test('real email login identifiers remain email addresses', () {
    expect(
      authEmailForLoginIdentifier(' Person@Example.com '),
      'person@example.com',
    );
  });

  test('username validation rejects ambiguous identifiers', () {
    expect(validateAccountUsername('ab'), isNotNull);
    expect(validateAccountUsername('-bad'), isNotNull);
    expect(validateAccountUsername('bad name'), isNotNull);
    expect(validateAccountUsername('good_name-7'), isNull);
  });
}
