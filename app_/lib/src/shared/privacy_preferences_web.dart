import 'dart:js_interop';

@JS('ronikPrivacy.open')
external void _openPrivacyPreferences();

bool openPrivacyPreferences() {
  try {
    _openPrivacyPreferences();
    return true;
  } catch (_) {
    return false;
  }
}
