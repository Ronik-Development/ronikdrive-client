import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';

import 'helpers/firebase_test_auth.dart';

import 'package:cloud_storage/src/shared/app_error_reporter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reporting reconnects after failed Firebase initialization', () async {
    final attached = <FirebaseApp>[];
    final reporter = AppErrorReporter.forTesting(
      authForApp: (app) {
        attached.add(app);
        return MockFirebaseAuth();
      },
    );
    final initial = Completer<FirebaseApp>();
    reporter.configure(firebaseAppFuture: initial.future);
    initial.completeError(StateError('synthetic initial failure'));
    await Future<void>.delayed(Duration.zero);
    expect(attached, isEmpty);
    final recovered = TestFirebaseApp();
    reporter.configure(firebaseAppFuture: Future.value(recovered));
    await Future<void>.delayed(Duration.zero);
    expect(attached, [recovered]);
    expect(reporter.diagnosticsEnabled.value, isFalse);
    expect(reporter.pendingReportCount, 0);
  });

  test('diagnostic sharing is off by default and drops reports', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    final reporter = AppErrorReporter.forTesting();
    await reporter.initializePrivacyPreferences(preferences: preferences);

    await reporter.recordError(
      Exception('private@example.com'),
      StackTrace.current,
    );

    expect(reporter.diagnosticsEnabled.value, isFalse);
    expect(reporter.pendingReportCount, 0);
  });

  test('disabling diagnostics clears queued reports', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      AppErrorReporter.diagnosticsPreferenceKey: true,
    });
    final preferences = await SharedPreferences.getInstance();
    final reporter = AppErrorReporter.forTesting();
    await reporter.initializePrivacyPreferences(preferences: preferences);
    await reporter.recordError(Exception('queued'), StackTrace.current);
    expect(reporter.pendingReportCount, 1);

    await reporter.setDiagnosticsEnabled(false);

    expect(reporter.pendingReportCount, 0);
    expect(
      preferences.getBool(AppErrorReporter.diagnosticsPreferenceKey),
      isFalse,
    );
  });

  test('diagnostic redaction removes common identity and secret forms', () {
    final reporter = AppErrorReporter.forTesting();
    final redacted = reporter.redactForTesting(
      'Bearer secret-token private@example.com '
      'uid=abc123 objectKey=user/file.pdf '
      'https://example.com/callback?token=secret#fragment '
      r'C:\Users\tom\project /home/alice/project',
    );

    expect(redacted, isNot(contains('secret-token')));
    expect(redacted, isNot(contains('private@example.com')));
    expect(redacted, isNot(contains('abc123')));
    expect(redacted, isNot(contains('user/file.pdf')));
    expect(redacted, isNot(contains('token=secret')));
    expect(redacted, isNot(contains(r'\tom\')));
    expect(redacted, isNot(contains('/alice/')));
  });

  test(
    'diagnostic payload sends fixed codes instead of exception text',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        AppErrorReporter.diagnosticsPreferenceKey: true,
      });
      final preferences = await SharedPreferences.getInstance();
      final reporter = AppErrorReporter.forTesting();
      await reporter.initializePrivacyPreferences(preferences: preferences);

      await reporter.recordError(
        Exception(
          'Quarterly Strategy in Northwind at '
          'https://storage.example/private/object-token',
        ),
        StackTrace.fromString(
          r'C:\Users\Alice\Board Papers\Quarterly Strategy:42 '
          'objectKey=user_0123456789abcdef0123456789abcdef/'
          'objects/aa/opaque-token',
        ),
        reason: 'upload_finalization',
        library: 'workspace upload',
      );

      final payload = reporter.pendingPayloadsForTesting.single;
      expect(payload['privacyVersion'], clientDiagnosticPrivacyVersion);
      expect(payload['errorType'], 'exception');
      expect(payload['reasonCode'], 'upload_finalization');
      expect(payload['libraryCode'], 'workspace_upload');
      expect(payload, isNot(contains('stackTrace')));
      expect(payload, isNot(contains('message')));
      expect(payload, isNot(contains('reason')));
      expect(payload, isNot(contains('library')));
      expect(payload.values.join(' '), isNot(contains('Quarterly Strategy')));
      expect(payload.values.join(' '), isNot(contains('Northwind')));
      expect(payload.values.join(' '), isNot(contains('opaque-token')));
      expect(payload.keys.toSet(), <String>{
        'privacyVersion',
        'source',
        'fatal',
        'errorType',
        'reasonCode',
        'libraryCode',
        'platform',
        'buildMode',
      });
    },
  );

  test(
    'free-form diagnostic reasons fail closed to an unspecified code',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        AppErrorReporter.diagnosticsPreferenceKey: true,
      });
      final preferences = await SharedPreferences.getInstance();
      final reporter = AppErrorReporter.forTesting();
      await reporter.initializePrivacyPreferences(preferences: preferences);

      await reporter.recordError(
        StateError('private data'),
        StackTrace.current,
        reason: 'Failure in Quarterly Strategy',
      );

      expect(
        reporter.pendingPayloadsForTesting.single['reasonCode'],
        'unspecified',
      );
    },
  );
}
