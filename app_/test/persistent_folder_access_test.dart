import 'dart:async';

import 'package:cloud_storage/src/shared/persistent_folder_access.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('ronikcloud/folder-access');
  final calls = <MethodCall>[];
  late FutureOr<Object?> Function(MethodCall) reply;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    calls.clear();
    reply = (call) => call.method == 'acquire' ? 'lease-1' : null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return await reply(call);
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    test(
      '$platform retains access until asynchronous reading completes',
      () async {
        debugDefaultTargetPlatformOverride = platform;
        final read = Completer<int>();
        final started = Completer<void>();
        final result = PersistentFolderAccess.withAccess(
          path: '/chosen',
          bookmark: 'bookmark',
          action: () {
            started.complete();
            return read.future;
          },
        );
        await started.future;
        expect(calls.map((c) => c.method), ['acquire']);
        expect(calls.single.arguments, {
          'path': '/chosen',
          'bookmark': 'bookmark',
        });
        read.complete(42);
        expect(await result, 42);
        expect(calls.map((c) => c.method), ['acquire', 'release']);
        expect(calls.last.arguments, 'lease-1');
      },
    );
  }

  test('an action failure releases access and preserves the failure', () async {
    final failure = StateError('upload failed');
    await expectLater(
      PersistentFolderAccess.withAccess<void>(
        path: '/chosen',
        bookmark: 'bookmark',
        action: () async => throw failure,
      ),
      throwsA(same(failure)),
    );
    expect(calls.map((c) => c.method), ['acquire', 'release']);
  });

  test('concurrent close calls release a lease exactly once', () async {
    final lease = await PersistentFolderAccess.acquire(
      path: '/chosen',
      bookmark: 'bookmark',
    );
    await Future.wait([lease.close(), lease.close(), lease.close()]);
    expect(calls.where((c) => c.method == 'release'), hasLength(1));
  });

  test(
    'release during engine teardown does not mask an action failure',
    () async {
      reply = (call) {
        if (call.method == 'release') {
          throw PlatformException(code: 'engine-closed');
        }
        return 'lease-1';
      };
      final failure = StateError('read failed');
      await expectLater(
        PersistentFolderAccess.withAccess<void>(
          path: '/chosen',
          bookmark: 'bookmark',
          action: () async => throw failure,
        ),
        throwsA(same(failure)),
      );
    },
  );

  test(
    'a missing grant never falls back to reading a raw saved path',
    () async {
      var read = false;
      await expectLater(
        PersistentFolderAccess.withAccess<void>(
          path: '/chosen',
          action: () async {
            read = true;
          },
        ),
        throwsA(isA<FolderAccessException>()),
      );
      expect(read, isFalse);
      expect(calls, isEmpty);
    },
  );

  test(
    'revoked or stale grants require selection again before reading',
    () async {
      reply = (_) => throw PlatformException(
        code: 'access-required',
        message: 'private path',
      );
      var read = false;
      await expectLater(
        PersistentFolderAccess.withAccess<void>(
          path: '/chosen',
          bookmark: 'revoked',
          action: () async {
            read = true;
          },
        ),
        throwsA(isA<FolderAccessException>()),
      );
      expect(read, isFalse);
      expect(calls.map((c) => c.method), ['acquire']);
      expect(
        const FolderAccessException().message,
        isNot(contains('private path')),
      );
    },
  );

  test('missing native registration fails closed', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await expectLater(
      PersistentFolderAccess.acquire(path: '/chosen', bookmark: 'bookmark'),
      throwsA(isA<FolderAccessException>()),
    );
  });

  test(
    'malformed paths and oversized grants are rejected before native calls',
    () async {
      for (final path in ['relative', '/chosen\u0000other']) {
        await expectLater(
          PersistentFolderAccess.acquire(path: path, bookmark: 'bookmark'),
          throwsA(isA<FolderAccessException>()),
        );
      }
      await expectLater(
        PersistentFolderAccess.acquire(path: '/chosen', bookmark: 'x' * 90001),
        throwsA(isA<FolderAccessException>()),
      );
      expect(calls, isEmpty);
    },
  );

  test('Windows backup continues without an Apple method channel', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(
      await PersistentFolderAccess.withAccess(
        path: r'C:\chosen',
        action: () async => 7,
      ),
      7,
    );
    expect(calls, isEmpty);
  });

  test('cancelled picker leaves saved access unchanged', () async {
    expect(await PersistentFolderAccess.pick(), isNull);
    expect(calls.map((c) => c.method), ['pick']);
  });

  test('picker accepts an absolute folder and opaque bookmark', () async {
    reply = (_) => {'path': '/chosen', 'bookmark': 'opaque'};
    final selected = await PersistentFolderAccess.pick();
    expect(selected?.path, '/chosen');
    expect(selected?.bookmark, 'opaque');
  });

  test('malformed picker results cannot create a saved grant', () async {
    for (final result in [
      {'path': 'relative', 'bookmark': 'opaque'},
      {'path': '/chosen', 'bookmark': ''},
      {'path': '/chosen\u0000other', 'bookmark': 'opaque'},
      {'path': '/chosen', 'bookmark': 12},
    ]) {
      reply = (_) => result;
      await expectLater(
        PersistentFolderAccess.pick(),
        throwsA(isA<FolderAccessException>()),
      );
    }
  });
}
