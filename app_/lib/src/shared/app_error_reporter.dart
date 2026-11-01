import 'dart:async';
import 'dart:collection';
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../privacy/privacy_redaction.dart';

const String clientDiagnosticPrivacyVersion = 'client-diagnostic-codes-only-v3';

class AppErrorReporter {
  AppErrorReporter._() : _authForApp = null;

  @visibleForTesting
  AppErrorReporter.forTesting({FirebaseAuth Function(FirebaseApp)? authForApp})
    : _authForApp = authForApp;

  static final AppErrorReporter instance = AppErrorReporter._();

  static const int _maxPendingReports = 20;
  static const String diagnosticsPreferenceKey =
      'privacy_diagnostics_sharing_enabled';
  final Queue<_PendingErrorReport> _pendingReports =
      ListQueue<_PendingErrorReport>();
  final ValueNotifier<bool> diagnosticsEnabled = ValueNotifier<bool>(false);

  StreamSubscription<User?>? _authSubscription;
  Future<FirebaseApp>? _firebaseAppFuture;
  final FirebaseAuth Function(FirebaseApp)? _authForApp;
  int _firebaseConfigurationGeneration = 0;
  SharedPreferences? _preferences;
  FlutterExceptionHandler? _previousFlutterErrorHandler;
  ErrorCallback? _previousPlatformErrorHandler;
  bool _handlersInstalled = false;
  bool _flushInProgress = false;
  int _consecutiveFlushFailures = 0;
  DateTime? _nextFlushAttemptAt;

  Future<void> initializePrivacyPreferences({
    SharedPreferences? preferences,
  }) async {
    try {
      final resolvedPreferences =
          preferences ?? _preferences ?? await SharedPreferences.getInstance();
      _preferences = resolvedPreferences;
      diagnosticsEnabled.value =
          resolvedPreferences.getBool(diagnosticsPreferenceKey) ?? false;
      if (diagnosticsEnabled.value) {
        unawaited(_flushPendingReports());
      } else {
        _pendingReports.clear();
      }
    } catch (_) {
      diagnosticsEnabled.value = false;
      _pendingReports.clear();
    }
  }

  Future<void> setDiagnosticsEnabled(bool enabled) async {
    final preferences = _preferences ?? await SharedPreferences.getInstance();
    _preferences = preferences;
    await preferences.setBool(diagnosticsPreferenceKey, enabled);
    diagnosticsEnabled.value = enabled;
    if (!enabled) {
      _pendingReports.clear();
      _consecutiveFlushFailures = 0;
      _nextFlushAttemptAt = null;
      return;
    }
    await _flushPendingReports();
  }

  void configure({required Future<FirebaseApp> firebaseAppFuture}) {
    final generation = ++_firebaseConfigurationGeneration;
    _firebaseAppFuture = firebaseAppFuture;
    // Startup may fail before the user can retry. Handle that attempt without
    // retaining a rejected future as the permanent reporting backend.
    firebaseAppFuture.then((app) {
      if (generation != _firebaseConfigurationGeneration) return;
      _consecutiveFlushFailures = 0;
      _nextFlushAttemptAt = null;
      _attachAuthListener(app);
      unawaited(_flushPendingReports());
    }).ignore();
  }

  void installHandlers() {
    if (_handlersInstalled) {
      return;
    }
    _handlersInstalled = true;
    _previousFlutterErrorHandler = FlutterError.onError;
    _previousPlatformErrorHandler = PlatformDispatcher.instance.onError;

    FlutterError.onError = (details) {
      _previousFlutterErrorHandler?.call(details);
      unawaited(recordFlutterError(details));
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(
        recordError(error, stack, fatal: true, reason: 'platform_dispatcher'),
      );
      try {
        _previousPlatformErrorHandler?.call(error, stack);
      } catch (previousError, previousStackTrace) {
        unawaited(
          recordError(
            previousError,
            previousStackTrace,
            fatal: true,
            reason: 'platform_dispatcher_previous_handler',
          ),
        );
      }
      return true;
    };
  }

  Future<void> recordFlutterError(
    FlutterErrorDetails details, {
    bool fatal = false,
  }) {
    return recordError(
      details.exception,
      details.stack ?? StackTrace.current,
      fatal: fatal,
      library: details.library,
      reason: 'flutter_framework',
    );
  }

  Future<void> recordError(
    Object error,
    StackTrace _, {
    bool fatal = false,
    String? library,
    String? reason,
  }) async {
    if (!diagnosticsEnabled.value) {
      return;
    }
    final rawMessage = error.toString();
    if (_isFirestoreTransportNoise(rawMessage)) {
      return;
    }

    final report = _PendingErrorReport(
      fatal: fatal,
      errorType: _diagnosticErrorType(error),
      libraryCode: _diagnosticLibraryCode(library),
      reasonCode: _diagnosticReasonCode(reason),
      buildMode: kReleaseMode
          ? 'release'
          : (kProfileMode ? 'profile' : 'debug'),
      platform: defaultTargetPlatform.name,
    );

    if (_pendingReports.length >= _maxPendingReports) {
      _pendingReports.removeFirst();
    }
    _pendingReports.add(report);
    await _flushPendingReports();
  }

  void _attachAuthListener(FirebaseApp app) {
    if (_authSubscription != null) {
      return;
    }
    final auth = _authForApp?.call(app) ?? FirebaseAuth.instanceFor(app: app);
    _authSubscription = auth.authStateChanges().listen((user) {
      if (user != null) {
        unawaited(_flushPendingReports());
      }
    });
  }

  Future<void> _flushPendingReports() async {
    if (!diagnosticsEnabled.value ||
        _flushInProgress ||
        _pendingReports.isEmpty) {
      return;
    }
    final nextAttempt = _nextFlushAttemptAt;
    if (nextAttempt != null && DateTime.now().isBefore(nextAttempt)) {
      return;
    }

    final firebaseAppFuture = _firebaseAppFuture;
    if (firebaseAppFuture == null) {
      return;
    }

    _flushInProgress = true;
    try {
      final app = await firebaseAppFuture;
      final auth = _authForApp?.call(app) ?? FirebaseAuth.instanceFor(app: app);
      final user = auth.currentUser;
      if (user == null) {
        return;
      }

      final functions = FirebaseFunctions.instanceFor(
        app: app,
        region: 'europe-west1',
      );
      while (_pendingReports.isNotEmpty) {
        final nextReport = _pendingReports.first;
        try {
          await functions
              .httpsCallable('submitClientErrorReport')
              .call(nextReport.toCallablePayload());
          _pendingReports.removeFirst();
          _consecutiveFlushFailures = 0;
          _nextFlushAttemptAt = null;
        } catch (_) {
          if (kDebugMode) {
            debugPrint('A minimal diagnostic report could not be submitted.');
          }
          _scheduleNextFlushRetry();
          break;
        }
      }
    } catch (_) {
      if (kDebugMode) {
        debugPrint('Minimal diagnostic reporting is temporarily unavailable.');
      }
      _scheduleNextFlushRetry();
    } finally {
      _flushInProgress = false;
    }
  }

  void _scheduleNextFlushRetry() {
    _consecutiveFlushFailures += 1;
    final exponent = _consecutiveFlushFailures.clamp(1, 8).toInt();
    final seconds = 1 << exponent;
    _nextFlushAttemptAt = DateTime.now().add(Duration(seconds: seconds));
  }

  bool _isFirestoreTransportNoise(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('firestore.googleapis.com') ||
        normalized.contains('webchannel_connection') ||
        normalized.contains('err_blocked_by_client');
  }

  String _redacted(String value) {
    return redactDiagnosticText(value);
  }

  String _diagnosticErrorType(Object error) {
    final normalized = error.runtimeType
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_.:-]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (normalized.isEmpty) {
      return 'unknown_error';
    }
    return normalized.length <= 80 ? normalized : normalized.substring(0, 80);
  }

  String _diagnosticReasonCode(String? value) {
    final normalized = value?.trim() ?? '';
    return RegExp(r'^[a-z][a-z0-9_.:-]{0,79}$').hasMatch(normalized)
        ? normalized
        : 'unspecified';
  }

  String _diagnosticLibraryCode(String? value) {
    final normalized = (value ?? '')
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_.:-]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (normalized.isEmpty) {
      return 'unspecified';
    }
    final bounded = normalized.length <= 80
        ? normalized
        : normalized.substring(0, 80);
    return RegExp(r'^[a-z][a-z0-9_.:-]{0,79}$').hasMatch(bounded)
        ? bounded
        : 'unspecified';
  }

  @visibleForTesting
  int get pendingReportCount => _pendingReports.length;

  @visibleForTesting
  String redactForTesting(String value) => _redacted(value);

  @visibleForTesting
  List<Map<String, Object?>> get pendingPayloadsForTesting =>
      List<Map<String, Object?>>.unmodifiable(
        _pendingReports.map((report) => report.toCallablePayload()),
      );
}

class _PendingErrorReport {
  const _PendingErrorReport({
    required this.fatal,
    required this.errorType,
    required this.libraryCode,
    required this.reasonCode,
    required this.buildMode,
    required this.platform,
  });

  final bool fatal;
  final String errorType;
  final String libraryCode;
  final String reasonCode;
  final String buildMode;
  final String platform;

  Map<String, Object?> toCallablePayload() {
    return <String, Object?>{
      'privacyVersion': clientDiagnosticPrivacyVersion,
      'source': 'flutter',
      'fatal': fatal,
      'errorType': errorType,
      'reasonCode': reasonCode,
      'libraryCode': libraryCode,
      'platform': platform,
      'buildMode': buildMode,
    };
  }
}
