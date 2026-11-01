part of 'workspace_home_page.dart';

class _CompactStorageSummary extends StatelessWidget {
  const _CompactStorageSummary({
    required this.usedBytes,
    required this.totalBytes,
    required this.hasLimit,
    required this.displayMode,
    this.limitPending = false,
    this.planLabel,
    this.emphasized = false,
  });

  final double usedBytes;
  final double totalBytes;
  final bool hasLimit;
  final bool limitPending;
  final _StorageDisplayMode displayMode;
  final String? planLabel;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    if (!hasLimit && usedBytes <= 0) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final metrics = _storageUsageMetrics(
      usedBytes,
      totalBytes,
      displayMode,
      hasLimit: hasLimit,
      planLabel: planLabel,
      limitPending: limitPending,
    );
    final capacityKnown = hasLimit && totalBytes.isFinite && totalBytes > 0;
    final usedLabel = _formatStorageValue(usedBytes);
    final usageLabel = capacityKnown
        ? '$usedLabel / ${_formatStorageValue(totalBytes)}'
        : '$usedLabel used';
    final percentageLabel = limitPending
        ? 'Syncing...'
        : capacityKnown && displayMode == _StorageDisplayMode.percentage
        ? metrics.badgeText
        : null;
    final textStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurface,
    );

    return Semantics(
      label: 'Storage usage',
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: emphasized ? 16 : 0,
          vertical: 8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(usageLabel, style: textStyle)),
                if (percentageLabel != null) ...[
                  const SizedBox(width: 12),
                  Text(percentageLabel, style: textStyle),
                ],
              ],
            ),
            if (capacityKnown || limitPending) ...[
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: limitPending ? null : metrics.progress,
                minHeight: 3,
                borderRadius: BorderRadius.circular(2),
                backgroundColor: theme.colorScheme.outlineVariant,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class EncryptionPasswordException implements Exception {
  const EncryptionPasswordException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'EncryptionPasswordException';
}

enum _WorkspaceWalkthroughAction { completed, skipped }

class _WorkspaceWalkthroughStep {
  const _WorkspaceWalkthroughStep({
    required this.icon,
    required this.title,
    required this.description,
    required this.points,
  });

  final IconData icon;
  final String title;
  final String description;
  final List<String> points;
}

class _WorkspaceWalkthroughDialog extends StatefulWidget {
  const _WorkspaceWalkthroughDialog({required this.steps});

  final List<_WorkspaceWalkthroughStep> steps;

  @override
  State<_WorkspaceWalkthroughDialog> createState() =>
      _WorkspaceWalkthroughDialogState();
}

class _WorkspaceWalkthroughDialogState
    extends State<_WorkspaceWalkthroughDialog> {
  late final PageController _controller;
  late final List<GlobalKey> _navigationKeys;
  final Set<String> _checkedPoints = <String>{};
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    _navigationKeys = List<GlobalKey>.generate(
      widget.steps.length,
      (_) => GlobalKey(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _goToStep(int index) async {
    if (index < 0 || index >= widget.steps.length || index == _currentIndex) {
      return;
    }
    await _controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _revealNavigationTile(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || index < 0 || index >= _navigationKeys.length) {
        return;
      }
      final tileContext = _navigationKeys[index].currentContext;
      if (tileContext == null) {
        return;
      }
      unawaited(
        Scrollable.ensureVisible(
          tileContext,
          alignment: 0.5,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }

  String _pointKey(int stepIndex, int pointIndex) => '$stepIndex:$pointIndex';

  void _togglePoint(int stepIndex, int pointIndex) {
    final key = _pointKey(stepIndex, pointIndex);
    setState(() {
      if (!_checkedPoints.add(key)) {
        _checkedPoints.remove(key);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final steps = widget.steps;
    final isLastStep = _currentIndex == steps.length - 1;
    final viewport = MediaQuery.sizeOf(context);
    final compact = viewport.width < 520 || viewport.height < 660;
    final horizontalInset = viewport.width < 600 ? 12.0 : 24.0;
    final verticalInset = viewport.height < 700 ? 12.0 : 24.0;
    final dialogWidth = min(
      560.0,
      max(0.0, viewport.width - horizontalInset * 2),
    );
    final dialogHeight = min(
      720.0,
      max(0.0, viewport.height - verticalInset * 2),
    );
    final contentPadding = compact ? 14.0 : 20.0;
    final sectionSpacing = compact ? 12.0 : 20.0;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: horizontalInset,
        vertical: verticalInset,
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Padding(
          padding: EdgeInsets.all(contentPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Workspace tour',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Swipe, use the tabs, and tap each tip as you try it.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.of(
                        context,
                      ).pop(_WorkspaceWalkthroughAction.skipped);
                    },
                    child: const Text('Skip'),
                  ),
                ],
              ),
              SizedBox(height: compact ? 10 : 16),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var index = 0; index < steps.length; index++) ...[
                      if (index > 0) const SizedBox(width: 10),
                      _WorkspaceWalkthroughNavTile(
                        key: _navigationKeys[index],
                        step: steps[index],
                        index: index,
                        isSelected: index == _currentIndex,
                        compact: compact,
                        onTap: () => unawaited(_goToStep(index)),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(height: sectionSpacing),
              Semantics(
                label:
                    'Tour progress, step ${_currentIndex + 1} of ${steps.length}',
                child: LinearProgressIndicator(
                  value: (_currentIndex + 1) / steps.length,
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              SizedBox(height: compact ? 10 : 14),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: steps.length,
                  onPageChanged: (index) {
                    setState(() {
                      _currentIndex = index;
                    });
                    _revealNavigationTile(index);
                  },
                  itemBuilder: (context, index) {
                    final step = steps[index];
                    return SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            step.title,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            step.description,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.35,
                            ),
                          ),
                          SizedBox(height: sectionSpacing),
                          Container(
                            width: double.infinity,
                            padding: EdgeInsets.all(compact ? 14 : 18),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: theme.colorScheme.outlineVariant
                                    .withValues(alpha: 0.45),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color:
                                            theme.colorScheme.primaryContainer,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      alignment: Alignment.center,
                                      child: Icon(
                                        step.icon,
                                        size: 20,
                                        color: theme
                                            .colorScheme
                                            .onPrimaryContainer,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Try it as you go',
                                            style: theme.textTheme.titleMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${List<int>.generate(step.points.length, (pointIndex) => pointIndex).where((pointIndex) => _checkedPoints.contains(_pointKey(index, pointIndex))).length} of ${step.points.length} tips checked',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  color: theme
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                for (
                                  var pointIndex = 0;
                                  pointIndex < step.points.length;
                                  pointIndex++
                                )
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Semantics(
                                      button: true,
                                      toggled: _checkedPoints.contains(
                                        _pointKey(index, pointIndex),
                                      ),
                                      label:
                                          'Tour tip ${pointIndex + 1}: ${step.points[pointIndex]}',
                                      child: InkWell(
                                        key: ValueKey(
                                          'workspace-tour-point-$index-$pointIndex',
                                        ),
                                        onTap: () =>
                                            _togglePoint(index, pointIndex),
                                        borderRadius: BorderRadius.circular(8),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 8,
                                          ),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 1,
                                                ),
                                                child: AnimatedSwitcher(
                                                  duration: const Duration(
                                                    milliseconds: 160,
                                                  ),
                                                  child: Icon(
                                                    _checkedPoints.contains(
                                                          _pointKey(
                                                            index,
                                                            pointIndex,
                                                          ),
                                                        )
                                                        ? Icons
                                                              .check_circle_rounded
                                                        : Icons
                                                              .radio_button_unchecked_rounded,
                                                    key: ValueKey(
                                                      _checkedPoints.contains(
                                                        _pointKey(
                                                          index,
                                                          pointIndex,
                                                        ),
                                                      ),
                                                    ),
                                                    size: 20,
                                                    color: theme
                                                        .colorScheme
                                                        .primary,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Text(
                                                  step.points[pointIndex],
                                                  style: theme
                                                      .textTheme
                                                      .bodyMedium
                                                      ?.copyWith(height: 1.35),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              SizedBox(height: compact ? 8 : 12),
              Row(
                children: [
                  if (_currentIndex > 0)
                    OutlinedButton(
                      onPressed: () => unawaited(_goToStep(_currentIndex - 1)),
                      child: const Text('Back'),
                    )
                  else
                    const SizedBox(width: 72),
                  const Spacer(),
                  Text(
                    '${_currentIndex + 1}/${steps.length}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () {
                      if (isLastStep) {
                        Navigator.of(
                          context,
                        ).pop(_WorkspaceWalkthroughAction.completed);
                        return;
                      }
                      unawaited(_goToStep(_currentIndex + 1));
                    },
                    child: Text(isLastStep ? 'Finish' : 'Next'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkspaceWalkthroughNavTile extends StatelessWidget {
  const _WorkspaceWalkthroughNavTile({
    super.key,
    required this.step,
    required this.index,
    required this.isSelected,
    required this.compact,
    required this.onTap,
  });

  final _WorkspaceWalkthroughStep step;
  final int index;
  final bool isSelected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backgroundColor = isSelected
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerLowest;
    final foregroundColor = isSelected
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurfaceVariant;
    final tileSize = compact ? const Size(92, 92) : const Size(108, 116);
    final iconSize = compact ? 34.0 : 42.0;

    return Semantics(
      button: true,
      selected: isSelected,
      label: 'Tour step ${index + 1} of ${step.title}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: tileSize.width,
          height: tileSize.height,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 12,
            vertical: compact ? 8 : 12,
          ),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? theme.colorScheme.primary.withValues(alpha: 0.35)
                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : const <BoxShadow>[],
          ),
          child: Column(
            children: [
              Container(
                width: iconSize,
                height: iconSize,
                decoration: BoxDecoration(
                  color: isSelected
                      ? theme.colorScheme.surface.withValues(alpha: 0.9)
                      : theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Icon(
                  step.icon,
                  size: compact ? 19 : 22,
                  color: foregroundColor,
                ),
              ),
              SizedBox(height: compact ? 6 : 8),
              Expanded(
                child: Center(
                  child: Text(
                    '${index + 1}. ${step.title}',
                    textAlign: TextAlign.center,
                    maxLines: compact ? 2 : 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: foregroundColor,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegalAcceptanceChecklist extends StatelessWidget {
  const _LegalAcceptanceChecklist({
    required this.acceptedTermsAndUse,
    required this.acknowledgedPrivacyAndPolicies,
    required this.productUpdatesOptIn,
    required this.enabled,
    required this.onAcceptedTermsAndUseChanged,
    required this.onAcknowledgedPrivacyAndPoliciesChanged,
    required this.onProductUpdatesOptInChanged,
    required this.onOpenDocument,
  });

  final bool acceptedTermsAndUse;
  final bool acknowledgedPrivacyAndPolicies;
  final bool productUpdatesOptIn;
  final bool enabled;
  final ValueChanged<bool> onAcceptedTermsAndUseChanged;
  final ValueChanged<bool> onAcknowledgedPrivacyAndPoliciesChanged;
  final ValueChanged<bool> onProductUpdatesOptInChanged;
  final ValueChanged<LegalDocument> onOpenDocument;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
        color: colorScheme.surfaceContainerLow,
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: acceptedTermsAndUse,
              onChanged: enabled
                  ? (value) => onAcceptedTermsAndUseChanged(value ?? false)
                  : null,
              title: const Text(
                'I agree to the Terms of Service and Acceptable Use Policy.',
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: acknowledgedPrivacyAndPolicies,
              onChanged: enabled
                  ? (value) =>
                        onAcknowledgedPrivacyAndPoliciesChanged(value ?? false)
                  : null,
              title: const Text(
                'I acknowledge the Privacy Policy, Cancellation and Refund Policy, Data Retention Policy, and Subprocessors list.',
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: productUpdatesOptIn,
              onChanged: enabled
                  ? (value) => onProductUpdatesOptInChanged(value ?? false)
                  : null,
              title: const Text(
                'Send me product updates, release notes, and service news.',
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 4,
                children: [
                  for (final document in LegalDocuments.all)
                    TextButton(
                      onPressed: enabled
                          ? () => onOpenDocument(document)
                          : null,
                      child: Text(document.title),
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

class _WorkspaceLoadingBanner extends StatelessWidget {
  const _WorkspaceLoadingBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Loading your workspace...',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceHeader extends StatelessWidget {
  const _WorkspaceHeader({
    required this.name,
    required this.email,
    required this.onOpenSettings,
    required this.onSignOut,
    required this.onManageSubscription,
    required this.onDeleteAccount,
    this.showAccountManagement = true,
    required this.usedBytes,
    required this.totalBytes,
    required this.hasLimit,
    required this.limitPending,
    required this.storageLocation,
    required this.searchController,
    required this.onSearchChanged,
    required this.onSearchClear,
    required this.pathItems,
    required this.onPathNavigate,
    required this.tileDensity,
    this.planLabel,
    this.displayMode = _StorageDisplayMode.percentage,
    this.sectionTitle,
    this.accountOnly = false,
    this.hideAccount = false,
  });

  final bool accountOnly;
  final bool hideAccount;
  final String name;
  final String? sectionTitle;
  final String email;
  final VoidCallback onOpenSettings;
  final VoidCallback onSignOut;
  final VoidCallback onManageSubscription;
  final VoidCallback onDeleteAccount;
  final bool showAccountManagement;
  final double usedBytes;
  final double totalBytes;
  final bool hasLimit;
  final bool limitPending;
  final _StorageCapacityLocation storageLocation;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearchClear;
  final List<_WorkspacePathItem> pathItems;
  final ValueChanged<String?> onPathNavigate;
  final _WorkspaceTileDensity tileDensity;
  final String? planLabel;
  final _StorageDisplayMode displayMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trimmedName = name.trim();
    final trimmedEmail = email.trim();
    final seed = trimmedName.isNotEmpty ? trimmedName : trimmedEmail;
    final resolvedPlanLabel = planLabel?.trim().isNotEmpty == true
        ? planLabel!.trim()
        : (hasLimit ? 'Storage plan' : 'Unlimited storage');
    final compactEmail = isUsernameOnlyAuthEmail(trimmedEmail)
        ? trimmedEmail.split('@').first
        : _compactEmailLabel(trimmedEmail);
    final compactPlanLabel = _compactPlanLabel(resolvedPlanLabel);
    final showHeaderStorage =
        storageLocation == _StorageCapacityLocation.header;

    return Padding(
      padding: accountOnly
          ? const EdgeInsets.symmetric(vertical: 12)
          : const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!hideAccount)
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                PopupMenuButton<_AccountMenuAction>(
                  tooltip: trimmedName.isNotEmpty ? trimmedName : trimmedEmail,
                  offset: const Offset(0, 48),
                  onSelected: (value) {
                    switch (value) {
                      case _AccountMenuAction.signOut:
                        LoginPasswordVault.instance.clear();
                        onSignOut();
                        break;
                      case _AccountMenuAction.manageSubscription:
                        onManageSubscription();
                        break;
                      case _AccountMenuAction.deleteAccount:
                        onDeleteAccount();
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    if (showAccountManagement) ...[
                      const PopupMenuItem<_AccountMenuAction>(
                        value: _AccountMenuAction.manageSubscription,
                        child: Row(
                          children: [
                            Icon(Icons.credit_card, size: 20),
                            SizedBox(width: 12),
                            Text('Manage subscription'),
                          ],
                        ),
                      ),
                      const PopupMenuItem<_AccountMenuAction>(
                        value: _AccountMenuAction.deleteAccount,
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_forever,
                              size: 20,
                              color: Colors.red,
                            ),
                            SizedBox(width: 12),
                            Text(
                              selfServiceAccountDeletionEnabled
                                  ? 'Delete account'
                                  : 'Request account closure',
                              style: TextStyle(color: Colors.red),
                            ),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(),
                    ],
                    const PopupMenuItem<_AccountMenuAction>(
                      value: _AccountMenuAction.signOut,
                      child: Row(
                        children: [
                          Icon(Icons.logout, size: 20),
                          SizedBox(width: 12),
                          Text('Sign out'),
                        ],
                      ),
                    ),
                  ],
                  child: Container(
                    width: 44,
                    height: 44,
                    padding: const EdgeInsets.all(6),
                    child: CustomPaint(
                      painter: _PixelArtPainter(
                        seed,
                        theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (compactEmail.isNotEmpty) ...[
                        Text(
                          compactEmail,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                      ],
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          Text(
                            compactPlanLabel,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (limitPending) const Text('Syncing'),
                        ],
                      ),
                    ],
                  ),
                ),
                if (!accountOnly) const SizedBox(width: 8),
                if (!accountOnly)
                  IconButton(
                    onPressed: onOpenSettings,
                    icon: const Icon(Icons.tune_rounded),
                    tooltip: 'Workspace settings',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(
                      width: 40,
                      height: 40,
                    ),
                  ),
              ],
            ),
          if (!accountOnly && !hideAccount) const SizedBox(height: 14),
          if (!accountOnly)
            LayoutBuilder(
              builder: (context, constraints) {
                if (sectionTitle != null) {
                  return Text(
                    sectionTitle!,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  );
                }
                final pathBar = _WorkspacePathBar(
                  items: pathItems,
                  tileDensity: tileDensity,
                  onNavigate: onPathNavigate,
                );
                final searchBar = _WorkspaceSearchBar(
                  controller: searchController,
                  onChanged: onSearchChanged,
                  onClear: onSearchClear,
                );
                if (constraints.maxWidth < 720) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [pathBar, const SizedBox(height: 10), searchBar],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: 180,
                        maxWidth: 420,
                      ),
                      child: pathBar,
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: searchBar),
                  ],
                );
              },
            ),
          if (!accountOnly && showHeaderStorage) ...[
            const SizedBox(height: 16),
            _CompactStorageSummary(
              usedBytes: usedBytes,
              totalBytes: totalBytes,
              hasLimit: hasLimit,
              limitPending: limitPending,
              displayMode: displayMode,
              planLabel: planLabel,
            ),
          ],
        ],
      ),
    );
  }
}

String _compactEmailLabel(String email) {
  final trimmed = email.trim();
  if (trimmed.isEmpty) {
    return '';
  }

  final atIndex = trimmed.indexOf('@');
  if (atIndex <= 0 || atIndex >= trimmed.length - 1) {
    return trimmed;
  }

  final local = trimmed.substring(0, atIndex);
  final domain = trimmed.substring(atIndex + 1);
  final compactLocal = local.length <= 4
      ? local
      : '${local.substring(0, 4)}...';
  final compactDomain = domain.length <= 12
      ? domain
      : '${domain.substring(0, 12)}...';
  return '$compactLocal@$compactDomain';
}

String _compactPlanLabel(String label) {
  final trimmed = label.trim();
  if (trimmed.isEmpty) {
    return 'Plan';
  }

  final lower = trimmed.toLowerCase();
  if (lower.contains('unlimited')) {
    return 'Unlimited';
  }
  if (lower.contains('enterprise')) {
    return 'Enterprise';
  }
  if (lower.contains('business')) {
    return 'Business';
  }
  if (lower.contains('premium')) {
    return 'Premium';
  }
  if (lower.contains('basic')) {
    return 'Basic';
  }
  if (lower.contains('free')) {
    return 'Free';
  }
  if (lower.contains('plus')) {
    return 'Plus';
  }
  if (lower.contains('pro')) {
    return 'Pro';
  }

  final words = trimmed
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (words.length <= 2) {
    return trimmed;
  }
  return words.take(2).join(' ');
}

class _PixelArtPainter extends CustomPainter {
  _PixelArtPainter(this.seed, this.color);
  final String seed;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final hash = seed.hashCode;
    final random = Random(hash);
    final pixelW = size.width / 10;
    final pixelH = size.height / 10;

    final paint = Paint()..color = color;

    // Generate 10x10 symmetric identicon
    for (int x = 0; x < 5; x++) {
      // First 5 columns for 10-pixel width (5 + 5 mirrored)
      for (int y = 0; y < 10; y++) {
        // Use random boolean based on seed
        if (random.nextBool()) {
          // Draw pixel on left side
          canvas.drawRect(
            Rect.fromLTWH(x * pixelW, y * pixelH, pixelW + 0.5, pixelH + 0.5),
            paint,
          );
          // Mirror to right side
          canvas.drawRect(
            // No condition here, as 10x10 is even
            Rect.fromLTWH(
              (9 - x) * pixelW,
              y * pixelH,
              pixelW + 0.5,
              pixelH + 0.5,
            ),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _WorkspaceSearchBar extends StatelessWidget {
  const _WorkspaceSearchBar({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final hasQuery = controller.text.trim().isNotEmpty;
    final theme = Theme.of(context);
    final underline = UnderlineInputBorder(
      borderSide: BorderSide(
        color: theme.colorScheme.primary.withValues(alpha: 0.5),
      ),
    );
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 24),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search files and folders',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: hasQuery
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded),
                  onPressed: onClear,
                  tooltip: 'Clear search',
                )
              : null,
          filled: false,
          hoverColor: Colors.transparent,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 16,
          ),
          border: underline,
          enabledBorder: underline,
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(
              color: theme.colorScheme.primary.withValues(alpha: 0.7),
              width: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.label,
    this.icon,
    this.dense = false,
    this.compact = false,
  });

  final String label;
  final IconData? icon;
  final bool dense;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedForeground = theme.colorScheme.onSurfaceVariant;
    final horizontalPadding = compact ? 7.0 : (dense ? 10.0 : 12.0);
    final verticalPadding = compact ? 4.0 : (dense ? 6.0 : 8.0);
    final radius = compact ? 10.0 : (dense ? 12.0 : 14.0);
    final iconSize = compact ? 12.0 : (dense ? 14.0 : 16.0);
    final iconGap = compact ? 4.0 : (dense ? 6.0 : 8.0);
    final labelStyle =
        (compact ? theme.textTheme.labelSmall : theme.textTheme.labelMedium)
            ?.copyWith(color: resolvedForeground, fontWeight: FontWeight.w600);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: verticalPadding,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: dense ? 0.72 : 0.82),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: iconSize, color: resolvedForeground),
            SizedBox(width: iconGap),
          ],
          Flexible(child: Text(label, style: labelStyle)),
        ],
      ),
    );
  }
}

enum _InlineFilePreviewKind { text, image, unsupported }

class _FolderNameDialog extends StatefulWidget {
  const _FolderNameDialog({
    required this.title,
    required this.confirmLabel,
    this.initialValue,
  });

  final String title;
  final String confirmLabel;
  final String? initialValue;

  @override
  State<_FolderNameDialog> createState() => _FolderNameDialogState();
}

class _FolderNameDialogState extends State<_FolderNameDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late String _currentValue;

  @override
  void initState() {
    super.initState();
    _currentValue = widget.initialValue?.trim() ?? '';
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    Navigator.of(context).pop(_currentValue.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: TextFormField(
          initialValue: widget.initialValue ?? '',
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(labelText: 'Folder name'),
          onChanged: (value) => _currentValue = value,
          validator: (value) {
            final trimmed = value?.trim() ?? '';
            if (trimmed.length > 80) {
              return 'Keep folder names under 80 characters.';
            }
            return null;
          },
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}

class _WorkspacePathItem {
  const _WorkspacePathItem({
    required this.label,
    required this.folderId,
    this.isRoot = false,
  });

  final String label;
  final String? folderId;
  final bool isRoot;
}

enum _WorkspaceTileDensity {
  compact('compact', 'Compact'),
  comfortable('comfortable', 'Comfortable'),
  large('large', 'Large');

  const _WorkspaceTileDensity(this.storageKey, this.label);

  final String storageKey;
  final String label;

  static _WorkspaceTileDensity fromStorageKey(String? value) {
    final normalized = value?.trim().toLowerCase();
    for (final density in values) {
      if (density.storageKey == normalized) {
        return density;
      }
    }
    return _WorkspaceTileDensity.comfortable;
  }
}

enum _WorkspaceFolderPlacement {
  auto(
    'auto',
    'Automatic',
    'Use a left pane on wide screens and stack on narrow screens.',
  ),
  above('above', 'Above files', 'Keep folders above the file grid.'),
  left(
    'left',
    'Left pane',
    'Show folders in a Windows-style pane when there is room.',
  ),
  right(
    'right',
    'Right pane',
    'Show folders in a right-side tree when there is room.',
  );

  const _WorkspaceFolderPlacement(
    this.storageKey,
    this.label,
    this.description,
  );

  final String storageKey;
  final String label;
  final String description;

  static _WorkspaceFolderPlacement fromStorageKey(String? value) {
    final normalized = value?.trim().toLowerCase();
    for (final placement in values) {
      if (placement.storageKey == normalized) {
        return placement;
      }
    }
    return _WorkspaceFolderPlacement.auto;
  }
}

class _WorkspaceTileMetrics {
  const _WorkspaceTileMetrics({
    required this.folderTileExtent,
    required this.folderSectionHeight,
    required this.fileGridExtent,
    required this.fileGridAspectRatio,
    required this.gridSpacing,
    required this.cardRadius,
    required this.pathCardPadding,
    required this.pathChipPadding,
    required this.selectControlSize,
    required this.previewIconSize,
  });

  final double folderTileExtent;
  final double folderSectionHeight;
  final double fileGridExtent;
  final double fileGridAspectRatio;
  final double gridSpacing;
  final double cardRadius;
  final EdgeInsets pathCardPadding;
  final EdgeInsets pathChipPadding;
  final double selectControlSize;
  final double previewIconSize;
}

extension _WorkspaceTileDensityMetrics on _WorkspaceTileDensity {
  _WorkspaceTileMetrics get metrics {
    switch (this) {
      case _WorkspaceTileDensity.compact:
        return const _WorkspaceTileMetrics(
          folderTileExtent: 190,
          folderSectionHeight: 96,
          fileGridExtent: 178,
          fileGridAspectRatio: 0.9,
          gridSpacing: 10,
          cardRadius: 14,
          pathCardPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          pathChipPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          selectControlSize: 30,
          previewIconSize: 40,
        );
      case _WorkspaceTileDensity.comfortable:
        return const _WorkspaceTileMetrics(
          folderTileExtent: 230,
          folderSectionHeight: 112,
          fileGridExtent: 230,
          fileGridAspectRatio: 0.84,
          gridSpacing: 14,
          cardRadius: 20,
          pathCardPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          pathChipPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          selectControlSize: 34,
          previewIconSize: 48,
        );
      case _WorkspaceTileDensity.large:
        return const _WorkspaceTileMetrics(
          folderTileExtent: 300,
          folderSectionHeight: 136,
          fileGridExtent: 282,
          fileGridAspectRatio: 0.78,
          gridSpacing: 18,
          cardRadius: 24,
          pathCardPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          pathChipPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          selectControlSize: 38,
          previewIconSize: 56,
        );
    }
  }
}

class _WorkspacePathBar extends StatelessWidget {
  const _WorkspacePathBar({
    required this.items,
    required this.onNavigate,
    required this.tileDensity,
  });

  final List<_WorkspacePathItem> items;
  final ValueChanged<String?> onNavigate;
  final _WorkspaceTileDensity tileDensity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visibleItems = _visiblePathItems(items);
    return Material(
      type: MaterialType.transparency,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 0, vertical: 4),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var index = 0; index < visibleItems.length; index++) ...[
                if (index > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                _WorkspacePathChip(
                  item: visibleItems[index],
                  isCurrent: index == visibleItems.length - 1,
                  tileDensity: tileDensity,
                  compact: visibleItems.length > 2 && index == 0,
                  onTap: () => onNavigate(visibleItems[index].folderId),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<_WorkspacePathItem> _visiblePathItems(List<_WorkspacePathItem> source) {
    if (source.length <= 3) {
      return source;
    }
    return <_WorkspacePathItem>[
      source.first,
      source[source.length - 2],
      source.last,
    ];
  }
}

class _WorkspacePathChip extends StatelessWidget {
  const _WorkspacePathChip({
    required this.item,
    required this.isCurrent,
    required this.tileDensity,
    required this.onTap,
    this.compact = false,
  });

  final _WorkspacePathItem item;
  final bool isCurrent;
  final _WorkspaceTileDensity tileDensity;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foregroundColor = isCurrent
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    final chipPadding = EdgeInsets.symmetric(
      horizontal: tileDensity == _WorkspaceTileDensity.compact ? 7 : 9,
      vertical: tileDensity == _WorkspaceTileDensity.compact ? 4 : 5,
    );

    return InkWell(
      onTap: isCurrent ? null : onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: chipPadding,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              item.isRoot ? Icons.home_outlined : Icons.folder_outlined,
              size: tileDensity == _WorkspaceTileDensity.large ? 18 : 16,
              color: foregroundColor,
            ),
            if (!compact) ...[
              SizedBox(
                width: tileDensity == _WorkspaceTileDensity.compact ? 6 : 8,
              ),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: isCurrent
                      ? (tileDensity == _WorkspaceTileDensity.large ? 150 : 124)
                      : 104,
                ),
                child: Text(
                  item.label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: foregroundColor,
                    fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StorageSpaceSwitcher extends StatelessWidget {
  const _StorageSpaceSwitcher({
    required this.spaces,
    required this.activeSpace,
    required this.onSelected,
  });

  final List<CompanyStorageSpace> spaces;
  final CompanyStorageSpace activeSpace;
  final ValueChanged<CompanyStorageSpace> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final space in spaces)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                avatar: Icon(_iconForScope(space.scope), size: 18),
                selected: space.id == activeSpace.id,
                label: Text(space.label),
                onSelected: (_) => onSelected(space),
                selectedColor: theme.colorScheme.primaryContainer,
                checkmarkColor: theme.colorScheme.onPrimaryContainer,
              ),
            ),
        ],
      ),
    );
  }

  IconData _iconForScope(String scope) {
    switch (scope) {
      case 'company_private':
        return Icons.lock_outline;
      case 'company_shared':
        return Icons.folder_shared_outlined;
      case 'group':
        return Icons.groups_2_outlined;
      default:
        return Icons.cloud_outlined;
    }
  }
}

class _OnlineFoldersSection extends StatelessWidget {
  const _OnlineFoldersSection({
    required this.items,
    required this.loading,
    required this.offlineFolders,
    required this.onOpenFolder,
    required this.onCreateFolder,
    required this.onToggleOfflineFolder,
    required this.tileDensity,
    this.searching = false,
    this.searchQuery = '',
    this.hasAnyItems = false,
    this.selectedFolderIds = const {},
    this.selectionMode = false,
    this.onToggleSelection,
    this.createEnabled = true,
    this.emptyMessage,
    this.navigationPane = false,
    this.treeItems = const <_FolderTreeItem>[],
  });

  final List<_FolderListItem> items;
  final bool loading;
  final Map<String, _OfflineFolderConfig> offlineFolders;
  final ValueChanged<_FolderSummary> onOpenFolder;
  final VoidCallback onCreateFolder;
  final Future<void> Function(_FolderSummary summary, bool enable)
  onToggleOfflineFolder;
  final _WorkspaceTileDensity tileDensity;
  final bool searching;
  final String searchQuery;
  final bool hasAnyItems;
  final Set<String> selectedFolderIds;
  final bool selectionMode;
  final ValueChanged<String>? onToggleSelection;
  final bool createEnabled;
  final String? emptyMessage;
  final bool navigationPane;
  final List<_FolderTreeItem> treeItems;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final useVirtualizedGrid = items.length > 12;
    final metrics = tileDensity.metrics;
    final folderTileWidth = (screenWidth * 0.28)
        .clamp(metrics.folderTileExtent, metrics.folderTileExtent + 90)
        .toDouble();

    String buildEmptyMessage() {
      if (!searching || !hasAnyItems) {
        return emptyMessage ??
            'Your Drive folders will appear here after syncing.';
      }
      final query = searchQuery.trim();
      if (query.isEmpty) {
        return 'No folders match your search.';
      }
      return 'No folders match "$query".';
    }

    Widget buildFolderTile(_FolderListItem item) {
      final isOffline = offlineFolders.containsKey(item.summary.id);
      return _FolderListTile(
        item: item,
        isOffline: isOffline,
        selected: selectedFolderIds.contains(item.summary.id),
        selectionMode: selectionMode,
        tileDensity: tileDensity,
        onTap: () => onOpenFolder(item.summary),
        onToggleOffline: () =>
            unawaited(onToggleOfflineFolder(item.summary, !isOffline)),
        onToggleSelection: () => onToggleSelection?.call(item.summary.id),
      );
    }

    Widget buildCreateFolderButton() {
      return SizedBox(
        width: tileDensity == _WorkspaceTileDensity.compact ? 64 : 76,
        height: metrics.folderSectionHeight,
        child: Tooltip(
          message: createEnabled ? 'New folder' : 'Cannot create folder here',
          child: OutlinedButton(
            onPressed: createEnabled ? onCreateFolder : null,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Icon(Icons.create_new_folder_outlined),
          ),
        ),
      );
    }

    Widget buildCreateFolderIconButton() {
      return Tooltip(
        message: createEnabled ? 'New folder' : 'Cannot create folder here',
        child: IconButton.filledTonal(
          onPressed: createEnabled ? onCreateFolder : null,
          icon: const Icon(Icons.create_new_folder_outlined),
          tooltip: createEnabled ? 'New folder' : 'Cannot create folder here',
          visualDensity: VisualDensity.compact,
        ),
      );
    }

    if (navigationPane) {
      final resolvedTreeItems = treeItems.isNotEmpty
          ? treeItems
          : <_FolderTreeItem>[
              for (final item in items)
                _FolderTreeItem(
                  item: item,
                  depth: 0,
                  hasChildren: false,
                  isExpanded: false,
                  isCurrent: false,
                ),
            ];
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.folder_outlined,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Folders',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (loading)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                buildCreateFolderIconButton(),
              ],
            ),
            if (selectionMode) ...[
              const SizedBox(height: 8),
              Text(
                '${selectedFolderIds.length} selected',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (resolvedTreeItems.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Text(
                  buildEmptyMessage(),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              )
            else
              for (final treeItem in resolvedTreeItems) ...[
                _FolderTreeTile(
                  treeItem: treeItem,
                  isOffline: offlineFolders.containsKey(
                    treeItem.item.summary.id,
                  ),
                  selected: selectedFolderIds.contains(
                    treeItem.item.summary.id,
                  ),
                  selectionMode: selectionMode,
                  onTap: () => onOpenFolder(treeItem.item.summary),
                  onToggleOffline: () => unawaited(
                    onToggleOfflineFolder(
                      treeItem.item.summary,
                      !offlineFolders.containsKey(treeItem.item.summary.id),
                    ),
                  ),
                  onToggleSelection: () =>
                      onToggleSelection?.call(treeItem.item.summary.id),
                ),
                const SizedBox(height: 4),
              ],
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (selectionMode || loading)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                if (selectionMode)
                  Text(
                    '${selectedFolderIds.length} selected',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                const Spacer(),
                if (loading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
        if (items.isEmpty)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SizedBox(
                  height: metrics.folderSectionHeight,
                  child: Center(
                    child: Text(
                      buildEmptyMessage(),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              buildCreateFolderButton(),
            ],
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final buttonWidth = createEnabled ? 82.0 : 82.0;
              final listWidth = (constraints.maxWidth - buttonWidth).clamp(
                0.0,
                constraints.maxWidth,
              );
              final grid = GridView.builder(
                primary: false,
                scrollDirection: Axis.horizontal,
                physics: useVirtualizedGrid
                    ? const ClampingScrollPhysics()
                    : const BouncingScrollPhysics(),
                itemCount: items.length,
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: folderTileWidth,
                  mainAxisExtent: folderTileWidth,
                  mainAxisSpacing: metrics.gridSpacing,
                  crossAxisSpacing: metrics.gridSpacing,
                ),
                itemBuilder: (context, index) {
                  return SizedBox(
                    width: folderTileWidth,
                    child: buildFolderTile(items[index]),
                  );
                },
              );
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: metrics.folderSectionHeight,
                    width: listWidth,
                    child: Scrollbar(
                      thumbVisibility: items.length > 3,
                      child: grid,
                    ),
                  ),
                  const SizedBox(width: 10),
                  buildCreateFolderButton(),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _FolderTreeTile extends StatelessWidget {
  const _FolderTreeTile({
    required this.treeItem,
    required this.isOffline,
    required this.onTap,
    required this.onToggleOffline,
    this.selected = false,
    this.selectionMode = false,
    this.onToggleSelection,
  });

  final _FolderTreeItem treeItem;
  final bool isOffline;
  final VoidCallback onTap;
  final VoidCallback onToggleOffline;
  final bool selected;
  final bool selectionMode;
  final VoidCallback? onToggleSelection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = treeItem.item;
    final summary = item.summary;
    final active = treeItem.isCurrent;
    final background = selected
        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.34)
        : active
        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.22)
        : Colors.transparent;
    final foreground = active
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;
    final indent = (treeItem.depth * 12.0).clamp(0.0, 48.0);
    final description = summary.description;

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: selectionMode && !summary.isRoot ? onToggleSelection : onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(6 + indent, 6, 6, 6),
          child: Row(
            children: [
              SizedBox(
                width: 16,
                child: treeItem.hasChildren
                    ? Icon(
                        treeItem.isExpanded
                            ? Icons.keyboard_arrow_down_rounded
                            : Icons.keyboard_arrow_right_rounded,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      )
                    : null,
              ),
              const SizedBox(width: 3),
              if (selectionMode && !summary.isRoot)
                Checkbox(
                  value: selected,
                  onChanged: (_) => onToggleSelection?.call(),
                  visualDensity: VisualDensity.compact,
                )
              else
                Icon(
                  summary.isRoot ? Icons.home_outlined : Icons.folder_outlined,
                  size: 19,
                  color: active
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      summary.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: foreground,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
                    if (description.isNotEmpty)
                      Text(
                        description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (!selectionMode && !summary.isRoot)
                IconButton(
                  icon: Icon(
                    isOffline
                        ? Icons.offline_pin
                        : Icons.download_for_offline_outlined,
                    size: 18,
                  ),
                  visualDensity: VisualDensity.compact,
                  tooltip: isOffline
                      ? 'Stop keeping offline'
                      : 'Keep encrypted offline',
                  onPressed: onToggleOffline,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FolderListTile extends StatelessWidget {
  const _FolderListTile({
    required this.item,
    required this.isOffline,
    required this.onTap,
    required this.onToggleOffline,
    required this.tileDensity,
    this.selected = false,
    this.selectionMode = false,
    this.onToggleSelection,
  });

  final _FolderListItem item;
  final bool isOffline;
  final VoidCallback onTap;
  final VoidCallback onToggleOffline;
  final _WorkspaceTileDensity tileDensity;
  final bool selected;
  final bool selectionMode;
  final VoidCallback? onToggleSelection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = item.summary;

    Color resolveFolderColor(String? hex) {
      if (hex == null || hex.isEmpty) {
        return theme.colorScheme.primary;
      }
      final normalized = hex.replaceAll('#', '').trim();
      final buffer = StringBuffer();
      if (normalized.length == 6) {
        buffer.write('ff');
      } else if (normalized.length != 8) {
        return theme.colorScheme.primary;
      }
      buffer.write(normalized.toLowerCase());
      final parsed = int.tryParse(buffer.toString(), radix: 16);
      if (parsed == null) {
        return theme.colorScheme.primary;
      }
      return Color(parsed);
    }

    final folderColor = summary.isRoot
        ? theme.colorScheme.primary
        : resolveFolderColor(summary.colorHex);

    final itemLabel = summary.itemCount == 1
        ? '1 item'
        : '${summary.itemCount} items';
    final sizeLabel = summary.totalBytes > 0
        ? _formatStorageValue(summary.totalBytes.toDouble())
        : 'Empty';
    final borderColor = selected
        ? theme.colorScheme.primary.withValues(alpha: 0.65)
        : theme.colorScheme.outlineVariant.withValues(alpha: 0.55);
    final backgroundColor = selected
        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.22)
        : theme.colorScheme.surfaceContainerLowest;
    final metrics = tileDensity.metrics;
    final horizontalGap = tileDensity == _WorkspaceTileDensity.compact
        ? 8.0
        : 12.0;
    final iconExtent = switch (tileDensity) {
      _WorkspaceTileDensity.compact => 38.0,
      _WorkspaceTileDensity.comfortable => 46.0,
      _WorkspaceTileDensity.large => 54.0,
    };

    return Material(
      color: backgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(metrics.cardRadius * 0.55),
        side: BorderSide(color: borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: selectionMode ? onToggleSelection : onTap,
        onLongPress: kIsWeb ? null : onToggleSelection,
        child: Padding(
          padding: EdgeInsets.all(
            tileDensity == _WorkspaceTileDensity.compact ? 9 : 12,
          ),
          child: Row(
            children: [
              if (selectionMode || kIsWeb)
                Checkbox(
                  value: selected,
                  onChanged: (_) => onToggleSelection?.call(),
                )
              else
                Container(
                  width: iconExtent,
                  height: iconExtent,
                  decoration: BoxDecoration(
                    color: folderColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    summary.isRoot ? Icons.home_outlined : Icons.folder_rounded,
                    color: folderColor,
                    size: tileDensity == _WorkspaceTileDensity.large ? 32 : 28,
                  ),
                ),
              SizedBox(width: horizontalGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            summary.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (summary.isSystem) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.lock_outline,
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _FolderMetaPill(label: itemLabel),
                        _FolderMetaPill(label: sizeLabel),
                        if (isOffline)
                          const _FolderMetaPill(
                            label: 'Offline',
                            icon: Icons.offline_pin,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!selectionMode) ...[
                const SizedBox(width: 4),
                IconButton(
                  icon: Icon(
                    isOffline
                        ? Icons.offline_pin
                        : Icons.download_for_offline_outlined,
                  ),
                  tooltip: isOffline
                      ? 'Stop keeping offline'
                      : 'Keep encrypted offline',
                  onPressed: onToggleOffline,
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FolderMetaPill extends StatelessWidget {
  const _FolderMetaPill({required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

const double _bytesPerKb = 1024;
const double _bytesPerMb = 1048576;
const double _bytesPerGb = 1073741824;
const double _bytesPerTb = 1099511627776;
const double _bytesPerPb = 1125899906842624;

String _formatStorageValue(double bytes) {
  if (bytes.isNaN || bytes.isInfinite) {
    return '0 B';
  }
  var value = bytes;
  if (value < 0) {
    value = 0;
  }
  const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }
  final decimals = unitIndex == 0
      ? 0
      : (value >= 100
            ? 0
            : value >= 10
            ? 1
            : 2);
  return '${value.toStringAsFixed(decimals)} ${units[unitIndex]}';
}

class _StorageUsageMetrics {
  const _StorageUsageMetrics({
    required this.progress,
    required this.primaryText,
    required this.secondaryText,
    required this.percentageText,
    required this.badgeText,
    required this.hasLimit,
    this.hintText,
  });

  final double progress;
  final String primaryText;
  final String secondaryText;
  final String percentageText;
  final String badgeText;
  final bool hasLimit;
  final String? hintText;
}

_StorageUsageMetrics _storageUsageMetrics(
  double usedBytes,
  double totalBytes,
  _StorageDisplayMode displayMode, {
  bool hasLimit = true,
  String? planLabel,
  bool limitPending = false,
  int unknownItemCount = 0,
  bool hasPendingUploads = false,
}) {
  final safeUsed = usedBytes.isFinite && usedBytes > 0
      ? usedBytes
      : max(0.0, usedBytes);
  final effectiveTotal = hasLimit && totalBytes.isFinite && totalBytes > 0
      ? totalBytes
      : (safeUsed <= 0 ? 0.0 : safeUsed);
  final progress = hasLimit && effectiveTotal > 0
      ? (safeUsed / effectiveTotal).clamp(0.0, 1.0)
      : 0.0;

  final usedLabel = _formatStorageValue(safeUsed);
  final totalLabel = _formatStorageValue(effectiveTotal);
  final percentage = effectiveTotal <= 0
      ? 0.0
      : (safeUsed / effectiveTotal * 100).clamp(0.0, 100.0);
  final percentageText = hasLimit ? percentage.toStringAsFixed(1) : '--';
  final badgeText = hasLimit
      ? (percentage >= 100.0
            ? '100%'
            : percentage >= 10.0
            ? '${percentage.round()}%'
            : '${percentage.toStringAsFixed(1)}%')
      : (safeUsed > 0 ? 'unlimited' : '0%');

  late final String primaryText;
  late final String secondaryText;

  if (hasLimit && effectiveTotal > 0) {
    switch (displayMode) {
      case _StorageDisplayMode.percentage:
        primaryText = '$percentageText% of capacity used';
        secondaryText = '$usedLabel of $totalLabel used';
      case _StorageDisplayMode.amount:
        primaryText = '$usedLabel of $totalLabel used';
        secondaryText = '';
    }
  } else if (hasLimit) {
    primaryText = 'Storage usage not yet available';
    if (limitPending) {
      secondaryText = 'Usage details are still syncing.';
    } else if (planLabel != null && planLabel.isNotEmpty) {
      secondaryText = planLabel;
    } else {
      secondaryText = 'Plan details unavailable.';
    }
  } else {
    if (safeUsed <= 0) {
      primaryText = '0 B stored';
    } else {
      primaryText = '$usedLabel stored';
    }
    if (limitPending) {
      secondaryText = 'Usage details are still syncing.';
    } else if (planLabel != null && planLabel.isNotEmpty) {
      secondaryText = planLabel;
    } else {
      secondaryText = safeUsed <= 0 ? 'Upload files to see usage.' : '';
    }
  }

  final hints = <String>[];
  if (hasLimit &&
      planLabel != null &&
      planLabel.isNotEmpty &&
      planLabel != secondaryText) {
    hints.add(planLabel);
  }
  if (!hasLimit &&
      planLabel != null &&
      planLabel.isNotEmpty &&
      planLabel != secondaryText) {
    hints.add(planLabel);
  }
  if (limitPending) {
    hints.add('Plan details pending');
  }
  if (hasPendingUploads) {
    hints.add('Including items still uploading');
  }
  if (unknownItemCount > 0) {
    hints.add(
      unknownItemCount == 1
          ? '1 item awaiting usage details'
          : '$unknownItemCount items awaiting usage details',
    );
  }

  final hintText = hints.isEmpty ? null : hints.join('  -  ');

  return _StorageUsageMetrics(
    progress: progress,
    primaryText: primaryText,
    secondaryText: secondaryText,
    percentageText: percentageText,
    badgeText: badgeText,
    hasLimit: hasLimit,
    hintText: hintText,
  );
}

class _RecentFilesSection extends StatelessWidget {
  const _RecentFilesSection({
    required this.files,
    required this.loading,
    required this.offlineKeys,
    required this.onOpenFile,
    required this.expanded,
    required this.onToggleExpanded,
    required this.thumbnailFetcher,
    required this.activeShareLinkCountFor,
    required this.tileDensity,
    this.searching = false,
    this.searchQuery = '',
    this.selectedFileIds = const {},
    this.selectionMode = false,
    this.onToggleSelection,
    this.title = 'Recent files',
    this.emptyMessage,
    this.allowCollapse = true,
  });

  final List<_DriveFile> files;
  final bool loading;
  final Set<String> offlineKeys;
  final Future<void> Function(_DriveFile file) onOpenFile;
  final Future<Uint8List?> Function(
    _DriveFile file, {
    bool force,
    bool interactive,
  })
  thumbnailFetcher;
  final int Function(String fileId) activeShareLinkCountFor;
  final _WorkspaceTileDensity tileDensity;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final bool searching;
  final String searchQuery;
  final Set<String> selectedFileIds;
  final bool selectionMode;
  final ValueChanged<String>? onToggleSelection;
  final String title;
  final String? emptyMessage;
  final bool allowCollapse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const collapsedCount = 6; // Show more items in grid initially
    final showToggle =
        allowCollapse && !searching && files.length > collapsedCount;
    final visibleFiles = expanded || searching || !allowCollapse
        ? files
        : files.take(collapsedCount).toList(growable: false);
    final query = searchQuery.trim();
    final screenHeight = MediaQuery.sizeOf(context).height;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!searching)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  selectionMode ? '${selectedFileIds.length} selected' : title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (loading)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    if (showToggle)
                      TextButton.icon(
                        onPressed: onToggleExpanded,
                        icon: Icon(
                          expanded ? Icons.expand_less : Icons.expand_more,
                        ),
                        label: Text(expanded ? 'Show less' : 'Show all'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        if (!searching) const SizedBox(height: 12),
        if (files.isEmpty && !loading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
            child: Text(
              searching
                  ? (query.isEmpty
                        ? 'No files match your search.'
                        : 'No files match "$query".')
                  : (emptyMessage ??
                        'Upload a file to start building your library.'),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 640;
              final useVirtualizedGrid =
                  visibleFiles.length > (compact ? 12 : 18);
              final metrics = tileDensity.metrics;
              final maxExtent = compact
                  ? min(metrics.fileGridExtent, 210)
                  : metrics.fileGridExtent;
              final maxTileExtent = maxExtent.toDouble();
              final aspectRatio = compact
                  ? (metrics.fileGridAspectRatio + 0.04)
                  : metrics.fileGridAspectRatio;
              final spacing = metrics.gridSpacing;
              final columns = max(
                1,
                (constraints.maxWidth / maxTileExtent).floor(),
              );
              final rows = (visibleFiles.length / columns).ceil();
              final tileHeight = maxTileExtent / aspectRatio;
              final naturalHeight =
                  rows * tileHeight + max(0, rows - 1) * spacing;
              final gridHeight = (screenHeight * (compact ? 0.48 : 0.58))
                  .clamp(260.0, 760.0)
                  .toDouble();
              final boundedHeight = useVirtualizedGrid
                  ? gridHeight
                  : naturalHeight.clamp(tileHeight, gridHeight).toDouble();
              final gridView = GridView.builder(
                primary: false,
                shrinkWrap: false,
                physics: useVirtualizedGrid
                    ? const ClampingScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: maxTileExtent,
                  childAspectRatio: aspectRatio,
                  crossAxisSpacing: spacing,
                  mainAxisSpacing: spacing,
                ),
                itemCount: visibleFiles.length,
                itemBuilder: (context, index) {
                  final file = visibleFiles[index];
                  final isOffline = offlineKeys.contains(file.objectKey);
                  return _FileGridTile(
                    key: ValueKey<String>(file.objectKey),
                    file: file,
                    isOffline: isOffline,
                    thumbnailFetcher: thumbnailFetcher,
                    activeShareLinkCount: activeShareLinkCountFor(file.id),
                    selected: selectedFileIds.contains(file.id),
                    selectionMode: selectionMode,
                    tileDensity: tileDensity,
                    onTap: () => onOpenFile(file),
                    onToggleSelection: () => onToggleSelection?.call(file.id),
                  );
                },
              );
              return SizedBox(
                height: boundedHeight,
                child: Scrollbar(
                  thumbVisibility: useVirtualizedGrid,
                  child: gridView,
                ),
              );
            },
          ),
      ],
    );
  }
}

class _FileGridTile extends StatelessWidget {
  const _FileGridTile({
    super.key,
    required this.file,
    required this.isOffline,
    required this.thumbnailFetcher,
    required this.activeShareLinkCount,
    required this.onTap,
    required this.tileDensity,
    this.selected = false,
    this.selectionMode = false,
    this.onToggleSelection,
  });

  final _DriveFile file;
  final bool isOffline;
  final Future<Uint8List?> Function(
    _DriveFile file, {
    bool force,
    bool interactive,
  })
  thumbnailFetcher;
  final int activeShareLinkCount;
  final VoidCallback onTap;
  final _WorkspaceTileDensity tileDensity;
  final bool selected;
  final bool selectionMode;
  final VoidCallback? onToggleSelection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extension = p
        .extension(file.name)
        .replaceFirst('.', '')
        .toUpperCase();
    final typeLabel = extension.isNotEmpty
        ? extension
        : (file.isFolder
              ? 'FOLDER'
              : (file.contentType?.startsWith('image/') == true
                    ? 'IMAGE'
                    : 'FILE'));
    final metaParts = <String>[
      file.hasKnownSize || file.size > 0
          ? _formatBytes(file.size)
          : 'Size pending',
      if (file.uploadedAt != null) _formatRelativeTime(file.uploadedAt!),
    ];
    final metaText = metaParts.join('  -  ');
    final metrics = tileDensity.metrics;
    final contentPadding = switch (tileDensity) {
      _WorkspaceTileDensity.compact => const EdgeInsets.fromLTRB(10, 9, 10, 8),
      _WorkspaceTileDensity.comfortable => const EdgeInsets.fromLTRB(
        12,
        12,
        12,
        10,
      ),
      _WorkspaceTileDensity.large => const EdgeInsets.fromLTRB(16, 14, 16, 14),
    };

    Widget content;
    if (file.supportsThumbnailPreview) {
      content = _ThumbnailImage(
        key: ValueKey<String>('thumb-${file.objectKey}'),
        file: file,
        fetcher: thumbnailFetcher,
      );
    } else {
      IconData icon = Icons.insert_drive_file_outlined;
      if (file.isFolder) {
        icon = Icons.folder_rounded;
      } else {
        final name = file.name.toLowerCase();
        if (name.endsWith('.pdf')) {
          icon = Icons.picture_as_pdf_rounded;
        } else if (name.endsWith('.doc') || name.endsWith('.docx')) {
          icon = Icons.description_rounded;
        } else if (name.endsWith('.xls') || name.endsWith('.xlsx')) {
          icon = Icons.table_chart_rounded;
        } else if (name.endsWith('.ppt') || name.endsWith('.pptx')) {
          icon = Icons.slideshow_rounded;
        } else if (name.endsWith('.zip') || name.endsWith('.rar')) {
          icon = Icons.archive_rounded;
        } else if (name.endsWith('.mp4') || name.endsWith('.mov')) {
          icon = Icons.video_file_rounded;
        } else if (name.endsWith('.mp3') || name.endsWith('.wav')) {
          icon = Icons.audio_file_rounded;
        } else if (name.endsWith('.jpg') ||
            name.endsWith('.jpeg') ||
            name.endsWith('.png')) {
          icon = Icons.image_rounded;
        }
      }

      content = Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
        ),
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: metrics.previewIconSize,
          color: theme.colorScheme.primary,
        ),
      );
    }

    return Card(
      elevation: selected ? 6 : 1,
      shadowColor: theme.colorScheme.shadow.withValues(alpha: 0.08),
      color: selected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.32)
          : theme.colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(metrics.cardRadius),
        side: BorderSide(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.42),
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: selectionMode ? onToggleSelection : onTap,
        onLongPress: kIsWeb ? null : onToggleSelection,
        borderRadius: BorderRadius.circular(metrics.cardRadius),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  content,
                  if (selectionMode || kIsWeb)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Tooltip(
                        message: selected ? 'Deselect file' : 'Select file',
                        child: Material(
                          color: theme.colorScheme.surface.withValues(
                            alpha: 0.94,
                          ),
                          shape: const CircleBorder(),
                          elevation: selected ? 3 : 1,
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: onToggleSelection,
                            child: SizedBox(
                              width: metrics.selectControlSize,
                              height: metrics.selectControlSize,
                              child: Icon(
                                selected
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                size: metrics.selectControlSize - 12,
                                color: selected
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: contentPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _InfoPill(
                              label: typeLabel,
                              dense: true,
                              compact: true,
                            ),
                            if (isOffline)
                              const _InfoPill(
                                icon: Icons.offline_pin_rounded,
                                label: 'Offline',
                                dense: true,
                              ),
                            if (activeShareLinkCount > 0)
                              _InfoPill(
                                icon: Icons.link_rounded,
                                label: activeShareLinkCount == 1
                                    ? '1 link'
                                    : '$activeShareLinkCount links',
                                dense: true,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(
                    height: tileDensity == _WorkspaceTileDensity.compact
                        ? 7
                        : 10,
                  ),
                  Tooltip(
                    message: file.name,
                    child: Text(
                      file.name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                      maxLines: tileDensity == _WorkspaceTileDensity.large
                          ? 2
                          : 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(
                    height: tileDensity == _WorkspaceTileDensity.compact
                        ? 5
                        : 8,
                  ),
                  Text(
                    metaText,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

class _OfflineFilesSection extends StatelessWidget {
  const _OfflineFilesSection({
    required this.entries,
    required this.onOpenFile,
    required this.onRemove,
    this.searching = false,
    this.searchQuery = '',
    this.hadEntries = false,
  });

  final List<_OfflineEntry> entries;
  final Future<void> Function(_DriveFile file, _OfflineFileInfo info)
  onOpenFile;
  final Future<void> Function(_DriveFile file) onRemove;
  final bool searching;
  final String searchQuery;
  final bool hadEntries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty && (!searching || !hadEntries)) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Offline files',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Stored as authenticated encrypted vault objects. Open them '
              'through RonikCloud to decrypt locally.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  searchQuery.trim().isEmpty
                      ? 'No offline files match your search.'
                      : 'No offline files match "${searchQuery.trim()}".',
                ),
              )
            else
              ...entries.map((entry) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.offline_pin),
                  title: Text(entry.file.name),
                  subtitle: Text(
                    '${entry.info.isEncryptedVault ? 'Encrypted' : 'Encryption upgrade pending'}'
                    ' · Saved ${entry.info.downloadedAt.toLocal()}',
                  ),
                  onTap: () => onOpenFile(entry.file, entry.info),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => onRemove(entry.file),
                    tooltip: 'Remove offline copy',
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _BackupProgressIndicator extends StatelessWidget {
  const _BackupProgressIndicator({required this.status});

  final _BackupProgressStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progressValue = status.progress;
    final scanning = status.scanning;
    final primaryStyle = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w600,
    );
    final subtleColor =
        (theme.textTheme.bodySmall?.color ?? theme.colorScheme.onSurface)
            .withValues(alpha: 0.7);
    final subtleStyle = theme.textTheme.bodySmall?.copyWith(color: subtleColor);

    final baseLabel = scanning
        ? 'Scanning for new files...'
        : status.incremental
        ? 'Syncing recent changes...'
        : 'Checking and syncing ${status.completedFiles} of ${status.totalFiles}';
    final label = scanning && status.scannedFiles > 0
        ? '$baseLabel (${status.scannedFiles} checked)'
        : baseLabel;

    final details = <String>[];
    final currentFile = status.currentFile;
    if (currentFile != null && currentFile.isNotEmpty) {
      details.add(currentFile);
    }
    if (!scanning && status.totalBytes > 0) {
      final total = status.totalBytes;
      final transferred = status.transferredBytes < 0
          ? 0
          : (status.transferredBytes > total ? total : status.transferredBytes);
      details.add('${_formatBytes(transferred)} of ${_formatBytes(total)}');
    } else if (!scanning && status.transferredBytes > 0) {
      details.add('${_formatBytes(status.transferredBytes)} uploaded');
    }
    final detailText = details.join('  -  ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: primaryStyle),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 6,
            child: LinearProgressIndicator(value: progressValue),
          ),
        ),
        if (detailText.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(detailText, style: subtleStyle),
        ],
      ],
    );
  }
}

class _BackupProgressStatus {
  const _BackupProgressStatus({
    required this.totalFiles,
    required this.completedFiles,
    required this.totalBytes,
    required this.transferredBytes,
    required this.scannedFiles,
    required this.scanning,
    required this.incremental,
    this.currentFile,
  });

  final int totalFiles;
  final int completedFiles;
  final int totalBytes;
  final int transferredBytes;
  final int scannedFiles;
  final bool scanning;
  final bool incremental;
  final String? currentFile;

  static const Object _sentinel = Object();

  factory _BackupProgressStatus.scanning({int scannedFiles = 0}) {
    return _BackupProgressStatus(
      totalFiles: 0,
      completedFiles: 0,
      totalBytes: 0,
      transferredBytes: 0,
      scannedFiles: scannedFiles,
      scanning: true,
      incremental: false,
      currentFile: null,
    );
  }

  factory _BackupProgressStatus.preparing({
    required int totalFiles,
    required int totalBytes,
    int scannedFiles = 0,
  }) {
    return _BackupProgressStatus(
      totalFiles: totalFiles,
      completedFiles: 0,
      totalBytes: totalBytes,
      transferredBytes: 0,
      scannedFiles: scannedFiles,
      scanning: false,
      incremental: false,
      currentFile: null,
    );
  }

  factory _BackupProgressStatus.incremental({String? currentFile}) {
    return _BackupProgressStatus(
      totalFiles: 1,
      completedFiles: 0,
      totalBytes: 0,
      transferredBytes: 0,
      scannedFiles: 0,
      scanning: false,
      incremental: true,
      currentFile: currentFile,
    );
  }

  double? get progress {
    if (scanning || totalFiles <= 0) {
      return null;
    }
    if (totalFiles == 0) {
      return null;
    }
    final value = completedFiles / totalFiles;
    if (!value.isFinite) {
      return null;
    }
    final clamped = value.clamp(0.0, 1.0);
    return clamped.isFinite ? clamped.toDouble() : null;
  }

  _BackupProgressStatus copyWith({
    int? totalFiles,
    int? completedFiles,
    int? totalBytes,
    int? transferredBytes,
    int? scannedFiles,
    bool? scanning,
    Object? currentFile = _sentinel,
    bool? incremental,
  }) {
    return _BackupProgressStatus(
      totalFiles: totalFiles ?? this.totalFiles,
      completedFiles: completedFiles ?? this.completedFiles,
      totalBytes: totalBytes ?? this.totalBytes,
      transferredBytes: transferredBytes ?? this.transferredBytes,
      scannedFiles: scannedFiles ?? this.scannedFiles,
      scanning: scanning ?? this.scanning,
      incremental: incremental ?? this.incremental,
      currentFile: identical(currentFile, _sentinel)
          ? this.currentFile
          : currentFile as String?,
    );
  }
}

class _BackupSection extends StatelessWidget {
  const _BackupSection({
    required this.configs,
    required this.issues,
    required this.onRetry,
    required this.onAdd,
    required this.onToggle,
    required this.onRemove,
    required this.progress,
    this.onAddPhotos,
    this.onManagePhotos,
    this.searching = false,
    this.searchQuery = '',
    this.hadConfigs = false,
  });

  final List<_BackupFolderConfig> configs;
  final Map<String, String> issues;
  final Future<void> Function(_BackupFolderConfig) onRetry;
  final Future<void> Function() onAdd;
  final Future<void> Function()? onAddPhotos;
  final Future<void> Function()? onManagePhotos;
  final Future<void> Function(_BackupFolderConfig config, bool value) onToggle;
  final Future<void> Function(_BackupFolderConfig config) onRemove;
  final Map<String, _BackupProgressStatus> progress;
  final bool searching;
  final String searchQuery;
  final bool hadConfigs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final folderBackupsAvailable = supportsPersistentFolderBackups(
      isWeb: kIsWeb,
      platform: defaultTargetPlatform,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final title = Text(
                  'Backups',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                );
                final action = TextButton.icon(
                  onPressed: folderBackupsAvailable ? onAdd : null,
                  icon: const Icon(Icons.add),
                  label: const Text('Add folder'),
                );
                if (constraints.maxWidth < 440) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [title, action],
                  );
                }
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [title, action],
                );
              },
            ),
            const SizedBox(height: 12),
            if (!folderBackupsAvailable)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  persistentFolderBackupUnavailableMessage(
                    isWeb: kIsWeb,
                    platform: defaultTargetPlatform,
                  ),
                ),
              ),
            if (onAddPhotos != null &&
                !configs.any((config) => config.photoLibrary))
              TextButton.icon(
                onPressed: onAddPhotos,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Back up Photos'),
              ),
            if (configs.isEmpty) ...[
              if (searching && hadConfigs)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    searchQuery.trim().isEmpty
                        ? 'No backup folders match your search.'
                        : 'No backup folders match "${searchQuery.trim()}".',
                  ),
                ),
            ] else
              ...List<Widget>.generate(configs.length, (index) {
                final config = configs[index];
                final available = canRunPersistentBackupConfig(
                  isWeb: kIsWeb,
                  platform: defaultTargetPlatform,
                  photoLibrary: config.photoLibrary,
                );
                final remoteSegments = config.remoteFolder
                    .split(RegExp(r'[\\/]+'))
                    .map((segment) => segment.trim())
                    .where((segment) => segment.isNotEmpty)
                    .toList();
                final remoteLabel = remoteSegments.isEmpty
                    ? (config.remoteFolder.trim().isEmpty
                          ? 'Backup folder'
                          : config.remoteFolder.trim())
                    : remoteSegments.join(' / ');
                final sourceLabel = config.photoLibrary
                    ? 'iOS Photos library'
                    : config.localPath;
                final statusText = !available
                    ? 'Unavailable on this platform  -  $sourceLabel'
                    : config.enabled
                    ? 'Enabled  -  $sourceLabel'
                    : 'Paused  -  $sourceLabel';
                final lastSynced = config.lastSynced;
                final subtitleParts = <String>[statusText];
                if (lastSynced != null) {
                  subtitleParts.add(
                    'Last synced ${_formatRelativeTime(lastSynced.toLocal())}',
                  );
                }
                if (lastSynced == null) {
                  subtitleParts.add('No successful sync yet');
                }
                final status = progress[config.localPath];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Switch(
                        value: available && config.enabled,
                        onChanged: available
                            ? (value) => onToggle(config, value)
                            : null,
                      ),
                      title: Text(remoteLabel),
                      subtitle: Text(subtitleParts.join('  -  ')),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Remove backup',
                        onPressed: () => onRemove(config),
                      ),
                    ),
                    if (issues[config.localPath] case final String issue)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          issue,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                    if (config.photoLibrary) ...[
                      const Text(
                        'Original still photos you allow access to. Background timing is controlled by iOS; open RonikCloud to finish large backups.',
                      ),
                      TextButton(
                        onPressed: onManagePhotos,
                        child: const Text('Manage Photos access'),
                      ),
                    ],
                    TextButton.icon(
                      onPressed: available && status == null
                          ? () => onRetry(config)
                          : null,
                      icon: const Icon(Icons.sync),
                      label: const Text('Back up now'),
                    ),
                    if (status != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: _BackupProgressIndicator(status: status),
                      ),
                    if (index != configs.length - 1) const Divider(),
                  ],
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _FolderSummary {
  const _FolderSummary({
    required this.id,
    required this.displayName,
    required this.itemCount,
    required this.totalBytes,
    required this.isRoot,
    this.colorHex,
    this.isSystem = false,
  });

  final String id;
  final String displayName;
  final int itemCount;
  final int totalBytes;
  final bool isRoot;
  final String? colorHex;
  final bool isSystem;

  String get description {
    if (itemCount <= 0) {
      return '';
    }
    final itemLabel = itemCount == 1 ? 'item' : 'items';
    return '$itemCount $itemLabel';
  }
}

class _FolderAccumulator {
  _FolderAccumulator({
    required this.id,
    required this.displayName,
    required this.isRoot,
    this.colorHex,
    this.isSystem = false,
  });

  final String id;
  String displayName;
  final bool isRoot;
  String? colorHex;
  bool isSystem;
  int itemCount = 0;
  int totalBytes = 0;

  _FolderSummary toSummary() {
    final label = displayName.isNotEmpty
        ? displayName
        : (isRoot ? 'My Drive' : 'Folder');
    return _FolderSummary(
      id: id,
      displayName: label,
      itemCount: itemCount,
      totalBytes: totalBytes,
      isRoot: isRoot,
      colorHex: colorHex,
      isSystem: isSystem,
    );
  }
}

class _FolderListItem {
  const _FolderListItem({required this.summary, this.folder});

  final _FolderSummary summary;
  final _DriveFolder? folder;
}

class _FolderTreeItem {
  const _FolderTreeItem({
    required this.item,
    required this.depth,
    required this.hasChildren,
    required this.isExpanded,
    required this.isCurrent,
  });

  final _FolderListItem item;
  final int depth;
  final bool hasChildren;
  final bool isExpanded;
  final bool isCurrent;
}

class _ResolvedFileNameCacheEntry {
  const _ResolvedFileNameCacheEntry({
    required this.cacheKey,
    required this.decryptedName,
  });

  final String cacheKey;
  final String? decryptedName;
}

class _DriveFolder implements FolderInterface {
  _DriveFolder({
    required this.id,
    required this.name,
    this.encryptedName,
    this.metadataEncryption,
    this.colorHex,
    this.createdAt,
    this.updatedAt,
    this.lastFileAt,
    this.systemFolder = false,
    this.systemKey,
    this.parentId,
    this.storageScope = 'personal',
    this.companyId,
    this.ownerUid,
    this.createdByUid,
    List<String>? allowedUids,
    List<String>? groupIds,
    Map<String, dynamic>? sharedKeyEnvelopes,
  }) : allowedUids = List<String>.unmodifiable(allowedUids ?? const <String>[]),
       groupIds = List<String>.unmodifiable(groupIds ?? const <String>[]),
       sharedKeyEnvelopes = Map<String, dynamic>.unmodifiable(
         sharedKeyEnvelopes ?? const <String, dynamic>{},
       );

  @override
  final String id;
  @override
  final String name;
  final String? encryptedName;
  final String? metadataEncryption;
  @override
  final String? colorHex;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? lastFileAt;
  final bool systemFolder;
  final String? systemKey;
  @override
  final String? parentId;
  final String storageScope;
  final String? companyId;
  final String? ownerUid;
  final String? createdByUid;
  final List<String> allowedUids;
  final List<String> groupIds;
  final Map<String, dynamic> sharedKeyEnvelopes;

  String get displayName {
    final trimmed = name.trim();
    return trimmed.isEmpty ? 'Untitled folder' : trimmed;
  }

  DateTime? get activity {
    final timestamps = <DateTime>[
      if (lastFileAt != null) lastFileAt!,
      if (updatedAt != null) updatedAt!,
      if (createdAt != null) createdAt!,
    ];
    if (timestamps.isEmpty) {
      return null;
    }
    timestamps.sort();
    return timestamps.last;
  }

  bool get canDelete => !systemFolder;

  factory _DriveFolder.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    final pathSegments = data['pathSegments'];
    String? fallbackName;
    if (pathSegments is Iterable) {
      for (final segment in pathSegments) {
        final trimmedSegment = _trimmedOrNull(segment);
        if (trimmedSegment != null) {
          fallbackName = trimmedSegment;
        }
      }
    }
    fallbackName ??= _trimmedOrNull(data['path']);
    final encryptedName = _trimmedOrNull(data['encryptedName']);
    final name = encryptedName == null
        ? safeEncryptedDisplayLabel(
            placeholder: 'Untitled folder',
            candidate: _trimmedOrNull(data['name']) ?? fallbackName,
          )
        : 'Encrypted folder';
    final color =
        _trimmedOrNull(data['color']) ?? _trimmedOrNull(data['colorHex']);
    final systemFolder = data['systemFolder'] == true;
    final systemKey = _trimmedOrNull(data['systemKey']);
    final parentId = _trimmedOrNull(data['parentId']);

    return _DriveFolder(
      id: doc.id,
      name: name,
      encryptedName: encryptedName,
      metadataEncryption: _trimmedOrNull(data['metadataEncryption']),
      colorHex: color,
      createdAt: _DriveFile._parseTimestamp(data['createdAt']),
      updatedAt: _DriveFile._parseTimestamp(data['updatedAt']),
      lastFileAt: _DriveFile._parseTimestamp(data['lastFileAt']),
      systemFolder: systemFolder,
      systemKey: systemKey,
      parentId: parentId,
      storageScope: _normalizeStorageScope(data['storageScope']),
      companyId: _trimmedOrNull(data['companyId']),
      ownerUid: _trimmedOrNull(data['ownerUid']),
      createdByUid: _trimmedOrNull(data['createdByUid']),
      allowedUids: _stringListFrom(data['allowedUids']),
      groupIds: _stringListFrom(data['groupIds']),
      sharedKeyEnvelopes: _stringKeyedMap(data['sharedKeyEnvelopes']),
    );
  }

  factory _DriveFolder.fromLocalCacheJson(Map<String, dynamic> json) {
    final id = _trimmedOrNull(json['id']);
    if (id == null) {
      throw const FormatException('Cached folder entry is missing an id.');
    }

    final encryptedName = _trimmedOrNull(json['encryptedName']);
    return _DriveFolder(
      id: id,
      name: safeEncryptedDisplayLabel(
        placeholder: 'Encrypted folder',
        encryptedLabel: encryptedName,
        candidate: _trimmedOrNull(json['name']),
      ),
      encryptedName: encryptedName,
      metadataEncryption: _trimmedOrNull(json['metadataEncryption']),
      colorHex: _trimmedOrNull(json['colorHex']),
      createdAt: _DriveFile._parseTimestamp(json['createdAt']),
      updatedAt: _DriveFile._parseTimestamp(json['updatedAt']),
      lastFileAt: _DriveFile._parseTimestamp(json['lastFileAt']),
      systemFolder: json['systemFolder'] == true,
      systemKey: _trimmedOrNull(json['systemKey']),
      parentId: _trimmedOrNull(json['parentId']),
      storageScope: _normalizeStorageScope(json['storageScope']),
      companyId: _trimmedOrNull(json['companyId']),
      ownerUid: _trimmedOrNull(json['ownerUid']),
      createdByUid: _trimmedOrNull(json['createdByUid']),
      allowedUids: _stringListFrom(json['allowedUids']),
      groupIds: _stringListFrom(json['groupIds']),
      sharedKeyEnvelopes: _stringKeyedMap(json['sharedKeyEnvelopes']),
    );
  }

  Map<String, dynamic> toLocalCacheJson() {
    final payload = <String, dynamic>{
      'id': id,
      'name': name,
      'systemFolder': systemFolder,
    };

    if (colorHex != null && colorHex!.trim().isNotEmpty) {
      payload['colorHex'] = colorHex;
    }
    if (encryptedName != null && encryptedName!.trim().isNotEmpty) {
      payload['encryptedName'] = encryptedName;
    }
    if (metadataEncryption != null && metadataEncryption!.trim().isNotEmpty) {
      payload['metadataEncryption'] = metadataEncryption;
    }
    if (createdAt != null) {
      payload['createdAt'] = createdAt!.toIso8601String();
    }
    if (updatedAt != null) {
      payload['updatedAt'] = updatedAt!.toIso8601String();
    }
    if (lastFileAt != null) {
      payload['lastFileAt'] = lastFileAt!.toIso8601String();
    }
    if (systemKey != null && systemKey!.trim().isNotEmpty) {
      payload['systemKey'] = systemKey;
    }
    if (parentId != null && parentId!.trim().isNotEmpty) {
      payload['parentId'] = parentId;
    }
    if (storageScope != 'personal') {
      payload['storageScope'] = storageScope;
    }
    if (companyId != null && companyId!.trim().isNotEmpty) {
      payload['companyId'] = companyId;
    }
    if (ownerUid != null && ownerUid!.trim().isNotEmpty) {
      payload['ownerUid'] = ownerUid;
    }
    if (createdByUid != null && createdByUid!.trim().isNotEmpty) {
      payload['createdByUid'] = createdByUid;
    }
    if (allowedUids.isNotEmpty) {
      payload['allowedUids'] = allowedUids;
    }
    if (groupIds.isNotEmpty) {
      payload['groupIds'] = groupIds;
    }
    if (sharedKeyEnvelopes.isNotEmpty) {
      payload['sharedKeyEnvelopes'] = sharedKeyEnvelopes;
    }

    return payload;
  }
}

enum _BackupScanFrequency {
  rapid(
    'rapid',
    Duration(minutes: 1),
    'Every minute',
    'Catch changes almost immediately with the most frequent scans.',
  ),
  standard(
    'standard',
    Duration(minutes: 2),
    'Every 2 minutes',
    'Balanced scanning that keeps backups current without extra load.',
  ),
  relaxed(
    'relaxed',
    Duration(minutes: 5),
    'Every 5 minutes',
    'Run occasional scans to reduce background activity.',
  );

  const _BackupScanFrequency(
    this.storageKey,
    this.interval,
    this.title,
    this.description,
  );

  final String storageKey;
  final Duration interval;
  final String title;
  final String description;

  String get feedbackMessage =>
      'Automatic scans will run ${title.toLowerCase()}.';

  static _BackupScanFrequency fromStorageKey(String? key) {
    for (final option in _BackupScanFrequency.values) {
      if (option.storageKey == key) {
        return option;
      }
    }
    return _BackupScanFrequency.standard;
  }
}

enum _StorageDisplayMode { percentage, amount }

enum _StorageCapacityLocation { hidden, summaryCard, header }

enum _UploadCollisionChoice { keepBoth, replaceAsVersion, cancel }

enum _AccountMenuAction { signOut, manageSubscription, deleteAccount }

class _DriveFile {
  _DriveFile({
    required this.id,
    required this.name,
    required this.objectKey,
    required this.size,
    required this.isFolder,
    this.contentType,
    this.uploadedAt,
    List<String>? pathSegments,
    this.folderId,
    this.folderName,
    this.folderColor,
    this.etag,
    this.encryptionMode = 'unsecured',
    this.encryptedName,
    this.storageLayout = 'single',
    this.shardCount,
    this.shardSizeBytes,
    this.shardScheme,
    this.contentEncryption,
    this.secureContentEncoding,
    this.secureRefreshedAt,
    this.secureRefreshDueAt,
    this.hash,
    this.hasKnownSize = true,
    this.plaintextSizeBytes,
    this.hasThumbnail = false,
    this.storageScope = 'personal',
    this.companyId,
    this.ownerUid,
    this.createdByUid,
    this.lifecycleState = 'active',
    this.versionGroupId,
    this.revision = 1,
    this.backupPathHash,
    this.backupModifiedMillis,
    List<String>? allowedUids,
    List<String>? groupIds,
    Map<String, dynamic>? sharedKeyEnvelopes,
  }) : pathSegments = List<String>.unmodifiable(
         pathSegments ?? const <String>[],
       ),
       allowedUids = List<String>.unmodifiable(allowedUids ?? const <String>[]),
       groupIds = List<String>.unmodifiable(groupIds ?? const <String>[]),
       sharedKeyEnvelopes = Map<String, dynamic>.unmodifiable(
         sharedKeyEnvelopes ?? const <String, dynamic>{},
       );

  final String id;
  final String name;
  final String objectKey;
  final int size;
  final bool isFolder;
  final String? contentType;
  final DateTime? uploadedAt;
  final List<String> pathSegments;
  final String? folderId;
  final String? folderName;
  final String? folderColor;
  final String? etag;
  final String encryptionMode;
  final String? encryptedName;
  final String storageLayout;
  final int? shardCount;
  final int? shardSizeBytes;
  final String? shardScheme;
  final String? contentEncryption;
  final String? secureContentEncoding;
  final DateTime? secureRefreshedAt;
  final DateTime? secureRefreshDueAt;
  final String? hash;
  final bool hasKnownSize;
  final int? plaintextSizeBytes;
  final bool hasThumbnail;
  final String storageScope;
  final String? companyId;
  final String? ownerUid;
  final String? createdByUid;
  final String lifecycleState;
  final String? versionGroupId;
  final int revision;
  final String? backupPathHash;
  final int? backupModifiedMillis;
  final List<String> allowedUids;
  final List<String> groupIds;
  final Map<String, dynamic> sharedKeyEnvelopes;

  bool get isImageLike {
    final normalizedContentType = contentType?.trim().toLowerCase();
    if (normalizedContentType != null &&
        normalizedContentType.startsWith('image/')) {
      return true;
    }

    String extensionOf(String value) {
      final trimmed = value.trim().toLowerCase();
      if (trimmed.isEmpty) {
        return '';
      }
      final lastSegment = trimmed.split('/').last;
      final dotIndex = lastSegment.lastIndexOf('.');
      if (dotIndex < 0 || dotIndex == lastSegment.length - 1) {
        return '';
      }
      return lastSegment.substring(dotIndex + 1);
    }

    const imageExtensions = <String>{
      'bmp',
      'gif',
      'heic',
      'heif',
      'jpeg',
      'jpg',
      'png',
      'webp',
    };

    return imageExtensions.contains(extensionOf(name)) ||
        imageExtensions.contains(extensionOf(objectKey));
  }

  bool get supportsThumbnailPreview => hasThumbnail || isImageLike;

  bool get isActive => lifecycleState == 'active';

  bool get isSecured => encryptionMode == 'secured';

  bool get isStandardEncrypted => encryptionMode == 'standard';

  bool get isEncrypted => isSecured || isStandardEncrypted;

  bool get isSharded => storageLayout == 'sharded' && (shardCount ?? 0) > 0;

  bool get usesPassphraseHmacShards =>
      shardScheme == _WorkspaceHomePageState._secureShardSchemePassphraseHmacV1;

  bool get usesWholeFileSecureContent =>
      secureContentEncoding ==
      _WorkspaceHomePageState._secureContentEncodingWholeFileV1;

  bool isSecureRefreshOverdue(DateTime now) =>
      isSecured &&
      secureRefreshDueAt != null &&
      !secureRefreshDueAt!.isAfter(now);

  String? get derivedFolderId => _extractFolderIdFromObjectKey(objectKey);

  String get folderKey {
    final trimmedId = folderId?.trim();
    if (trimmedId != null && trimmedId.isNotEmpty) {
      return trimmedId;
    }
    final objectFolderId = derivedFolderId;
    if (objectFolderId != null && objectFolderId.isNotEmpty) {
      return objectFolderId;
    }
    final trimmedName = folderName?.trim();
    if (trimmedName != null && trimmedName.isNotEmpty) {
      return 'name::${trimmedName.toLowerCase()}';
    }
    return 'root';
  }

  String get folderLabel {
    final trimmedName = folderName?.trim();
    if (trimmedName != null && trimmedName.isNotEmpty) {
      return trimmedName;
    }
    final objectFolderId = derivedFolderId;
    if (objectFolderId != null && objectFolderId.isNotEmpty) {
      return 'Folder';
    }
    return 'My Drive';
  }

  factory _DriveFile.fromDocument(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final uploadedAt = _parseTimestamp(data['uploadedAt']);
    final folderId = _trimmedOrNull(data['folderId']);
    final folderName = _trimmedOrNull(data['folderName']);
    final folderColor = _trimmedOrNull(data['folderColor']);

    final objectKey = _resolveObjectKey(data, doc.id);
    final encryptedName = _trimmedOrNull(data['encryptedName']);
    final displayName = _resolveDisplayName(data, objectKey);
    final rawSizeValue = data['sizeBytes'] ?? data['size'];
    final size = _parseSize(rawSizeValue);
    final hasKnownSize = () {
      if (rawSizeValue == null) {
        return false;
      }
      if (rawSizeValue is num) {
        return true;
      }
      if (rawSizeValue is String) {
        final trimmed = rawSizeValue.trim();
        if (trimmed.isEmpty) {
          return false;
        }
        return double.tryParse(trimmed) != null;
      }
      return false;
    }();
    final hasThumbnail = data['hasThumbnail'] == true;
    final contentType = _trimmedOrNull(data['contentType']);
    final etag = _trimmedOrNull(data['etag']);
    final encryptionMode = _normalizeEncryptionMode(data['encryptionMode']);
    final storageLayout = _normalizeStorageLayout(data['storageLayout']);
    final shardCount = _parseOptionalPositiveInt(data['shardCount']);
    final shardSizeBytes = _parseOptionalPositiveInt(data['shardSizeBytes']);
    final shardScheme = _trimmedOrNull(data['shardScheme']);
    final contentEncryption = _trimmedOrNull(data['contentEncryption']);
    final secureContentEncoding = _trimmedOrNull(data['secureContentEncoding']);
    final secureRefreshedAt = _parseTimestamp(data['secureRefreshedAt']);
    final secureRefreshDueAt = _parseTimestamp(data['secureRefreshDueAt']);
    final rawHash =
        data['contentIntegrityTag'] ?? data['hashBase64'] ?? data['hash'];
    final parsedHash = rawHash is String ? rawHash.trim() : '';
    final hash = parsedHash.isEmpty ? null : parsedHash;

    final pathSegments = <String>[];
    final rawSegments = data['pathSegments'];
    if (rawSegments is Iterable) {
      for (final segment in rawSegments) {
        if (segment is String && segment.trim().isNotEmpty) {
          pathSegments.add(segment.trim());
        }
      }
    }

    final isFolder = data['isFolder'] == true || contentType == 'folder';

    return _DriveFile(
      id: doc.id,
      name: displayName,
      objectKey: objectKey,
      size: size,
      isFolder: isFolder,
      contentType: contentType,
      uploadedAt: uploadedAt,
      pathSegments: pathSegments,
      folderId: folderId,
      folderName: folderName,
      folderColor: folderColor,
      etag: etag,
      encryptionMode: encryptionMode,
      encryptedName: encryptedName,
      storageLayout: storageLayout,
      shardCount: shardCount,
      shardSizeBytes: shardSizeBytes,
      shardScheme: shardScheme,
      contentEncryption: contentEncryption,
      secureContentEncoding: secureContentEncoding,
      secureRefreshedAt: secureRefreshedAt,
      secureRefreshDueAt: secureRefreshDueAt,
      hash: hash,
      hasKnownSize: hasKnownSize,
      plaintextSizeBytes: data['sizeBytes'] is num && (data['sizeBytes'] as num).isFinite &&
        (data['sizeBytes'] as num)>=0 && (data['sizeBytes'] as num).round()==data['sizeBytes'] &&
        ((encryptionMode=='standard' && contentEncryption=='standard') ||
         (encryptionMode=='secured' && secureContentEncoding=='whole-file-aes-ctr-hmac-sha256-v1'))
        ? (data['sizeBytes'] as num).toInt() : null,
      hasThumbnail: hasThumbnail,
      storageScope: _normalizeStorageScope(data['storageScope']),
      companyId: _trimmedOrNull(data['companyId']),
      ownerUid: _trimmedOrNull(data['ownerUid']),
      createdByUid: _trimmedOrNull(data['createdByUid']),
      lifecycleState: _normalizeLifecycleState(data['lifecycleState']),
      versionGroupId: _trimmedOrNull(data['versionGroupId']),
      revision: _parseOptionalPositiveInt(data['revision']) ?? 1,
      backupPathHash: _trimmedOrNull(data['backupPathHash']),
      backupModifiedMillis: _parseOptionalPositiveInt(
        data['backupModifiedMillis'],
      ),
      allowedUids: _stringListFrom(data['allowedUids']),
      groupIds: _stringListFrom(data['groupIds']),
      sharedKeyEnvelopes: _stringKeyedMap(data['sharedKeyEnvelopes']),
    );
  }

  factory _DriveFile.fromLocalCacheJson(Map<String, dynamic> json) {
    final id = _trimmedOrNull(json['id']);
    final objectKey = _trimmedOrNull(json['objectKey']);
    if (id == null || objectKey == null) {
      throw const FormatException(
        'Cached file entry is missing an id or object key.',
      );
    }

    final encryptionMode = _normalizeEncryptionMode(json['encryptionMode']);
    final storageLayout = _normalizeStorageLayout(json['storageLayout']);
    final shardCount = _parseOptionalPositiveInt(json['shardCount']);
    final shardSizeBytes = _parseOptionalPositiveInt(json['shardSizeBytes']);
    final shardScheme = _trimmedOrNull(json['shardScheme']);
    final contentEncryption = _trimmedOrNull(json['contentEncryption']);
    final secureContentEncoding = _trimmedOrNull(json['secureContentEncoding']);
    final secureRefreshedAt = _parseTimestamp(json['secureRefreshedAt']);
    final secureRefreshDueAt = _parseTimestamp(json['secureRefreshDueAt']);
    final encryptedName = _trimmedOrNull(json['encryptedName']);
    final storedName = _trimmedOrNull(json['name']);
    final fallbackSegment = objectKey.split('/').last.trim();
    final displayName = safeEncryptedDisplayLabel(
      placeholder: encryptionMode == 'secured'
          ? 'Secure file'
          : 'Encrypted file',
      encryptedLabel: encryptedName,
      candidate:
          storedName ??
          (encryptedName == null && fallbackSegment.isNotEmpty
              ? fallbackSegment
              : null),
    );

    final pathSegments = <String>[];
    final rawSegments = json['pathSegments'];
    if (rawSegments is Iterable) {
      for (final segment in rawSegments) {
        if (segment is String && segment.trim().isNotEmpty) {
          pathSegments.add(segment.trim());
        }
      }
    }

    final hasKnownSize = json['hasKnownSize'];
    final hasThumbnail = json['hasThumbnail'];

    return _DriveFile(
      id: id,
      name: displayName,
      objectKey: objectKey,
      size: _parseSize(json['size']),
      isFolder: json['isFolder'] == true,
      contentType: _trimmedOrNull(json['contentType']),
      uploadedAt: _parseTimestamp(json['uploadedAt']),
      pathSegments: pathSegments,
      folderId: _trimmedOrNull(json['folderId']),
      folderName: _trimmedOrNull(json['folderName']),
      folderColor: _trimmedOrNull(json['folderColor']),
      etag: _trimmedOrNull(json['etag']),
      encryptionMode: encryptionMode,
      encryptedName: encryptedName,
      storageLayout: storageLayout,
      shardCount: shardCount,
      shardSizeBytes: shardSizeBytes,
      shardScheme: shardScheme,
      contentEncryption: contentEncryption,
      secureContentEncoding: secureContentEncoding,
      secureRefreshedAt: secureRefreshedAt,
      secureRefreshDueAt: secureRefreshDueAt,
      hash: _trimmedOrNull(json['hash']),
      hasKnownSize: hasKnownSize is bool ? hasKnownSize : true,
      plaintextSizeBytes: json['plaintextSizeBytes'] is int ? json['plaintextSizeBytes'] as int : null,
      hasThumbnail: hasThumbnail is bool ? hasThumbnail : false,
      storageScope: _normalizeStorageScope(json['storageScope']),
      companyId: _trimmedOrNull(json['companyId']),
      ownerUid: _trimmedOrNull(json['ownerUid']),
      createdByUid: _trimmedOrNull(json['createdByUid']),
      lifecycleState: _normalizeLifecycleState(json['lifecycleState']),
      versionGroupId: _trimmedOrNull(json['versionGroupId']),
      revision: _parseOptionalPositiveInt(json['revision']) ?? 1,
      backupPathHash: _trimmedOrNull(json['backupPathHash']),
      backupModifiedMillis: _parseOptionalPositiveInt(
        json['backupModifiedMillis'],
      ),
      allowedUids: _stringListFrom(json['allowedUids']),
      groupIds: _stringListFrom(json['groupIds']),
      sharedKeyEnvelopes: _stringKeyedMap(json['sharedKeyEnvelopes']),
    );
  }

  Map<String, dynamic> toLocalCacheJson() {
    final payload = <String, dynamic>{
      'id': id,
      'objectKey': objectKey,
      'size': size,
      'isFolder': isFolder,
      'encryptionMode': encryptionMode,
      'storageLayout': storageLayout,
      'hasKnownSize': hasKnownSize,
      if(plaintextSizeBytes!=null) 'plaintextSizeBytes':plaintextSizeBytes,
      'hasThumbnail': hasThumbnail,
      'lifecycleState': lifecycleState,
      'revision': revision,
    };

    if (!isSecured) {
      payload['name'] = name;
    }
    if (contentType != null && contentType!.trim().isNotEmpty) {
      payload['contentType'] = contentType;
    }
    if (uploadedAt != null) {
      payload['uploadedAt'] = uploadedAt!.toIso8601String();
    }
    if (pathSegments.isNotEmpty) {
      payload['pathSegments'] = pathSegments;
    }
    if (folderId != null && folderId!.trim().isNotEmpty) {
      payload['folderId'] = folderId;
    }
    if (folderName != null && folderName!.trim().isNotEmpty) {
      payload['folderName'] = folderName;
    }
    if (folderColor != null && folderColor!.trim().isNotEmpty) {
      payload['folderColor'] = folderColor;
    }
    if (etag != null && etag!.trim().isNotEmpty) {
      payload['etag'] = etag;
    }
    if (encryptedName != null && encryptedName!.trim().isNotEmpty) {
      payload['encryptedName'] = encryptedName;
    }
    if (shardCount != null) {
      payload['shardCount'] = shardCount;
    }
    if (shardSizeBytes != null) {
      payload['shardSizeBytes'] = shardSizeBytes;
    }
    if (shardScheme != null && shardScheme!.trim().isNotEmpty) {
      payload['shardScheme'] = shardScheme;
    }
    if (contentEncryption != null && contentEncryption!.trim().isNotEmpty) {
      payload['contentEncryption'] = contentEncryption;
    }
    if (secureContentEncoding != null &&
        secureContentEncoding!.trim().isNotEmpty) {
      payload['secureContentEncoding'] = secureContentEncoding;
    }
    if (secureRefreshedAt != null) {
      payload['secureRefreshedAt'] = secureRefreshedAt!.toIso8601String();
    }
    if (secureRefreshDueAt != null) {
      payload['secureRefreshDueAt'] = secureRefreshDueAt!.toIso8601String();
    }
    if (hash != null && hash!.trim().isNotEmpty) {
      payload['hash'] = hash;
    }
    if (versionGroupId != null && versionGroupId!.trim().isNotEmpty) {
      payload['versionGroupId'] = versionGroupId;
    }
    if (backupPathHash != null && backupPathHash!.trim().isNotEmpty) {
      payload['backupPathHash'] = backupPathHash;
    }
    if (backupModifiedMillis != null) {
      payload['backupModifiedMillis'] = backupModifiedMillis;
    }
    if (storageScope != 'personal') {
      payload['storageScope'] = storageScope;
    }
    if (companyId != null && companyId!.trim().isNotEmpty) {
      payload['companyId'] = companyId;
    }
    if (ownerUid != null && ownerUid!.trim().isNotEmpty) {
      payload['ownerUid'] = ownerUid;
    }
    if (createdByUid != null && createdByUid!.trim().isNotEmpty) {
      payload['createdByUid'] = createdByUid;
    }
    if (allowedUids.isNotEmpty) {
      payload['allowedUids'] = allowedUids;
    }
    if (groupIds.isNotEmpty) {
      payload['groupIds'] = groupIds;
    }
    if (sharedKeyEnvelopes.isNotEmpty) {
      payload['sharedKeyEnvelopes'] = sharedKeyEnvelopes;
    }

    return payload;
  }

  static String _resolveObjectKey(Map<String, dynamic> data, String fallback) {
    final candidates = <String?>[
      _trimmedOrNull(data['fileName']),
      _trimmedOrNull(data['objectKey']),
    ];
    for (final candidate in candidates) {
      if (candidate != null && candidate.trim().isNotEmpty) {
        return candidate.trim();
      }
    }
    return fallback;
  }

  static String _resolveDisplayName(
    Map<String, dynamic> data,
    String objectKey,
  ) {
    final isSecured =
        _normalizeEncryptionMode(data['encryptionMode']) == 'secured';
    final encryptedName = _trimmedOrNull(data['encryptedName']);
    if (encryptedName != null) {
      return isSecured ? 'Secure file' : 'Encrypted file';
    }
    final candidates = isSecured
        ? <String?>[_trimmedOrNull(data['name']), 'Secure file']
        : <String?>[
            _trimmedOrNull(data['originalName']),
            _trimmedOrNull(data['name']),
          ];
    for (final candidate in candidates) {
      if (candidate != null && candidate.trim().isNotEmpty) {
        return safeEncryptedDisplayLabel(
          placeholder: isSecured ? 'Secure file' : 'Encrypted file',
          candidate: candidate,
        );
      }
    }

    final lastSegment = objectKey.split('/').last;
    final encryptedMarker = '.e.';
    final markerIndex = lastSegment.indexOf(encryptedMarker);
    if (markerIndex > 0 &&
        markerIndex + encryptedMarker.length < lastSegment.length) {
      return safeEncryptedDisplayLabel(
        placeholder: isSecured ? 'Secure file' : 'Encrypted file',
        candidate: lastSegment.substring(markerIndex + encryptedMarker.length),
      );
    }
    final underscoreIndex = lastSegment.indexOf('_');
    if (underscoreIndex > 0 && underscoreIndex < lastSegment.length - 1) {
      return safeEncryptedDisplayLabel(
        placeholder: isSecured ? 'Secure file' : 'Encrypted file',
        candidate: lastSegment.substring(underscoreIndex + 1),
      );
    }
    final dashIndex = lastSegment.indexOf('-');
    if (dashIndex > 0 && dashIndex < lastSegment.length - 1) {
      return safeEncryptedDisplayLabel(
        placeholder: isSecured ? 'Secure file' : 'Encrypted file',
        candidate: lastSegment.substring(dashIndex + 1),
      );
    }
    return safeEncryptedDisplayLabel(
      placeholder: isSecured ? 'Secure file' : 'Encrypted file',
      candidate: lastSegment,
    );
  }

  static String? _extractFolderIdFromObjectKey(String objectKey) {
    const marker = '/folders/';
    final markerIndex = objectKey.indexOf(marker);
    if (markerIndex == -1) {
      return null;
    }
    final remainder = objectKey.substring(markerIndex + marker.length);
    if (remainder.isEmpty) {
      return null;
    }
    final rawSegment = remainder.split('/').first.trim();
    if (rawSegment.isEmpty) {
      return null;
    }
    return Uri.decodeComponent(rawSegment);
  }

  static int _parseSize(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is double) {
      return value.round();
    }
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) {
        return parsed;
      }
      final numeric = double.tryParse(value);
      if (numeric != null) {
        return numeric.round();
      }
    }
    return 0;
  }

  static int? _parseOptionalPositiveInt(dynamic value) {
    final parsed = _parseSize(value);
    return parsed > 0 ? parsed : null;
  }

  static DateTime? _parseTimestamp(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    if (value is String) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}

String? _trimmedOrNull(dynamic value) {
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return null;
}

List<String> _stringListFrom(dynamic value) {
  if (value is! Iterable) {
    return const <String>[];
  }
  return value.map(_trimmedOrNull).whereType<String>().toList(growable: false);
}

Map<String, dynamic> _stringKeyedMap(dynamic value) {
  if (value is! Map) {
    return const <String, dynamic>{};
  }
  return Map<String, dynamic>.fromEntries(
    value.entries.map((entry) => MapEntry(entry.key.toString(), entry.value)),
  );
}

String _normalizeStorageScope(dynamic value) {
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'company_private' ||
        normalized == 'company_shared' ||
        normalized == 'group') {
      return normalized;
    }
  }
  return 'personal';
}

String _normalizeLifecycleState(dynamic value) {
  final normalized = value?.toString().trim().toLowerCase();
  return switch (normalized) {
    'trashed' => 'trashed',
    'version' => 'version',
    _ => 'active',
  };
}

String _normalizeEncryptionMode(dynamic value) {
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'secured' || normalized == 'standard') {
      return normalized;
    }
  }
  return 'unsecured';
}

String _normalizeStorageLayout(dynamic value) {
  if (value is String && value.trim().toLowerCase() == 'sharded') {
    return 'sharded';
  }
  return 'single';
}

class _OfflineFileInfo {
  const _OfflineFileInfo({
    required this.objectKey,
    required this.localPath,
    required this.downloadedAt,
    this.etag,
    this.size,
    this.folderKey,
    this.managedByFolder = false,
    this.storageFormat = 'legacy-plaintext',
  });

  final String objectKey;
  final String localPath;
  final DateTime downloadedAt;
  final String? etag;
  final int? size;
  final String? folderKey;
  final bool managedByFolder;
  final String storageFormat;

  bool get isEncryptedVault => storageFormat == LocalOfflineVault.storageFormat;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'objectKey': objectKey,
      'localPath': localPath,
      'downloadedAt': downloadedAt.toIso8601String(),
      'etag': etag,
      'size': size,
      'folderKey': folderKey,
      'managedByFolder': managedByFolder,
      'storageFormat': storageFormat,
    };
  }

  _OfflineFileInfo copyWith({
    String? localPath,
    DateTime? downloadedAt,
    String? etag,
    int? size,
    String? folderKey,
    bool? managedByFolder,
    String? storageFormat,
  }) {
    return _OfflineFileInfo(
      objectKey: objectKey,
      localPath: localPath ?? this.localPath,
      downloadedAt: downloadedAt ?? this.downloadedAt,
      etag: etag ?? this.etag,
      size: size ?? this.size,
      folderKey: folderKey ?? this.folderKey,
      managedByFolder: managedByFolder ?? this.managedByFolder,
      storageFormat: storageFormat ?? this.storageFormat,
    );
  }

  factory _OfflineFileInfo.fromJson(Map<String, dynamic> json) {
    final dynamic rawSize = json['size'];
    int? parsedSize;
    if (rawSize is int) {
      parsedSize = rawSize;
    } else if (rawSize is double) {
      parsedSize = rawSize.toInt();
    }

    return _OfflineFileInfo(
      objectKey: json['objectKey'] as String,
      localPath: json['localPath'] as String,
      downloadedAt:
          DateTime.tryParse(json['downloadedAt'] as String? ?? '') ??
          DateTime.now(),
      etag: json['etag'] as String?,
      size: parsedSize,
      folderKey: json['folderKey'] as String?,
      managedByFolder: json['managedByFolder'] == true,
      storageFormat:
          (json['storageFormat'] as String?)?.trim() ?? 'legacy-plaintext',
    );
  }
}

class _OfflineFolderConfig {
  const _OfflineFolderConfig({
    required this.folderKey,
    required this.folderName,
    required this.addedAt,
  });

  final String folderKey;
  final String folderName;
  final DateTime addedAt;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'folderKey': folderKey,
      'folderName': folderName,
      'addedAt': addedAt.toIso8601String(),
    };
  }

  factory _OfflineFolderConfig.fromJson(Map<String, dynamic> json) {
    final rawName = (json['folderName'] as String?)?.trim();
    final addedAtRaw = json['addedAt'];
    DateTime addedAt;
    if (addedAtRaw is String) {
      addedAt = DateTime.tryParse(addedAtRaw) ?? DateTime.now();
    } else {
      addedAt = DateTime.now();
    }

    return _OfflineFolderConfig(
      folderKey: json['folderKey'] as String,
      folderName: (rawName == null || rawName.isEmpty) ? 'Folder' : rawName,
      addedAt: addedAt,
    );
  }
}

class _BackupFolderConfig {
  const _BackupFolderConfig({
    required this.localPath,
    required this.remoteFolder,
    required this.enabled,
    required this.lastSynced,
    this.photoLibrary = false,
    this.accessBookmark,
  });

  final String localPath;
  final String remoteFolder;
  final bool photoLibrary;
  final String? accessBookmark;
  final bool enabled;
  final DateTime? lastSynced;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'localPath': localPath,
      'remoteFolder': remoteFolder,
      'photoLibrary': photoLibrary,
      if (accessBookmark != null) 'accessBookmark': accessBookmark,
      'enabled': enabled,
      'lastSynced': lastSynced?.toIso8601String(),
    };
  }

  _BackupFolderConfig copyWith({bool? enabled, DateTime? lastSynced}) {
    return _BackupFolderConfig(
      localPath: localPath,
      photoLibrary: photoLibrary,
      accessBookmark: accessBookmark,
      remoteFolder: remoteFolder,
      enabled: enabled ?? this.enabled,
      lastSynced: lastSynced ?? this.lastSynced,
    );
  }

  factory _BackupFolderConfig.fromJson(Map<String, dynamic> json) {
    return _BackupFolderConfig(
      localPath: json['localPath'] as String,
      photoLibrary: json['photoLibrary'] == true,
      accessBookmark: json['accessBookmark'] as String?,
      remoteFolder: json['remoteFolder'] as String,
      enabled: json['enabled'] as bool? ?? false,
      lastSynced: json['lastSynced'] == null
          ? null
          : DateTime.tryParse(json['lastSynced'] as String) ?? DateTime.now(),
    );
  }
}

class _BackupCandidate {
  const _BackupCandidate({required this.file, required this.stat});

  final File file;
  final FileStat stat;
}

class _RadioOptionTile<T> extends StatelessWidget {
  const _RadioOptionTile({
    required this.value,
    required this.groupValue,
    required this.title,
    this.subtitle,
    required this.onSelected,
    this.isEnabled = true,
  });

  final T value;
  final T groupValue;
  final Widget title;
  final Widget? subtitle;
  final FutureOr<void> Function(T value) onSelected;
  final bool isEnabled;

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    final theme = Theme.of(context);
    final iconColor = !isEnabled
        ? theme.disabledColor
        : selected
        ? theme.colorScheme.primary
        : theme.iconTheme.color;

    return ListTile(
      enabled: isEnabled,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
        color: iconColor,
      ),
      title: title,
      subtitle: subtitle,
      onTap: !isEnabled
          ? null
          : () {
              final result = onSelected(value);
              if (result is Future) {
                unawaited(result);
              }
            },
    );
  }
}

class _SessionExpiredException implements Exception {
  _SessionExpiredException({this.message, this.cause});

  final String? message;
  final Object? cause;

  @override
  String toString() {
    if (message != null && message!.isNotEmpty) {
      return 'SessionExpiredException: $message';
    }
    if (cause != null) {
      return 'SessionExpiredException: ${cause.toString()}';
    }
    return 'SessionExpiredException';
  }
}

class EncryptionOperationException implements Exception {
  const EncryptionOperationException(this.message);

  final String message;

  @override
  String toString() => 'EncryptionOperationException: $message';
}

class _BackupFileResult {
  const _BackupFileResult._({
    required this.didUpload,
    required this.uploadedBytes,
    required this.failed,
    this.fileName,
    required this.shouldRetry,
  });

  final bool didUpload;
  final int uploadedBytes;
  final bool failed;
  final String? fileName;
  final bool shouldRetry;

  factory _BackupFileResult.success({
    required int uploadedBytes,
    required String fileName,
  }) {
    return _BackupFileResult._(
      didUpload: true,
      uploadedBytes: uploadedBytes,
      failed: false,
      fileName: fileName,
      shouldRetry: false,
    );
  }

  factory _BackupFileResult.skipped() {
    return const _BackupFileResult._(
      didUpload: false,
      uploadedBytes: 0,
      failed: false,
      shouldRetry: false,
    );
  }

  factory _BackupFileResult.failure({bool shouldRetry = true}) {
    return _BackupFileResult._(
      didUpload: false,
      uploadedBytes: 0,
      failed: true,
      shouldRetry: shouldRetry,
    );
  }
}

class _BandwidthLimitOption {
  const _BandwidthLimitOption({
    required this.label,
    required this.value,
    required this.description,
  });

  final String label;
  final int value;
  final String description;
}

enum _BandwidthLimitUnit {
  kilobytesPerSecond('KB/s', 1024),
  megabytesPerSecond('MB/s', 1024 * 1024);

  const _BandwidthLimitUnit(this.label, this.bytesPerSecond);

  final String label;
  final int bytesPerSecond;
}

class _CapacityInfo {
  const _CapacityInfo({this.limitBytes, this.label, this.pending = false});

  final double? limitBytes;
  final String? label;
  final bool pending;

  bool get hasLimit =>
      limitBytes != null && limitBytes!.isFinite && limitBytes! > 0;
}

class _BackupFileFingerprint {
  const _BackupFileFingerprint({
    required this.localPath,
    required this.size,
    required this.modified,
    this.hash = '',
    this.remoteIntegrityTag = '',
  });

  final String localPath;
  final int size;
  final DateTime modified;
  final String hash;
  final String remoteIntegrityTag;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'localPath': localPath,
      'size': size,
      'modified': modified.toIso8601String(),
      'modifiedMillis': modified.toUtc().millisecondsSinceEpoch,
      'hash': hash,
      'remoteIntegrityTag': remoteIntegrityTag,
    };
  }

  _BackupFileFingerprint copyWith({
    String? localPath,
    int? size,
    DateTime? modified,
    String? hash,
    String? remoteIntegrityTag,
  }) {
    return _BackupFileFingerprint(
      localPath: localPath ?? this.localPath,
      size: size ?? this.size,
      modified: modified ?? this.modified,
      hash: hash ?? this.hash,
      remoteIntegrityTag: remoteIntegrityTag ?? this.remoteIntegrityTag,
    );
  }

  bool matches(_BackupFileFingerprint other) {
    if (hash.isNotEmpty && other.hash.isNotEmpty) {
      return hash == other.hash;
    }
    return size == other.size &&
        modified.toUtc().millisecondsSinceEpoch ==
            other.modified.toUtc().millisecondsSinceEpoch;
  }

  factory _BackupFileFingerprint.fromJson(Map<String, dynamic> json) {
    final path = json['localPath'] as String? ?? '';
    final rawSize = json['size'];
    int size = 0;
    if (rawSize is int) {
      size = rawSize;
    } else if (rawSize is double) {
      size = rawSize.round();
    } else if (rawSize is String) {
      size = int.tryParse(rawSize) ?? 0;
    }
    if (size < 0) {
      size = 0;
    }

    DateTime? parsedModified;
    final modifiedIso = json['modified'] as String?;
    if (modifiedIso != null && modifiedIso.isNotEmpty) {
      parsedModified = DateTime.tryParse(modifiedIso)?.toUtc();
    }
    if (parsedModified == null) {
      final rawMillis = json['modifiedMillis'];
      if (rawMillis is int) {
        parsedModified = DateTime.fromMillisecondsSinceEpoch(
          rawMillis,
          isUtc: true,
        );
      } else if (rawMillis is double) {
        parsedModified = DateTime.fromMillisecondsSinceEpoch(
          rawMillis.round(),
          isUtc: true,
        );
      }
    }

    final resolvedModified =
        parsedModified ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

    final rawHash = json['hash'];
    final parsedHash = rawHash is String ? rawHash.trim() : '';

    return _BackupFileFingerprint(
      localPath: path,
      size: size,
      modified: resolvedModified,
      hash: parsedHash,
      remoteIntegrityTag: (json['remoteIntegrityTag'] as String? ?? '').trim(),
    );
  }
}

class _EncryptionPassphraseDialog extends StatefulWidget {
  const _EncryptionPassphraseDialog({
    required this.isRotation,
    required this.forcePrompt,
    this.title,
    this.description,
    this.submitLabel,
  });

  final bool isRotation;
  final bool forcePrompt;
  final String? title;
  final String? description;
  final String? submitLabel;

  @override
  State<_EncryptionPassphraseDialog> createState() =>
      _EncryptionPassphraseDialogState();
}

class _EncryptionPassphraseDialogState
    extends State<_EncryptionPassphraseDialog> {
  final TextEditingController _controller = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Expanded(
            child: Text(
              widget.title ??
                  (widget.isRotation
                      ? 'Rotate encryption passphrase'
                      : 'Create encryption passphrase'),
            ),
          ),
          if (!widget.forcePrompt)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Close',
              onPressed: () => Navigator.of(context).pop(),
            ),
        ],
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.description ??
                  (widget.isRotation
                      ? 'Replace your existing passphrase before any secure files are uploaded.'
                      : 'Set a separate passphrase for advanced secure mode. It stays on this device and cannot be recovered if lost.'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _controller,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              autofillHints: const <String>[],
              enableInteractiveSelection: false,
              keyboardType: TextInputType.visiblePassword,
              decoration: const InputDecoration(
                labelText: 'Encryption passphrase',
                hintText: 'Use at least 12 characters',
              ),
              validator: (value) {
                final trimmed = value?.trim() ?? '';
                if (trimmed.length < 12) {
                  return 'Use at least 12 characters.';
                }
                if (!RegExp(r'[A-Z]').hasMatch(trimmed)) {
                  return 'Include an uppercase letter.';
                }
                if (!RegExp(r'[0-9]').hasMatch(trimmed)) {
                  return 'Include a number.';
                }
                return null;
              },
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            const Text(
              'The advanced-mode key clears when you sign out.',
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
      ),
      actions: [
        if (!widget.forcePrompt)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        FilledButton(
          onPressed: _submit,
          child: Text(
            widget.submitLabel ??
                (widget.isRotation ? 'Replace key' : 'Activate key'),
          ),
        ),
      ],
    );
  }
}

class _OfflineEntry {
  const _OfflineEntry({required this.file, required this.info});

  final _DriveFile file;
  final _OfflineFileInfo info;
}

String _formatBytes(int bytes) {
  if (bytes <= 0) {
    return '0 B';
  }
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = bytes.toDouble();
  var unitIndex = 0;
  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex++;
  }
  final fractionDigits = unitIndex == 0 ? 0 : 1;
  return '${size.toStringAsFixed(fractionDigits)} ${units[unitIndex]}';
}

String _formatRelativeTime(DateTime time) {
  final now = DateTime.now();
  final difference = now.difference(time);
  if (difference.inMinutes < 1) {
    return 'Just now';
  }
  if (difference.inHours < 1) {
    return '${difference.inMinutes} min ago';
  }
  if (difference.inHours < 24) {
    return '${difference.inHours} hr ago';
  }
  if (difference.inDays < 7) {
    final days = difference.inDays;
    return '$days day${days == 1 ? '' : 's'} ago';
  }
  return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
}

class _ThumbnailImage extends StatefulWidget {
  const _ThumbnailImage({super.key, required this.file, required this.fetcher});

  final _DriveFile file;
  final Future<Uint8List?> Function(
    _DriveFile file, {
    bool force,
    bool interactive,
  })
  fetcher;

  @override
  State<_ThumbnailImage> createState() => _ThumbnailImageState();
}

class _ThumbnailImageState extends State<_ThumbnailImage> {
  static const Duration _loadTimeout = Duration(seconds: 30);

  Uint8List? _bytes;
  String? _requestedObjectKey;
  Timer? _retryTimer;
  int _automaticRetryCount = 0;
  bool _loading = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  @override
  void didUpdateWidget(covariant _ThumbnailImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final objectChanged = oldWidget.file.objectKey != widget.file.objectKey;
    final previewCapabilityChanged =
        oldWidget.file.supportsThumbnailPreview !=
        widget.file.supportsThumbnailPreview;
    if (objectChanged || previewCapabilityChanged) {
      _retryTimer?.cancel();
      _automaticRetryCount = 0;
    }
    if (objectChanged || previewCapabilityChanged || _bytes == null) {
      _loadThumbnail(
        resetBytes: objectChanged || !widget.file.supportsThumbnailPreview,
      );
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  bool _scheduleAutomaticRetry() {
    if (_retryTimer?.isActive == true) {
      return true;
    }
    if (!ImageThumbnailRetryPolicy.canRetryAutomatically(
      isImageLike: widget.file.isImageLike,
      completedRetries: _automaticRetryCount,
    )) {
      return false;
    }
    final delay = ImageThumbnailRetryPolicy.delayBeforeNextRetry(
      _automaticRetryCount,
    );
    _automaticRetryCount += 1;
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      if (!mounted || _bytes != null) {
        return;
      }
      _loadThumbnail(force: true);
    });
    return true;
  }

  void _loadThumbnail({
    bool resetBytes = false,
    bool force = false,
    bool interactive = false,
  }) {
    if (!widget.file.supportsThumbnailPreview) {
      _requestedObjectKey = null;
      _retryTimer?.cancel();
      if (resetBytes && _bytes != null && mounted) {
        setState(() {
          _bytes = null;
          _loading = false;
          _failed = false;
        });
      } else {
        _bytes = null;
        _loading = false;
        _failed = false;
      }
      return;
    }

    final objectKey = widget.file.objectKey;
    if (_loading && !force && !resetBytes) {
      return;
    }
    if (force) {
      _retryTimer?.cancel();
    }
    if (!force &&
        !resetBytes &&
        _requestedObjectKey == objectKey &&
        _bytes != null) {
      return;
    }
    _requestedObjectKey = objectKey;
    if (mounted) {
      setState(() {
        if (resetBytes || force) {
          _bytes = null;
        }
        _loading = true;
        _failed = false;
      });
    } else {
      _loading = true;
      _failed = false;
    }
    widget
        .fetcher(widget.file, force: force, interactive: interactive)
        .timeout(_loadTimeout)
        .then((bytes) {
          if (!mounted) {
            return;
          }
          final retryScheduled = bytes == null && _scheduleAutomaticRetry();
          setState(() {
            _bytes = bytes;
            _loading = retryScheduled;
            _failed = bytes == null && !retryScheduled;
          });
          if (bytes != null) {
            _retryTimer?.cancel();
            _automaticRetryCount = 0;
          }
        })
        .catchError((error) {
          if (!mounted) {
            return;
          }
          final retryScheduled = _scheduleAutomaticRetry();
          setState(() {
            _loading = retryScheduled;
            _failed = !retryScheduled;
          });
        });
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes != null) {
      if (kDebugMode) {}
      return Image.memory(
        _bytes!,
        semanticLabel: 'Thumbnail of ${widget.file.name}',
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
      );
    }

    final theme = Theme.of(context);
    final isImage = widget.file.isImageLike;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _failed
            ? () => _loadThumbnail(force: true, interactive: true)
            : null,
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                widget.file.isFolder
                    ? Icons.folder_rounded
                    : isImage
                    ? Icons.image_outlined
                    : Icons.insert_drive_file_rounded,
                color: theme.colorScheme.primary.withValues(alpha: 0.5),
                size: 34,
              ),
              if (_loading)
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              if (_failed)
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: Tooltip(
                    message: widget.file.isEncrypted
                        ? 'Unlock or retry image preview'
                        : 'Retry image preview',
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface.withValues(
                          alpha: 0.92,
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.refresh_rounded),
                        iconSize: 18,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 32,
                          height: 32,
                        ),
                        onPressed: () =>
                            _loadThumbnail(force: true, interactive: true),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
