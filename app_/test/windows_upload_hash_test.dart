import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_storage/src/storage/windows_upload_hash.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Windows acceleration is available and exactly preserves SHA-256',
    () {
      final native = WindowsUploadHash.instance;
      expect(
        native,
        isNotNull,
        reason: 'Do not silently benchmark the fallback',
      );
      for (final size in [0, 1, 15, 16, 17, 63, 64, 65, 65537, 256 * 1024]) {
        final bytes = Uint8List.fromList(List.generate(size, (i) => i % 251));
        expect(native!.digest(bytes), sha256.convert(bytes).toString());
        expect(native.digest(bytes), sha256.convert(bytes).toString());
      }
      expect(native!.digest(Uint8List(256 * 1024 + 1)), isNull);
    },
    skip:
        !Platform.isWindows ||
        !const bool.fromEnvironment(
          'NATIVE_UPLOAD_HASHING',
          defaultValue: false,
        ),
  );
}
