import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

enum ServiceEnvironment { local, staging, production }

class ServiceEnvironmentException implements Exception {
  const ServiceEnvironmentException(this.message);

  final String message;

  @override
  String toString() => 'ServiceEnvironmentException: $message';
}

class ServiceEnvironmentPolicy {
  const ServiceEnvironmentPolicy._();

  static const String productionProjectId = 'cloudapp-7dcc2';
  static const String localProjectId = 'demo-ronikdrive-local';

  static ServiceEnvironment resolve({
    required String rawEnvironment,
    required bool isRelease,
  }) {
    switch (rawEnvironment.trim().toLowerCase()) {
      case 'local':
      case 'development':
      case 'dev':
      case 'test':
        return ServiceEnvironment.local;
      case 'staging':
      case 'tester':
      case 'qa':
        return ServiceEnvironment.staging;
      case 'production':
      case 'prod':
        return ServiceEnvironment.production;
      case '':
        if (isRelease) {
          throw const ServiceEnvironmentException(
            'Release builds must explicitly set '
            'RONIKDRIVE_SERVICE_ENVIRONMENT to staging or production.',
          );
        }
        return ServiceEnvironment.local;
      default:
        throw ServiceEnvironmentException(
          'Unknown RONIKDRIVE_SERVICE_ENVIRONMENT "$rawEnvironment".',
        );
    }
  }

  static void validateFirebaseProject({
    required ServiceEnvironment environment,
    required String projectId,
  }) {
    final normalized = projectId.trim().toLowerCase();
    if (normalized.isEmpty) {
      throw const ServiceEnvironmentException(
        'A Firebase project ID is required.',
      );
    }
    if (environment == ServiceEnvironment.production) {
      if (normalized != productionProjectId) {
        throw ServiceEnvironmentException(
          'Production builds must target $productionProjectId, not $projectId.',
        );
      }
      return;
    }
    if (normalized == productionProjectId) {
      throw ServiceEnvironmentException(
        '${environment.name} builds may not target the production Firebase project.',
      );
    }
    if (environment == ServiceEnvironment.staging &&
        !RegExp(
          r'(^|[-_.])(staging|stage|test|qa)([-_.]|$)',
        ).hasMatch(normalized)) {
      throw const ServiceEnvironmentException(
        'Staging Firebase project IDs must contain a staging/test/qa marker.',
      );
    }
    if (environment == ServiceEnvironment.local &&
        !normalized.startsWith('demo-')) {
      throw ServiceEnvironmentException(
        'Local builds must use a Firebase demo project so accidental deploys cannot create live resources.',
      );
    }
  }

  static Uri requireSafeServiceUri({
    required ServiceEnvironment environment,
    required Uri uri,
  }) {
    final host = uri.host.trim().toLowerCase();
    final isLoopback =
        host == 'localhost' || host == '127.0.0.1' || host == '::1';
    final isHttp = uri.isScheme('http');
    final isHttps = uri.isScheme('https');
    if (host.isEmpty || (!isHttp && !isHttps) || uri.userInfo.isNotEmpty) {
      throw ServiceEnvironmentException(
        'Service URLs must be absolute HTTP(S) URLs without embedded credentials: $uri.',
      );
    }
    if (isHttp && !isLoopback) {
      throw ServiceEnvironmentException(
        'Plain HTTP is allowed only for loopback services, not $uri.',
      );
    }
    if (environment == ServiceEnvironment.local && !isLoopback) {
      throw ServiceEnvironmentException(
        'Local builds may call only loopback service URLs, not $uri.',
      );
    }
    if (environment != ServiceEnvironment.production &&
        (host.contains(productionProjectId) ||
            host == 'api-hn7guzik3q-ew.a.run.app' ||
            host == 'ronikcloud.com' ||
            host.endsWith('.ronikcloud.com'))) {
      throw ServiceEnvironmentException(
        '${environment.name} builds may not call the production service URL $uri.',
      );
    }
    if (environment == ServiceEnvironment.staging && isLoopback) {
      throw ServiceEnvironmentException(
        'Staging builds require a deployed staging URL, not $uri.',
      );
    }
    if (environment == ServiceEnvironment.production && isLoopback) {
      throw ServiceEnvironmentException(
        'Production builds may not call loopback service URLs: $uri.',
      );
    }
    return uri;
  }

  static Uri firebaseCallableUri({
    required ServiceEnvironment environment,
    required String projectId,
    required String functionName,
    String region = 'europe-west1',
  }) {
    final normalizedRegion = region.trim().toLowerCase();
    final normalizedFunction = functionName.trim();
    if (!RegExp(r'^[a-z0-9-]+$').hasMatch(normalizedRegion)) {
      throw ServiceEnvironmentException('Invalid Firebase region "$region".');
    }
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(normalizedFunction)) {
      throw ServiceEnvironmentException(
        'Invalid Firebase function name "$functionName".',
      );
    }
    final normalizedProjectId = projectId.trim().toLowerCase();
    validateFirebaseProject(
      environment: environment,
      projectId: normalizedProjectId,
    );
    final uri = environment == ServiceEnvironment.local
        ? Uri.parse(
            'http://127.0.0.1:5001/$normalizedProjectId/'
            '$normalizedRegion/$normalizedFunction',
          )
        : Uri.parse(
            'https://$normalizedRegion-$normalizedProjectId.cloudfunctions.net/'
            '$normalizedFunction',
          );
    return requireSafeServiceUri(environment: environment, uri: uri);
  }

  static bool allowsDirectStorageCredentials({
    required ServiceEnvironment environment,
    required bool explicitlyAllowed,
  }) => environment == ServiceEnvironment.production && explicitlyAllowed;
}

class ServiceEnvironmentConfig {
  const ServiceEnvironmentConfig._();

  static const String _rawEnvironment = String.fromEnvironment(
    'RONIKDRIVE_SERVICE_ENVIRONMENT',
  );
  static const String _firebaseProjectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
  );
  static const String _firebaseApiKey = String.fromEnvironment(
    'FIREBASE_API_KEY',
  );
  static const String _firebaseAppId = String.fromEnvironment(
    'FIREBASE_APP_ID',
  );
  static const String _firebaseMessagingSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  );
  static const String _firebaseAuthDomain = String.fromEnvironment(
    'FIREBASE_AUTH_DOMAIN',
  );
  static const String _firebaseStorageBucket = String.fromEnvironment(
    'FIREBASE_STORAGE_BUCKET',
  );
  static const String _firebaseMeasurementId = String.fromEnvironment(
    'FIREBASE_MEASUREMENT_ID',
  );

  static ServiceEnvironment get current => ServiceEnvironmentPolicy.resolve(
    rawEnvironment: _rawEnvironment,
    isRelease: kReleaseMode,
  );

  static bool get usesLocalEmulators => current == ServiceEnvironment.local;

  static String get firebaseProjectId {
    switch (current) {
      case ServiceEnvironment.local:
        return ServiceEnvironmentPolicy.localProjectId;
      case ServiceEnvironment.production:
        return ServiceEnvironmentPolicy.productionProjectId;
      case ServiceEnvironment.staging:
        final value = _firebaseProjectId.trim();
        ServiceEnvironmentPolicy.validateFirebaseProject(
          environment: current,
          projectId: value,
        );
        return value;
    }
  }

  static FirebaseOptions firebaseOptions(FirebaseOptions productionDefaults) {
    final environment = current;
    if (environment == ServiceEnvironment.production) {
      ServiceEnvironmentPolicy.validateFirebaseProject(
        environment: environment,
        projectId: productionDefaults.projectId,
      );
      return productionDefaults;
    }

    if (environment == ServiceEnvironment.local) {
      return const FirebaseOptions(
        // Firebase Auth Web validates the API-key shape before contacting the
        // emulator. This is a non-secret, syntactically valid dummy key.
        apiKey: 'AIzaSyAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
        appId: '1:000000000000:web:ronikdrivelocal',
        messagingSenderId: '000000000000',
        projectId: ServiceEnvironmentPolicy.localProjectId,
        authDomain: 'localhost',
        storageBucket: 'demo-ronikdrive-local.appspot.com',
      );
    }

    final projectId = firebaseProjectId;
    final apiKey = _firebaseApiKey.trim();
    final appId = _firebaseAppId.trim();
    final senderId = _firebaseMessagingSenderId.trim();
    if (apiKey.isEmpty || appId.isEmpty || senderId.isEmpty) {
      throw const ServiceEnvironmentException(
        'Staging builds require FIREBASE_API_KEY, FIREBASE_APP_ID, '
        'FIREBASE_MESSAGING_SENDER_ID, and FIREBASE_PROJECT_ID.',
      );
    }
    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: senderId,
      projectId: projectId,
      authDomain: _firebaseAuthDomain.trim().isEmpty
          ? '$projectId.firebaseapp.com'
          : _firebaseAuthDomain.trim(),
      storageBucket: _firebaseStorageBucket.trim().isEmpty
          ? '$projectId.firebasestorage.app'
          : _firebaseStorageBucket.trim(),
      measurementId: _firebaseMeasurementId.trim().isEmpty
          ? null
          : _firebaseMeasurementId.trim(),
      iosBundleId: productionDefaults.iosBundleId,
    );
  }

  static Uri guardServiceUri(Uri uri) =>
      ServiceEnvironmentPolicy.requireSafeServiceUri(
        environment: current,
        uri: uri,
      );

  static Uri firebaseCallableUri({
    required String functionName,
    String? projectId,
    String region = 'europe-west1',
  }) => ServiceEnvironmentPolicy.firebaseCallableUri(
    environment: current,
    projectId: projectId?.trim().isNotEmpty == true
        ? projectId!.trim()
        : firebaseProjectId,
    functionName: functionName,
    region: region,
  );
}
