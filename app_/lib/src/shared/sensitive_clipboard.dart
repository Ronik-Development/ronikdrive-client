import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

typedef SensitiveClipboardRead = Future<String?> Function();
typedef SensitiveClipboardWrite = Future<void> Function(String value);
typedef SensitiveClipboardSchedule =
    void Function(Duration delay, void Function() callback);

class SensitiveClipboard {
  SensitiveClipboard({
    SensitiveClipboardRead? read,
    SensitiveClipboardWrite? write,
    SensitiveClipboardSchedule? schedule,
  }) : _read = read ?? _readPlatformClipboard,
       _write = write ?? _writePlatformClipboard,
       _schedule = schedule ?? _scheduleTimer;

  static const Duration defaultClearAfter = Duration(minutes: 2);

  final SensitiveClipboardRead _read;
  final SensitiveClipboardWrite _write;
  final SensitiveClipboardSchedule _schedule;

  Future<void> copy(
    String value, {
    Duration clearAfter = defaultClearAfter,
  }) async {
    if (value.isEmpty || value.length > 4096) {
      throw ArgumentError.value(value.length, 'value', 'Invalid secret length');
    }
    if (clearAfter <= Duration.zero) {
      throw ArgumentError.value(clearAfter, 'clearAfter', 'Must be positive');
    }
    await _write(value);
    final copiedLength = value.length;
    final copiedDigest = List<int>.unmodifiable(
      sha256.convert(utf8.encode(value)).bytes,
    );
    _schedule(clearAfter, () {
      unawaited(_clearIfUnchanged(copiedLength, copiedDigest));
    });
  }

  Future<void> _clearIfUnchanged(
    int copiedLength,
    List<int> copiedDigest,
  ) async {
    try {
      final current = await _read();
      if (current == null || current.length != copiedLength) {
        return;
      }
      final currentDigest = sha256.convert(utf8.encode(current)).bytes;
      if (!_constantTimeEquals(currentDigest, copiedDigest)) {
        return;
      }
      await _write('');
    } catch (_) {
      // Browsers and operating systems may deny clipboard reads outside a
      // direct user gesture. The copy still succeeds; the UI asks the user to
      // clear sensitive text manually after use.
    }
  }

  static Future<String?> _readPlatformClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    return data?.text;
  }

  static Future<void> _writePlatformClipboard(String value) {
    return Clipboard.setData(ClipboardData(text: value));
  }

  static void _scheduleTimer(Duration delay, void Function() callback) {
    Timer(delay, callback);
  }
}

bool _constantTimeEquals(List<int> left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }
  var difference = 0;
  for (var index = 0; index < left.length; index += 1) {
    difference |= left[index] ^ right[index];
  }
  return difference == 0;
}

final SensitiveClipboard sensitiveClipboard = SensitiveClipboard();
