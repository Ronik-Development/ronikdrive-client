import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../authentication/login_password_vault.dart';
import '../shared/app_page_title.dart';
import 'google_play_purchase_service.dart';

final Uri _privacyUri = Uri.parse('https://ronikcloud.com/privacy');
final Uri _termsUri = Uri.parse('https://ronikcloud.com/terms');
final Uri _googlePlaySubscriptionsUri = Uri.parse(
  'https://play.google.com/store/account/subscriptions',
);
final Uri _googlePlayRefundUri = Uri.parse(
  'https://support.google.com/googleplay/answer/2479637',
);

const String _googlePlayPaymentDisclosure =
    'Google Play handles payment details for purchases; RonikCloud never '
    'receives or stores your full card number or security code. Deleting your '
    'RonikCloud account does not cancel your Google Play subscription. Manage or '
    'cancel it with Google Play before deleting your account. Refund requests are '
    'handled by Google Play. A Google Play purchase does not cancel a '
    'subscription from another billing provider. Check existing renewals '
    'before you subscribe.';

class GooglePlaySubscriptionPage extends StatefulWidget {
  const GooglePlaySubscriptionPage({
    super.key,
    required this.auth,
    this.purchaseApi,
  });

  final FirebaseAuth auth;
  final GooglePlayPurchaseApi? purchaseApi;

  @override
  State<GooglePlaySubscriptionPage> createState() =>
      _GooglePlaySubscriptionPageState();
}

class _GooglePlaySubscriptionPageState
    extends State<GooglePlaySubscriptionPage> {
  late final GooglePlayPurchaseApi _purchaseApi;
  late GooglePlayPurchaseState _state;
  StreamSubscription<GooglePlayPurchaseState>? _stateSubscription;
  String _interval = 'monthly';

  @override
  void initState() {
    super.initState();
    _purchaseApi =
        widget.purchaseApi ??
        FirebaseGooglePlayPurchaseApi.forApp(widget.auth.app);
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
    var opened = false;
    try {
      opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      ).timeout(const Duration(seconds: 20));
    } catch (_) {}
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This link could not be opened. Try again.'),
        ),
      );
    }
  }

  Future<void> _signOut() async {
    LoginPasswordVault.instance.clear();
    try {
      await widget.auth.signOut();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sign-out could not finish. Try again.'),
          ),
        );
      }
    }
  }

  Future<void> _choosePlan(GooglePlaySubscriptionProduct product) async {
    if (_state.currentProductId != null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Change to ${product.title}?'),
          content: const Text(
            'Your current Google Play subscription will be replaced. '
            'The change takes effect immediately, and Google Play applies '
            'the remaining paid time toward the new plan. '
            'Google Play will show the price and next renewal date before you confirm. '
            'If you choose less storage, keep your usage within the new limit.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep current plan'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continue with Google Play'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    await _purchaseApi.purchase(product.id);
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
                      'Your purchase is billed to your Google Play account.',
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
                    if (_state.phase == GooglePlayPurchasePhase.loading ||
                        _state.phase == GooglePlayPurchasePhase.idle)
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
                                      busy:
                                          _state.busy ||
                                          (_state.hasExistingSubscription &&
                                              _state.currentProductId ==
                                                  null) ||
                                          _state.currentProductId == product.id,
                                      current:
                                          _state.currentProductId == product.id,
                                      replacement:
                                          _state.currentProductId != null,
                                      onPurchase: () => _choosePlan(product),
                                    ),
                                  ),
                                )
                                .toList(growable: false),
                          );
                        },
                      ),
                    if (products.isEmpty && !_state.busy)
                      const Text(
                        'No plans are available for this billing interval. '
                        'Choose another interval or reload subscriptions.',
                        textAlign: TextAlign.center,
                      ),
                    if (_state.message case final message?)
                      Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: _PurchaseMessage(
                          phase: _state.phase,
                          message: message,
                        ),
                      ),
                    if (_state.phase == GooglePlayPurchasePhase.error)
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
                                  _state.phase !=
                                      GooglePlayPurchasePhase.pending
                              ? null
                              : _purchaseApi.restorePurchases,
                          icon: const Icon(Icons.restore),
                          label: const Text('Restore Purchases'),
                        ),
                        TextButton(
                          onPressed: () => _open(_googlePlaySubscriptionsUri),
                          child: const Text('Manage Google Play subscriptions'),
                        ),
                        TextButton(
                          key: const Key('google-play-refund-link'),
                          onPressed: () => _open(_googlePlayRefundUri),
                          child: const Text('Request Google Play refund'),
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
                      'Subscriptions renew automatically unless canceled. '
                      'Manage renewal in Google Play. Payment is '
                      'charged to your Google Play account after confirmation.\n\n'
                      '$_googlePlayPaymentDisclosure',
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
    required this.current,
    required this.replacement,
  });

  final GooglePlaySubscriptionProduct product;
  final bool busy;
  final VoidCallback onPurchase;
  final bool current;
  final bool replacement;

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
              child: Text(
                current
                    ? 'Current plan'
                    : replacement
                    ? 'Change to ${product.title}'
                    : 'Subscribe to ${product.title}',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PurchaseMessage extends StatelessWidget {
  const _PurchaseMessage({required this.phase, required this.message});

  final GooglePlayPurchasePhase phase;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isError = phase == GooglePlayPurchasePhase.error;
    final isComplete =
        phase == GooglePlayPurchasePhase.complete ||
        phase == GooglePlayPurchasePhase.restored;
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
            if (phase == GooglePlayPurchasePhase.restoring ||
                phase == GooglePlayPurchasePhase.purchasing ||
                phase == GooglePlayPurchasePhase.verifying) ...[
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
            ],
            if (phase == GooglePlayPurchasePhase.pending) ...[
              const Icon(Icons.pending_actions),
              const SizedBox(width: 12),
            ],
            Flexible(child: Text(message, textAlign: TextAlign.center)),
          ],
        ),
      ),
    );
  }
}
