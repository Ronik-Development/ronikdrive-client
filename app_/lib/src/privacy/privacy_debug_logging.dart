import 'package:flutter/foundation.dart';

import 'privacy_redaction.dart';

bool _privacySafeDebugPrintInstalled = false;

void installPrivacySafeDebugPrint() {
  if (_privacySafeDebugPrintInstalled) {
    return;
  }
  _privacySafeDebugPrintInstalled = true;
  final previousDebugPrint = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (!kDebugMode || message == null) {
      return;
    }
    previousDebugPrint(redactDiagnosticText(message), wrapWidth: wrapWidth);
  };
}
