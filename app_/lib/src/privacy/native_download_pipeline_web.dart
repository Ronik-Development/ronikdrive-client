import 'package:cryptography/cryptography.dart';
import 'temporary_plaintext_lease.dart';

Stream<List<int>> decryptFramedDownload(
  Stream<List<int>> encrypted, {
  required SecretKey key,
  required TemporaryPlaintextLeaseManager manager,
  required void Function() checkAccess,
}) =>
    throw UnsupportedError('Framed file streaming requires a native platform.');

class NativeStreamingZip {
  static Future<NativeStreamingZip> create(TemporaryPlaintextLease lease) =>
      throw UnsupportedError('Native ZIP unavailable.');
  Future<void> add(TemporaryPlaintextLease lease, String name) =>
      throw UnsupportedError('Native ZIP unavailable.');
  Future<void> close() async {}
  void cancel() {}
}
