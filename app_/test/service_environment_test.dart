import 'package:cloud_storage/src/shared/service_environment.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ServiceEnvironmentPolicy', () {
    test('debug builds default to local emulators', () {
      expect(
        ServiceEnvironmentPolicy.resolve(rawEnvironment: '', isRelease: false),
        ServiceEnvironment.local,
      );
    });

    test('release builds fail closed without an explicit environment', () {
      expect(
        () => ServiceEnvironmentPolicy.resolve(
          rawEnvironment: '',
          isRelease: true,
        ),
        throwsA(isA<ServiceEnvironmentException>()),
      );
    });

    test('production must be explicitly selected', () {
      expect(
        ServiceEnvironmentPolicy.resolve(
          rawEnvironment: 'production',
          isRelease: true,
        ),
        ServiceEnvironment.production,
      );
    });

    test('a live-account debug preview must explicitly select production', () {
      expect(
        ServiceEnvironmentPolicy.resolve(
          rawEnvironment: 'production',
          isRelease: false,
        ),
        ServiceEnvironment.production,
      );
    });

    test('tester is an alias for staging', () {
      expect(
        ServiceEnvironmentPolicy.resolve(
          rawEnvironment: 'tester',
          isRelease: true,
        ),
        ServiceEnvironment.staging,
      );
    });

    test('staging cannot use the production Firebase project', () {
      expect(
        () => ServiceEnvironmentPolicy.validateFirebaseProject(
          environment: ServiceEnvironment.staging,
          projectId: ServiceEnvironmentPolicy.productionProjectId,
        ),
        throwsA(isA<ServiceEnvironmentException>()),
      );
      expect(
        () => ServiceEnvironmentPolicy.validateFirebaseProject(
          environment: ServiceEnvironment.staging,
          projectId: 'unmarked-customer-project',
        ),
        throwsA(isA<ServiceEnvironmentException>()),
      );
    });

    test('local can call loopback but not a remote host', () {
      expect(
        ServiceEnvironmentPolicy.requireSafeServiceUri(
          environment: ServiceEnvironment.local,
          uri: Uri.parse('http://127.0.0.1:5001/example'),
        ).host,
        '127.0.0.1',
      );
      expect(
        () => ServiceEnvironmentPolicy.requireSafeServiceUri(
          environment: ServiceEnvironment.local,
          uri: Uri.parse('https://example.test/api'),
        ),
        throwsA(isA<ServiceEnvironmentException>()),
      );
    });

    test('local Firebase options pass Firebase Auth Web validation', () {
      final options = ServiceEnvironmentConfig.firebaseOptions(
        const FirebaseOptions(
          apiKey: 'production-key-is-not-used',
          appId: 'production-app-is-not-used',
          messagingSenderId: 'production-sender-is-not-used',
          projectId: ServiceEnvironmentPolicy.productionProjectId,
        ),
      );

      expect(options.projectId, ServiceEnvironmentPolicy.localProjectId);
      expect(options.apiKey, matches(RegExp(r'^AIza[0-9A-Za-z_-]{35}$')));
    });

    test('staging rejects known production service hosts', () {
      expect(
        () => ServiceEnvironmentPolicy.requireSafeServiceUri(
          environment: ServiceEnvironment.staging,
          uri: Uri.parse('https://api-hn7guzik3q-ew.a.run.app/'),
        ),
        throwsA(isA<ServiceEnvironmentException>()),
      );
    });

    test('staging rejects the production public domain and insecure HTTP', () {
      for (final uri in <Uri>[
        Uri.parse('https://ronikcloud.com/api'),
        Uri.parse('http://staging.example.test/api'),
      ]) {
        expect(
          () => ServiceEnvironmentPolicy.requireSafeServiceUri(
            environment: ServiceEnvironment.staging,
            uri: uri,
          ),
          throwsA(isA<ServiceEnvironmentException>()),
        );
      }
    });

    test('production rejects loopback and embedded URL credentials', () {
      for (final uri in <Uri>[
        Uri.parse('http://127.0.0.1:5001/api'),
        Uri.parse('https://user:password@example.test/api'),
      ]) {
        expect(
          () => ServiceEnvironmentPolicy.requireSafeServiceUri(
            environment: ServiceEnvironment.production,
            uri: uri,
          ),
          throwsA(isA<ServiceEnvironmentException>()),
        );
      }
    });

    test('Firebase callable URLs are centralized by environment', () {
      expect(
        ServiceEnvironmentPolicy.firebaseCallableUri(
          environment: ServiceEnvironment.local,
          projectId: ServiceEnvironmentPolicy.localProjectId,
          functionName: 'ensureEncryptionSetup',
        ),
        Uri.parse(
          'http://127.0.0.1:5001/demo-ronikdrive-local/europe-west1/'
          'ensureEncryptionSetup',
        ),
      );
      expect(
        ServiceEnvironmentPolicy.firebaseCallableUri(
          environment: ServiceEnvironment.production,
          projectId: ServiceEnvironmentPolicy.productionProjectId,
          functionName: 'deleteUserAccount',
        ),
        Uri.parse(
          'https://europe-west1-cloudapp-7dcc2.cloudfunctions.net/'
          'deleteUserAccount',
        ),
      );
      expect(
        () => ServiceEnvironmentPolicy.firebaseCallableUri(
          environment: ServiceEnvironment.staging,
          projectId: ServiceEnvironmentPolicy.productionProjectId,
          functionName: 'deleteUserAccount',
        ),
        throwsA(isA<ServiceEnvironmentException>()),
      );
    });

    test('direct storage credentials require a production-only opt-in', () {
      expect(
        ServiceEnvironmentPolicy.allowsDirectStorageCredentials(
          environment: ServiceEnvironment.local,
          explicitlyAllowed: true,
        ),
        isFalse,
      );
      expect(
        ServiceEnvironmentPolicy.allowsDirectStorageCredentials(
          environment: ServiceEnvironment.staging,
          explicitlyAllowed: true,
        ),
        isFalse,
      );
      expect(
        ServiceEnvironmentPolicy.allowsDirectStorageCredentials(
          environment: ServiceEnvironment.production,
          explicitlyAllowed: false,
        ),
        isFalse,
      );
      expect(
        ServiceEnvironmentPolicy.allowsDirectStorageCredentials(
          environment: ServiceEnvironment.production,
          explicitlyAllowed: true,
        ),
        isTrue,
      );
    });
  });
}
