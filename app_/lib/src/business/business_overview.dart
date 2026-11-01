import 'package:flutter/material.dart';

import 'company_admin_service.dart';

enum BusinessAdminSection { overview, profile, users, groups, access, logs }

/// A summary of the loaded dashboard, never an assurance of recovery or security.
class BusinessOverview extends StatelessWidget {
  const BusinessOverview({
    super.key,
    required this.dashboard,
    required this.onOpenSection,
    this.onInvite,
    this.onOpenOperations,
    this.busy = false,
  });

  final CompanyDashboard dashboard;
  final ValueChanged<BusinessAdminSection> onOpenSection;
  final VoidCallback? onInvite;
  final VoidCallback? onOpenOperations;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final company = dashboard.company!;
    final active = dashboard.members.where((m) => m.status == 'active').length;
    final invited = dashboard.members
        .where((m) => m.status == 'invited')
        .length;
    final unready = dashboard.members
        .where((m) => m.status == 'active' && !m.encryptionReady)
        .length;
    final pendingSpaces =
        (company.reconciliation.pending ? 1 : 0) +
        dashboard.groups.where((g) => g.reconciliation.pending).length;
    final inventory = company.storageInventory;

    return ListView(
      key: const PageStorageKey('business-overview'),
      padding: const EdgeInsets.all(24),
      children: [
        Text('Your team’s workspace', style: theme.textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          'Manage company storage, bring your team in, and keep access up to date.',
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            if (onInvite != null)
              FilledButton.icon(
                onPressed: busy ? null : onInvite,
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: const Text('Invite a teammate'),
              ),
            OutlinedButton.icon(
              onPressed: () => onOpenSection(BusinessAdminSection.profile),
              icon: const Icon(Icons.storage_outlined),
              label: const Text('Manage storage'),
            ),
            if (onOpenOperations != null)
              OutlinedButton.icon(
                onPressed: onOpenOperations,
                icon: const Icon(Icons.support_agent_outlined),
                label: const Text('Support & recovery'),
              ),
          ],
        ),
        const SizedBox(height: 28),
        Text('In your directory', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ActionChip(
              avatar: const Icon(Icons.people_alt_outlined, size: 18),
              label: Text('$active active · $invited invited'),
              onPressed: () => onOpenSection(BusinessAdminSection.users),
            ),
            ActionChip(
              avatar: const Icon(Icons.groups_outlined, size: 18),
              label: Text('${dashboard.groups.length} groups'),
              onPressed: () => onOpenSection(BusinessAdminSection.groups),
            ),
          ],
        ),
        const SizedBox(height: 28),
        Text('Workspace setup', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        _OverviewTask(
          complete: company.metadataProtected && company.metadataReadable,
          title: 'Protect your company profile',
          body: !company.metadataProtected
              ? 'Save your company profile to encrypt its name and domain.'
              : !company.metadataReadable
              ? 'Ask an authorized member to refresh label access for this account.'
              : 'This device can read your encrypted company labels.',
          onTap: () => onOpenSection(BusinessAdminSection.profile),
        ),
        _OverviewTask(
          complete: active > 1,
          title: 'Bring your team in',
          body: active > 1
              ? 'Review roles and permissions as your team changes.'
              : invited > 0
              ? 'Share each one-time code privately. Teammates claim it in their Business account.'
              : 'Invite a teammate with a one-time code and choose their access.',
          onTap: () => onOpenSection(BusinessAdminSection.users),
        ),
        _OverviewTask(
          complete: dashboard.groups.isNotEmpty,
          title: 'Organize shared work',
          body: dashboard.groups.isEmpty
              ? 'Optionally create a group for a department, project, or client team.'
              : 'Review group membership and choose which groups have shared storage.',
          onTap: () => onOpenSection(BusinessAdminSection.groups),
        ),
        const SizedBox(height: 24),
        Text('Access and storage checks', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        if (company.status != 'active')
          _OverviewNotice(
            icon: Icons.business_outlined,
            title: 'Company status: ${company.status}',
            body:
                'Review your company status before bringing more people into the workspace.',
            onTap: () => onOpenSection(BusinessAdminSection.profile),
          ),
        if (unready > 0)
          _OverviewNotice(
            icon: Icons.key_outlined,
            title:
                '$unready active ${unready == 1 ? 'member needs' : 'members need'} encryption setup',
            body:
                'Ask them to open their workspace on a trusted device. Account access alone does not unlock shared files.',
            onTap: () => onOpenSection(BusinessAdminSection.users),
          ),
        if (pendingSpaces > 0)
          _OverviewNotice(
            icon: Icons.lock_reset_outlined,
            title:
                '$pendingSpaces shared ${pendingSpaces == 1 ? 'space needs' : 'spaces need'} access reconciliation',
            body:
                'Use the follow-up banner in your Business workspace to open each affected space from a trusted member device.',
            onTap: () => onOpenSection(BusinessAdminSection.groups),
          ),
        _OverviewNotice(
          icon: inventory.healthy
              ? Icons.fact_check_outlined
              : Icons.info_outline,
          title: inventory.healthy
              ? 'Storage inventory matches'
              : inventory.needsAttention
              ? 'Review storage inventory differences'
              : 'Storage inventory is not yet confirmed',
          body: inventory.healthy
              ? 'The last complete check matched aggregate object counts and sizes. This is not a restore test.'
              : inventory.needsAttention
              ? 'Open the profile for the latest aggregate storage check and reconciliation details.'
              : 'A missing or incomplete check cannot confirm that stored objects match the file index.',
          onTap: () => onOpenSection(BusinessAdminSection.profile),
        ),
        const SizedBox(height: 24),
        Text('Review access', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'Check who can use your shared spaces and review recorded administrative changes.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => onOpenSection(BusinessAdminSection.access),
              icon: const Icon(Icons.hub_outlined),
              label: const Text('Review file access'),
            ),
            OutlinedButton.icon(
              onPressed: () => onOpenSection(BusinessAdminSection.logs),
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('View audit log'),
            ),
          ],
        ),
      ],
    );
  }
}

class _OverviewTask extends StatelessWidget {
  const _OverviewTask({
    required this.complete,
    required this.title,
    required this.body,
    required this.onTap,
  });

  final bool complete;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(vertical: 8),
    leading: Icon(
      complete ? Icons.check_circle_outline : Icons.radio_button_unchecked,
      color: complete ? Theme.of(context).colorScheme.primary : null,
    ),
    title: Text(title),
    subtitle: Text(body),
    trailing: const Icon(Icons.chevron_right),
    onTap: onTap,
  );
}

class _OverviewNotice extends StatelessWidget {
  const _OverviewNotice({
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(vertical: 8),
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(body),
    trailing: const Icon(Icons.chevron_right),
    onTap: onTap,
  );
}
