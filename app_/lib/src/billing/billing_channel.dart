import 'package:flutter/foundation.dart' show TargetPlatform;

enum BillingChannel { stripe, appStore, googlePlay, disabled }

/// Native Android uses Play purchases; its browser client retains web checkout.
BillingChannel defaultBillingChannel({
  required bool isWeb,
  required TargetPlatform platform,
  required bool externalCheckoutEnabled,
}) {
  if (!externalCheckoutEnabled) {
    return BillingChannel.disabled;
  }
  if (!isWeb && platform == TargetPlatform.android) {
    return BillingChannel.googlePlay;
  }
  return BillingChannel.stripe;
}

extension BillingChannelValue on BillingChannel {
  String get buildValue => switch (this) {
    BillingChannel.stripe => 'stripe',
    BillingChannel.appStore => 'app_store',
    BillingChannel.googlePlay => 'google_play',
    BillingChannel.disabled => 'disabled',
  };

  bool get allowsRegistration => this != BillingChannel.disabled;

  bool get usesStripe => this == BillingChannel.stripe;

  bool get usesAppStore => this == BillingChannel.appStore;

  bool get usesGooglePlay => this == BillingChannel.googlePlay;
}

BillingChannel parseBillingChannel(
  String value, {
  BillingChannel fallback = BillingChannel.stripe,
}) {
  return switch (value.trim().toLowerCase()) {
    'stripe' => BillingChannel.stripe,
    'app_store' || 'appstore' || 'apple' => BillingChannel.appStore,
    'google_play' || 'googleplay' || 'play' => BillingChannel.googlePlay,
    'disabled' || 'none' => BillingChannel.disabled,
    _ => fallback,
  };
}
