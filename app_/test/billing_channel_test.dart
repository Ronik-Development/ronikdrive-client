import 'package:cloud_storage/main.dart';
import 'package:cloud_storage/src/billing/billing_channel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'native Android supports signup and paid Play upgrades without Stripe',
    () {
      expect(
        defaultBillingChannel(
          isWeb: false,
          platform: TargetPlatform.android,
          externalCheckoutEnabled: true,
        ),
        BillingChannel.googlePlay,
      );
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(
        const CloudStorageApp().resolvedBillingChannel,
        BillingChannel.googlePlay,
      );
      expect(
        const CloudStorageApp().resolvedBillingChannel.allowsRegistration,
        isTrue,
      );
      expect(
        const CloudStorageApp().resolvedBillingChannel.usesStripe,
        isFalse,
      );
      expect(
        const CloudStorageApp().resolvedBillingChannel.usesGooglePlay,
        isTrue,
      );
      expect(
        const CloudStorageApp(
          billingChannel: BillingChannel.stripe,
        ).resolvedBillingChannel,
        BillingChannel.stripe,
      );
    },
  );

  test(
    'Android web retains browser checkout and the global off switch wins',
    () {
      expect(
        defaultBillingChannel(
          isWeb: true,
          platform: TargetPlatform.android,
          externalCheckoutEnabled: true,
        ),
        BillingChannel.stripe,
      );
      for (final platform in TargetPlatform.values) {
        expect(
          defaultBillingChannel(
            isWeb: false,
            platform: platform,
            externalCheckoutEnabled: false,
          ),
          BillingChannel.disabled,
        );
      }
    },
  );

  test(
    'desktop defaults retain checkout with explicit Apple channel support',
    () {
      for (final platform in [TargetPlatform.windows, TargetPlatform.macOS]) {
        expect(
          defaultBillingChannel(
            isWeb: false,
            platform: platform,
            externalCheckoutEnabled: true,
          ),
          BillingChannel.stripe,
        );
      }
      expect(parseBillingChannel('app_store'), BillingChannel.appStore);
      expect(parseBillingChannel('google_play'), BillingChannel.googlePlay);
      expect(
        parseBillingChannel('unknown', fallback: BillingChannel.disabled),
        BillingChannel.disabled,
      );
    },
  );
}
