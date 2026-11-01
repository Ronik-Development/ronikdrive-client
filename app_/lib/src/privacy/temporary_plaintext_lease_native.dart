import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum TemporaryPlaintextLeaseFailure {
  invalidInput,
  permissionFailure,
  storageFailure,
}

class TemporaryPlaintextLeaseException implements Exception {
  const TemporaryPlaintextLeaseException(this.failure, this.message);

  final TemporaryPlaintextLeaseFailure failure;
  final String message;

  @override
  String toString() => 'TemporaryPlaintextLeaseException: $message';
}

typedef TemporaryPlaintextRootProvider = Future<Directory> Function();
typedef TemporaryPlaintextClock = DateTime Function();

/// A bounded plaintext file intended only for an explicit external-app action.
///
/// The containing directory and filename are opaque. Call [seal] after another
/// component writes the file, or use [writeBytes]. [scheduleRelease] may
/// shorten the default lease after a share/open handoff completes.
class TemporaryPlaintextLease {
  TemporaryPlaintextLease._({
    required this.file,
    required this.createdAt,
    required this.expiresAt,
    required TemporaryPlaintextLeaseManager owner,
  }) : _owner = owner;

  final File file;
  final DateTime createdAt;
  DateTime expiresAt;
  final TemporaryPlaintextLeaseManager _owner;

  bool get isActive => _owner._isActive(file.parent.path);

  Future<void> writeBytes(List<int> bytes) async {
    if (!isActive) {
      throw const TemporaryPlaintextLeaseException(
        TemporaryPlaintextLeaseFailure.storageFailure,
        'The temporary plaintext lease has expired.',
      );
    }
    try {
      await file.writeAsBytes(bytes, flush: true);
      await seal();
    } on TemporaryPlaintextLeaseException {
      rethrow;
    } catch (_) {
      await release();
      throw const TemporaryPlaintextLeaseException(
        TemporaryPlaintextLeaseFailure.storageFailure,
        'The temporary plaintext copy could not be written.',
      );
    }
  }

  /// Publish only after the source completes successfully (including its MAC).
  Future<int> writeStream(
    Stream<List<int>> stream, {
    void Function()? checkAccess,
  }) async {
    IOSink? sink;
    var count = 0;
    try {
      if (!isActive) throw StateError('The private lease expired.');
      checkAccess?.call();
      sink = file.openWrite(mode: FileMode.writeOnly);
      final guarded = () async* {
        await for (final chunk in stream) {
          if (!isActive) throw StateError('The private lease expired.');
          checkAccess?.call();
          count += chunk.length;
          yield chunk;
        }
        checkAccess?.call();
      }();
      await sink.addStream(guarded);
      await sink.flush();
      await sink.close();
      sink = null;
      checkAccess?.call();
      await seal();
      return count;
    } catch (_) {
      try {
        await sink?.close();
      } catch (_) {}
      await release();
      rethrow;
    }
  }

  Future<void> seal() => _owner._sealFile(this);

  void scheduleRelease(Duration delay) {
    _owner._scheduleRelease(this, delay);
  }

  Future<void> release() => _owner._release(this);
}

/// Owns private, opaque, automatically expiring plaintext handoff files.
class TemporaryPlaintextLeaseManager {
  TemporaryPlaintextLeaseManager({
    TemporaryPlaintextRootProvider? rootDirectoryProvider,
    TemporaryPlaintextClock? clock,
    Random? random,
    this.defaultLifetime = const Duration(minutes: 30),
  }) : _rootDirectoryProvider = rootDirectoryProvider ?? _defaultRootDirectory,
       _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure() {
    if (defaultLifetime <= Duration.zero) {
      throw const TemporaryPlaintextLeaseException(
        TemporaryPlaintextLeaseFailure.invalidInput,
        'The temporary plaintext lifetime must be positive.',
      );
    }
  }

  static const String rootDirectoryName = 'ronikdrive-plaintext-leases-v1';
  static const String legacyOpenDirectoryName = 'ronikdrive-open';
  static final RegExp _leaseDirectoryName = RegExp(
    r'^lease-[A-Za-z0-9_-]{32}$',
  );
  static final RegExp _safeExtension = RegExp(r'^\.[A-Za-z0-9]{1,16}$');

  final TemporaryPlaintextRootProvider _rootDirectoryProvider;
  final TemporaryPlaintextClock _clock;
  final Random _random;
  final Duration defaultLifetime;
  final Map<String, TemporaryPlaintextLease> _active =
      <String, TemporaryPlaintextLease>{};
  final Map<String, Timer> _timers = <String, Timer>{};

  static Future<Directory> _defaultRootDirectory() async {
    final temporaryDirectory = await getTemporaryDirectory();
    return Directory(p.join(temporaryDirectory.path, rootDirectoryName));
  }

  static String extensionForName(String name) {
    final extension = p.extension(name).toLowerCase();
    return _safeExtension.hasMatch(extension) ? extension : '';
  }

  Future<TemporaryPlaintextLease> create({String extension = ''}) async {
    final normalizedExtension = extension.trim().toLowerCase();
    if (normalizedExtension.isNotEmpty &&
        !_safeExtension.hasMatch(normalizedExtension)) {
      throw const TemporaryPlaintextLeaseException(
        TemporaryPlaintextLeaseFailure.invalidInput,
        'The temporary plaintext file extension is invalid.',
      );
    }

    Directory? leaseDirectory;
    try {
      final root = await _rootDirectoryProvider();
      await root.create(recursive: true);
      await _applyPrivateMode(root.path, directory: true);

      for (var attempt = 0; attempt < 8; attempt += 1) {
        final token = base64UrlEncode(
          List<int>.generate(24, (_) => _random.nextInt(256)),
        ).replaceAll('=', '');
        final candidate = Directory(p.join(root.path, 'lease-$token'));
        if (await candidate.exists()) {
          continue;
        }
        await candidate.create();
        leaseDirectory = candidate;
        break;
      }
      if (leaseDirectory == null) {
        throw const TemporaryPlaintextLeaseException(
          TemporaryPlaintextLeaseFailure.storageFailure,
          'A unique temporary plaintext lease could not be created.',
        );
      }
      await _applyPrivateMode(leaseDirectory.path, directory: true);

      final file = File(
        p.join(leaseDirectory.path, 'content$normalizedExtension'),
      );
      await file.create(exclusive: true);
      await _applyPrivateMode(file.path, directory: false);
      final createdAt = _clock();
      final lease = TemporaryPlaintextLease._(
        file: file,
        createdAt: createdAt,
        expiresAt: createdAt.add(defaultLifetime),
        owner: this,
      );
      _active[leaseDirectory.path] = lease;
      _scheduleRelease(lease, defaultLifetime);
      return lease;
    } on TemporaryPlaintextLeaseException {
      if (leaseDirectory != null) {
        await _deleteDirectoryBestEffort(leaseDirectory);
      }
      rethrow;
    } catch (_) {
      if (leaseDirectory != null) {
        await _deleteDirectoryBestEffort(leaseDirectory);
      }
      throw const TemporaryPlaintextLeaseException(
        TemporaryPlaintextLeaseFailure.storageFailure,
        'A private temporary plaintext lease could not be created.',
      );
    }
  }

  Future<int> cleanupStale({
    Duration minimumAge = const Duration(hours: 1),
  }) async {
    if (minimumAge.isNegative) {
      throw const TemporaryPlaintextLeaseException(
        TemporaryPlaintextLeaseFailure.invalidInput,
        'The temporary plaintext cleanup age is invalid.',
      );
    }
    final root = await _rootDirectoryProvider();
    if (!await root.exists()) {
      return 0;
    }
    final cutoff = _clock().subtract(minimumAge);
    var removed = 0;
    try {
      await for (final entity in root.list(followLinks: false)) {
        if (entity is! Directory ||
            !_leaseDirectoryName.hasMatch(p.basename(entity.path)) ||
            _active.containsKey(entity.path)) {
          continue;
        }
        try {
          final stat = await entity.stat();
          if (!stat.modified.isAfter(cutoff)) {
            await entity.delete(recursive: true);
            removed += 1;
          }
        } catch (_) {
          // An inaccessible lease is retried by a later cleanup pass.
        }
      }
      return removed;
    } catch (_) {
      throw const TemporaryPlaintextLeaseException(
        TemporaryPlaintextLeaseFailure.storageFailure,
        'Temporary plaintext crash recovery could not complete.',
      );
    }
  }

  Future<int> cleanupActive({
    Duration minimumAge = const Duration(minutes: 2),
  }) async {
    if (minimumAge.isNegative) {
      throw const TemporaryPlaintextLeaseException(
        TemporaryPlaintextLeaseFailure.invalidInput,
        'The active temporary plaintext cleanup age is invalid.',
      );
    }
    final cutoff = _clock().subtract(minimumAge);
    final targets = _active.values
        .where((lease) => !lease.createdAt.isAfter(cutoff))
        .toList(growable: false);
    for (final lease in targets) {
      await _release(lease);
    }
    return targets.length;
  }

  Future<int> clearAll() async {
    final active = _active.values.toList(growable: false);
    var removed = 0;
    for (final lease in active) {
      final directory = lease.file.parent;
      await _release(lease);
      if (!await directory.exists()) {
        removed += 1;
      }
    }

    final root = await _rootDirectoryProvider();
    if (await root.exists()) {
      await for (final entity in root.list(followLinks: false)) {
        if (entity is! Directory ||
            !_leaseDirectoryName.hasMatch(p.basename(entity.path))) {
          continue;
        }
        await _deleteDirectoryBestEffort(entity);
        if (!await entity.exists()) {
          removed += 1;
        }
      }
    }
    return removed;
  }

  Future<int> cleanupLegacyOpenDirectory({
    Duration minimumAge = const Duration(hours: 12),
    bool removeAll = false,
  }) async {
    final root = await _rootDirectoryProvider();
    final legacy = Directory(p.join(root.parent.path, legacyOpenDirectoryName));
    if (!await legacy.exists()) {
      return 0;
    }
    final cutoff = _clock().subtract(minimumAge);
    var removed = 0;
    await for (final entity in legacy.list(followLinks: false)) {
      try {
        final stat = await entity.stat();
        if (removeAll || !stat.modified.isAfter(cutoff)) {
          await entity.delete(recursive: true);
          removed += 1;
        }
      } catch (_) {
        // Keep cleaning other entries.
      }
    }
    try {
      if (await legacy.list(followLinks: false).isEmpty) {
        await legacy.delete();
      }
    } catch (_) {
      // An empty legacy directory is harmless.
    }
    return removed;
  }

  bool _isActive(String directoryPath) => _active.containsKey(directoryPath);

  Future<void> _sealFile(TemporaryPlaintextLease lease) async {
    if (!_isActive(lease.file.parent.path) || !await lease.file.exists()) {
      throw const TemporaryPlaintextLeaseException(
        TemporaryPlaintextLeaseFailure.storageFailure,
        'The temporary plaintext lease is unavailable.',
      );
    }
    await _applyPrivateMode(lease.file.path, directory: false);
  }

  void _scheduleRelease(TemporaryPlaintextLease lease, Duration delay) {
    if (delay <= Duration.zero || !_isActive(lease.file.parent.path)) {
      unawaited(_release(lease));
      return;
    }
    final path = lease.file.parent.path;
    _timers.remove(path)?.cancel();
    lease.expiresAt = _clock().add(delay);
    _timers[path] = Timer(delay, () {
      unawaited(_release(lease));
    });
  }

  Future<void> _release(TemporaryPlaintextLease lease) async {
    final path = lease.file.parent.path;
    _timers.remove(path)?.cancel();
    _active.remove(path);
    await _deleteDirectoryBestEffort(lease.file.parent);
  }

  Future<void> _applyPrivateMode(String path, {required bool directory}) async {
    if (!Platform.isLinux && !Platform.isMacOS) {
      return;
    }
    final result = await Process.run('/bin/chmod', [
      directory ? '700' : '600',
      path,
    ]);
    if (result.exitCode != 0) {
      throw const TemporaryPlaintextLeaseException(
        TemporaryPlaintextLeaseFailure.permissionFailure,
        'Private temporary-file permissions could not be applied.',
      );
    }
  }

  Future<void> _deleteDirectoryBestEffort(Directory directory) async {
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } catch (_) {
      // Startup cleanup retries an abandoned lease.
    }
  }
}
