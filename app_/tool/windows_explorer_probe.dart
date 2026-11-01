// Synthetic local-only CFAPI test. Never loads Firebase or customer keys.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart';
import 'package:cloud_storage/src/desktop_drive/drive_provider_broker.dart';
import 'package:cloud_storage/src/desktop_drive/drive_provider_protocol.dart';

class SyntheticDrive implements DriveProviderBackend, RecoverableDriveCreates {
  bool valid = true;
  final created = Completer<void>();
  final updated = Completer<void>();
  final replaced = Completer<void>();
  ProviderItem? localItem;
  var remoteVersion = '1';
  var localContents = '';
  var bytes = Uint8List.fromList(
    utf8.encode('RonikCloud synthetic Explorer test.'),
  );
  ProviderItem get file => ProviderItem(
    id: 'f:synthetic',
    parentId: 'root',
    name: 'Explorer-test.txt',
    version: remoteVersion,
    directory: false,
    size: bytes.length,
  );
  void check() {
    if (!valid) throw const ProviderFailure('unauthorized');
  }

  @override
  void invalidate() {
    valid = false;
  }

  @override
  Future<List<ProviderItem>> list(String parentId) async {
    check();
    return [file, if (localItem != null) localItem!];
  }

  @override
  Future<ProviderItem> item(String id) async {
    check();
    return id == 'f:created' ? localItem! : file;
  }

  @override
  Future<Uint8List> read(String id, String version) async {
    check();
    if (id != file.id || version != file.version) {
      throw const ProviderFailure('conflict');
    }
    return Uint8List.fromList(bytes);
  }

  @override
  Future<ProviderItem> create(
    String parentId,
    String name,
    bool directory,
    Uint8List contents,
  ) async {
    check();
    debugPrint('EXPLORER_PROBE create_request length=${contents.length}');
    if (utf8.decode(contents) != 'Synthetic local create') {
      throw StateError('Create contents mismatch');
    }
    localContents = utf8.decode(contents);
    localItem = ProviderItem(
      id: 'f:created',
      parentId: parentId,
      name: name,
      version: '1',
      directory: directory,
      size: contents.length,
    );
    if (!created.isCompleted) created.complete();
    return localItem!;
  }

  @override
  Future<ProviderItem> createWithRequestId(
    String requestId,
    String parentId,
    String name,
    bool directory,
    Uint8List contents,
  ) => create(parentId, name, directory, contents);
  @override
  Future<ProviderItem> update(
    String id,
    String version,
    String? parentId,
    String? name,
    Uint8List? contents,
  ) async {
    check();
    debugPrint(
      'EXPLORER_PROBE update_request id=$id version=$version length=${contents?.length}',
    );
    if (id != 'f:created' || contents == null) {
      throw StateError('Update mismatch');
    }
    final content = utf8.decode(contents);
    if (localItem!.version != version) {
      if (localContents == content) return localItem!;
      throw const ProviderFailure('conflict');
    }
    localContents = content;
    localItem = ProviderItem(
      id: id,
      parentId: 'root',
      name: 'Created-test.txt',
      version: '${int.parse(version) + 1}',
      directory: false,
      size: contents.length,
    );
    if (version == '1' && !updated.isCompleted) updated.complete();
    if (version == '2' && !replaced.isCompleted) replaced.complete();
    return localItem!;
  }

  @override
  Future<void> recycle(String id, String version) async =>
      throw const ProviderFailure('read-only');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SizedBox.shrink());
  const channel = MethodChannel('ronikcloud/desktop-drive');
  final backend = SyntheticDrive();
  var broker = DriveProviderBroker(backend);
  final domain = sha256
      .convert(utf8.encode('ronikcloud-synthetic-explorer-probe-v2-$pid'))
      .toString();
  var result = 1;
  try {
    final endpoint = await broker.start();
    final root = await channel.invokeMethod<String>('start', {
      'domain': domain,
      'port': endpoint.port,
      'token': endpoint.token,
      'rootItems': jsonEncode({
        'items': (await backend.list(
          'root',
        )).map((item) => item.toJson()).toList(),
      }),
    });
    if (root == null) throw StateError('No sync root');
    final items = await Directory(
      root,
    ).list().toList().timeout(const Duration(seconds: 40));
    debugPrint('EXPLORER_PROBE enumeration=${items.length}');
    final file = File('$root\\Explorer-test.txt');
    final bytes = await file.readAsBytes().timeout(const Duration(seconds: 40));
    if (utf8.decode(bytes) != utf8.decode(backend.bytes)) {
      throw StateError('Content mismatch');
    }
    debugPrint('EXPLORER_PROBE authenticated_read=PASS');
    final local = File('$root\\Created-test.txt');
    await local.writeAsString('Synthetic local create');
    await backend.created.future.timeout(const Duration(seconds: 30));
    await Future<void>.delayed(const Duration(seconds: 2));
    debugPrint('EXPLORER_PROBE local_create=PASS');
    final handle = await local.open(mode: FileMode.writeOnlyAppend);
    await handle.writeString(' edit');
    await handle.close();
    await backend.updated.future.timeout(const Duration(seconds: 30));
    debugPrint('EXPLORER_PROBE local_edit=PASS');
    await Future<void>.delayed(const Duration(seconds: 2));
    await local.writeAsString('Synthetic replacement');
    await backend.replaced.future.timeout(const Duration(seconds: 30));
    debugPrint('EXPLORER_PROBE file_replacement=PASS');
    var acknowledged = false;
    for (var attempt = 0; attempt < 30; attempt++) {
      final state = await channel.invokeMapMethod<String, dynamic>('inspect', {
        'name': 'Created-test.txt',
      });
      if (state?['inSync'] == true &&
          jsonDecode(state!['identity'] as String)['version'] == '3') {
        acknowledged = true;
        break;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    if (!acknowledged) {
      throw StateError('Windows did not acknowledge the latest version');
    }
    debugPrint('EXPLORER_PROBE windows_acknowledgement=PASS');
    backend.remoteVersion = '2';
    backend.bytes = Uint8List.fromList(utf8.encode('Synthetic remote edit'));
    Future<void> waitVersion(String name, String version) async {
      for (var i = 0; i < 40; i++) {
        final state = await channel.invokeMapMethod<String, dynamic>(
          'inspect',
          {'name': name},
        );
        if (state?['inSync'] == true &&
            jsonDecode(state!['identity'] as String)['version'] == version) {
          return;
        }
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      throw StateError('Version not acknowledged');
    }

    await waitVersion('Explorer-test.txt', '2');
    String? refreshed;
    for (var attempt = 0; attempt < 20; attempt++) {
      try {
        refreshed = await file.readAsString();
        break;
      } on FileSystemException catch (error) {
        if (error.osError?.errorCode != 32) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
    if (refreshed != 'Synthetic remote edit') {
      throw StateError('Stale remote contents');
    }
    debugPrint('EXPLORER_PROBE remote_refresh=PASS');
    Future<void> restart() async {
      backend.valid = true;
      broker = DriveProviderBroker(backend);
      final next = await broker.start();
      await channel.invokeMethod<String>('start', {
        'domain': domain,
        'port': next.port,
        'token': next.token,
        'rootItems': jsonEncode({
          'items': (await backend.list(
            'root',
          )).map((item) => item.toJson()).toList(),
        }),
      });
    }

    await broker.stop();
    await channel.invokeMethod<void>('stop');
    await local.writeAsString('Synthetic replacement after restart');
    await restart();
    await waitVersion('Created-test.txt', '4');
    debugPrint('EXPLORER_PROBE durable_replacement_recovery=PASS');
    await broker.stop();
    await channel.invokeMethod<void>('stop');
    await local.writeAsString('Synthetic offline conflict');
    backend.localContents = 'Newer remote contents';
    backend.localItem = ProviderItem(
      id: 'f:created',
      parentId: 'root',
      name: 'Created-test.txt',
      version: '5',
      directory: false,
      size: backend.localContents.length,
    );
    await restart();
    var conflict = false;
    for (var i = 0; i < 30; i++) {
      if (await channel.invokeMethod<String>('heartbeat') ==
          'needs-attention') {
        conflict = true;
        break;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    if (!conflict ||
        await local.readAsString() != 'Synthetic offline conflict' ||
        backend.localContents != 'Newer remote contents') {
      throw StateError('Conflict was not preserved');
    }
    debugPrint('EXPLORER_PROBE conflict_preserves_both=PASS');
    result = 0;
  } on PlatformException catch (e) {
    debugPrint(
      'EXPLORER_PROBE native_error=${e.code} windows_status=${e.details}',
    );
  } catch (e) {
    debugPrint(
      'EXPLORER_PROBE failure=${e.runtimeType} code=${e is FileSystemException ? e.osError?.errorCode : null}',
    );
  } finally {
    await broker.stop();
    await channel.invokeMethod<void>('remove');
  }
  exit(result);
}
