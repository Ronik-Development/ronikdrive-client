import 'dart:io';

import 'package:cloud_storage/src/legal/legal_documents_page.dart';
import 'package:cloud_storage/src/legal/legal_html.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'public legal documents match the in-app source and work without JavaScript',
    () {
      final pages = renderLegalHtml();
      for (final entry in pages.entries) {
        final file = File('web/${entry.key}');
        if (const bool.fromEnvironment('UPDATE_LEGAL_HTML')) {
          file.writeAsStringSync(entry.value);
        }
        expect(
          file.readAsStringSync().replaceAll('\r\n', '\n'),
          entry.value,
          reason:
              'Regenerate with flutter test --dart-define=UPDATE_LEGAL_HTML=true test/legal_html_test.dart',
        );
        expect(entry.value, isNot(contains('<script')));
        expect(entry.value, contains('<main'));
        expect(entry.value, contains(LegalDocuments.legalVersion));
      }
      expect(pages['privacy.html'], contains('one month'));
      expect(pages['privacy.html'], contains('uoou.gov.cz'));
      expect(
        pages['cancellation-refund.html'],
        contains('Model withdrawal statement'),
      );
      expect(pages['acceptable-use.html'], contains('Illegal content notice'));
    },
  );
}
