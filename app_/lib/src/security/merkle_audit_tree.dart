import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Represents a single immutable, cryptographically verifiable leaf in an audit chain.
class MerkleAuditLeaf {
  MerkleAuditLeaf({
    required this.sequenceNumber,
    required this.parentHash,
    required this.timestampMillis,
    required this.action,
    required this.actorId,
    required this.payloadDigest,
    String? leafHash,
  }) : leafHash = leafHash ??
            _computeHash(
              sequenceNumber: sequenceNumber,
              parentHash: parentHash,
              timestampMillis: timestampMillis,
              action: action,
              actorId: actorId,
              payloadDigest: payloadDigest,
            );

  final int sequenceNumber;
  final String parentHash;
  final int timestampMillis;
  final String action;
  final String actorId;
  final String payloadDigest;
  final String leafHash;

  static const String genesisParentHash =
      '0000000000000000000000000000000000000000000000000000000000000000';

  static String _computeHash({
    required int sequenceNumber,
    required String parentHash,
    required int timestampMillis,
    required String action,
    required String actorId,
    required String payloadDigest,
  }) {
    final rawString =
        '$sequenceNumber:$parentHash:$timestampMillis:$action:$actorId:$payloadDigest';
    return sha256.convert(utf8.encode(rawString)).toString();
  }

  /// Verifies that this leaf's hash strictly matches its computed digest.
  bool verifySelfHash() {
    final recomputed = _computeHash(
      sequenceNumber: sequenceNumber,
      parentHash: parentHash,
      timestampMillis: timestampMillis,
      action: action,
      actorId: actorId,
      payloadDigest: payloadDigest,
    );
    return recomputed == leafHash;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'seq': sequenceNumber,
        'parent': parentHash,
        'ts': timestampMillis,
        'action': action,
        'actor': actorId,
        'payload': payloadDigest,
        'hash': leafHash,
      };

  factory MerkleAuditLeaf.fromJson(Map<String, dynamic> json) {
    return MerkleAuditLeaf(
      sequenceNumber: json['seq'] as int,
      parentHash: json['parent'] as String,
      timestampMillis: json['ts'] as int,
      action: json['action'] as String,
      actorId: json['actor'] as String,
      payloadDigest: json['payload'] as String,
      leafHash: json['hash'] as String?,
    );
  }
}

/// Result of an audit chain integrity verification.
class AuditChainVerificationResult {
  const AuditChainVerificationResult({
    required this.isValid,
    required this.verifiedLeafCount,
    this.errorMessage,
  });

  final bool isValid;
  final int verifiedLeafCount;
  final String? errorMessage;
}

/// An append-only cryptographic audit chain for workspace mutations, providing
/// mathematical proof that historical logs have not been tampered with or rolled back.
class MerkleAuditChain {
  MerkleAuditChain({List<MerkleAuditLeaf>? initialLeaves})
      : _leaves = initialLeaves != null
            ? List<MerkleAuditLeaf>.from(initialLeaves)
            : <MerkleAuditLeaf>[];

  final List<MerkleAuditLeaf> _leaves;

  List<MerkleAuditLeaf> get leaves => List.unmodifiable(_leaves);
  int get length => _leaves.length;
  bool get isEmpty => _leaves.isEmpty;

  /// Returns the latest leaf hash, or the genesis parent hash if empty.
  String get currentHeadHash =>
      _leaves.isEmpty ? MerkleAuditLeaf.genesisParentHash : _leaves.last.leafHash;

  /// Appends a new verified mutation leaf to the audit chain.
  MerkleAuditLeaf append({
    required String action,
    required String actorId,
    required String payloadDigest,
    int? timestampMillis,
  }) {
    final nextSeq = _leaves.length;
    final parent = currentHeadHash;
    final ts = timestampMillis ?? DateTime.now().millisecondsSinceEpoch;

    final leaf = MerkleAuditLeaf(
      sequenceNumber: nextSeq,
      parentHash: parent,
      timestampMillis: ts,
      action: action,
      actorId: actorId,
      payloadDigest: payloadDigest,
    );

    _leaves.add(leaf);
    return leaf;
  }

  /// Verifies the cryptographic integrity of the entire audit chain.
  AuditChainVerificationResult verifyChain() {
    if (_leaves.isEmpty) {
      return const AuditChainVerificationResult(
        isValid: true,
        verifiedLeafCount: 0,
      );
    }

    var expectedParent = MerkleAuditLeaf.genesisParentHash;

    for (var i = 0; i < _leaves.length; i++) {
      final leaf = _leaves[i];

      if (leaf.sequenceNumber != i) {
        return AuditChainVerificationResult(
          isValid: false,
          verifiedLeafCount: i,
          errorMessage: 'Sequence mismatch at index $i: expected $i but got ${leaf.sequenceNumber}',
        );
      }

      if (leaf.parentHash != expectedParent) {
        return AuditChainVerificationResult(
          isValid: false,
          verifiedLeafCount: i,
          errorMessage:
              'Parent hash mismatch at index $i: expected $expectedParent but got ${leaf.parentHash}',
        );
      }

      if (!leaf.verifySelfHash()) {
        return AuditChainVerificationResult(
          isValid: false,
          verifiedLeafCount: i,
          errorMessage: 'Leaf hash verification failed at index $i',
        );
      }

      expectedParent = leaf.leafHash;
    }

    return AuditChainVerificationResult(
      isValid: true,
      verifiedLeafCount: _leaves.length,
    );
  }
}
