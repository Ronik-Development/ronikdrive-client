import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:grpc/grpc.dart' as grpc;

import 'firestore_wire/google/firestore/v1/document.pb.dart' as wire;
import 'firestore_wire/google/firestore/v1/firestore.pbgrpc.dart' as rpc;
import 'native_auth_session.dart';

part 'native_firestore_watch.dart';

class NativeFirestoreRpc {
  NativeFirestoreRpc({
    required this.session,
    required String apiKey,
    String databaseId = '(default)',
    int? emulatorPort,
  }) : database = 'projects/${session.projectId}/databases/$databaseId',
       _apiKey = apiKey {
    if (databaseId.isEmpty ||
        databaseId.contains('/') ||
        databaseId.contains(RegExp(r'[\x00-\x1f]'))) {
      throw ArgumentError('Invalid database identifier.');
    }
    if (emulatorPort != null &&
        (session.transport.emulatorPort == null ||
            emulatorPort < 1 ||
            emulatorPort > 65535)) {
      throw ArgumentError(
        'The database emulator requires a loopback emulator session.',
      );
    }
    _channel = emulatorPort == null
        ? grpc.ClientChannel(
            'firestore.googleapis.com',
            port: 443,
            options: const grpc.ChannelOptions(
              credentials: grpc.ChannelCredentials.secure(),
            ),
          )
        : grpc.ClientChannel(
            '127.0.0.1',
            port: emulatorPort,
            options: const grpc.ChannelOptions(
              credentials: grpc.ChannelCredentials.insecure(),
            ),
          );
    _client = rpc.FirestoreClient(_channel);
  }
  final NativeAuthSession session;
  final String database;
  final String _apiKey;
  late final grpc.ClientChannel _channel;
  late final rpc.FirestoreClient _client;
  final _watches = <_NativeFirestoreWatch>{};
  bool _closed = false;
  String get documentsRoot => '$database/documents';

  grpc.CallOptions _options(String? uid, {Duration? timeout}) =>
      grpc.CallOptions(
        timeout: timeout,
        providers: [
          (metadata, uri) async {
            if (_closed || uid != session.currentIdentity?.uid) {
              throw const grpc.GrpcError.cancelled('Account session changed.');
            }
            if (uid != null) {
              try {
                metadata['authorization'] =
                    'Bearer ${await session.idToken(forUid: uid)}';
              } catch (_) {
                throw const grpc.GrpcError.unauthenticated(
                  'Account authentication is required.',
                );
              }
            }
            if (_closed || uid != session.currentIdentity?.uid) {
              throw const grpc.GrpcError.cancelled('Account session changed.');
            }
            metadata['x-goog-api-key'] = _apiKey;
            metadata['google-cloud-resource-prefix'] = database;
            metadata['x-goog-request-params'] =
                'database=${Uri.encodeComponent(database)}';
          },
        ],
      );

  Future<T> invoke<T>(
    Future<T> Function(rpc.FirestoreClient, grpc.CallOptions) operation, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (_closed) throw _error('failed-precondition');
    final uid = session.currentIdentity?.uid;
    try {
      final result = await operation(_client, _options(uid, timeout: timeout));
      if (_closed || uid != session.currentIdentity?.uid) {
        throw _error('cancelled');
      }
      return result;
    } on grpc.GrpcError catch (error) {
      if (_closed || uid != session.currentIdentity?.uid) {
        throw _error('cancelled');
      }
      throw _grpcError(error.code);
    }
  }

  Stream<List<wire.Document>> watch(rpc.Target target) {
    if (_closed) return Stream.error(_error('failed-precondition'));
    final watch = _NativeFirestoreWatch(this, target);
    return watch.stream;
  }

  static FirebaseException _error(String code) => FirebaseException(
    plugin: 'cloud_firestore',
    code: code,
    message: 'The native database request could not be completed.',
  );
  static FirebaseException _grpcError(int code) => _error(switch (code) {
    1 => 'cancelled',
    2 => 'unknown',
    3 => 'invalid-argument',
    4 => 'deadline-exceeded',
    5 => 'not-found',
    6 => 'already-exists',
    7 => 'permission-denied',
    8 => 'resource-exhausted',
    9 => 'failed-precondition',
    10 => 'aborted',
    11 => 'out-of-range',
    12 => 'unimplemented',
    13 => 'internal',
    14 => 'unavailable',
    15 => 'data-loss',
    16 => 'unauthenticated',
    _ => 'unknown',
  });
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final watch in _watches.toList()) {
      await watch.close();
    }
    await _channel.terminate();
  }
}
