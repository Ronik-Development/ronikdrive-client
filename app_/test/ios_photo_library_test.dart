import 'package:cloud_storage/src/shared/ios_photo_library.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('ronikcloud/photo-library');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'manual selection does not request photo-library authorization',
    () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return [
          {'path': '/private/export/image.heic', 'name': 'IMG_1234.HEIC'},
        ];
      });
      final files = await IosPhotoLibrary.pick();
      expect(calls, ['pick']);
      expect(files.single.name, 'IMG_1234.HEIC');
      expect(files.single.path, '/private/export/image.heic');
    },
  );

  test('cancelled picker returns no uploads', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => []);
    expect(await IosPhotoLibrary.pick(), isEmpty);
  });

  test(
    'denied backup access fails before enumeration and never prompts',
    () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return 'denied';
      });
      await expectLater(
        IosPhotoLibrary.assets().toList(),
        throwsA(isA<PlatformException>()),
      );
      expect(calls, ['status']);
    },
  );

  test('limited library is paged without exporting image bytes', () async {
    final offsets = <int>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'status') return 'limited';
      expect(call.method, 'list');
      final offset = (call.arguments as Map)['offset'] as int;
      offsets.add(offset);
      return List.generate(
        offset == 0 ? 100 : 2,
        (index) => {
          'id': 'asset-${offset + index}/L0/001',
          'modified': 1234567890,
        },
      );
    });
    final assets = await IosPhotoLibrary.assets().toList();
    expect(offsets, [0, 100]);
    expect(assets.length, 102);
    expect(assets.map((asset) => asset.sourcePath).toSet().length, 102);
    expect(assets.first.token, matches(RegExp(r'^[a-f0-9]{64}$')));
    expect(assets.first.sourcePath, isNot(contains('/L0/001')));
  });

  test(
    'asset identity survives edits while the checkpoint revision changes',
    () {
      final before = IosPhotoAsset({'id': 'same-asset', 'modified': 1000});
      final after = IosPhotoAsset({'id': 'same-asset', 'modified': 2000});
      expect(before.sourcePath, after.sourcePath);
      expect(before.modified, isNot(after.modified));
    },
  );

  test(
    'export sends expected revision and release targets only returned export',
    () async {
      final asset = IosPhotoAsset({'id': 'id', 'modified': 1000});
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'export') {
          expect(call.arguments, {'id': 'id', 'modified': 1000});
          return {
            'path': '/private/export/image.heic',
            'name': 'original.heic',
          };
        }
        expect(call.method, 'release');
        expect(call.arguments, {'path': '/private/export/image.heic'});
        return null;
      });
      await IosPhotoLibrary.release(await IosPhotoLibrary.export(asset));
    },
  );

  test(
    'partial native selection failure cannot silently upload a subset',
    () async {
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(
          code: 'photo_export',
          message: '/private/name.heic',
        );
      });
      await expectLater(
        IosPhotoLibrary.pick(),
        throwsA(isA<PlatformException>()),
      );
      expect(
        IosPhotoLibrary.message(
          PlatformException(
            code: 'photo_export',
            message: '/private/name.heic',
          ),
        ),
        isNot(contains('/private/name.heic')),
      );
    },
  );
}
