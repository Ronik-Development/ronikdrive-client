import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../shared/app_page_title.dart';
import 'apple_subscription_page.dart';
import 'google_play_subscription_page.dart';
import 'google_play_purchase_service.dart';
import 'billing_channel.dart';
import 'subscription_coordinator.dart';
import 'subscription_gate.dart';

/// An in-workspace upgrade must observe server confirmation, not a checkout URL.
class StorageUpgradePage extends StatefulWidget {
  const StorageUpgradePage({
    super.key,
    required this.auth,
    required this.user,
    required this.coordinator,
    required this.billingChannel,
    required this.initialSubscription,
    this.googlePlayPurchaseApi,
  });

  final FirebaseAuth auth;
  final User user;
  final SubscriptionCoordinator coordinator;
  final BillingChannel billingChannel;
  final SubscriptionState initialSubscription;
  final GooglePlayPurchaseApi? googlePlayPurchaseApi;

  @override
  State<StorageUpgradePage> createState() => _StorageUpgradePageState();
}

class _StorageUpgradePageState extends State<StorageUpgradePage> {
  late Stream<SubscriptionState> _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = widget.coordinator.watchSubscription(widget.user.uid);
  }

  @override
  void didUpdateWidget(covariant StorageUpgradePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coordinator != widget.coordinator ||
        oldWidget.user.uid != widget.user.uid) {
      _subscription = widget.coordinator.watchSubscription(widget.user.uid);
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<SubscriptionState>(
    stream: _subscription,
    initialData: widget.initialSubscription,
    builder: (context, snapshot) {
      final subscription = snapshot.data ?? widget.initialSubscription;
      if (snapshot.hasError || subscription.isPaid) {
        return Scaffold(
          appBar: AppBar(title: const Text('Storage plan')),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    snapshot.hasError
                        ? 'We could not confirm your plan yet. Return to your files and check again before retrying payment.'
                        : 'Your storage upgrade is active. Your files and encryption settings are unchanged.',
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () {
                      if (!snapshot.hasError && subscription.isPaid) {
                        paymentProcessingNotifier.value = false;
                      }
                      Navigator.of(context).pop();
                    },
                    child: const Text('Back to files'),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      return widget.billingChannel.usesAppStore
          ? AppleSubscriptionPage(auth: widget.auth)
          : widget.billingChannel.usesGooglePlay
          ? GooglePlaySubscriptionPage(
              key: ValueKey('play-upgrade-${widget.user.uid}'),
              auth: widget.auth,
              purchaseApi: widget.googlePlayPurchaseApi,
            )
          : SubscriptionPaywallPage(
              auth: widget.auth,
              user: widget.user,
              subscription: subscription,
              coordinator: widget.coordinator,
              externalCheckoutEnabled: widget.billingChannel.usesStripe,
            );
    },
  ).withAppPageTitle('Storage Plan | RonikCloud');
}
