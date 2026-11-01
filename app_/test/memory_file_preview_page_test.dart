import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_storage/src/home/memory_file_preview_page.dart';
import 'package:cloud_storage/src/privacy/memory_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  Future<void> open(
    WidgetTester tester,
    PreviewReadGuard guard,
    Future<Uint8List> Function() load, {
    MemoryPreviewKind kind = MemoryPreviewKind.text,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MemoryFilePreviewPage(
          name: 'private.txt',
          kind: kind,
          guard: guard,
          load: load,
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('loads once, renders inert text and wipes the input', (
    tester,
  ) async {
    final guard = PreviewReadGuard(() => true);
    var loads = 0;
    final bytes = Uint8List.fromList(
      utf8.encode('<script>private content</script>'),
    );
    await open(tester, guard, () async {
      loads++;
      return bytes;
    });
    await tester.pumpAndSettle();
    expect(find.text('<script>private content</script>'), findsOneWidget);
    expect(bytes.every((byte) => byte == 0), true);
    expect(loads, 1);
    expect(find.text('Download'), findsNothing);
    guard.cancel();
    await tester.pumpAndSettle();
    expect(find.text('<script>private content</script>'), findsNothing);
    expect(find.text('private.txt'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    guard.dispose();
  });

  testWidgets('large text renders only visible rows', (tester) async {
    final guard = PreviewReadGuard(() => true);
    final text = List.generate(5000, (i) => 'Line $i: text content').join('\n');
    await open(
      tester,
      guard,
      () async => Uint8List.fromList(utf8.encode(text)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Line 0: text content'), findsOneWidget);
    expect(find.byType(Text).evaluate().length, lessThan(100));
    expect(find.text('Line 4999: text content'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    guard.dispose();
  });

  testWidgets('late completion after closing is discarded and wiped', (
    tester,
  ) async {
    final guard = PreviewReadGuard(() => true);
    final pending = Completer<Uint8List>();
    await open(tester, guard, () => pending.future);
    await tester.pumpWidget(const SizedBox.shrink());
    final bytes = Uint8List.fromList(utf8.encode('late secret'));
    pending.complete(bytes);
    await tester.pump();
    expect(bytes.every((byte) => byte == 0), true);
    expect(guard.cancelled, true);
    expect(tester.takeException(), isNull);
    guard.dispose();
  });

  testWidgets(
    'backgrounding hides content and reopening requires a new session',
    (tester) async {
      final guard = PreviewReadGuard(() => true);
      await open(
        tester,
        guard,
        () async => Uint8List.fromList(utf8.encode('secret')),
      );
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.text('secret'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('secret'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      guard.dispose();
    },
  );

  testWidgets(
    'image decoding bypasses the global image cache and disposes on revoke',
    (tester) async {
      final guard = PreviewReadGuard(() => true);
      final before = PaintingBinding.instance.imageCache.currentSize;
      final png = img.encodePng(img.Image(width: 2, height: 2));
      await open(tester, guard, () async => png, kind: MemoryPreviewKind.image);
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      expect(find.byType(RawImage), findsOneWidget);
      expect(PaintingBinding.instance.imageCache.currentSize, before);
      expect(png.every((byte) => byte == 0), true);
      guard.cancel();
      await tester.pump();
      expect(find.byType(RawImage), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      guard.dispose();
    },
  );

  testWidgets('load failures never reveal internal exception details', (
    tester,
  ) async {
    final guard = PreviewReadGuard(() => true);
    await open(
      tester,
      guard,
      () async => throw StateError('secret-key/private/path'),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('could not be verified'), findsOneWidget);
    expect(find.textContaining('secret-key'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    guard.dispose();
  });

  testWidgets('oversized image dimensions fail before rendering', (
    tester,
  ) async {
    final guard = PreviewReadGuard(() => true);
    final png = img.encodePng(img.Image(width: 16385, height: 1));
    await open(tester, guard, () async => png, kind: MemoryPreviewKind.image);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(find.byType(RawImage), findsNothing);
    expect(find.textContaining('could not be verified'), findsOneWidget);
    expect(png.every((byte) => byte == 0), true);
    await tester.pumpWidget(const SizedBox.shrink());
    guard.dispose();
  });
}
