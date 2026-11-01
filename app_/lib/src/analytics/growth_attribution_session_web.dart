import 'package:web/web.dart' as web;
import 'dart:convert';

bool optionalGrowthAllowed() {
  try {
    final raw = web.window.localStorage.getItem(
      'ronikcloud.optional-analytics.v2',
    );
    if (raw == null) return false;
    final saved = jsonDecode(raw);
    final at = saved['at'];
    if (saved['allowed'] != true || at is! num || !at.isFinite) return false;
    final age = DateTime.now().millisecondsSinceEpoch - at;
    return age >= 0 && age < const Duration(days: 180).inMilliseconds;
  } on Object {
    return false;
  }
}

String? readGrowthAttributionSessionValue(String key) {
  try {
    if (!optionalGrowthAllowed()) return null;
    return web.window.sessionStorage.getItem(key);
  } on Object {
    return null;
  }
}

void writeGrowthAttributionSessionValue(String key, String value) {
  try {
    if (!optionalGrowthAllowed()) return;
    web.window.sessionStorage.setItem(key, value);
  } on Object {
    // Storage can be unavailable in hardened browser modes. Attribution is
    // best-effort and must never block navigation or conversion.
  }
}
