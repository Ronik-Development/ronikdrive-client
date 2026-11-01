import 'business_key_verification_page.dart';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../authentication/account_environment.dart';
import '../authentication/login_password_vault.dart';
import '../billing/billing_channel.dart';
import '../home/workspace_home_page.dart';
import '../privacy/local_private_cache.dart';
import 'business_metadata_coordinator.dart';
import 'company_admin_page.dart';
import 'company_admin_service.dart';
import 'business_reconciliation_queue.dart';
import 'business_operations_service.dart';
import 'business_billing_page.dart';
import 'business_storage_billing_gate.dart';

class BusinessWorkspacePage extends StatefulWidget {
  const BusinessWorkspacePage({
    super.key,
    required this.auth,
    required this.user,
    required this.firestore,
    this.companyService,
    this.billingChannel = BillingChannel.stripe,
  });

  final FirebaseAuth auth;
  final User user;
  final FirebaseFirestore firestore;
  final CompanyAdminService? companyService;
  final BillingChannel billingChannel;

  @override
  State<BusinessWorkspacePage> createState() => _BusinessWorkspacePageState();
}

class _BusinessWorkspacePageState extends State<BusinessWorkspacePage> {
  late final CompanyAdminService _companyService;
  CompanySession? _session;
  CompanyDashboard? _dashboard;
  bool _loading = true;
  bool _refreshing = false;
  bool _sessionRequestInFlight = false;
  String? _errorMessage;
  int _selectedIndex = 0;
  BusinessReconciliationQueueStore? _reconciliationQueueStore;
  late final Future<void> _reconciliationQueueReady;
  List<BusinessReconciliationTarget> _reconciliationTargets =
      const <BusinessReconciliationTarget>[];
  bool _reconciliationQueueLocked = false;
  bool _reconciliationQueueRecovered = false;
  BusinessReconciliationLocation? _requestedReconciliationLocation;
  int _reconciliationRequestRevision = 0;

  @override
  void initState() {
    super.initState();
    final providedService = widget.companyService;
    _companyService =
        providedService ??
        CompanyAdminService.forApp(
          widget.auth.app,
          metadataProtection: BusinessMetadataCoordinator.forApp(
            app: widget.auth.app,
            user: widget.user,
            firestore: widget.firestore,
          ),
        );
    _reconciliationQueueReady = _loadReconciliationQueue();
    unawaited(_loadSession());
  }

  String _localPrivateCacheScope() {
    try {
      final projectId = widget.auth.app.options.projectId.trim();
      if (projectId.isNotEmpty) {
        return projectId;
      }
    } catch (_) {
      // Firebase test doubles may not expose production app options.
    }
    try {
      final appName = widget.auth.app.name.trim();
      if (appName.isNotEmpty) {
        return appName;
      }
    } catch (_) {
      // Fall through to a deterministic local-only scope.
    }
    return 'local-firebase-app';
  }

  Future<void> _loadReconciliationQueue() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final store = BusinessReconciliationQueueStore(
        privateCache: LocalPrivateCachePreferences(
          preferences: preferences,
          uid: widget.user.uid,
          scope: _localPrivateCacheScope(),
        ),
      );
      _reconciliationQueueStore = store;
      final load = await store.load();
      if (!mounted) {
        return;
      }
      setState(() {
        _reconciliationTargets = load.targets;
        _reconciliationQueueLocked = load.temporarilyUnavailable;
        _reconciliationQueueRecovered = load.discardedCorruptValue;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _reconciliationQueueLocked = true;
      });
    }
  }

  Future<void> _queueReconciliationTargets(
    Iterable<BusinessReconciliationTarget> targets,
  ) async {
    await _reconciliationQueueReady;
    final merged = <String, BusinessReconciliationTarget>{
      for (final target in _reconciliationTargets)
        target.location.identity: target,
    };
    for (final target in targets) {
      final identity = target.location.identity;
      final existing = merged[identity];
      merged[identity] = existing == null ? target : existing.merge(target);
    }
    final next = merged.values.toList()
      ..sort((first, second) => second.queuedAt.compareTo(first.queuedAt));
    if (next.length > BusinessReconciliationQueueStore.maxTargets) {
      next.removeRange(
        BusinessReconciliationQueueStore.maxTargets,
        next.length,
      );
    }
    if (mounted) {
      setState(() {
        _reconciliationTargets = next;
        _reconciliationQueueRecovered = false;
      });
    } else {
      _reconciliationTargets = next;
    }
    try {
      final store = _reconciliationQueueStore;
      if (store == null) {
        throw StateError('The encrypted reconciliation queue is unavailable.');
      }
      await store.save(next);
      if (mounted) {
        setState(() {
          _reconciliationQueueLocked = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _reconciliationQueueLocked = true;
        });
      }
    }
  }

  Future<void> _synchronizeRemoteReconciliationState({
    required CompanyProfile company,
    required Iterable<CompanyGroup> groups,
  }) async {
    await _reconciliationQueueReady;
    final groupList = groups.toList(growable: false);
    final next = BusinessReconciliationPlanner.synchronizeRemoteState(
      existingTargets: _reconciliationTargets,
      company: company,
      groups: groupList,
    );
    if (mounted) {
      setState(() {
        _reconciliationTargets = next;
        _reconciliationQueueRecovered = false;
      });
    } else {
      _reconciliationTargets = next;
    }
    try {
      final store = _reconciliationQueueStore;
      if (store == null) {
        throw StateError('The encrypted reconciliation queue is unavailable.');
      }
      await store.save(next);
      if (mounted) {
        setState(() => _reconciliationQueueLocked = false);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _reconciliationQueueLocked = true);
      }
    }
  }

  Future<void> _completeReconciliationLocation(
    BusinessReconciliationLocation location,
  ) async {
    await _reconciliationQueueReady;
    BusinessReconciliationTarget? completedTarget;
    for (final target in _reconciliationTargets) {
      if (target.location == location) {
        completedTarget = target;
        break;
      }
    }
    final localRequiredRevision = completedTarget?.requiredRevision ?? 0;
    final remoteRequiredRevision = _remoteReconciliationState(location);
    final requiredRevision = localRequiredRevision > 0
        ? localRequiredRevision
        : remoteRequiredRevision?.pending == true
        ? remoteRequiredRevision!.requiredRevision
        : 0;
    if (requiredRevision > 0) {
      try {
        await _companyService.acknowledgeReconciliation(
          storageScope: location.storageScope,
          groupId: location.groupId,
          expectedRevision: requiredRevision,
        );
      } on CompanyAdminException catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(
              SnackBar(
                content: Text(
                  '${error.message} The encrypted work is safe; the reminder '
                  'will stay until the latest access state is confirmed.',
                ),
              ),
            );
        }
        rethrow;
      }
    }
    final next = _reconciliationTargets
        .where((target) => target.location != location)
        .toList(growable: false);
    if (next.length == _reconciliationTargets.length) {
      return;
    }
    if (mounted) {
      setState(() {
        _reconciliationTargets = next;
      });
    } else {
      _reconciliationTargets = next;
    }
    try {
      final store = _reconciliationQueueStore;
      if (store == null) {
        throw StateError('The encrypted reconciliation queue is unavailable.');
      }
      await store.save(next);
      if (mounted) {
        setState(() {
          _reconciliationQueueLocked = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _reconciliationQueueLocked = true;
        });
      }
    }
  }

  BusinessReconciliationState? _remoteReconciliationState(
    BusinessReconciliationLocation location,
  ) {
    if (location.storageScope == 'company_shared') {
      final company = _dashboard?.company ?? _session?.company;
      return company?.id == location.companyId ? company?.reconciliation : null;
    }
    final groupId = location.groupId;
    if (groupId == null) {
      return null;
    }
    for (final group
        in _dashboard?.groups ?? _session?.groups ?? const <CompanyGroup>[]) {
      if (group.id == groupId) {
        return group.reconciliation;
      }
    }
    return null;
  }

  Future<void> _loadSession() async {
    if (_sessionRequestInFlight) {
      return;
    }
    _sessionRequestInFlight = true;
    final preserveWorkspace = _session != null;
    setState(() {
      if (preserveWorkspace) {
        _refreshing = true;
      } else {
        _loading = true;
      }
      _errorMessage = null;
    });
    try {
      final session = await _companyService.beginSession();
      if (!mounted) {
        return;
      }
      setState(() {
        _session = session;
        if (!preserveWorkspace) {
          _selectedIndex = 0;
        }
      });
      final company = session.company;
      if (company != null) {
        await _synchronizeRemoteReconciliationState(
          company: company,
          groups: session.groups,
        );
      }
    } on CompanyAdminException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage =
            'Company access could not be refreshed. Check your connection and try again.';
      });
    } finally {
      _sessionRequestInFlight = false;
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  void _handleDashboardChanged(CompanyDashboard dashboard) {
    final company = dashboard.company;
    final member = dashboard.currentMember;
    setState(() {
      _dashboard = dashboard;
      _session = CompanySession(
        company: company,
        currentMember: member,
        canCreate: company == null,
        canManage: dashboard.canManage,
        groups: dashboard.groups,
      );
    });
    if (company != null) {
      unawaited(
        _synchronizeRemoteReconciliationState(
          company: company,
          groups: dashboard.groups,
        ),
      );
    }
  }

  List<BusinessReconciliationTarget> get _currentCompanyTargets {
    final companyId = _session?.company?.id.trim();
    if (companyId == null || companyId.isEmpty) {
      return const <BusinessReconciliationTarget>[];
    }
    return _reconciliationTargets
        .where((target) => target.location.companyId == companyId)
        .toList(growable: false);
  }

  String _reconciliationTargetLabel(BusinessReconciliationTarget target) {
    if (target.location.storageScope == 'company_shared') {
      final companyName = _session?.company?.name.trim();
      return companyName == null || companyName.isEmpty
          ? 'Company Shared'
          : '$companyName Shared';
    }
    final groupId = target.location.groupId;
    for (final group
        in _dashboard?.groups ?? _session?.groups ?? const <CompanyGroup>[]) {
      if (group.id == groupId) {
        return group.name;
      }
    }
    return 'Group workspace';
  }

  bool _canOpenReconciliationTarget(BusinessReconciliationTarget target) {
    final member = _dashboard?.currentMember ?? _session?.currentMember;
    if (member == null || member.status != 'active') {
      return false;
    }
    if (member.permissions['downloadFiles'] != true ||
        member.permissions['uploadFiles'] != true) {
      return false;
    }
    if (target.location.storageScope == 'company_shared') {
      return member.accessScopes.contains('company_workspace') ||
          member.accessScopes.contains('shared_folders');
    }
    final groupId = target.location.groupId;
    if (groupId == null || !member.groupIds.contains(groupId)) {
      return false;
    }
    for (final group
        in _dashboard?.groups ?? _session?.groups ?? const <CompanyGroup>[]) {
      if (group.id == groupId) {
        return group.sharedStorageEnabled;
      }
    }
    return true;
  }

  void _openReconciliationTarget(BusinessReconciliationTarget target) {
    if (!_canOpenReconciliationTarget(target)) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'A current member of this encrypted space must complete the '
              'reconciliation from their trusted device.',
            ),
          ),
        );
      return;
    }
    setState(() {
      _selectedIndex = 0;
      _requestedReconciliationLocation = target.location;
      _reconciliationRequestRevision += 1;
    });
  }

  Future<void> _signOut() async {
    LoginPasswordVault.instance.clear();
    await AccountEnvironmentStore.instance.clear();
    await widget.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const _BusinessLoadingView();
    }
    if (_errorMessage != null && _session == null) {
      return _BusinessAccessErrorView(
        message: _errorMessage!,
        onRetry: _loadSession,
        onSignOut: _signOut,
      );
    }

    final session = _session;
    if (session == null) {
      return _BusinessAccessErrorView(
        message: 'The company session could not be loaded.',
        onRetry: _loadSession,
        onSignOut: _signOut,
      );
    }
    if (session.canCreate && session.company == null) {
      return _BusinessShell(
        title: 'Set up your company',
        email: widget.user.email ?? '',
        onSignOut: _signOut,
        body: CompanyAdminPage(
          auth: widget.auth,
          firestore: widget.firestore,
          service: _companyService,
          embedded: true,
          onDashboardChanged: _handleDashboardChanged,
          onReconciliationRequired: _queueReconciliationTargets,
        ),
      );
    }
    if (!session.hasActiveMembership) {
      return _BusinessAccessErrorView(
        message:
            'This login does not have an active company membership. Contact a company administrator.',
        onRetry: _loadSession,
        onSignOut: _signOut,
      );
    }

    return _buildActiveWorkspace(session);
  }

  Widget _buildActiveWorkspace(CompanySession session) {
    final company = session.company!;
    final destinations = <_BusinessDestination>[
      _BusinessDestination(
        label: 'Company files',
        icon: Icons.folder_shared_outlined,
        selectedIcon: Icons.folder_shared_rounded,
        child: BusinessStorageBillingGate(
          service: BusinessOperationsService.forApp(widget.auth.app),
          allowExternalPayments: widget.billingChannel.usesStripe,
          child: WorkspaceHomePage(
            billingChannel: widget.billingChannel,
            auth: widget.auth,
            user: widget.user,
            firestore: widget.firestore,
            businessMode: true,
            requestedBusinessReconciliationLocation:
                _requestedReconciliationLocation,
            businessReconciliationRequestRevision:
                _reconciliationRequestRevision,
            onBusinessReconciliationCompleted: _completeReconciliationLocation,
            businessGroupLabels: <String, String>{
              for (final group in _dashboard?.groups ?? session.groups)
                group.id: group.name,
            },
            businessCompanyLabel: company.name,
          ),
        ),
      ),
      _BusinessDestination(
        label: 'Key verification',
        icon: Icons.verified_user_outlined,
        selectedIcon: Icons.verified_user,
        child: BusinessKeyVerificationPage(
          key: ValueKey('${widget.auth.currentUser?.uid}/${company.id}'),
          auth: widget.auth,
          companyId: company.id,
        ),
      ),
      if (session.canManage)
        _BusinessDestination(
          label: 'Billing',
          icon: Icons.receipt_long_outlined,
          selectedIcon: Icons.receipt_long,
          child: BusinessBillingPage(
            service: BusinessOperationsService.forApp(widget.auth.app),
            embedded: true,
            allowExternalPayments: widget.billingChannel.usesStripe,
          ),
        ),
      if (session.canManage)
        _BusinessDestination(
          label: 'Administration',
          icon: Icons.admin_panel_settings_outlined,
          selectedIcon: Icons.admin_panel_settings_rounded,
          child: CompanyAdminPage(
            auth: widget.auth,
            firestore: widget.firestore,
            service: _companyService,
            embedded: true,
            onDashboardChanged: _handleDashboardChanged,
            onReconciliationRequired: _queueReconciliationTargets,
          ),
        ),
    ];
    final selectedIndex = _selectedIndex.clamp(0, destinations.length - 1);
    final content = IndexedStack(
      index: selectedIndex,
      children: destinations.map((destination) => destination.child).toList(),
    );
    final currentTargets = _currentCompanyTargets;
    final showReconciliationBanner =
        currentTargets.isNotEmpty ||
        _reconciliationQueueLocked ||
        _reconciliationQueueRecovered;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(company.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              'Business workspace',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh company access',
            onPressed: _refreshing ? null : _loadSession,
            icon: _refreshing
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: _signOut,
            icon: const Icon(Icons.logout_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          if (_errorMessage != null)
            BusinessAccessRefreshNotice(
              message: _errorMessage!,
              refreshing: _refreshing,
              onRetry: _loadSession,
              onDismiss: () => setState(() => _errorMessage = null),
            ),
          if (showReconciliationBanner)
            BusinessReconciliationQueueBanner(
              targets: currentTargets,
              cacheLocked: _reconciliationQueueLocked,
              recoveredCorruptValue: _reconciliationQueueRecovered,
              labelFor: _reconciliationTargetLabel,
              canOpen: _canOpenReconciliationTarget,
              onOpen: _openReconciliationTarget,
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (destinations.length == 1) {
                  return content;
                }
                if (constraints.maxWidth >= 900) {
                  return Row(
                    children: [
                      NavigationRail(
                        selectedIndex: selectedIndex,
                        onDestinationSelected: (value) {
                          setState(() => _selectedIndex = value);
                        },
                        labelType: NavigationRailLabelType.all,
                        destinations: destinations
                            .map(
                              (destination) => NavigationRailDestination(
                                icon: Icon(destination.icon),
                                selectedIcon: Icon(destination.selectedIcon),
                                label: Text(destination.label),
                              ),
                            )
                            .toList(),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(child: content),
                    ],
                  );
                }
                return content;
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: destinations.length > 1
          ? LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 900) {
                  return const SizedBox.shrink();
                }
                return NavigationBar(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: (value) {
                    setState(() => _selectedIndex = value);
                  },
                  destinations: destinations
                      .map(
                        (destination) => NavigationDestination(
                          icon: Icon(destination.icon),
                          selectedIcon: Icon(destination.selectedIcon),
                          label: destination.label,
                        ),
                      )
                      .toList(),
                );
              },
            )
          : null,
    );
  }
}

class BusinessAccessRefreshNotice extends StatelessWidget {
  const BusinessAccessRefreshNotice({
    super.key,
    required this.message,
    required this.refreshing,
    required this.onRetry,
    required this.onDismiss,
  });

  final String message;
  final bool refreshing;
  final Future<void> Function() onRetry;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return MaterialBanner(
      leading: const Icon(Icons.sync_problem_outlined),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Using the last verified company access',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 2),
          Text(message),
          const SizedBox(height: 2),
          const Text(
            'Your current encrypted workspace remains open while access is refreshed.',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: refreshing ? null : onDismiss,
          child: const Text('Dismiss'),
        ),
        FilledButton.tonalIcon(
          onPressed: refreshing ? null : onRetry,
          icon: refreshing
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded),
          label: Text(refreshing ? 'Refreshing' : 'Retry'),
        ),
      ],
    );
  }
}

class _BusinessDestination {
  const _BusinessDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.child,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget child;
}

class BusinessReconciliationQueueBanner extends StatelessWidget {
  const BusinessReconciliationQueueBanner({
    super.key,
    required this.targets,
    required this.cacheLocked,
    required this.recoveredCorruptValue,
    required this.labelFor,
    required this.canOpen,
    required this.onOpen,
  });

  final List<BusinessReconciliationTarget> targets;
  final bool cacheLocked;
  final bool recoveredCorruptValue;
  final String Function(BusinessReconciliationTarget target) labelFor;
  final bool Function(BusinessReconciliationTarget target) canOpen;
  final ValueChanged<BusinessReconciliationTarget> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = targets.length;
    final title = count == 0
        ? cacheLocked
              ? 'Unlock this device to restore encrypted follow-up'
              : 'Encrypted follow-up list recovered safely'
        : '$count encrypted space${count == 1 ? '' : 's'} '
              '${count == 1 ? 'needs' : 'need'} attention';
    final subtitle = count == 0
        ? cacheLocked
              ? 'The credential store is unavailable. Existing encrypted '
                    'reminders remain protected and are not replaced with '
                    'readable state.'
              : 'Unreadable local reminder data was discarded. Cloud files '
                    'and access controls were not changed.'
        : 'Access changed here or on another administrator device. Open each '
              'available space from a trusted member device and reconcile it. '
              'File content stays on that device; RonikCloud synchronizes only '
              'revision counters, never file or task details.';
    return Material(
      color: theme.colorScheme.tertiaryContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                cacheLocked
                    ? Icons.phonelink_lock_outlined
                    : Icons.admin_panel_settings_outlined,
                color: theme.colorScheme.onTertiaryContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(subtitle, style: theme.textTheme.bodySmall),
                    if (targets.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          for (final target in targets.take(4))
                            ActionChip(
                              avatar: Icon(
                                canOpen(target)
                                    ? Icons.lock_reset_outlined
                                    : Icons.person_search_outlined,
                                size: 18,
                              ),
                              label: Text(
                                canOpen(target)
                                    ? labelFor(target)
                                    : '${labelFor(target)} - trusted member',
                              ),
                              tooltip: canOpen(target)
                                  ? 'Open this encrypted space'
                                  : 'A current member must open this space',
                              onPressed: () => onOpen(target),
                            ),
                          if (targets.length > 4)
                            Chip(label: Text('+${targets.length - 4} more')),
                        ],
                      ),
                    ],
                    if (cacheLocked && targets.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'New reminders are visible for this session, but '
                        'device persistence will retry after unlock.',
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                    if (recoveredCorruptValue && targets.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'An older unreadable reminder was removed without '
                        'touching cloud data.',
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BusinessShell extends StatelessWidget {
  const _BusinessShell({
    required this.title,
    required this.email,
    required this.onSignOut,
    required this.body,
  });

  final String title;
  final String email;
  final Future<void> Function() onSignOut;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title),
            if (email.isNotEmpty)
              Text(email, style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: onSignOut,
            icon: const Icon(Icons.logout_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: body,
    );
  }
}

class _BusinessLoadingView extends StatelessWidget {
  const _BusinessLoadingView();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Opening company workspace...'),
          ],
        ),
      ),
    );
  }
}

class _BusinessAccessErrorView extends StatelessWidget {
  const _BusinessAccessErrorView({
    required this.message,
    required this.onRetry,
    required this.onSignOut,
  });

  final String message;
  final Future<void> Function() onRetry;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.business_center_outlined,
                  size: 48,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  'Business access unavailable',
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: onSignOut,
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
