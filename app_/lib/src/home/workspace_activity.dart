part of 'workspace_home_page.dart';

extension _WorkspaceActivity on _WorkspaceHomePageState {
  bool get _activityAccountCurrent =>
      mounted &&
      !_sessionInvalidated &&
      widget.auth.currentUser?.uid == widget.user.uid;
  Future<void> _initializeActivity() async {
    final ownerUid = widget.user.uid;
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      if (!_activityAccountCurrent || widget.user.uid != ownerUid) return;
      final store = UserActivityStore(
        prefs,
        uid: widget.user.uid,
        scope: _localPrivateCacheScope(),
      );
      _activityStore = store;
      NotificationService().bindAccount(store.account);
      _activitySubscription = UserActivityStore.changes
          .where((account) => account == store.account)
          .listen((_) {
            if (_activityAccountCurrent) setState(() {});
          });
      _notificationOpenSubscription = NotificationService().opens
          .where((account) => account == store.account)
          .listen((_) {
            if (_activityAccountCurrent) setState(() {});
          });
      // Unsupported OS notification delivery must not prevent in-app activity.
      try {
        await NotificationService().initialize();
      } catch (_) {}
      if (!_activityAccountCurrent) return;
      await _refreshActivity();
      _recordTransferAttention();
    } catch (_) {
      if (mounted) setState(() => _activityUnavailable = true);
    }
  }

  void _consumeActivityNotification() {
    if (!_activityAccountCurrent ||
        _initializing ||
        !_legalAcceptanceCurrent ||
        _legalAcceptancePromptVisible ||
        _walkthroughVisible ||
        _activityCenterOpen) {
      return;
    }
    final store = _activityStore;
    if (store != null && NotificationService().takePending(store.account)) {
      unawaited(_openActivityCenter());
    }
  }

  Future<void> _refreshActivity() async {
    try {
      await _activityStore?.reload();
      if (_activityAccountCurrent) setState(() => _activityUnavailable = false);
    } catch (_) {
      if (mounted) setState(() => _activityUnavailable = true);
    }
  }

  Future<void> _recordActivity(
    ActivityKind kind, {
    bool resolved = false,
  }) async {
    final store = _activityStore;
    if (store == null || !_activityAccountCurrent) return;
    await NotificationService().record(
      store,
      kind,
      resolved: resolved,
      accountCurrent: () =>
          _activityAccountCurrent && identical(_activityStore, store),
    );
  }

  void _recordTransferAttention() {
    final journal = _transferJournal;
    if (journal == null || _activityStore == null) return;
    final needsReview = journal.entries.any(
      (entry) => const {
        TransferJournalState.interrupted,
        TransferJournalState.awaitingMetadata,
        TransferJournalState.cleanupRequired,
      }.contains(entry.state),
    );
    if (_lastTransferAttention == needsReview) return;
    _lastTransferAttention = needsReview;
    unawaited(
      _recordActivity(ActivityKind.transferInterrupted, resolved: !needsReview),
    );
  }

  Future<void> _resolveBackupAttention() async {
    final recorded = _activityStore?.entry(ActivityKind.backupProblem);
    if (recorded == null || recorded.resolved || _backupIssues.isNotEmpty) {
      return;
    }
    final enabled = _backupFolders.values.where((folder) => folder.enabled);
    if (enabled.isNotEmpty &&
        enabled.every(
          (folder) => folder.lastSynced?.isAfter(recorded.changedAt) == true,
        )) {
      await _recordActivity(ActivityKind.backupProblem, resolved: true);
    }
  }

  SecuritySettingsPage _activitySecurityPage() {
    final ownerUid = widget.user.uid;
    return SecuritySettingsPage(
      user: widget.user,
      firestore: widget.firestore,
      validateRecoveryMaterial: _validateRecoveryMaterial,
      onRecoveryMaterialImported: _applyRecoveryMaterial,
      onSecurityChanged: () {
        if (widget.user.uid == ownerUid) {
          unawaited(_recordActivity(ActivityKind.securityChanged));
        }
      },
    );
  }

  Future<void> _openActivitySecurity() async {
    if (!_activityAccountCurrent) return;
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => _activitySecurityPage()));
  }

  Future<void> _openActivityCenter() async {
    if (!_activityAccountCurrent || _activityCenterOpen) return;
    final store = _activityStore;
    if (store == null) {
      _showMessage('Activity is not available yet. Please try again.');
      return;
    }
    final ownerUid = widget.user.uid;
    bool sameAccount() =>
        _activityAccountCurrent &&
        widget.user.uid == ownerUid &&
        identical(_activityStore, store);
    _activityCenterOpen = true;
    try {
      final action = await Navigator.of(context).push<ActivityKind>(
        MaterialPageRoute(
          builder: (_) =>
              ActivityCenterPage(store: store, isCurrentAccount: sameAccount),
        ),
      );
      if (!sameAccount() || action == null) return;
      _ensureSessionActive();
      switch (action) {
        case ActivityKind.backupProblem:
        case ActivityKind.backgroundProblem:
          setState(() => _workspaceDestination = 1);
        case ActivityKind.backgroundLocked:
          await _showSettingsSheet();
        case ActivityKind.storageFull:
          await _manageSubscription();
        case ActivityKind.securityChanged:
          await _openActivitySecurity();
        default:
          await _openDataSafetyCenter();
      }
    } finally {
      _activityCenterOpen = false;
    }
  }

  Widget _buildActivityStatus() {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _consumeActivityNotification(),
    );
    final attention =
        _activityStore?.entries
            .where((entry) => !entry.resolved && !entry.kind.informational)
            .length ??
        0;
    final configured = _backupFolders.values;
    final enabled = configured.where((folder) => folder.enabled).toList();
    final dates =
        configured
            .map((folder) => folder.lastSynced)
            .whereType<DateTime>()
            .toList()
          ..sort();
    final pending = _transferJournal?.pendingEntries.length ?? 0;
    final status = _initializing || _loadingFiles || _loadingFolders
        ? 'Checking backup status'
        : _backupIssues.isNotEmpty || attention > 0
        ? 'Needs attention'
        : _backupProgress.isNotEmpty
        ? 'Backing up'
        : configured.isEmpty
        ? (kIsWeb
              ? 'Folder backup requires the desktop or mobile app'
              : 'Backup not configured')
        : enabled.isEmpty
        ? 'Backups paused'
        : enabled.any((folder) => folder.lastSynced == null)
        ? 'First backup not completed'
        : 'Last backup completed';
    final last = dates.isEmpty
        ? 'No successful folder sync recorded on this device.'
        : 'Latest successful folder sync: ${MaterialLocalizations.of(context).formatMediumDate(dates.last.toLocal())}, ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(dates.last.toLocal()))}.';
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: Icon(
              attention > 0 ? Icons.error_outline : Icons.cloud_outlined,
            ),
            title: Text(status),
            subtitle: Text(
              _activityUnavailable
                  ? 'Activity history is unavailable. Open Backups to check status.'
                  : '$last $pending transfers pending. This does not verify a complete restore.',
            ),
            onTap: () {
              if (_activityAccountCurrent) {
                setState(() => _workspaceDestination = 1);
              }
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: _openActivityCenter,
                  icon: const Icon(Icons.notifications_outlined),
                  label: Text(
                    attention > 0
                        ? 'Activity ($attention)'
                        : 'Activity and notifications',
                  ),
                ),
                TextButton(
                  onPressed: () => setState(
                    () => _showSetupChecklist = !_showSetupChecklist,
                  ),
                  child: Text(
                    _showSetupChecklist ? 'Hide setup guide' : 'Setup guide',
                  ),
                ),
                TextButton(
                  onPressed: _openDataSafetyCenter,
                  child: const Text('Check recovery'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
