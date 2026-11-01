import 'package:flutter/material.dart';

import '../legal/legal_documents_page.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const LegalDocumentPage(document: LegalDocuments.privacy);
  }
}
