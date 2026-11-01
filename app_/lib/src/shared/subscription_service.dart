import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart';

import 'release_runtime_config.dart';

enum SubscriptionServiceFailure {
  unauthenticated,
  unavailable,
  invalidResponse,
  launchFailed,
}

class SubscriptionServiceException implements Exception {
  const SubscriptionServiceException(this.failure);

  final SubscriptionServiceFailure failure;

  @override
  String toString() => 'SubscriptionServiceException(${failure.name})';
}

class SubscriptionService {
  // Ensure the region matches your Cloud Functions region
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'europe-west1',
  );

  Future<SubscriptionChangeResult> changeSubscriptionTier({
    required String tier,
    String? interval,
  }) async {
    final data = <String, Object?>{'tier': tier};
    final normalizedInterval = interval?.trim();
    if (normalizedInterval != null && normalizedInterval.isNotEmpty) {
      data['interval'] = normalizedInterval;
    }

    final result = await _callFunctionWithRestFallback(
      functionName: 'changeSubscriptionTier',
      restUri: ReleaseRuntimeConfig.resolveChangeSubscriptionTierRestUri(),
      data: data,
    );

    return SubscriptionChangeResult(
      unchanged: result['unchanged'] == true,
      tier: _stringValue(result['tier']),
      interval: _stringValue(result['interval']),
      status: _stringValue(result['status']),
    );
  }

  Future<SubscriptionCancellationResult> cancelSubscription() async {
    final result = await _callFunctionWithRestFallback(
      functionName: 'cancelSubscription',
      restUri: ReleaseRuntimeConfig.resolveCancelSubscriptionRestUri(),
      data: const <String, Object?>{},
    );

    return SubscriptionCancellationResult(
      status: _stringValue(result['status']),
      currentPeriodEnd: _parseDateTime(result['currentPeriodEnd']),
      cancelAt: _parseDateTime(result['cancelAt']),
      cancelAtPeriodEnd: result['cancelAtPeriodEnd'] == true,
    );
  }

  Future<void> manageSubscription() async {
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
        await _manageSubscriptionViaRest();
        return;
      }

      // Call the Cloud Function to get the portal session URL
      final result = await _functions
          .httpsCallable('createPortalSession')
          .call();

      final data = result.data as Map<Object?, Object?>?;
      final urlString = data?['url'] as String?;

      _launchPortalUrl(urlString);
    } catch (_) {
      if (kIsWeb) {
        if (kDebugMode) {
          debugPrint('Callable subscription portal request failed on web.');
        }
        throw const SubscriptionServiceException(
          SubscriptionServiceFailure.unavailable,
        );
      }
      if (kDebugMode) {
        debugPrint('Subscription portal plugin failed; trying REST fallback.');
      }
      // Try REST fallback if plugin fails on other platforms too
      try {
        await _manageSubscriptionViaRest();
      } on SubscriptionServiceException {
        rethrow;
      } catch (_) {
        if (kDebugMode) {
          debugPrint('Subscription portal REST fallback failed.');
        }
        throw const SubscriptionServiceException(
          SubscriptionServiceFailure.unavailable,
        );
      }
    }
  }

  Future<void> _manageSubscriptionViaRest() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const SubscriptionServiceException(
        SubscriptionServiceFailure.unauthenticated,
      );
    }

    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw const SubscriptionServiceException(
        SubscriptionServiceFailure.unauthenticated,
      );
    }

    final uri = ReleaseRuntimeConfig.resolvePortalSessionRestUri();
    final redirectUri = ReleaseRuntimeConfig.resolveRedirectUri(
      projectId: FirebaseAuth.instance.app.options.projectId,
    );

    late http.Response response;
    try {
      response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'data': {'returnUrl': redirectUri.toString()},
        }),
      );
    } catch (_) {
      throw const SubscriptionServiceException(
        SubscriptionServiceFailure.unavailable,
      );
    }

    if (response.statusCode != 200) {
      throw const SubscriptionServiceException(
        SubscriptionServiceFailure.unavailable,
      );
    }

    dynamic body;
    try {
      body = jsonDecode(response.body);
    } on FormatException {
      throw const SubscriptionServiceException(
        SubscriptionServiceFailure.invalidResponse,
      );
    }
    final result = body is Map ? body['result'] : null;
    final rawUrl = result is Map ? result['url'] : null;
    final urlString = rawUrl is String ? rawUrl : null;

    _launchPortalUrl(urlString);
  }

  Future<Map<String, Object?>> _callFunctionWithRestFallback({
    required String functionName,
    required Uri restUri,
    required Map<String, Object?> data,
  }) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      return _callFunctionViaRest(restUri: restUri, data: data);
    }

    try {
      final result = await _functions.httpsCallable(functionName).call(data);
      return _normalizeResultMap(result.data);
    } catch (_) {
      if (kIsWeb) {
        if (kDebugMode) {
          debugPrint('Subscription callable failed on web.');
        }
        throw const SubscriptionServiceException(
          SubscriptionServiceFailure.unavailable,
        );
      }
      if (kDebugMode) {
        debugPrint('Subscription callable failed; trying REST fallback.');
      }
      try {
        return await _callFunctionViaRest(restUri: restUri, data: data);
      } on SubscriptionServiceException {
        rethrow;
      } catch (_) {
        throw const SubscriptionServiceException(
          SubscriptionServiceFailure.unavailable,
        );
      }
    }
  }

  Future<Map<String, Object?>> _callFunctionViaRest({
    required Uri restUri,
    required Map<String, Object?> data,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const SubscriptionServiceException(
        SubscriptionServiceFailure.unauthenticated,
      );
    }

    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw const SubscriptionServiceException(
        SubscriptionServiceFailure.unauthenticated,
      );
    }

    late http.Response response;
    try {
      response = await http.post(
        restUri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'data': data}),
      );
    } catch (_) {
      throw const SubscriptionServiceException(
        SubscriptionServiceFailure.unavailable,
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const SubscriptionServiceException(
        SubscriptionServiceFailure.unavailable,
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const SubscriptionServiceException(
        SubscriptionServiceFailure.invalidResponse,
      );
    }
    if (decoded is Map) {
      return _normalizeResultMap(decoded['result']);
    }
    return const <String, Object?>{};
  }

  Future<void> _launchPortalUrl(String? urlString) async {
    if (urlString != null && urlString.isNotEmpty) {
      try {
        final uri = Uri.parse(urlString);
        // Launch the URL in an external browser.
        if (await canLaunchUrl(uri) &&
            await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          return;
        }
      } catch (_) {
        // Fall through to the closed failure below.
      }
    }
    throw const SubscriptionServiceException(
      SubscriptionServiceFailure.launchFailed,
    );
  }

  Map<String, Object?> _normalizeResultMap(Object? value) {
    if (value is Map) {
      return Map<String, Object?>.fromEntries(
        value.entries.map(
          (entry) => MapEntry(entry.key.toString(), entry.value),
        ),
      );
    }
    return const <String, Object?>{};
  }

  String? _stringValue(Object? value) {
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    return value?.toString();
  }

  DateTime? _parseDateTime(Object? value) {
    final text = _stringValue(value);
    if (text == null) {
      return null;
    }
    return DateTime.tryParse(text);
  }
}

class SubscriptionChangeResult {
  const SubscriptionChangeResult({
    required this.unchanged,
    this.tier,
    this.interval,
    this.status,
  });

  final bool unchanged;
  final String? tier;
  final String? interval;
  final String? status;
}

class SubscriptionCancellationResult {
  const SubscriptionCancellationResult({
    required this.cancelAtPeriodEnd,
    this.status,
    this.currentPeriodEnd,
    this.cancelAt,
  });

  final bool cancelAtPeriodEnd;
  final String? status;
  final DateTime? currentPeriodEnd;
  final DateTime? cancelAt;
}
