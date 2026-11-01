import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<void> runWithDesktopWorkerLease(
  Future<void> Function() action, {
  bool nativeDrive = false,
}) async {
  final support = await getApplicationSupportDirectory();
  await support.create(recursive: true);
  final handle = await File(
    p.join(
      support.path,
      nativeDrive ? 'desktop-drive-worker.lock' : 'desktop-backup-worker.lock',
    ),
  ).open(mode: FileMode.append);
  try {
    try {
      // Non-blocking OS lock, released even if the process crashes. A heartbeat
      // alone races when the UI and a login item start workers simultaneously.
      await handle.lock(FileLock.exclusive);
    } on FileSystemException {
      return;
    }
    try {
      await action();
    } finally {
      await handle.unlock();
    }
  } finally {
    await handle.close();
  }
}

void finishDesktopWorker(int code) => exit(code);
