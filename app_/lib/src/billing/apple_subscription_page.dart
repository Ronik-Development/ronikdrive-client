import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../authentication/login_password_vault.dart';
import '../shared/app_page_title.dart';
import 'apple_store_purchase_service.dart';

final Uri _privacyUri = Uri.parse('https://ronikcloud.com/privacy');
final Uri _termsUri = Uri.parse('https://ronikcloud.com/terms');
final Uri _appleSubscriptionsUri = Uri.parse(
  'https://apps.apple.com/account/subscriptions',
);
final Uri _appleRefundUri = Uri.parse('https://reportaproblem.apple.com/');

const String _applePaymentDisclosure =
    'Apple handles payment details for App Store purchases; RonikCloud never '
    'receives or stores your full card number or security code. Deleting your '
    'RonikCloud account does not cancel your App Store subscription. Manage or '
    'cancel it with Apple before deleting your account. Refund requests are '
    'handled by Apple.';

class AppleSubscriptionPage extends StatefulWidget {
  const AppleSubscriptionPage({
    super.key,
    required this.auth,
    this.purchaseApi,
  });

  final FirebaseAuth auth;
  final ApplePurchaseApi? purchaseApi;

  @override
  State<AppleSubscriptionPage> createState() => _AppleSubscriptionPageState();
}

class _AppleSubscriptionPageState extends State<AppleSubscriptionPage> {
  late final ApplePurchaseApi _purchaseApi;
  late ApplePurchaseState _state;
  StreamSubscription<ApplePurchaseState>? _stateSubscription;
  String _interval = 'monthly';

  @override
  void initState() {
    super.initState();
    _purchaseApi =
        widget.purchaseApi ?? FirebaseApplePurchaseApi.forApp(widget.auth.app);
    _state = _purchaseApi.currentState;
    _stateSubscription = _purchaseApi.states.listen((state) {
      if (mounted) {
        setState(() => _state = state);
      }
    });
    unawaited(_purchaseApi.initialize());
  }

  @override
  void dispose() {
    unawaited(_stateSubscription?.cancel());
    if (widget.purchaseApi == null) {
      unawaited(_purchaseApi.dispose());
    }
    super.dispose();
  }

  Future<void> _open(Uri uri) async {
    try {
      if (await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      ).timeout(const Duration(seconds: 20))) {
        return;
      }
    } catch (_) {
      // Provider diagnostics may contain private account or device details.
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not open this Apple or support page. Try again.',
          ),
        ),
      );
    }
  }

  Future<void> _signOut() async {
    LoginPasswordVault.instance.clear();
    try {
      await widget.auth.signOut().timeout(const Duration(seconds: 20));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to sign out. Try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final products = _state.products
        .where((product) => product.interval == _interval)
        .toList(growable: false);
    return Scaffold(
      appBar: AppBar(
        title: const Text('RonikCloud Storage'),
        actions: [
          TextButton(onPressed: _signOut, child: const Text('Sign out')),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 36),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Choose encrypted storage for every workspace',
                      style: theme.textTheme.headlineMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'One subscription unlocks both Personal and Business modes. '
                      'Your purchase is billed to your Apple Account.',
                      style: theme.textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment<String>(
                            value: 'monthly',
                            label: Text('Monthly'),
                          ),
                          ButtonSegment<String>(
                            value: 'yearly',
                            label: Text('Yearly'),
                          ),
                        ],
                        selected: <String>{_interval},
                        onSelectionChanged: _state.busy
                            ? null
                            : (selection) {
                                setState(() => _interval = selection.single);
                              },
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (_state.phase == ApplePurchasePhase.loading ||
                        _state.phase == ApplePurchasePhase.idle)
                      const Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (products.isNotEmpty)
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final cardWidth = constraints.maxWidth >= 840
                              ? (constraints.maxWidth - 32) / 3
                              : constraints.maxWidth;
                          return Wrap(
                            spacing: 16,
                            runSpacing: 16,
                            children: products
                                .map(
                                  (product) => SizedBox(
                                    width: cardWidth,
                                    child: _PlanCard(
                                      product: product,
                                      busy: _state.busy,
                                      onPurchase: () =>
                                          _purchaseApi.purchase(product.id),
                                    ),
                                  ),
                                )
                                .toList(growable: false),
                          );
                        },
                      )
                    else
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'No subscriptions are available for this billing period. Try another period or reload subscriptions.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    if (_state.message case final message?)
                      Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: _PurchaseMessage(
                          phase: _state.phase,
                          message: message,
                        ),
                      ),
                    if (_state.phase == ApplePurchasePhase.error ||
                        (products.isEmpty && !_state.busy))
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Center(
                          child: OutlinedButton.icon(
                            onPressed: _state.busy
                                ? null
                                : _purchaseApi.initialize,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Reload subscriptions'),
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed:
                              _state.busy &&
                                  _state.phase != ApplePurchasePhase.pending
                              ? null
                              : _purchaseApi.restorePurchases,
                          icon: const Icon(Icons.restore),
                          label: const Text('Restore Purchases'),
                        ),
                        TextButton(
                          onPressed: () => _open(_appleSubscriptionsUri),
                          child: const Text('Manage Apple subscriptions'),
                        ),
                        TextButton(
                          key: const Key('apple-refund-link'),
                          onPressed: () => _open(_appleRefundUri),
                          child: const Text('Request Apple refund'),
                        ),
                        TextButton(
                          onPressed: () => _open(_termsUri),
                          child: const Text('Terms of Service'),
                        ),
                        TextButton(
                          onPressed: () => _open(_privacyUri),
                          child: const Text('Privacy Policy'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Subscriptions renew automatically unless canceled at least '
                      '24 hours before the end of the current period. Payment is '
                      'charged to your Apple Account after confirmation.\n\n'
                      '$_applePaymentDisclosure',
                      style: theme.textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ).withAppPageTitle('Choose a Storage Plan | RonikCloud');
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.product,
    required this.busy,
    required this.onPurchase,
  });

  final AppleSubscriptionProduct product;
  final bool busy;
  final VoidCallback onPurchase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final descriptionStyle = theme.textTheme.bodyMedium;
    final descriptionLineHeight =
        (descriptionStyle?.fontSize ?? 14) * (descriptionStyle?.height ?? 1);
    final capacity = switch (product.tier) {
      'basic' => '500 GB',
      'pro' => '1 TB',
      'ultra' => '2 TB',
      _ => '',
    };
    final intervalLabel = product.isYearly ? 'per year' : 'per month';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(product.title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(capacity, style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            Text(
              product.localizedPrice,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(intervalLabel, style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: descriptionLineHeight * 2),
              child: Text(product.description, style: descriptionStyle),
            ),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: busy ? null : onPurchase,
              child: Text('Subscribe to ${product.title}'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PurchaseMessage extends StatelessWidget {
  const _PurchaseMessage({required this.phase, required this.message});

  final ApplePurchasePhase phase;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isError = phase == ApplePurchasePhase.error;
    final isComplete =
        phase == ApplePurchasePhase.complete ||
        phase == ApplePurchasePhase.restored;
    final color = isError
        ? colorScheme.errorContainer
        : isComplete
        ? colorScheme.primaryContainer
        : colorScheme.surfaceContainerHighest;
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (phase == ApplePurchasePhase.purchasing ||
                phase == ApplePurchasePhase.restoring ||
                phase == ApplePurchasePhase.verifying) ...[
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
            ],
            Flexible(child: Text(message, textAlign: TextAlign.center)),
          ],
        ),
      ),
    );
  }
}
