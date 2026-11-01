import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../billing/web_checkout_launcher_stub.dart'
    if (dart.library.html) '../billing/web_checkout_launcher_html.dart'
    as web_checkout;
import 'business_operations_service.dart';

bool get businessExternalPaymentsAllowed =>
    kIsWeb ||
    (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS);

class BusinessBillingPage extends StatefulWidget {
  const BusinessBillingPage({
    super.key,
    required this.service,
    this.onChanged,
    this.openUrl,
    this.embedded = false,
    this.allowExternalPayments = true,
    this.readOnlySample = false,
  });
  final BusinessOperationsService service;
  final VoidCallback? onChanged;
  final Future<bool> Function(Uri)? openUrl;
  final bool embedded;
  final bool allowExternalPayments;
  final bool readOnlySample;
  @override
  State<BusinessBillingPage> createState() => _BusinessBillingPageState();
}

class _BusinessBillingPageState extends State<BusinessBillingPage> {
  Map<String, dynamic>? _state;
  String? _error;
  bool _loading = true;
  bool _busy = false;
  bool _acceptSchedule = false;
  bool _authorizeCharges = false;
  String _requestId = BusinessOperationsService.newRequestId();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.service.call('getBusinessBillingState');
      if (!mounted) return;
      setState(() {
        if (_state?['offer']?['offerHash'] != result['offer']?['offerHash']) {
          _acceptSchedule = false;
          _authorizeCharges = false;
        }
        _state = result;
        if (result['setupExpired'] == true) {
          _requestId = BusinessOperationsService.newRequestId();
        }
        if (result['setupRequestId'] is String) {
          _requestId = result['setupRequestId'] as String;
        }
      });
      if (result['status'] == 'active') widget.onChanged?.call();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Billing status could not be confirmed. Refresh before retrying a payment setup.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy || _loading) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'The billing request could not be confirmed. Refresh status before retrying. An existing Personal subscription must end before company billing can start.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(String? value) async {
    final uri = Uri.tryParse(value ?? '');
    if (uri == null ||
        uri.scheme != 'https' ||
        ![
          'checkout.stripe.com',
          'billing.stripe.com',
          'invoice.stripe.com',
          'pay.stripe.com',
        ].contains(uri.host) ||
        uri.userInfo.isNotEmpty) {
      throw const BusinessOperationsException();
    }
    final launcher = widget.openUrl;
    final opened = launcher != null
        ? await launcher(uri)
        : kIsWeb
        ? await web_checkout.launchCheckoutInWeb(uri)
        : await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) throw const BusinessOperationsException();
  }

  Future<void> _cancel() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stop future Business billing?'),
        content: const Text(
          'Service ends at the next UTC calendar month. The final month is not prorated. Approved charges for service already delivered remain due. Files are not deleted by this action.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep service'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel at month end'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    await _run(() async {
      await widget.service.call('cancelBusinessAutomaticBilling');
      await _load();
      widget.onChanged?.call();
    });
  }

  String _money(Object? cents) => cents is num
      ? 'USD ${(cents / 100).toStringAsFixed(2)}'
      : 'Not yet calculated';
  String _status(Object? value) => switch (value) {
    'active' => 'Automatic billing active',
    'pending_setup' => 'Payment setup awaiting confirmation',
    'setup_expired' => 'Payment setup expired — start again',
    'cancel_at_period_end' => 'Cancellation scheduled',
    'cancelled' => 'Service cancelled',
    'paid' => 'Paid',
    'open' => 'Awaiting automatic collection',
    'payment_action_required' => 'Payment needs attention',
    'held_missing_approved_cost' => 'Waiting for approved cost evidence',
    'held_provider_reconciliation_required' =>
      'Provider reconciliation required',
    'retry_required' => 'Provider is checking invoice status',
    'void' => 'Voided — contact support',
    'uncollectible' => 'Unpaid — contact support',
    _ => 'Billing is not active',
  };

  @override
  Widget build(BuildContext context) {
    final offer = _state?['offer'] as Map?;
    final status = _state?['status'];
    final maySetup =
        _state?['isOwner'] == true &&
        _state?['personalBillingConflict'] != true &&
        offer != null &&
        [
          null,
          'not_configured',
          'pending_setup',
          'setup_expired',
        ].contains(status);
    final mayPay =
        !widget.readOnlySample &&
        widget.allowExternalPayments &&
        businessExternalPaymentsAllowed;
    final body = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (widget.readOnlySample)
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Text(
                  'Read-only fictional billing example. No payment setup, invoice or charge is created. Tax amounts in this example are illustrative.',
                ),
              ),
            Text(
              'Business billing',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 12),
            const Text(
              'One company bill. Monthly service subtotal = max(USD 6.00, approved attributable cost ÷ 0.50), rounded upward to a cent. USD 10 of cost means USD 20 total before tax. The USD 6 minimum is not added again.',
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _status(status),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh billing status',
                  onPressed: _busy || _loading ? null : _load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_state?['isOwner'] == false)
              const Text(
                'Your company owner manages payment setup and invoices. Ask them to activate company billing.',
              ),
            if (_state?['personalBillingConflict'] == true)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'An existing Personal subscription must finish cancellation before company billing can start. Manage that subscription from your Personal workspace; company billing does not cancel it for you.',
                ),
              ),
            if (_state?['isOwner'] == true && offer == null)
              const Text(
                'Your provider must publish the cost schedule and agreed storage capacity before payment setup. Contact Business support to finish your service order.',
              ),
            if (offer != null) ...[
              const Divider(height: 40),
              Text(
                'Your disclosed cost schedule',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(offer['costScheduleText'] as String? ?? ''),
              const SizedBox(height: 12),
              Text(
                'Schedule: ${offer['costScheduleReference']} · Per-member capacity: ${((offer['capacityBytesPerMember'] as num) / 1073741824).toStringAsFixed(1)} GiB',
              ),
              const SizedBox(height: 20),
              Text(
                'Automatic payment authorization',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(offer['collectionTerms'] as String? ?? ''),
              const SizedBox(height: 12),
              const Text(
                'Stripe handles your card details. RonikCloud stores provider references, your authorization, cost evidence and invoice status; it does not receive your card number or CVC.',
              ),
            ],
            if (!mayPay && !widget.readOnlySample)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Automatic Business payment setup is available in the web or supported desktop client. This client does not open external payment setup.',
                ),
              ),
            if (maySetup && mayPay) ...[
              const SizedBox(height: 16),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _acceptSchedule,
                onChanged: _busy || _loading
                    ? null
                    : (v) => setState(() => _acceptSchedule = v == true),
                title: const Text(
                  'I am authorized to bind this business and accept this cost schedule, capacity, billing periods and cancellation terms.',
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _authorizeCharges,
                onChanged: _busy || _loading
                    ? null
                    : (v) => setState(() => _authorizeCharges = v == true),
                title: const Text(
                  'I authorize Stripe to save a payment method and RonikCloud to charge the variable monthly invoices automatically, including applicable taxes.',
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed:
                    _busy || _loading || !_acceptSchedule || !_authorizeCharges
                    ? null
                    : () => _run(() async {
                        final result = await widget.service
                            .call('createBusinessBillingSetup', {
                              'requestId': _requestId,
                              'offerHash': offer['offerHash'],
                              'accepted': true,
                              'authorizeAutomaticCharges': true,
                            });
                        await _open(result['url'] as String?);
                      }),
                child: Text(
                  status == 'pending_setup'
                      ? 'Continue secure payment setup'
                      : 'Set up automatic billing with Stripe',
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'No charge is collected during card setup. After returning from Stripe, refresh billing status. Existing Personal subscriptions are not cancelled for you; finish their cancellation before enabling company billing.',
              ),
            ],
            if (['active', 'cancel_at_period_end'].contains(status) &&
                mayPay) ...[
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: _busy || _loading
                    ? null
                    : () => _run(() async {
                        final response = await widget.service.call(
                          'createBusinessBillingPortal',
                        );
                        await _open(response['url'] as String?);
                      }),
                child: const Text('Manage payment method with Stripe'),
              ),
              if (status == 'active')
                TextButton(
                  onPressed: _busy || _loading ? null : _cancel,
                  child: const Text('Cancel future Business service'),
                ),
            ],
            if (_state?['serviceEndAt'] != null)
              Text(
                'Service ends: ${_state!['serviceEndAt']} (UTC). Final accrued charges remain due.',
              ),
            const Divider(height: 40),
            Text(
              'Recent monthly invoices (up to 24)',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            const Text(
              'Invoices are created after the UTC service month closes and its documented costs are approved. Missing cost evidence holds billing for review; it is not treated as zero cost.',
            ),
            for (final invoice in (_state?['invoices'] as List? ?? const []))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${invoice['period']} · ${_status(invoice['status'])}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      'Service: ${_money(invoice['serviceSubtotalCents'])} · Total including tax: ${_money(invoice['totalCents'])}',
                    ),
                    if (invoice['costUsdMicros'] is num)
                      Text(
                        'Approved cost: USD ${((invoice['costUsdMicros'] as num) / 1000000).toStringAsFixed(6)}',
                      ),
                    if (invoice['url'] != null && mayPay)
                      TextButton(
                        onPressed: _busy || _loading
                            ? null
                            : () => _run(() => _open(invoice['url'] as String)),
                        child: const Text(
                          'Open Stripe invoice or complete payment',
                        ),
                      ),
                  ],
                ),
              ),
            if ((_state?['invoices'] as List? ?? const []).isEmpty && !_loading)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Text('No invoices yet.'),
              ),
          ],
        ),
      ),
    );
    return widget.embedded
        ? body
        : Scaffold(
            appBar: AppBar(title: const Text('Business billing')),
            body: body,
          );
  }
}
