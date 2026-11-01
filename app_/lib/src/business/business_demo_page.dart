import 'package:flutter/material.dart';

import '../shared/app_page_title.dart';
import 'business_overview.dart';
import 'business_operations_page.dart';
import 'business_operations_service.dart';
import 'company_admin_page.dart';
import 'company_admin_service.dart';

/// Public, local-only sample. No Firebase clients, accounts, files or writes.
class BusinessDemoPage extends StatelessWidget {
  const BusinessDemoPage({super.key, required this.onCreateAccount});

  final VoidCallback onCreateAccount;

  @override
  Widget build(BuildContext context) {
    final dashboard = _sampleDashboard;
    return DefaultTabController(
      length: BusinessAdminSection.values.length,
      child: Scaffold(
        appBar: AppBar(title: const Text('Sample Business workspace')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Northstar Studio',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Read-only sample data. Explore the administration tools without an account. No real files, people, or storage are connected.',
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: onCreateAccount,
                          icon: const Icon(Icons.add_business_outlined),
                          label: const Text('Create your Business account'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              body: Column(
                children: [
                  const TabBar(
                    isScrollable: true,
                    tabs: [
                      Tab(text: 'Overview'),
                      Tab(text: 'Profile'),
                      Tab(text: 'Users'),
                      Tab(text: 'Groups'),
                      Tab(text: 'Access'),
                      Tab(text: 'Logs'),
                    ],
                  ),
                  Expanded(
                    child: Builder(
                      builder: (tabContext) => TabBarView(
                        children: [
                          BusinessOverview(
                            dashboard: dashboard,
                            onOpenOperations: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => BusinessOperationsPage(
                                  sample: true,
                                  service: BusinessOperationsService(
                                    callable: (name, _) async => switch (name) {
                                      'getBusinessOperationsState' => {
                                        'guaranteeActive': false,
                                        'firstHumanResponseHours': 8,
                                      },
                                      'listBusinessSupportTickets' => {
                                        'tickets': [
                                          {
                                            'id': 'sample-ticket',
                                            'kind': 'recovery',
                                            'priority': 'normal',
                                            'status': 'answered',
                                            'description':
                                                'Example: help restoring a retained deleted file.',
                                            'humanResponse':
                                                'Example response: restore the retained encrypted version, then verify the read on your trusted device.',
                                          },
                                        ],
                                      },
                                      'getBusinessBillingState' => {
                                        'isOwner': true,
                                        'status': 'active',
                                        'offer': {
                                          'offerHash': 'sample-offer',
                                          'costScheduleReference':
                                              'illustrative-schedule',
                                          'costScheduleText':
                                              'Illustrative only: this month has USD 10 of approved attributable service costs. Your real schedule must disclose its actual rates and cost allocation before acceptance.',
                                          'capacityBytesPerMember': 1073741824,
                                          'collectionTerms':
                                              'Example: monthly payment in arrears, a USD 6 minimum total, with higher service subtotals calculated as approved cost divided by 0.50. Applicable taxes are separate. The real authorization discloses UTC periods, cancellation and payment handling.',
                                        },
                                        'invoices': [
                                          {
                                            'period': '2026-09',
                                            'status': 'paid',
                                            'costUsdMicros': 10000000,
                                            'serviceSubtotalCents': 2000,
                                            'totalCents': 2400,
                                          },
                                        ],
                                      },
                                      'listBusinessRecoveryFiles' => {
                                        'files': [
                                          {
                                            'id': 'sample-retained-file',
                                            'state': 'trashed',
                                            'bytes': 1048576,
                                            'storageScope': 'company_shared',
                                          },
                                        ],
                                      },
                                      'listBusinessRecoveryOperations' => {
                                        'operations': [
                                          {
                                            'id': 'sample-restore',
                                            'fileId': 'sample-restored-file',
                                            'status': 'restored',
                                            'verification':
                                                'customer_device_required',
                                          },
                                        ],
                                      },
                                      _ =>
                                        throw const BusinessOperationsException(),
                                    },
                                  ),
                                ),
                              ),
                            ),
                            onOpenSection: (section) => DefaultTabController.of(
                              tabContext,
                            ).animateTo(section.index),
                          ),
                          _SampleProfile(dashboard: dashboard),
                          BusinessMembersView(
                            dashboard: dashboard,
                            busy: false,
                            readOnly: true,
                            onAdd: _ignore,
                            onEdit: (_) {},
                            onRevokeInvitation: (_) {},
                          ),
                          BusinessGroupsView(
                            dashboard: dashboard,
                            busy: false,
                            readOnly: true,
                            onAdd: _ignore,
                            onEdit: (_) {},
                            onRefreshProtectedLabels: (_) {},
                            onDelete: (_) {},
                          ),
                          BusinessAccessMetricsView(dashboard: dashboard),
                          BusinessAuditLogView(dashboard: dashboard),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ).withAppPageTitle('Sample workspace | RonikCloud Business');
  }
}

void _ignore() {}

class _SampleProfile extends StatelessWidget {
  const _SampleProfile({required this.dashboard});
  final CompanyDashboard dashboard;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text(
        'Storage your team can manage',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 16),
      const ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.folder_shared_outlined),
        title: Text('Company and group spaces'),
        subtitle: Text(
          'Administrators choose shared storage, private storage defaults, and member or group quota overrides.',
        ),
      ),
      const ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.key_outlined),
        title: Text('Access belongs to your team'),
        subtitle: Text(
          'Invite people with private one-time codes, set roles and permissions, and verify recipient keys on trusted devices.',
        ),
      ),
      const SizedBox(height: 16),
      BusinessStorageInventoryCard(
        inventory: dashboard.company!.storageInventory,
      ),
      const SizedBox(height: 28),
      Text(
        'Plan backup and recovery before rollout',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 12),
      const Text(
        'Persistent folder backup currently runs on Windows. Individual file uploads remain available on supported cloud clients; iOS Photo Library backup has its own authorization flow. Linux currently opens the browser client.',
      ),
      const SizedBox(height: 12),
      const Text(
        'Keep your encryption recovery information safe and test recovery on a trusted customer device before relying on it. A matching storage inventory does not prove that files can be restored.',
      ),
      const SizedBox(height: 12),
      const Text(
        'An active paid subscription is required for Business. Review the storage capacity, price, and billing period shown during account setup.',
      ),
    ],
  );
}

final _sampleDashboard = CompanyDashboard(
  canCreate: false,
  canManage: true,
  company: const CompanyProfile(
    id: 'sample-company',
    name: 'Northstar Studio',
    metadataProtected: true,
    storageInventory: CompanyStorageInventory(
      available: true,
      status: 'healthy',
      complete: true,
      objectCount: 24,
      observedBytes: 125829120,
      metadataUsageBytes: 125829120,
    ),
  ),
  members: [
    const CompanyMember(
      id: 'sample-owner',
      uid: 'sample-owner',
      displayName: 'Alex Morgan',
      role: 'owner',
      encryptionReady: true,
      accessScopes: ['company_workspace'],
      groupIds: ['sample-design'],
    ),
    const CompanyMember(
      id: 'sample-member',
      uid: 'sample-member',
      displayName: 'Sam Rivera',
      encryptionReady: true,
      accessScopes: ['company_workspace'],
      groupIds: ['sample-design'],
    ),
    const CompanyMember(
      id: 'sample-setup',
      uid: 'sample-setup',
      displayName: 'Jamie Chen',
      accessScopes: ['company_workspace'],
    ),
    CompanyMember(
      id: 'sample-invite',
      status: 'invited',
      invitationFingerprint: 'DEMO123456',
      invitationExpiresAt: DateTime.utc(2099, 1, 1),
      accessScopes: const ['company_workspace'],
    ),
  ],
  groups: const [
    CompanyGroup(
      id: 'sample-design',
      name: 'Design team',
      description: 'A shared space for the project team.',
      memberUids: ['sample-owner', 'sample-member'],
      metadataProtected: true,
    ),
    CompanyGroup(
      id: 'sample-client',
      name: 'Client projects',
      description: 'Keep project access separate from the whole company.',
      memberUids: ['sample-owner'],
      metadataProtected: true,
    ),
  ],
  accessPatternsAvailable: true,
  accessPatternsComplete: true,
  accessPatterns: const [
    CompanyAccessPattern(
      memberIndex: 0,
      role: 'owner',
      fileCount: 16,
      folderCount: 3,
      sharedFileCount: 12,
      usageBytes: 83886080,
      accessScopes: ['company_workspace'],
    ),
    CompanyAccessPattern(
      memberIndex: 1,
      fileCount: 8,
      folderCount: 2,
      sharedFileCount: 8,
      usageBytes: 41943040,
      accessScopes: ['company_workspace'],
    ),
  ],
  auditLogsAvailable: true,
  auditLogsComplete: true,
  auditLogs: const [
    CompanyAuditLogEntry(
      id: 'sample-event-2',
      action: 'company.member_invited',
      title: 'Company user invited',
      actorMemberId: 'sample-owner',
      actorPresent: true,
    ),
    CompanyAuditLogEntry(
      id: 'sample-event-1',
      action: 'company.group_created',
      title: 'Company group created',
      actorMemberId: 'sample-owner',
      actorPresent: true,
    ),
  ],
);
