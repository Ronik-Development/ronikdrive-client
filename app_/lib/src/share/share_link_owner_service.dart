import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_functions/cloud_functions.dart';

typedef ShareOwnerCallable =
    Future<Map<String, dynamic>> Function(String functionName);

enum ShareOwnerFailureKind {
  sessionExpired,
  temporarilyLimited,
  unavailable,
  invalidResponse,
}

class ShareOwnerException implements Exception {
  const ShareOwnerException(this.kind);

  final ShareOwnerFailureKind kind;

  @override
  String toString() => 'ShareOwnerException(${kind.name})';
}

class ShareEmergencyRevocationResult {
  const ShareEmergencyRevocationResult({
    required this.revokedCount,
    required this.complete,
  });

  factory ShareEmergencyRevocationResult.fromMap(Map<String, dynamic> data) {
    final rawCount = data['revokedCount'];
    if (data['ok'] != true || rawCount is! num || !rawCount.isFinite) {
      throw const ShareOwnerException(ShareOwnerFailureKind.invalidResponse);
    }
    final count = rawCount.toInt();
    if (count < 0 || count > 100000 || data['complete'] is! bool) {
      throw const ShareOwnerException(ShareOwnerFailureKind.invalidResponse);
    }
    return ShareEmergencyRevocationResult(
      revokedCount: count,
      complete: data['complete'] as bool,
    );
  }

  final int revokedCount;
  final bool complete;
}

class ShareLinkOwnerService {
  ShareLinkOwnerService({
    FirebaseFunctions? functions,
    ShareOwnerCallable? callable,
  }) : assert(functions != null || callable != null),
       _functions = functions,
       _callable = callable;

  factory ShareLinkOwnerService.forApp(FirebaseApp app) =>
      ShareLinkOwnerService(
        functions: FirebaseFunctions.instanceFor(
          app: app,
          region: 'europe-west1',
        ),
      );

  final FirebaseFunctions? _functions;
  final ShareOwnerCallable? _callable;

  Future<ShareEmergencyRevocationResult> revokeAll() async {
    try {
      final data = await _call('revokeAllShareLinks');
      return ShareEmergencyRevocationResult.fromMap(data);
    } on ShareOwnerException {
      rethrow;
    } on FirebaseFunctionsException catch (error) {
      throw ShareOwnerException(_failureKindForCode(error.code));
    } catch (_) {
      throw const ShareOwnerException(ShareOwnerFailureKind.unavailable);
    }
  }

  Future<Map<String, dynamic>> _call(String functionName) async {
    final injected = _callable;
    if (injected != null) {
      return injected(functionName);
    }
    final result = await _functions!
        .httpsCallable(functionName)
        .call<dynamic>();
    final data = result.data;
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return data.map((key, value) => MapEntry(key.toString(), value));
    }
    throw const ShareOwnerException(ShareOwnerFailureKind.invalidResponse);
  }

  ShareOwnerFailureKind _failureKindForCode(String rawCode) {
    final code = rawCode.trim().toLowerCase();
    if (code == 'unauthenticated' || code == 'permission-denied') {
      return ShareOwnerFailureKind.sessionExpired;
    }
    if (code == 'resource-exhausted') {
      return ShareOwnerFailureKind.temporarilyLimited;
    }
    return ShareOwnerFailureKind.unavailable;
  }
}
