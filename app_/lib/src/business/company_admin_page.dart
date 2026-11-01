import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../shared/sensitive_clipboard.dart';
import 'business_reconciliation_queue.dart';
import 'business_overview.dart';
import 'business_operations_page.dart';
import 'business_operations_service.dart';
import 'business_service_agreement_page.dart';
import 'company_admin_service.dart';

const String businessMutationStatusUncertainMessage =
    'RonikCloud could not confirm whether the Business change completed. The '
    'last verified dashboard remains visible. Refresh status before repeating '
    'or starting another access change.';

class CompanyAdminPage extends StatefulWidget {
  const CompanyAdminPage({
    super.key,
    required this.auth,
    required this.firestore,
    this.service,
    this.operationsService,
    this.onDashboardChanged,
    this.onReconciliationRequired,
    this.embedded = false,
  });

  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final CompanyAdminService? service;
  final BusinessOperationsService? operationsService;
  final ValueChanged<CompanyDashboard>? onDashboardChanged;
  final Future<void> Function(Iterable<BusinessReconciliationTarget> targets)?
  onReconciliationRequired;
  final bool embedded;

  @override
  State<CompanyAdminPage> createState() => _CompanyAdminPageState();
}

class _CompanyAdminPageState extends State<CompanyAdminPage> {
  late final CompanyAdminService _service;
  CompanyDashboard? _dashboard;
  bool _loading = true;
  bool _refreshing = false;
  bool _dashboardRequestInFlight = false;
  bool _busy = false;
  bool _mutationStatusUncertain = false;
  String? _errorMessage;

  final TextEditingController _companyNameController = TextEditingController();
  final TextEditingController _companyDomainController =
      TextEditingController();
  final TextEditingController _invitationCodeController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    _service =
        widget.service ?? CompanyAdminService.forApp(widget.firestore.app);
    unawaited(_loadDashboard());
  }

  @override
  void dispose() {
    _companyNameController.dispose();
    _companyDomainController.dispose();
    _invitationCodeController.dispose();
    super.dispose();
  }

  Future<void> _loadDashboard() async {
    if (_dashboardRequestInFlight) {
      return;
    }
    _dashboardRequestInFlight = true;
    final preserveDashboard = _dashboard != null;
    setState(() {
      if (preserveDashboard) {
        _refreshing = true;
      } else {
        _loading = true;
      }
      _errorMessage = null;
    });
    try {
      final dashboard = await _service.fetchDashboard();
      if (!mounted) {
        return;
      }
      _applyDashboard(dashboard);
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
            'The Business workspace could not be loaded. Check your connection and retry.';
      });
    } finally {
      _dashboardRequestInFlight = false;
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  void _applyDashboard(CompanyDashboard dashboard) {
    _dashboard = dashboard;
    _mutationStatusUncertain = false;
    widget.onDashboardChanged?.call(dashboard);
    final company = dashboard.company;
    if (company != null &&
        (!company.metadataProtected || company.metadataReadable)) {
      _companyNameController.text = company.name;
      _companyDomainController.text = company.domain ?? '';
    }
  }

  Future<CompanyDashboard?> _runMutation(
    Future<CompanyDashboard> Function() action, {
    String? successMessage,
  }) async {
    if (_busy) {
      return null;
    }
    if (_mutationStatusUncertain) {
      _showMessage(businessMutationStatusUncertainMessage);
      return null;
    }
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      final dashboard = await action();
      if (!mounted) {
        return null;
      }
      _applyDashboard(dashboard);
      setState(() {
        _busy = false;
      });
      if (successMessage != null) {
        _showMessage(successMessage);
      }
      return dashboard;
    } on CompanyAdminException catch (error) {
      if (!mounted) {
        return null;
      }
      final statusUncertain = error.kind == CompanyAdminFailureKind.cloud;
      final message = statusUncertain
          ? businessMutationStatusUncertainMessage
          : error.message;
      setState(() {
        _busy = false;
        _mutationStatusUncertain = statusUncertain;
        _errorMessage = message;
      });
      _showMessage(message);
      return null;
    } catch (_) {
      if (!mounted) {
        return null;
      }
      setState(() {
        _busy = false;
        _mutationStatusUncertain = true;
        _errorMessage = businessMutationStatusUncertainMessage;
      });
      _showMessage(businessMutationStatusUncertainMessage);
      return null;
    }
  }

  Future<void> _queueReconciliationTargets(
    Iterable<BusinessReconciliationTarget> targets,
  ) async {
    final normalized = targets.toList(growable: false);
    if (normalized.isEmpty || widget.onReconciliationRequired == null) {
      return;
    }
    try {
      await widget.onReconciliationRequired!(normalized);
    } catch (_) {
      _showMessage(
        'Permissions were updated, but this device could not save the '
        'encrypted follow-up reminder. Open the affected workspace before '
        'closing the app.',
      );
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _createCompany() async {
    final name = _companyNameController.text.trim();
    if (name.isEmpty) {
      _showMessage('Company name is required.');
      return;
    }
    final accepted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => BusinessServiceAgreementPage(
          service:
              widget.operationsService ??
              BusinessOperationsService.forApp(widget.firestore.app),
        ),
      ),
    );
    if (accepted != true || !mounted) return;
    await _runMutation(
      () => _service.createCompany(
        name: name,
        domain: _companyDomainController.text.trim(),
      ),
      successMessage: 'Company profile created.',
    );
  }

  Future<void> _claimInvitation() async {
    final code = _invitationCodeController.text.trim();
    final dashboard = await _runMutation(() => _service.claimInvitation(code));
    if (dashboard == null || !mounted) {
      return;
    }
    _invitationCodeController.clear();
    _showMessage(
      'Invitation accepted. Your company workspace is ready. A current '
      'member may still need to add your encryption envelope before shared '
      'files can open on this device.',
    );
  }

  Future<void> _showPendingInvitation(
    CompanyPendingInvitation invitation,
  ) async {
    final expiry = MaterialLocalizations.of(
      context,
    ).formatMediumDate(invitation.expiresAt.toLocal());
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Share the one-time invitation code'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'No email address or account lookup was used. Anyone with '
                'this code can claim the selected access while signed in, so '
                'send it through a trusted channel and verify the fingerprint '
                'separately. The code is shown only in this response.',
              ),
              const SizedBox(height: 16),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: SelectableText(
                    invitation.code,
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(fontFamily: 'monospace'),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Fingerprint ${invitation.fingerprint} • expires $expiry. '
                'The code is single-use and is never stored in plaintext.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Done'),
          ),
          FilledButton.icon(
            onPressed: () async {
              try {
                await sensitiveClipboard.copy(invitation.code);
              } catch (_) {
                _showMessage(
                  'Clipboard access is unavailable. Select the code and copy '
                  'it manually.',
                );
                return;
              }
              if (!dialogContext.mounted) {
                return;
              }
              Navigator.of(dialogContext).pop();
              _showMessage(
                'Invitation code copied. Share it privately and clear it '
                'after use. RonikCloud will also try to remove unchanged '
                'clipboard content after two minutes.',
              );
            },
            icon: const Icon(Icons.copy_all_outlined),
            label: const Text('Copy code'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveCompanyProfile() async {
    final name = _companyNameController.text.trim();
    if (name.isEmpty) {
      _showMessage('Company name is required.');
      return;
    }
    final company = _dashboard?.company;
    if (company == null) {
      _showMessage('Reload the company profile before saving.');
      return;
    }
    await _runMutation(
      () => _service.updateCompany(
        company: company,
        name: name,
        domain: _companyDomainController.text.trim(),
      ),
      successMessage: 'Company profile updated.',
    );
  }

  Future<void> _refreshProtectedLabels([CompanyGroup? group]) async {
    final company = _dashboard?.company;
    if (company == null) {
      _showMessage('Reload the company profile before refreshing labels.');
      return;
    }
    var added = 0;
    final dashboard = await _runMutation(() async {
      added = await _service.refreshProtectedLabels(
        company: company,
        group: group,
      );
      return _service.fetchDashboard();
    });
    if (dashboard == null || !mounted) {
      return;
    }
    _showMessage(
      added == 0
          ? 'Every encryption-ready member already has protected label access.'
          : 'Protected label access added for $added member'
                '${added == 1 ? '' : 's'}.',
    );
  }

  Future<void> _saveStoragePolicy(CompanyStoragePolicy policy) async {
    await _runMutation(
      () => _service.setStoragePolicy(policy),
      successMessage: 'Storage policy updated.',
    );
  }

  Future<void> _showAddMemberDialog() async {
    var role = 'member';
    var scopes = <String>{'personal_workspace'};
    final result = await showDialog<_MemberEditDraft>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Invite company user'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: role,
                        decoration: const InputDecoration(
                          labelText: 'Role',
                          prefixIcon: Icon(Icons.admin_panel_settings),
                        ),
                        items: _roles
                            .map(
                              (value) => DropdownMenuItem<String>(
                                value: value,
                                child: Text(_roleLabel(value)),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setDialogState(() {
                            role = value;
                            scopes = _defaultScopesForRole(value).toSet();
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Access areas',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _ScopeSelector(
                        selected: scopes,
                        onChanged: (next) {
                          setDialogState(() {
                            scopes = next;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'RonikCloud does not ask for an email address or '
                        'check whether an account exists. It creates a '
                        'seven-day, single-use code for exactly the role and '
                        'access areas selected above. The recipient must '
                        'claim it while signed in. Share it privately.',
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop(
                      _MemberEditDraft(
                        role: role,
                        status: 'invited',
                        permissions: _defaultPermissionsForRole(role),
                        accessScopes: scopes.toList(growable: false),
                      ),
                    );
                  },
                  icon: const Icon(Icons.key_outlined),
                  label: const Text('Generate code'),
                ),
              ],
            );
          },
        );
      },
    );
    if (result == null || !mounted) {
      return;
    }
    final dashboard = await _runMutation(
      () => _service.addMember(
        role: result.role,
        permissions: result.permissions,
        accessScopes: result.accessScopes,
      ),
    );
    final invitation = dashboard?.pendingInvitation;
    if (dashboard == null || !mounted) {
      return;
    }
    if (invitation == null) {
      _showMessage(
        'The invitation response could not be verified. Refresh the company '
        'user list before trying again.',
      );
      await _loadDashboard();
      return;
    }
    await _showPendingInvitation(invitation);
    if (mounted) {
      _applyDashboard(dashboard.copyWith(clearPendingInvitation: true));
      setState(() {});
    }
  }

  Future<void> _revokeInvitation(CompanyMember member) async {
    if (member.status != 'invited') {
      _showMessage('Refresh the company user list before revoking this code.');
      return;
    }
    final fingerprint = member.invitationFingerprint?.trim();
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Revoke this invitation?'),
            content: Text(
              'The one-time code${fingerprint == null || fingerprint.isEmpty ? '' : ' with fingerprint $fingerprint'} '
              'will stop working immediately. No active member is removed. '
              'Generate a new invitation if the intended recipient still '
              'needs access.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Keep invitation'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                icon: const Icon(Icons.link_off_outlined),
                label: const Text('Revoke code'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) {
      return;
    }
    await _runMutation(
      () => _service.revokeInvitation(memberId: member.id),
      successMessage: 'Invitation revoked. The one-time code no longer works.',
    );
  }

  Future<void> _showMemberEditor(CompanyMember member) async {
    var role = member.role;
    var status = member.status;
    var permissions = <String, bool>{
      ..._defaultPermissionsForRole(member.role),
      ...member.permissions,
    };
    var scopes = member.accessScopes.isEmpty
        ? _defaultScopesForRole(member.role).toSet()
        : member.accessScopes.toSet();
    var privateStorageMode = _privateStorageModeFromOverride(
      member.storageOverride.privateStorageEnabled,
    );
    final privateQuotaController = TextEditingController(
      text: _quotaGbText(member.storageOverride.privateQuotaBytes),
    );

    late final _MemberEditDraft? result;
    try {
      result = await showModalBottomSheet<_MemberEditDraft>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setSheetState) {
              final bottom = MediaQuery.viewInsetsOf(context).bottom;
              return Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, bottom + 20),
                child: SafeArea(
                  top: false,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            member.label,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          if (member.email != null)
                            Text(
                              member.email!,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  initialValue: role,
                                  decoration: const InputDecoration(
                                    labelText: 'Role',
                                    prefixIcon: Icon(
                                      Icons.admin_panel_settings_outlined,
                                    ),
                                  ),
                                  items: _roles
                                      .map(
                                        (value) => DropdownMenuItem<String>(
                                          value: value,
                                          child: Text(_roleLabel(value)),
                                        ),
                                      )
                                      .toList(growable: false),
                                  onChanged: (value) {
                                    if (value == null) {
                                      return;
                                    }
                                    setSheetState(() {
                                      role = value;
                                      permissions = _defaultPermissionsForRole(
                                        value,
                                      );
                                      scopes = scopes.isEmpty
                                          ? _defaultScopesForRole(value).toSet()
                                          : scopes;
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  initialValue: status,
                                  decoration: const InputDecoration(
                                    labelText: 'Status',
                                    prefixIcon: Icon(Icons.verified_user),
                                  ),
                                  items: _statuses
                                      .map(
                                        (value) => DropdownMenuItem<String>(
                                          value: value,
                                          child: Text(_statusLabel(value)),
                                        ),
                                      )
                                      .toList(growable: false),
                                  onChanged: (value) {
                                    if (value == null) {
                                      return;
                                    }
                                    setSheetState(() {
                                      status = value;
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'Permissions',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _permissionKeys
                                .map((key) {
                                  return FilterChip(
                                    selected: permissions[key] == true,
                                    label: Text(_permissionLabel(key)),
                                    onSelected: (selected) {
                                      setSheetState(() {
                                        permissions[key] = selected;
                                      });
                                    },
                                  );
                                })
                                .toList(growable: false),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'Access areas',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          _ScopeSelector(
                            selected: scopes,
                            onChanged: (next) {
                              setSheetState(() {
                                scopes = next;
                              });
                            },
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'Company private storage',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  initialValue: privateStorageMode,
                                  decoration: const InputDecoration(
                                    labelText: 'Private storage',
                                    prefixIcon: Icon(Icons.lock_outline),
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'default',
                                      child: Text('Company default'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'enabled',
                                      child: Text('Enabled'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'disabled',
                                      child: Text('Disabled'),
                                    ),
                                  ],
                                  onChanged: (value) {
                                    if (value == null) {
                                      return;
                                    }
                                    setSheetState(() {
                                      privateStorageMode = value;
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: privateQuotaController,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Quota override (GB)',
                                    prefixIcon: Icon(Icons.speed_outlined),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.icon(
                              onPressed: () {
                                Navigator.of(context).pop(
                                  _MemberEditDraft(
                                    role: role,
                                    status: status,
                                    permissions: permissions,
                                    accessScopes: scopes.toList(
                                      growable: false,
                                    ),
                                    storageOverride:
                                        CompanyMemberStorageOverride(
                                          privateStorageEnabled:
                                              _privateStorageBoolFromMode(
                                                privateStorageMode,
                                              ),
                                          privateQuotaBytes: _quotaGbBytes(
                                            privateQuotaController.text,
                                          ),
                                        ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.save_outlined),
                              label: const Text('Save'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      privateQuotaController.dispose();
    }

    if (result == null || !mounted) {
      return;
    }
    final draft = result;
    if (member.status == 'active' && draft.status != 'active') {
      final confirmed =
          await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Suspend this member?'),
              content: const Text(
                'Live sign-in and provider access are revoked immediately. '
                'Then open every affected shared or group workspace and use '
                'Reconcile encrypted member access. That trusted device will '
                'stream-reencrypt affected files under fresh keys. Previously '
                'downloaded copies cannot be erased remotely.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  icon: const Icon(Icons.person_off_outlined),
                  label: const Text('Suspend access'),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirmed || !mounted) {
        return;
      }
    }
    final companyId = _dashboard?.company?.id.trim();
    final groups = _dashboard?.groups ?? const <CompanyGroup>[];
    final reconciliationTargets = companyId == null || companyId.isEmpty
        ? const <BusinessReconciliationTarget>[]
        : BusinessReconciliationPlanner.forMemberChange(
            companyId: companyId,
            before: member,
            status: draft.status,
            accessScopes: draft.accessScopes,
            permissions: draft.permissions,
            groups: groups,
          );
    await _runMutation(
      () async {
        await _service.updateMember(
          memberId: member.id,
          role: draft.role,
          status: draft.status,
          permissions: draft.permissions,
          accessScopes: draft.accessScopes,
        );
        await _queueReconciliationTargets(reconciliationTargets);
        return _service.setMemberStoragePolicy(
          memberId: member.id,
          override: draft.storageOverride,
        );
      },
      successMessage:
          'Company permissions updated. The protected follow-up banner lists '
          'each affected shared or group space.',
    );
  }

  Future<void> _showGroupEditor([CompanyGroup? group]) async {
    if (group != null && group.metadataProtected && !group.metadataReadable) {
      _showMessage(
        'This device does not have the protected group-label key. Ask an '
        'authorized member who can read the label to refresh member access.',
      );
      return;
    }
    final nameController = TextEditingController(text: group?.name ?? '');
    final descriptionController = TextEditingController(
      text: group?.description ?? '',
    );
    final quotaController = TextEditingController(
      text: _quotaGbText(group?.storageOverride.privateQuotaBytes),
    );
    var selectedUids = group?.memberUids.toSet() ?? <String>{};
    var sharedStorageEnabled = group?.sharedStorageEnabled ?? true;
    var privateStorageMode = _privateStorageModeFromOverride(
      group?.storageOverride.privateStorageEnabled,
    );
    try {
      final result = await showDialog<_GroupEditDraft>(
        context: context,
        builder: (context) {
          final members =
              _dashboard?.members
                  .where(
                    (member) => member.uid != null && member.status == 'active',
                  )
                  .toList(growable: false) ??
              const <CompanyMember>[];
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: Text(group == null ? 'Create group' : 'Edit group'),
                content: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: nameController,
                          decoration: const InputDecoration(
                            labelText: 'Group name',
                            prefixIcon: Icon(Icons.group_work_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: descriptionController,
                          minLines: 1,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Description',
                            prefixIcon: Icon(Icons.notes_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          value: sharedStorageEnabled,
                          contentPadding: EdgeInsets.zero,
                          secondary: const Icon(Icons.folder_shared_outlined),
                          title: const Text('Group storage'),
                          onChanged: (value) {
                            setDialogState(() {
                              sharedStorageEnabled = value;
                            });
                          },
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: privateStorageMode,
                                decoration: const InputDecoration(
                                  labelText: 'Private storage',
                                  prefixIcon: Icon(Icons.lock_outline),
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'default',
                                    child: Text('Company default'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'enabled',
                                    child: Text('Enabled'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'disabled',
                                    child: Text('Disabled'),
                                  ),
                                ],
                                onChanged: (value) {
                                  if (value == null) {
                                    return;
                                  }
                                  setDialogState(() {
                                    privateStorageMode = value;
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: quotaController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Quota (GB)',
                                  prefixIcon: Icon(Icons.speed_outlined),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Members',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                        const SizedBox(height: 6),
                        ...members.map((member) {
                          final uid = member.uid!;
                          return CheckboxListTile(
                            value: selectedUids.contains(uid),
                            contentPadding: EdgeInsets.zero,
                            title: Text(member.label),
                            subtitle: member.email == null
                                ? null
                                : Text(member.email!),
                            onChanged: (value) {
                              setDialogState(() {
                                if (value == true) {
                                  selectedUids.add(uid);
                                } else {
                                  selectedUids.remove(uid);
                                }
                              });
                            },
                          );
                        }),
                        const SizedBox(height: 8),
                        const Text(
                          'After changing group membership, open the group '
                          'workspace and reconcile encrypted member access. A '
                          'trusted current member’s device adds access for new '
                          'members and reencrypts files when access was removed.',
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton.icon(
                    onPressed: () {
                      final name = nameController.text.trim();
                      if (name.isEmpty) {
                        return;
                      }
                      Navigator.of(context).pop(
                        _GroupEditDraft(
                          name: name,
                          description: descriptionController.text.trim(),
                          memberUids: selectedUids.toList(growable: false),
                          sharedStorageEnabled: sharedStorageEnabled,
                          storageOverride: CompanyMemberStorageOverride(
                            privateStorageEnabled: _privateStorageBoolFromMode(
                              privateStorageMode,
                            ),
                            privateQuotaBytes: _quotaGbBytes(
                              quotaController.text,
                            ),
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.save_outlined),
                    label: Text(group == null ? 'Create' : 'Save'),
                  ),
                ],
              );
            },
          );
        },
      );
      if (result == null || !mounted) {
        return;
      }
      final removedMemberCount = group == null
          ? 0
          : group.memberUids
                .where((uid) => !result.memberUids.contains(uid))
                .length;
      if (removedMemberCount > 0) {
        final confirmed =
            await showDialog<bool>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: Text(
                  'Remove $removedMemberCount group member'
                  '${removedMemberCount == 1 ? '' : 's'}?',
                ),
                content: const Text(
                  'Group storage authorization is revoked immediately. Then '
                  'open this group workspace and reconcile encrypted member '
                  'access so a trusted device replaces affected encrypted '
                  'objects and keys. Previously downloaded copies cannot be '
                  'erased remotely.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    icon: const Icon(Icons.group_remove_outlined),
                    label: const Text('Remove and continue'),
                  ),
                ],
              ),
            ) ??
            false;
        if (!confirmed || !mounted) {
          return;
        }
      }
      final companyId = _dashboard?.company?.id.trim();
      final reconciliationTargets =
          group == null || companyId == null || companyId.isEmpty
          ? const <BusinessReconciliationTarget>[]
          : BusinessReconciliationPlanner.forGroupChange(
              companyId: companyId,
              before: group,
              memberUids: result.memberUids,
              sharedStorageEnabled: result.sharedStorageEnabled,
            );
      final dashboard = await _runMutation(
        () => group == null
            ? _service.createGroup(
                name: result.name,
                description: result.description,
                memberUids: result.memberUids,
                storageOverride: result.storageOverride,
                sharedStorageEnabled: result.sharedStorageEnabled,
              )
            : _service.updateGroup(
                group: group,
                name: result.name,
                description: result.description,
                memberUids: result.memberUids,
                storageOverride: result.storageOverride,
                sharedStorageEnabled: result.sharedStorageEnabled,
              ),
        successMessage: group == null
            ? 'Group created. Members initialize encryption by opening '
                  'Business once.'
            : 'Group updated. The protected follow-up banner tracks this '
                  'workspace when encrypted access changed.',
      );
      if (dashboard != null) {
        await _queueReconciliationTargets(reconciliationTargets);
      }
    } finally {
      nameController.dispose();
      descriptionController.dispose();
      quotaController.dispose();
    }
  }

  Future<void> _deleteGroup(CompanyGroup group) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('Delete ${group.name}?'),
            content: const Text(
              'A group can be deleted only after its stored files and folders '
              'have been moved or deleted. This prevents encrypted data from '
              'becoming inaccessible. Member accounts are not deleted.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete empty group'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) {
      return;
    }
    await _runMutation(
      () => _service.deleteGroup(groupId: group.id),
      successMessage: 'Group deleted.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = _dashboard;
    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(
              title: Text(dashboard?.company?.name ?? 'Business'),
              actions: [
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: _loading || _refreshing ? null : _loadDashboard,
                  icon: _refreshing
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                ),
              ],
            ),
      body: Stack(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: _loading && _dashboard == null
                ? const Center(child: CircularProgressIndicator())
                : _buildBody(context),
          ),
          if (_refreshing)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final dashboard = _dashboard;
    if (_errorMessage != null && dashboard == null) {
      return _ErrorState(message: _errorMessage!, onRetry: _loadDashboard);
    }
    if (dashboard == null || dashboard.company == null) {
      return BusinessCompanySetupView(
        nameController: _companyNameController,
        domainController: _companyDomainController,
        invitationCodeController: _invitationCodeController,
        busy: _busy || _mutationStatusUncertain,
        errorMessage: _mutationStatusUncertain ? null : _errorMessage,
        statusUncertain: _mutationStatusUncertain,
        refreshingStatus: _refreshing,
        onRefreshStatus: _loadDashboard,
        onCreate: _createCompany,
        onClaimInvitation: _claimInvitation,
      );
    }
    if (!dashboard.canManage) {
      return _LockedCompanyView(
        company: dashboard.company!,
        member: dashboard.currentMember,
      );
    }

    return DefaultTabController(
      length: BusinessAdminSection.values.length,
      child: Builder(
        builder: (tabContext) => Column(
          children: [
            if (_mutationStatusUncertain)
              BusinessMutationStatusNotice(
                refreshing: _refreshing,
                onRefresh: _loadDashboard,
              )
            else if (_errorMessage != null)
              MaterialBanner(
                content: Text(_errorMessage!),
                leading: const Icon(Icons.error_outline),
                actions: [
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _errorMessage = null;
                      });
                    },
                    child: const Text('Dismiss'),
                  ),
                ],
              ),
            const TabBar(
              isScrollable: true,
              tabs: [
                Tab(
                  icon: Icon(Icons.space_dashboard_outlined),
                  text: 'Overview',
                ),
                Tab(icon: Icon(Icons.business_outlined), text: 'Profile'),
                Tab(icon: Icon(Icons.people_alt_outlined), text: 'Users'),
                Tab(icon: Icon(Icons.groups_2_outlined), text: 'Groups'),
                Tab(icon: Icon(Icons.hub_outlined), text: 'Access'),
                Tab(icon: Icon(Icons.receipt_long_outlined), text: 'Logs'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  BusinessOverview(
                    dashboard: dashboard,
                    busy: _busy || _mutationStatusUncertain,
                    onInvite: _showAddMemberDialog,
                    onOpenOperations: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => BusinessOperationsPage(
                          service:
                              widget.operationsService ??
                              BusinessOperationsService.forApp(
                                widget.firestore.app,
                              ),
                        ),
                      ),
                    ),
                    onOpenSection: (section) => DefaultTabController.of(
                      tabContext,
                    ).animateTo(section.index),
                  ),
                  _ProfileTab(
                    dashboard: dashboard,
                    nameController: _companyNameController,
                    domainController: _companyDomainController,
                    busy: _busy || _mutationStatusUncertain,
                    onSave: _saveCompanyProfile,
                    onRefreshProtectedLabels: _refreshProtectedLabels,
                    onStoragePolicySave: _saveStoragePolicy,
                  ),
                  BusinessMembersView(
                    dashboard: dashboard,
                    busy: _busy || _mutationStatusUncertain,
                    onAdd: _showAddMemberDialog,
                    onEdit: _showMemberEditor,
                    onRevokeInvitation: _revokeInvitation,
                  ),
                  BusinessGroupsView(
                    dashboard: dashboard,
                    busy: _busy || _mutationStatusUncertain,
                    onAdd: () => _showGroupEditor(),
                    onEdit: _showGroupEditor,
                    onRefreshProtectedLabels: _refreshProtectedLabels,
                    onDelete: _deleteGroup,
                  ),
                  BusinessAccessMetricsView(dashboard: dashboard),
                  BusinessAuditLogView(
                    dashboard: dashboard,
                    refreshing: _refreshing,
                    onRefresh: _loadDashboard,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BusinessCompanySetupView extends StatelessWidget {
  const BusinessCompanySetupView({
    super.key,
    required this.nameController,
    required this.domainController,
    required this.invitationCodeController,
    required this.busy,
    required this.onCreate,
    required this.onClaimInvitation,
    this.onRefreshStatus,
    this.statusUncertain = false,
    this.refreshingStatus = false,
    this.errorMessage,
  });

  final TextEditingController nameController;
  final TextEditingController domainController;
  final TextEditingController invitationCodeController;
  final bool busy;
  final bool statusUncertain;
  final bool refreshingStatus;
  final String? errorMessage;
  final VoidCallback onCreate;
  final VoidCallback onClaimInvitation;
  final Future<void> Function()? onRefreshStatus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.business_center_outlined,
                    size: 44,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Create company profile',
                    style: theme.textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'The company name and domain are encrypted on this device '
                    'before they leave it.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: nameController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Company name',
                      prefixIcon: Icon(Icons.business_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: domainController,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Domain',
                      prefixIcon: Icon(Icons.public_outlined),
                    ),
                  ),
                  if (statusUncertain) ...[
                    const SizedBox(height: 12),
                    BusinessMutationStatusNotice(
                      refreshing: refreshingStatus,
                      onRefresh: onRefreshStatus ?? () async {},
                    ),
                  ],
                  if (errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      errorMessage!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: busy ? null : onCreate,
                    icon: busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_business_outlined),
                    label: Text(busy ? 'Creating' : 'Create'),
                  ),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),
                  Text(
                    'Join an existing company',
                    style: theme.textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Paste the one-time code shared by your company admin. '
                    'RonikCloud stores only a random hash of this code; it is '
                    'single-use and expires after seven days.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: invitationCodeController,
                    enabled: !busy,
                    autocorrect: false,
                    enableSuggestions: false,
                    textCapitalization: TextCapitalization.none,
                    decoration: const InputDecoration(
                      labelText: 'Business invitation code',
                      prefixIcon: Icon(Icons.key_outlined),
                    ),
                    onSubmitted: busy ? null : (_) => onClaimInvitation(),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: busy ? null : onClaimInvitation,
                    icon: const Icon(Icons.group_add_outlined),
                    label: Text(busy ? 'Checking code' : 'Accept invitation'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BusinessMutationStatusNotice extends StatelessWidget {
  const BusinessMutationStatusNotice({
    super.key,
    required this.refreshing,
    required this.onRefresh,
  });

  final bool refreshing;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return MaterialBanner(
      backgroundColor: colorScheme.errorContainer,
      leading: Icon(
        Icons.sync_problem_outlined,
        color: colorScheme.onErrorContainer,
      ),
      content: Text(
        businessMutationStatusUncertainMessage,
        style: TextStyle(color: colorScheme.onErrorContainer),
      ),
      actions: [
        FilledButton.icon(
          onPressed: refreshing ? null : onRefresh,
          icon: refreshing
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_outlined),
          label: Text(refreshing ? 'Checking status' : 'Refresh status'),
        ),
      ],
    );
  }
}

class _LockedCompanyView extends StatelessWidget {
  const _LockedCompanyView({required this.company, this.member});

  final CompanyProfile company;
  final CompanyMember? member;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_person_outlined,
                size: 44,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(company.name, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'Your role is ${_roleLabel(member?.role ?? 'member')}.',
                style: theme.textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Company administration requires owner or admin access.',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileTab extends StatelessWidget {
  const _ProfileTab({
    required this.dashboard,
    required this.nameController,
    required this.domainController,
    required this.busy,
    required this.onSave,
    required this.onRefreshProtectedLabels,
    required this.onStoragePolicySave,
  });

  final CompanyDashboard dashboard;
  final TextEditingController nameController;
  final TextEditingController domainController;
  final bool busy;
  final VoidCallback onSave;
  final VoidCallback onRefreshProtectedLabels;
  final ValueChanged<CompanyStoragePolicy> onStoragePolicySave;

  @override
  Widget build(BuildContext context) {
    final company = dashboard.company!;
    final activeMembers = dashboard.members
        .where((member) => member.status == 'active')
        .length;
    final invitedMembers = dashboard.members
        .where((member) => member.status == 'invited')
        .length;
    final suspendedMembers = dashboard.members
        .where((member) => member.status == 'suspended')
        .length;
    final indexedBusinessUsageBytes = dashboard.accessPatterns.fold<int>(
      0,
      (total, item) => total + item.usageBytes,
    );
    final inventory = company.storageInventory;
    final usageValue = inventory.available
        ? _formatBytes(inventory.metadataUsageBytes)
        : dashboard.accessPatternsAvailable
        ? _formatBytes(indexedBusinessUsageBytes)
        : 'Pending';
    final labelsReadable =
        !company.metadataProtected || company.metadataReadable;
    final privacyMessage = !company.metadataProtected
        ? 'Legacy profile: save once to encrypt the company name and domain.'
        : company.metadataReadable
        ? 'Company labels leave devices encrypted. The server receives only '
              'ciphertext and per-member key envelopes.'
        : 'Protected company labels are waiting for a key envelope for this '
              'account. Ask an authorized member to refresh label access.';

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _MetricTile(
              icon: Icons.people_alt_outlined,
              label: 'Active users',
              value: '$activeMembers',
            ),
            _MetricTile(
              icon: Icons.mark_email_unread_outlined,
              label: 'Invited',
              value: '$invitedMembers',
            ),
            _MetricTile(
              icon: Icons.block_outlined,
              label: 'Suspended',
              value: '$suspendedMembers',
            ),
            _MetricTile(
              icon: Icons.storage_outlined,
              label: inventory.available
                  ? 'Business storage'
                  : 'Indexed Business usage',
              value: usageValue,
            ),
          ],
        ),
        const SizedBox(height: 12),
        BusinessStorageInventoryCard(inventory: inventory),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Company profile',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    company.metadataProtected && company.metadataReadable
                        ? Icons.enhanced_encryption_outlined
                        : Icons.warning_amber_rounded,
                  ),
                  title: Text(privacyMessage),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: nameController,
                  enabled: labelsReadable && !busy,
                  decoration: const InputDecoration(
                    labelText: 'Company name',
                    prefixIcon: Icon(Icons.business_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: domainController,
                  enabled: labelsReadable && !busy,
                  decoration: const InputDecoration(
                    labelText: 'Domain',
                    prefixIcon: Icon(Icons.public_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (company.metadataProtected && company.metadataReadable)
                      OutlinedButton.icon(
                        onPressed: busy ? null : onRefreshProtectedLabels,
                        icon: const Icon(Icons.key_outlined),
                        label: const Text('Refresh member label access'),
                      ),
                    FilledButton.icon(
                      onPressed: busy || !labelsReadable ? null : onSave,
                      icon: const Icon(Icons.save_outlined),
                      label: Text(
                        company.metadataProtected
                            ? 'Save encrypted profile'
                            : 'Encrypt and save profile',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _StoragePolicyCard(
          policy: company.storagePolicy,
          busy: busy,
          onSave: onStoragePolicySave,
        ),
        const SizedBox(height: 12),
        _SecurityModelTile(company: company),
      ],
    );
  }
}

class BusinessStorageInventoryCard extends StatelessWidget {
  const BusinessStorageInventoryCard({super.key, required this.inventory});

  final CompanyStorageInventory inventory;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (icon, title, body, color) = switch ((
      inventory.available,
      inventory.status,
    )) {
      (false, _) => (
        Icons.schedule_outlined,
        'Business storage check is waiting',
        'RonikCloud will compare aggregate encrypted-object counts and sizes. '
            'File contents and names are never inspected.',
        colorScheme.onSurfaceVariant,
      ),
      (true, 'healthy') when inventory.complete => (
        Icons.verified_outlined,
        'Business storage matches',
        '${_counted(inventory.objectCount, 'encrypted storage object')} match the '
            'workspace index. Only aggregate counts and sizes are retained.',
        colorScheme.primary,
      ),
      (true, 'partial' || 'healthy') => (
        Icons.sync_outlined,
        'Business storage check is incomplete',
        'The bounded scan will continue automatically. No storage restriction '
            'is applied from an incomplete check.',
        colorScheme.tertiary,
      ),
      _ => (
        Icons.warning_amber_rounded,
        'Business storage needs reconciliation',
        '${_counted(inventory.orphanObjectCount, 'unindexed object')} and '
            '${_counted(inventory.missingObjectCount, 'missing object')} were '
            'counted. File names and contents were not inspected.',
        colorScheme.error,
      ),
    };
    return Card(
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(title),
        subtitle: Text(body),
      ),
    );
  }
}

String _counted(int count, String singular) =>
    '$count $singular${count == 1 ? '' : 's'}';

class _StoragePolicyCard extends StatefulWidget {
  const _StoragePolicyCard({
    required this.policy,
    required this.busy,
    required this.onSave,
  });

  final CompanyStoragePolicy policy;
  final bool busy;
  final ValueChanged<CompanyStoragePolicy> onSave;

  @override
  State<_StoragePolicyCard> createState() => _StoragePolicyCardState();
}

class _StoragePolicyCardState extends State<_StoragePolicyCard> {
  late bool _privateEnabled;
  late bool _sharedEnabled;
  late final TextEditingController _quotaController;

  @override
  void initState() {
    super.initState();
    _privateEnabled = widget.policy.privateStorageEnabledByDefault;
    _sharedEnabled = widget.policy.sharedStorageEnabled;
    _quotaController = TextEditingController(
      text: _quotaGbText(widget.policy.defaultPrivateQuotaBytes),
    );
  }

  @override
  void didUpdateWidget(covariant _StoragePolicyCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.policy != widget.policy) {
      _privateEnabled = widget.policy.privateStorageEnabledByDefault;
      _sharedEnabled = widget.policy.sharedStorageEnabled;
      _quotaController.text = _quotaGbText(
        widget.policy.defaultPrivateQuotaBytes,
      );
    }
  }

  @override
  void dispose() {
    _quotaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Storage policy',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              value: _privateEnabled,
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.lock_outline),
              title: const Text('Private company storage'),
              onChanged: widget.busy
                  ? null
                  : (value) {
                      setState(() {
                        _privateEnabled = value;
                      });
                    },
            ),
            SwitchListTile(
              value: _sharedEnabled,
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.folder_shared_outlined),
              title: const Text('Company shared storage'),
              onChanged: widget.busy
                  ? null
                  : (value) {
                      setState(() {
                        _sharedEnabled = value;
                      });
                    },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _quotaController,
              enabled: !widget.busy,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Default private quota (GB)',
                prefixIcon: Icon(Icons.speed_outlined),
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: widget.busy
                    ? null
                    : () {
                        widget.onSave(
                          CompanyStoragePolicy(
                            privateStorageEnabledByDefault: _privateEnabled,
                            sharedStorageEnabled: _sharedEnabled,
                            defaultPrivateQuotaBytes: _quotaGbBytes(
                              _quotaController.text,
                            ),
                          ),
                        );
                      },
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save policy'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BusinessMembersView extends StatefulWidget {
  const BusinessMembersView({
    super.key,
    required this.dashboard,
    required this.busy,
    required this.onAdd,
    required this.onEdit,
    required this.onRevokeInvitation,
    this.readOnly = false,
  });

  final CompanyDashboard dashboard;
  final bool busy;
  final VoidCallback onAdd;
  final ValueChanged<CompanyMember> onEdit;
  final ValueChanged<CompanyMember> onRevokeInvitation;
  final bool readOnly;

  @override
  State<BusinessMembersView> createState() => _BusinessMembersViewState();
}

enum _MemberFilter { all, active, invited, suspended, needsSetup, expired }

class _BusinessMembersViewState extends State<BusinessMembersView> {
  final _search = TextEditingController();
  _MemberFilter _filter = _MemberFilter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = widget.dashboard;
    final busy = widget.busy;
    final onAdd = widget.onAdd;
    final onEdit = widget.onEdit;
    final onRevokeInvitation = widget.onRevokeInvitation;
    final query = _search.text.trim().toLowerCase();
    final now = DateTime.now();
    final members = dashboard.members
        .where((member) {
          final matchesQuery =
              [member.label, member.email, member.invitationFingerprint]
                  .whereType<String>()
                  .any((value) => value.toLowerCase().contains(query));
          final matchesFilter = switch (_filter) {
            _MemberFilter.all => true,
            _MemberFilter.active => member.status == 'active',
            _MemberFilter.invited => member.status == 'invited',
            _MemberFilter.suspended => member.status == 'suspended',
            _MemberFilter.needsSetup =>
              member.status == 'active' && !member.encryptionReady,
            _MemberFilter.expired =>
              member.status == 'invited' &&
                  member.invitationExpiresAt != null &&
                  !member.invitationExpiresAt!.isAfter(now),
          };
          return matchesQuery && matchesFilter;
        })
        .toList(growable: false);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (!widget.readOnly)
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: busy ? null : onAdd,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Add user'),
            ),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Search users',
            hintText: 'Name, email or invitation fingerprint',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear user search',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(_search.clear),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (filter, label) in const [
              (_MemberFilter.all, 'All'),
              (_MemberFilter.active, 'Active'),
              (_MemberFilter.invited, 'Invited'),
              (_MemberFilter.suspended, 'Suspended'),
              (_MemberFilter.needsSetup, 'Needs setup'),
              (_MemberFilter.expired, 'Expired invitations'),
            ])
              ChoiceChip(
                label: Text(label),
                tooltip: filter == _MemberFilter.needsSetup
                    ? 'Active members who need encryption setup'
                    : null,
                selected: _filter == filter,
                onSelected: (_) => setState(() => _filter = filter),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Showing ${members.length} of ${dashboard.members.length} users in this directory',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        if (members.isEmpty)
          _EmptyInlineState(
            icon: Icons.people_outline,
            title: dashboard.members.isEmpty
                ? 'No company users'
                : 'No users match your search or filter',
          )
        else
          ...members.map(
            (member) => Card(
              child: ListTile(
                leading: CircleAvatar(child: Text(_avatarText(member.label))),
                title: Text(member.label),
                subtitle: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _InfoChip(
                      icon: Icons.admin_panel_settings_outlined,
                      label: _roleLabel(member.role),
                    ),
                    _InfoChip(
                      icon: Icons.verified_user_outlined,
                      label: _statusLabel(member.status),
                    ),
                    if (member.status == 'invited' &&
                        member.invitationExpiresAt != null)
                      _InfoChip(
                        icon:
                            member.invitationExpiresAt!.isBefore(DateTime.now())
                            ? Icons.timer_off_outlined
                            : Icons.schedule_outlined,
                        label:
                            member.invitationExpiresAt!.isBefore(DateTime.now())
                            ? 'Code expired'
                            : 'Code expires ${MaterialLocalizations.of(context).formatMediumDate(member.invitationExpiresAt!.toLocal())}',
                      ),
                    if (member.isLegacyInvitation)
                      const _InfoChip(
                        icon: Icons.warning_amber_rounded,
                        label: 'Legacy invite - suspend and recreate privately',
                      ),
                    for (final scope in member.accessScopes.take(3))
                      _InfoChip(
                        icon: Icons.hub_outlined,
                        label: _scopeLabel(scope),
                      ),
                    if (member.groupIds.isNotEmpty)
                      _InfoChip(
                        icon: Icons.groups_2_outlined,
                        label: '${member.groupIds.length} groups',
                      ),
                    _InfoChip(
                      icon: Icons.lock_outline,
                      label: _privateStorageLabel(member.storageOverride),
                    ),
                    _InfoChip(
                      icon: member.encryptionReady
                          ? Icons.enhanced_encryption_outlined
                          : Icons.warning_amber_rounded,
                      label: member.encryptionReady
                          ? 'Shared encryption ready'
                          : member.status == 'invited'
                          ? 'Waiting for code acceptance'
                          : 'Open workspace to enable encryption',
                    ),
                  ],
                ),
                trailing: widget.readOnly
                    ? null
                    : member.status == 'invited'
                    ? IconButton(
                        tooltip: 'Revoke invitation',
                        onPressed: busy
                            ? null
                            : () => onRevokeInvitation(member),
                        icon: const Icon(Icons.link_off_outlined),
                      )
                    : IconButton(
                        tooltip: 'Edit',
                        onPressed: busy ? null : () => onEdit(member),
                        icon: const Icon(Icons.tune_outlined),
                      ),
              ),
            ),
          ),
      ],
    );
  }
}

class BusinessGroupsView extends StatefulWidget {
  const BusinessGroupsView({
    super.key,
    required this.dashboard,
    required this.busy,
    required this.onAdd,
    required this.onEdit,
    required this.onRefreshProtectedLabels,
    required this.onDelete,
    this.readOnly = false,
  });

  final CompanyDashboard dashboard;
  final bool busy;
  final VoidCallback onAdd;
  final ValueChanged<CompanyGroup> onEdit;
  final ValueChanged<CompanyGroup> onRefreshProtectedLabels;
  final ValueChanged<CompanyGroup> onDelete;
  final bool readOnly;

  @override
  State<BusinessGroupsView> createState() => _BusinessGroupsViewState();
}

class _BusinessGroupsViewState extends State<BusinessGroupsView> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = widget.dashboard;
    final busy = widget.busy;
    final onAdd = widget.onAdd;
    final onEdit = widget.onEdit;
    final onDelete = widget.onDelete;
    final onRefreshProtectedLabels = widget.onRefreshProtectedLabels;
    final query = _search.text.trim().toLowerCase();
    final groups = dashboard.groups
        .where(
          (group) =>
              group.name.toLowerCase().contains(query) ||
              (group.description?.toLowerCase().contains(query) ?? false),
        )
        .toList(growable: false);
    final membersByUid = <String, CompanyMember>{
      for (final member in dashboard.members)
        if (member.uid != null) member.uid!: member,
    };
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (!widget.readOnly)
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: busy ? null : onAdd,
              icon: const Icon(Icons.group_add_outlined),
              label: const Text('Add group'),
            ),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Search groups',
            hintText: 'Group name or description',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear group search',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(_search.clear),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Showing ${groups.length} of ${dashboard.groups.length} groups in this directory',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        if (groups.isEmpty)
          _EmptyInlineState(
            icon: Icons.groups_2_outlined,
            title: dashboard.groups.isEmpty
                ? 'No company groups'
                : 'No groups match your search',
          )
        else
          ...groups.map((group) {
            final memberLabels = group.memberUids
                .map((uid) => membersByUid[uid]?.label ?? 'Company member')
                .take(4)
                .toList(growable: false);
            return Card(
              child: ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.groups_2_outlined),
                ),
                title: Text(group.name),
                subtitle: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _InfoChip(
                      icon: Icons.people_alt_outlined,
                      label: '${group.memberUids.length} users',
                    ),
                    _InfoChip(
                      icon: group.sharedStorageEnabled
                          ? Icons.folder_shared_outlined
                          : Icons.folder_off_outlined,
                      label: group.sharedStorageEnabled
                          ? 'Group storage on'
                          : 'Group storage off',
                    ),
                    _InfoChip(
                      icon: Icons.lock_outline,
                      label: _privateStorageLabel(group.storageOverride),
                    ),
                    _InfoChip(
                      icon: group.metadataProtected && group.metadataReadable
                          ? Icons.enhanced_encryption_outlined
                          : Icons.warning_amber_rounded,
                      label: !group.metadataProtected
                          ? 'Legacy label'
                          : group.metadataReadable
                          ? 'Encrypted label'
                          : 'Label key pending',
                    ),
                    if (memberLabels.isNotEmpty)
                      _InfoChip(
                        icon: Icons.badge_outlined,
                        label: memberLabels.join(', '),
                      ),
                  ],
                ),
                trailing: widget.readOnly
                    ? null
                    : PopupMenuButton<String>(
                        tooltip: 'Group actions',
                        enabled: !busy,
                        onSelected: (action) {
                          switch (action) {
                            case 'refresh':
                              onRefreshProtectedLabels(group);
                            case 'edit':
                              onEdit(group);
                            case 'delete':
                              onDelete(group);
                          }
                        },
                        itemBuilder: (_) => [
                          if (group.metadataProtected && group.metadataReadable)
                            const PopupMenuItem(
                              value: 'refresh',
                              child: Text('Refresh protected label access'),
                            ),
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('Edit group'),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete group'),
                          ),
                        ],
                      ),
              ),
            );
          }),
      ],
    );
  }
}

class BusinessAccessMetricsView extends StatelessWidget {
  const BusinessAccessMetricsView({super.key, required this.dashboard});

  final CompanyDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    if (!dashboard.accessPatternsAvailable) {
      return const _BusinessMetricsUnavailable();
    }
    final patterns = dashboard.accessPatterns;
    if (patterns.isEmpty) {
      return const _EmptyInlineState(
        icon: Icons.hub_outlined,
        title: 'No Business workspace activity',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const _BusinessPrivacyNotice(
          text:
              'These metrics include only this company’s encrypted private, shared, and group workspaces. Personal files, usage, and account activity are excluded.',
        ),
        if (!dashboard.accessPatternsComplete) ...[
          const SizedBox(height: 12),
          const Card(
            child: ListTile(
              leading: Icon(Icons.sync_outlined),
              title: Text('Business metrics are still being indexed'),
              subtitle: Text(
                'The bounded company scan will continue. Counts shown below may be incomplete.',
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('User')),
              DataColumn(label: Text('Role')),
              DataColumn(label: Text('Access')),
              DataColumn(label: Text('Business files'), numeric: true),
              DataColumn(label: Text('Business folders'), numeric: true),
              DataColumn(label: Text('Shared/group'), numeric: true),
              DataColumn(label: Text('Business usage')),
              DataColumn(label: Text('Last Business upload')),
            ],
            rows: patterns
                .map((pattern) {
                  final user =
                      pattern.memberIndex >= 0 &&
                          pattern.memberIndex < dashboard.members.length
                      ? dashboard.members[pattern.memberIndex].label
                      : 'Former company member';
                  return DataRow(
                    cells: [
                      DataCell(Text(user)),
                      DataCell(Text(_roleLabel(pattern.role))),
                      DataCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 260),
                          child: Text(
                            pattern.accessScopes.map(_scopeLabel).join(', '),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(Text('${pattern.fileCount}')),
                      DataCell(Text('${pattern.folderCount}')),
                      DataCell(Text('${pattern.sharedFileCount}')),
                      DataCell(Text(_formatBytes(pattern.usageBytes))),
                      DataCell(Text(_formatDate(pattern.lastFileUploadedAt))),
                    ],
                  );
                })
                .toList(growable: false),
          ),
        ),
      ],
    );
  }
}

class BusinessAuditLogView extends StatelessWidget {
  const BusinessAuditLogView({
    super.key,
    required this.dashboard,
    this.refreshing = false,
    this.onRefresh,
  });

  final CompanyDashboard dashboard;
  final bool refreshing;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    if (!dashboard.auditLogsAvailable) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.cloud_off_outlined),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Activity history unavailable',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'RonikCloud could not verify the Business '
                              'activity history. An unavailable history is '
                              'never shown as an empty history. Refresh before '
                              'relying on it for an access review.',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (onRefresh != null) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.tonalIcon(
                        onPressed: refreshing
                            ? null
                            : () => unawaited(onRefresh!()),
                        icon: refreshing
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh_rounded),
                        label: Text(refreshing ? 'Refreshing' : 'Refresh'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      );
    }

    final entries = <CompanyAuditLogEntry>[...dashboard.auditLogs]
      ..sort(
        (a, b) => (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
      );
    final memberLabels = <String, String>{
      for (final member in dashboard.members) member.id: member.label,
      for (final member in dashboard.members)
        if (member.uid != null) member.uid!: member.label,
    };
    final rows = <Widget>[
      const _BusinessPrivacyNotice(
        text:
            'Activity titles come from a fixed privacy-safe vocabulary. File '
            'names, folder names, company and group labels, comments, raw '
            'account identifiers, and provider error text are excluded.',
      ),
      if (!dashboard.auditLogsComplete)
        Card(
          child: ListTile(
            leading: const Icon(Icons.history_toggle_off_outlined),
            title: const Text('Showing recent activity'),
            subtitle: Text(
              'The latest ${entries.length} events are available. Older '
              'events may exist and are not represented in this view.',
            ),
          ),
        ),
      if (entries.isEmpty)
        const Card(
          child: ListTile(
            leading: Icon(Icons.receipt_long_outlined),
            title: Text('No recorded Business activity'),
            subtitle: Text('The verified activity history is currently empty.'),
          ),
        ),
      for (final entry in entries)
        Builder(
          builder: (context) {
            final actor =
                memberLabels[entry.actorMemberId] ??
                (entry.actorPresent ? 'Former company member' : null);
            final target =
                memberLabels[entry.targetMemberId] ??
                (entry.targetPresent ? 'Former or invited member' : null);
            return ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: Text(entry.title),
              subtitle: Text(
                [
                  if (actor != null) 'Actor: $actor',
                  if (target != null) 'Target: $target',
                  _formatDate(entry.createdAt),
                ].join('  |  '),
              ),
            );
          },
        ),
    ];
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) => rows[index],
    );
  }
}

class _BusinessMetricsUnavailable extends StatelessWidget {
  const _BusinessMetricsUnavailable();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: const [
        _BusinessPrivacyNotice(
          text:
              'Business metrics are waiting for the privacy-scoped server update. Personal workspace counts and account activity are intentionally not shown as a fallback.',
        ),
      ],
    );
  }
}

class _BusinessPrivacyNotice extends StatelessWidget {
  const _BusinessPrivacyNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: ListTile(
        leading: const Icon(Icons.privacy_tip_outlined),
        title: const Text('Business privacy boundary'),
        subtitle: Text(text),
      ),
    );
  }
}

class _SecurityModelTile extends StatelessWidget {
  const _SecurityModelTile({required this.company});

  final CompanyProfile company;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.enhanced_encryption_outlined),
        title: const Text('Storage and encryption boundary'),
        subtitle: Text(
          company.securityModel.isEmpty
              ? 'Files leave each device encrypted. Shared files use a random '
                    'file key wrapped separately for every authorized member. '
                    'Reconcile encrypted member access after membership changes.'
              : 'Files leave each device encrypted; shared file keys are '
                    'wrapped per authorized member. Company admins and service '
                    'operators do not receive storage secrets, encryption '
                    'passphrases, or decrypted file content. After membership '
                    'changes, an authorized device adds envelopes for new '
                    'members and rotates file contents and keys after removals.',
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 190,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: theme.textTheme.labelMedium),
                    const SizedBox(height: 4),
                    Text(value, style: theme.textTheme.titleLarge),
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

class _ScopeSelector extends StatelessWidget {
  const _ScopeSelector({required this.selected, required this.onChanged});

  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _scopeOptions
          .map((scope) {
            return FilterChip(
              selected: selected.contains(scope),
              label: Text(_scopeLabel(scope)),
              onSelected: (value) {
                final next = selected.toSet();
                if (value) {
                  next.add(scope);
                } else {
                  next.remove(scope);
                }
                if (next.isEmpty) {
                  next.add('personal_workspace');
                }
                onChanged(next);
              },
            );
          })
          .toList(growable: false),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _EmptyInlineState extends StatelessWidget {
  const _EmptyInlineState({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 38, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: theme.colorScheme.error, size: 42),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberEditDraft {
  const _MemberEditDraft({
    required this.role,
    required this.status,
    required this.permissions,
    required this.accessScopes,
    this.storageOverride = const CompanyMemberStorageOverride(),
  });

  final String role;
  final String status;
  final Map<String, bool> permissions;
  final List<String> accessScopes;
  final CompanyMemberStorageOverride storageOverride;
}

class _GroupEditDraft {
  const _GroupEditDraft({
    required this.name,
    required this.description,
    required this.memberUids,
    required this.sharedStorageEnabled,
    required this.storageOverride,
  });

  final String name;
  final String description;
  final List<String> memberUids;
  final bool sharedStorageEnabled;
  final CompanyMemberStorageOverride storageOverride;
}

const List<String> _roles = ['owner', 'admin', 'member', 'viewer'];
const List<String> _statuses = ['active', 'invited', 'suspended'];
const List<String> _scopeOptions = [
  'personal_workspace',
  'company_workspace',
  'shared_folders',
  'member_management',
  'audit_logs',
  'billing',
];
const List<String> _permissionKeys = [
  'manageCompanyProfile',
  'manageMembers',
  'managePermissions',
  'viewAuditLogs',
  'viewAccessPatterns',
  'uploadFiles',
  'downloadFiles',
  'shareFiles',
];

Map<String, bool> _defaultPermissionsForRole(String role) {
  final normalized = role.trim().toLowerCase();
  final isOwner = normalized == 'owner';
  final isAdmin = normalized == 'admin';
  final isMember = normalized == 'member';
  return <String, bool>{
    'manageCompanyProfile': isOwner || isAdmin,
    'manageMembers': isOwner || isAdmin,
    'managePermissions': isOwner || isAdmin,
    'viewAuditLogs': isOwner || isAdmin,
    'viewAccessPatterns': isOwner || isAdmin,
    'uploadFiles': isOwner || isAdmin || isMember,
    'downloadFiles': isOwner || isAdmin || isMember || normalized == 'viewer',
    'shareFiles': isOwner || isAdmin || isMember,
  };
}

List<String> _defaultScopesForRole(String role) {
  switch (role) {
    case 'owner':
    case 'admin':
      return const [
        'personal_workspace',
        'company_workspace',
        'member_management',
        'audit_logs',
      ];
    case 'viewer':
      return const ['company_workspace'];
    default:
      return const ['personal_workspace', 'company_workspace'];
  }
}

String _roleLabel(String role) {
  switch (role) {
    case 'owner':
      return 'Owner';
    case 'admin':
      return 'Admin';
    case 'viewer':
      return 'Viewer';
    default:
      return 'Member';
  }
}

String _statusLabel(String status) {
  switch (status) {
    case 'invited':
      return 'Invited';
    case 'suspended':
      return 'Suspended';
    default:
      return 'Active';
  }
}

String _scopeLabel(String scope) {
  switch (scope) {
    case 'personal_workspace':
      return 'Personal workspace';
    case 'company_workspace':
      return 'Company workspace';
    case 'shared_folders':
      return 'Shared folders';
    case 'member_management':
      return 'Member management';
    case 'audit_logs':
      return 'Audit logs';
    case 'billing':
      return 'Billing';
    default:
      return scope
          .split(RegExp(r'[_\s-]+'))
          .where((part) => part.isNotEmpty)
          .map((part) => part[0].toUpperCase() + part.substring(1))
          .join(' ');
  }
}

String _permissionLabel(String key) {
  switch (key) {
    case 'manageCompanyProfile':
      return 'Manage profile';
    case 'manageMembers':
      return 'Manage users';
    case 'managePermissions':
      return 'Manage permissions';
    case 'viewAuditLogs':
      return 'View logs';
    case 'viewAccessPatterns':
      return 'View access';
    case 'uploadFiles':
      return 'Upload';
    case 'downloadFiles':
      return 'Download';
    case 'shareFiles':
      return 'Share';
    default:
      return key;
  }
}

String _privateStorageModeFromOverride(bool? value) {
  if (value == true) {
    return 'enabled';
  }
  if (value == false) {
    return 'disabled';
  }
  return 'default';
}

bool? _privateStorageBoolFromMode(String mode) {
  switch (mode) {
    case 'enabled':
      return true;
    case 'disabled':
      return false;
    default:
      return null;
  }
}

String _quotaGbText(int? bytes) {
  if (bytes == null || bytes <= 0) {
    return '';
  }
  final gb = bytes / (1024 * 1024 * 1024);
  return gb == gb.roundToDouble()
      ? gb.toStringAsFixed(0)
      : gb.toStringAsFixed(1);
}

int? _quotaGbBytes(String value) {
  final normalized = value.trim().replaceAll(',', '.');
  if (normalized.isEmpty) {
    return null;
  }
  final gb = double.tryParse(normalized);
  if (gb == null || gb <= 0) {
    return null;
  }
  return (gb * 1024 * 1024 * 1024).round();
}

String _privateStorageLabel(CompanyMemberStorageOverride override) {
  final mode = override.privateStorageEnabled;
  final quota = override.privateQuotaBytes;
  final parts = <String>[
    if (mode == true)
      'Private on'
    else if (mode == false)
      'Private off'
    else
      'Default private',
    if (quota != null && quota > 0) _formatBytes(quota),
  ];
  return parts.join(' | ');
}

String _formatBytes(int bytes) {
  if (bytes <= 0) {
    return '0 B';
  }
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var index = 0;
  while (value >= 1024 && index < units.length - 1) {
    value /= 1024;
    index++;
  }
  final precision = value >= 10 || index == 0 ? 0 : 1;
  return '${value.toStringAsFixed(precision)} ${units[index]}';
}

String _formatDate(DateTime? value) {
  if (value == null) {
    return 'Never';
  }
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

String _avatarText(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '?';
  }
  return trimmed.substring(0, 1).toUpperCase();
}
