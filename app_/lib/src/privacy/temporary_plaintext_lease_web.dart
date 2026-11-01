import '../shared/platform_io.dart';

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

class TemporaryPlaintextLease {
  TemporaryPlaintextLease._()
    : file = File(''),
      createdAt = DateTime.fromMillisecondsSinceEpoch(0),
      expiresAt = DateTime.fromMillisecondsSinceEpoch(0);

  final File file;
  final DateTime createdAt;
  DateTime expiresAt;

  bool get isActive => false;

  Future<void> writeBytes(List<int> bytes) async {
    throw const TemporaryPlaintextLeaseException(
      TemporaryPlaintextLeaseFailure.storageFailure,
      'Native temporary plaintext files are unavailable on the web.',
    );
  }

  Future<int> writeStream(
    Stream<List<int>> stream, {
    void Function()? checkAccess,
  }) async => throw UnsupportedError(
    'Private file streaming requires a native platform.',
  );

  Future<void> seal() async {}
  void scheduleRelease(Duration delay) {}
  Future<void> release() async {}
}

class TemporaryPlaintextLeaseManager {
  TemporaryPlaintextLeaseManager({
    TemporaryPlaintextRootProvider? rootDirectoryProvider,
    TemporaryPlaintextClock? clock,
    Object? random,
    this.defaultLifetime = const Duration(minutes: 30),
  });

  static const String rootDirectoryName = 'ronikdrive-plaintext-leases-v1';
  static const String legacyOpenDirectoryName = 'ronikdrive-open';
  final Duration defaultLifetime;

  static String extensionForName(String name) => '';

  Future<TemporaryPlaintextLease> create({String extension = ''}) async {
    throw const TemporaryPlaintextLeaseException(
      TemporaryPlaintextLeaseFailure.storageFailure,
      'Native temporary plaintext files are unavailable on the web.',
    );
  }

  Future<int> cleanupStale({
    Duration minimumAge = const Duration(hours: 1),
  }) async => 0;

  Future<int> cleanupActive({
    Duration minimumAge = const Duration(minutes: 2),
  }) async => 0;

  Future<int> clearAll() async => 0;

  Future<int> cleanupLegacyOpenDirectory({
    Duration minimumAge = const Duration(hours: 12),
    bool removeAll = false,
  }) async => 0;
}
