import 'dart:convert';
import 'dart:math';

import 'package:web/web.dart' as web;

Future<bool> launchCheckoutInWeb(Uri uri) async {
  try {
    final safeUri = _uriWithSessionCheckoutState(uri);
    // Redirect in the same tab so web users continue the checkout flow.
    web.window.location.assign(safeUri.toString());
    return true;
  } catch (_) {
    return false;
  }
}

Uri _uriWithSessionCheckoutState(Uri uri) {
  final hasSensitiveCheckoutData =
      uri.queryParameters.containsKey('clientSecret') ||
      uri.queryParameters.containsKey('idToken') ||
      uri.queryParameters.containsKey('checkoutUrl');
  if (!hasSensitiveCheckoutData) {
    return uri;
  }

  final currentOrigin = web.window.location.origin;
  if (uri.origin != currentOrigin) {
    return uri;
  }

  final stateKey =
      'ronikdrive_checkout_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1 << 31)}';
  web.window.sessionStorage.setItem(stateKey, jsonEncode(uri.queryParameters));
  return uri.replace(
    queryParameters: <String, String>{'checkoutState': stateKey},
  );
}
