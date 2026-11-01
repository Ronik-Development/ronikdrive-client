import 'package:web/web.dart' as web;

void replaceCurrentUrl(String url) {
  web.window.history.replaceState(null, '', url);
}
