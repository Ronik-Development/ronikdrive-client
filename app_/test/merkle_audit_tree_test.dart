import 'package:cloud_storage/src/security/merkle_audit_tree.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MerkleAuditChain tests', () {
    test('Empty chain is valid', () {
      final chain = MerkleAuditChain();
      expect(chain.isEmpty, isTrue);
      expect(chain.currentHeadHash, equals(MerkleAuditLeaf.genesisParentHash));

      final result = chain.verifyChain();
      expect(result.isValid, isTrue);
      expect(result.verifiedLeafCount, equals(0));
    });

    test('Appends and verifies sequential mutation leaves', () {
      final chain = MerkleAuditChain();

      final leaf0 = chain.append(
        action: 'FILE_CREATE',
        actorId: 'user_1',
        payloadDigest: 'digest_aaa',
        timestampMillis: 1000,
      );

      expect(leaf0.sequenceNumber, equals(0));
      expect(leaf0.parentHash, equals(MerkleAuditLeaf.genesisParentHash));
      expect(leaf0.verifySelfHash(), isTrue);

      final leaf1 = chain.append(
        action: 'FILE_UPDATE',
        actorId: 'user_1',
        payloadDigest: 'digest_bbb',
        timestampMillis: 2000,
      );

      expect(leaf1.sequenceNumber, equals(1));
      expect(leaf1.parentHash, equals(leaf0.leafHash));

      final leaf2 = chain.append(
        action: 'FILE_DELETE',
        actorId: 'user_2',
        payloadDigest: 'digest_ccc',
        timestampMillis: 3000,
      );

      expect(leaf2.sequenceNumber, equals(2));
      expect(leaf2.parentHash, equals(leaf1.leafHash));

      final result = chain.verifyChain();
      expect(result.isValid, isTrue);
      expect(result.verifiedLeafCount, equals(3));
    });

    test('Detects modified payload digest (tampering)', () {
      final chain = MerkleAuditChain();
      chain.append(
        action: 'FILE_CREATE',
        actorId: 'user_1',
        payloadDigest: 'digest_original',
      );

      // Create a corrupted clone with modified payload
      final original = chain.leaves.first;
      final tamperedLeaf = MerkleAuditLeaf(
        sequenceNumber: original.sequenceNumber,
        parentHash: original.parentHash,
        timestampMillis: original.timestampMillis,
        action: original.action,
        actorId: original.actorId,
        payloadDigest: 'digest_tampered',
        leafHash: original.leafHash, // Retaining old hash
      );

      final corruptedChain = MerkleAuditChain(initialLeaves: [tamperedLeaf]);
      final result = corruptedChain.verifyChain();

      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('Leaf hash verification failed'));
    });

    test('Detects deleted or missing intermediate leaf (chain break)', () {
      final chain = MerkleAuditChain();
      final l0 = chain.append(action: 'A', actorId: 'u', payloadDigest: 'd1');
      chain.append(action: 'B', actorId: 'u', payloadDigest: 'd2');
      final l2 = chain.append(action: 'C', actorId: 'u', payloadDigest: 'd3');

      // Omit leaf 1
      final brokenChain = MerkleAuditChain(initialLeaves: [l0, l2]);
      final result = brokenChain.verifyChain();

      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('Sequence mismatch'));
    });

    test('Serialization to and from JSON preserves cryptographic verification', () {
      final chain = MerkleAuditChain();
      chain.append(action: 'ACTION_1', actorId: 'u1', payloadDigest: 'd1');
      chain.append(action: 'ACTION_2', actorId: 'u2', payloadDigest: 'd2');

      final serialized = chain.leaves.map((l) => l.toJson()).toList();
      final deserializedLeaves =
          serialized.map((json) => MerkleAuditLeaf.fromJson(json)).toList();

      final restoredChain = MerkleAuditChain(initialLeaves: deserializedLeaves);
      final result = restoredChain.verifyChain();

      expect(result.isValid, isTrue);
      expect(result.verifiedLeafCount, equals(2));
    });
  });
}
