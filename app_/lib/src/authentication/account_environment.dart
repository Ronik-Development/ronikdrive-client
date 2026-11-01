import 'package:shared_preferences/shared_preferences.dart';

enum AccountEnvironment { personal, business }

extension AccountEnvironmentValue on AccountEnvironment {
  String get storageValue => name;

  String get label => switch (this) {
    AccountEnvironment.personal => 'Personal',
    AccountEnvironment.business => 'Business',
  };
}

class AccountEnvironmentStore {
  AccountEnvironmentStore._();

  static final AccountEnvironmentStore instance = AccountEnvironmentStore._();

  static const String _environmentKey = 'account_environment_v1';
  static const String _uidKey = 'account_environment_uid_v1';

  AccountEnvironment? _pendingEnvironment;

  void prepareSignIn(AccountEnvironment environment) {
    _pendingEnvironment = environment;
  }

  void cancelPreparedSignIn() {
    _pendingEnvironment = null;
  }

  Future<void> saveForUser({
    required String uid,
    required AccountEnvironment environment,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await Future.wait(<Future<bool>>[
      preferences.setString(_uidKey, uid),
      preferences.setString(_environmentKey, environment.storageValue),
    ]);
    _pendingEnvironment = null;
  }

  Future<AccountEnvironment> resolveForUser(String uid) async {
    final pending = _pendingEnvironment;
    if (pending != null) {
      return pending;
    }

    final preferences = await SharedPreferences.getInstance();
    if (preferences.getString(_uidKey) != uid) {
      return AccountEnvironment.personal;
    }
    return switch (preferences.getString(_environmentKey)) {
      'business' => AccountEnvironment.business,
      _ => AccountEnvironment.personal,
    };
  }

  Future<void> clear() async {
    _pendingEnvironment = null;
    final preferences = await SharedPreferences.getInstance();
    await Future.wait(<Future<bool>>[
      preferences.remove(_uidKey),
      preferences.remove(_environmentKey),
    ]);
  }
}
