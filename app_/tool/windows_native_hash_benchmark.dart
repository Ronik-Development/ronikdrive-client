// Opt-in Windows CNG experiment. Synthetic data only; never used by the app.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

void main() {
  if (!Platform.isWindows) throw UnsupportedError('Windows only');
  final kernel = DynamicLibrary.open('kernel32.dll');
  final heap = kernel
      .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
        'GetProcessHeap',
      )();
  final alloc = kernel
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>, Uint32, IntPtr),
        Pointer<Void> Function(Pointer<Void>, int, int)
      >('HeapAlloc');
  final free = kernel
      .lookupFunction<
        Int32 Function(Pointer<Void>, Uint32, Pointer<Void>),
        int Function(Pointer<Void>, int, Pointer<Void>)
      >('HeapFree');
  final allocations = <Pointer<Void>>[];
  Pointer<T> allocate<T extends NativeType>(int bytes) {
    final result = alloc(heap, 8, bytes);
    if (result == nullptr) throw StateError('Allocation failed');
    allocations.add(result);
    return result.cast<T>();
  }

  final cng = DynamicLibrary.open('bcrypt.dll');
  final open = cng
      .lookupFunction<
        Int32 Function(
          Pointer<Pointer<Void>>,
          Pointer<Uint16>,
          Pointer<Uint16>,
          Uint32,
        ),
        int Function(
          Pointer<Pointer<Void>>,
          Pointer<Uint16>,
          Pointer<Uint16>,
          int,
        )
      >('BCryptOpenAlgorithmProvider');
  final hash = cng
      .lookupFunction<
        Int32 Function(
          Pointer<Void>,
          Pointer<Uint8>,
          Uint32,
          Pointer<Uint8>,
          Uint32,
          Pointer<Uint8>,
          Uint32,
        ),
        int Function(
          Pointer<Void>,
          Pointer<Uint8>,
          int,
          Pointer<Uint8>,
          int,
          Pointer<Uint8>,
          int,
        )
      >('BCryptHash');
  final close = cng
      .lookupFunction<
        Int32 Function(Pointer<Void>, Uint32),
        int Function(Pointer<Void>, int)
      >('BCryptCloseAlgorithmProvider');
  final handles = <Pointer<Void>>[];
  try {
    final name = allocate<Uint16>(14);
    name.asTypedList(7).setAll(0, [...'SHA256'.codeUnits, 0]);
    final input = allocate<Uint8>(256 * 1024);
    final output = allocate<Uint8>(32);
    final secret = allocate<Uint8>(32);
    final key = Uint8List.fromList(List.filled(32, 7));
    secret.asTypedList(32).setAll(0, key);
    final block = Uint8List.fromList(List.generate(256 * 1024, (i) => i % 251));
    final samples = <Map<String, Object>>[];
    for (final hmac in [false, true]) {
      final slot = allocate<Pointer<Void>>(sizeOf<Pointer<Void>>());
      if (open(slot, name, nullptr, hmac ? 8 : 0) != 0) {
        throw StateError('CNG unavailable');
      }
      handles.add(slot.value);
      List<int> dartHash(Uint8List bytes) => hmac
          ? Hmac(sha256, key).convert(bytes).bytes
          : sha256.convert(bytes).bytes;
      List<int> nativeHash(Uint8List bytes) {
        input.asTypedList(bytes.length).setAll(0, bytes);
        if (hash(
              slot.value,
              hmac ? secret : nullptr,
              hmac ? 32 : 0,
              input,
              bytes.length,
              output,
              32,
            ) !=
            0) {
          throw StateError('CNG failed');
        }
        return Uint8List.fromList(output.asTypedList(32));
      }

      for (final length in [0, 1, 15, 16, 17, 63, 64, 65, block.length]) {
        final bytes = Uint8List.sublistView(block, 0, length);
        if (base64Encode(nativeHash(bytes)) != base64Encode(dartHash(bytes))) {
          throw StateError('Native compatibility mismatch');
        }
      }
      final expected = base64Encode(dartHash(block));
      for (var repetition = -3; repetition < 30; repetition++) {
        final methods = [('dart', dartHash), ('CNG-FFI', nativeHash)];
        for (final (method, run)
            in repetition.isEven ? methods : methods.reversed) {
          final watch = Stopwatch()..start();
          List<int>? digest;
          for (var i = 0; i < 40; i++) {
            digest = run(block);
          }
          final elapsed = watch.elapsedMicroseconds;
          if (base64Encode(digest!) != expected) {
            throw StateError('Hash mismatch');
          }
          if (repetition >= 0) {
            samples.add({
              'algorithm': hmac ? 'HMAC-SHA256' : 'SHA256',
              'method': method,
              'repetition': repetition,
              'bytes': block.length * 40,
              'microseconds': elapsed,
            });
          }
        }
      }
    }
    stdout.writeln(
      jsonEncode({
        'benchmark': 'Windows-CNG-AOT-experiment',
        'includesInputCopy': true,
        'integratedInApp': false,
        'samples': samples,
      }),
    );
  } finally {
    for (final handle in handles) {
      close(handle, 0);
    }
    for (final allocation in allocations.reversed) {
      free(heap, 0, allocation);
    }
  }
}
