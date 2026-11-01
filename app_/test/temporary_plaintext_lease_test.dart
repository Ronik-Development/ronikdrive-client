import 'dart:io';
import 'dart:math';

import 'package:cloud_storage/src/privacy/temporary_plaintext_lease.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory sandbox;
  late Directory leaseRoot;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp(
      'ronikdrive-plaintext-lease-test-',
    );
    leaseRoot = Directory(
      p.join(sandbox.path, TemporaryPlaintextLeaseManager.rootDirectoryName),
    );
  });

  tearDown(() async {
    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  });

  TemporaryPlaintextLeaseManager manager({
    DateTime Function()? clock,
    int seed = 41,
  }) {
    return TemporaryPlaintextLeaseManager(
      rootDirectoryProvider: () async => leaseRoot,
      clock: clock,
      random: Random(seed),
      defaultLifetime: const Duration(hours: 1),
    );
  }

  test(
    'uses an opaque lease directory and a generic content filename',
    () async {
      final lease = await manager().create(extension: '.pdf');

      expect(
        p.basename(lease.file.parent.path),
        matches(RegExp(r'^lease-[A-Za-z0-9_-]{32}$')),
      );
      expect(p.basename(lease.file.path), 'content.pdf');
      expect(lease.file.path.toLowerCase(), isNot(contains('payroll')));

      await lease.writeBytes(<int>[1, 2, 3, 4]);
      expect(await lease.file.readAsBytes(), <int>[1, 2, 3, 4]);
      await lease.release();

      expect(await lease.file.parent.exists(), isFalse);
      expect(lease.isActive, isFalse);
    },
  );

  test('accepts only bounded alphanumeric file extensions', () async {
    expect(
      TemporaryPlaintextLeaseManager.extensionForName('Report.Final.PDF'),
      '.pdf',
    );
    expect(TemporaryPlaintextLeaseManager.extensionForName('no-extension'), '');
    expect(
      TemporaryPlaintextLeaseManager.extensionForName(
        'file.thisextensionistoolong',
      ),
      '',
    );

    expect(
      manager().create(extension: '../secret'),
      throwsA(
        isA<TemporaryPlaintextLeaseException>().having(
          (error) => error.failure,
          'failure',
          TemporaryPlaintextLeaseFailure.invalidInput,
        ),
      ),
    );
  });

  test(
    'crash cleanup removes only recognized stale lease directories',
    () async {
      await leaseRoot.create(recursive: true);
      final staleLease = Directory(
        p.join(leaseRoot.path, 'lease-${List.filled(32, 'A').join()}'),
      );
      final unrelatedDirectory = Directory(
        p.join(leaseRoot.path, 'customer-visible-folder'),
      );
      final similarlyNamedFile = File(
        p.join(leaseRoot.path, 'lease-${List.filled(32, 'B').join()}'),
      );
      await staleLease.create();
      await unrelatedDirectory.create();
      await similarlyNamedFile.writeAsString('leave me alone');

      final removed = await manager(
        clock: () => DateTime.now().add(const Duration(hours: 1)),
      ).cleanupStale(minimumAge: Duration.zero);

      expect(removed, 1);
      expect(await staleLease.exists(), isFalse);
      expect(await unrelatedDirectory.exists(), isTrue);
      expect(await similarlyNamedFile.exists(), isTrue);
    },
  );

  test(
    'resume cleanup releases only active leases older than the limit',
    () async {
      var now = DateTime.utc(2026, 7, 24, 10);
      final leases = manager(clock: () => now);
      final older = await leases.create(extension: '.txt');

      now = now.add(const Duration(minutes: 3));
      final newer = await leases.create(extension: '.txt');
      final removed = await leases.cleanupActive(
        minimumAge: const Duration(minutes: 2),
      );

      expect(removed, 1);
      expect(older.isActive, isFalse);
      expect(await older.file.parent.exists(), isFalse);
      expect(newer.isActive, isTrue);
      expect(await newer.file.exists(), isTrue);

      await newer.release();
    },
  );

  test('manual cleanup clears every active plaintext lease', () async {
    final leases = manager();
    final first = await leases.create(extension: '.txt');
    final second = await leases.create(extension: '.zip');

    expect(await leases.clearAll(), 2);
    expect(first.isActive, isFalse);
    expect(second.isActive, isFalse);
    expect(await first.file.parent.exists(), isFalse);
    expect(await second.file.parent.exists(), isFalse);
  });

  test('legacy cleanup stays scoped to the old RonikDrive directory', () async {
    final legacy = Directory(
      p.join(
        sandbox.path,
        TemporaryPlaintextLeaseManager.legacyOpenDirectoryName,
      ),
    );
    final legacyFile = File(p.join(legacy.path, 'old-copy.txt'));
    final neighbor = File(p.join(sandbox.path, 'unrelated-copy.txt'));
    await legacy.create(recursive: true);
    await legacyFile.writeAsString('old');
    await neighbor.writeAsString('keep');

    final removed = await manager().cleanupLegacyOpenDirectory(removeAll: true);

    expect(removed, 1);
    expect(await legacyFile.exists(), isFalse);
    expect(await neighbor.exists(), isTrue);
  });
}
