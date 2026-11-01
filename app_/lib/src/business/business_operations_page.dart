import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../support/support_report_privacy.dart';
import 'business_operations_service.dart';
import 'business_service_agreement_page.dart';
import 'business_billing_page.dart';

class BusinessOperationsPage extends StatefulWidget {
  const BusinessOperationsPage({
    super.key,
    required this.service,
    this.verifyFile,
    this.resolveFileName,
    this.sample = false,
  });
  final BusinessOperationsService service;
  final Future<bool> Function(String fileId)? verifyFile;
  final Future<String?> Function(String fileId)? resolveFileName;
  final bool sample;

  @override
  State<BusinessOperationsPage> createState() => _BusinessOperationsPageState();
}

class _BusinessOperationsPageState extends State<BusinessOperationsPage> {
  final _description = TextEditingController();
  final _period = TextEditingController(
    text:
        '${DateTime.now().toUtc().year}-${DateTime.now().toUtc().month.toString().padLeft(2, '0')}',
  );
  String _kind = 'support';
  String _priority = 'normal';
  bool _consent = false;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String _requestId = BusinessOperationsService.newRequestId();
  Map<String, dynamic>? _state;
  Map<String, dynamic>? _quote;
  List<Map<String, dynamic>> _tickets = [];
  List<Map<String, dynamic>> _files = [];
  List<Map<String, dynamic>> _operations = [];
  String? _next;
  bool _truncated = false;
  final Map<String, String> _revealedNames = {};
  final Set<String> _revealing = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _description.dispose();
    _period.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _items(Object? value) => value is List
      ? value
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList()
      : [];

  Future<void> _load({bool next = false}) async {
    if (_busy) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.service.call('getBusinessOperationsState'),
        widget.service.call('listBusinessSupportTickets'),
        widget.service.call('listBusinessRecoveryFiles', {
          if (next && _next != null) 'after': _next,
        }),
        widget.service.call('listBusinessRecoveryOperations'),
      ]);
      if (!mounted) return;
      setState(() {
        _state = results[0];
        _revealedNames.clear();
        _tickets = _items(results[1]['tickets']);
        _truncated = results[1]['truncated'] == true;
        _files = next
            ? [..._files, ..._items(results[2]['files'])]
            : _items(results[2]['files']);
        _next = results[2]['next'] as String?;
        _operations = _items(results[3]['operations']);
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Support and recovery status could not be refreshed. Keep the last known view and retry; do not assume a request failed.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy || _loading || widget.sample) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(() => _error = const BusinessOperationsException().message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (!_consent || _description.text.trim().isEmpty) return;
    final protectedDescription = redactSupportReportText(
      _description.text.trim(),
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Review support ticket'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Only this filtered text is sent to support and your company administrators. Filtering cannot recognize every secret; review it before sending. No files, keys or logs are attached.',
              ),
              const SizedBox(height: 16),
              SelectableText(protectedDescription),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Back to editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send ticket'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(() async {
      final result = await widget.service.call('createBusinessSupportTicket', {
        'requestId': _requestId,
        'kind': _kind,
        'priority': _priority,
        'description': protectedDescription,
        'consent': true,
      });
      if (result['id'] is! String) throw const BusinessOperationsException();
      if (!mounted) return;
      setState(() {
        _tickets = [
          result,
          ..._tickets.where((ticket) => ticket['id'] != result['id']),
        ];
        _description.clear();
        _consent = false;
        _requestId = BusinessOperationsService.newRequestId();
      });
    });
  }

  Future<void> _restore(Map<String, dynamic> file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore this encrypted file?'),
        content: const Text(
          'Restore to this space’s root. If this is an older version, the current version is retained. Encrypted objects are not overwritten. You must verify the restored file on your trusted device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore file'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(() async {
      final requestId = sha256
          .convert(
            utf8.encode('business-restore:${file['id']}:${file['revision']}'),
          )
          .toString()
          .substring(0, 32);
      final result = await widget.service.call('restoreBusinessRecoveryFile', {
        'requestId': requestId,
        'fileId': file['id'],
        'revision': file['revision'],
      });
      if (result['status'] != 'restored') {
        throw const BusinessOperationsException();
      }
      if (!mounted) return;
      setState(() {
        _files.removeWhere((item) => item['id'] == file['id']);
        _operations.insert(0, {
          'id': result['operationId'],
          'fileId': file['id'],
          'status': 'restored',
          'verification': 'customer_device_required',
        });
      });
    });
  }

  Future<void> _revealName(String fileId) async {
    final resolver = widget.resolveFileName;
    if (resolver == null || _revealing.contains(fileId)) return;
    setState(() => _revealing.add(fileId));
    try {
      final label = await resolver(fileId);
      if (!mounted) return;
      setState(() {
        if (label == null || label.isEmpty) {
          _error =
              'This device could not unlock the private file name. Unlock the correct workspace keys and retry.';
        } else {
          _revealedNames[fileId] = label;
        }
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'The private file name could not be read with current access. Refresh company access and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _revealing.remove(fileId));
    }
  }

  Future<void> _verify(Map<String, dynamic> operation) => _run(() async {
    final verify = widget.verifyFile;
    if (verify == null || !await verify(operation['fileId'] as String)) {
      if (mounted) {
        setState(
          () => _error =
              'Restore read verification did not complete. Open Company files, unlock the correct keys, and retry. The restored object remains protected.',
        );
      }
      return;
    }
    await widget.service.call('recordBusinessRecoveryCheck', {
      'operationId': operation['id'],
      'verified': true,
    });
    if (mounted) {
      setState(
        () => operation['verification'] = 'customer_device_reported_verified',
      );
    }
  });

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Text(text, style: Theme.of(context).textTheme.titleLarge),
  );

  String _when(Object? value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    return date == null
        ? 'Unavailable'
        : '${DateFormat.yMMMd().add_Hm().format(date.toLocal())} local time';
  }

  String _space(Object? value) => switch (value) {
    'company_shared' => 'Company shared space',
    'company_private' => 'Private company space',
    'group' => 'Group space',
    _ => 'Company space',
  };

  String _compensation(Object? value) => switch (value) {
    'due_provider_review' => 'provider compensation due; review pending',
    'offered' => 'compensation offered',
    'settled' => 'settlement recorded',
    _ => 'no contracted compensation recorded',
  };

  String _size(Object? value) {
    if (value is! num) return 'Size unavailable';
    final bytes = value;
    if (bytes >= 1048576) return '${(bytes / 1048576).toStringAsFixed(1)} MiB';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
    return '$bytes bytes';
  }

  Widget _errorNotice() => _error == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Semantics(liveRegion: true, child: Text(_error!)),
        );

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.sample
              ? 'Sample support & recovery'
              : 'Business support & recovery',
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh Business operations',
            onPressed: _busy || _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: const TabBar(
          isScrollable: true,
          tabs: [
            Tab(text: 'Support'),
            Tab(text: 'File recovery'),
            Tab(text: 'Service terms'),
          ],
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            children: [
              if (_loading) const LinearProgressIndicator(),
              if (widget.sample)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Read-only fictional sample. No real ticket, contract, payment or file restore is created.',
                  ),
                ),
              Expanded(
                child: TabBarView(
                  children: [
                    ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        _errorNotice(),
                        Text(
                          'Support intake, any time',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _state == null
                              ? 'Response coverage has not been verified.'
                              : _state!['guaranteeActive'] == true
                              ? 'Contracted 24/7 coverage is active. A human first response is due within eight elapsed hours. Missed deadlines create a provider compensation review.'
                              : 'Human first-response target: eight elapsed hours. The contractual guarantee is not active until your Business agreement and staffed coverage are confirmed.',
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Automated receipts do not count as a human reply. A first response does not promise that the issue is resolved.',
                        ),
                        if (!widget.sample) ...[
                          _heading('Open a support ticket'),
                          DropdownButtonFormField<String>(
                            initialValue: _kind,
                            decoration: const InputDecoration(
                              labelText: 'Request type',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'support',
                                child: Text('Support'),
                              ),
                              DropdownMenuItem(
                                value: 'recovery',
                                child: Text('Recovery assistance'),
                              ),
                            ],
                            onChanged: _busy || _loading
                                ? null
                                : (value) => setState(() => _kind = value!),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: _priority,
                            decoration: const InputDecoration(
                              labelText: 'Priority',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'normal',
                                child: Text('Normal'),
                              ),
                              DropdownMenuItem(
                                value: 'urgent',
                                child: Text('Urgent — work is blocked'),
                              ),
                            ],
                            onChanged: _busy || _loading
                                ? null
                                : (value) => setState(() => _priority = value!),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _description,
                            enabled: !_busy && !_loading,
                            minLines: 3,
                            maxLines: 8,
                            maxLength: 4000,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'Describe the problem',
                              helperText:
                                  'Never include passwords, file contents, private keys or recovery material.',
                              helperMaxLines: 3,
                            ),
                          ),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _consent,
                            onChanged: _busy || _loading
                                ? null
                                : (value) =>
                                      setState(() => _consent = value ?? false),
                            title: const Text(
                              'I agree to share this description with support and my company administrators.',
                            ),
                          ),
                          FilledButton(
                            onPressed:
                                _busy ||
                                    _loading ||
                                    !_consent ||
                                    _description.text.trim().isEmpty
                                ? null
                                : _submit,
                            child: Text(
                              _busy ? 'Submitting…' : 'Submit support ticket',
                            ),
                          ),
                        ],
                        _heading('Your support tickets'),
                        if (_state != null && _tickets.isEmpty)
                          const Text('No tickets in the loaded inbox.'),
                        if (_truncated)
                          const Text('Showing the most recent 50 tickets.'),
                        for (final ticket in _tickets)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${ticket['kind']} · ${ticket['priority']} · ${ticket['status']}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  Text(
                                    'First-response deadline: ${_when(ticket['firstResponseDueAt'])}',
                                  ),
                                  Text(ticket['description'] as String? ?? ''),
                                  if (ticket['humanResponse'] != null) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      'Human response: ${ticket['humanResponse']}',
                                    ),
                                  ],
                                  if (ticket['breached'] == true)
                                    Text(
                                      'Deadline missed · ${_compensation(ticket['compensationStatus'])}',
                                    ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        _errorNotice(),
                        Text(
                          'Restore, then verify',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Review the deletion time, size and space before restoring. Private names and file contents are not sent to support. Current company permissions and retention limits apply. Recovery uses retained ciphertext; it cannot recreate missing customer keys.',
                        ),
                        _heading('Retained deleted files and versions'),
                        if (_state != null && _files.isEmpty)
                          const Text(
                            'No recoverable files in this loaded page. This does not verify a backup.',
                          ),
                        for (final file in _files)
                          Card(
                            child: ListTile(
                              leading: const Icon(Icons.history),
                              title: Text(
                                _revealedNames[file['id']] ??
                                    'Encrypted recovery item',
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${file['state'] == 'version' ? 'Older version' : 'Recycle bin'} · ${_size(file['bytes'])} · ${_space(file['storageScope'])}\nChanged: ${_when(file['changedAt'])}',
                                  ),
                                  if (widget.resolveFileName != null &&
                                      !_revealedNames.containsKey(file['id']))
                                    TextButton(
                                      onPressed: _revealing.contains(file['id'])
                                          ? null
                                          : () => _revealName(
                                              file['id'] as String,
                                            ),
                                      child: Text(
                                        _revealing.contains(file['id'])
                                            ? 'Unlocking name…'
                                            : 'Reveal name on this device',
                                      ),
                                    ),
                                ],
                              ),
                              trailing: widget.sample
                                  ? null
                                  : IconButton(
                                      tooltip: 'Restore encrypted file',
                                      onPressed: _busy || _loading
                                          ? null
                                          : () => _restore(file),
                                      icon: const Icon(Icons.restore),
                                    ),
                            ),
                          ),
                        if (_next != null)
                          TextButton(
                            onPressed: _loading || _busy
                                ? null
                                : () => _load(next: true),
                            child: const Text('Load more recovery items'),
                          ),
                        _heading('Recovery workflows'),
                        const Text(
                          'A restored metadata record is not a verified restore. The verification step streams and authenticates the file on the customer device; the server records only the customer-device report.',
                        ),
                        for (final operation in _operations)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Encrypted file restored'),
                                  Text(
                                    operation['verification'] ==
                                            'customer_device_reported_verified'
                                        ? 'Customer device reported a verified read.'
                                        : 'Awaiting customer-device read verification.',
                                  ),
                                  if (operation['verification'] !=
                                          'customer_device_reported_verified' &&
                                      !widget.sample)
                                    OutlinedButton(
                                      onPressed:
                                          widget.verifyFile == null ||
                                              _busy ||
                                              _loading
                                          ? null
                                          : () => _verify(operation),
                                      child: const Text('Verify restored file'),
                                    ),
                                  if (widget.verifyFile == null &&
                                      !widget.sample)
                                    const Text(
                                      'Open Support & recovery from Company files to verify using the unlocked customer device.',
                                    ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        _errorNotice(),
                        Text(
                          'Agreement & pricing',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Monthly total = max(USD 6.00, attributable service cost ÷ 0.50), rounded upward to a cent. For USD 10 of cost, the total is USD 20; the USD 6 minimum is not added again. Taxes are separate.',
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Rates and cost allocation must be disclosed before billing. Signed service orders may supplement the online agreement. Cost schedule changes need a new version and acceptance before they apply.',
                        ),
                        if (_state?['signedServiceOrderReference'] != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              'Signed service order: ${_state!['signedServiceOrderReference']}',
                            ),
                          ),
                        if (!widget.sample) ...[
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _busy || _loading
                                ? null
                                : () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => BusinessBillingPage(
                                        service: widget.service,
                                      ),
                                    ),
                                  ),
                            icon: const Icon(Icons.receipt_long_outlined),
                            label: const Text(
                              'Manage automatic Business billing',
                            ),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: _busy || _loading
                                ? null
                                : () async {
                                    await Navigator.of(context).push<bool>(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            BusinessServiceAgreementPage(
                                              service: widget.service,
                                            ),
                                      ),
                                    );
                                    if (mounted) _load();
                                  },
                            child: const Text(
                              'Review and accept service agreement',
                            ),
                          ),
                          _heading('Approved monthly cost quote'),
                          TextField(
                            controller: _period,
                            decoration: const InputDecoration(
                              labelText: 'Billing period (YYYY-MM)',
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _busy || _loading
                                ? null
                                : () => _run(() async {
                                    final quote = await widget.service.call(
                                      'getBusinessPricingQuote',
                                      {'period': _period.text.trim()},
                                    );
                                    if (mounted) setState(() => _quote = quote);
                                  }),
                            child: const Text('Get approved quote'),
                          ),
                          if (_quote != null)
                            Text(
                              'USD ${((_quote!['totalCents'] as num) / 100).toStringAsFixed(2)} · quote only; no payment collected.',
                            ),
                        ],
                        if (widget.sample)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.receipt_long_outlined),
                              label: const Text(
                                'Explore a sample Business bill',
                              ),
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => BusinessBillingPage(
                                    service: widget.service,
                                    readOnlySample: true,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        _heading('Periodic adversarial testing'),
                        const Text(
                          'Weekly automated regression tests exercise synthetic tenant isolation, authorization, support deadlines, retry behavior and recovery integrity. They are not an independent human red-team assessment.',
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _state?['security'] == null
                              ? 'No published test evidence is available for this environment.'
                              : 'Latest recorded automated check: ${_state!['security']['status']} · ${_state!['security']['completedAt']}. Scope: synthetic regression tests.',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
