import 'package:flutter/foundation.dart';

import 'service_environment.dart';

const String _envWebBaseUrl = String.fromEnvironment('RONIKDRIVE_WEB_BASE_URL');
const String _envRedirectUrl = String.fromEnvironment(
  'RONIKDRIVE_REDIRECT_URL',
);
const String _envEmbeddedCheckoutPageUrl = String.fromEnvironment(
  'STRIPE_EMBEDDED_CHECKOUT_PAGE_URL',
);
const String _envCheckoutApiBaseUrl = String.fromEnvironment(
  'STRIPE_CHECKOUT_API_BASE_URL',
);
const String _envPortalSessionRestUrl = String.fromEnvironment(
  'STRIPE_PORTAL_SESSION_REST_URL',
);
const String _envChangeSubscriptionTierRestUrl = String.fromEnvironment(
  'STRIPE_CHANGE_SUBSCRIPTION_TIER_REST_URL',
);
const String _envCancelSubscriptionRestUrl = String.fromEnvironment(
  'STRIPE_CANCEL_SUBSCRIPTION_REST_URL',
);
const String _envDeleteAccountRestUrl = String.fromEnvironment(
  'DELETE_ACCOUNT_REST_URL',
);
const String _envDownloadApiBaseUrl = String.fromEnvironment(
  'DOWNLOAD_API_BASE_URL',
);

class ReleaseRuntimeConfig {
  ReleaseRuntimeConfig._();

  static const String productionWebProjectId =
      ServiceEnvironmentPolicy.productionProjectId;
  static String get defaultWebProjectId =>
      ServiceEnvironmentConfig.firebaseProjectId;
  static const String defaultNativeCancelUrl = 'ronikdrive://payment-cancel';
  static const String defaultCheckoutApiBaseUrl =
      'https://api-hn7guzik3q-ew.a.run.app/';
  static const String defaultPortalSessionRestUrl =
      'https://createportalsession-hn7guzik3q-ew.a.run.app';
  static const String defaultChangeSubscriptionTierRestUrl =
      'https://changesubscriptiontier-hn7guzik3q-ew.a.run.app';
  static const String defaultCancelSubscriptionRestUrl =
      'https://cancelsubscription-hn7guzik3q-ew.a.run.app';
  static const String defaultDeleteAccountRestUrl =
      'https://deleteuseraccount-hn7guzik3q-ew.a.run.app';

  static Uri resolveCheckoutApiBaseUri() => _resolveServiceUri(
    configuredValue: _envCheckoutApiBaseUrl,
    configuredName: 'STRIPE_CHECKOUT_API_BASE_URL',
    productionDefault: defaultCheckoutApiBaseUrl,
    localFunctionName: 'api',
    normalizeAsDirectory: true,
  );

  static Uri resolveDownloadApiBaseUri() => _resolveServiceUri(
    configuredValue: _envDownloadApiBaseUrl,
    configuredName: 'DOWNLOAD_API_BASE_URL',
    productionDefault: defaultCheckoutApiBaseUrl,
    localFunctionName: 'api',
    normalizeAsDirectory: true,
  );

  static Uri resolvePortalSessionRestUri() => _resolveServiceUri(
    configuredValue: _envPortalSessionRestUrl,
    configuredName: 'STRIPE_PORTAL_SESSION_REST_URL',
    productionDefault: defaultPortalSessionRestUrl,
    localFunctionName: 'createPortalSession',
  );

  static Uri resolveChangeSubscriptionTierRestUri() => _resolveServiceUri(
    configuredValue: _envChangeSubscriptionTierRestUrl,
    configuredName: 'STRIPE_CHANGE_SUBSCRIPTION_TIER_REST_URL',
    productionDefault: defaultChangeSubscriptionTierRestUrl,
    localFunctionName: 'changeSubscriptionTier',
  );

  static Uri resolveCancelSubscriptionRestUri() => _resolveServiceUri(
    configuredValue: _envCancelSubscriptionRestUrl,
    configuredName: 'STRIPE_CANCEL_SUBSCRIPTION_REST_URL',
    productionDefault: defaultCancelSubscriptionRestUrl,
    localFunctionName: 'cancelSubscription',
  );

  static Uri resolveDeleteAccountRestUri() => _resolveServiceUri(
    configuredValue: _envDeleteAccountRestUrl,
    configuredName: 'DELETE_ACCOUNT_REST_URL',
    productionDefault: defaultDeleteAccountRestUrl,
    localFunctionName: 'deleteUserAccount',
  );

  static Uri resolveWebAppBaseUri({required String projectId}) {
    final configured = _configuredHttpUri(
      _envWebBaseUrl,
      variableName: 'RONIKDRIVE_WEB_BASE_URL',
    );
    if (configured != null) {
      return _normalizeDirectoryUri(
        ServiceEnvironmentConfig.guardServiceUri(configured),
      );
    }

    if (kIsWeb) {
      final runtimeOrigin = _currentOriginUri();
      if (runtimeOrigin != null) {
        return ServiceEnvironmentConfig.guardServiceUri(runtimeOrigin);
      }
    }

    final environment = ServiceEnvironmentConfig.current;
    if (environment == ServiceEnvironment.local) {
      return Uri.parse('http://127.0.0.1:5000/');
    }
    if (environment == ServiceEnvironment.staging) {
      throw const ServiceEnvironmentException(
        'Staging builds require RONIKDRIVE_WEB_BASE_URL.',
      );
    }
    final effectiveProjectId = projectId.trim().isEmpty
        ? productionWebProjectId
        : projectId.trim();
    ServiceEnvironmentPolicy.validateFirebaseProject(
      environment: environment,
      projectId: effectiveProjectId,
    );
    return Uri.parse('https://$effectiveProjectId.web.app/');
  }

  static Uri resolveRedirectUri({required String projectId}) {
    final configured = _configuredHttpUri(
      _envRedirectUrl,
      variableName: 'RONIKDRIVE_REDIRECT_URL',
    );
    if (configured != null) {
      return ServiceEnvironmentConfig.guardServiceUri(configured);
    }

    if (kIsWeb) {
      final runtimeOrigin = _currentOriginUri();
      if (runtimeOrigin != null) {
        return ServiceEnvironmentConfig.guardServiceUri(
          runtimeOrigin.resolve('redirect.html'),
        );
      }
    }

    return resolveWebAppBaseUri(projectId: projectId).resolve('redirect.html');
  }

  static Uri resolvePaymentSuccessUri({required String projectId}) {
    return resolveWebAppBaseUri(
      projectId: projectId,
    ).resolve('payment-success');
  }

  static Uri resolveEmbeddedCheckoutPageUri({required String projectId}) {
    final configured = _configuredHttpUri(
      _envEmbeddedCheckoutPageUrl,
      variableName: 'STRIPE_EMBEDDED_CHECKOUT_PAGE_URL',
    );
    if (configured != null) {
      return ServiceEnvironmentConfig.guardServiceUri(configured);
    }
    return resolveWebAppBaseUri(
      projectId: projectId,
    ).resolve('stripe_embedded_checkout.html');
  }

  static Uri? _currentOriginUri() {
    final runtimeUri = Uri.tryParse(Uri.base.toString());
    if (runtimeUri == null ||
        !runtimeUri.hasScheme ||
        (!runtimeUri.isScheme('https') && !runtimeUri.isScheme('http'))) {
      return null;
    }
    return Uri(
      scheme: runtimeUri.scheme,
      host: runtimeUri.host,
      port: runtimeUri.hasPort ? runtimeUri.port : null,
      path: '/',
    );
  }

  static Uri? _configuredHttpUri(String value, {required String variableName}) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final parsed = Uri.tryParse(trimmed);
    if (parsed == null || !parsed.hasScheme) {
      throw ServiceEnvironmentException(
        '$variableName must be an absolute HTTP(S) URL.',
      );
    }
    if (parsed.isScheme('http') && _isAllowedInsecureHttpHost(parsed.host)) {
      return parsed;
    }
    if (!parsed.isScheme('https')) {
      throw ServiceEnvironmentException(
        '$variableName must use HTTPS, except for a loopback emulator URL.',
      );
    }
    return parsed;
  }

  static Uri _resolveServiceUri({
    required String configuredValue,
    required String configuredName,
    required String productionDefault,
    required String localFunctionName,
    bool normalizeAsDirectory = false,
  }) {
    final configured = _configuredHttpUri(
      configuredValue,
      variableName: configuredName,
    );
    if (configured != null) {
      final guarded = ServiceEnvironmentConfig.guardServiceUri(configured);
      return normalizeAsDirectory ? _normalizeDirectoryUri(guarded) : guarded;
    }

    switch (ServiceEnvironmentConfig.current) {
      case ServiceEnvironment.local:
        final uri = Uri.parse(
          'http://127.0.0.1:5001/'
          '${ServiceEnvironmentPolicy.localProjectId}/europe-west1/'
          '$localFunctionName',
        );
        return normalizeAsDirectory ? _normalizeDirectoryUri(uri) : uri;
      case ServiceEnvironment.staging:
        throw ServiceEnvironmentException(
          'Staging builds require an explicit URL for $localFunctionName.',
        );
      case ServiceEnvironment.production:
        final guarded = ServiceEnvironmentConfig.guardServiceUri(
          Uri.parse(productionDefault),
        );
        return normalizeAsDirectory ? _normalizeDirectoryUri(guarded) : guarded;
    }
  }

  static Uri resolveCallableRestUri({
    required String functionName,
    String? projectId,
    String region = 'europe-west1',
  }) => ServiceEnvironmentConfig.firebaseCallableUri(
    functionName: functionName,
    projectId: projectId,
    region: region,
  );

  static bool _isAllowedInsecureHttpHost(String host) {
    final normalized = host.trim().toLowerCase();
    return normalized == 'localhost' ||
        normalized == '127.0.0.1' ||
        normalized == '::1';
  }

  static Uri _normalizeDirectoryUri(Uri uri) {
    if (uri.path.isEmpty || uri.path.endsWith('/')) {
      return uri;
    }
    return uri.replace(path: '${uri.path}/');
  }
}
