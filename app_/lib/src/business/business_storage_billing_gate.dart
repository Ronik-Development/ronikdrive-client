import 'dart:async';
import 'package:flutter/material.dart';

import 'business_billing_page.dart';
import 'business_operations_service.dart';

/// Company management and recovery remain available while sponsored storage
/// waits for billing. Never rebuild a live transfer workspace on each poll.
class BusinessStorageBillingGate extends StatefulWidget {
  const BusinessStorageBillingGate({
    super.key,
    required this.service,
    required this.child,
    required this.allowExternalPayments,
  });
  final BusinessOperationsService service;
  final Widget child;
  final bool allowExternalPayments;
  @override
  State<BusinessStorageBillingGate> createState() =>
      _BusinessStorageBillingGateState();
}

class _BusinessStorageBillingGateState extends State<BusinessStorageBillingGate>
    with WidgetsBindingObserver {
  Map<String, dynamic>? _access;
  bool _refreshing = false;
  bool _failed = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final response = await widget.service.call(
        'refreshBusinessBillingAccess',
      );
      if (mounted) {
        setState(() {
          _access = response;
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      _refreshing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_access?['accessActive'] == true || _access?['legacyAccess'] == true) {
      return widget.child;
    }
    if (_access?['recoveryAccess'] == true) {
      return Column(
        children: [
          MaterialBanner(
            content: const Text(
              'Company billing needs attention. New uploads are paused; existing files and recovery remain available.',
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => BusinessBillingPage(
                        service: widget.service,
                        allowExternalPayments: widget.allowExternalPayments,
                      ),
                    ),
                  );
                  if (mounted) _refresh();
                },
                child: const Text('Review billing'),
              ),
            ],
          ),
          Expanded(child: widget.child),
        ],
      );
    }
    if (_access == null) {
      return Center(
        child: _failed
            ? TextButton(
                onPressed: _refresh,
                child: const Text('Retry company billing access check'),
              )
            : const CircularProgressIndicator(),
      );
    }
    return BusinessBillingPage(
      service: widget.service,
      embedded: true,
      onChanged: _refresh,
      allowExternalPayments: widget.allowExternalPayments,
    );
  }
}
