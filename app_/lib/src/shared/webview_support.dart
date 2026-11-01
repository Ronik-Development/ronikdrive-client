import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

/// Ensures that a concrete [WebViewPlatform] implementation is registered.
///
/// Returns `true` when a platform implementation is available and has been
/// registered, otherwise returns `false`.
bool ensureWebViewPlatformRegistered() {
  if (WebViewPlatform.instance != null) {
    return true;
  }

  try {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        WebViewPlatform.instance = AndroidWebViewPlatform();
        break;
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        WebViewPlatform.instance = WebKitWebViewPlatform();
        break;
      default:
        break;
    }
  } catch (_) {
    // Ignore failures and fall through to the final null check below.
  }

  return WebViewPlatform.instance != null;
}
