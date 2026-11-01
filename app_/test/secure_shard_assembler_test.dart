import 'dart:typed_data';

import 'package:cloud_storage/src/security/encryption_service.dart';
import 'package:cloud_storage/src/storage/secure_shard_assembler.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final service = EncryptionService.instance;
  final key = SecretKey(List<int>.generate(32, (index) => index + 1));
  final plain = Uint8List.fromList(
    List<int>.generate(500, (index) => index % 251),
  );

  test('all secure shards reassemble and authenticate', () async {
    final encrypted = await service.encryptData(plain, key);
    final shards = <Uint8List>[
      encrypted.sublist(0, 180),
      encrypted.sublist(180, 360),
      encrypted.sublist(360),
    ];
    final restored = await assembleSecureShards(
      shardCount: shards.length,
      openShard: (index) async => Stream.value(shards[index]),
      decryptWholeFile: (bytes) => service.decryptData(bytes, key),
    );
    expect(restored, plain);
  });

  test('a missing shard fails without returning partial plaintext', () async {
    await expectLater(
      assembleSecureShards(
        shardCount: 3,
        openShard: (index) async {
          if (index == 1) throw StateError('object not found');
          return Stream.value(<int>[index]);
        },
      ),
      throwsA(
        isA<SecureShardReadException>().having(
          (error) => error.shardIndex,
          'shardIndex',
          1,
        ),
      ),
    );
  });

  test('a corrupted shard fails whole-file authentication', () async {
    final encrypted = await service.encryptData(plain, key);
    encrypted[encrypted.length ~/ 2] ^= 0xff;
    await expectLater(
      assembleSecureShards(
        shardCount: 2,
        openShard: (index) async => Stream.value(
          index == 0
              ? encrypted.sublist(0, encrypted.length ~/ 2)
              : encrypted.sublist(encrypted.length ~/ 2),
        ),
        decryptWholeFile: (bytes) => service.decryptData(bytes, key),
      ),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });

  test(
    'rejects cumulative shard bytes above the local buffer ceiling',
    () async {
      var decryptCalled = false;

      await expectLater(
        assembleSecureShards(
          shardCount: 2,
          openShard: (index) async =>
              Stream.value(index == 0 ? <int>[1, 2, 3] : <int>[4, 5]),
          maxBufferedBytes: 4,
          decryptWholeFile: (bytes) async {
            decryptCalled = true;
            return bytes;
          },
        ),
        throwsA(
          isA<SecureShardReadException>().having(
            (error) => error.cause,
            'cause',
            isA<FormatException>(),
          ),
        ),
      );
      expect(decryptCalled, isFalse);
    },
  );

  test('accepts a cumulative shard payload exactly at its ceiling', () async {
    final restored = await assembleSecureShards(
      shardCount: 2,
      openShard: (index) async =>
          Stream.value(index == 0 ? <int>[1, 2] : <int>[3, 4]),
      maxBufferedBytes: 4,
    );

    expect(restored, orderedEquals(<int>[1, 2, 3, 4]));
  });
}
