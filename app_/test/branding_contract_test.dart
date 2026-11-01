import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  final appRoot = _resolveAppRoot();

  test('user-facing Flutter and web sources use RonikCloud branding', () {
    final sourceRoots = [
      Directory(p.join(appRoot.path, 'lib')),
      Directory(p.join(appRoot.path, 'web')),
    ];
    final stale = <String>[];
    for (final root in sourceRoots) {
      for (final entity in root.listSync(recursive: true, followLinks: false)) {
        if (entity is! File || !_isTextSource(entity.path)) {
          continue;
        }
        if (entity.readAsStringSync().contains('RonikDrive')) {
          stale.add(p.relative(entity.path, from: appRoot.path));
        }
      }
    }
    expect(stale, isEmpty, reason: 'Stale visible product branding: $stale');
  });

  test('native platform display names use RonikCloud', () {
    final expected = <String, String>{
      'android/app/src/main/AndroidManifest.xml': 'android:label="RonikCloud"',
      'ios/Runner/Info.plist': '<string>RonikCloud</string>',
      'macos/Runner/Configs/AppInfo.xcconfig': 'PRODUCT_NAME = RonikCloud',
      'linux/runner/my_application.cc': '"RonikCloud"',
      'windows/runner/Runner.rc': 'VALUE "ProductName", "RonikCloud"',
    };
    for (final entry in expected.entries) {
      final contents = File(
        p.join(appRoot.path, p.fromUri(entry.key)),
      ).readAsStringSync();
      expect(contents, contains(entry.value), reason: entry.key);
    }
  });

  test('compatibility identifiers remain unchanged for existing installs', () {
    final releaseConfig = File(
      p.join(
        appRoot.path,
        'lib',
        'src',
        'shared',
        'release_runtime_config.dart',
      ),
    ).readAsStringSync();
    final iosInfo = File(
      p.join(appRoot.path, 'ios', 'Runner', 'Info.plist'),
    ).readAsStringSync();
    final windowsMetadata = File(
      p.join(appRoot.path, 'windows', 'runner', 'Runner.rc'),
    ).readAsStringSync();

    expect(releaseConfig, contains('ronikdrive://payment-cancel'));
    expect(iosInfo, contains('<string>ronikdrive</string>'));
    expect(windowsMetadata, contains('"RonikDrive.exe"'));
  });
}

Directory _resolveAppRoot() {
  final current = Directory.current.absolute;
  if (File(p.join(current.path, 'pubspec.yaml')).existsSync()) {
    return current;
  }
  final nested = Directory(p.join(current.path, 'app_'));
  if (File(p.join(nested.path, 'pubspec.yaml')).existsSync()) {
    return nested;
  }
  throw StateError('Could not locate the Flutter app root.');
}

bool _isTextSource(String path) {
  return const <String>{
    '.dart',
    '.arb',
    '.html',
    '.json',
    '.xml',
  }.contains(p.extension(path).toLowerCase());
}
