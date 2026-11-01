import 'package:cloud_storage/src/authentication/account_environment.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await AccountEnvironmentStore.instance.clear();
  });

  test('defaults unknown users to the personal environment', () async {
    expect(
      await AccountEnvironmentStore.instance.resolveForUser('user-1'),
      AccountEnvironment.personal,
    );
  });

  test('persists business environment only for the signed-in user', () async {
    await AccountEnvironmentStore.instance.saveForUser(
      uid: 'company-admin',
      environment: AccountEnvironment.business,
    );

    expect(
      await AccountEnvironmentStore.instance.resolveForUser('company-admin'),
      AccountEnvironment.business,
    );
    expect(
      await AccountEnvironmentStore.instance.resolveForUser('other-user'),
      AccountEnvironment.personal,
    );
  });

  test(
    'prepared environment is available during the auth transition',
    () async {
      AccountEnvironmentStore.instance.prepareSignIn(
        AccountEnvironment.business,
      );

      expect(
        await AccountEnvironmentStore.instance.resolveForUser('pending-user'),
        AccountEnvironment.business,
      );

      AccountEnvironmentStore.instance.cancelPreparedSignIn();
    },
  );
}
