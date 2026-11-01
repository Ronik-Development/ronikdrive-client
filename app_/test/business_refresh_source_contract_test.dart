import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Business refreshes retain verified workspace and dashboard state', () {
    final workspace = File(
      'lib/src/business/business_workspace_page.dart',
    ).readAsStringSync();
    final administration = File(
      'lib/src/business/company_admin_page.dart',
    ).readAsStringSync();

    expect(
      workspace,
      contains('if (_errorMessage != null && _session == null)'),
    );
    expect(workspace, contains('BusinessAccessRefreshNotice('));
    expect(workspace, contains('if (preserveWorkspace)'));
    expect(workspace, contains('if (!preserveWorkspace)'));
    expect(workspace, contains('Company access could not be refreshed.'));
    expect(administration, contains('if (preserveDashboard)'));
    expect(administration, contains('_loading && _dashboard == null'));
  });
}
