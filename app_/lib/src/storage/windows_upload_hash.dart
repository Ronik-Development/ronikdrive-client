import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

/// Device-local SHA-256 only. No keys, network access or format changes.
/// Each synchronous call owns and wipes its native buffers before returning.
class WindowsUploadHash {
  WindowsUploadHash._();
  static final WindowsUploadHash? instance = _load();
  static WindowsUploadHash? _load() {
    if (!Platform.isWindows ||
        !const bool.fromEnvironment(
          'NATIVE_UPLOAD_HASHING',
          defaultValue: false,
        )) {
      return null;
    }
    try {
      final result = WindowsUploadHash._();
      if (result.digest(Uint8List(0)) !=
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855') {
        return null;
      }
      return result;
    } catch (_) {
      return null;
    }
  }

  late final _kernel = DynamicLibrary.open('kernel32.dll');
  late final _heap = _kernel
      .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
        'GetProcessHeap',
      )();
  late final _allocate = _kernel
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>, Uint32, IntPtr),
        Pointer<Void> Function(Pointer<Void>, int, int)
      >('HeapAlloc');
  late final _free = _kernel
      .lookupFunction<
        Int32 Function(Pointer<Void>, Uint32, Pointer<Void>),
        int Function(Pointer<Void>, int, Pointer<Void>)
      >('HeapFree');

  late final _cng = _loadSystemCng();
  DynamicLibrary _loadSystemCng() {
    final directory = _allocate(_heap, 8, 65536).cast<Uint16>();
    if (directory == nullptr) throw StateError('Native hashing unavailable');
    try {
      final length = _kernel
          .lookupFunction<
            Uint32 Function(Pointer<Uint16>, Uint32),
            int Function(Pointer<Uint16>, int)
          >('GetSystemDirectoryW')(directory, 32768);
      if (length == 0 || length >= 32768) {
        throw StateError('Native hashing unavailable');
      }
      return DynamicLibrary.open(
        '${String.fromCharCodes(directory.asTypedList(length))}\\bcrypt.dll',
      );
    } finally {
      _free(_heap, 0, directory.cast());
    }
  }

  late final _open = _cng
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
  late final _hash = _cng
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
  late final _close = _cng
      .lookupFunction<
        Int32 Function(Pointer<Void>, Uint32),
        int Function(Pointer<Void>, int)
      >('BCryptCloseAlgorithmProvider');

  String? digest(Uint8List bytes) {
    if (bytes.length > 256 * 1024) return null;
    final allocations = <Pointer<Void>>[];
    Pointer<Uint8>? input;
    Pointer<Uint8>? output;
    Pointer<Void> handle = nullptr;
    Pointer<T> allocate<T extends NativeType>(int count) {
      final result = _allocate(_heap, 8, count);
      if (result == nullptr) throw StateError('Native hashing unavailable');
      allocations.add(result);
      return result.cast<T>();
    }

    try {
      final name = allocate<Uint16>(14);
      name.asTypedList(7).setAll(0, [...'SHA256'.codeUnits, 0]);
      final slot = allocate<Pointer<Void>>(sizeOf<Pointer<Void>>());
      if (_open(slot, name, nullptr, 0) != 0) return null;
      handle = slot.value;
      input = allocate<Uint8>(bytes.isEmpty ? 1 : bytes.length);
      output = allocate<Uint8>(32);
      input.asTypedList(bytes.length).setAll(0, bytes);
      if (_hash(handle, nullptr, 0, input, bytes.length, output, 32) != 0) {
        return null;
      }
      return output
          .asTypedList(32)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
    } catch (_) {
      return null; // The caller retains the existing Dart SHA-256 fallback.
    } finally {
      input?.asTypedList(bytes.length).fillRange(0, bytes.length, 0);
      output?.asTypedList(32).fillRange(0, 32, 0);
      if (handle != nullptr) _close(handle, 0);
      for (final allocation in allocations.reversed) {
        _free(_heap, 0, allocation);
      }
    }
  }
}
