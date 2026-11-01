import 'package:flutter/material.dart';

import 'business_operations_service.dart';

class BusinessServiceAgreementPage extends StatefulWidget {
  const BusinessServiceAgreementPage({super.key, required this.service});
  final BusinessOperationsService service;

  @override
  State<BusinessServiceAgreementPage> createState() =>
      _BusinessServiceAgreementPageState();
}

class _BusinessServiceAgreementPageState
    extends State<BusinessServiceAgreementPage> {
  Map<String, dynamic>? _terms;
  bool _accepted = false;
  bool _authorized = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final terms = await widget.service.call('getBusinessServiceTerms');
      if (terms['termsHash'] is! String ||
          terms['clauses'] is! List ||
          terms['version'] is! String) {
        throw const BusinessOperationsException();
      }
      if (mounted) {
        setState(() {
          _terms = terms;
          _accepted = false;
          _authorized = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'The Business agreement could not be loaded. Retry before accepting.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _accept() async {
    if (_busy || !_accepted || !_authorized || _terms == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.service
          .call('acceptBusinessServiceAgreement', {
            'termsHash': _terms!['termsHash'],
            'accepted': true,
            'authorizedRepresentative': true,
          });
      if (result['accepted'] != true ||
          result['termsHash'] != _terms!['termsHash']) {
        throw const BusinessOperationsException();
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Acceptance could not be confirmed. Retry uses the same agreement version safely.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Business service agreement')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Review your Business service terms',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            const Text(
              'Minimum USD 6 per month. Above the minimum, total price is attributable service cost divided by 0.50. This is a 50% gross margin, not a 50% markup. Taxes are separate.',
            ),
            const SizedBox(height: 12),
            const Text(
              'The eight-hour human-response guarantee applies after the provider activates contracted 24/7 coverage. A missed contracted deadline opens a provider compensation obligation and review. This agreement does not invent a compensation amount or promise universal file recovery.',
            ),
            if (_busy && _terms == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!),
              if (_terms == null)
                TextButton(
                  onPressed: _busy ? null : _load,
                  child: const Text('Retry agreement'),
                ),
            ],
            if (_terms != null) ...[
              const SizedBox(height: 20),
              Text(
                'Version ${_terms!['version']}',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              for (final clause
                  in (_terms!['clauses'] as List).whereType<String>())
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: SelectableText(clause),
                ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _authorized,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _authorized = value ?? false),
                title: const Text(
                  'I am authorized to enter this agreement on behalf of the business.',
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _accepted,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _accepted = value ?? false),
                title: const Text(
                  'I accept this Business service agreement, including dynamic pricing and the support and compensation clauses.',
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: !_busy && _accepted && _authorized ? _accept : null,
                child: Text(
                  _busy
                      ? 'Recording acceptance…'
                      : 'Accept Business service agreement',
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
