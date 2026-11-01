import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../privacy/local_offline_vault.dart';
import '../privacy/local_private_cache.dart';
import '../shared/platform_io.dart';
import '../shared/user_facing_cloud_error.dart';
import '../storage/drive_repository.dart';
import '../shared/release_runtime_config.dart';
import '../storage/wasabi_storage_service.dart';
import 'login_password_vault.dart';

typedef AccountDeletionCallable = Future<void> Function();

class AccountDeletionException implements Exception {
  const AccountDeletionException(this.message);

  final String message;

  @override
  String toString() => 'AccountDeletionException: $message';
}

class AccountDeletionService {
  AccountDeletionService({
    required FirebaseAuth auth,
    DriveRepository? driveRepository,
    WasabiStorageService? wasabiService,
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    http.Client? httpClient,
    AccountDeletionCallable? callable,
  }) : _auth = auth,
       _functions = functions,
       _httpClient = httpClient ?? http.Client(),
       _callable = callable;

  final FirebaseAuth _auth;
  final FirebaseFunctions? _functions;
  final http.Client _httpClient;
  final AccountDeletionCallable? _callable;

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[RonikCloud][account-deletion] $message');
    }
  }

  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw AccountDeletionException(
        userFacingCloudErrorMessage(
          operation: UserFacingCloudOperation.accountDeletion,
          code: 'unauthenticated',
        ),
      );
    }

    try {
      try {
        await _callDeleteAccount();
        await _clearLocalPrivateCache(user.uid);
        LoginPasswordVault.instance.clear();
        return;
      } on FirebaseFunctionsException catch (error) {
        if ({
          'failed-precondition',
          'permission-denied',
          'unauthenticated',
          'invalid-argument',
        }.contains(error.code)) {
          throw AccountDeletionException(
            userFacingCloudErrorMessage(
              operation: UserFacingCloudOperation.accountDeletion,
              code: error.code,
            ),
          );
        }
        _log('Callable request failed; trying the authenticated HTTPS path.');
      } on AccountDeletionException {
        rethrow;
      } catch (_) {
        _log('Callable request was unavailable; trying authenticated HTTPS.');
      }

      try {
        await _deleteAccountViaRest(user);
        await _clearLocalPrivateCache(user.uid);
        LoginPasswordVault.instance.clear();
      } on AccountDeletionException {
        rethrow;
      } catch (_) {
        _log('Authenticated HTTPS deletion request could not be completed.');
        throw AccountDeletionException(
          userFacingCloudErrorMessage(
            operation: UserFacingCloudOperation.accountDeletion,
          ),
        );
      }
    } on AccountDeletionException {
      rethrow;
    } on FirebaseFunctionsException catch (error) {
      throw AccountDeletionException(
        userFacingCloudErrorMessage(
          operation: UserFacingCloudOperation.accountDeletion,
          code: error.code,
        ),
      );
    } on PlatformException {
      _log('The platform connection for account deletion was unavailable.');
      throw AccountDeletionException(
        userFacingCloudErrorMessage(
          operation: UserFacingCloudOperation.accountDeletion,
          code: 'unavailable',
        ),
      );
    } catch (_) {
      _log('Account deletion stopped at a protected failure boundary.');
      throw AccountDeletionException(
        userFacingCloudErrorMessage(
          operation: UserFacingCloudOperation.accountDeletion,
        ),
      );
    }
  }

  Future<void> _callDeleteAccount() async {
    final injected = _callable;
    if (injected != null) {
      await injected();
      return;
    }
    final functions =
        _functions ??
        FirebaseFunctions.instanceFor(app: _auth.app, region: 'europe-west1');
    final callable = functions.httpsCallable(
      'deleteUserAccount',
      options: HttpsCallableOptions(timeout: const Duration(minutes: 9)),
    );
    await callable.call();
  }

  Future<void> _deleteAccountViaRest(User user) async {
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw AccountDeletionException(
        userFacingCloudErrorMessage(
          operation: UserFacingCloudOperation.accountDeletion,
          code: 'unauthenticated',
        ),
      );
    }

    final configuredProjectId = _auth.app.options.projectId.trim();
    final projectId = configuredProjectId.isEmpty ? null : configuredProjectId;

    final endpoints = <Uri>{
      ReleaseRuntimeConfig.resolveCallableRestUri(
        projectId: projectId,
        functionName: 'deleteUserAccount',
      ),
      // Fallback direct Cloud Run callable URL.
      ReleaseRuntimeConfig.resolveDeleteAccountRestUri(),
    };

    int? lastStatusCode;
    for (final uri in endpoints) {
      try {
        final response = await _httpClient.post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          // Callable functions expect a `data` wrapper.
          body: jsonEncode({'data': {}}),
        );

        if (response.statusCode >= 200 && response.statusCode < 300) {
          return;
        }

        lastStatusCode = response.statusCode;
      } catch (_) {
        lastStatusCode = null;
      }
    }

    throw AccountDeletionException(
      userFacingCloudErrorMessage(
        operation: UserFacingCloudOperation.accountDeletion,
        httpStatus: lastStatusCode,
        code: lastStatusCode == null ? 'unavailable' : null,
      ),
    );
  }

  Future<void> _clearLocalPrivateCache(String uid) async {
    final scope = _localPrivateCacheScope();
    try {
      final preferences = await SharedPreferences.getInstance();
      final privateCache = LocalPrivateCachePreferences(
        preferences: preferences,
        uid: uid,
        scope: scope,
      );
      final offlineFiles = await privateCache.read(
        baseKey: LocalPrivateCacheCodec.offlineFilesPreferenceKey,
        namespace: LocalPrivateCacheCodec.offlineFilesNamespace,
      );
      final payload = offlineFiles.value;
      if (payload != null) {
        try {
          final entries = jsonDecode(payload) as List<dynamic>;
          for (final entry in entries) {
            final map = Map<String, dynamic>.from(entry as Map);
            final localPath = (map['localPath'] as String?)?.trim();
            if (localPath == null || localPath.isEmpty) {
              continue;
            }
            final file = File(localPath);
            if (await file.exists()) {
              await file.delete();
            }
          }
        } catch (_) {
          // Cryptographic key erasure below still makes any remaining vault
          // objects inaccessible when an old mapping cannot be parsed.
        }
      }
      await privateCache.purge(
        LocalPrivateCacheCodec.protectedPreferenceNamespaces.keys,
        forgetKey: true,
      );
    } catch (_) {
      // Remote deletion already succeeded. Do not make the deleted account
      // appear active again because a best-effort device cleanup failed.
      if (kDebugMode) {
        debugPrint('Private cache cleanup after account deletion failed.');
      }
    } finally {
      try {
        await LocalOfflineVault(uid: uid, scope: scope).forgetKey();
      } catch (_) {
        if (kDebugMode) {
          debugPrint('Offline vault key cleanup after deletion failed.');
        }
      }
    }
  }

  String _localPrivateCacheScope() {
    try {
      final projectId = _auth.app.options.projectId.trim();
      if (projectId.isNotEmpty) {
        return projectId;
      }
    } catch (_) {
      // Firebase test doubles may not expose production app options.
    }
    try {
      final appName = _auth.app.name.trim();
      if (appName.isNotEmpty) {
        return appName;
      }
    } catch (_) {
      // Fall through to a deterministic local-only scope.
    }
    return 'local-firebase-app';
  }
}
