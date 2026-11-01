import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cloud_storage/src/shared/app_error_reporter.dart';

void main() {
  test('automatic diagnostics use the codes-only privacy schema', () {
    expect(clientDiagnosticPrivacyVersion, 'client-diagnostic-codes-only-v3');

    final reporterSource = File(
      'lib/src/shared/app_error_reporter.dart',
    ).readAsStringSync();
    expect(reporterSource, isNot(contains("'stackTrace':")));
    expect(reporterSource, isNot(contains('stackTrace.toString()')));
    expect(reporterSource, isNot(contains('error.toString(),')));
  });

  test('client operational diagnostics do not interpolate private failures', () {
    final sources = <String>[
      'lib/main.dart',
      'lib/src/authentication/login_page.dart',
      'lib/src/shared/app_error_reporter.dart',
      'lib/src/shared/background_service.dart',
      'lib/src/home/workspace_home_page.dart',
      'lib/src/storage/drive_repository.dart',
      'lib/src/storage/wasabi_provisioning_service.dart',
      'lib/src/storage/wasabi_storage_service.dart',
    ].map((path) => File(path).readAsStringSync()).join('\n');

    final rawDiagnosticInterpolation = RegExp(
      r'''debugPrint\([^;\r\n]*(?:\$error\b|\$err\b|\$e\b|\$stack|\$\{file\.(?:id|name)\})''',
    );
    expect(sources, isNot(matches(rawDiagnosticInterpolation)));

    for (final prohibited in const <String>[
      'Received deep link:',
      'Failed to ensure Photos folder:',
      'File picker error:',
      'Folder picker error:',
      'Restore verification failed for',
      'Deferred thumbnail load for "\${file.name}"',
      'Uploading "\$displayName"',
      '_debugObjectLabel',
      '_debugOwnerLabel',
      '_safeErrorType',
    ]) {
      expect(sources, isNot(contains(prohibited)), reason: prohibited);
    }
  });
}
