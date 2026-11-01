import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'native_auth_transport.dart';

abstract interface class NativeSessionStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Linux uses libsecret through flutter_secure_storage. There is no file or
/// preferences fallback when the user's keyring is locked or unavailable.
class KeyringNativeSessionStore implements NativeSessionStore {
  const KeyringNativeSessionStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;
  final FlutterSecureStorage _storage;
  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class NativeAuthIdentity {
  NativeAuthIdentity(Map<String, dynamic> account)
    : uid = account['localId'] as String,
      account = Map.unmodifiable(account);
  final String uid;
  final Map<String, dynamic> account;
}

class _Session {
  _Session(this.identity, this.idToken, this.refreshToken, this.expiresAt);
  final NativeAuthIdentity identity;
  final String idToken;
  final String refreshToken;
  final DateTime expiresAt;
}

/// Native user sessions shared by the Linux Auth, Firestore and Functions
/// adapters. Decoded JWT fields are consistency checks, never authorization.
class NativeAuthSession {
  NativeAuthSession({
    required this.projectId,
    this.projectNumber,
    required String appId,
    required String appName,
    required this.transport,
    required NativeSessionStore store,
    DateTime Function()? now,
    this.automaticallyRefresh = true,
  }) : _store = store,
       _now = now ?? DateTime.now,
       storageKey =
           'ronikcloud.native-auth.${sha256.convert(utf8.encode(jsonEncode([projectId, appId, appName, transport.sessionAuthority])))}';

  final String projectId;
  // Secure Token returns the numeric project number as `project_id`; JWT
  // audience/issuer use the textual project ID. Keep both namespaces distinct.
  final String? projectNumber;
  final NativeAuthTransport transport;
  final String storageKey;
  final NativeSessionStore _store;
  final DateTime Function() _now;
  final bool automaticallyRefresh;
  final _changes = StreamController<NativeAuthIdentity?>.broadcast();
  Stream<NativeAuthIdentity?> get changes => _changes.stream;
  NativeAuthIdentity? get currentIdentity => _session?.identity;
  _Session? _session;
  int _generation = 0;
  Future<void> _storeTail = Future.value();
  Future<String>? _refreshing;
  Timer? _timer;
  bool _disposed = false;

  Future<T> _storage<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _storeTail = _storeTail.then((_) async {
      try {
        result.complete(await operation());
      } catch (_) {
        result.completeError(_error('keychain-error'));
      }
    });
    return result.future;
  }

  Future<void> _persist(_Session? session) => session == null
      ? _store.delete(storageKey)
      : _store.write(
          storageKey,
          jsonEncode({
            'schema': 1,
            'uid': session.identity.uid,
            'refreshToken': session.refreshToken,
          }),
        );

  void _checkGeneration(int generation) {
    if (_disposed || generation != _generation) {
      throw _error('user-token-expired');
    }
  }

  Future<void> _commit(_Session session, int generation) async {
    var cancelled = false;
    await _storage(() async {
      if (_disposed || generation != _generation) {
        cancelled = true;
        return;
      }
      await _persist(session);
      if (_disposed || generation != _generation) {
        // A sign-out/account change can occur while the keyring write awaits.
        // Restore the actual current session before the next queued mutation.
        await _persist(_session);
        cancelled = true;
        return;
      }
      _session = session;
    });
    if (cancelled) throw _error('user-token-expired');
    _checkGeneration(generation);
    _changes.add(session.identity);
    _scheduleRefresh();
  }

  Future<NativeAuthIdentity?> restore() async {
    final generation = _generation;
    final raw = await _storage(() => _store.read(storageKey));
    _checkGeneration(generation);
    if (raw == null) return null;
    String uid;
    String refresh;
    try {
      if (raw.length > 100000) throw const FormatException();
      final value = jsonDecode(raw);
      if (value is! Map || value['schema'] != 1 || value.length != 3) {
        throw const FormatException();
      }
      uid = value['uid'] as String;
      refresh = value['refreshToken'] as String;
      _validateUid(uid);
      _validateToken(refresh);
    } catch (_) {
      await _storage(() => _store.delete(storageKey));
      throw _error('invalid-user-token');
    }
    try {
      final response = await transport.refresh(refresh);
      final session = await _sessionFromGrant(response, expectedUid: uid);
      await _commit(session, generation);
      return session.identity;
    } on FirebaseAuthException catch (error) {
      if (_isRevoked(error) && generation == _generation) await signOut();
      rethrow;
    }
  }

  Future<NativeAuthIdentity> signIn(String email, String password) =>
      _authenticate('signInWithPassword', {
        'email': email,
        'password': password,
        'returnSecureToken': true,
      });

  Future<NativeAuthIdentity> createAccount(String email, String password) =>
      _authenticate('signUp', {
        'email': email,
        'password': password,
        'returnSecureToken': true,
      });

  Future<NativeAuthIdentity> signInWithCustomToken(String token) =>
      _authenticate('signInWithCustomToken', {
        'token': token,
        'returnSecureToken': true,
      });

  Future<NativeAuthIdentity> reauthenticate(
    String uid,
    String email,
    String password,
  ) async {
    final generation = _generation;
    await idToken(forUid: uid);
    _checkGeneration(generation);
    final response = await transport.account('signInWithPassword', {
      'email': email,
      'password': password,
      'returnSecureToken': true,
    });
    _checkGeneration(generation);
    if (response['localId'] != null && response['localId'] != uid) {
      throw _error('user-mismatch');
    }
    final session = await _sessionFromGrant(response, expectedUid: uid);
    await _commit(session, generation);
    return session.identity;
  }

  Future<NativeAuthIdentity> _authenticate(
    String operation,
    Map<String, Object?> body,
  ) async {
    if (_disposed) throw StateError('Authentication session is closed.');
    final generation = ++_generation;
    _refreshing = null;
    final response = await transport.account(operation, body);
    _checkGeneration(generation);
    final session = await _sessionFromGrant(response);
    await _commit(session, generation);
    return session.identity;
  }

  Future<_Session> _sessionFromGrant(
    Map<String, dynamic> grant, {
    String? expectedUid,
  }) async {
    final idToken = grant['idToken'] ?? grant['id_token'];
    final refresh = grant['refreshToken'] ?? grant['refresh_token'];
    _validateToken(idToken);
    _validateToken(refresh);
    final Map<String, dynamic> claims;
    try {
      final segments = (idToken as String).split('.');
      if (segments.length != 3) throw const FormatException();
      claims = Map<String, dynamic>.from(
        jsonDecode(
              utf8.decode(base64Url.decode(base64Url.normalize(segments[1]))),
            )
            as Map,
      );
    } catch (_) {
      throw _error('invalid-user-token');
    }
    final uid = claims['sub'];
    _validateUid(uid);
    final grantProject = grant['project_id'];
    if (claims['aud'] != projectId ||
        claims['iss'] != 'https://securetoken.google.com/$projectId' ||
        (expectedUid != null && uid != expectedUid) ||
        (grant['localId'] != null && grant['localId'] != uid) ||
        (grant['user_id'] != null && grant['user_id'] != uid) ||
        (grantProject != null &&
            (grantProject is! String ||
                !RegExp(r'^[0-9]{1,30}$').hasMatch(grantProject) ||
                (projectNumber != null && grantProject != projectNumber)))) {
      throw _error('invalid-user-token');
    }
    final expiration = claims['exp'];
    if (expiration is! int) throw _error('invalid-user-token');
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(
      expiration * 1000,
      isUtc: true,
    );
    if (!expiresAt.isAfter(_now())) throw _error('invalid-user-token');
    final lookup = await transport.account('lookup', {'idToken': idToken});
    final users = lookup['users'];
    if (users is! List || users.length != 1 || users.single is! Map) {
      throw _error('invalid-user-token');
    }
    final account = Map<String, dynamic>.from(users.single as Map);
    if (account['localId'] != uid || account['disabled'] == true) {
      throw _error('invalid-user-token');
    }
    return _Session(
      NativeAuthIdentity(account),
      idToken,
      refresh as String,
      expiresAt,
    );
  }

  Future<String> idToken({String? forUid, bool forceRefresh = false}) async {
    final session = _session;
    if (_disposed ||
        session == null ||
        (forUid != null && session.identity.uid != forUid)) {
      throw _error('user-token-expired');
    }
    if (!forceRefresh &&
        session.expiresAt.isAfter(_now().add(const Duration(minutes: 1)))) {
      return session.idToken;
    }
    final pending = _refreshing;
    if (pending != null) return pending;
    final generation = _generation;
    final attempt = _refresh(session, generation);
    _refreshing = attempt;
    try {
      return await attempt;
    } finally {
      if (identical(_refreshing, attempt)) _refreshing = null;
    }
  }

  Future<String> _refresh(_Session old, int generation) async {
    try {
      final grant = await transport.refresh(old.refreshToken);
      _checkGeneration(generation);
      final session = await _sessionFromGrant(
        grant,
        expectedUid: old.identity.uid,
      );
      await _commit(session, generation);
      return session.idToken;
    } on FirebaseAuthException catch (error) {
      if (_isRevoked(error) && generation == _generation) await signOut();
      rethrow;
    }
  }

  Future<void> reload(String uid) async {
    final generation = _generation;
    final token = await idToken(forUid: uid);
    final result = await transport.account('lookup', {'idToken': token});
    _checkGeneration(generation);
    final users = result['users'];
    if (users is! List ||
        users.length != 1 ||
        users.single is! Map ||
        users.single['localId'] != uid) {
      throw _error('invalid-user-token');
    }
    final previous = _session!;
    await _commit(
      _Session(
        NativeAuthIdentity(Map<String, dynamic>.from(users.single as Map)),
        previous.idToken,
        previous.refreshToken,
        previous.expiresAt,
      ),
      generation,
    );
  }

  Future<Map<String, dynamic>> accountRequest(
    String uid,
    String operation,
    Map<String, Object?> body,
  ) async {
    final generation = _generation;
    final token = await idToken(forUid: uid);
    _checkGeneration(generation);
    final result = await transport.account(operation, {
      ...body,
      'idToken': token,
    });
    _checkGeneration(generation);
    if (result['idToken'] != null) {
      final session = await _sessionFromGrant(result, expectedUid: uid);
      await _commit(session, generation);
    }
    return result;
  }

  Future<void> signOut() async {
    ++_generation;
    _timer?.cancel();
    _refreshing = null;
    _session = null;
    if (!_disposed) _changes.add(null);
    await _storage(() => _store.delete(storageKey));
  }

  void _scheduleRefresh({Duration? retry}) {
    _timer?.cancel();
    if (!automaticallyRefresh || _disposed || _session == null) return;
    final until =
        retry ??
        _session!.expiresAt.difference(_now()) - const Duration(minutes: 1);
    _timer = Timer(
      until < const Duration(seconds: 30) ? const Duration(seconds: 30) : until,
      () async {
        try {
          await idToken(forceRefresh: true);
        } catch (_) {
          _scheduleRefresh(retry: const Duration(seconds: 30));
        }
      },
    );
  }

  static void _validateToken(Object? token) {
    if (token is! String ||
        token.isEmpty ||
        token.length > 65536 ||
        token.contains(RegExp(r'[\r\n]'))) {
      throw _error('invalid-user-token');
    }
  }

  static void _validateUid(Object? uid) {
    if (uid is! String ||
        uid.isEmpty ||
        uid.length > 128 ||
        uid.contains(RegExp(r'[\x00-\x1f]'))) {
      throw _error('invalid-user-token');
    }
  }

  static bool _isRevoked(FirebaseAuthException error) => const {
    'invalid-user-token',
    'user-token-expired',
    'user-disabled',
  }.contains(error.code);
  static FirebaseAuthException _error(String code) => FirebaseAuthException(
    code: code,
    message: 'The native account session could not be used.',
  );

  Future<void> dispose() async {
    _disposed = true;
    ++_generation;
    _timer?.cancel();
    _session = null;
    transport.close();
    await _storeTail;
    await _changes.close();
  }
}
