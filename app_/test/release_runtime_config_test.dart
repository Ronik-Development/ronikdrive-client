import 'package:cloud_storage/src/shared/release_runtime_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('local API base is a directory under the Functions emulator', () {
    final base = ReleaseRuntimeConfig.resolveCheckoutApiBaseUri();

    expect(base.host, '127.0.0.1');
    expect(base.path, '/demo-ronikdrive-local/europe-west1/api/');
    expect(
      base.resolve('storage/wasabi/proxy-upload').path,
      '/demo-ronikdrive-local/europe-west1/api/storage/wasabi/proxy-upload',
    );
  });

  test('callable REST fallbacks share the emulator resolver', () {
    expect(
      ReleaseRuntimeConfig.resolveCallableRestUri(
        functionName: 'deleteUserAccount',
      ).path,
      '/demo-ronikdrive-local/europe-west1/deleteUserAccount',
    );
  });
}
