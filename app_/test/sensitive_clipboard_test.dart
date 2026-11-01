import 'package:cloud_storage/src/shared/sensitive_clipboard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'unchanged sensitive clipboard content is cleared after its lease',
    () async {
      String? clipboard;
      Duration? scheduledDelay;
      void Function()? scheduledCallback;
      final lease = SensitiveClipboard(
        read: () async => clipboard,
        write: (value) async => clipboard = value,
        schedule: (delay, callback) {
          scheduledDelay = delay;
          scheduledCallback = callback;
        },
      );

      await lease.copy('private-invitation-code');
      expect(clipboard, 'private-invitation-code');
      expect(scheduledDelay, SensitiveClipboard.defaultClearAfter);

      scheduledCallback!();
      await pumpEventQueue();
      expect(clipboard, isEmpty);
    },
  );

  test('newer clipboard content is never overwritten', () async {
    String? clipboard;
    void Function()? scheduledCallback;
    final lease = SensitiveClipboard(
      read: () async => clipboard,
      write: (value) async => clipboard = value,
      schedule: (_, callback) => scheduledCallback = callback,
    );

    await lease.copy('private-invitation-code');
    clipboard = 'new user clipboard content';
    scheduledCallback!();
    await pumpEventQueue();

    expect(clipboard, 'new user clipboard content');
  });

  test('a denied background clipboard read fails privately', () async {
    final writes = <String>[];
    void Function()? scheduledCallback;
    final lease = SensitiveClipboard(
      read: () async => throw StateError('clipboard permission denied'),
      write: (value) async => writes.add(value),
      schedule: (_, callback) => scheduledCallback = callback,
    );

    await lease.copy('private-invitation-code');
    scheduledCallback!();
    await pumpEventQueue();

    expect(writes, <String>['private-invitation-code']);
  });
}
