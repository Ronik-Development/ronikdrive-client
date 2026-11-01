import '../shared/transfer_verification_pause.dart';
import '../privacy/restore_sample_verifier.dart';
import '../privacy/native_download_pipeline.dart';
import '../privacy/encrypted_metadata_shards.dart';
import '../authentication/account_identity.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'workspace_navigation_frame.dart';
import 'workspace_storage_footer.dart';
import 'backup_startup_tile.dart';
import '../agent_access/local_access_panel.dart';
import '../desktop_drive/desktop_drive_setup_tile.dart';

import 'package:archive/archive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' hide Hmac;
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../authentication/account_closure_dialog.dart';
import '../shared/persistent_folder_access.dart';
import '../authentication/account_closure_request_service.dart';
import '../authentication/account_deletion_service.dart';
import '../authentication/login_password_vault.dart';
import '../authentication/two_factor_service.dart';
import '../billing/billing_channel.dart';
import '../billing/subscription_coordinator.dart';
import '../billing/storage_upgrade_page.dart';
import '../billing/google_play_subscription_page.dart';
import '../business/company_admin_service.dart';
import '../business/business_operations_page.dart';
import '../business/business_operations_service.dart';
import '../business/business_storage_labels.dart';
import '../business/business_reconciliation_queue.dart';
import '../business/business_storage_permissions.dart';
import '../documentation/user_documentation_page.dart';
import '../legal/legal_documents_page.dart';
import '../privacy/account_profile_privacy.dart';
import '../privacy/local_offline_vault.dart';
import '../privacy/local_private_cache.dart';
import '../privacy/memory_preview.dart';
import 'memory_file_preview_page.dart';
import '../privacy/temporary_plaintext_lease.dart';
import '../security/business_encryption_registry.dart';
import '../security/business_encryption_service.dart';
import '../security/business_reconciliation_checkpoint.dart';
import '../security/encryption_recovery_kit.dart';
import '../security/encryption_setup_service.dart';
import '../security/encryption_service.dart';
import '../security/encrypted_workspace_visibility.dart';
import '../security/standard_encryption_unlock_dialog.dart';
import '../security/workspace_metadata_encryption_service.dart';
import '../settings/security_settings_page.dart';
import '../share/share_link_security.dart';
import '../share/share_link_owner_service.dart';
import '../share/share_link_crypto.dart';
import '../share/share_link_dialogs.dart';
import '../share/share_email_service.dart';
import '../share/share_metadata_envelope.dart';
import '../share/share_preparation.dart';
import '../share/file_request_metadata_envelope.dart';
import '../shared/app_error_reporter.dart';
import '../shared/app_page_title.dart';
import '../shared/background_backup_runner.dart';
import '../shared/background_service.dart';
import '../shared/folder_backup_platform_policy.dart';
import '../shared/file_downloader.dart';
import '../shared/platform_io.dart';
import '../shared/privacy_preferences.dart';
import '../shared/release_runtime_config.dart';
import '../shared/subscription_service.dart';
import '../shared/user_facing_client_failure.dart';
import '../authentication/account_bound_token.dart';
import '../shared/user_facing_cloud_error.dart';
import '../shared/web_folder_upload_picker_stub.dart'
    if (dart.library.html) '../shared/web_folder_upload_picker_html.dart'
    as web_folder_picker;
import '../storage/drive_repository.dart';
import '../storage/folder_document_writer.dart';
import '../storage/file_identity.dart';
import '../storage/image_thumbnail_service.dart';
import '../shared/ios_photo_library.dart';
import '../storage/interrupted_multipart_cleanup.dart';
import '../storage/upload_coordinator.dart';
import '../storage/upload_source_snapshot.dart';
import '../storage/upload_cipher.dart';
import '../storage/upload_capacity_dialog.dart';
import '../storage/upload_transfer_tray.dart';
import '../storage/secure_drive_service.dart';
import '../storage/secure_shard_assembler.dart';
import '../storage/storage_inventory_status.dart';
import '../storage/storage_home_prefix.dart';
import '../storage/transfer_journal.dart';
import '../storage/upload_metadata_recovery.dart';
import '../security/pending_business_envelopes.dart';
import '../security/business_recipient_trust.dart';
import '../storage/upload_resume_context.dart';
import '../storage/upload_recovery_selection.dart';
import '../storage/backup_upload_checkpoint.dart';
import '../storage/cancel_interrupted_upload.dart' as saved_upload;
import '../storage/secure_upload_checkpoint.dart';
import '../storage/upload_metadata_service.dart';
import '../storage/wasabi_provisioning_service.dart';
import '../storage/wasabi_storage_service.dart';
import '../support/support_report_privacy.dart';
import '../support/support_report_preview.dart';
import '../support/support_access.dart';
import '../support/product_feedback.dart';
import 'data_safety_center_page.dart';
import 'activity_center.dart';
import '../shared/user_activity.dart';
import '../shared/notification_service.dart';
import 'download_page.dart';
import 'file_collaboration_page.dart';
import 'folder_picker.dart';
import 'migration/cloud_drive_provider.dart';
import 'migration/drive_migration_overlay.dart';
import 'migration/dropbox_provider.dart';
import 'migration/google_drive_provider.dart';
import 'migration/icloud_drive_provider.dart';
import 'migration/onedrive_provider.dart';
import 'selection_action_bar.dart';
import 'workspace_move_plan.dart';
import 'workspace_mutation_status.dart';
import 'workspace_source_snapshot.dart';
import 'workspace_transfer_controller.dart';
import 'workspace_transfer_status.dart';
import 'workspace_record_index.dart';
import 'workspace_view_cache.dart';

part 'workspace_activity.dart';
part 'workspace_home_page_supporting_types.dart';
part 'workspace_home_projection.dart';

class _PreparedUploadFile {
  const _PreparedUploadFile({
    required this.file,
    this.relativeFolderSegments = const <String>[],
    this.sizeBytes,
    this.readStreamFactory,
    this.boundedReadStreamFactory,
    this.displayName,
    this.mimeType,
    this.bytes,
  });

  final XFile file;
  final List<String> relativeFolderSegments;
  final int? sizeBytes;
  final Stream<List<int>> Function()? readStreamFactory;
  final Stream<List<int>> Function(int endExclusive)? boundedReadStreamFactory;
  final String? displayName;
  final String? mimeType;
  final Uint8List? bytes;

  String get resolvedName {
    final explicit = displayName?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return explicit;
    }
    return file.name;
  }

  String? get resolvedMimeType {
    final explicit = mimeType?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return explicit;
    }
    return file.mimeType;
  }
}

class _PreparedFolderEncryption {
  const _PreparedFolderEncryption({
    required this.encryptedName,
    required this.metadataEncryption,
    this.businessEnvelopes = const <String, BusinessFileKeyEnvelope>{},
  });

  final String encryptedName;
  final String metadataEncryption;
  final Map<String, BusinessFileKeyEnvelope> businessEnvelopes;
}

class _UploadCanceledException implements Exception {
  const _UploadCanceledException();
}

class _BusinessReconciliationPaused implements Exception {
  const _BusinessReconciliationPaused();
}

enum _HotStorageChoice { automatic, alwaysFast, keepFastUntil, archiveNow }

class WorkspaceHomePage extends StatefulWidget {
  const WorkspaceHomePage({
    super.key,
    required this.auth,
    required this.user,
    required this.firestore,
    this.storageService,
    this.driveRepository,
    this.uploadMetadataService,
    this.encryptionSetupService,
    this.shareLinkOwnerService,
    this.businessMode = false,
    this.billingChannel = BillingChannel.stripe,
    this.requestedBusinessReconciliationLocation,
    this.businessReconciliationRequestRevision = 0,
    this.onBusinessReconciliationCompleted,
    this.businessGroupLabels = const <String, String>{},
    this.businessCompanyLabel,
  });

  final FirebaseAuth auth;
  final User user;
  final FirebaseFirestore firestore;
  final WasabiStorageService? storageService;
  final DriveRepository? driveRepository;
  final UploadMetadataService? uploadMetadataService;
  final EncryptionSetupService? encryptionSetupService;
  final ShareLinkOwnerService? shareLinkOwnerService;
  final bool businessMode;
  final BillingChannel billingChannel;
  final BusinessReconciliationLocation? requestedBusinessReconciliationLocation;
  final int businessReconciliationRequestRevision;
  final Future<void> Function(BusinessReconciliationLocation location)?
  onBusinessReconciliationCompleted;
  final Map<String, String> businessGroupLabels;
  final String? businessCompanyLabel;

  @override
  State<WorkspaceHomePage> createState() => _WorkspaceHomePageState();
}

class _WorkspaceHomePageState extends State<WorkspaceHomePage>
    with WidgetsBindingObserver {
  late WasabiStorageService _storageService;
  late final DriveRepository _driveRepository;
  late final UploadMetadataService _uploadMetadataService;
  late final SecureDriveService _secureDriveService;
  late final EncryptionSetupService _encryptionSetupService;
  late final ShareLinkOwnerService _shareLinkOwnerService;
  late final BusinessEncryptionRegistry _businessEncryptionRegistry;
  late final BusinessEncryptionService _businessEncryptionService;
  late final WorkspaceMetadataEncryptionService _metadataEncryptionService;
  late final LocalPrivateCacheCodec _localPrivateCacheCodec;
  final Map<String,EncryptedMetadataShards> _metadataShardCaches={};
  final Map<String,({Object source,int membership,Map<String,dynamic> row})> _fileCacheRows={};
  final Map<String,({Object source,int membership,Map<String,dynamic> row})> _folderCacheRows={};
  late final LocalOfflineVault _offlineVault;
  late final TemporaryPlaintextLeaseManager _temporaryPlaintextLeases;
  late final TwoFactorApi _twoFactorApi;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _filesSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _companyFilesSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _foldersSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _companyFoldersSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _shareLinksSubscription;
  Timer? _shareLinkExpiryTimer;
  ShareLinkOwnerIndex _shareLinkOwnerIndex = const ShareLinkOwnerIndex.empty();
  bool _shareLinkIndexAvailable = false;
  final _files = RevisionList<_DriveFile>();
  final _folders = RevisionList<_DriveFolder>();
  final _viewCache = WorkspaceViewCache<_WorkspaceProjection>();
  final _offlineFiles = RevisionMap<String, _OfflineFileInfo>();
  final Map<String, _OfflineFolderConfig> _offlineFolders =
      <String, _OfflineFolderConfig>{};
  final Map<String, String> _businessFileKeyCache = <String, String>{};
  BusinessReconciliationCheckpointStore? _businessReconciliationStore;
  final Set<String> _businessReconciliationCheckpointKeys = <String>{};
  bool _businessReconciliationCacheLocked = false;
  BusinessEncryptionIdentity? _businessEncryptionIdentity;
  Future<BusinessEncryptionIdentity>? _businessEncryptionIdentityRequest;
  bool _refreshingBusinessFileAccess = false;
  bool _pauseBusinessReconciliationRequested = false;
  String? _businessFileAccessStatus;
  int _appliedBusinessReconciliationRequestRevision = -1;
  bool _protectingLegacyMetadata = false;
  String? _metadataPrivacyStatus;
  String? _offlineDirectoryPath;
  bool _offlineDirectoryWarningShown = false;
  final _backupFolders = RevisionMap<String, _BackupFolderConfig>();
  static const String _backupFingerprintOrphanBucket = '__orphan__';
  final Map<String, Map<String, _BackupFileFingerprint>> _backupFingerprints =
      <String, Map<String, _BackupFileFingerprint>>{};
  final Map<String, StreamSubscription<FileSystemEvent>> _backupListeners =
      <String, StreamSubscription<FileSystemEvent>>{};
  final Map<String, FolderAccessLease> _backupFolderLeases = {};
  final Map<String, Timer> _backupWatchDebouncers = <String, Timer>{};
  final Map<String, Set<String>> _pendingBackupWatchPaths =
      <String, Set<String>>{};
  final Set<String> _activeBackupWatchConfigs = <String>{};
  final Set<String> _fullBackupInFlightConfigs = <String>{};
  final Set<String> _cancelledBackupConfigs = <String>{};
  final Map<String, _BackupProgressStatus> _backupProgress =
      <String, _BackupProgressStatus>{};
  late final WorkspaceTransferController _transferController;
  TransferJournal? _transferJournal;
  Future<void>? _interruptedTransferCleanup;
  Future<UploadMetadataRecoveryResult>? _pendingMetadataRecovery;
  final Map<String, Uint8List?> _thumbnailCache = <String, Uint8List?>{};
  final Map<String, Future<Uint8List?>> _thumbnailRequests =
      <String, Future<Uint8List?>>{};
  final Map<String, DateTime> _thumbnailRetryAfter = <String, DateTime>{};
  final Map<String, _DriveFile> _filesById = <String, _DriveFile>{};
  final Map<String, _ResolvedFileNameCacheEntry> _resolvedFileNameCache =
      <String, _ResolvedFileNameCacheEntry>{};
  final Map<String, _ResolvedFileNameCacheEntry> _resolvedFolderNameCache =
      <String, _ResolvedFileNameCacheEntry>{};
  final Set<String> _knownBackupFolderIds = <String>{};
  final _backupFolderIdsByLocalPath = RevisionMap<String, String>();
  final Set<String> _selectedFileIds = <String>{};
  final Set<String> _selectedFolderIds = <String>{};
  bool _isSelectionMode = false;
  Future<void> _pendingFileSnapshotProcessing = Future<void>.value();
  Future<void> _pendingFolderSnapshotProcessing = Future<void>.value();
  late final WorkspaceSourceSnapshot<_DriveFile> _fileSnapshotSources =
      WorkspaceSourceSnapshot<_DriveFile>(
        equivalent: workspaceIncrementalIndexEnabled ? _driveFilesEqual : null,
        index: workspaceIncrementalIndexEnabled
            ? WorkspaceRecordIndex<_DriveFile>(
                compare: _compareDriveFiles,
                include: (file) => file.isActive,
                weight: (file) => file.size,
                bucketOf: (file) =>
                    file.folderId ?? file.derivedFolderId ?? file.folderName ?? '',
              )
            : null,
      );
  final Set<WorkspaceSnapshotSource> _initializedFileSnapshotSources =
      <WorkspaceSnapshotSource>{};
  int _companyStorageStreamGeneration = 0;
  late final WorkspaceSourceSnapshot<_DriveFolder> _folderSnapshotSources =
      WorkspaceSourceSnapshot<_DriveFolder>(
        equivalent: workspaceIncrementalIndexEnabled ? _driveFoldersEqual : null,
        index: workspaceIncrementalIndexEnabled
            ? WorkspaceRecordIndex<_DriveFolder>(
                compare: _compareDriveFolders,
                include: (_) => true,
                weight: (_) => 0,
                bucketOf: (_) => '',
              )
            : null,
      );
  Future<void>? _initialFileSnapshotLoad;
  bool _hasLoadedFileSnapshot = false;
  bool _hasAppliedUserProfileState = false;
  Future<void>? _initialFolderSnapshotLoad;
  bool _hasLoadedFolderSnapshot = false;
  Timer? _userStreamReconnectTimer;
  Timer? _filesStreamReconnectTimer;
  Timer? _foldersStreamReconnectTimer;
  int _userStreamReconnectAttempts = 0;
  int _filesStreamReconnectAttempts = 0;
  int _foldersStreamReconnectAttempts = 0;
  DateTime? _lastFilesStreamErrorNoticeAt;
  DateTime? _lastFoldersStreamErrorNoticeAt;
  WorkspaceMutationFailure? _workspaceMutationFailure;
  bool _refreshingWorkspaceMutationState = false;

  Timer? _backupScanTimer;
  Timer? _startupBackupActivationTimer;
  Timer? _startupPhotosProvisionTimer;
  Timer? _folderCachePersistTimer;
  Duration? _activeBackupScanInterval;
  _BackupScanFrequency _backupScanFrequency = _BackupScanFrequency.standard;
  static const Duration _backupWatchDebounceDuration = Duration(seconds: 2);
  static const int _backupFingerprintCheckpointUploadCount = 25;
  static const int _backupUploadBatchSize = 3;
  Timer? _fileCachePersistTimer;

  SharedPreferences? _prefs;
  String? _activeFolderId;
  String? _activeFolderLabel;
  bool _isDragging = false;

  bool _loadingFiles = true;
  bool _loadingFolders = true;
  bool _initializing = true;
  bool _isUploading = false;
  bool _revokingAllShareLinks = false;
  bool _preparingShare = false;
  bool _openingUploadSheet = false;
  bool _offlineSyncScheduled = false;
  bool _isSyncingOffline = false;
  bool _offlineStorageWarningShown = false;
  bool _offlineUnlockWarningShown = false;
  bool _backupAuthErrorShown = false;
  bool _backgroundBackupEnabled = false;
  bool _backgroundBackupPreferenceSet = false;
  bool _sessionInvalidated = false;
  UserActivityStore? _activityStore;
  StreamSubscription<String>? _activitySubscription;
  StreamSubscription<String>? _notificationOpenSubscription;
  bool _activityCenterOpen = false;
  bool _activityUnavailable = false;
  bool? _lastTransferAttention;
  bool _walkthroughCheckScheduled = false;
  bool _walkthroughVisible = false;
  int _workspaceDestination = 0;
  bool _showSetupChecklist = false;
  bool _setupSettingsReviewed = false;
  bool _legalAcceptancePromptScheduled = false;
  bool _legalAcceptancePromptVisible = false;
  bool _legalAcceptanceCurrent = true;
  bool _productUpdatesOptIn = false;
  Future<void>? _activePassphraseRestore;
  Future<bool>? _activeStandardUnlockPrompt;

  Future<void> _manageSubscription() async {
    if (!await _ensureAuthenticated(interactive: true)) {
      return;
    }

    try {
      final snapshot = await widget.firestore
          .collection('users')
          .doc(widget.user.uid)
          .get();
      if (!mounted) {
        return;
      }
      final subscription = SubscriptionState.fromSnapshot(snapshot);
      if (subscription.isFree) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => StorageUpgradePage(
              auth: widget.auth,
              user: widget.user,
              initialSubscription: subscription,
              coordinator: SubscriptionCoordinator(
                firestore: widget.firestore,
                checkoutApi: HttpStripeCheckoutApi(
                  apiBaseUrl: ReleaseRuntimeConfig.resolveCheckoutApiBaseUri(),
                  projectId: widget.auth.app.options.projectId,
                ),
              ),
              billingChannel: widget.billingChannel,
            ),
          ),
        );
      } else {
        await _showSubscriptionManagementSheet(snapshot.data() ?? {});
      }
    } catch (_) {
      if (mounted) {
        _showMessage(
          userFacingClientFailureMessage(
            UserFacingClientFailure.subscriptionManagement,
          ),
        );
      }
    }
  }

  Future<void> _showSubscriptionManagementSheet(
    Map<String, dynamic> profileData,
  ) async {
    final primaryProvider =
        _trimmedOrNull(profileData['billingPrimaryProvider']) ?? 'stripe';
    final activeProviders = (profileData['billingProvidersActive'] is Iterable)
        ? (profileData['billingProvidersActive'] as Iterable)
              .map((value) => value.toString().trim())
              .where((value) => value.isNotEmpty)
              .toSet()
        : <String>{primaryProvider};
    final hasStripeProvider =
        primaryProvider.toLowerCase() == 'stripe' ||
        activeProviders.any((provider) => provider.toLowerCase() == 'stripe');
    final hasAppleProvider =
        {
          'appstore',
          'app_store',
          'apple',
        }.contains(primaryProvider.toLowerCase()) ||
        activeProviders.any(
          (provider) => {
            'appstore',
            'app_store',
            'apple',
          }.contains(provider.toLowerCase()),
        );
    if (!widget.billingChannel.usesStripe || !hasStripeProvider) {
      await _showProviderSubscriptionSheet(
        profileData: profileData,
        primaryProvider: primaryProvider,
        activeProviders: activeProviders,
      );
      return;
    }

    final service = SubscriptionService();
    final currentTier =
        _normalizeSubscriptionTier(
          _trimmedOrNull(profileData['subscriptionTier']) ??
              _trimmedOrNull(profileData['planTier']),
        ) ??
        'pro';
    final currentInterval =
        _normalizeSubscriptionInterval(
          _trimmedOrNull(profileData['subscriptionInterval']) ??
              _trimmedOrNull(profileData['interval']),
        ) ??
        'monthly';
    final status =
        _trimmedOrNull(profileData['subscriptionStatus']) ?? 'unknown';
    final cancelAtPeriodEnd = profileData['cancelAtPeriodEnd'] == true;
    final periodEnd = _coerceSubscriptionDate(
      profileData['currentPeriodEnd'] ?? profileData['subscriptionEndDate'],
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        var selectedTier = currentTier;
        var selectedInterval = currentInterval;
        var busy = false;

        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> runAction(Future<void> Function() action) async {
              if (busy) {
                return;
              }
              setSheetState(() => busy = true);
              try {
                await action();
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        userFacingClientFailureMessage(
                          UserFacingClientFailure.subscriptionManagement,
                        ),
                      ),
                    ),
                  );
                }
              } finally {
                if (context.mounted) {
                  setSheetState(() => busy = false);
                }
              }
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Subscription',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _subscriptionStatusSummary(
                          tier: currentTier,
                          interval: currentInterval,
                          status: status,
                          cancelAtPeriodEnd: cancelAtPeriodEnd,
                          periodEnd: periodEnd,
                        ),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 20),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'basic', label: Text('Basic')),
                          ButtonSegment(value: 'pro', label: Text('Pro')),
                          ButtonSegment(value: 'ultra', label: Text('Ultra')),
                        ],
                        selected: {selectedTier},
                        onSelectionChanged: busy
                            ? null
                            : (values) {
                                setSheetState(() {
                                  selectedTier = values.single;
                                });
                              },
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: 'monthly',
                            label: Text('Monthly'),
                          ),
                          ButtonSegment(value: 'yearly', label: Text('Yearly')),
                        ],
                        selected: {selectedInterval},
                        onSelectionChanged: busy
                            ? null
                            : (values) {
                                setSheetState(() {
                                  selectedInterval = values.single;
                                });
                              },
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: busy
                            ? null
                            : () => unawaited(
                                runAction(() async {
                                  final result = await service
                                      .changeSubscriptionTier(
                                        tier: selectedTier,
                                        interval: selectedInterval,
                                      );
                                  if (!context.mounted) {
                                    return;
                                  }
                                  Navigator.of(context).pop();
                                  if (!result.unchanged) {
                                    paymentProcessingNotifier.value = true;
                                  }
                                  _showMessage(
                                    result.unchanged
                                        ? 'You are already on that subscription tier.'
                                        : 'Subscription update requested. Stripe will confirm the change shortly.',
                                  );
                                }),
                              ),
                        icon: busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.swap_horiz),
                        label: const Text('Change plan'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: busy
                            ? null
                            : () => unawaited(
                                runAction(() async {
                                  await service.manageSubscription();
                                }),
                              ),
                        icon: const Icon(Icons.credit_card),
                        label: const Text('Manage billing'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: busy
                            ? null
                            : () => unawaited(
                                runAction(_openStripeRefundRequest),
                              ),
                        icon: const Icon(Icons.receipt_long_outlined),
                        label: const Text('Stripe refund or billing help'),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: busy || cancelAtPeriodEnd
                            ? null
                            : () => unawaited(
                                runAction(() async {
                                  final confirmed =
                                      await _confirmSubscriptionCancel();
                                  if (confirmed != true) {
                                    return;
                                  }
                                  final result = await service
                                      .cancelSubscription();
                                  if (!context.mounted) {
                                    return;
                                  }
                                  Navigator.of(context).pop();
                                  final end = _formatSubscriptionDate(
                                    result.cancelAt ??
                                        result.currentPeriodEnd ??
                                        periodEnd,
                                  );
                                  _showMessage(
                                    end == null
                                        ? 'Subscription cancellation scheduled. Account and data deletion will be scheduled after paid access ends.'
                                        : 'Subscription will end on $end. Account and data deletion is scheduled 3 months later unless renewed.',
                                  );
                                }),
                              ),
                        icon: const Icon(Icons.cancel_outlined),
                        label: Text(
                          cancelAtPeriodEnd
                              ? 'Cancellation scheduled'
                              : 'Unsubscribe',
                        ),
                      ),
                      if (hasAppleProvider) ...[
                        const Divider(height: 32),
                        Text(
                          'Apple subscription',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Apple billing is also linked to this account. Manage its renewal and any refund through Apple separately.',
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: busy
                              ? null
                              : () => unawaited(
                                  runAction(_openAppleSubscriptions),
                                ),
                          icon: const Icon(Icons.apple),
                          label: const Text('Manage with Apple'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: busy
                              ? null
                              : () => unawaited(
                                  runAction(_openAppleRefundRequest),
                                ),
                          icon: const Icon(Icons.receipt_long_outlined),
                          label: const Text('Request Apple refund'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showProviderSubscriptionSheet({
    required Map<String, dynamic> profileData,
    required String primaryProvider,
    required Set<String> activeProviders,
  }) async {
    final currentTier =
        _normalizeSubscriptionTier(
          _trimmedOrNull(profileData['subscriptionTier']) ??
              _trimmedOrNull(profileData['planTier']),
        ) ??
        'unknown';
    final providerLabels = activeProviders
        .map((provider) {
          return switch (provider) {
            'appStore' || 'app_store' => 'Apple App Store',
            'googlePlay' || 'google_play' || 'googleplay' || 'play' => 'Google Play',
            'stripe' => 'RonikCloud web billing',
            'reviewGrant' || 'review_grant' => 'App Review access grant',
            _ => provider,
          };
        })
        .toList(growable: false);
    final managedByApple =
        primaryProvider == 'appStore' ||
        primaryProvider == 'app_store' ||
        activeProviders.contains('appStore') ||
        activeProviders.contains('app_store');
    final managedByStripe =
        primaryProvider.toLowerCase() == 'stripe' ||
        activeProviders.any((provider) => provider.toLowerCase() == 'stripe');
    final managedByGooglePlay = <String>{primaryProvider, ...activeProviders}
        .any((provider) => {
          'googleplay', 'google_play', 'play',
        }.contains(provider.toLowerCase()));

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Subscription',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(
                '${currentTier[0].toUpperCase()}${currentTier.substring(1)} plan',
              ),
              const SizedBox(height: 8),
              Text(
                providerLabels.length > 1
                    ? 'Active billing sources: ${providerLabels.join(' and ')}. '
                          'Your highest active tier is applied; storage is not added together.'
                    : 'This subscription is managed through '
                          '${providerLabels.isEmpty ? 'its original purchase channel' : providerLabels.single}.',
              ),
              const SizedBox(height: 16),
              if (managedByGooglePlay)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.billingChannel.usesGooglePlay) ...[
                      FilledButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          Navigator.of(this.context).push<void>(
                            MaterialPageRoute(
                              builder: (_) => GooglePlaySubscriptionPage(
                                auth: widget.auth,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.swap_horiz),
                        label: const Text('Change storage plan'),
                      ),
                      const SizedBox(height: 8),
                    ],
                    OutlinedButton.icon(
                      onPressed: () async {
                        var opened = false;
                        try {
                          opened = await launchUrl(
                            Uri.parse(
                              'https://play.google.com/store/account/subscriptions',
                            ),
                            mode: LaunchMode.externalApplication,
                          ).timeout(const Duration(seconds: 20));
                        } catch (_) {}
                        if (!opened && mounted) {
                          _showMessage(
                            'Google Play subscription management could not be opened. Try again.',
                          );
                        }
                      },
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Manage with Google Play'),
                    ),
                  ],
                )
              else if (managedByApple &&
                  widget.billingChannel != BillingChannel.disabled)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.icon(
                      onPressed: _openAppleSubscriptions,
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Manage with Apple'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _openAppleRefundRequest,
                      icon: const Icon(Icons.receipt_long_outlined),
                      label: const Text('Request Apple refund'),
                    ),
                  ],
                )
              else
                const Text(
                  'To change or cancel this subscription, use the original '
                  'purchase channel. Checkout and billing links are not '
                  'available in this app.',
                ),
              if (managedByStripe) ...[
                const SizedBox(height: 16),
                const Text(
                  'A Stripe subscription is also linked. RonikCloud support can help with its cancellation or refund without routing an Apple purchase away from Apple.',
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _openStripeRefundRequest,
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('Stripe refund or billing help'),
                ),
              ],
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool?> _confirmSubscriptionCancel() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsubscribe?'),
        content: const Text(
          'Your subscription will be cancelled at the end of the current billing period. You can keep using your paid storage until then. If the subscription is not renewed, your account and stored data are scheduled for permanent deletion 3 months after paid access ends.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep subscription'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Unsubscribe'),
          ),
        ],
      ),
    );
  }

  Future<void> _openStripeRefundRequest() async {
    final opened = await launchUrl(
      Uri(
        scheme: 'mailto',
        path: LegalDocuments.supportEmail,
        queryParameters: const {'subject': 'RonikCloud refund request'},
      ),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      _showMessage(
        'Email support@ronikcloud.com with the subject "RonikCloud refund request".',
      );
    }
  }

  Future<void> _openAppleSubscriptions() async {
    final opened = await launchUrl(
      Uri.parse('https://apps.apple.com/account/subscriptions'),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      _showMessage('Open Apple Account > Subscriptions to manage renewal.');
    }
  }

  Future<void> _openAppleRefundRequest() async {
    final opened = await launchUrl(
      Uri.parse('https://reportaproblem.apple.com/'),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      _showMessage('Open reportaproblem.apple.com to request an Apple refund.');
    }
  }

  String? _normalizeSubscriptionTier(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return ['basic', 'pro', 'ultra'].contains(normalized) ? normalized : null;
  }

  String? _normalizeSubscriptionInterval(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    if (normalized == 'month') {
      return 'monthly';
    }
    if (normalized == 'year') {
      return 'yearly';
    }
    return ['monthly', 'yearly'].contains(normalized) ? normalized : null;
  }

  DateTime? _coerceSubscriptionDate(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    if (value is num) {
      final milliseconds = value > 100000000000
          ? value.toInt()
          : (value * 1000).round();
      return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
    }
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : DateTime.tryParse(trimmed);
    }
    return null;
  }

  String? _formatSubscriptionDate(DateTime? value) {
    if (value == null) {
      return null;
    }
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}';
  }

  String _subscriptionStatusSummary({
    required String tier,
    required String interval,
    required String status,
    required bool cancelAtPeriodEnd,
    required DateTime? periodEnd,
  }) {
    final tierLabel = tier[0].toUpperCase() + tier.substring(1);
    final intervalLabel = interval == 'yearly' ? 'yearly' : 'monthly';
    final statusLabel = status.replaceAll('_', ' ');
    final end = _formatSubscriptionDate(periodEnd);
    if (cancelAtPeriodEnd) {
      return end == null
          ? '$tierLabel $intervalLabel plan. Cancellation is scheduled.'
          : '$tierLabel $intervalLabel plan. Access ends on $end.';
    }
    if (end == null) {
      return '$tierLabel $intervalLabel plan. Status: $statusLabel.';
    }
    return '$tierLabel $intervalLabel plan. Status: $statusLabel. Renews on $end.';
  }

  Future<void> _confirmAccountDeletion() async {
    Map<String, dynamic>? profileData;
    try {
      final snapshot = await widget.firestore
          .collection('users')
          .doc(widget.user.uid)
          .get();
      profileData = snapshot.data();
    } catch (_) {
      // The shared confirmation still explains permanent deletion when billing
      // status cannot be refreshed. The backend remains authoritative.
    }

    if (!mounted) return;
    final action = await showAccountClosureDialog(
      context: context,
      profileData: profileData,
    );

    if (action == AccountClosureAction.cancel) return;

    if (!mounted) return;

    // Both the non-destructive queue request and staged deletion require a
    // fresh Firebase authentication time, not merely a still-valid session.
    final password = await _collectAccountClosurePassword();
    if (password == null || password.isEmpty || !mounted) return;
    try {
      await _verifyCurrentLoginPassword(password);
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        _showMessage(
          userFacingCloudErrorMessage(
            operation: UserFacingCloudOperation.accountVerification,
            code: error.code,
          ),
        );
      }
      return;
    } catch (_) {
      if (mounted) {
        _showMessage('Could not confirm your identity. Try again.');
      }
      return;
    }
    if (!await _ensureTwoFactorSession(interactive: true)) return;

    if (action == AccountClosureAction.requestClosure) {
      setState(() => _isUploading = true);
      try {
        final receipt = await AccountClosureRequestService(
          auth: widget.auth,
        ).submit();
        if (!mounted) return;
        setState(() => _isUploading = false);
        await showAccountClosureRequestRecordedDialog(
          context: context,
          alreadyRequested: receipt.alreadyRequested,
          status: receipt.status,
          receiptUrl: receipt.receiptUrl,
        );
      } on AccountClosureRequestException catch (error) {
        if (!mounted) return;
        setState(() => _isUploading = false);
        await showAccountClosureRequestFallbackDialog(
          context: context,
          message: error.message,
        );
      } catch (_) {
        if (!mounted) return;
        setState(() => _isUploading = false);
        await showAccountClosureRequestFallbackDialog(
          context: context,
          message: 'The closure request could not be recorded.',
        );
      }
      return;
    }

    setState(
      () => _isUploading = true,
    ); // Reuse loading state/overlay if available or add one

    try {
      final deletionService = AccountDeletionService(
        driveRepository: _driveRepository,
        auth: widget.auth,
        firestore: widget.firestore,
        wasabiService: _storageService,
      );
      await deletionService.deleteAccount();

      if (mounted) {
        LoginPasswordVault.instance.clear();
        await widget.auth.signOut();
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/');
        }
      }
    } on AccountDeletionException catch (error) {
      if (mounted) {
        setState(() => _isUploading = false);
        _showMessage(error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isUploading = false);
        _showMessage(
          'Account deletion did not finish. Sign-in was preserved, but some provider cleanup may already be complete. Retry, or contact support before uploading or purchasing again.',
        );
      }
    }
  }

  void _toggleFileSelection(String id) {
    setState(() {
      if (_selectedFileIds.contains(id)) {
        _selectedFileIds.remove(id);
      } else {
        _selectedFileIds.add(id);
      }
      _isSelectionMode =
          _selectedFileIds.isNotEmpty || _selectedFolderIds.isNotEmpty;
    });
  }

  void _toggleFolderSelection(String id) {
    setState(() {
      if (_selectedFolderIds.contains(id)) {
        _selectedFolderIds.remove(id);
      } else {
        _selectedFolderIds.add(id);
      }
      _isSelectionMode =
          _selectedFileIds.isNotEmpty || _selectedFolderIds.isNotEmpty;
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedFileIds.clear();
      _selectedFolderIds.clear();
      _isSelectionMode = false;
    });
  }

  List<_DriveFile> _selectedFiles() {
    if (_selectedFileIds.isEmpty) {
      return const <_DriveFile>[];
    }
    return _files
        .where((file) => _selectedFileIds.contains(file.id))
        .toList(growable: false);
  }

  List<_FolderListItem> _selectedFolderItems() {
    if (_selectedFolderIds.isEmpty) {
      return const <_FolderListItem>[];
    }
    return _buildFolderSummaries()
        .where((item) => _selectedFolderIds.contains(item.summary.id))
        .toList(growable: false);
  }

  _DriveFile? _singleSelectedFile() {
    if (_selectedFolderIds.isNotEmpty || _selectedFileIds.length != 1) {
      return null;
    }
    final selectedFiles = _selectedFiles();
    return selectedFiles.length == 1 ? selectedFiles.first : null;
  }

  _FolderListItem? _singleSelectedFolderItem() {
    if (_selectedFileIds.isNotEmpty || _selectedFolderIds.length != 1) {
      return null;
    }
    final selectedFolders = _selectedFolderItems();
    return selectedFolders.length == 1 ? selectedFolders.first : null;
  }

  Future<void> _shareSelectedItem() async {
    final file = _singleSelectedFile();
    if (file == null) {
      return;
    }
    if (!_ensureStorageReadsAvailable(storageScope: file.storageScope) ||
        !_ensureStorageSharesAvailable(storageScope: file.storageScope)) {
      return;
    }
    _clearSelection();
    await _handleShareAction(file);
  }

  Future<void> _collaborateOnSelectedFile() async {
    final file = _singleSelectedFile();
    if (file == null) return;
    if (!_ensureStorageReadsAvailable(storageScope: file.storageScope)) {
      return;
    }
    _clearSelection();
    final keyString = await _encryptionKeyStringForFile(
      file,
      interactive: true,
    );
    if (keyString == null || keyString.isEmpty) {
      _showMessage(
        'Encrypted discussion is unavailable until this file can be opened '
        'with its client-held key.',
      );
      return;
    }
    late final SecretKey collaborationKey;
    try {
      collaborationKey = SecretKey(base64Decode(keyString));
    } catch (_) {
      _showMessage(
        'The protected file key could not be opened on this device.',
      );
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => FileCollaborationPage(
          fileId: file.id,
          fileName: file.name,
          userId: widget.user.uid,
          userName: widget.user.displayName?.trim().isNotEmpty == true
              ? widget.user.displayName!.trim()
              : (widget.user.email?.trim().isNotEmpty == true
                    ? widget.user.email!.trim()
                    : 'RonikCloud user'),
          encryptionKey: collaborationKey,
          firestore: widget.firestore,
          service: _secureDriveService,
        ),
      ),
    );
  }

  Future<void> _renameSelectedItem() async {
    final file = _singleSelectedFile();
    final folderItem = _singleSelectedFolderItem();
    final folder = folderItem?.folder;
    if (file == null && folder == null) {
      return;
    }
    _clearSelection();
    if (file != null) {
      await _renameFile(file);
      return;
    }
    await _renameFolder(folder!);
  }

  Future<void> _removeSelectedFolderKeepContents() async {
    final folder = _singleSelectedFolderItem()?.folder;
    if (folder == null) {
      return;
    }
    _clearSelection();
    await _deleteFolder(folder, deleteContents: false);
  }

  Future<void> _toggleSelectedOfflineAvailability() async {
    final files = _selectedFiles();
    final folders = _selectedFolderItems();
    if (files.isEmpty && folders.isEmpty) {
      return;
    }
    if (!_ensureStorageReadsAvailable()) {
      return;
    }

    final fileTargets = List<_DriveFile>.from(files);
    final folderTargets = folders
        .map((item) => item.summary)
        .toList(growable: false);
    _clearSelection();

    for (final file in fileTargets) {
      await _toggleOffline(file);
    }
    for (final summary in folderTargets) {
      final enable = !_offlineFolders.containsKey(summary.id);
      await _toggleFolderOffline(summary, enable);
    }
  }

  Future<void> _downloadSelectedFiles() async {
    final selectedFiles = _selectedFiles();
    if (selectedFiles.isEmpty) {
      return;
    }
    for (final file in selectedFiles) {
      if (!_ensureStorageReadsAvailable(storageScope: file.storageScope)) {
        return;
      }
    }
    _clearSelection();

    if (selectedFiles.length == 1) {
      await _downloadSingleSelectedFile(selectedFiles.single);
      return;
    }

    await _downloadSelectedFilesAsZip(selectedFiles);
  }

  Future<void> _downloadSingleSelectedFile(_DriveFile file) async {
    if (!_ensureStorageReadsAvailable(storageScope: file.storageScope)) {
      return;
    }
    if (!await _confirmPlaintextLocalWrite(file, action: 'Download')) {
      return;
    }

    final storageReady = await _ensureStorageConfigured(
      forceRefresh: !_storageService.isConfigured,
    );
    if (!mounted || !storageReady) {
      return;
    }

    final transferId = 'download-selection:${file.objectKey}';
    _beginTransfer(transferId, 'Downloading ${file.name}');
    try {
      final secretKey = await _secretKeyForDownload(file);
      if (file.isEncrypted && secretKey == null) {
        _showMessage('Unlock this file to download it.');
        return;
      }

      if (kIsWeb) {
        final bytes = await _downloadFileBytes(file, secretKey: secretKey);
        try {
          await downloadFile(bytes, file.name);
        } finally {
          bytes.fillRange(0, bytes.length, 0);
        }
        return;
      }
      final lease = await _createTemporaryPlaintextLease(file.name);
      await lease.writeStream(
        _streamFilePlaintext(file, secretKey: secretKey),
        checkAccess: () => _checkFileDownloadAccess(file),
      );
      await _shareTemporaryPlaintextLease(lease, displayName: file.name);
    } on _SessionExpiredException catch (error) {
      _handleSessionExpired(error);
    } catch (error) {
      BackgroundBackupRunner.logFailure('download', 'selected_file', error);
      _showMessage('Failed to download ${file.name}.');
    } finally {
      _endTransfer(transferId);
    }
  }

  Future<void> _downloadSelectedFilesAsZip(List<_DriveFile> files) async {
    _DriveFile? securedDesktopFile;
    for (final file in files) {
      if (_blocksPlaintextLocalWrite(file)) {
        securedDesktopFile = file;
        break;
      }
    }
    if (securedDesktopFile != null &&
        !await _confirmPlaintextLocalWrite(
          securedDesktopFile,
          action: 'Download',
        )) {
      return;
    }

    final storageReady = await _ensureStorageConfigured(
      forceRefresh: !_storageService.isConfigured,
    );
    if (!mounted || !storageReady) {
      return;
    }

    final transferId =
        'download-bundle:${DateTime.now().millisecondsSinceEpoch}';
    _beginTransfer(transferId, 'Preparing ZIP download...');
    if (!kIsWeb) {
      try {
        await _downloadNativeZip(files, transferId);
      } on _SessionExpiredException catch (error) {
        _handleSessionExpired(error);
      } catch (error) {
        BackgroundBackupRunner.logFailure('download', 'zip_bundle', error);
        _showMessage('Failed to download selected files.');
      } finally {
        _endTransfer(transferId);
      }
      return;
    }

    final archive = Archive();
    final buffers = <Uint8List>[];
    final included = <_DriveFile>[];
    Uint8List? zipBuffer;
    final usedNames = <String>{};
    final failures = <String>[];

    try {
      for (var index = 0; index < files.length; index += 1) {
        final file = files[index];
        _updateTransfer(
          transferId,
          'Preparing ZIP ${index + 1}/${files.length}: ${file.name}',
        );
        try {
          _ensureSessionActive();
          _ensureOwnsObjectKey(file.objectKey);
          final secretKey = await _secretKeyForDownload(file);
          if (file.isEncrypted && secretKey == null) {
            failures.add(file.name);
            continue;
          }
          final bytes = await _downloadFileBytes(file, secretKey: secretKey);
          final entryName = _uniqueArchiveEntryName(file, usedNames);
          archive.addFile(ArchiveFile(entryName, bytes.length, bytes));
          buffers.add(bytes);
          included.add(file);
        } on _SessionExpiredException {
          rethrow;
        } catch (error) {
          BackgroundBackupRunner.logFailure('download', 'zip_entry', error);
          failures.add(file.name);
        }
      }

      if (archive.isEmpty) {
        _showMessage('No selected files could be downloaded.');
        return;
      }

      _updateTransfer(transferId, 'Creating ZIP download...');
      final encoded = ZipEncoder().encode(archive);
      if (encoded.isEmpty) {
        _showMessage('Could not create ZIP download.');
        return;
      }

      final zipBytes = encoded is Uint8List
          ? encoded
          : Uint8List.fromList(encoded);
      zipBuffer = zipBytes;
      for (final file in included) {
        _checkFileDownloadAccess(file);
      }
      final zipName = _downloadBundleFileName();
      if (kIsWeb) {
        await downloadFile(zipBytes, zipName);
      } else {
        final lease = await _createTemporaryPlaintextLease(zipName);
        await lease.writeBytes(zipBytes);
        await _shareTemporaryPlaintextLease(lease, displayName: zipName);
      }

      final downloadedCount = archive.length;
      _showMessage(
        failures.isEmpty
            ? 'Downloaded $downloadedCount files as a ZIP.'
            : 'Downloaded $downloadedCount files. ${failures.length} failed.',
      );
    } on _SessionExpiredException catch (error) {
      _handleSessionExpired(error);
    } catch (error) {
      BackgroundBackupRunner.logFailure('download', 'zip_bundle', error);
      _showMessage('Failed to download selected files.');
    } finally {
      for (final bytes in buffers) {
        bytes.fillRange(0, bytes.length, 0);
      }
      zipBuffer?.fillRange(0, zipBuffer.length, 0);
      archive.clear();
      _endTransfer(transferId);
    }
  }

  Future<SecretKey?> _secretKeyForDownload(_DriveFile file) async {
    final keyString = await _encryptionKeyStringForFile(
      file,
      interactive: true,
    );
    if (keyString == null) {
      return null;
    }
    return SecretKey(base64Decode(keyString));
  }

  Future<BusinessEncryptionIdentity> _ensureBusinessEncryptionIdentity({
    required SecretKey accountProtectionKey,
  }) async {
    final cached = _businessEncryptionIdentity;
    if (cached != null) {
      return cached;
    }
    final activeRequest = _businessEncryptionIdentityRequest;
    if (activeRequest != null) {
      return activeRequest;
    }
    final request = _businessEncryptionRegistry.ensureIdentity(
      accountProtectionKey: accountProtectionKey,
    );
    _businessEncryptionIdentityRequest = request;
    try {
      final identity = await request;
      _businessEncryptionIdentity = identity;
      return identity;
    } finally {
      if (identical(_businessEncryptionIdentityRequest, request)) {
        _businessEncryptionIdentityRequest = null;
      }
    }
  }

  Future<void> _initializeBusinessEncryptionIfReady() async {
    if (!_hasActiveCompanyMembership ||
        _businessEncryptionIdentity != null ||
        _businessEncryptionIdentityRequest != null) {
      return;
    }
    try {
      await _restoreStandardEncryptionKeyIfAvailable();
      final accountKeyString = _cachedEncryptionKey;
      if (accountKeyString == null || accountKeyString.isEmpty) {
        return;
      }
      await _ensureBusinessEncryptionIdentity(
        accountProtectionKey: SecretKey(base64Decode(accountKeyString)),
      );
    } on Exception catch (_) {
      if (kDebugMode) {
        debugPrint('Business encryption readiness could not be refreshed.');
      }
    }
  }

  Future<String?> _businessFileKeyStringForFile(
    _DriveFile file, {
    required bool interactive,
  }) async {
    if (!_canReadStorageScope(file.storageScope)) {
      return null;
    }
    return _businessEnvelopeKeyString(
      cacheId: 'file:${file.id}',
      encryptionContext: file.objectKey,
      sharedKeyEnvelopes: file.sharedKeyEnvelopes,
      interactive: interactive,
      itemLabel: 'file',
    );
  }

  Future<String?> _businessFolderKeyString(
    _DriveFolder folder, {
    required bool interactive,
  }) {
    if (!_canReadStorageScope(folder.storageScope)) {
      return Future<String?>.value();
    }
    return _businessEnvelopeKeyString(
      cacheId: 'folder:${folder.id}',
      encryptionContext: _metadataEncryptionService.folderEncryptionContext(
        folder.id,
      ),
      sharedKeyEnvelopes: folder.sharedKeyEnvelopes,
      interactive: interactive,
      itemLabel: 'folder',
    );
  }

  Future<String?> _businessEnvelopeKeyString({
    required String cacheId,
    required String encryptionContext,
    required Map<String, dynamic> sharedKeyEnvelopes,
    required bool interactive,
    required String itemLabel,
  }) async {
    final rawEnvelope = sharedKeyEnvelopes[widget.user.uid];
    if (rawEnvelope is! Map) {
      if (interactive) {
        _showMessage(
          'Your Business encryption identity does not have access to this '
          '$itemLabel yet. Ask a teammate who can open it to refresh member '
          'access.',
        );
      }
      return null;
    }
    try {
      final accountKeyString = await _ensureEncryptionKey(
        interactive: interactive,
      );
      if (accountKeyString == null) {
        return null;
      }
      final accountProtectionKey = SecretKey(base64Decode(accountKeyString));
      final identity = await _ensureBusinessEncryptionIdentity(
        accountProtectionKey: accountProtectionKey,
      );
      final envelope = BusinessFileKeyEnvelope.fromMap(<String, Object?>{
        for (final entry in rawEnvelope.entries)
          entry.key.toString(): entry.value,
      });
      final cacheKey =
          '$cacheId|${identity.keyId}|${envelope.encryptedFileKeyBase64}';
      final cachedKey = _businessFileKeyCache[cacheKey];
      if (cachedKey != null) {
        return cachedKey;
      }
      final fileKey = await _businessEncryptionService.openFileKey(
        objectKey: encryptionContext,
        currentUid: widget.user.uid,
        identity: identity,
        envelope: envelope,
        accountProtectionKey: accountProtectionKey,
      );
      final encodedKey = base64Encode(await fileKey.extractBytes());
      _businessFileKeyCache[cacheKey] = encodedKey;
      return encodedKey;
    } on BusinessEncryptionRegistryException catch (error) {
      if (interactive) {
        _showMessage(error.message);
      }
      return null;
    } on BusinessEncryptionException catch (error) {
      if (interactive) {
        _showMessage(error.message);
      }
      return null;
    } on Exception {
      if (interactive) {
        _showMessage(
          'This Business $itemLabel key could not be opened on this device.',
        );
      }
      return null;
    }
  }

  Future<BusinessFileRotationResult> _rotateBusinessFileEncryption({
    required _DriveFile file,
    required String currentFileKeyString,
    required List<BusinessEncryptionRecipient> recipients,
  }) async {
    final replacementObjectKey = _buildObjectKey(
      '',
      folderId: file.folderId,
      securedObjectKey: true,
    );
    _ensureOwnsObjectKey(replacementObjectKey);
    final currentFileKey = SecretKey(base64Decode(currentFileKeyString));
    final replacementMaterial = await _businessEncryptionService
        .createFileEncryptionMaterial(
          objectKey: replacementObjectKey,
          recipients: recipients,
        );
    var clearName = file.name.trim();
    final currentEncryptedName = file.encryptedName?.trim();
    if (currentEncryptedName != null && currentEncryptedName.isNotEmpty) {
      final decryptedName = await EncryptionService.instance.decryptFileName(
        currentEncryptedName,
        currentFileKey,
      );
      if (decryptedName != null && decryptedName.trim().isNotEmpty) {
        clearName = decryptedName.trim();
      }
    }
    if (clearName.isEmpty) {
      throw const BusinessEncryptionRegistryException(
        'A Business file name could not be opened before key rotation.',
      );
    }
    final replacementEncryptedName = await EncryptionService.instance
        .encryptFileName(clearName, replacementMaterial.fileKey);
    final plaintext = await _storageService.download(
      objectKey: file.objectKey,
      encryptionKey: currentFileKey,
    );

    await _storageService.upload(
      objectKey: replacementObjectKey,
      stream: plaintext,
      length: file.size,
      contentType: file.contentType,
      encryptionKey: replacementMaterial.fileKey,
      transferId: 'business-key-rotation:${file.id}',
    );
    // Never delete the replacement from the client after the commit request
    // starts. A lost response can be ambiguous: the backend may already have
    // made this object active. Server-side reconciliation must decide whether
    // an uploaded replacement is truly unreferenced.
    final result = await _businessEncryptionRegistry.rotateFileEncryption(
      fileId: file.id,
      expectedObjectKey: file.objectKey,
      replacementObjectKey: replacementObjectKey,
      encryptedName: replacementEncryptedName,
      envelopes: replacementMaterial.envelopes,
    );
    _businessFileKeyCache.removeWhere(
      (cacheKey, _) => cacheKey.startsWith('file:${file.id}|'),
    );
    return result;
  }

  void _pauseBusinessReconciliation() {
    if (!_refreshingBusinessFileAccess ||
        _pauseBusinessReconciliationRequested) {
      return;
    }
    setState(() {
      _pauseBusinessReconciliationRequested = true;
      _businessFileAccessStatus =
          'Pausing safely after the current encrypted item finishes…';
    });
  }

  void _checkBusinessReconciliationPause() {
    if (_pauseBusinessReconciliationRequested) {
      throw const _BusinessReconciliationPaused();
    }
  }

  Future<void> _refreshBusinessMemberAccess() async {
    if (!_activeStorageUsesMemberEnvelopes ||
        _refreshingBusinessFileAccess ||
        !mounted) {
      return;
    }
    if (!_ensureStorageReadsAvailable()) {
      return;
    }
    if (!_canWriteActiveStorage) {
      _showMessage(
        'Your current Business permissions do not allow encrypted access '
        'reconciliation from this device.',
      );
      return;
    }
    if (_isUploading) {
      _showMessage('Wait for the current upload to finish first.');
      return;
    }
    final resumeRequested = _activeBusinessReconciliationCanResume;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(
              resumeRequested
                  ? 'Resume encrypted member access?'
                  : 'Reconcile encrypted member access?',
            ),
            content: Text(
              '${resumeRequested ? 'Authenticated progress saved on this device will skip completed items. ' : ''}'
              'This device will add encrypted key envelopes for new members. '
              'When access was removed, it will stream-decrypt and '
              'stream-reencrypt affected files under fresh random keys, then '
              'replace their encrypted provider objects. Folder labels are '
              'rotated the same way. Plain file contents, names, and '
              'unencrypted keys never leave this device.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                icon: const Icon(Icons.enhanced_encryption_outlined),
                label: Text(
                  resumeRequested ? 'Resume safely' : 'Reconcile access',
                ),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) {
      return;
    }

    final targetScope = _activeStorageScope;
    final targetGroupId = _activeStorageGroupId;
    final targetCompanyId = _companyId?.trim();
    setState(() {
      _refreshingBusinessFileAccess = true;
      _pauseBusinessReconciliationRequested = false;
      _businessFileAccessStatus = 'Checking member encryption readiness…';
    });

    var refreshedFiles = 0;
    var rotatedFiles = 0;
    var cleanupPendingFiles = 0;
    var addedEnvelopes = 0;
    var alreadyCurrentFiles = 0;
    var unavailableFiles = 0;
    var protectedFileMetadata = 0;
    var refreshedFolders = 0;
    var alreadyCurrentFolders = 0;
    var unavailableFolders = 0;
    String? reconciliationWorkspaceKey;
    var reconciliationCheckpointSaved = false;
    try {
      if (targetCompanyId == null || targetCompanyId.isEmpty) {
        throw const BusinessEncryptionRegistryException(
          'The active company workspace is unavailable.',
        );
      }
      if (!await _ensureAuthenticated(interactive: true)) {
        if (mounted) {
          setState(() {
            _businessFileAccessStatus =
                'Sign in again before refreshing encrypted member access.';
          });
        }
        return;
      }
      if (!await _ensureTwoFactorSession(interactive: true)) {
        if (mounted) {
          setState(() {
            _businessFileAccessStatus =
                'Complete security verification before refreshing access.';
          });
        }
        _showMessage(
          'Security verification is required before refreshing file access.',
        );
        return;
      }
      final accountKeyString = await _ensureEncryptionKey(interactive: true);
      if (accountKeyString == null) {
        if (mounted) {
          setState(() {
            _businessFileAccessStatus =
                'Unlock standard encryption before refreshing access.';
          });
        }
        return;
      }
      final accountProtectionKey = SecretKey(base64Decode(accountKeyString));
      final identity = await _ensureBusinessEncryptionIdentity(
        accountProtectionKey: accountProtectionKey,
      );
      final recipientSet = await _businessEncryptionRegistry.listRecipients(
        storageScope: targetScope,
        groupId: targetGroupId,
      );
      final currentRecipient = recipientSet.recipients
          .cast<BusinessEncryptionRecipient?>()
          .firstWhere(
            (recipient) => recipient?.uid == widget.user.uid,
            orElse: () => null,
          );
      if (!recipientSet.isComplete ||
          currentRecipient == null ||
          currentRecipient.keyId != identity.keyId) {
        final missingCount = recipientSet.missingUids.length;
        throw BusinessEncryptionRegistryException(
          missingCount == 0
              ? 'Business encryption is still synchronizing. Try again shortly.'
              : '$missingCount current member${missingCount == 1 ? '' : 's'} '
                    'must open the Business '
                    'workspace once before encrypted access can be refreshed.',
        );
      }

      final prefs = _prefs;
      if (prefs == null) {
        throw const BusinessReconciliationCheckpointException(
          'Encrypted reconciliation progress is not ready on this device.',
        );
      }
      final recipientFingerprint = _businessRecipientFingerprint(
        recipientSet.recipients,
      );
      reconciliationWorkspaceKey =
          BusinessReconciliationCheckpoint.workspaceKeyFor(
            companyId: targetCompanyId,
            storageScope: targetScope,
            groupId: targetGroupId,
          );
      final checkpointLoad = await _businessCheckpointStore(prefs).load();
      if (checkpointLoad.temporarilyUnavailable) {
        _businessReconciliationCacheLocked = true;
        throw const BusinessReconciliationCheckpointException(
          'Encrypted reconciliation progress is waiting for the device '
          'credential store. Unlock this device and retry.',
        );
      }
      BusinessReconciliationCheckpoint? existingCheckpoint;
      for (final candidate in checkpointLoad.checkpoints) {
        if (candidate.workspaceKey == reconciliationWorkspaceKey) {
          existingCheckpoint = candidate;
          break;
        }
      }
      final canResume =
          existingCheckpoint?.matches(
            companyId: targetCompanyId,
            storageScope: targetScope,
            groupId: targetGroupId,
            recipientFingerprint: recipientFingerprint,
          ) ==
          true;
      final activeCheckpoint = canResume
          ? existingCheckpoint!
          : BusinessReconciliationCheckpoint.start(
              companyId: targetCompanyId,
              storageScope: targetScope,
              groupId: targetGroupId,
              recipientFingerprint: recipientFingerprint,
            );
      await _saveBusinessReconciliationCheckpoint(activeCheckpoint);
      reconciliationCheckpointSaved = true;
      refreshedFiles = activeCheckpoint.refreshedFiles;
      rotatedFiles = activeCheckpoint.rotatedFiles;
      cleanupPendingFiles = activeCheckpoint.cleanupPendingFiles;
      addedEnvelopes = activeCheckpoint.addedEnvelopes;
      alreadyCurrentFiles = activeCheckpoint.alreadyCurrentFiles;
      protectedFileMetadata = activeCheckpoint.protectedFileMetadata;
      refreshedFolders = activeCheckpoint.refreshedFolders;
      alreadyCurrentFolders = activeCheckpoint.alreadyCurrentFolders;
      if (canResume && mounted) {
        setState(() {
          _businessFileAccessStatus =
              'Resuming authenticated encrypted progress: '
              '${activeCheckpoint.completedFileCount} file'
              '${activeCheckpoint.completedFileCount == 1 ? '' : 's'} '
              'and ${activeCheckpoint.completedFolderCount} folder'
              '${activeCheckpoint.completedFolderCount == 1 ? '' : 's'} '
              'already checked.';
        });
      }

      bool matchesTarget(_DriveFile file) {
        if (!file.isActive ||
            file.companyId != targetCompanyId ||
            file.storageScope != targetScope) {
          return false;
        }
        return targetScope != 'group' ||
            (targetGroupId != null && file.groupIds.contains(targetGroupId));
      }

      final currentRecipientUids = recipientSet.recipients
          .map((recipient) => recipient.uid)
          .toSet();
      final candidates = _files.where(matchesTarget).toList()
        ..sort((left, right) => left.id.compareTo(right.id));
      for (var index = 0; index < candidates.length; index += 1) {
        if (!mounted) {
          return;
        }
        _checkBusinessReconciliationPause();
        final file = candidates[index];
        if (activeCheckpoint.isFileComplete(file.id)) {
          continue;
        }
        final missingRecipients = recipientSet.recipients
            .where(
              (recipient) =>
                  !file.sharedKeyEnvelopes.containsKey(recipient.uid),
            )
            .toList(growable: false);
        final historicalRecipientUids = file.sharedKeyEnvelopes.keys
            .where((uid) => !currentRecipientUids.contains(uid))
            .toSet();
        final needsContentRotation = historicalRecipientUids.isNotEmpty;
        if (missingRecipients.isEmpty && !needsContentRotation) {
          activeCheckpoint.markFileComplete(file.id, alreadyCurrent: 1);
          await _saveBusinessReconciliationCheckpoint(activeCheckpoint);
          alreadyCurrentFiles = activeCheckpoint.alreadyCurrentFiles;
          continue;
        }
        if (!file.sharedKeyEnvelopes.containsKey(widget.user.uid)) {
          unavailableFiles += 1;
          continue;
        }
        setState(() {
          _businessFileAccessStatus = needsContentRotation
              ? 'Rotating encrypted file ${index + 1}/${candidates.length}…'
              : 'Adding encrypted member access ${index + 1}/${candidates.length}…';
        });
        final fileKeyString = await _businessFileKeyStringForFile(
          file,
          interactive: false,
        );
        if (fileKeyString == null) {
          unavailableFiles += 1;
          continue;
        }
        if (needsContentRotation) {
          final result = await _rotateBusinessFileEncryption(
            file: file,
            currentFileKeyString: fileKeyString,
            recipients: recipientSet.recipients,
          );
          activeCheckpoint.markFileComplete(
            file.id,
            rotated: 1,
            cleanupPending: result.cleanupPending ? 1 : 0,
          );
          await _saveBusinessReconciliationCheckpoint(activeCheckpoint);
          rotatedFiles = activeCheckpoint.rotatedFiles;
          cleanupPendingFiles = activeCheckpoint.cleanupPendingFiles;
        } else {
          final additions = await _businessEncryptionService
              .wrapExistingFileKey(
                objectKey: file.objectKey,
                fileKey: SecretKey(base64Decode(fileKeyString)),
                recipients: missingRecipients,
              );
          final result = await _businessEncryptionRegistry.appendFileEnvelopes(
            fileId: file.id,
            additions: additions,
          );
          activeCheckpoint.markFileComplete(
            file.id,
            refreshed: 1,
            envelopesAdded: result.addedCount,
          );
          await _saveBusinessReconciliationCheckpoint(activeCheckpoint);
          refreshedFiles = activeCheckpoint.refreshedFiles;
          addedEnvelopes = activeCheckpoint.addedEnvelopes;
        }
      }

      final filesWithLegacyMetadata = candidates
          .where(
            (file) =>
                file.isEncrypted &&
                !activeCheckpoint.isMetadataFileComplete(file.id) &&
                (file.folderName != null ||
                    file.folderColor != null ||
                    file.pathSegments.isNotEmpty),
          )
          .map((file) => file.id)
          .toList(growable: false);
      const metadataBatchSize = 200;
      for (
        var offset = 0;
        offset < filesWithLegacyMetadata.length;
        offset += metadataBatchSize
      ) {
        _checkBusinessReconciliationPause();
        final end = min(
          offset + metadataBatchSize,
          filesWithLegacyMetadata.length,
        );
        final batchFileIds = filesWithLegacyMetadata.sublist(offset, end);
        final protectedCount = await _businessEncryptionRegistry
            .protectFileMetadata(
              fileIds: batchFileIds,
              storageScope: targetScope,
              groupId: targetScope == 'group' ? targetGroupId : null,
            );
        activeCheckpoint.markMetadataComplete(
          batchFileIds,
          protectedCount: protectedCount,
        );
        await _saveBusinessReconciliationCheckpoint(activeCheckpoint);
        protectedFileMetadata = activeCheckpoint.protectedFileMetadata;
      }

      bool folderMatchesTarget(_DriveFolder folder) {
        if (folder.companyId != targetCompanyId ||
            folder.storageScope != targetScope) {
          return false;
        }
        return targetScope != 'group' ||
            (targetGroupId != null && folder.groupIds.contains(targetGroupId));
      }

      final folderCandidates = _folders.where(folderMatchesTarget).toList()
        ..sort((left, right) => left.id.compareTo(right.id));
      for (var index = 0; index < folderCandidates.length; index += 1) {
        if (!mounted) {
          return;
        }
        _checkBusinessReconciliationPause();
        final folder = folderCandidates[index];
        if (activeCheckpoint.isFolderComplete(folder.id)) {
          continue;
        }
        final envelopeUids = folder.sharedKeyEnvelopes.keys.toSet();
        final needsRotation =
            folder.encryptedName == null ||
            !setEquals(envelopeUids, currentRecipientUids);
        if (!needsRotation) {
          activeCheckpoint.markFolderComplete(folder.id, alreadyCurrent: 1);
          await _saveBusinessReconciliationCheckpoint(activeCheckpoint);
          alreadyCurrentFolders = activeCheckpoint.alreadyCurrentFolders;
          continue;
        }

        var clearName = folder.displayName;
        if (folder.encryptedName != null) {
          final existingFolderKey = await _businessFolderKeyString(
            folder,
            interactive: false,
          );
          if (existingFolderKey == null) {
            unavailableFolders += 1;
            continue;
          }
          final decryptedName = await _metadataEncryptionService.decryptLabel(
            encryptedLabel: folder.encryptedName!,
            key: SecretKey(base64Decode(existingFolderKey)),
          );
          if (decryptedName == null || decryptedName.trim().isEmpty) {
            unavailableFolders += 1;
            continue;
          }
          clearName = decryptedName.trim();
        }

        setState(() {
          _businessFileAccessStatus =
              'Refreshing encrypted folder access ${index + 1}/'
              '${folderCandidates.length}…';
        });
        final material = await _businessEncryptionService
            .createFileEncryptionMaterial(
              objectKey: _metadataEncryptionService.folderEncryptionContext(
                folder.id,
              ),
              recipients: recipientSet.recipients,
            );
        final encryptedName = await _metadataEncryptionService.encryptLabel(
          label: clearName,
          key: material.fileKey,
        );
        await _businessEncryptionRegistry.saveEncryptedFolder(
          folderId: folder.id,
          encryptedName: encryptedName,
          storageScope: targetScope,
          color: folder.colorHex ?? '#E8F0FE',
          envelopes: material.envelopes,
          parentId: folder.parentId,
          groupId: targetScope == 'group' ? targetGroupId : null,
        );
        activeCheckpoint.markFolderComplete(folder.id, refreshed: 1);
        await _saveBusinessReconciliationCheckpoint(activeCheckpoint);
        refreshedFolders = activeCheckpoint.refreshedFolders;
      }

      if (!mounted) {
        return;
      }
      final changedCount = refreshedFiles + rotatedFiles + refreshedFolders;
      final unavailableCount = unavailableFiles + unavailableFolders;
      if (unavailableCount == 0) {
        await _removeBusinessReconciliationCheckpoint(
          reconciliationWorkspaceKey,
        );
        reconciliationCheckpointSaved = false;
        final completedLocation = targetScope == 'group'
            ? BusinessReconciliationLocation.group(
                companyId: targetCompanyId,
                groupId: targetGroupId!,
              )
            : BusinessReconciliationLocation.companyShared(
                companyId: targetCompanyId,
              );
        try {
          await widget.onBusinessReconciliationCompleted?.call(
            completedLocation,
          );
        } catch (_) {
          // Access reconciliation is already complete. The encrypted local
          // attention queue can remove this reminder on a later retry.
        }
      }
      final baseStatus = changedCount > 0
          ? 'Added member access to $refreshedFiles file'
                '${refreshedFiles == 1 ? '' : 's'}, rotated $rotatedFiles file'
                '${rotatedFiles == 1 ? '' : 's'}, and refreshed '
                '$refreshedFolders '
                'folder${refreshedFolders == 1 ? '' : 's'} for current '
                'members. Added $addedEnvelopes file-key '
                'envelope${addedEnvelopes == 1 ? '' : 's'} and removed '
                'legacy path labels from $protectedFileMetadata file '
                'record${protectedFileMetadata == 1 ? '' : 's'}.'
                '${cleanupPendingFiles > 0 ? ' Encrypted cleanup for $cleanupPendingFiles replaced provider object${cleanupPendingFiles == 1 ? '' : 's'} will retry automatically.' : ''}'
          : candidates.isEmpty && folderCandidates.isEmpty
          ? 'There are no encrypted files or folders in this space yet.'
          : protectedFileMetadata > 0
          ? 'Removed legacy path labels from $protectedFileMetadata encrypted '
                'file record${protectedFileMetadata == 1 ? '' : 's'}.'
                '${unavailableCount > 0 ? ' $unavailableCount older encrypted item${unavailableCount == 1 ? '' : 's'} still need a member with existing access.' : ''}'
          : unavailableCount > 0
          ? 'No items changed. $unavailableCount older encrypted '
                'item${unavailableCount == 1 ? '' : 's'} need a member with '
                'existing access to refresh them.'
          : 'All $alreadyCurrentFiles encrypted file'
                '${alreadyCurrentFiles == 1 ? '' : 's'} and '
                '$alreadyCurrentFolders folder'
                '${alreadyCurrentFolders == 1 ? '' : 's'} are already '
                'available to current members.';
      final status =
          '$baseStatus'
          '${unavailableCount > 0 ? ' Authenticated progress is saved on this device; retry when a member with existing access is available.' : ''}';
      setState(() {
        _businessFileAccessStatus = status;
      });
      _showMessage(status);
    } on _BusinessReconciliationPaused {
      final message = reconciliationCheckpointSaved
          ? 'Encrypted member access paused safely. Authenticated progress is '
                'saved on this device; resume when ready.'
          : 'Encrypted member access paused before progress started.';
      if (mounted) {
        setState(() {
          _businessFileAccessStatus = message;
        });
        _showMessage(message);
      }
    } on BusinessReconciliationCheckpointException catch (error) {
      final message =
          '${error.message}'
          '${reconciliationCheckpointSaved ? ' Completed items remain safely updated; encrypted progress is retained for retry.' : ''}';
      if (mounted) {
        setState(() {
          _businessFileAccessStatus = message;
        });
        _showMessage(message);
      }
    } on BusinessEncryptionRegistryException catch (error) {
      final message =
          '${error.message}'
          '${reconciliationCheckpointSaved ? ' Authenticated progress is saved on this device; retry to continue.' : ''}';
      if (mounted) {
        setState(() {
          _businessFileAccessStatus = message;
        });
        _showMessage(message);
      }
    } on BusinessEncryptionException catch (error) {
      final message =
          '${error.message}'
          '${reconciliationCheckpointSaved ? ' Authenticated progress is saved on this device; retry to continue.' : ''}';
      if (mounted) {
        setState(() {
          _businessFileAccessStatus = message;
        });
        _showMessage(message);
      }
    } on Exception {
      final message = reconciliationCheckpointSaved
          ? 'Encrypted member access reconciliation stopped. Completed items '
                'remain safely updated, and authenticated progress is saved '
                'on this device; retry to continue.'
          : 'Encrypted member access reconciliation stopped before local '
                'progress could be saved. Cloud data already confirmed by the '
                'app remains safely updated; retry to continue.';
      if (mounted) {
        setState(() {
          _businessFileAccessStatus = message;
        });
        _showMessage(message);
      }
    } finally {
      if (mounted) {
        setState(() {
          _refreshingBusinessFileAccess = false;
          _pauseBusinessReconciliationRequested = false;
        });
      } else {
        _refreshingBusinessFileAccess = false;
        _pauseBusinessReconciliationRequested = false;
      }
    }
  }

  int get _legacyMetadataItemCountForActiveSpace {
    final folderCount = _folders
        .where(
          (folder) =>
              _folderMatchesActiveStorageSpace(folder) &&
              folder.encryptedName == null,
        )
        .length;
    final fileCount = _files
        .where(
          (file) =>
              file.isActive &&
              file.isEncrypted &&
              _fileMatchesActiveStorageSpace(file) &&
              (file.folderName != null ||
                  file.folderColor != null ||
                  file.pathSegments.isNotEmpty),
        )
        .length;
    return folderCount + fileCount;
  }

  Map<String, dynamic> _storageMetadataForFolder(_DriveFolder folder) {
    if (folder.storageScope == 'personal') {
      return const <String, dynamic>{};
    }
    final metadata = <String, dynamic>{
      'storageScope': folder.storageScope,
      if (folder.companyId != null) 'companyId': folder.companyId,
      'ownerUid': folder.ownerUid ?? widget.user.uid,
      'createdByUid': folder.createdByUid ?? widget.user.uid,
      'allowedUids': folder.allowedUids.isEmpty
          ? <String>[widget.user.uid]
          : folder.allowedUids,
    };
    if (folder.groupIds.isNotEmpty) {
      metadata['groupIds'] = folder.groupIds;
    }
    return metadata;
  }

  Future<void> _protectLegacyMetadataForActiveSpace() async {
    if (_protectingLegacyMetadata ||
        _activeStorageUsesMemberEnvelopes ||
        !mounted) {
      return;
    }
    final initialCount = _legacyMetadataItemCountForActiveSpace;
    if (initialCount == 0) {
      _showMessage('Folder and path metadata is already protected.');
      return;
    }
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Protect existing metadata?'),
            content: Text(
              'This device will encrypt existing folder names and remove '
              'redundant path labels from $initialCount item'
              '${initialCount == 1 ? '' : 's'}. Names remain readable after '
              'this device unlocks encryption.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Not now'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                icon: const Icon(Icons.lock_outline),
                label: const Text('Protect metadata'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) {
      return;
    }

    setState(() {
      _protectingLegacyMetadata = true;
      _metadataPrivacyStatus = 'Preparing encrypted metadata…';
    });
    var protectedFolders = 0;
    var protectedFiles = 0;
    var failedItems = 0;
    try {
      if (!await _ensureAuthenticated(interactive: true) ||
          !await _ensureTwoFactorSession(interactive: true)) {
        _metadataPrivacyStatus =
            'Sign in and complete security verification before protecting '
            'metadata.';
        return;
      }
      final keyString = await _ensureEncryptionKey(interactive: true);
      if (keyString == null || keyString.isEmpty) {
        _metadataPrivacyStatus =
            'Unlock encryption before protecting existing metadata.';
        return;
      }

      final folders = _folders
          .where(
            (folder) =>
                _folderMatchesActiveStorageSpace(folder) &&
                folder.encryptedName == null,
          )
          .toList(growable: false);
      for (var index = 0; index < folders.length; index += 1) {
        if (!mounted) {
          return;
        }
        final folder = folders[index];
        setState(() {
          _metadataPrivacyStatus =
              'Encrypting folder ${index + 1}/${folders.length}…';
        });
        try {
          final saved = await _saveEncryptedFolderDocument(
            folderId: folder.id,
            name: folder.displayName,
            color: folder.colorHex ?? '#E8F0FE',
            parentId: folder.parentId,
            systemFolder: folder.systemFolder,
            systemKey: folder.systemKey,
            storageMetadataOverride: _storageMetadataForFolder(folder),
            interactive: false,
          );
          if (saved) {
            protectedFolders += 1;
          } else {
            failedItems += 1;
          }
        } on Exception {
          failedItems += 1;
        }
      }

      final files = _files
          .where(
            (file) =>
                file.isActive &&
                file.isEncrypted &&
                _fileMatchesActiveStorageSpace(file) &&
                (file.folderName != null ||
                    file.folderColor != null ||
                    file.pathSegments.isNotEmpty),
          )
          .toList(growable: false);
      const chunkSize = 400;
      for (var offset = 0; offset < files.length; offset += chunkSize) {
        final batch = widget.firestore.batch();
        final end = min(offset + chunkSize, files.length);
        for (final file in files.sublist(offset, end)) {
          batch.update(widget.firestore.collection('files').doc(file.id), {
            'folderName': FieldValue.delete(),
            'folderColor': FieldValue.delete(),
            'pathSegments': FieldValue.delete(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        try {
          await batch.commit();
          protectedFiles += end - offset;
        } on Exception {
          failedItems += end - offset;
        }
      }

      if (!mounted) {
        return;
      }
      final status =
          'Protected $protectedFolders folder'
          '${protectedFolders == 1 ? '' : 's'} and $protectedFiles file '
          'record${protectedFiles == 1 ? '' : 's'}'
          '${failedItems == 0 ? '.' : '; $failedItems item${failedItems == 1 ? '' : 's'} could not be changed.'}';
      setState(() {
        _metadataPrivacyStatus = status;
      });
      _showMessage(status);
    } finally {
      if (mounted) {
        setState(() {
          _protectingLegacyMetadata = false;
        });
      } else {
        _protectingLegacyMetadata = false;
      }
    }
  }

  String _uniqueArchiveEntryName(_DriveFile file, Set<String> usedNames) {
    final sanitized = _sanitizeFileName(file.name);
    final safeName = sanitized.isEmpty ? 'file' : sanitized;
    final extension = p.extension(safeName);
    final stem = p.basenameWithoutExtension(safeName);
    var candidate = safeName;
    var suffix = 2;
    while (!usedNames.add(candidate.toLowerCase())) {
      candidate =
          '${stem.isEmpty ? 'file' : stem} ($suffix)${extension.isEmpty ? '' : extension}';
      suffix += 1;
    }
    return candidate;
  }

  String _downloadBundleFileName() {
    final timestamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(RegExp(r'[^0-9A-Za-z]'), '')
        .substring(0, 15);
    return 'ronik-cloud-files-$timestamp.zip';
  }

  Future<void> _manageSelectedStorageSpeed() async {
    final file = _singleSelectedFile();
    if (file == null || !mounted) {
      return;
    }
    final choice = await showModalBottomSheet<_HotStorageChoice>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('Storage speed'),
              subtitle: Text(
                'RonikCloud manages this automatically. Change it only when you want to.',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: const Text('Automatic (recommended)'),
              subtitle: const Text(
                'Keeps active files fast and archives inactive files safely.',
              ),
              onTap: () =>
                  Navigator.pop(sheetContext, _HotStorageChoice.automatic),
            ),
            ListTile(
              leading: const Icon(Icons.bolt_rounded),
              title: const Text('Always fast'),
              subtitle: const Text('Never archive this file automatically.'),
              onTap: () =>
                  Navigator.pop(sheetContext, _HotStorageChoice.alwaysFast),
            ),
            ListTile(
              leading: const Icon(Icons.event_outlined),
              title: const Text('Keep fast until...'),
              subtitle: const Text('Choose a specific date.'),
              onTap: () =>
                  Navigator.pop(sheetContext, _HotStorageChoice.keepFastUntil),
            ),
            ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: const Text('Archive now'),
              subtitle: const Text(
                'Create a cold copy now; provider retention still applies.',
              ),
              onTap: () =>
                  Navigator.pop(sheetContext, _HotStorageChoice.archiveNow),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) {
      return;
    }

    var action = 'automatic';
    DateTime? hotUntil;
    switch (choice) {
      case _HotStorageChoice.automatic:
        action = 'automatic';
        break;
      case _HotStorageChoice.alwaysFast:
        action = 'always_fast';
        break;
      case _HotStorageChoice.keepFastUntil:
        final now = DateTime.now();
        final selectedDate = await showDatePicker(
          context: context,
          firstDate: DateTime(now.year, now.month, now.day + 1),
          lastDate: DateTime(now.year + 10, now.month, now.day),
          initialDate: DateTime(now.year, now.month, now.day + 30),
          helpText: 'KEEP FAST UNTIL',
        );
        if (selectedDate == null) {
          return;
        }
        action = 'keep_fast_until';
        hotUntil = DateTime.utc(
          selectedDate.year,
          selectedDate.month,
          selectedDate.day,
          23,
          59,
          59,
        );
        break;
      case _HotStorageChoice.archiveNow:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Archive this file now?'),
            content: const Text(
              'RonikCloud will create and verify the cold copies immediately. '
              'The fast Wasabi copy stays until its minimum billing period ends, so this does not risk data loss.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Archive'),
              ),
            ],
          ),
        );
        if (confirmed != true) {
          return;
        }
        action = 'archive_now';
        break;
    }

    try {
      await _secureDriveService.setFileHotStoragePolicy(
        fileId: file.id,
        action: action,
        hotUntil: hotUntil,
      );
      _clearSelection();
      _showMessage(
        choice == _HotStorageChoice.archiveNow
            ? 'Cold copies will be created safely in the background.'
            : 'Storage speed preference updated.',
      );
    } on SecureDriveException catch (error) {
      _showMessage(error.message);
    }
  }

  List<SelectionActionBarItem> _buildSelectionActions() {
    final selectedFiles = _selectedFiles();
    final selectedFolders = _selectedFolderItems();
    final singleFile = _singleSelectedFile();
    final singleFolderItem = _singleSelectedFolderItem();
    final singleFolder = singleFolderItem?.folder;
    final movableFolders = selectedFolders
        .where((item) => item.folder != null)
        .map((item) => item.folder!)
        .toList(growable: false);
    final deletableFolders = movableFolders
        .where((folder) => folder.canDelete)
        .toList(growable: false);
    final hasOfflineTargets =
        selectedFiles.isNotEmpty || selectedFolders.isNotEmpty;
    final allSelectedOffline =
        hasOfflineTargets &&
        selectedFiles.every(
          (file) => _offlineFiles.containsKey(file.objectKey),
        ) &&
        selectedFolders.every(
          (item) => _offlineFolders.containsKey(item.summary.id),
        );
    final canMove = selectedFiles.isNotEmpty || movableFolders.isNotEmpty;
    final canDelete = selectedFiles.isNotEmpty || deletableFolders.isNotEmpty;

    return <SelectionActionBarItem>[
      if (selectedFiles.isNotEmpty && _canReadActiveStorage)
        SelectionActionBarItem(
          icon: Icons.download_rounded,
          tooltip: selectedFiles.length == 1
              ? 'Download'
              : 'Download selected as ZIP',
          onPressed: () => unawaited(_downloadSelectedFiles()),
        ),
      if (singleFile != null && _canShareFromActiveStorage)
        SelectionActionBarItem(
          icon: Icons.share_rounded,
          tooltip: 'Share',
          onPressed: () => unawaited(_shareSelectedItem()),
        ),
      if (singleFile != null && _canReadActiveStorage)
        SelectionActionBarItem(
          icon: Icons.forum_outlined,
          tooltip: 'Comments and review',
          onPressed: () => unawaited(_collaborateOnSelectedFile()),
        ),
      if (singleFile != null && _canWriteActiveStorage)
        SelectionActionBarItem(
          icon: Icons.speed_rounded,
          tooltip: 'Storage speed',
          onPressed: () => unawaited(_manageSelectedStorageSpeed()),
        ),
      if ((singleFile != null || singleFolder != null) &&
          _canWriteActiveStorage)
        SelectionActionBarItem(
          icon: Icons.drive_file_rename_outline,
          tooltip: 'Rename',
          onPressed: () => unawaited(_renameSelectedItem()),
        ),
      if (hasOfflineTargets && _canReadActiveStorage)
        SelectionActionBarItem(
          icon: allSelectedOffline
              ? Icons.offline_pin_outlined
              : Icons.download_for_offline_outlined,
          tooltip: allSelectedOffline
              ? 'Stop keeping offline'
              : 'Keep encrypted offline',
          onPressed: () => unawaited(_toggleSelectedOfflineAvailability()),
        ),
      if (canMove && _canWriteActiveStorage)
        SelectionActionBarItem(
          icon: Icons.drive_file_move_outline,
          tooltip: 'Move',
          onPressed: () => unawaited(_moveSelectedItems()),
        ),
      if (singleFolder?.canDelete == true && _canWriteActiveStorage)
        SelectionActionBarItem(
          icon: Icons.folder_open_outlined,
          tooltip: 'Remove folder, keep files',
          onPressed: () => unawaited(_removeSelectedFolderKeepContents()),
        ),
      if (canDelete && _canWriteActiveStorage)
        SelectionActionBarItem(
          icon: Icons.delete_outline,
          tooltip: 'Delete',
          onPressed: () => unawaited(_deleteSelectedItems()),
        ),
    ];
  }

  double _usedBytes = 0;
  double _totalBytes = 0;
  double? _profileUsageBytes;
  double? _fileUsageBytes;
  double _pendingUploadBytes = 0;
  double? _storageLimitBytes;
  bool _isFreeStorageAccount = false;
  Map<String, dynamic>? _supportProfile;
  bool _feedbackSubmitted = false;
  bool _storageHasLimit = false;
  bool _storageLimitPending = false;
  String? _storagePlanLabel;
  StorageInventoryStatus _storageInventoryStatus =
      const StorageInventoryStatus();
  bool _profileRequiresTwoFactor = false;

  bool _passphraseRequired = false;
  bool _securityBusy = false;
  String? _sessionPassphrase;
  String? _secureSessionPassphrase;
  String? _storageHomePrefix;
  String? _companyId;
  String? _companyMembershipStatus;
  List<String> _companyAccessScopes = const <String>[];
  List<String> _companyGroupIds = const <String>[];
  BusinessStoragePermissions _companyStoragePermissions =
      const BusinessStoragePermissions();
  List<String>? _companyGroupStorageEnabledIds;
  CompanyStoragePolicy _companyStoragePolicy = const CompanyStoragePolicy();
  CompanyMemberStorageOverride _companyStorageOverride =
      const CompanyMemberStorageOverride();
  String _activeStorageScope = 'personal';
  String? _activeStorageGroupId;
  Uint8List? _encryptionSalt;
  Uint8List? _secureEncryptionSalt;
  String? _encryptionPasswordHash;
  String? _cachedEncryptionKey;
  String? _cachedSecureEncryptionKey;
  PreviewReadGuard? _activeMemoryPreview;
  bool _memoryPreviewReadInFlight = false;
  String? _lastEncryptionSetupError;
  _StorageDisplayMode _storageDisplay = _StorageDisplayMode.amount;
  _StorageCapacityLocation _storageLocation = _StorageCapacityLocation.hidden;
  _WorkspaceTileDensity _tileDensity = _WorkspaceTileDensity.comfortable;
  _WorkspaceFolderPlacement _folderPlacement = _WorkspaceFolderPlacement.auto;
  bool _authSessionInvalid = false;
  bool _authWarningShown = false;
  bool _secureRefreshPromptActive = false;
  Future<bool>? _activeAuthCheck;
  Future<bool>? _activeStorageProvisionCheck;
  Future<void>? _activeWasabiCorsCheck;
  DateTime? _lastStorageProvisionCheckAt;
  bool _wasabiCorsReady = false;
  int? _uploadBandwidthLimitBytesPerSecond;
  double _bandwidthTokens = 0;
  DateTime? _bandwidthLastTokenTime;
  late final TextEditingController _searchController;
  String _searchQuery = '';
  bool _recentExpanded = false;
  final Random _random = Random();
  static const Duration _backupResyncInterval = Duration(minutes: 15);
  static const Duration _storageProvisionCheckCooldown = Duration(seconds: 10);
  static const String _defaultWasabiRegion = 'eu-south-1';
  static const String _defaultWasabiSigningRegion = 'us-east-1';
  static const String _defaultWasabiEndpoint =
      'https://s3.eu-south-1.wasabisys.com';
  static const int _secureShardSizeBytes = 4 * 1024 * 1024;
  static const Duration _secureRefreshInterval = Duration(days: 90);
  static const String _secureShardSchemePassphraseHmacV1 =
      'passphrase-hmac-sha256-v1';
  static const String _secureContentEncodingWholeFileV1 =
      'whole-file-aes-ctr-hmac-sha256-v1';
  static final RegExp _invalidFileNamePattern = RegExp(r'[\\/:*?"<>|]');
  static const String _backupConfigsPrefKey =
      LocalPrivateCacheCodec.backupConfigsPreferenceKey;
  static const String _backupSignaturesPrefKey =
      LocalPrivateCacheCodec.backupFingerprintsPreferenceKey;
  static const String _backupScanRatePrefKey = 'workspace_backup_scan_rate_v1';
  static const String _backupBackgroundEnabledPrefKey =
      'workspace_backup_background_enabled_v1';
  static const String _backupBackgroundPreferenceSetPrefKey =
      'workspace_backup_background_pref_set_v1';
  static const String _offlineFilesPrefKey =
      LocalPrivateCacheCodec.offlineFilesPreferenceKey;
  static const String _cachedFilesPrefKey =
      LocalPrivateCacheCodec.cachedFilesPreferenceKey;
  static const String _cachedFoldersPrefKey =
      LocalPrivateCacheCodec.cachedFoldersPreferenceKey;
  static const String _offlineFoldersPrefKey =
      LocalPrivateCacheCodec.offlineFoldersPreferenceKey;
  static const String _offlineDirectoryPrefKey =
      LocalPrivateCacheCodec.offlineDirectoryPreferenceKey;
  static const String _workspaceWalkthroughCompletedPrefKey =
      'workspace_walkthrough_completed_v1';
  static const String _workspaceTileDensityPrefKey =
      'workspace_tile_density_v1';
  static const String _workspaceFolderPlacementPrefKey =
      'workspace_folder_placement_v1';
  static const String _uploadBandwidthLimitPrefKey =
      'workspace_upload_bandwidth_limit_bps_v1';
  static const int _customBandwidthOptionValue = -1;
  static const int _minimumCustomBandwidthBytesPerSecond = 1024;
  static const int _maximumCustomBandwidthBytesPerSecond =
      10 * 1024 * 1024 * 1024;

  static const List<_BandwidthLimitOption> _bandwidthLimitOptions =
      <_BandwidthLimitOption>[
        _BandwidthLimitOption(
          label: 'Unlimited (maximum speed)',
          value: 0,
          description: 'Uploads use the maximum bandwidth available.',
        ),
        _BandwidthLimitOption(
          label: 'Slow - 512 KB/s',
          value: 512 * 1024,
          description: 'Best when uploads should stay in the background.',
        ),
        _BandwidthLimitOption(
          label: 'Medium - 2 MB/s',
          value: 2 * 1024 * 1024,
          description: 'A balanced limit for normal browsing and calls.',
        ),
        _BandwidthLimitOption(
          label: 'Fast - 10 MB/s',
          value: 10 * 1024 * 1024,
          description: 'Faster uploads while keeping a fixed ceiling.',
        ),
      ];

  static const Map<String, String> _contentTypeByExtension = <String, String>{
    'bmp': 'image/bmp',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'gif': 'image/gif',
    'heic': 'image/heic',
    'heif': 'image/heif',
    'webp': 'image/webp',
    'pdf': 'application/pdf',
    'txt': 'text/plain',
    'csv': 'text/csv',
    'json': 'application/json',
    'mp4': 'video/mp4',
    'mov': 'video/quicktime',
    'avi': 'video/x-msvideo',
    'zip': 'application/zip',
  };

  String? _contentTypeForName(String name, {String? fallbackMimeType}) {
    final trimmedMime = fallbackMimeType?.trim().toLowerCase();
    if (trimmedMime != null && trimmedMime.isNotEmpty) {
      return trimmedMime;
    }
    final extension = p.extension(name).replaceFirst('.', '').toLowerCase();
    return extension.isEmpty ? null : _contentTypeByExtension[extension];
  }

  String _thumbnailObjectKeyFor(String objectKey) {
    return thumbnailStorageObjectKey(
      objectKey,
      fallbackPrefix: _objectKeyOwnerPrefix,
    );
  }

  List<String> _thumbnailObjectKeyCandidatesFor(String objectKey) {
    return thumbnailStorageObjectKeyCandidates(
      objectKey,
      fallbackPrefix: _objectKeyOwnerPrefix,
    );
  }

  static const int _maxInlinePreviewBytes = 20 * 1024 * 1024;
  static const Set<String> _textPreviewExtensions = <String>{
    'bat',
    'c',
    'cc',
    'conf',
    'cpp',
    'css',
    'csv',
    'dart',
    'go',
    'gradle',
    'h',
    'hpp',
    'htm',
    'html',
    'ini',
    'java',
    'js',
    'json',
    'kt',
    'kts',
    'log',
    'md',
    'php',
    'properties',
    'ps1',
    'py',
    'rb',
    'rs',
    'sh',
    'sql',
    'swift',
    'ts',
    'txt',
    'xml',
    'yaml',
    'yml',
  };
  static const Set<String> _imagePreviewExtensions = <String>{
    'bmp',
    'gif',
    'jpeg',
    'jpg',
    'png',
    'webp',
  };

  static const List<String> _folderAccentPalette = <String>[
    '#dbe4ff',
    '#f9e6ff',
    '#ffe8f0',
    '#e6f5ff',
    '#e7f9ed',
    '#ffeede',
  ];

  bool get _supportsPersistentFolderBackups => supportsPersistentFolderBackups(
    isWeb: kIsWeb,
    platform: defaultTargetPlatform,
  );

  bool get _supportsBackgroundBackupSources =>
      _supportsPersistentFolderBackups || IosPhotoLibrary.supported;

  String get _folderBackupUnavailableMessage =>
      persistentFolderBackupUnavailableMessage(
        isWeb: kIsWeb,
        platform: defaultTargetPlatform,
      );

  bool _canRunBackupConfig(_BackupFolderConfig config) =>
      canRunPersistentBackupConfig(
        isWeb: kIsWeb,
        platform: defaultTargetPlatform,
        photoLibrary: config.photoLibrary,
        hasFolderBookmark: config.accessBookmark?.isNotEmpty == true,
      );

  bool get _supportsForegroundBackupWatchers =>
      _supportsPersistentFolderBackups &&
      defaultTargetPlatform == TargetPlatform.macOS;

  @override
  void initState() {
    super.initState();
    _transferController = WorkspaceTransferController();
    if (widget.businessMode) {
      _activeStorageScope = 'company_shared';
    }
    _logRuntime('lifecycle', 'Workspace initialized.');
    _searchController = TextEditingController(text: _searchQuery);
    final injectedService = widget.storageService;
    if (injectedService != null) {
      _storageService = injectedService;
    } else {
      final resolvedService = WasabiStorageService.fromEnvironment();
      _storageService = resolvedService;
    }
    _driveRepository =
        widget.driveRepository ?? DriveRepository(firestore: widget.firestore);
    _uploadMetadataService =
        widget.uploadMetadataService ??
        UploadMetadataService.forApp(widget.auth.app);
    _secureDriveService = SecureDriveService.forApp(
      app: widget.auth.app,
      firestore: widget.firestore,
    );
    _encryptionSetupService =
        widget.encryptionSetupService ??
        EncryptionSetupService.forApp(widget.auth.app);
    _shareLinkOwnerService =
        widget.shareLinkOwnerService ??
        ShareLinkOwnerService.forApp(widget.auth.app);
    _businessEncryptionRegistry = BusinessEncryptionRegistry.forApp(
      widget.auth.app,
    );
    _businessEncryptionService = BusinessEncryptionService();
    _metadataEncryptionService = WorkspaceMetadataEncryptionService();
    _localPrivateCacheCodec = LocalPrivateCacheCodec.instance;
    _offlineVault = LocalOfflineVault(
      uid: widget.user.uid,
      scope: _localPrivateCacheScope(),
    );
    _temporaryPlaintextLeases = TemporaryPlaintextLeaseManager();
    _twoFactorApi = FirebaseTwoFactorApi.forApp(widget.auth.app);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_primeUserProfileSnapshot());
    unawaited(_cleanupPlaintextTemporaryFilesOnStartup());
    _loadInitialState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryApplyRequestedBusinessReconciliationLocation();
    });
  }

  @override
  void didUpdateWidget(covariant WorkspaceHomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.uid != widget.user.uid) {
      final oldActivity = _activityStore;
      if (oldActivity != null) unawaited(NotificationService().cancelAccount(oldActivity));
      _activitySubscription?.cancel();
      _notificationOpenSubscription?.cancel();
      _activityStore = null;
      _metadataShardCaches.clear();_fileCacheRows.clear();_folderCacheRows.clear();
      _lastTransferAttention = null;
      unawaited(_initializeActivity());
    }
    if (oldWidget.businessReconciliationRequestRevision !=
            widget.businessReconciliationRequestRevision ||
        oldWidget.requestedBusinessReconciliationLocation !=
            widget.requestedBusinessReconciliationLocation) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _tryApplyRequestedBusinessReconciliationLocation();
      });
    }
  }

  @override
  void setState(VoidCallback fn) {
    if (!mounted) {
      return;
    }
    super.setState(fn);
  }

  @override
  void dispose() {
    final activity = _activityStore;
    if (activity != null && widget.auth.currentUser?.uid != widget.user.uid) {
      unawaited(NotificationService().cancelAccount(activity));
    }
    _activitySubscription?.cancel();
    _notificationOpenSubscription?.cancel();
    _viewCache.clear();
    _fileSnapshotSources.index?.clear();
    _folderSnapshotSources.index?.clear();
    _activeMemoryPreview?.cancel();
    _logRuntime('lifecycle', 'Workspace disposed.');
    _cachedEncryptionKey = null;
    _cachedSecureEncryptionKey = null;
    _secureSessionPassphrase = null;
    _businessEncryptionIdentity = null;
    _businessEncryptionIdentityRequest = null;
    _businessFileKeyCache.clear();
    _resolvedFileNameCache.clear();
    _resolvedFolderNameCache.clear();
    _thumbnailCache.clear();
    _thumbnailRequests.clear();
    _thumbnailRetryAfter.clear();
    _userSubscription?.cancel();
    _filesSubscription?.cancel();
    _companyFilesSubscription?.cancel();
    _foldersSubscription?.cancel();
    _companyFoldersSubscription?.cancel();
    _shareLinksSubscription?.cancel();
    _shareLinkExpiryTimer?.cancel();
    _userStreamReconnectTimer?.cancel();
    _filesStreamReconnectTimer?.cancel();
    _foldersStreamReconnectTimer?.cancel();
    for (final subscription in _backupListeners.values) {
      subscription.cancel();
    }
    for (final lease in _backupFolderLeases.values) {
      unawaited(lease.close());
    }
    _backupFolderLeases.clear();
    for (final debounce in _backupWatchDebouncers.values) {
      debounce.cancel();
    }
    _backupScanTimer?.cancel();
    _startupBackupActivationTimer?.cancel();
    _startupPhotosProvisionTimer?.cancel();
    _folderCachePersistTimer?.cancel();
    _fileCachePersistTimer?.cancel();
    _transferController.dispose();
    _transferJournal?.lifecycle.removeListener(_handleTransferJournalChanged);
    _transferJournal?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (UploadCoordinator.enabled) {
      UploadCoordinator.instance.scheduler.setRestricted(state != AppLifecycleState.resumed);
    }
    if (state != AppLifecycleState.resumed) {
      _activeMemoryPreview?.cancel();
      return;
    }
    if (!kIsWeb) {
      unawaited(_cleanupPlaintextTemporaryFilesAfterResume());
    }
    unawaited(_refreshActivity());
    unawaited(_recoverPendingUploadMetadata());
  }

  void _handleTransferJournalChanged() {
    _recordTransferAttention();
    if (mounted) setState(() {});
  }

  Future<void> _loadInitialState() async {
    await _loadPreferences();
    unawaited(_initializeActivity());
    if (!mounted) {
      _logRuntime(
        'lifecycle',
        'WorkspaceHomePage startup stopped before passphrase restore because the widget was disposed.',
      );
      return;
    }
    // Fetch metadata while the device keychain restores the encryption key.
    // Encrypted labels still go through their existing key checks.
    _subscribeToUserProfile();
    _subscribeToFolders();
    _subscribeToFiles();
    _subscribeToOwnedShareLinks();

    _initializing = false;
    if (mounted) {
      setState(() {});
    }

    await _restoreLoginPassphraseIfAvailable();
    if (!mounted) return;
    _scheduleDeferredStartupTasks();
  }

  void _subscribeToOwnedShareLinks() {
    unawaited(_shareLinksSubscription?.cancel());
    _shareLinkExpiryTimer?.cancel();
    _shareLinkExpiryTimer = null;
    _shareLinksSubscription = widget.firestore
        .collection('shared_links')
        .where('uid', isEqualTo: widget.user.uid)
        .snapshots()
        .listen(
          (snapshot) {
            if (!mounted) {
              return;
            }
            final index = ShareLinkOwnerIndex.fromMaps(
              snapshot.docs.map((document) => document.data()),
              timestampParser: _DriveFile._parseTimestamp,
            );
            setState(() {
              _shareLinkOwnerIndex = index;
              _shareLinkIndexAvailable = true;
            });
            _scheduleShareLinkExpiryRefresh();
          },
          onError: (_) {
            if (!mounted) {
              return;
            }
            _shareLinkExpiryTimer?.cancel();
            _shareLinkExpiryTimer = null;
            setState(() => _shareLinkIndexAvailable = false);
            if (kDebugMode) {
              debugPrint('Password-link summary updates are unavailable.');
            }
          },
        );
  }

  void _scheduleShareLinkExpiryRefresh() {
    _shareLinkExpiryTimer?.cancel();
    _shareLinkExpiryTimer = null;
    final now = DateTime.now().toUtc();
    final nextExpiry = _shareLinkOwnerIndex.nextExpiryAfter(now);
    if (nextExpiry == null) {
      return;
    }
    final delay = nextExpiry.difference(now) + const Duration(seconds: 1);
    _shareLinkExpiryTimer = Timer(delay, () {
      _shareLinkExpiryTimer = null;
      if (mounted) {
        setState(() {});
        _scheduleShareLinkExpiryRefresh();
      }
    });
  }

  int _activeShareLinkCountFor(String fileId) {
    if (!_shareLinkIndexAvailable) {
      return 0;
    }
    return _shareLinkOwnerIndex.activeCountFor(fileId, DateTime.now().toUtc());
  }

  void _scheduleDeferredStartupTasks() {
    _startupBackupActivationTimer?.cancel();
    _startupPhotosProvisionTimer?.cancel();

    if (_supportsBackgroundBackupSources) {
      _startupBackupActivationTimer = Timer(const Duration(seconds: 15), () {
        _startupBackupActivationTimer = null;
        unawaited(
          _runGuardedTask(
            scope: 'backup',
            reason: 'startup_backup_activation',
            action: _activateConfiguredBackgroundBackups,
          ),
        );
      });
    }

    _startupPhotosProvisionTimer = Timer(const Duration(seconds: 25), () {
      _startupPhotosProvisionTimer = null;
      unawaited(
        _runGuardedTask(
          scope: 'folders',
          reason: 'startup_photos_folder_provisioning',
          action: _ensurePhotosFolder,
        ),
      );
    });
  }

  Future<void> _activateConfiguredBackgroundBackups() async {
    if (!mounted || kIsWeb) {
      return;
    }

    if (_backgroundBackupEnabled) {
      for (final config in _backupFolders.values) {
        if (!config.enabled || !_canRunBackupConfig(config)) {
          continue;
        }
        await _startBackupListener(config);
      }
    }

    _updateBackupScanTimerState(forceRestart: true);
  }

  Future<void> _maybeShowWorkspaceWalkthrough({bool force = false}) async {
    if (!mounted || _walkthroughVisible) {
      return;
    }

    final prefs = _prefs ?? await SharedPreferences.getInstance();
    _prefs ??= prefs;

    final completed =
        await _readAccountScopedBoolPreference(
          prefs,
          _workspaceWalkthroughCompletedPrefKey,
        ) ==
        true;
    if (!force && completed) {
      return;
    }
    if (!mounted) {
      return;
    }

    setState(() => _showSetupChecklist = true);
    _walkthroughVisible = true;
    try {
      final action = await showDialog<_WorkspaceWalkthroughAction>(
        context: context,
        barrierDismissible: true,
        builder: (context) {
          return _WorkspaceWalkthroughDialog(
            steps: _buildWorkspaceWalkthroughSteps(),
          );
        },
      );
      if (action == _WorkspaceWalkthroughAction.completed ||
          action == _WorkspaceWalkthroughAction.skipped) {
        await _writeAccountScopedBoolPreference(
          prefs,
          _workspaceWalkthroughCompletedPrefKey,
          true,
        );
      }
    } finally {
      _walkthroughVisible = false;
    }
  }

  List<_WorkspaceWalkthroughStep> _buildWorkspaceWalkthroughSteps() {
    return const <_WorkspaceWalkthroughStep>[
      _WorkspaceWalkthroughStep(
        icon: Icons.folder_outlined,
        title: 'Your files, in one place',
        description: 'Use Files to upload, search, and organize your files.',
        points: <String>[
          'Choose Upload to add a file. On desktop, you can also drag it into the window.',
          'Open your account menu for settings. This tour is available again under Workspace tour.',
        ],
      ),
      _WorkspaceWalkthroughStep(
        icon: Icons.backup_outlined,
        title: 'Back up a folder',
        description:
            'Open Backups and choose a folder on this device. Only folders you select are included.',
        points: <String>[
          'On supported devices, backup status updates automatically. Opening Backups is not required to start or confirm a sync.',
          'Check for a successful sync before relying on a backup. Sleep, sign-out, and a locked keychain can pause it.',
        ],
      ),
      _WorkspaceWalkthroughStep(
        icon: Icons.offline_pin_outlined,
        title: 'Keep files available offline',
        description:
            'Keep selected files offline to access them through RonikCloud without a connection.',
        points: <String>[
          'Use Offline to find the files saved on this device.',
          'The optional setup guide can be expanded or minimized at any time. You can start using Files straight away.',
        ],
      ),
    ];
  }

  Future<void> _ensurePhotosFolder() async {
    try {
      final localFolder = _folders.cast<_DriveFolder?>().firstWhere(
        (folder) =>
            folder?.storageScope == 'personal' &&
            folder?.displayName == 'Photos',
        orElse: () => null,
      );
      if (localFolder?.encryptedName != null) {
        return;
      }
      String? folderId = localFolder?.id;
      if (folderId == null) {
        final query = widget.firestore
            .collection('folders')
            .where('uid', isEqualTo: widget.user.uid)
            .where('systemKey', isEqualTo: 'photos');
        final snapshot = await query.get().timeout(const Duration(seconds: 5));
        if (snapshot.docs.isNotEmpty) {
          final existing = snapshot.docs.first;
          if (_trimmedOrNull(existing.data()['encryptedName']) != null) {
            return;
          }
          folderId = existing.id;
        }
      }
      folderId ??= widget.firestore.collection('folders').doc().id;
      await _saveEncryptedFolderDocument(
        folderId: folderId,
        name: 'Photos',
        color: '#f9e6ff',
        parentId: null,
        systemFolder: true,
        systemKey: 'photos',
        storageMetadataOverride: const <String, dynamic>{},
        interactive: false,
      ).timeout(const Duration(seconds: 5));
    } catch (_) {
      if (kDebugMode) {
        debugPrint('Photos folder provisioning was unavailable.');
      }
      _logRuntime('folders', 'Photos folder provisioning was skipped safely.');
    }
  }

  Future<bool> _ensureAuthenticated({required bool interactive}) async {
    if (_authSessionInvalid) {
      if (interactive && !_authWarningShown) {
        _showMessage(
          'Your session has expired. Please sign in again to continue.',
        );
        _authWarningShown = true;
      }
      return false;
    }

    final currentUser = widget.auth.currentUser;
    if (currentUser != null && currentUser.uid == widget.user.uid) {
      _authWarningShown = false;
      return true;
    }

    final future = _activeAuthCheck ?? _reloadAuthUser();
    _activeAuthCheck = future;
    final authenticated = await future;
    if (identical(_activeAuthCheck, future)) {
      _activeAuthCheck = null;
    }

    if (authenticated) {
      _authSessionInvalid = false;
      _authWarningShown = false;
      return true;
    }

    _authSessionInvalid = true;
    if (interactive && !_authWarningShown) {
      _showMessage(
        'Your session has expired. Please sign in again to continue.',
      );
      _authWarningShown = true;
    }
    return false;
  }

  Future<bool> _ensureTwoFactorSession({required bool interactive}) async {
    if (!_profileRequiresTwoFactor) {
      return true;
    }

    try {
      final status = await _twoFactorApi.fetchStatus();
      if (!status.enabled || status.verified) {
        return true;
      }
      if (!interactive || !mounted) {
        return false;
      }
      return await _promptForTwoFactorVerification();
    } on TwoFactorException {
      if (!_profileRequiresTwoFactor) {
        return true;
      }
      if (interactive && mounted) {
        _showMessage(
          userFacingClientFailureMessage(
            UserFacingClientFailure.twoFactorStatus,
          ),
        );
      }
      return false;
    } catch (_) {
      if (!_profileRequiresTwoFactor) {
        return true;
      }
      if (interactive && mounted) {
        _showMessage(
          userFacingClientFailureMessage(
            UserFacingClientFailure.twoFactorStatus,
          ),
        );
      }
      return false;
    }
  }

  Future<bool> _forceTwoFactorReverificationIfEnabled() async {
    try {
      final status = await _twoFactorApi.fetchStatus();
      if (!status.enabled && !_profileRequiresTwoFactor) {
        return false;
      }
      if (!mounted) {
        return false;
      }
      return await _promptForTwoFactorVerification();
    } on TwoFactorException {
      if (!_profileRequiresTwoFactor) {
        if (mounted) {
          _showMessage(
            userFacingClientFailureMessage(
              UserFacingClientFailure.twoFactorStatus,
            ),
          );
        }
        return false;
      }
      if (!mounted) {
        return false;
      }
      return await _promptForTwoFactorVerification();
    } catch (_) {
      if (!_profileRequiresTwoFactor) {
        if (mounted) {
          _showMessage(
            userFacingClientFailureMessage(
              UserFacingClientFailure.twoFactorStatus,
            ),
          );
        }
        return false;
      }
      if (!mounted) {
        return false;
      }
      return await _promptForTwoFactorVerification();
    }
  }

  Future<bool> _promptForTwoFactorVerification() async {
    final codeController = TextEditingController();
    String? errorText;
    var verifying = false;

    final verified = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> verify() async {
              final code = codeController.text.trim();
              if (code.length != 6) {
                setDialogState(() {
                  errorText =
                      'Enter the 6-digit code from your authenticator app.';
                });
                return;
              }

              setDialogState(() {
                verifying = true;
                errorText = null;
              });

              try {
                final status = await _twoFactorApi.verifyCode(code);
                if (!dialogContext.mounted) {
                  return;
                }
                if (!status.enabled || status.verified) {
                  Navigator.of(dialogContext).pop(true);
                  return;
                }
                setDialogState(() {
                  verifying = false;
                  errorText =
                      'The verification code was rejected. Try a fresh code.';
                });
                codeController.clear();
              } on TwoFactorException {
                if (!dialogContext.mounted) {
                  return;
                }
                setDialogState(() {
                  verifying = false;
                  errorText = userFacingClientFailureMessage(
                    UserFacingClientFailure.twoFactorVerification,
                  );
                });
              } catch (_) {
                if (!dialogContext.mounted) {
                  return;
                }
                setDialogState(() {
                  verifying = false;
                  errorText = userFacingClientFailureMessage(
                    UserFacingClientFailure.twoFactorVerification,
                  );
                });
              }
            }

            return AlertDialog(
              title: const Text('Security Check Required'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Enter your 6-digit authentication code to continue with this upload.',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: codeController,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    enabled: !verifying,
                    decoration: InputDecoration(
                      labelText: 'Authentication code',
                      errorText: errorText,
                    ),
                    onSubmitted: verifying ? null : (_) => unawaited(verify()),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: verifying
                      ? null
                      : () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: verifying ? null : () => unawaited(verify()),
                  child: Text(verifying ? 'Verifying...' : 'Verify'),
                ),
              ],
            );
          },
        );
      },
    );

    codeController.dispose();
    return verified == true;
  }

  Future<bool> _reloadAuthUser() async {
    try {
      final candidate = widget.auth.currentUser;
      if (candidate != null) {
        await candidate.reload();
      }
    } on FirebaseAuthException catch (_) {
      if (kDebugMode) {
        debugPrint('The authenticated session could not be refreshed.');
      }
    } catch (_) {
      if (kDebugMode) {
        debugPrint('The authenticated session refresh was unavailable.');
      }
    }

    final refreshed = widget.auth.currentUser;
    return refreshed != null && refreshed.uid == widget.user.uid;
  }

  String _accountScopedPrefKey(String baseKey) {
    final uid = widget.user.uid.trim();
    if (uid.isEmpty) {
      return baseKey;
    }
    final safeUid = uid.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return '${baseKey}_$safeUid';
  }

  Future<void> _safePreferenceWrite(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (kDebugMode) {
        debugPrint('An account-scoped preference update was unavailable.');
      }
    }
  }

  void _logRuntime(String scope, String message) {
    if (!kDebugMode) {
      return;
    }
    final timestamp = DateTime.now().toIso8601String();
    debugPrint('[RonikCloud][$scope][$timestamp] $message');
  }

  Future<void> _runGuardedTask({
    required String scope,
    required String reason,
    required Future<void> Function() action,
  }) async {
    try {
      await action();
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('A guarded workspace task failed safely.');
      }
      _logRuntime(scope, 'A guarded workspace task failed safely.');
      unawaited(
        AppErrorReporter.instance.recordError(
          error,
          stackTrace,
          reason: reason,
        ),
      );
    }
  }

  Future<String?> _readAccountScopedStringPreference(
    SharedPreferences prefs,
    String baseKey,
  ) async {
    final scopedKey = _accountScopedPrefKey(baseKey);
    final scopedValue = prefs.getString(scopedKey);
    if (scopedValue != null) {
      return scopedValue;
    }

    final legacyValue = prefs.getString(baseKey);
    if (legacyValue == null) {
      return null;
    }

    await _safePreferenceWrite(() async {
      await prefs.setString(scopedKey, legacyValue);
      await prefs.remove(baseKey);
    });
    return legacyValue;
  }

  Future<void> _writeAccountScopedStringPreference(
    SharedPreferences prefs,
    String baseKey,
    String? value,
  ) async {
    final scopedKey = _accountScopedPrefKey(baseKey);
    await _safePreferenceWrite(() async {
      if (value == null) {
        await prefs.remove(scopedKey);
      } else {
        await prefs.setString(scopedKey, value);
      }
      await prefs.remove(baseKey);
    });
  }

  LocalPrivateCachePreferences _privateCachePreferences(
    SharedPreferences prefs,
  ) {
    return LocalPrivateCachePreferences(
      preferences: prefs,
      uid: widget.user.uid,
      scope: _localPrivateCacheScope(),
      codec: _localPrivateCacheCodec,
    );
  }

  BusinessReconciliationCheckpointStore _businessCheckpointStore(
    SharedPreferences prefs,
  ) {
    return _businessReconciliationStore ??=
        BusinessReconciliationCheckpointStore(
          privateCache: _privateCachePreferences(prefs),
        );
  }

  String _businessRecipientFingerprint(
    Iterable<BusinessEncryptionRecipient> recipients,
  ) {
    final identities =
        recipients
            .map(
              (recipient) =>
                  '${recipient.uid.trim()}\u0000${recipient.keyId.trim()}',
            )
            .toList(growable: false)
          ..sort();
    return sha256
        .convert(
          utf8.encode(
            'ronikdrive-business-recipients-v1\n${identities.join('\n')}',
          ),
        )
        .toString();
  }

  String? get _activeBusinessReconciliationWorkspaceKey {
    if (!_activeStorageUsesMemberEnvelopes) {
      return null;
    }
    final companyId = _companyId?.trim();
    if (companyId == null || companyId.isEmpty) {
      return null;
    }
    try {
      return BusinessReconciliationCheckpoint.workspaceKeyFor(
        companyId: companyId,
        storageScope: _activeStorageScope,
        groupId: _activeStorageGroupId,
      );
    } on BusinessReconciliationCheckpointException {
      return null;
    }
  }

  bool get _activeBusinessReconciliationCanResume {
    final workspaceKey = _activeBusinessReconciliationWorkspaceKey;
    return workspaceKey != null &&
        _businessReconciliationCheckpointKeys.contains(workspaceKey);
  }

  Future<void> _saveBusinessReconciliationCheckpoint(
    BusinessReconciliationCheckpoint checkpoint,
  ) async {
    final prefs = _prefs;
    if (prefs == null) {
      throw const BusinessReconciliationCheckpointException(
        'Encrypted reconciliation progress is not ready on this device.',
      );
    }
    await _businessCheckpointStore(prefs).save(checkpoint);
    _businessReconciliationCheckpointKeys.add(checkpoint.workspaceKey);
    _businessReconciliationCacheLocked = false;
  }

  Future<void> _removeBusinessReconciliationCheckpoint(
    String workspaceKey,
  ) async {
    final prefs = _prefs;
    if (prefs == null) {
      return;
    }
    await _businessCheckpointStore(prefs).remove(workspaceKey);
    _businessReconciliationCheckpointKeys.remove(workspaceKey);
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

  EncryptedMetadataShards _metadataShards(SharedPreferences prefs,String base,String namespace) {
    final owner=widget.user.uid;
    return _metadataShardCaches.putIfAbsent(base,()=>EncryptedMetadataShards(
      cache:_privateCachePreferences(prefs),preferences:prefs,baseKey:base,namespace:namespace,
      uid:owner,scope:_localPrivateCacheScope(),accountCurrent:()=>mounted &&
        !_sessionInvalidated && widget.user.uid==owner && widget.auth.currentUser?.uid==owner));
  }

  Future<LocalPrivateCachePreferenceRead> _readPrivateCachePreference(
    SharedPreferences prefs, {
    required String baseKey,
    required String namespace,
  }) {
    if (baseKey == _cachedFilesPrefKey || baseKey == _cachedFoldersPrefKey) {
      return _metadataShards(prefs,baseKey,namespace).read();
    }
    return _privateCachePreferences(
      prefs,
    ).read(baseKey: baseKey, namespace: namespace);
  }

  Future<void> _writePrivateCachePreference(
    SharedPreferences prefs, {
    required String baseKey,
    required String namespace,
    required String? value,
  }) {
    if (baseKey == _cachedFilesPrefKey || baseKey == _cachedFoldersPrefKey) {
      final shards=_metadataShards(prefs,baseKey,namespace);
      return value==null?shards.clear():shards.replace((jsonDecode(value) as List)
        .map((e)=>Map<String,dynamic>.from(e as Map)).toList());
    }
    return _privateCachePreferences(
      prefs,
    ).write(baseKey: baseKey, namespace: namespace, value: value);
  }

  Future<bool?> _readAccountScopedBoolPreference(
    SharedPreferences prefs,
    String baseKey,
  ) async {
    final scopedKey = _accountScopedPrefKey(baseKey);
    if (prefs.containsKey(scopedKey)) {
      return prefs.getBool(scopedKey);
    }

    if (!prefs.containsKey(baseKey)) {
      return null;
    }

    final legacyValue = prefs.getBool(baseKey);
    await _safePreferenceWrite(() async {
      if (legacyValue != null) {
        await prefs.setBool(scopedKey, legacyValue);
      }
      await prefs.remove(baseKey);
    });
    return legacyValue;
  }

  Future<void> _writeAccountScopedBoolPreference(
    SharedPreferences prefs,
    String baseKey,
    bool? value,
  ) async {
    final scopedKey = _accountScopedPrefKey(baseKey);
    await _safePreferenceWrite(() async {
      if (value == null) {
        await prefs.remove(scopedKey);
      } else {
        await prefs.setBool(scopedKey, value);
      }
      await prefs.remove(baseKey);
    });
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    BusinessReconciliationCheckpointLoad reconciliationCheckpointLoad;
    try {
      reconciliationCheckpointLoad = await _businessCheckpointStore(
        prefs,
      ).load();
    } on Exception {
      reconciliationCheckpointLoad = const BusinessReconciliationCheckpointLoad(
        checkpoints: <BusinessReconciliationCheckpoint>[],
        temporarilyUnavailable: true,
      );
    }
    final transferJournal = await TransferJournal.open(
      preferences: prefs,
      uid: widget.user.uid,
      scope: _localPrivateCacheScope(),
      codec: _localPrivateCacheCodec,
    );
    _transferJournal?.lifecycle.removeListener(_handleTransferJournalChanged);
    _transferJournal?.dispose();
    _transferJournal = transferJournal
      ..lifecycle.addListener(_handleTransferJournalChanged);
    unawaited(_recoverPendingUploadMetadata());
    if (_storageService.isConfigured) {
      unawaited(_cleanupInterruptedMultipartUploads());
    }

    // These records use separate preference keys. The codec coalesces device
    // key loads, so independent decryptions need not queue behind each other.
    final cacheReads = await Future.wait<LocalPrivateCachePreferenceRead>([
      _readPrivateCachePreference(
        prefs,
        baseKey: _cachedFilesPrefKey,
        namespace: LocalPrivateCacheCodec.cachedFilesNamespace,
      ),
      _readPrivateCachePreference(
        prefs,
        baseKey: _cachedFoldersPrefKey,
        namespace: LocalPrivateCacheCodec.cachedFoldersNamespace,
      ),
      _readPrivateCachePreference(
        prefs,
        baseKey: _offlineFilesPrefKey,
        namespace: LocalPrivateCacheCodec.offlineFilesNamespace,
      ),
      _readPrivateCachePreference(
        prefs,
        baseKey: _offlineFoldersPrefKey,
        namespace: LocalPrivateCacheCodec.offlineFoldersNamespace,
      ),
      _readPrivateCachePreference(
        prefs,
        baseKey: _offlineDirectoryPrefKey,
        namespace: LocalPrivateCacheCodec.offlineDirectoryNamespace,
      ),
      _readPrivateCachePreference(
        prefs,
        baseKey: _backupConfigsPrefKey,
        namespace: LocalPrivateCacheCodec.backupConfigsNamespace,
      ),
      _readPrivateCachePreference(
        prefs,
        baseKey: _backupSignaturesPrefKey,
        namespace: LocalPrivateCacheCodec.backupFingerprintsNamespace,
      ),
    ]);
    final cachedFilesCacheRead = cacheReads[0];
    final cachedFoldersCacheRead = cacheReads[1];
    final offlineFilesCacheRead = cacheReads[2];
    final offlineFoldersCacheRead = cacheReads[3];
    final offlineDirectoryCacheRead = cacheReads[4];
    final backupCacheRead = cacheReads[5];
    final backupSignatureCacheRead = cacheReads[6];
    if (cachedFilesCacheRead.temporarilyUnavailable ||
        cachedFoldersCacheRead.temporarilyUnavailable) {
      _logRuntime(
        'cache',
        'Encrypted workspace listings are waiting for the device credential store.',
      );
    }
    if (cachedFilesCacheRead.discardedCorruptValue ||
        cachedFoldersCacheRead.discardedCorruptValue) {
      _logRuntime(
        'cache',
        'Unreadable or unprotectable cached workspace listings were removed.',
      );
    }
    final displayRaw = prefs.getString('workspace_storage_display_v1');
    final passphraseEnabled =
        await _readAccountScopedBoolPreference(
          prefs,
          'workspace_passphrase_required_v1',
        ) ??
        prefs.getBool('workspace_passphrase_required_v1') ??
        false;

    final offlineRaw = offlineFilesCacheRead.value;
    final offlineFolderRaw = offlineFoldersCacheRead.value;
    final offlineDirectoryRaw = offlineDirectoryCacheRead.value;

    final backupRaw = backupCacheRead.value;
    final backupSignatureRaw = backupSignatureCacheRead.value;
    final locationRaw = prefs.getString('workspace_storage_location_v1');
    final tileDensityRaw = await _readAccountScopedStringPreference(
      prefs,
      _workspaceTileDensityPrefKey,
    );
    final folderPlacementRaw = await _readAccountScopedStringPreference(
      prefs,
      _workspaceFolderPlacementPrefKey,
    );
    final scanRaw = await _readAccountScopedStringPreference(
      prefs,
      _backupScanRatePrefKey,
    );
    final backgroundBackupEnabledRaw = await _readAccountScopedBoolPreference(
      prefs,
      _backupBackgroundEnabledPrefKey,
    );
    final backgroundBackupPreferenceSetRaw =
        await _readAccountScopedBoolPreference(
          prefs,
          _backupBackgroundPreferenceSetPrefKey,
        );
    final bandwidthRaw = prefs.getInt(_uploadBandwidthLimitPrefKey);

    final storageDisplay =
        _parseStorageDisplayMode(displayRaw) ?? _StorageDisplayMode.amount;
    final storageLocation = switch (locationRaw?.trim().toLowerCase()) {
      'card' => _StorageCapacityLocation.summaryCard,
      'header' => _StorageCapacityLocation.header,
      _ => _StorageCapacityLocation.hidden,
    };
    final tileDensity = _WorkspaceTileDensity.fromStorageKey(tileDensityRaw);
    final folderPlacement = _WorkspaceFolderPlacement.fromStorageKey(
      folderPlacementRaw,
    );
    final scanFrequency = _BackupScanFrequency.fromStorageKey(scanRaw);
    final backgroundBackupEnabled = backgroundBackupEnabledRaw ?? true;
    final backgroundBackupPreferenceSet =
        backgroundBackupPreferenceSetRaw == true;
    final bandwidthLimit = bandwidthRaw != null && bandwidthRaw > 0
        ? bandwidthRaw
        : null;
    final offlineDirectoryPath = () {
      if (offlineDirectoryRaw == null) {
        return null;
      }
      final trimmed = offlineDirectoryRaw.trim();
      if (kDebugMode) {
        debugPrint(
          '[ENCRYPTION] Loaded passphraseRequired: $passphraseEnabled',
        );
      }
      return trimmed.isEmpty ? null : trimmed;
    }();

    var recoveredOfflineFilesPayload = false;
    final offlineFiles = <String, _OfflineFileInfo>{};
    if (offlineRaw != null) {
      try {
        final decoded = jsonDecode(offlineRaw) as List<dynamic>;
        for (final entry in decoded) {
          final map = Map<String, dynamic>.from(entry);
          final info = _OfflineFileInfo.fromJson(map);
          offlineFiles[info.objectKey] = info;
        }
      } catch (error) {
        recoveredOfflineFilesPayload = true;
        await _writePrivateCachePreference(
          prefs,
          baseKey: _offlineFilesPrefKey,
          namespace: LocalPrivateCacheCodec.offlineFilesNamespace,
          value: null,
        );
        BackgroundBackupRunner.logFailure(
          'privacy',
          'offline_cache_decode',
          error,
        );
      }
    }

    final backupFolders = <String, _BackupFolderConfig>{};
    if (backupRaw != null) {
      try {
        final decoded = jsonDecode(backupRaw) as List<dynamic>;
        for (final entry in decoded) {
          final config = _BackupFolderConfig.fromJson(
            Map<String, dynamic>.from(entry),
          );
          backupFolders[config.localPath] = config;
        }
      } catch (error) {
        BackgroundBackupRunner.logFailure(
          'privacy',
          'backup_config_decode',
          error,
        );
      }
    }

    final nestedFingerprints = <String, Map<String, _BackupFileFingerprint>>{};
    if (backupSignatureRaw != null) {
      try {
        final decoded = jsonDecode(backupSignatureRaw);
        final configsPayload = decoded is Map ? decoded['configs'] : null;
        if (configsPayload is List) {
          for (final entry in configsPayload) {
            if (entry is! Map) {
              continue;
            }
            final rawPath = (entry['path'] as String?) ?? '';
            final normalizedConfig = _normalizedLocalPath(rawPath);
            if (normalizedConfig.isEmpty) {
              continue;
            }
            final bucket = nestedFingerprints.putIfAbsent(
              normalizedConfig,
              () => <String, _BackupFileFingerprint>{},
            );
            final files = entry['files'];
            if (files is List) {
              for (final file in files) {
                if (file is Map) {
                  final fingerprint = _BackupFileFingerprint.fromJson(
                    Map<String, dynamic>.from(file),
                  );
                  final normalizedPath = _normalizedLocalPath(
                    fingerprint.localPath,
                  );
                  bucket[normalizedPath] = fingerprint.copyWith(
                    localPath: normalizedPath,
                  );
                }
              }
            }
          }
          final orphanPayload = decoded is Map ? decoded['orphans'] : null;
          if (orphanPayload is List) {
            final orphanBucket = nestedFingerprints.putIfAbsent(
              _backupFingerprintOrphanBucket,
              () => <String, _BackupFileFingerprint>{},
            );
            for (final entry in orphanPayload) {
              if (entry is Map) {
                final fingerprint = _BackupFileFingerprint.fromJson(
                  Map<String, dynamic>.from(entry),
                );
                final normalizedPath = _normalizedLocalPath(
                  fingerprint.localPath,
                );
                orphanBucket[normalizedPath] = fingerprint.copyWith(
                  localPath: normalizedPath,
                );
              }
            }
          }
        } else {
          final flatFingerprints = <String, _BackupFileFingerprint>{};
          if (decoded is List) {
            for (final entry in decoded) {
              if (entry is Map) {
                final fingerprint = _BackupFileFingerprint.fromJson(
                  Map<String, dynamic>.from(entry),
                );
                final normalizedPath = _normalizedLocalPath(
                  fingerprint.localPath,
                );
                flatFingerprints[normalizedPath] = fingerprint.copyWith(
                  localPath: normalizedPath,
                );
              }
            }
          } else if (decoded is Map) {
            decoded.forEach((_, value) {
              if (value is Map) {
                final fingerprint = _BackupFileFingerprint.fromJson(
                  Map<String, dynamic>.from(value),
                );
                final normalizedPath = _normalizedLocalPath(
                  fingerprint.localPath,
                );
                flatFingerprints[normalizedPath] = fingerprint.copyWith(
                  localPath: normalizedPath,
                );
              }
            });
          }

          final configPaths = backupFolders.values
              .map((config) => _normalizedLocalPath(config.localPath))
              .where((path) => path.isNotEmpty)
              .toList();

          for (final entry in flatFingerprints.entries) {
            final path = entry.key;
            final fingerprint = entry.value;
            var assigned = false;
            for (final configPath in configPaths) {
              if (path == configPath ||
                  path.startsWith('$configPath${p.separator}')) {
                final bucket = nestedFingerprints.putIfAbsent(
                  configPath,
                  () => <String, _BackupFileFingerprint>{},
                );
                bucket[path] = fingerprint;
                assigned = true;
                break;
              }
            }
            if (!assigned) {
              final bucket = nestedFingerprints.putIfAbsent(
                _backupFingerprintOrphanBucket,
                () => <String, _BackupFileFingerprint>{},
              );
              bucket[path] = fingerprint;
            }
          }
        }
      } catch (error) {
        BackgroundBackupRunner.logFailure(
          'privacy',
          'backup_fingerprint_decode',
          error,
        );
      }
    }

    for (final config in backupFolders.values) {
      final normalized = _normalizedLocalPath(config.localPath);
      if (normalized.isEmpty) {
        continue;
      }
      nestedFingerprints.putIfAbsent(
        normalized,
        () => <String, _BackupFileFingerprint>{},
      );
    }

    var recoveredOfflineFoldersPayload = false;
    final offlineFolders = <String, _OfflineFolderConfig>{};
    if (offlineFolderRaw != null) {
      try {
        final decoded = jsonDecode(offlineFolderRaw) as List<dynamic>;
        for (final entry in decoded) {
          final config = _OfflineFolderConfig.fromJson(
            Map<String, dynamic>.from(entry),
          );
          offlineFolders[config.folderKey] = config;
        }
      } catch (_) {
        recoveredOfflineFoldersPayload = true;
        await _writePrivateCachePreference(
          prefs,
          baseKey: _offlineFoldersPrefKey,
          namespace: LocalPrivateCacheCodec.offlineFoldersNamespace,
          value: null,
        );
        if (kDebugMode) {
          debugPrint('Encrypted offline-folder settings were unreadable.');
        }
      }
    }

    _backupFingerprints
      ..clear()
      ..addAll(nestedFingerprints);

    final knownBackupIds = backupFolders.values
        .map(_backupFolderIdForDisplay)
        .toSet();

    _backupScanFrequency = scanFrequency;

    if (!mounted) {
      _knownBackupFolderIds
        ..clear()
        ..addAll(knownBackupIds);
      return;
    }

    setState(() {
      _prefs = prefs;
      _storageDisplay = storageDisplay;
      _passphraseRequired = passphraseEnabled;
      _offlineFiles
        ..clear()
        ..addAll(offlineFiles);
      _backupFolders
        ..clear()
        ..addAll(backupFolders);
      _offlineFolders
        ..clear()
        ..addAll(offlineFolders);
      _storageLocation = storageLocation;
      _tileDensity = tileDensity;
      _folderPlacement = folderPlacement;
      _backupScanFrequency = scanFrequency;
      _backgroundBackupEnabled = backgroundBackupEnabled;
      _backgroundBackupPreferenceSet = backgroundBackupPreferenceSet;
      _knownBackupFolderIds
        ..clear()
        ..addAll(knownBackupIds);
      _uploadBandwidthLimitBytesPerSecond = bandwidthLimit;
      _bandwidthTokens = 0;
      _bandwidthLastTokenTime = null;
      _offlineDirectoryPath = offlineDirectoryPath;
      _businessReconciliationCheckpointKeys
        ..clear()
        ..addAll(
          reconciliationCheckpointLoad.checkpoints.map(
            (checkpoint) => checkpoint.workspaceKey,
          ),
        );
      _businessReconciliationCacheLocked =
          reconciliationCheckpointLoad.temporarilyUnavailable;
      if (reconciliationCheckpointLoad.discardedCorruptValue) {
        _businessFileAccessStatus =
            'Unreadable local reconciliation progress was removed. '
            'Encrypted cloud data was not changed.';
      } else if (reconciliationCheckpointLoad.temporarilyUnavailable) {
        _businessFileAccessStatus =
            'Encrypted reconciliation progress is waiting for the device '
            'credential store.';
      }
      if (offlineDirectoryPath != null) {
        _offlineDirectoryWarningShown = false;
      }
    });
    final offlineCacheReads = <LocalPrivateCachePreferenceRead>[
      offlineFilesCacheRead,
      offlineFoldersCacheRead,
      offlineDirectoryCacheRead,
    ];
    final offlineCacheUnavailable = offlineCacheReads.any(
      (read) => read.temporarilyUnavailable,
    );
    final offlineCacheRecovered =
        offlineCacheReads.any((read) => read.discardedCorruptValue) ||
        recoveredOfflineFilesPayload ||
        recoveredOfflineFoldersPayload;
    final privateCacheNotice = !transferJournal.storageAvailable
        ? 'Transfers are securely paused because the device keychain is '
              'locked. Unlock the device and restart the app.'
        : transferJournal.recoveredCorruptState
        ? 'Interrupted transfer history could not be authenticated and was '
              'rebuilt. Your stored cloud files were not deleted.'
        : offlineCacheUnavailable
        ? 'Offline-file settings are securely locked right now. Your local '
              'encrypted copies were not changed.'
        : offlineCacheRecovered
        ? 'Offline-file mappings could not be authenticated and were reset. '
              'Your cloud files were not deleted.'
        : backupCacheRead.temporarilyUnavailable
        ? 'Backup settings are securely locked right now. Restart the app or '
              'unlock the device keychain, then try again.'
        : backupCacheRead.discardedCorruptValue
        ? 'Local backup settings could not be authenticated and were reset. '
              'Choose your backup folders again.'
        : backupSignatureCacheRead.temporarilyUnavailable
        ? 'Backup comparison history is securely locked right now. Your cloud '
              'files were not changed.'
        : backupSignatureCacheRead.discardedCorruptValue
        ? 'Backup comparison history was rebuilt safely. Your cloud files '
              'were not deleted.'
        : null;
    if (privateCacheNotice != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _showMessage(privateCacheNotice);
      });
    }
    if (_hasOfflineSyncTargets) {
      _scheduleOfflineSync();
    }
  }

  void _subscribeToUserProfile() {
    _userStreamReconnectTimer?.cancel();
    _userSubscription?.cancel();

    final docRef = widget.firestore.collection('users').doc(widget.user.uid);
    _userSubscription = docRef.snapshots().listen(
      (snapshot) {
        _userStreamReconnectAttempts = 0;
        _runOnPlatformThread(() async {
          if (mounted) {
            _updateUserProfileState(snapshot.data());
          }
        });
      },
      onError: (_, __) {
        Future.microtask(() {
          if (kDebugMode) {
            debugPrint('The account profile stream was interrupted.');
          }
        });
        _scheduleUserStreamReconnect();
      },
    );
  }

  Future<void> _primeUserProfileSnapshot() async {
    try {
      final snapshot = await widget.firestore
          .collection('users')
          .doc(widget.user.uid)
          .get()
          .timeout(const Duration(seconds: 5));
      if (!mounted) {
        return;
      }
      _updateUserProfileState(snapshot.data());
    } catch (_) {
      if (kDebugMode) {
        debugPrint('The initial account profile refresh was unavailable.');
      }
    }
  }

  Duration _streamReconnectDelay(int attempts) {
    final seconds = min(30, max(2, 1 << min(attempts, 5)));
    return Duration(seconds: seconds);
  }

  bool _shouldShowStreamErrorNotice(DateTime? lastNoticeAt) {
    if (lastNoticeAt == null) {
      return true;
    }
    return DateTime.now().difference(lastNoticeAt) > const Duration(minutes: 1);
  }

  void _scheduleUserStreamReconnect() {
    if (!mounted ||
        _sessionInvalidated ||
        _userStreamReconnectTimer?.isActive == true) {
      return;
    }
    final delay = _streamReconnectDelay(_userStreamReconnectAttempts++);
    _userStreamReconnectTimer = Timer(delay, () {
      _userStreamReconnectTimer = null;
      if (mounted) {
        _subscribeToUserProfile();
      }
    });
  }

  bool _hasCurrentLegalAcceptance(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) {
      return true;
    }
    bool hasAcceptedField(String key) {
      final value = data[key];
      if (value is Timestamp) {
        return true;
      }
      if (value is DateTime) {
        return true;
      }
      if (value is String) {
        return value.trim().isNotEmpty;
      }
      return false;
    }

    return _trimmedStringValue(data['legalVersion']) ==
            LegalDocuments.legalVersion &&
        hasAcceptedField('termsAcceptedAt') &&
        hasAcceptedField('privacyAcknowledgedAt') &&
        hasAcceptedField('acceptableUseAcceptedAt') &&
        hasAcceptedField('cancellationRefundAcknowledgedAt') &&
        hasAcceptedField('dataRetentionAcknowledgedAt') &&
        hasAcceptedField('subprocessorsAcknowledgedAt');
  }

  void _scheduleLegalAcceptancePromptIfNeeded(Map<String, dynamic>? data) {
    final current = _hasCurrentLegalAcceptance(data);
    final optIn = data?['productUpdatesOptIn'] == true;
    if (mounted &&
        (_legalAcceptanceCurrent != current || _productUpdatesOptIn != optIn)) {
      setState(() {
        _legalAcceptanceCurrent = current;
        _productUpdatesOptIn = optIn;
      });
    } else {
      _legalAcceptanceCurrent = current;
      _productUpdatesOptIn = optIn;
    }

    if (current ||
        _legalAcceptancePromptScheduled ||
        _legalAcceptancePromptVisible ||
        !mounted) {
      return;
    }

    _legalAcceptancePromptScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _legalAcceptancePromptScheduled = false;
      if (!mounted ||
          _legalAcceptancePromptVisible ||
          _legalAcceptanceCurrent) {
        return;
      }
      unawaited(_showLegalAcceptancePrompt());
    });
  }

  Future<void> _showLegalAcceptancePrompt() async {
    if (!mounted || _legalAcceptancePromptVisible) {
      return;
    }

    _legalAcceptancePromptVisible = true;
    var acceptedTermsAndUse = false;
    var acknowledgedPrivacyAndPolicies = false;
    var productUpdatesOptIn = _productUpdatesOptIn;
    var busy = false;
    String? errorMessage;

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return PopScope(
            canPop: false,
            child: StatefulBuilder(
              builder: (context, setDialogState) {
                Future<void> accept() async {
                  if (busy ||
                      !acceptedTermsAndUse ||
                      !acknowledgedPrivacyAndPolicies) {
                    return;
                  }
                  setDialogState(() {
                    busy = true;
                    errorMessage = null;
                  });
                  final acceptedAt = DateTime.now().toUtc().toIso8601String();
                  final update = <String, dynamic>{
                    'legalVersion': LegalDocuments.legalVersion,
                    'termsAcceptedAt': acceptedAt,
                    'privacyAcknowledgedAt': acceptedAt,
                    'acceptableUseAcceptedAt': acceptedAt,
                    'cancellationRefundAcknowledgedAt': acceptedAt,
                    'dataRetentionAcknowledgedAt': acceptedAt,
                    'subprocessorsAcknowledgedAt': acceptedAt,
                    'legalAcceptanceSource': 'reacceptance',
                    'productUpdatesOptIn': productUpdatesOptIn,
                    'productUpdatesSource': 'legal_prompt',
                  };
                  if (productUpdatesOptIn) {
                    update['productUpdatesOptInAt'] = acceptedAt;
                  } else {
                    update['productUpdatesOptInAt'] = FieldValue.delete();
                  }
                  try {
                    await widget.firestore
                        .collection('users')
                        .doc(widget.user.uid)
                        .update(update);
                    if (!dialogContext.mounted) {
                      return;
                    }
                    setState(() {
                      _legalAcceptanceCurrent = true;
                      _productUpdatesOptIn = productUpdatesOptIn;
                    });
                    Navigator.of(dialogContext).pop();
                    _showMessage('Legal documents accepted.');
                  } catch (_) {
                    if (kDebugMode) {
                      debugPrint('Legal acceptance could not be saved.');
                    }
                    if (dialogContext.mounted) {
                      setDialogState(() {
                        busy = false;
                        errorMessage =
                            'Could not save acceptance. Check your connection and try again.';
                      });
                    }
                  }
                }

                void openDocument(LegalDocument document) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) =>
                          LegalDocumentPage(document: document),
                    ),
                  );
                }

                return AlertDialog(
                  title: const Text('Review updated terms'),
                  content: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'RonikCloud needs your acceptance of the current Core Pack before the workspace can continue.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 12),
                          _LegalAcceptanceChecklist(
                            acceptedTermsAndUse: acceptedTermsAndUse,
                            acknowledgedPrivacyAndPolicies:
                                acknowledgedPrivacyAndPolicies,
                            productUpdatesOptIn: productUpdatesOptIn,
                            enabled: !busy,
                            onAcceptedTermsAndUseChanged: (value) {
                              setDialogState(() {
                                acceptedTermsAndUse = value;
                              });
                            },
                            onAcknowledgedPrivacyAndPoliciesChanged: (value) {
                              setDialogState(() {
                                acknowledgedPrivacyAndPolicies = value;
                              });
                            },
                            onProductUpdatesOptInChanged: (value) {
                              setDialogState(() {
                                productUpdatesOptIn = value;
                              });
                            },
                            onOpenDocument: openDocument,
                          ),
                          if (errorMessage != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              errorMessage!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    FilledButton.icon(
                      onPressed:
                          busy ||
                              !acceptedTermsAndUse ||
                              !acknowledgedPrivacyAndPolicies
                          ? null
                          : accept,
                      icon: busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_circle_outline),
                      label: Text(busy ? 'Saving' : 'Accept and continue'),
                    ),
                  ],
                );
              },
            ),
          );
        },
      );
    } finally {
      _legalAcceptancePromptVisible = false;
    }
  }

  Future<void> _updateProductUpdatesOptIn(bool value) async {
    if (!await _ensureAuthenticated(interactive: true)) {
      return;
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final update = <String, dynamic>{
      'productUpdatesOptIn': value,
      'productUpdatesSource': 'settings',
    };
    if (value) {
      update['productUpdatesOptInAt'] = now;
    } else {
      update['productUpdatesOptInAt'] = FieldValue.delete();
    }
    final previous = _productUpdatesOptIn;
    setState(() {
      _productUpdatesOptIn = value;
    });
    try {
      await widget.firestore
          .collection('users')
          .doc(widget.user.uid)
          .update(update);
      _showMessage(
        value ? 'Product updates enabled.' : 'Product updates disabled.',
      );
    } catch (_) {
      if (kDebugMode) {
        debugPrint('The product-update preference could not be saved.');
      }
      if (mounted) {
        setState(() {
          _productUpdatesOptIn = previous;
        });
      }
      _showMessage('Could not save product update preference.');
    }
  }

  void _scheduleFilesStreamReconnect() {
    if (!mounted ||
        _sessionInvalidated ||
        _filesStreamReconnectTimer?.isActive == true) {
      return;
    }
    final delay = _streamReconnectDelay(_filesStreamReconnectAttempts++);
    _filesStreamReconnectTimer = Timer(delay, () {
      _filesStreamReconnectTimer = null;
      if (mounted) {
        _subscribeToFiles();
      }
    });
  }

  void _scheduleFoldersStreamReconnect() {
    if (!mounted ||
        _sessionInvalidated ||
        _foldersStreamReconnectTimer?.isActive == true) {
      return;
    }
    final delay = _streamReconnectDelay(_foldersStreamReconnectAttempts++);
    _foldersStreamReconnectTimer = Timer(delay, () {
      _foldersStreamReconnectTimer = null;
      if (mounted) {
        _subscribeToFolders();
      }
    });
  }

  Map<String, Object?> _profileMap(Object? value) {
    if (value is Map<String, Object?>) {
      return value;
    }
    if (value is Map) {
      return Map<String, Object?>.fromEntries(
        value.entries.map(
          (entry) => MapEntry(entry.key.toString(), entry.value),
        ),
      );
    }
    return const <String, Object?>{};
  }

  List<String> _profileStringList(Object? value) {
    if (value is! Iterable) {
      return const <String>[];
    }
    return value
        .map((item) => item?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  BusinessStoragePermissions _profileBusinessStoragePermissions(Object? value) {
    return BusinessStoragePermissions.fromMap(_profileMap(value));
  }

  bool get _hasActiveCompanyMembership =>
      _companyId != null &&
      _companyId!.trim().isNotEmpty &&
      _companyMembershipStatus == 'active';

  bool get _canReadCompanyStorage =>
      _hasActiveCompanyMembership && _companyStoragePermissions.canDownload;

  bool get _canWriteCompanyStorage =>
      _hasActiveCompanyMembership && _companyStoragePermissions.canUpload;

  bool get _canShareCompanyStorage =>
      _canReadCompanyStorage && _companyStoragePermissions.canShare;

  bool get _canUseCompanyStorage =>
      _hasActiveCompanyMembership && _companyStoragePermissions.canUseStorage;

  bool get _activeStorageIsBusiness =>
      _activeStorageScope == 'company_private' ||
      _activeStorageScope == 'company_shared' ||
      _activeStorageScope == 'group';

  bool _isBusinessStorageScope(String storageScope) {
    final normalized = storageScope.trim().toLowerCase();
    return normalized == 'company_private' ||
        normalized == 'company_shared' ||
        normalized == 'group';
  }

  bool _canReadStorageScope(String storageScope) =>
      !_isBusinessStorageScope(storageScope) || _canReadCompanyStorage;

  bool _canWriteStorageScope(String storageScope) =>
      !_isBusinessStorageScope(storageScope) || _canWriteCompanyStorage;

  bool _canShareStorageScope(String storageScope) =>
      !_isBusinessStorageScope(storageScope) || _canShareCompanyStorage;

  bool get _canReadActiveStorage =>
      !_activeStorageIsBusiness || _canReadCompanyStorage;

  bool get _canWriteActiveStorage =>
      !_activeStorageIsBusiness || _canWriteCompanyStorage;

  bool get _canShareFromActiveStorage =>
      !_activeStorageIsBusiness || _canShareCompanyStorage;

  bool get _companyPrivateStorageAllowed {
    if (!_canUseCompanyStorage) {
      return false;
    }
    final override = _companyStorageOverride.privateStorageEnabled;
    if (override != null) {
      return override;
    }
    return _companyStoragePolicy.privateStorageEnabledByDefault;
  }

  bool get _companySharedStorageAllowed {
    if (!_canUseCompanyStorage || !_companyStoragePolicy.sharedStorageEnabled) {
      return false;
    }
    return _companyAccessScopes.contains('company_workspace') ||
        _companyAccessScopes.contains('shared_folders');
  }

  List<CompanyStorageSpace> get _storageSpaces {
    final spaces = <CompanyStorageSpace>[
      if (!widget.businessMode)
        const CompanyStorageSpace(
          id: 'personal',
          scope: 'personal',
          label: 'My Drive',
        ),
    ];
    final companyId = _companyId?.trim();
    if (companyId == null || companyId.isEmpty || !_canUseCompanyStorage) {
      if (widget.businessMode) {
        return const <CompanyStorageSpace>[
          CompanyStorageSpace(
            id: 'company_pending',
            scope: 'company_shared',
            label: 'Company files',
            enabled: false,
          ),
        ];
      }
      return spaces;
    }
    if (_companyPrivateStorageAllowed) {
      spaces.add(
        CompanyStorageSpace(
          id: 'company_private',
          scope: 'company_private',
          label: 'My Company Private',
          companyId: companyId,
          quotaBytes:
              _companyStorageOverride.privateQuotaBytes ??
              _companyStoragePolicy.defaultPrivateQuotaBytes,
        ),
      );
    }
    if (_companySharedStorageAllowed) {
      spaces.add(
        CompanyStorageSpace(
          id: 'company_shared',
          scope: 'company_shared',
          label: businessCompanyStorageLabel(widget.businessCompanyLabel),
          companyId: companyId,
        ),
      );
    }
    final storageEnabledGroupIds =
        _companyGroupStorageEnabledIds ?? _companyGroupIds;
    for (var index = 0; index < storageEnabledGroupIds.length; index += 1) {
      final groupId = storageEnabledGroupIds[index];
      final groupLabel = widget.businessGroupLabels[groupId]?.trim();
      spaces.add(
        CompanyStorageSpace(
          id: 'group:$groupId',
          scope: 'group',
          label: businessGroupStorageLabel(
            groupLabel,
            protectedOrdinal: index + 1,
          ),
          companyId: companyId,
          groupId: groupId,
        ),
      );
    }
    if (spaces.isEmpty) {
      return <CompanyStorageSpace>[
        CompanyStorageSpace(
          id: 'company_unavailable',
          scope: 'company_unavailable',
          label: 'No company storage enabled',
          companyId: companyId,
          enabled: false,
        ),
      ];
    }
    return spaces;
  }

  CompanyStorageSpace get _activeStorageSpace {
    final spaces = _storageSpaces;
    return spaces.firstWhere(
      (space) =>
          space.scope == _activeStorageScope &&
          (space.scope != 'group' || space.groupId == _activeStorageGroupId),
      orElse: () => spaces.first,
    );
  }

  String get _activeStorageSpaceLabel => _activeStorageSpace.label;

  void _normalizeActiveStorageSpace() {
    final spaces = _storageSpaces;
    final activeStillValid = spaces.any(
      (space) =>
          space.scope == _activeStorageScope &&
          (space.scope != 'group' || space.groupId == _activeStorageGroupId),
    );
    if (activeStillValid) {
      return;
    }
    final fallback = spaces.first;
    _activeStorageScope = fallback.scope;
    _activeStorageGroupId = fallback.groupId;
    _activeFolderId = null;
    _activeFolderLabel = null;
  }

  void _selectStorageSpace(CompanyStorageSpace space) {
    if (_refreshingBusinessFileAccess) {
      _showMessage(
        'Wait for encrypted member access to finish refreshing before '
        'switching spaces.',
      );
      return;
    }
    if (_activeStorageScope == space.scope &&
        _activeStorageGroupId == space.groupId) {
      return;
    }
    setState(() {
      _activeStorageScope = space.scope;
      _activeStorageGroupId = space.groupId;
      _activeFolderId = null;
      _activeFolderLabel = null;
      _selectedFileIds.clear();
      _selectedFolderIds.clear();
      _isSelectionMode = false;
      _businessFileAccessStatus = null;
    });
  }

  void _tryApplyRequestedBusinessReconciliationLocation() {
    if (!mounted || _refreshingBusinessFileAccess) {
      return;
    }
    final location = widget.requestedBusinessReconciliationLocation;
    final revision = widget.businessReconciliationRequestRevision;
    if (location == null ||
        revision == _appliedBusinessReconciliationRequestRevision) {
      return;
    }
    final companyId = _companyId?.trim();
    if (companyId == null ||
        companyId.isEmpty ||
        companyId != location.companyId) {
      return;
    }
    CompanyStorageSpace? requestedSpace;
    for (final space in _storageSpaces) {
      if (space.enabled &&
          space.scope == location.storageScope &&
          (space.scope != 'group' || space.groupId == location.groupId)) {
        requestedSpace = space;
        break;
      }
    }
    if (requestedSpace == null) {
      return;
    }
    setState(() {
      _activeStorageScope = requestedSpace!.scope;
      _activeStorageGroupId = requestedSpace.groupId;
      _activeFolderId = null;
      _activeFolderLabel = null;
      _selectedFileIds.clear();
      _selectedFolderIds.clear();
      _isSelectionMode = false;
      _businessFileAccessStatus =
          'Access changed in this space. Review the current members, then '
          'start encrypted reconciliation when this trusted device is ready.';
      _appliedBusinessReconciliationRequestRevision = revision;
    });
  }

  bool _storageScopeMatchesActive({
    required String storageScope,
    String? companyId,
    List<String> groupIds = const <String>[],
  }) {
    if (_activeStorageScope == 'personal') {
      return storageScope == 'personal';
    }
    final activeCompanyId = _companyId?.trim();
    if (activeCompanyId == null || activeCompanyId.isEmpty) {
      return false;
    }
    if (companyId != activeCompanyId || storageScope != _activeStorageScope) {
      return false;
    }
    if (storageScope != 'group') {
      return true;
    }
    final activeGroupId = _activeStorageGroupId;
    return activeGroupId != null && groupIds.contains(activeGroupId);
  }

  bool _folderMatchesActiveStorageSpace(_DriveFolder folder) {
    return _storageScopeMatchesActive(
      storageScope: folder.storageScope,
      companyId: folder.companyId,
      groupIds: folder.groupIds,
    );
  }

  bool _fileMatchesActiveStorageSpace(_DriveFile file) {
    return _storageScopeMatchesActive(
      storageScope: file.storageScope,
      companyId: file.companyId,
      groupIds: file.groupIds,
    );
  }

  bool get _activeStorageUsesMemberEnvelopes =>
      _activeStorageScope == 'company_shared' || _activeStorageScope == 'group';

  Map<String, dynamic> _metadataForActiveStorageSpace() {
    final scope = _activeStorageScope;
    if (scope == 'personal') {
      return const <String, dynamic>{};
    }
    final companyId = _companyId?.trim();
    if (companyId == null || companyId.isEmpty) {
      return const <String, dynamic>{};
    }
    final metadata = <String, dynamic>{
      'storageScope': scope,
      'companyId': companyId,
      'ownerUid': widget.user.uid,
      'createdByUid': widget.user.uid,
      'allowedUids': <String>[widget.user.uid],
    };
    if (scope == 'group' && _activeStorageGroupId != null) {
      metadata['groupIds'] = <String>[_activeStorageGroupId!];
    }
    return metadata;
  }

  void _resubscribeCompanyStorageStreams() {
    final streamGeneration = ++_companyStorageStreamGeneration;
    _companyFilesSubscription?.cancel();
    _companyFilesSubscription = null;
    _initializedFileSnapshotSources.remove(
      WorkspaceSnapshotSource.assignedBusiness,
    );
    _companyFoldersSubscription?.cancel();
    _companyFoldersSubscription = null;

    if (!_canReadCompanyStorage) {
      _removeCompanyStorageDocumentsFromLocalState();
      return;
    }

    final filesQuery = widget.firestore
        .collection('files')
        .where('allowedUids', arrayContains: widget.user.uid);
    _companyFilesSubscription = filesQuery.snapshots().listen(
      (snapshot) {
        _filesStreamReconnectAttempts = 0;
        _enqueueFileSnapshotProcessing(
          snapshot,
          source: WorkspaceSnapshotSource.assignedBusiness,
          companyStreamGeneration: streamGeneration,
        );
      },
      onError: (_) {
        _runOnPlatformThread(() async {
          if (kDebugMode) {
            debugPrint('Assigned company file refresh was unavailable.');
          }
          if (!mounted) {
            return;
          }
          if (_shouldShowStreamErrorNotice(_lastFilesStreamErrorNoticeAt)) {
            _lastFilesStreamErrorNoticeAt = DateTime.now();
            _showMessage(
              'Assigned company files could not be refreshed. The last '
              'verified file view remains available.',
            );
          }
        });
      },
    );

    final foldersQuery = widget.firestore
        .collection('folders')
        .where('allowedUids', arrayContains: widget.user.uid);
    _companyFoldersSubscription = foldersQuery.snapshots().listen(
      (snapshot) {
        _foldersStreamReconnectAttempts = 0;
        _enqueueFolderSnapshotProcessing(
          snapshot,
          source: WorkspaceSnapshotSource.assignedBusiness,
          companyStreamGeneration: streamGeneration,
        );
      },
      onError: (_) {
        _runOnPlatformThread(() async {
          if (kDebugMode) {
            debugPrint('Assigned company folder refresh was unavailable.');
          }
          if (!mounted) {
            return;
          }
          if (_shouldShowStreamErrorNotice(_lastFoldersStreamErrorNoticeAt)) {
            _lastFoldersStreamErrorNoticeAt = DateTime.now();
            _showMessage(
              'Assigned company folders could not be refreshed. The last verified folder view remains available.',
            );
          }
        });
      },
    );
  }

  void _removeCompanyStorageDocumentsFromLocalState() {
    _fileCacheRows.clear();_folderCacheRows.clear();
    for(final cache in _metadataShardCaches.values) {
      cache.invalidate();
      unawaited(cache.clear().catchError((Object _,StackTrace __) {}));
    }

    _fileSnapshotSources.replace(
      WorkspaceSnapshotSource.assignedBusiness,
      const <_DriveFile>[],
      idOf: (file) => file.id,
    );
    _initializedFileSnapshotSources.remove(
      WorkspaceSnapshotSource.assignedBusiness,
    );
    _folderSnapshotSources.replace(
      WorkspaceSnapshotSource.assignedBusiness,
      const <_DriveFolder>[],
      idOf: (folder) => folder.id,
    );

    final remainingRetainedFiles = _fileSnapshotSources.mergedItems;
    final remainingFiles =
        remainingRetainedFiles
            .where((file) => file.isActive)
            .toList(growable: true)
          ..sort(_compareDriveFiles);
    final remainingFilesById = <String, _DriveFile>{
      for (final file in remainingFiles) file.id: file,
    };
    final remainingFileUsage = remainingRetainedFiles
        .fold<int>(0, (total, file) => total + file.size)
        .toDouble();
    final remainingFolders = _folderSnapshotSources.mergedItems.toList()
      ..sort((a, b) {
        final aActivity = a.activity ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bActivity = b.activity ?? DateTime.fromMillisecondsSinceEpoch(0);
        final activityComparison = bActivity.compareTo(aActivity);
        return activityComparison != 0
            ? activityComparison
            : a.displayName.toLowerCase().compareTo(
                b.displayName.toLowerCase(),
              );
      });
    final remainingFolderIds = remainingFolders
        .map((folder) => folder.id)
        .toSet();
    final totals = _calculateUsageTotals(computedUsage: remainingFileUsage);

    void applyRevokedState() {
      _files
        ..clear()
        ..addAll(remainingFiles);
      _filesById
        ..clear()
        ..addAll(remainingFilesById);
      _folders
        ..clear()
        ..addAll(remainingFolders);
      _fileUsageBytes = remainingFileUsage;
      _usedBytes = totals.used;
      _totalBytes = totals.total;
      if (widget.businessMode) {
        _activeStorageScope = 'company_shared';
        _activeStorageGroupId = null;
      } else {
        _activeStorageScope = 'personal';
        _activeStorageGroupId = null;
      }
      _activeFolderId = null;
      _activeFolderLabel = null;
      _selectedFileIds.clear();
      _selectedFolderIds.clear();
      _isSelectionMode = false;
      _knownBackupFolderIds
        ..clear()
        ..addAll(remainingFolderIds);
    }

    if (mounted) {
      setState(applyRevokedState);
    } else {
      applyRevokedState();
    }
    _resolvedFileNameCache.removeWhere(
      (id, _) => !remainingFilesById.containsKey(id),
    );
    _resolvedFolderNameCache.removeWhere(
      (id, _) => !remainingFolderIds.contains(id),
    );
    _scheduleCachedFilesPersist();
    _scheduleCachedFoldersPersist();
    _scheduleOfflineSync();
  }

  void _updateUserProfileState(Map<String, dynamic>? data) {
    _supportProfile = data;
    final profileRequiresTwoFactor = data?['twoFactorEnabled'] == true;
    _scheduleLegalAcceptancePromptIfNeeded(data);

    // Auto-clear payment processing state if subscription becomes active
    if (paymentProcessingNotifier.value) {
      final status = data?['subscriptionStatus'] as String?;
      if (status == 'active') {
        paymentProcessingNotifier.value = false;
        if (mounted) {
          _showMessage(
            'Payment processed successfully! Your plan is now active.',
          );
        }
      }
    }

    final usageBytes = _parseUsageBytes(data, 'usageBytes');
    final isFreeStorageAccount = data?['subscriptionStatus'] == 'free';
    final capacityInfo = _parseCapacityInfo(data, usageBytes: usageBytes);
    final limitBytes = capacityInfo.limitBytes;
    final hasLimit = capacityInfo.hasLimit;
    final planLabel = capacityInfo.label;
    final limitPending = capacityInfo.pending;
    final storageInventoryStatus = StorageInventoryStatus.fromProfile(data);

    String? trimmedString(String key) {
      final value = data?[key];
      if (value is! String) {
        return null;
      }
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    Uint8List? parsedSalt;
    final rawSalt = data?['encryptionSalt'];
    if (rawSalt is String) {
      final trimmedSalt = rawSalt.trim();
      if (trimmedSalt.isNotEmpty) {
        try {
          parsedSalt = Uint8List.fromList(base64Decode(trimmedSalt));
        } catch (_) {
          parsedSalt = null;
        }
      }
    }

    Uint8List? parsedSecureSalt;
    final rawSecureSalt = data?['secureEncryptionSalt'];
    if (rawSecureSalt is String) {
      final trimmedSalt = rawSecureSalt.trim();
      if (trimmedSalt.isNotEmpty) {
        try {
          parsedSecureSalt = Uint8List.fromList(base64Decode(trimmedSalt));
        } catch (_) {
          parsedSecureSalt = null;
        }
      }
    }

    final rawHash = data?['encryptionPasswordHash'];
    final normalizedHash = rawHash is String ? rawHash.trim() : null;
    final sanitizedHash = (normalizedHash == null || normalizedHash.isEmpty)
        ? null
        : normalizedHash;

    final previousSalt = _encryptionSalt;
    final previousSecureSalt = _secureEncryptionSalt;
    final previousHash = _encryptionPasswordHash;
    final saltChanged = !_bytesEqual(previousSalt, parsedSalt);
    final secureSaltChanged = !_bytesEqual(
      previousSecureSalt,
      parsedSecureSalt,
    );
    final hashChanged = previousHash != sanitizedHash;

    final totals = _calculateUsageTotals(
      profileUsage: usageBytes,
      limitBytes: limitBytes,
      hasLimit: hasLimit,
    );

    final storagePrefixCandidates = <String?>[
      trimmedString('storageHomePrefix'),
      trimmedString('storageRootPrefix'),
      trimmedString('storageFolderPrefix'),
    ];
    String? resolvedStoragePrefix;
    for (final candidate in storagePrefixCandidates) {
      final sanitized = sanitizeStorageHomePrefix(candidate);
      if (sanitized != null) {
        resolvedStoragePrefix = sanitized;
        break;
      }
    }
    resolvedStoragePrefix ??= storageHomePrefixForUid(widget.user.uid);
    final parsedCompanyId = trimmedString('companyId');
    final parsedCompanyMembershipStatus = trimmedString(
      'companyMembershipStatus',
    );
    final parsedCompanyAccessScopes = _profileStringList(
      data?['companyAccessScopes'],
    );
    final parsedCompanyGroupIds = _profileStringList(data?['companyGroupIds']);
    final parsedCompanyGroupStorageEnabledIds =
        data != null && data.containsKey('companyGroupStorageEnabledIds')
        ? _profileStringList(data['companyGroupStorageEnabledIds'])
        : null;
    final parsedCompanyStoragePermissions = _profileBusinessStoragePermissions(
      data?['companyPermissions'],
    );
    final parsedCompanyStorageOverride = CompanyMemberStorageOverride.fromMap(
      _profileMap(data?['companyStorageOverride']),
    );
    final parsedCompanyStoragePolicy = CompanyStoragePolicy.fromMap(
      _profileMap(data?['companyStoragePolicy']),
    );
    final displayPreference = (data?['storageUsageDisplay'] as String?)
        ?.trim()
        .toLowerCase();
    final remoteDisplay = _parseStorageDisplayMode(displayPreference);
    final displayChanged =
        remoteDisplay != null && remoteDisplay != _storageDisplay;
    final companyStreamAccessChanged =
        !_hasAppliedUserProfileState ||
        _companyId != parsedCompanyId ||
        _companyMembershipStatus != parsedCompanyMembershipStatus ||
        _companyStoragePermissions != parsedCompanyStoragePermissions ||
        !listEquals(_companyAccessScopes, parsedCompanyAccessScopes) ||
        !listEquals(_companyGroupIds, parsedCompanyGroupIds) ||
        !listEquals(
          _companyGroupStorageEnabledIds,
          parsedCompanyGroupStorageEnabledIds,
        );

    if (!mounted) {
      return;
    }

    final stateChanged =
        _isFreeStorageAccount != isFreeStorageAccount ||
        _profileRequiresTwoFactor != profileRequiresTwoFactor ||
        _storageLimitBytes != limitBytes ||
        _storageHasLimit != hasLimit ||
        _storagePlanLabel != planLabel ||
        _storageInventoryStatus != storageInventoryStatus ||
        _storageLimitPending != limitPending ||
        _totalBytes != totals.total ||
        _profileUsageBytes != usageBytes ||
        _usedBytes != totals.used ||
        _storageHomePrefix != resolvedStoragePrefix ||
        _companyId != parsedCompanyId ||
        _companyMembershipStatus != parsedCompanyMembershipStatus ||
        _companyStoragePermissions != parsedCompanyStoragePermissions ||
        !listEquals(_companyAccessScopes, parsedCompanyAccessScopes) ||
        !listEquals(_companyGroupIds, parsedCompanyGroupIds) ||
        !listEquals(
          _companyGroupStorageEnabledIds,
          parsedCompanyGroupStorageEnabledIds,
        ) ||
        _companyStoragePolicy.privateStorageEnabledByDefault !=
            parsedCompanyStoragePolicy.privateStorageEnabledByDefault ||
        _companyStoragePolicy.sharedStorageEnabled !=
            parsedCompanyStoragePolicy.sharedStorageEnabled ||
        _companyStoragePolicy.defaultPrivateQuotaBytes !=
            parsedCompanyStoragePolicy.defaultPrivateQuotaBytes ||
        _companyStorageOverride.privateStorageEnabled !=
            parsedCompanyStorageOverride.privateStorageEnabled ||
        _companyStorageOverride.privateQuotaBytes !=
            parsedCompanyStorageOverride.privateQuotaBytes ||
        saltChanged ||
        secureSaltChanged ||
        hashChanged ||
        displayChanged;

    if (stateChanged) {
      setState(() {
        _profileRequiresTwoFactor = profileRequiresTwoFactor;
        _isFreeStorageAccount = isFreeStorageAccount;
        _storageLimitBytes = limitBytes;
        _storageHasLimit = hasLimit;
        _storagePlanLabel = planLabel;
        _storageInventoryStatus = storageInventoryStatus;
        _storageLimitPending = limitPending;
        _totalBytes = totals.total;
        _profileUsageBytes = usageBytes;
        _usedBytes = totals.used;
        _storageHomePrefix = resolvedStoragePrefix;
        _companyId = parsedCompanyId;
        _companyMembershipStatus = parsedCompanyMembershipStatus;
        _companyStoragePermissions = parsedCompanyStoragePermissions;
        _companyAccessScopes = parsedCompanyAccessScopes;
        _companyGroupIds = parsedCompanyGroupIds;
        _companyGroupStorageEnabledIds = parsedCompanyGroupStorageEnabledIds;
        _companyStoragePolicy = parsedCompanyStoragePolicy;
        _companyStorageOverride = parsedCompanyStorageOverride;
        _normalizeActiveStorageSpace();

        if (displayChanged) {
          _storageDisplay = remoteDisplay;
        }
        if (saltChanged || hashChanged) {
          _activeMemoryPreview?.cancel();
          _cachedEncryptionKey = null;
          _resolvedFileNameCache.clear();
          _resolvedFolderNameCache.clear();
        }
        if (secureSaltChanged) {
          _activeMemoryPreview?.cancel();
          _cachedSecureEncryptionKey = null;
          _resolvedFileNameCache.clear();
        }

        _encryptionSalt = parsedSalt;
        _secureEncryptionSalt = parsedSecureSalt;
        _encryptionPasswordHash = sanitizedHash;
      });
    }

    if (companyStreamAccessChanged) {
      _activeMemoryPreview?.cancel();
      _businessEncryptionIdentity = null;
      _businessEncryptionIdentityRequest = null;
      _businessFileKeyCache.clear();
      _resolvedFileNameCache.clear();
      _resolvedFolderNameCache.clear();
      _thumbnailCache.clear();
      _thumbnailRequests.clear();
      _thumbnailRetryAfter.clear();
      _businessFileAccessStatus = null;
      if (_refreshingBusinessFileAccess) {
        _pauseBusinessReconciliationRequested = true;
      }
    }
    _hasAppliedUserProfileState = true;
    if (companyStreamAccessChanged) {
      _resubscribeCompanyStorageStreams();
    }
    if (_hasActiveCompanyMembership) {
      unawaited(_initializeBusinessEncryptionIfReady());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryApplyRequestedBusinessReconciliationLocation();
    });

    if (displayChanged) {
      unawaited(_persistDisplaySetting(syncRemote: false));
    }

    if ((saltChanged && parsedSalt != null) ||
        (secureSaltChanged && parsedSecureSalt != null)) {
      // Key material arrived; retry processing files to reveal decrypted names.
      unawaited(() async {
        await _restoreStandardEncryptionKeyIfAvailable();
        await _retryFileDecryption();
      }());
    }
  }

  Future<void> _retryFileDecryption() async {
    if (!mounted) {
      return;
    }
    final resolvedFiles = _files.isEmpty
        ? <_DriveFile>[]
        : await _maybeDecryptFileNames(_files);
    final resolvedFolders = _folders.isEmpty
        ? <_DriveFolder>[]
        : await _maybeDecryptFolderNames(_folders);
    resolvedFiles.sort(_compareDriveFiles);
    resolvedFolders.sort((a, b) {
      final aActivity = a.activity ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bActivity = b.activity ?? DateTime.fromMillisecondsSinceEpoch(0);
      final activityCompare = bActivity.compareTo(aActivity);
      return activityCompare != 0
          ? activityCompare
          : a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    if (!mounted) {
      return;
    }
    final filesChanged = !_driveFileListsEqual(_files, resolvedFiles);
    final foldersChanged = !_driveFolderListsEqual(_folders, resolvedFolders);
    if (!filesChanged && !foldersChanged) {
      return;
    }
    final nextFilesById = <String, _DriveFile>{
      for (final file in resolvedFiles) file.id: file,
    };
    if (filesChanged) {
      for (final file in resolvedFiles) {
        final updatedExisting = _fileSnapshotSources.updateExisting(
          file,
          idOf: (record) => record.id,
        );
        if (!updatedExisting) {
          _fileSnapshotSources.upsert(
            _snapshotSourceForFile(file),
            file,
            idOf: (record) => record.id,
          );
        }
      }
    }
    if (foldersChanged) {
      _folderSnapshotSources.restore(
        resolvedFolders,
        idOf: (folder) => folder.id,
        isAssignedBusiness: (folder) => folder.storageScope != 'personal',
      );
    }
    setState(() {
      if (filesChanged) {
        _files
          ..clear()
          ..addAll(resolvedFiles);
        _filesById
          ..clear()
          ..addAll(nextFilesById);
      }
      if (foldersChanged) {
        _folders
          ..clear()
          ..addAll(resolvedFolders);
      }
    });
  }

  bool _driveFoldersEqual(_DriveFolder a, _DriveFolder b) {
    return a.id == b.id &&
        a.name == b.name &&
        a.encryptedName == b.encryptedName &&
        a.metadataEncryption == b.metadataEncryption &&
        a.colorHex == b.colorHex &&
        a.createdAt == b.createdAt &&
        a.updatedAt == b.updatedAt &&
        a.lastFileAt == b.lastFileAt &&
        a.systemFolder == b.systemFolder &&
        a.systemKey == b.systemKey &&
        a.parentId == b.parentId &&
        a.storageScope == b.storageScope &&
        a.companyId == b.companyId &&
        a.ownerUid == b.ownerUid &&
        a.createdByUid == b.createdByUid &&
        listEquals(a.allowedUids, b.allowedUids) &&
        listEquals(a.groupIds, b.groupIds) &&
        mapEquals(a.sharedKeyEnvelopes, b.sharedKeyEnvelopes);
  }

  bool _driveFolderListsEqual(List<_DriveFolder> a, List<_DriveFolder> b) {
    if (identical(a, b)) {
      return true;
    }
    if (a.length != b.length) {
      return false;
    }
    for (var index = 0; index < a.length; index++) {
      if (!_driveFoldersEqual(a[index], b[index])) {
        return false;
      }
    }
    return true;
  }

  String? _trimmedStringValue(dynamic value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? _firstNonEmptyField(Map<String, dynamic>? data, List<String> keys) {
    if (data == null || data.isEmpty) {
      return null;
    }
    for (final key in keys) {
      final value = _trimmedStringValue(data[key]);
      if (value != null) {
        return value;
      }
    }
    return null;
  }

  String? _resolveStoragePrefixFromData(Map<String, dynamic>? data) {
    final directPrefix = sanitizeStorageHomePrefix(
      _firstNonEmptyField(data, const <String>[
        'storagePrefix',
        'storageHomePrefix',
        'storageRootPrefix',
        'storageFolderPrefix',
      ]),
    );
    if (directPrefix != null) {
      return directPrefix;
    }
    return storageHomePrefixForUid(widget.user.uid);
  }

  WasabiStorageService? _buildWasabiServiceFromData(
    Map<String, dynamic>? data,
  ) {
    final credentialMode = _trimmedStringValue(
      data?['credentialMode'],
    )?.toLowerCase();
    final bucketName = _firstNonEmptyField(data, const <String>[
      'bucketName',
      'wasabiBucketName',
      'bucket',
    ]);
    if (credentialMode != 'server_managed') {
      return null;
    }

    final resolvedRegion =
        _firstNonEmptyField(data, const <String>['region', 'wasabiRegion']) ??
        _defaultWasabiRegion;
    final resolvedEndpoint =
        _firstNonEmptyField(data, const <String>[
          'endpointUrl',
          'wasabiEndpointUrl',
          'wasabiS3Endpoint',
          'endpoint',
        ]) ??
        _defaultWasabiEndpoint;

    final useLegacyGlobalWasabiConfig =
        resolvedRegion.trim().toLowerCase() == 'us-east-1' &&
        resolvedEndpoint.trim().toLowerCase() == 'https://s3.wasabisys.com';

    final region = useLegacyGlobalWasabiConfig
        ? _defaultWasabiRegion
        : resolvedRegion;
    final signingRegion =
        _firstNonEmptyField(data, const <String>[
          'signingRegion',
          'wasabiSigningRegion',
        ]) ??
        _defaultWasabiSigningRegion;
    final endpoint = useLegacyGlobalWasabiConfig
        ? _defaultWasabiEndpoint
        : resolvedEndpoint;
    final serverManagedPrefixes = data?['serverManagedPrefixes'] is List
        ? (data!['serverManagedPrefixes'] as List)
              .map((value) => value.toString().trim())
              .where((value) => value.isNotEmpty)
              .toList(growable: false)
        : const <String>[];
    final storagePrefix = _resolveStoragePrefixFromData(data);
    final serverManagedScopes = <String>{
      ...serverManagedPrefixes,
      if (storagePrefix != null) storagePrefix,
    }.toList(growable: false);

    try {
      return WasabiStorageService.serverManaged(
        bucket: bucketName ?? 'managed-storage',
        region: region,
        signingRegion: signingRegion,
        endpointUrl: endpoint,
        idTokenProvider: accountBoundTokenProvider(
          auth: widget.auth, uid: widget.user.uid,
        ),
        authorizedObjectUri: ReleaseRuntimeConfig.resolveCheckoutApiBaseUri()
            .resolve('storage/wasabi/authorize-object'),
        serverManagedPrefixes: serverManagedScopes,
      );
    } on WasabiConfigurationException {
      if (kDebugMode) {
        debugPrint('Provisioned secure-storage configuration was invalid.');
      }
      return null;
    } catch (_) {
      if (kDebugMode) {
        debugPrint('Could not apply the provisioned secure-storage response.');
      }
      return null;
    }
  }

  bool _shouldAttemptWasabiProvisionRepair(Map<String, dynamic>? profileData) {
    final subscriptionStatus = _trimmedStringValue(
      profileData?['subscriptionStatus'],
    )?.toLowerCase();
    final provisioningStatus = _trimmedStringValue(
      profileData?['wasabiProvisioningStatus'],
    )?.toLowerCase();

    const subscriptionEligibleStatuses = <String>{
      'free',
      'active',
      'paid',
      'complete',
      'completed',
      'success',
      'succeeded',
      'trial',
      'trialing',
    };
    const repairableProvisioningStates = <String>{
      'provisioning',
      'ready',
      'error',
    };

    return subscriptionEligibleStatuses.contains(subscriptionStatus) ||
        repairableProvisioningStates.contains(provisioningStatus);
  }

  Future<WasabiStorageService?> _requestWasabiProvisionRepair(
    Map<String, dynamic>? profileData,
  ) async {
    final locallyEligible = _shouldAttemptWasabiProvisionRepair(profileData);
    if (!locallyEligible && kDebugMode) {
      debugPrint(
        'Attempting Wasabi repair even though local subscription flags are stale or incomplete.',
      );
    }

    try {
      _logRuntime(
        'storage',
        'Requesting Wasabi provisioning repair from the backend.',
      );
      final normalized = await WasabiProvisioningService.forApp(
        widget.auth.app,
      ).ensureProvisioned(user: widget.auth.currentUser ?? widget.user);
      final repairedPrefix = _resolveStoragePrefixFromData(normalized);
      if (repairedPrefix != null) {
        _storageHomePrefix = repairedPrefix;
      }
      _logRuntime(
        'storage',
        'Wasabi provisioning repair returned a usable configuration payload.',
      );
      return _buildWasabiServiceFromData(normalized);
    } on WasabiProvisioningException {
      if (kDebugMode) {
        debugPrint('Secure-storage repair request was not completed.');
      }
      return null;
    } catch (_) {
      if (kDebugMode) {
        debugPrint('Secure-storage repair request was unavailable.');
      }
      return null;
    }
  }

  Future<bool> _tryConfigureStorageFromProvisionedCredentials({
    bool forceRefresh = false,
  }) async {
    _logRuntime('storage', 'Checking protected storage configuration.');
    if (_storageService.isConfigured && !forceRefresh) {
      _logRuntime('storage', 'Wasabi storage is already configured in memory.');
      return true;
    }
    if (widget.storageService != null) {
      _logRuntime('storage', 'Using injected Wasabi storage service.');
      return _storageService.isConfigured;
    }

    final now = DateTime.now();
    if (!forceRefresh &&
        _lastStorageProvisionCheckAt != null &&
        now.difference(_lastStorageProvisionCheckAt!) <
            _storageProvisionCheckCooldown) {
      return _storageService.isConfigured;
    }

    final active = _activeStorageProvisionCheck;
    if (active != null) {
      return active;
    }

    final future = () async {
      _lastStorageProvisionCheckAt = now;

      try {
        _logRuntime(
          'storage',
          'Loading Wasabi provisioning data from user profile documents.',
        );
        final userRef = widget.firestore
            .collection('users')
            .doc(widget.user.uid);
        const profileSnapshotTimeout = Duration(seconds: 8);
        Future<DocumentSnapshot<Map<String, dynamic>>?>
        loadProfileSnapshot() async {
          try {
            return await userRef.get().timeout(profileSnapshotTimeout);
          } catch (_) {
            if (kDebugMode) {
              debugPrint('Could not read secure-storage profile state.');
            }
            return null;
          }
        }

        var profileSnapshot = await loadProfileSnapshot();
        final resolvedStoragePrefix = _resolveStoragePrefixFromData(
          profileSnapshot?.data(),
        );
        if (resolvedStoragePrefix != null) {
          _storageHomePrefix = resolvedStoragePrefix;
        }
        var provisioned = _buildWasabiServiceFromData(profileSnapshot?.data());
        var backendRepairAttempted = false;

        if (forceRefresh) {
          backendRepairAttempted = true;
          _logRuntime(
            'storage',
            'Requesting backend Wasabi provisioning refresh.',
          );
          final repaired = await _requestWasabiProvisionRepair(
            profileSnapshot?.data(),
          );
          if (repaired != null && repaired.isConfigured) {
            provisioned = repaired;
            _logRuntime(
              'storage',
              'Wasabi configuration and access policy were refreshed by backend repair.',
            );
          }
        }

        if (provisioned != null && provisioned.isConfigured) {
          _logRuntime(
            'storage',
            'Loaded a valid Wasabi configuration from Firestore data.',
          );
        }

        if (provisioned == null || !provisioned.isConfigured) {
          _logRuntime(
            'storage',
            'No valid Wasabi configuration found in Firestore. '
                'Attempting backend repair.',
          );
          if (!backendRepairAttempted) {
            backendRepairAttempted = true;
            final repaired = await _requestWasabiProvisionRepair(
              profileSnapshot?.data(),
            );
            if (repaired != null && repaired.isConfigured) {
              provisioned = repaired;
              _logRuntime(
                'storage',
                'Wasabi configuration became available after backend repair.',
              );
            }
          }
          if (provisioned == null || !provisioned.isConfigured) {
            profileSnapshot = await loadProfileSnapshot();
            final refreshedStoragePrefix = _resolveStoragePrefixFromData(
              profileSnapshot?.data(),
            );
            if (refreshedStoragePrefix != null) {
              _storageHomePrefix = refreshedStoragePrefix;
            }
            provisioned = _buildWasabiServiceFromData(profileSnapshot?.data());
            if (provisioned != null && provisioned.isConfigured) {
              _logRuntime(
                'storage',
                'Wasabi configuration became available after refreshing Firestore data.',
              );
            }
          }
        }

        if (provisioned == null || !provisioned.isConfigured) {
          _logRuntime(
            'storage',
            'Wasabi configuration is still unavailable after refresh attempts.',
          );
          return false;
        }

        if (!mounted) {
          _storageService = provisioned;
          _logRuntime(
            'storage',
            'Wasabi configuration applied while widget was unmounted.',
          );
          return true;
        }

        setState(() {
          _storageService = provisioned!;
        });
        _logRuntime('storage', 'Wasabi storage is now configured and ready.');
        return true;
      } catch (_) {
        if (kDebugMode) {
          debugPrint('Could not load provisioned secure-storage access.');
        }
        return false;
      }
    }();

    _activeStorageProvisionCheck = future;
    final configured = await future;
    if (identical(_activeStorageProvisionCheck, future)) {
      _activeStorageProvisionCheck = null;
    }
    return configured;
  }

  Future<bool> _ensureStorageConfigured({bool forceRefresh = false}) async {
    if (_storageService.isConfigured && !forceRefresh) {
      _logRuntime(
        'storage',
        'Storage check passed using existing configuration.',
      );
      unawaited(_cleanupInterruptedMultipartUploads());
      return true;
    }

    if (widget.storageService != null) {
      _logRuntime('storage', 'Storage check using injected storage service.');
      if (_storageService.isConfigured) {
        unawaited(_cleanupInterruptedMultipartUploads());
      }
      return _storageService.isConfigured;
    }

    final refreshed = WasabiStorageService.fromEnvironment();
    if (refreshed.isConfigured) {
      setState(() {
        _storageService = refreshed;
      });
      _logRuntime(
        'storage',
        'Storage configured from compile-time or environment values.',
      );
      unawaited(_cleanupInterruptedMultipartUploads());
      return true;
    }

    _logRuntime(
      'storage',
      'Storage not configured locally; trying provisioned credentials.',
    );
    final provisionedConfigured =
        await _tryConfigureStorageFromProvisionedCredentials(
          forceRefresh: forceRefresh,
        );
    if (provisionedConfigured) {
      _logRuntime('storage', 'Provisioned storage configuration succeeded.');
      unawaited(_cleanupInterruptedMultipartUploads());
      return true;
    }

    String? provisioningError;
    try {
      final snapshot = await widget.firestore
          .collection('users')
          .doc(widget.user.uid)
          .get()
          .timeout(const Duration(seconds: 8));
      provisioningError = _trimmedStringValue(
        snapshot.data()?['wasabiProvisioningError'],
      );
    } catch (_) {
      provisioningError = null;
    }

    if (provisioningError != null) {
      _logRuntime(
        'storage',
        'Storage remains unavailable and the backend reported a provisioning error.',
      );
      _showMessage(
        'Secure storage is still being prepared. Wait a moment and try again. '
        'If this continues, contact support.',
      );
      return false;
    }

    _logRuntime(
      'storage',
      'Storage remains unavailable and no provisioning error was returned.',
    );
    _showMessage(
      'Secure storage is not ready yet. Wait a moment and try again. '
      'If this continues, contact support.',
    );
    return false;
  }

  Future<bool> _ensureStorageConfiguredForPreview({
    bool forceRefresh = false,
  }) async {
    if (_storageService.isConfigured && !forceRefresh) {
      return true;
    }

    if (widget.storageService != null) {
      return _storageService.isConfigured;
    }

    final refreshed = WasabiStorageService.fromEnvironment();
    if (refreshed.isConfigured) {
      if (mounted) {
        setState(() {
          _storageService = refreshed;
        });
      } else {
        _storageService = refreshed;
      }
      _logRuntime(
        'storage',
        'Preview storage configured from compile-time or environment values.',
      );
      return true;
    }

    _logRuntime(
      'storage',
      'Preview storage is not configured; trying provisioned credentials.',
    );
    final provisionedConfigured =
        await _tryConfigureStorageFromProvisionedCredentials(
          forceRefresh: forceRefresh,
        );
    return provisionedConfigured || _storageService.isConfigured;
  }

  Future<bool> _refreshWasabiBrowserUploadProvisioning() async {
    if (!kIsWeb || widget.storageService != null) {
      return _storageService.isConfigured;
    }

    _logRuntime(
      'storage',
      'Refreshing Wasabi provisioning before browser upload.',
    );
    final refreshed = await _tryConfigureStorageFromProvisionedCredentials(
      forceRefresh: true,
    );
    if (!refreshed) {
      _logRuntime(
        'storage',
        'Wasabi provisioning refresh did not return a usable configuration.',
      );
    }
    return refreshed || _storageService.isConfigured;
  }

  Future<void> _ensureWasabiBrowserUploadCors() async {
    if (!kIsWeb || _wasabiCorsReady) {
      return;
    }

    final active = _activeWasabiCorsCheck;
    if (active != null) {
      await active;
      return;
    }

    final future = () async {
      await WasabiProvisioningService.forApp(
        widget.auth.app,
      ).ensureBrowserUploadCors();
      _wasabiCorsReady = true;
    }();

    _activeWasabiCorsCheck = future;
    try {
      await future;
    } finally {
      if (identical(_activeWasabiCorsCheck, future)) {
        _activeWasabiCorsCheck = null;
      }
    }
  }

  void _subscribeToFiles() {
    _filesStreamReconnectTimer?.cancel();
    _filesSubscription?.cancel();
    _initializedFileSnapshotSources.remove(WorkspaceSnapshotSource.personal);

    final query = widget.firestore
        .collection('files')
        .where('uid', isEqualTo: widget.user.uid);

    _filesSubscription = query.snapshots().listen(
      (snapshot) {
        _filesStreamReconnectAttempts = 0;
        _enqueueFileSnapshotProcessing(
          snapshot,
          source: WorkspaceSnapshotSource.personal,
        );
      },
      onError: (_) {
        _runOnPlatformThread(() async {
          if (kDebugMode) {
            debugPrint(
              'File refresh was unavailable; provider details were discarded.',
            );
          }
          if (!mounted) {
            return;
          }
          setState(() {
            _loadingFiles = false;
          });
          if (_shouldShowStreamErrorNotice(_lastFilesStreamErrorNoticeAt)) {
            _lastFilesStreamErrorNoticeAt = DateTime.now();
            _showMessage(
              'Files could not be refreshed. Your last verified file view '
              'remains available while RonikCloud retries.',
            );
          }
          _scheduleFilesStreamReconnect();
        });
      },
    );

    if (!_hasLoadedFileSnapshot) {
      _initialFileSnapshotLoad ??= _primeInitialFileSnapshot(query);
    }
  }

  Future<void> _primeInitialFileSnapshot(
    Query<Map<String, dynamic>> query,
  ) async {
    try {
      QuerySnapshot<Map<String, dynamic>>? snapshot;

      try {
        final cachedSnapshot = await query
            .get(const GetOptions(source: Source.cache))
            .timeout(const Duration(seconds: 3));
        if (cachedSnapshot.docs.isNotEmpty) {
          snapshot = cachedSnapshot;
          _logRuntime(
            'files',
            'Loaded initial file metadata from the provider cache.',
          );
        }
      } catch (_) {}

      if (snapshot == null) {
        await _restoreCachedFilesFromPreferences();
      }

      if (snapshot != null) {
        _logRuntime('files', 'Applying initial file metadata fallback.');
        await _applyInitialFileSnapshot(snapshot);
      } else {
        _logRuntime(
          'files',
          'No cached file snapshot was available. Waiting for live updates.',
        );
      }
    } catch (_) {
      if (kDebugMode) {
        debugPrint(
          'Initial file snapshot fallback was unavailable; provider details '
          'were discarded.',
        );
      }
      _logRuntime(
        'files',
        'Initial file metadata fallback was unavailable. Waiting for live '
            'updates.',
      );
      await _restoreCachedFilesFromPreferences();
      if (mounted && !_hasLoadedFileSnapshot) {
        setState(() {
          _loadingFiles = false;
        });
      }
    } finally {
      _initialFileSnapshotLoad = null;
    }
  }

  Future<void> _applyInitialFileSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) async {
    if (_initializedFileSnapshotSources.contains(
      WorkspaceSnapshotSource.personal,
    )) {
      _logRuntime(
        'files',
        'Ignored an older file fallback after live Personal metadata arrived.',
      );
      return;
    }
    try {
      await _runOnPlatformThread(() async {
        await _processFileSnapshot(
          snapshot,
          source: WorkspaceSnapshotSource.personal,
          markSourceInitialized: false,
        );
      });
    } catch (_) {
      _handleFileSnapshotProcessingError();
    }
  }

  void _enqueueFileSnapshotProcessing(
    QuerySnapshot<Map<String, dynamic>> snapshot, {
    required WorkspaceSnapshotSource source,
    int? companyStreamGeneration,
  }) {
    final previousProcessing = _pendingFileSnapshotProcessing;
    _pendingFileSnapshotProcessing = () async {
      try {
        await previousProcessing;
      } catch (_) {}
      try {
        await _runOnPlatformThread(() async {
          await _processFileSnapshot(
            snapshot,
            source: source,
            companyStreamGeneration: companyStreamGeneration,
          );
        });
      } catch (_) {
        _handleFileSnapshotProcessingError();
      }
    }();
  }

  void _handleFileSnapshotProcessingError() {
    if (kDebugMode) {
      debugPrint(
        'File metadata processing stopped at a protected failure boundary.',
      );
    }
    _logRuntime(
      'files',
      'File metadata processing stopped at a protected failure boundary.',
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _loadingFiles = false;
    });
  }

  _DriveFile? _tryParseDriveFile(DocumentSnapshot<Map<String, dynamic>> doc) {
    try {
      return _DriveFile.fromDocument(doc);
    } catch (_) {
      if (kDebugMode) {
        debugPrint('Malformed file metadata was skipped safely.');
      }
      _logRuntime('files', 'Malformed file metadata was skipped safely.');
      return null;
    }
  }

  Future<void> _processFileSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot, {
    required WorkspaceSnapshotSource source,
    bool markSourceInitialized = true,
    int? companyStreamGeneration,
  }) async {
    bool sourceIsCurrent() {
      return source != WorkspaceSnapshotSource.assignedBusiness ||
          (_canReadCompanyStorage &&
              companyStreamGeneration == _companyStorageStreamGeneration);
    }

    if (!sourceIsCurrent()) {
      return;
    }
    var changed = false;
    final sourceInitialized = _initializedFileSnapshotSources.contains(source);

    if (!sourceInitialized) {
      final sourceFiles = <_DriveFile>[];
      for (final doc in snapshot.docs) {
        final parsedFile = _tryParseDriveFile(doc);
        if (parsedFile == null) {
          continue;
        }
        sourceFiles.add(parsedFile);
      }
      final activeSourceFiles = sourceFiles
          .where((file) => file.isActive)
          .toList(growable: false);
      final resolvedActiveFiles =
          activeSourceFiles.any(_fileNeedsLocalNameDecryption)
          ? await _maybeDecryptFileNames(activeSourceFiles)
          : activeSourceFiles;
      if (!sourceIsCurrent()) {
        return;
      }
      final resolvedById = <String, _DriveFile>{
        for (final file in resolvedActiveFiles) file.id: file,
      };
      _fileSnapshotSources.replace(
        source,
        sourceFiles.map((file) => resolvedById[file.id] ?? file),
        idOf: (file) => file.id,
      );
      if (markSourceInitialized) {
        _initializedFileSnapshotSources.add(source);
      }
      changed = true;
    } else {
      var encryptionKeyChecked = false;
      String? encryptionKeyString;
      var secureEncryptionKeyChecked = false;
      String? secureEncryptionKeyString;
      Future<String?> ensureStandardEncryptionKeyString() async {
        if (encryptionKeyChecked) {
          return encryptionKeyString;
        }
        encryptionKeyChecked = true;
        encryptionKeyString = await _ensureEncryptionKey(interactive: false);
        return encryptionKeyString;
      }

      Future<String?> ensureSecureEncryptionKeyString() async {
        if (secureEncryptionKeyChecked) {
          return secureEncryptionKeyString;
        }
        secureEncryptionKeyChecked = true;
        secureEncryptionKeyString = await _ensureSecureEncryptionKey(
          interactive: false,
        );
        return secureEncryptionKeyString;
      }

      for (final change in snapshot.docChanges) {
        final fileId = change.doc.id;
        final previousFile = _fileSnapshotSources.item(source, fileId);
        if (change.type == DocumentChangeType.removed) {
          if (_fileSnapshotSources.remove(source, fileId) != null) {
            changed = true;
          }
          continue;
        }

        final parsedFile = _tryParseDriveFile(change.doc);
        if (parsedFile == null) {
          continue;
        }
        final resolvedFile = parsedFile.isActive
            ? await _resolveDriveFile(
                parsedFile,
                standardEncryptionKey: _fileNeedsLocalNameDecryption(parsedFile)
                    ? await ensureStandardEncryptionKeyString()
                    : null,
                secureEncryptionKey: _fileNeedsLocalNameDecryption(parsedFile)
                    ? await ensureSecureEncryptionKeyString()
                    : null,
              )
            : parsedFile;
        if (!sourceIsCurrent()) {
          return;
        }

        if (previousFile != null &&
            _driveFilesEqual(previousFile, resolvedFile)) {
          continue;
        }

        if (previousFile == null) {
          final mergedFilesById = <String, _DriveFile>{
            for (final file in _fileSnapshotSources.mergedItems) file.id: file,
          };
          final pendingId = pendingFileIdReplacedByServerRecord(
            serverFileId: fileId,
            objectKey: parsedFile.objectKey,
            knownFileIds: mergedFilesById.keys,
          );
          final pendingFile = pendingId == null
              ? null
              : mergedFilesById[pendingId];
          if (pendingFile != null &&
              pendingFile.objectKey == parsedFile.objectKey) {
            _fileSnapshotSources.removeWhere(
              (file) => file.id == pendingFile.id,
            );
            _resolvedFileNameCache.remove(pendingFile.id);
          }
        }

        _fileSnapshotSources.upsert(
          source,
          resolvedFile,
          idOf: (file) => file.id,
        );
        changed = true;
      }
    }

    final nextFiles = _fileSnapshotSources.index == null
        ? (_fileSnapshotSources.mergedItems.where((file) => file.isActive).toList()
          ..sort(_compareDriveFiles))
        : _fileSnapshotSources.sortedItems;
    final nextFilesById = <String, _DriveFile>{
      for (final file in nextFiles) file.id: file,
    };
    final computedUsage = (_fileSnapshotSources.index?.totalWeight ??
        _fileSnapshotSources.mergedItems.fold<int>(0, (total, file) => total + file.size)).toDouble();
    final viewChanged =
        !_driveFileListsEqual(_files, nextFiles) ||
        _fileUsageBytes != computedUsage;
    if (!changed && !viewChanged && !_loadingFiles) {
      return;
    }

    _hasLoadedFileSnapshot = true;
    _resolvedFileNameCache.removeWhere(
      (id, _) => !nextFilesById.containsKey(id),
    );
    final totals = _calculateUsageTotals(computedUsage: computedUsage);
    if (!mounted) {
      return;
    }
    setState(() {
      _files
        ..clear()
        ..addAll(nextFiles);
      _filesById
        ..clear()
        ..addAll(nextFilesById);
      _fileUsageBytes = computedUsage;
      _usedBytes = totals.used;
      _totalBytes = totals.total;
      _loadingFiles = false;
    });
    if (changed || viewChanged) {
      _scheduleCachedFilesPersist();
      _scheduleOfflineSync();
    }
    _logRuntime(
      'files',
      changed || viewChanged
          ? 'Applied merged Personal and Business file metadata.'
          : 'Confirmed merged Personal and Business file metadata.',
    );
    _maybePromptForSecureRefresh();
    if (nextFiles.any(_fileNeedsLocalNameDecryption)) {
      unawaited(_retryFileDecryption());
    }
  }

  Future<List<_DriveFile>> _maybeDecryptFileNames(
    List<_DriveFile> files,
  ) async {
    final needsStandardKey = files.any(_fileNeedsStandardNameDecryption);
    final needsSecureKey = files.any(_fileNeedsSecureNameDecryption);
    final standardKeyString = needsStandardKey || needsSecureKey
        ? await _ensureEncryptionKey(interactive: false)
        : null;
    final secureKeyString = needsSecureKey
        ? await _ensureSecureEncryptionKey(interactive: false)
        : null;
    return Future.wait(
      files.map(
        (file) => _resolveDriveFile(
          file,
          standardEncryptionKey: standardKeyString,
          secureEncryptionKey: secureKeyString,
        ),
      ),
    );
  }

  Future<_DriveFile> _resolveDriveFile(
    _DriveFile file, {
    String? standardEncryptionKey,
    String? secureEncryptionKey,
  }) async {
    if (!_fileNeedsLocalNameDecryption(file)) {
      _resolvedFileNameCache.remove(file.id);
      return file;
    }

    final cacheKey =
        '${file.encryptionMode}|${file.storageLayout}|${file.encryptedName ?? ""}|${file.objectKey}';
    final cached = _resolvedFileNameCache[file.id];
    if (cached != null && cached.cacheKey == cacheKey) {
      final decryptedName = cached.decryptedName;
      if (decryptedName == null || decryptedName.isEmpty) {
        return file;
      }
      return _rebuildDriveFileWithName(file, decryptedName);
    }

    final encryptionKey = file.sharedKeyEnvelopes.isNotEmpty
        ? await _businessFileKeyStringForFile(file, interactive: false)
        : (file.isSecured ? secureEncryptionKey : standardEncryptionKey);
    if (encryptionKey == null &&
        !(file.isSecured &&
            file.sharedKeyEnvelopes.isEmpty &&
            standardEncryptionKey != null)) {
      return file;
    }

    var decryptedName = encryptionKey == null
        ? null
        : await _decryptFileDisplayName(file, encryptionKey: encryptionKey);
    if ((decryptedName == null || decryptedName.isEmpty) &&
        file.isSecured &&
        file.sharedKeyEnvelopes.isEmpty &&
        standardEncryptionKey != null) {
      decryptedName = await _decryptFileDisplayName(
        file,
        encryptionKey: standardEncryptionKey,
      );
      if (decryptedName != null && decryptedName.isNotEmpty) {
        unawaited(_migrateLegacySecureFileToStandard(file));
      }
    }
    final normalizedName = (decryptedName == null || decryptedName.isEmpty)
        ? null
        : decryptedName;
    _resolvedFileNameCache[file.id] = _ResolvedFileNameCacheEntry(
      cacheKey: cacheKey,
      decryptedName: normalizedName,
    );
    if (normalizedName == null) {
      return file;
    }
    return _rebuildDriveFileWithName(file, normalizedName);
  }

  Future<void> _migrateLegacySecureFileToStandard(_DriveFile file) async {
    try {
      await widget.firestore.collection('files').doc(file.id).update({
        'encryptionMode': 'standard',
        'storageLayout': 'single',
        'contentEncryption': 'standard',
        'shardCount': FieldValue.delete(),
        'shardSizeBytes': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      if (kDebugMode) {
        debugPrint('Legacy secure-file metadata migration was unavailable.');
      }
    }
  }

  Future<Uint8List?> _generateThumbnailBytes(
    XFile file, {
    Uint8List? bytes,
    int? sourceLength,
    Stream<List<int>> Function(int endExclusive)? openRead,
  }) async {
    if (bytes != null) {
      return generateBoundedImageThumbnail(bytes);
    }
    if (sourceLength != null && openRead != null) {
      return generateBoundedImageThumbnailFromSource(
        sourceLength: () async => sourceLength,
        openRead: openRead,
      );
    }
    return generateBoundedImageThumbnailFromSource(
      sourceLength: file.length,
      openRead: (endExclusive) => file.openRead(0, endExclusive),
    );
  }

  Future<String?> _decryptFileDisplayName(
    _DriveFile file, {
    required String encryptionKey,
  }) async {
    final encryptedName = file.encryptedName?.trim();
    if (encryptedName != null && encryptedName.isNotEmpty) {
      return _decryptFileName(encryptedName, encryptionKey: encryptionKey);
    }
    return _decryptObjectKeyName(file.objectKey, encryptionKey: encryptionKey);
  }

  Future<String?> _decryptObjectKeyName(
    String objectKey, {
    required String encryptionKey,
  }) async {
    final encodedName = _extractEncryptedObjectKeyName(objectKey);
    if (encodedName == null) {
      return null;
    }
    return _decryptFileName(encodedName, encryptionKey: encryptionKey);
  }

  _DriveFile _rebuildDriveFileWithName(_DriveFile file, String name) {
    return _DriveFile(
      id: file.id,
      name: name,
      objectKey: file.objectKey,
      size: file.size,
      isFolder: file.isFolder,
      contentType: file.contentType,
      uploadedAt: file.uploadedAt,
      pathSegments: file.pathSegments,
      folderId: file.folderId,
      folderName: file.folderName,
      folderColor: file.folderColor,
      etag: file.etag,
      encryptionMode: file.encryptionMode,
      encryptedName: file.encryptedName,
      storageLayout: file.storageLayout,
      shardCount: file.shardCount,
      shardSizeBytes: file.shardSizeBytes,
      shardScheme: file.shardScheme,
      contentEncryption: file.contentEncryption,
      secureContentEncoding: file.secureContentEncoding,
      secureRefreshedAt: file.secureRefreshedAt,
      secureRefreshDueAt: file.secureRefreshDueAt,
      hash: file.hash,
      hasKnownSize: file.hasKnownSize,
      plaintextSizeBytes:file.plaintextSizeBytes,
      hasThumbnail: file.hasThumbnail,
      storageScope: file.storageScope,
      companyId: file.companyId,
      ownerUid: file.ownerUid,
      createdByUid: file.createdByUid,
      lifecycleState: file.lifecycleState,
      versionGroupId: file.versionGroupId,
      revision: file.revision,
      backupPathHash: file.backupPathHash,
      backupModifiedMillis: file.backupModifiedMillis,
      allowedUids: file.allowedUids,
      groupIds: file.groupIds,
      sharedKeyEnvelopes: file.sharedKeyEnvelopes,
    );
  }

  int _compareDriveFolders(_DriveFolder a, _DriveFolder b) {
    final aActivity = a.activity ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bActivity = b.activity ?? DateTime.fromMillisecondsSinceEpoch(0);
    final result = bActivity.compareTo(aActivity);
    return result != 0
        ? result
        : a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
  }

  int _compareDriveFiles(_DriveFile a, _DriveFile b) {
    final aDate = a.uploadedAt;
    final bDate = b.uploadedAt;
    if (aDate != null && bDate != null) {
      final compare = bDate.compareTo(aDate);
      if (compare != 0) {
        return compare;
      }
    } else if (bDate != null) {
      return 1;
    } else if (aDate != null) {
      return -1;
    }
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  bool _driveFilesEqual(_DriveFile a, _DriveFile b) {
    return a.id == b.id &&
        a.name == b.name &&
        a.objectKey == b.objectKey &&
        a.size == b.size &&
        a.isFolder == b.isFolder &&
        a.contentType == b.contentType &&
        a.uploadedAt == b.uploadedAt &&
        listEquals(a.pathSegments, b.pathSegments) &&
        a.folderId == b.folderId &&
        a.folderName == b.folderName &&
        a.folderColor == b.folderColor &&
        a.etag == b.etag &&
        a.encryptionMode == b.encryptionMode &&
        a.encryptedName == b.encryptedName &&
        a.storageLayout == b.storageLayout &&
        a.shardCount == b.shardCount &&
        a.shardSizeBytes == b.shardSizeBytes &&
        a.shardScheme == b.shardScheme &&
        a.contentEncryption == b.contentEncryption &&
        a.secureContentEncoding == b.secureContentEncoding &&
        a.secureRefreshedAt == b.secureRefreshedAt &&
        a.secureRefreshDueAt == b.secureRefreshDueAt &&
        a.hash == b.hash &&
        a.hasKnownSize == b.hasKnownSize &&
        a.hasThumbnail == b.hasThumbnail &&
        a.storageScope == b.storageScope &&
        a.companyId == b.companyId &&
        a.ownerUid == b.ownerUid &&
        a.createdByUid == b.createdByUid &&
        a.lifecycleState == b.lifecycleState &&
        a.versionGroupId == b.versionGroupId &&
        a.revision == b.revision &&
        a.backupPathHash == b.backupPathHash &&
        a.backupModifiedMillis == b.backupModifiedMillis &&
        listEquals(a.allowedUids, b.allowedUids) &&
        listEquals(a.groupIds, b.groupIds) &&
        mapEquals(a.sharedKeyEnvelopes, b.sharedKeyEnvelopes);
  }

  bool _driveFileListsEqual(List<_DriveFile> a, List<_DriveFile> b) {
    if (identical(a, b)) {
      return true;
    }
    if (a.length != b.length) {
      return false;
    }
    for (var index = 0; index < a.length; index++) {
      if (!_driveFilesEqual(a[index], b[index])) {
        return false;
      }
    }
    return true;
  }

  bool _fileNeedsLocalNameDecryption(_DriveFile file) {
    if (file.isFolder) {
      return false;
    }
    final encryptedName = file.encryptedName?.trim();
    if (encryptedName != null && encryptedName.isNotEmpty) {
      return true;
    }
    return _extractEncryptedObjectKeyName(file.objectKey) != null;
  }

  String? _extractEncryptedObjectKeyName(String objectKey) {
    final lastSegment = objectKey.split('/').last.trim();
    if (lastSegment.isEmpty) {
      return null;
    }

    const encryptedMarker = '.e.';
    final markerIndex = lastSegment.indexOf(encryptedMarker);
    if (markerIndex > 0 &&
        markerIndex + encryptedMarker.length < lastSegment.length) {
      final candidate = lastSegment
          .substring(markerIndex + encryptedMarker.length)
          .trim();
      if (candidate.startsWith('enc--')) {
        return candidate;
      }
    }

    final underscoreIndex = lastSegment.indexOf('_');
    final candidate =
        (underscoreIndex > 0 && underscoreIndex < lastSegment.length - 1)
        ? lastSegment.substring(underscoreIndex + 1).trim()
        : lastSegment;
    if (!candidate.startsWith('enc--')) {
      return null;
    }
    return candidate;
  }

  void _removeDriveFileFromList(List<_DriveFile> files, String fileId) {
    final index = files.indexWhere((file) => file.id == fileId);
    if (index >= 0) {
      files.removeAt(index);
    }
  }

  void _insertDriveFileSorted(List<_DriveFile> files, _DriveFile file) {
    final insertionIndex = _findDriveFileInsertIndex(files, file);
    files.insert(insertionIndex, file);
  }

  WorkspaceSnapshotSource _snapshotSourceForFile(_DriveFile file) {
    return file.storageScope == 'personal'
        ? WorkspaceSnapshotSource.personal
        : WorkspaceSnapshotSource.assignedBusiness;
  }

  void _upsertLocalDriveFile(_DriveFile file) {
    final nextFiles = List<_DriveFile>.from(_files);
    final nextFilesById = Map<String, _DriveFile>.from(_filesById);
    final existingForObjectKey = _knownFileByObjectKey(file.objectKey);
    if (!shouldApplyOptimisticFileRecord(
      candidateFileId: file.id,
      objectKey: file.objectKey,
      existingFileIdForObjectKey: existingForObjectKey?.id,
    )) {
      _logRuntime(
        'files',
        'Authoritative file metadata arrived before local upload finalization; '
            'the stale optimistic record was ignored.',
      );
      return;
    }
    _fileSnapshotSources.upsert(
      _snapshotSourceForFile(file),
      file,
      idOf: (record) => record.id,
    );
    final previous = nextFilesById[file.id] ?? existingForObjectKey;

    if (previous != null) {
      nextFilesById.remove(previous.id);
      _resolvedFileNameCache.remove(previous.id);
      _removeDriveFileFromList(nextFiles, previous.id);
    }

    nextFilesById[file.id] = file;
    _insertDriveFileSorted(nextFiles, file);

    final computedUsage = _fileSnapshotSources.mergedItems
        .fold<int>(0, (total, retainedFile) => total + retainedFile.size)
        .toDouble();
    final totals = _calculateUsageTotals(computedUsage: computedUsage);
    _hasLoadedFileSnapshot = true;

    if (!mounted) {
      _files
        ..clear()
        ..addAll(nextFiles);
      _filesById
        ..clear()
        ..addAll(nextFilesById);
      _fileUsageBytes = computedUsage;
      _usedBytes = totals.used;
      _totalBytes = totals.total;
      _loadingFiles = false;
      return;
    }

    setState(() {
      _files
        ..clear()
        ..addAll(nextFiles);
      _filesById
        ..clear()
        ..addAll(nextFilesById);
      _fileUsageBytes = computedUsage;
      _usedBytes = totals.used;
      _totalBytes = totals.total;
      _loadingFiles = false;
    });
    _scheduleCachedFilesPersist();
    _maybePromptForSecureRefresh();
  }

  int _findDriveFileInsertIndex(List<_DriveFile> files, _DriveFile file) {
    var minIndex = 0;
    var maxIndex = files.length;
    while (minIndex < maxIndex) {
      final midIndex = minIndex + ((maxIndex - minIndex) >> 1);
      if (_compareDriveFiles(file, files[midIndex]) > 0) {
        minIndex = midIndex + 1;
      } else {
        maxIndex = midIndex;
      }
    }
    return minIndex;
  }

  void _subscribeToFolders() {
    _foldersStreamReconnectTimer?.cancel();
    _foldersSubscription?.cancel();

    final query = widget.firestore
        .collection('folders')
        .where('uid', isEqualTo: widget.user.uid);

    _foldersSubscription = query.snapshots().listen(
      (snapshot) {
        _foldersStreamReconnectAttempts = 0;
        _enqueueFolderSnapshotProcessing(
          snapshot,
          source: WorkspaceSnapshotSource.personal,
        );
      },
      onError: (_) {
        _runOnPlatformThread(() async {
          if (kDebugMode) {
            debugPrint(
              'Folder refresh was unavailable; provider details were discarded.',
            );
          }
          if (!mounted) {
            return;
          }
          setState(() {
            _loadingFolders = false;
          });
          if (_shouldShowStreamErrorNotice(_lastFoldersStreamErrorNoticeAt)) {
            _lastFoldersStreamErrorNoticeAt = DateTime.now();
            _showMessage(
              'Folders could not be refreshed. Your last verified folder view remains available while RonikCloud retries.',
            );
          }
          _scheduleFoldersStreamReconnect();
        });
      },
    );

    if (!_hasLoadedFolderSnapshot) {
      _initialFolderSnapshotLoad ??= _primeInitialFolderSnapshot(query);
    }
  }

  Future<void> _primeInitialFolderSnapshot(
    Query<Map<String, dynamic>> query,
  ) async {
    try {
      QuerySnapshot<Map<String, dynamic>>? snapshot;

      try {
        final cachedSnapshot = await query
            .get(const GetOptions(source: Source.cache))
            .timeout(const Duration(seconds: 3));
        if (cachedSnapshot.docs.isNotEmpty) {
          snapshot = cachedSnapshot;
          _logRuntime('folders', 'Loaded initial folder metadata from cache.');
        }
      } catch (_) {}

      if (snapshot == null) {
        await _restoreCachedFoldersFromPreferences();
      }

      if (snapshot != null) {
        _logRuntime('folders', 'Loaded an initial folder snapshot fallback.');
        await _applyInitialFolderSnapshot(snapshot);
      } else {
        _logRuntime(
          'folders',
          'No cached folder snapshot was available. Waiting for live updates.',
        );
      }
    } catch (_) {
      _logRuntime(
        'folders',
        'Initial folder snapshot fallback was unavailable. Waiting for live updates.',
      );
      await _restoreCachedFoldersFromPreferences();
      if (mounted && !_hasLoadedFolderSnapshot) {
        setState(() {
          _loadingFolders = false;
        });
      }
    } finally {
      _initialFolderSnapshotLoad = null;
    }
  }

  Future<void> _applyInitialFolderSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) async {
    if (_hasLoadedFolderSnapshot) {
      return;
    }
    try {
      await _runOnPlatformThread(() async {
        if (!_hasLoadedFolderSnapshot) {
          await _processFolderSnapshot(
            snapshot,
            source: WorkspaceSnapshotSource.personal,
          );
        }
      });
    } catch (_) {
      _handleFolderSnapshotProcessingError();
    }
  }

  void _enqueueFolderSnapshotProcessing(
    QuerySnapshot<Map<String, dynamic>> snapshot, {
    required WorkspaceSnapshotSource source,
    int? companyStreamGeneration,
  }) {
    final previousProcessing = _pendingFolderSnapshotProcessing;
    _pendingFolderSnapshotProcessing = () async {
      try {
        await previousProcessing;
      } catch (_) {}
      try {
        await _runOnPlatformThread(() async {
          await _processFolderSnapshot(
            snapshot,
            source: source,
            companyStreamGeneration: companyStreamGeneration,
          );
        });
      } catch (_) {
        _handleFolderSnapshotProcessingError();
      }
    }();
  }

  void _handleFolderSnapshotProcessingError() {
    _logRuntime(
      'folders',
      'Folder metadata refresh stopped at a protected failure boundary.',
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _loadingFolders = false;
    });
  }

  _DriveFolder? _tryParseDriveFolder(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    try {
      return _DriveFolder.fromDocument(doc);
    } catch (_) {
      _logRuntime(
        'folders',
        'Skipped one malformed folder record without retaining its identifier.',
      );
      return null;
    }
  }

  Future<void> _processFolderSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot, {
    required WorkspaceSnapshotSource source,
    int? companyStreamGeneration,
  }) async {
    bool sourceIsCurrent() {
      return source != WorkspaceSnapshotSource.assignedBusiness ||
          (_canReadCompanyStorage &&
              companyStreamGeneration == _companyStorageStreamGeneration);
    }

    if (!sourceIsCurrent()) {
      return;
    }
    final parsedFolders = <_DriveFolder>[];
    var skippedFolders = 0;
    for (final doc in snapshot.docs) {
      final parsedFolder = _tryParseDriveFolder(doc);
      if (parsedFolder == null) {
        skippedFolders++;
        continue;
      }
      parsedFolders.add(parsedFolder);
    }
    final sourceFolders = parsedFolders.any(_folderNeedsLocalNameDecryption)
        ? await _maybeDecryptFolderNames(parsedFolders)
        : parsedFolders;
    if (!sourceIsCurrent()) {
      return;
    }
    _folderSnapshotSources.replace(
      source,
      sourceFolders,
      idOf: (folder) => folder.id,
    );
    final folders = _folderSnapshotSources.index == null
        ? (_folderSnapshotSources.mergedItems.toList()..sort(_compareDriveFolders))
        : _folderSnapshotSources.sortedItems;
    _hasLoadedFolderSnapshot = true;
    final folderIds = folders.map((folder) => folder.id).toSet();
    _resolvedFolderNameCache.removeWhere((id, _) => !folderIds.contains(id));
    if (!mounted) {
      return;
    }
    setState(() {
      _folders
        ..clear()
        ..addAll(folders);
      _loadingFolders = false;
      _knownBackupFolderIds
        ..clear()
        ..addAll(folders.map((folder) => folder.id));
    });
    _normalizeWorkspaceSelection(folders: folders);
    _scheduleCachedFoldersPersist();
    _logRuntime(
      'folders',
      skippedFolders > 0
          ? 'Applied merged folder metadata and skipped malformed records.'
          : 'Applied merged Personal and Business folder metadata.',
    );
    if (_offlineFolders.isNotEmpty) {
      final folderLookup = <String, _DriveFolder>{
        for (final folder in folders) folder.id: folder,
      };
      final updatedConfigs = Map<String, _OfflineFolderConfig>.from(
        _offlineFolders,
      );
      var changed = false;
      for (final entry in _offlineFolders.entries) {
        final match = folderLookup[entry.key];
        if (match != null && match.displayName != entry.value.folderName) {
          updatedConfigs[entry.key] = _OfflineFolderConfig(
            folderKey: entry.value.folderKey,
            folderName: match.displayName,
            addedAt: entry.value.addedAt,
          );
          changed = true;
        }
      }
      if (changed) {
        setState(() {
          _offlineFolders
            ..clear()
            ..addAll(updatedConfigs);
        });
        unawaited(_persistOfflineFolders());
      }
    }
  }

  bool _folderNeedsLocalNameDecryption(_DriveFolder folder) {
    final encryptedName = folder.encryptedName?.trim();
    return encryptedName != null && encryptedName.isNotEmpty;
  }

  bool _folderNeedsStandardNameDecryption(_DriveFolder folder) {
    return _folderNeedsLocalNameDecryption(folder) &&
        folder.sharedKeyEnvelopes.isEmpty;
  }

  Future<List<_DriveFolder>> _maybeDecryptFolderNames(
    List<_DriveFolder> folders,
  ) async {
    final needsStandardKey = folders.any(_folderNeedsStandardNameDecryption);
    final standardKeyString = needsStandardKey
        ? await _ensureEncryptionKey(interactive: false)
        : null;
    return Future.wait(
      folders.map(
        (folder) => _resolveDriveFolder(
          folder,
          standardEncryptionKey: standardKeyString,
        ),
      ),
    );
  }

  Future<_DriveFolder> _resolveDriveFolder(
    _DriveFolder folder, {
    String? standardEncryptionKey,
  }) async {
    if (!_folderNeedsLocalNameDecryption(folder)) {
      _resolvedFolderNameCache.remove(folder.id);
      return folder;
    }
    final cacheKey =
        '${folder.metadataEncryption ?? ""}|'
        '${folder.encryptedName ?? ""}|'
        '${folder.sharedKeyEnvelopes[widget.user.uid] ?? ""}';
    final cached = _resolvedFolderNameCache[folder.id];
    if (cached != null && cached.cacheKey == cacheKey) {
      final decryptedName = cached.decryptedName;
      return decryptedName == null
          ? folder
          : _rebuildDriveFolderWithName(folder, decryptedName);
    }

    final encryptionKey = folder.sharedKeyEnvelopes.isNotEmpty
        ? await _businessFolderKeyString(folder, interactive: false)
        : standardEncryptionKey;
    if (encryptionKey == null || encryptionKey.isEmpty) {
      return folder;
    }
    final decryptedName = await _metadataEncryptionService.decryptLabel(
      encryptedLabel: folder.encryptedName!,
      key: SecretKey(base64Decode(encryptionKey)),
    );
    final normalizedName = decryptedName?.trim();
    _resolvedFolderNameCache[folder.id] = _ResolvedFileNameCacheEntry(
      cacheKey: cacheKey,
      decryptedName: normalizedName == null || normalizedName.isEmpty
          ? null
          : normalizedName,
    );
    if (normalizedName == null || normalizedName.isEmpty) {
      return folder;
    }
    return _rebuildDriveFolderWithName(folder, normalizedName);
  }

  _DriveFolder _rebuildDriveFolderWithName(_DriveFolder folder, String name) {
    return _DriveFolder(
      id: folder.id,
      name: name,
      encryptedName: folder.encryptedName,
      metadataEncryption: folder.metadataEncryption,
      colorHex: folder.colorHex,
      createdAt: folder.createdAt,
      updatedAt: folder.updatedAt,
      lastFileAt: folder.lastFileAt,
      systemFolder: folder.systemFolder,
      systemKey: folder.systemKey,
      parentId: folder.parentId,
      storageScope: folder.storageScope,
      companyId: folder.companyId,
      ownerUid: folder.ownerUid,
      createdByUid: folder.createdByUid,
      allowedUids: folder.allowedUids,
      groupIds: folder.groupIds,
      sharedKeyEnvelopes: folder.sharedKeyEnvelopes,
    );
  }

  void _scheduleCachedFoldersPersist() {
    _folderCachePersistTimer?.cancel();
    _folderCachePersistTimer = Timer(const Duration(milliseconds: 750), () {
      _folderCachePersistTimer = null;
      unawaited(_persistCachedFolders());
    });
  }

  Future<void> _persistCachedFolders() async {
    final owner = widget.user.uid;
    final permissionRevision = _companyStorageStreamGeneration;
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      if (!mounted || widget.user.uid != owner || widget.auth.currentUser?.uid != owner || permissionRevision != _companyStorageStreamGeneration) return;
      _prefs ??= prefs;
      final currentIds = _folders.map((item) => item.id).toSet();
      _folderCacheRows.removeWhere((id, _) => !currentIds.contains(id));
      final payload = _folders
          .map((folder) {
            final sourceMembership = <String>[
              if (_folderSnapshotSources.item(
                    WorkspaceSnapshotSource.personal,
                    folder.id,
                  ) !=
                  null)
                WorkspaceSnapshotSource.personal.name,
              if (_folderSnapshotSources.item(
                    WorkspaceSnapshotSource.assignedBusiness,
                    folder.id,
                  ) !=
                  null)
                WorkspaceSnapshotSource.assignedBusiness.name,
            ];
            if (sourceMembership.isEmpty) {
              sourceMembership.add(
                folder.storageScope == 'personal'
                    ? WorkspaceSnapshotSource.personal.name
                    : WorkspaceSnapshotSource.assignedBusiness.name,
              );
            }
            final membership =
                (sourceMembership.contains('personal') ? 1 : 0) |
                (sourceMembership.contains('assignedBusiness') ? 2 : 0);
            final previous = _folderCacheRows[folder.id];
            if (previous != null &&
                identical(previous.source, folder) &&
                previous.membership == membership) {
              return previous.row;
            }
            final row = <String, dynamic>{
              ...folder.toLocalCacheJson(),
              '_localSourceMembership': sourceMembership,
            };
            _folderCacheRows[folder.id] = (
              source: folder,
              membership: membership,
              row: row,
            );
            return row;
          })
          .toList(growable: false);
      await _metadataShards(
        prefs,
        _cachedFoldersPrefKey,
        LocalPrivateCacheCodec.cachedFoldersNamespace,
      ).replace(payload);
    } catch (_) {
      _logRuntime(
        'folders',
        'Encrypted folder-cache persistence was unavailable.',
      );
    }
  }

  Future<bool> _restoreCachedFoldersFromPreferences() async {
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      _prefs ??= prefs;
      final cacheRead = await _readPrivateCachePreference(
        prefs,
        baseKey: _cachedFoldersPrefKey,
        namespace: LocalPrivateCacheCodec.cachedFoldersNamespace,
      );
      final raw = cacheRead.value;
      if (cacheRead.temporarilyUnavailable) {
        _logRuntime(
          'folders',
          'Encrypted cached folders are waiting for the device credential store.',
        );
        return false;
      }
      if (cacheRead.discardedCorruptValue) {
        _logRuntime(
          'folders',
          'Unreadable or unprotectable cached folder metadata was removed.',
        );
      }
      if (cacheRead.decodedRows == null && (raw == null || raw.trim().isEmpty)) {
        return false;
      }

      final decoded = cacheRead.decodedRows ?? jsonDecode(raw!);
      if (decoded is! List) {
        return false;
      }

      final folders = <_DriveFolder>[];
      final personalCachedFolderIds = <String>{};
      final assignedCachedFolderIds = <String>{};
      var skippedFolders = 0;
      for (final entry in decoded) {
        if (entry is! Map) {
          skippedFolders++;
          continue;
        }
        try {
          final cacheEntry = Map<String, dynamic>.from(entry);
          final folder = _DriveFolder.fromLocalCacheJson(cacheEntry);
          folders.add(folder);
          final rawMembership = cacheEntry['_localSourceMembership'];
          final memberships = rawMembership is List
              ? rawMembership.whereType<String>().toSet()
              : const <String>{};
          if (memberships.contains(WorkspaceSnapshotSource.personal.name)) {
            personalCachedFolderIds.add(folder.id);
          }
          if (memberships.contains(
            WorkspaceSnapshotSource.assignedBusiness.name,
          )) {
            assignedCachedFolderIds.add(folder.id);
          }
          if (memberships.isEmpty) {
            if (folder.storageScope == 'personal') {
              personalCachedFolderIds.add(folder.id);
            } else {
              assignedCachedFolderIds.add(folder.id);
            }
          }
        } catch (_) {
          skippedFolders++;
        }
      }

      if (_hasAppliedUserProfileState && !_canReadCompanyStorage) {
        assignedCachedFolderIds.clear();
      }
      final retainedFolders = folders
          .where(
            (folder) =>
                personalCachedFolderIds.contains(folder.id) ||
                assignedCachedFolderIds.contains(folder.id),
          )
          .toList(growable: true);
      if (retainedFolders.isEmpty) {
        _folderSnapshotSources.replace(
          WorkspaceSnapshotSource.personal,
          const <_DriveFolder>[],
          idOf: (folder) => folder.id,
        );
        _folderSnapshotSources.replace(
          WorkspaceSnapshotSource.assignedBusiness,
          const <_DriveFolder>[],
          idOf: (folder) => folder.id,
        );
        _scheduleCachedFoldersPersist();
        return false;
      }

      _folderSnapshotSources.replace(
        WorkspaceSnapshotSource.personal,
        retainedFolders.where(
          (folder) => personalCachedFolderIds.contains(folder.id),
        ),
        idOf: (folder) => folder.id,
      );
      _folderSnapshotSources.replace(
        WorkspaceSnapshotSource.assignedBusiness,
        retainedFolders.where(
          (folder) => assignedCachedFolderIds.contains(folder.id),
        ),
        idOf: (folder) => folder.id,
      );

      retainedFolders.sort((a, b) {
        final aActivity = a.activity ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bActivity = b.activity ?? DateTime.fromMillisecondsSinceEpoch(0);
        final compare = bActivity.compareTo(aActivity);
        if (compare != 0) {
          return compare;
        }
        return a.displayName.toLowerCase().compareTo(
          b.displayName.toLowerCase(),
        );
      });

      final folderIds = retainedFolders.map((folder) => folder.id).toSet();

      if (!mounted) {
        _folders
          ..clear()
          ..addAll(retainedFolders);
        _knownBackupFolderIds
          ..clear()
          ..addAll(folderIds);
        _loadingFolders = false;
      } else {
        setState(() {
          _folders
            ..clear()
            ..addAll(retainedFolders);
          _knownBackupFolderIds
            ..clear()
            ..addAll(folderIds);
          _loadingFolders = false;
        });
      }

      _normalizeWorkspaceSelection(folders: retainedFolders);
      _logRuntime(
        'folders',
        skippedFolders > 0
            ? 'Restored encrypted cached folder metadata and skipped malformed records.'
            : 'Restored encrypted cached folder metadata.',
      );
      return true;
    } catch (_) {
      _logRuntime(
        'folders',
        'Encrypted folder-cache restore stopped at a protected failure boundary.',
      );
      return false;
    }
  }

  void _normalizeWorkspaceSelection({List<_DriveFolder>? folders}) {
    final normalizedId = _normalizeFolderId(_activeFolderId);
    if (normalizedId == null) {
      return;
    }

    final activeFolders = folders ?? _folders;
    final folderExists = activeFolders.any(
      (folder) => folder.id == normalizedId,
    );
    if (folderExists) {
      return;
    }

    final fileBackedFolderExists = _files.any(
      (file) =>
          !file.isFolder && _resolvedFolderKeyForFile(file) == normalizedId,
    );
    if (fileBackedFolderExists) {
      return;
    }

    if (!mounted) {
      _activeFolderId = null;
      _activeFolderLabel = null;
      return;
    }

    setState(() {
      _activeFolderId = null;
      _activeFolderLabel = null;
    });
  }

  double? _parseUsageBytes(Map<String, dynamic>? data, String key) {
    if (data == null) {
      return null;
    }

    return _coerceUsageBytes(data[key]);
  }

  double? _coerceUsageBytes(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value.toDouble();
    }
    if (value is double) {
      if (value.isNaN || !value.isFinite) {
        return null;
      }
      return value;
    }
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        return null;
      }

      final sanitized = trimmed.replaceAll(',', '');
      final canonical = sanitized.replaceAll(
        RegExp(r'(?<=\d)[\s_]+(?=\d)'),
        '',
      );
      final direct = double.tryParse(canonical);
      if (direct != null && direct.isFinite) {
        return direct;
      }

      final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(canonical);
      if (match != null) {
        final numeric = double.tryParse(match.group(1)!);
        if (numeric != null && numeric.isFinite) {
          final lower = sanitized.toLowerCase();
          double multiplier = 1.0;
          if (lower.contains('pb') || lower.contains('pib')) {
            multiplier = _bytesPerPb;
          } else if (lower.contains('tb') || lower.contains('tib')) {
            multiplier = _bytesPerTb;
          } else if (lower.contains('gb') || lower.contains('gib')) {
            multiplier = _bytesPerGb;
          } else if (lower.contains('mb') || lower.contains('mib')) {
            multiplier = _bytesPerMb;
          } else if (lower.contains('kb') || lower.contains('kib')) {
            multiplier = _bytesPerKb;
          } else if (lower.contains('bytes') || lower.contains('byte')) {
            multiplier = 1.0;
          } else if (lower.contains(' b')) {
            multiplier = 1.0;
          } else if (lower.endsWith('b')) {
            multiplier = 1.0;
          }

          final resolved = numeric * multiplier;
          if (!resolved.isNaN && resolved.isFinite) {
            return resolved;
          }
        }
      }
    }
    if (value is Map) {
      return _coerceUsageBytes(
        value['bytes'] ??
            value['usageBytes'] ??
            value['valueBytes'] ??
            value['value'] ??
            value['formattedValue'] ??
            value['formatted'] ??
            value['display'],
      );
    }
    return null;
  }

  _CapacityInfo _parseCapacityInfo(
    Map<String, dynamic>? data, {
    double? usageBytes,
  }) {
    if (data == null) {
      return const _CapacityInfo();
    }

    double? limitBytes = _coerceUsageBytes(data['capacityBytes']);
    bool pending = false;
    String? planLabel;

    double? resolvedLimit(dynamic value) {
      final parsed = _coerceUsageBytes(value);
      if (parsed != null && parsed.isFinite && parsed > 0) {
        return parsed;
      }
      return null;
    }

    if (limitBytes == null) {
      final capacityValue = data['capacity'];
      final parsedCapacity = resolvedLimit(capacityValue);
      if (parsedCapacity != null) {
        limitBytes = parsedCapacity;
      } else if (capacityValue is String) {
        final trimmed = capacityValue.trim();
        if (trimmed.isNotEmpty) {
          final lower = trimmed.toLowerCase();
          if (lower == 'pending' || lower == 'unknown') {
            pending = true;
          } else if (lower == 'unlimited' || lower == 'infinite') {
            planLabel ??= 'Unlimited storage';
          } else {
            planLabel ??= trimmed;
          }
        }
      }
    }

    if (limitBytes == null) {
      final freeBytes = _parseUsageBytes(data, 'freeBytes');
      if (freeBytes != null && usageBytes != null) {
        final combined = usageBytes + freeBytes;
        if (combined > 0) {
          limitBytes = combined;
        }
      }
    }

    if (limitBytes == null) {
      final tier = _trimmedOrNull(data['planTier']);
      if (tier != null) {
        final lowerTier = tier.toLowerCase();
        const double gb = 1073741824;
        const double tb = 1099511627776;

        if (['free', 'starter'].contains(lowerTier)) {
          limitBytes = 5 * gb;
          planLabel ??= 'Free Plan';
        } else if (['basic'].contains(lowerTier)) {
          limitBytes = 500 * gb;
          planLabel ??= 'Basic Plan';
        } else if (['pro', 'premium', 'plus'].contains(lowerTier)) {
          limitBytes = 1 * tb;
          planLabel ??= 'Pro Plan';
        } else if (['ultra', 'business', 'enterprise'].contains(lowerTier)) {
          limitBytes = 2 * tb;
          planLabel ??= 'Ultra Plan';
        }
      }
    }

    final planCandidates = <String?>[
      _trimmedOrNull(data['planLabel']),
      _trimmedOrNull(data['planName']),
      _trimmedOrNull(data['capacityLabel']),
      _trimmedOrNull(data['subscriptionPlan']),
    ];
    for (final candidate in planCandidates) {
      if (candidate == null) {
        continue;
      }
      final lower = candidate.toLowerCase();
      if (lower == 'pending' || lower == 'unknown') {
        pending = true;
        continue;
      }
      planLabel = candidate;
      break;
    }

    if (planLabel == null && limitBytes != null && limitBytes > 0) {
      planLabel = '${_formatStorageValue(limitBytes)} available';
    }

    return _CapacityInfo(
      limitBytes: limitBytes,
      label: planLabel,
      pending: pending,
    );
  }

  ({double used, double total}) _calculateUsageTotals({
    double? profileUsage,
    double? computedUsage,
    double? pendingBytes,
    double? limitBytes,
    bool? hasLimit,
  }) {
    final profile = profileUsage ?? _profileUsageBytes;
    final computed = computedUsage ?? _fileUsageBytes;
    final pending = pendingBytes ?? _pendingUploadBytes;
    final limit = limitBytes ?? _storageLimitBytes;
    final limitEnabled = hasLimit ?? _storageHasLimit;
    final baseUsage = _preferredUsageBase(
      profileUsage: profile,
      computedUsage: computed,
    );
    final pendingContribution = (pending.isFinite && pending > 0)
        ? pending
        : 0.0;
    final combinedUsage = baseUsage + pendingContribution;

    if (limitEnabled && limit != null && limit.isFinite && limit > 0) {
      final effectiveLimit = limit < combinedUsage ? combinedUsage : limit;
      return (used: combinedUsage, total: effectiveLimit);
    }

    final safeUsage = combinedUsage < 0 ? 0.0 : combinedUsage;
    return (used: safeUsage, total: safeUsage);
  }

  double _preferredUsageBase({double? profileUsage, double? computedUsage}) {
    double? sanitize(double? value) {
      if (value == null || !value.isFinite || value < 0) {
        return null;
      }
      return value;
    }

    final profile = sanitize(profileUsage);
    final computed = sanitize(computedUsage);
    if (_hasLoadedFileSnapshot) {
      return computed ?? profile ?? 0.0;
    }
    return profile ?? computed ?? 0.0;
  }

  _DriveFile? _knownFileByObjectKey(String objectKey) {
    final trimmed = objectKey.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    for (final file in _files) {
      if (file.objectKey == trimmed) {
        return file;
      }
    }
    return null;
  }

  void _scheduleCachedFilesPersist() {
    _fileCachePersistTimer?.cancel();
    _fileCachePersistTimer = Timer(const Duration(milliseconds: 750), () {
      _fileCachePersistTimer = null;
      unawaited(_persistCachedFiles());
    });
  }

  Future<void> _persistCachedFiles() async {
    final owner = widget.user.uid;
    final permissionRevision = _companyStorageStreamGeneration;
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      if (!mounted || widget.user.uid != owner || widget.auth.currentUser?.uid != owner || permissionRevision != _companyStorageStreamGeneration) return;
      _prefs ??= prefs;
      final currentIds = _files.map((item) => item.id).toSet();
      _fileCacheRows.removeWhere((id, _) => !currentIds.contains(id));
      final payload = _files
          .map((file) {
            final sourceMembership = <String>[
              if (_fileSnapshotSources.item(
                    WorkspaceSnapshotSource.personal,
                    file.id,
                  ) !=
                  null)
                WorkspaceSnapshotSource.personal.name,
              if (_fileSnapshotSources.item(
                    WorkspaceSnapshotSource.assignedBusiness,
                    file.id,
                  ) !=
                  null)
                WorkspaceSnapshotSource.assignedBusiness.name,
            ];
            if (sourceMembership.isEmpty) {
              sourceMembership.add(_snapshotSourceForFile(file).name);
            }
            final membership =
                (sourceMembership.contains('personal') ? 1 : 0) |
                (sourceMembership.contains('assignedBusiness') ? 2 : 0);
            final previous = _fileCacheRows[file.id];
            if (previous != null &&
                identical(previous.source, file) &&
                previous.membership == membership) {
              return previous.row;
            }
            final row = <String, dynamic>{
              ...file.toLocalCacheJson(),
              '_localSourceMembership': sourceMembership,
            };
            _fileCacheRows[file.id] = (
              source: file,
              membership: membership,
              row: row,
            );
            return row;
          })
          .toList(growable: false);
      await _metadataShards(
        prefs,
        _cachedFilesPrefKey,
        LocalPrivateCacheCodec.cachedFilesNamespace,
      ).replace(payload);
    } catch (_) {
      if (kDebugMode) {
        debugPrint('Encrypted cached file metadata could not be persisted.');
      }
      _logRuntime(
        'files',
        'Encrypted cached file metadata could not be persisted.',
      );
    }
  }

  Future<bool> _restoreCachedFilesFromPreferences() async {
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      _prefs ??= prefs;
      final cacheRead = await _readPrivateCachePreference(
        prefs,
        baseKey: _cachedFilesPrefKey,
        namespace: LocalPrivateCacheCodec.cachedFilesNamespace,
      );
      final raw = cacheRead.value;
      if (cacheRead.temporarilyUnavailable) {
        _logRuntime(
          'files',
          'Encrypted cached files are waiting for the device credential store.',
        );
        return false;
      }
      if (cacheRead.discardedCorruptValue) {
        _logRuntime(
          'files',
          'Unreadable or unprotectable cached file metadata was removed.',
        );
      }
      if (cacheRead.decodedRows == null && (raw == null || raw.trim().isEmpty)) {
        return false;
      }

      final decoded = cacheRead.decodedRows ?? jsonDecode(raw!);
      if (decoded is! List) {
        return false;
      }

      final cachedFiles = <_DriveFile>[];
      final personalCachedFileIds = <String>{};
      final assignedCachedFileIds = <String>{};
      var skippedFiles = 0;
      for (final entry in decoded) {
        if (entry is! Map) {
          skippedFiles++;
          continue;
        }
        try {
          final cacheEntry = Map<String, dynamic>.from(entry);
          final file = _DriveFile.fromLocalCacheJson(cacheEntry);
          cachedFiles.add(file);
          final rawMembership = cacheEntry['_localSourceMembership'];
          final memberships = rawMembership is List
              ? rawMembership.whereType<String>().toSet()
              : const <String>{};
          if (memberships.contains(WorkspaceSnapshotSource.personal.name)) {
            personalCachedFileIds.add(file.id);
          }
          if (memberships.contains(
            WorkspaceSnapshotSource.assignedBusiness.name,
          )) {
            assignedCachedFileIds.add(file.id);
          }
          if (memberships.isEmpty) {
            final fallbackSource = _snapshotSourceForFile(file);
            if (fallbackSource == WorkspaceSnapshotSource.personal) {
              personalCachedFileIds.add(file.id);
            } else {
              assignedCachedFileIds.add(file.id);
            }
          }
        } catch (_) {
          skippedFiles++;
        }
      }

      if (_hasAppliedUserProfileState && !_canReadCompanyStorage) {
        assignedCachedFileIds.clear();
      }
      final retainedCachedFiles = cachedFiles
          .where(
            (file) =>
                personalCachedFileIds.contains(file.id) ||
                assignedCachedFileIds.contains(file.id),
          )
          .toList(growable: false);
      if (retainedCachedFiles.isEmpty) {
        _fileSnapshotSources.replace(
          WorkspaceSnapshotSource.personal,
          const <_DriveFile>[],
          idOf: (file) => file.id,
        );
        _fileSnapshotSources.replace(
          WorkspaceSnapshotSource.assignedBusiness,
          const <_DriveFile>[],
          idOf: (file) => file.id,
        );
        _scheduleCachedFilesPersist();
        return false;
      }

      final resolvedFiles =
          retainedCachedFiles.any(_fileNeedsLocalNameDecryption)
          ? await _maybeDecryptFileNames(retainedCachedFiles)
          : retainedCachedFiles;
      _fileSnapshotSources.replace(
        WorkspaceSnapshotSource.personal,
        resolvedFiles.where((file) => personalCachedFileIds.contains(file.id)),
        idOf: (file) => file.id,
      );
      _fileSnapshotSources.replace(
        WorkspaceSnapshotSource.assignedBusiness,
        resolvedFiles.where((file) => assignedCachedFileIds.contains(file.id)),
        idOf: (file) => file.id,
      );
      resolvedFiles.sort(_compareDriveFiles);

      final nextFilesById = <String, _DriveFile>{
        for (final file in resolvedFiles) file.id: file,
      };
      final computedUsage = resolvedFiles
          .fold<int>(0, (total, file) => total + file.size)
          .toDouble();
      final totals = _calculateUsageTotals(computedUsage: computedUsage);

      if (!mounted) {
        _files
          ..clear()
          ..addAll(resolvedFiles);
        _filesById
          ..clear()
          ..addAll(nextFilesById);
        _fileUsageBytes = computedUsage;
        _usedBytes = totals.used;
        _totalBytes = totals.total;
        _loadingFiles = false;
      } else {
        setState(() {
          _files
            ..clear()
            ..addAll(resolvedFiles);
          _filesById
            ..clear()
            ..addAll(nextFilesById);
          _fileUsageBytes = computedUsage;
          _usedBytes = totals.used;
          _totalBytes = totals.total;
          _loadingFiles = false;
        });
      }

      _logRuntime(
        'files',
        skippedFiles > 0
            ? 'Restored encrypted cached file metadata and skipped malformed '
                  'cached entries.'
            : 'Restored encrypted cached file metadata.',
      );
      return true;
    } catch (_) {
      if (kDebugMode) {
        debugPrint('Encrypted cached file metadata could not be restored.');
      }
      _logRuntime(
        'files',
        'Encrypted cached file metadata could not be restored.',
      );
      return false;
    }
  }

  void _addPendingBytes(int bytes) {
    if (bytes <= 0) {
      return;
    }
    final pending = _pendingUploadBytes + bytes;
    if (!mounted) {
      _pendingUploadBytes = pending;
      return;
    }
    final totals = _calculateUsageTotals(pendingBytes: pending);
    setState(() {
      _pendingUploadBytes = pending;
      _usedBytes = totals.used;
      _totalBytes = totals.total;
    });
  }

  void _removePendingBytes(int bytes) {
    if (bytes <= 0) {
      return;
    }
    final pending = max(0.0, _pendingUploadBytes - bytes);
    if (!mounted) {
      _pendingUploadBytes = pending;
      return;
    }
    final totals = _calculateUsageTotals(pendingBytes: pending);
    setState(() {
      _pendingUploadBytes = pending;
      _usedBytes = totals.used;
      _totalBytes = totals.total;
    });
  }

  Future<void> _applyBandwidthLimit(int bytes) async {
    final limit = _uploadBandwidthLimitBytesPerSecond;
    if (limit == null || limit <= 0 || bytes <= 0) {
      _bandwidthLastTokenTime = DateTime.now();
      return;
    }

    final now = DateTime.now();
    final last = _bandwidthLastTokenTime;
    if (last != null) {
      final elapsedSeconds = now.difference(last).inMicroseconds / 1000000.0;
      if (elapsedSeconds > 0) {
        _bandwidthTokens = min(
          limit.toDouble(),
          _bandwidthTokens + elapsedSeconds * limit,
        );
      }
    } else {
      _bandwidthTokens = limit.toDouble();
    }

    double required = bytes.toDouble();
    if (_bandwidthTokens >= required) {
      _bandwidthTokens -= required;
      _bandwidthLastTokenTime = now;
      return;
    }

    required -= _bandwidthTokens;
    _bandwidthTokens = 0.0;
    final waitSeconds = required / limit;
    final waitDuration = Duration(milliseconds: (waitSeconds * 1000).ceil());
    if (waitDuration > Duration.zero) {
      await Future<void>.delayed(waitDuration);
    }
    _bandwidthLastTokenTime = DateTime.now();
  }

  Future<void> _updateBandwidthLimit(int value) async {
    final normalized = value <= 0 ? null : value;
    if (!mounted) {
      _uploadBandwidthLimitBytesPerSecond = normalized;
      _bandwidthTokens = 0;
      _bandwidthLastTokenTime = null;
      await _persistBandwidthLimit();
      return;
    }
    setState(() {
      _uploadBandwidthLimitBytesPerSecond = normalized;
      _bandwidthTokens = 0;
      _bandwidthLastTokenTime = null;
    });
    await _persistBandwidthLimit();
    if (normalized == null) {
      _showMessage('Uploads will use the maximum bandwidth available.');
    } else {
      _showMessage(
        'Uploads will be limited to ${_formatBandwidthLimit(normalized)}.',
      );
    }
  }

  int get _selectedBandwidthOptionValue {
    final limit = _uploadBandwidthLimitBytesPerSecond;
    if (limit == null || limit <= 0) {
      return 0;
    }
    for (final option in _bandwidthLimitOptions) {
      if (option.value == limit) {
        return limit;
      }
    }
    return _customBandwidthOptionValue;
  }

  String _editableBandwidthValue(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'[.]$'), '');
  }

  int? _parseCustomBandwidthLimit(String rawValue, _BandwidthLimitUnit unit) {
    final normalized = rawValue.trim().replaceAll(',', '.');
    final value = double.tryParse(normalized);
    if (value == null || !value.isFinite || value <= 0) {
      return null;
    }
    final bytes = value * unit.bytesPerSecond;
    if (!bytes.isFinite ||
        bytes < _minimumCustomBandwidthBytesPerSecond ||
        bytes > _maximumCustomBandwidthBytesPerSecond) {
      return null;
    }
    return bytes.round();
  }

  Future<void> _showCustomBandwidthLimitDialog({
    required VoidCallback onUpdated,
  }) async {
    final currentLimit = _uploadBandwidthLimitBytesPerSecond;
    var unit = currentLimit != null && currentLimit < _bytesPerMb
        ? _BandwidthLimitUnit.kilobytesPerSecond
        : _BandwidthLimitUnit.megabytesPerSecond;
    final initialBytes = currentLimit ?? (2 * _bytesPerMb).round();
    final valueController = TextEditingController(
      text: _editableBandwidthValue(initialBytes / unit.bytesPerSecond),
    );
    String? validationMessage;

    try {
      final result = await showDialog<int>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              void submit() {
                final normalizedValue = valueController.text.trim().replaceAll(
                  ',',
                  '.',
                );
                final numericValue = double.tryParse(normalizedValue);
                String? nextValidationMessage;
                if (numericValue == null || !numericValue.isFinite) {
                  nextValidationMessage = 'Enter a valid number.';
                } else if (numericValue <= 0) {
                  nextValidationMessage = 'Enter a value greater than zero.';
                } else {
                  final bytes = numericValue * unit.bytesPerSecond;
                  if (bytes < _minimumCustomBandwidthBytesPerSecond) {
                    nextValidationMessage = 'The minimum limit is 1 KB/s.';
                  } else if (bytes > _maximumCustomBandwidthBytesPerSecond) {
                    nextValidationMessage = 'The maximum limit is 10 GB/s.';
                  }
                }

                final parsed = _parseCustomBandwidthLimit(
                  valueController.text,
                  unit,
                );
                if (nextValidationMessage != null || parsed == null) {
                  setDialogState(() {
                    validationMessage =
                        nextValidationMessage ??
                        'Enter a valid bandwidth limit.';
                  });
                  return;
                }
                Navigator.of(dialogContext).pop(parsed);
              }

              return AlertDialog(
                title: const Text('Custom upload bandwidth'),
                content: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Set the maximum bandwidth RonikCloud may use while uploading.',
                      ),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextField(
                              key: const ValueKey<String>(
                                'custom-upload-bandwidth-value',
                              ),
                              controller: valueController,
                              autofocus: true,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9.,]'),
                                ),
                              ],
                              decoration: const InputDecoration(
                                labelText: 'Upload limit',
                                border: OutlineInputBorder(),
                              ),
                              onSubmitted: (_) => submit(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 116,
                            child: DropdownButtonFormField<_BandwidthLimitUnit>(
                              initialValue: unit,
                              decoration: const InputDecoration(
                                labelText: 'Unit',
                                border: OutlineInputBorder(),
                              ),
                              items: [
                                for (final option in _BandwidthLimitUnit.values)
                                  DropdownMenuItem<_BandwidthLimitUnit>(
                                    value: option,
                                    child: Text(option.label),
                                  ),
                              ],
                              onChanged: (value) {
                                if (value == null) {
                                  return;
                                }
                                setDialogState(() {
                                  unit = value;
                                  validationMessage = null;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Allowed range: 1 KB/s to 10 GB/s.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (validationMessage != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          validationMessage!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: submit,
                    child: const Text('Save limit'),
                  ),
                ],
              );
            },
          );
        },
      );
      if (result == null) {
        return;
      }
      await _updateBandwidthLimit(result);
      onUpdated();
    } finally {
      valueController.dispose();
    }
  }

  bool get _isDesktopPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  Future<void> _persistBandwidthLimit() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final limit = _uploadBandwidthLimitBytesPerSecond;
    await prefs.setInt(
      _uploadBandwidthLimitPrefKey,
      limit == null || limit <= 0 ? 0 : limit,
    );
  }

  String _formatBandwidthLimit(int bytesPerSecond) {
    if (bytesPerSecond >= _bytesPerGb) {
      final value = bytesPerSecond / _bytesPerGb;
      return '${_editableBandwidthValue(value)} GB/s';
    }
    if (bytesPerSecond >= _bytesPerMb) {
      final value = bytesPerSecond / _bytesPerMb;
      return '${_editableBandwidthValue(value)} MB/s';
    }
    if (bytesPerSecond >= _bytesPerKb) {
      final value = bytesPerSecond / _bytesPerKb;
      return '${_editableBandwidthValue(value)} KB/s';
    }
    return '$bytesPerSecond B/s';
  }

  Future<void> _refresh() async {
    await _tryConfigureStorageFromProvisionedCredentials(forceRefresh: true);
    await _retryFileDecryption();
    _maybePromptForSecureRefresh();
  }

  void _maybePromptForSecureRefresh() {
    if (!mounted || _secureRefreshPromptActive) {
      return;
    }
    final now = DateTime.now().toUtc();
    final staleCount = _files
        .where((file) => !file.isFolder && file.isSecureRefreshOverdue(now))
        .length;
    if (staleCount == 0) {
      return;
    }

    _secureRefreshPromptActive = true;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger
        .showSnackBar(
          SnackBar(
            content: Text(
              staleCount == 1
                  ? 'A secure file needs a quick activity refresh.'
                  : '$staleCount secure files need a quick activity refresh.',
            ),
            duration: const Duration(seconds: 10),
            action: SnackBarAction(
              label: 'Refresh',
              onPressed: () => unawaited(_refreshSecureFiles()),
            ),
          ),
        )
        .closed
        .whenComplete(() {
          _secureRefreshPromptActive = false;
        });
  }

  Future<String?> _collectSecureRefreshEncryptionKey() async {
    final passphrase = await _collectEncryptionKey(
      isRotation: false,
      forcePrompt: true,
    );
    if (!mounted || passphrase == null) {
      return null;
    }

    var salt = _secureEncryptionSalt;
    if (salt == null || salt.isEmpty) {
      try {
        final doc = await widget.firestore
            .collection('users')
            .doc(widget.user.uid)
            .get();
        final rawSalt = doc.data()?['secureEncryptionSalt'];
        if (rawSalt is String && rawSalt.trim().isNotEmpty) {
          salt = Uint8List.fromList(base64Decode(rawSalt.trim()));
          if (mounted) {
            setState(() {
              _secureEncryptionSalt = salt;
            });
          } else {
            _secureEncryptionSalt = salt;
          }
        }
      } catch (_) {
        if (kDebugMode) {
          debugPrint('[ENCRYPTION] Secure parameters were unavailable.');
        }
      }
    }

    if (salt == null || salt.isEmpty) {
      _showMessage('Secure mode needs setup before files can be refreshed.');
      return null;
    }

    final key = await EncryptionService.instance.deriveKey(
      password: passphrase,
      salt: salt,
    );
    final keyString = base64Encode(await key.extractBytes());
    _DriveFile? probe;
    for (final file in _files) {
      final encryptedName = file.encryptedName?.trim();
      if (file.isSecured && encryptedName != null && encryptedName.isNotEmpty) {
        probe = file;
        break;
      }
    }

    if (probe != null) {
      final name = await _decryptFileDisplayName(
        probe,
        encryptionKey: keyString,
      );
      if (name == null || name.isEmpty) {
        _showMessage('That passphrase did not unlock secure files.');
        return null;
      }
    }

    _secureSessionPassphrase = passphrase;
    _cachedSecureEncryptionKey = keyString;
    return keyString;
  }

  Future<void> _refreshSecureFiles() async {
    final now = DateTime.now().toUtc();
    final targets = _files
        .where((file) => !file.isFolder && file.isSecureRefreshOverdue(now))
        .toList(growable: false);
    if (targets.isEmpty) {
      _showMessage('Secure files are already fresh.');
      return;
    }

    final keyString = await _collectSecureRefreshEncryptionKey();
    if (keyString == null || !mounted) {
      return;
    }

    final refreshedAt = DateTime.now().toUtc();
    final dueAt = refreshedAt.add(_secureRefreshInterval);
    const chunkSize = 450;
    for (var start = 0; start < targets.length; start += chunkSize) {
      final batch = widget.firestore.batch();
      final end = min(start + chunkSize, targets.length);
      for (final file in targets.sublist(start, end)) {
        batch.update(widget.firestore.collection('files').doc(file.id), {
          'secureRefreshedAt': Timestamp.fromDate(refreshedAt),
          'secureRefreshDueAt': Timestamp.fromDate(dueAt),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }

    _showMessage('Secure files refreshed for 90 days.');
  }

  Future<void> _showUploadSheet() async {
    if (!_ensureStorageWritesAvailable()) {
      return;
    }
    if (_isUploading || _transferController.uploadIntentActive) {
      _showMessage(
        'Please wait for the current upload or encryption unlock to finish.',
      );
      return;
    }

    if (_openingUploadSheet) {
      return;
    }

    if (mounted) {
      setState(() {
        _openingUploadSheet = true;
      });
    }

    try {
      final storageReady = await _ensureStorageConfigured();
      if (!mounted) {
        return;
      }

      if (!storageReady) {
        return;
      }

      final currentPathLabel = _workspacePathLabel();

      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: const Text('Upload to Drive'),
                  subtitle: Text('Current location: $currentPathLabel'),
                ),
                ListTile(
                  leading: const Icon(Icons.upload_file),
                  title: const Text('Files'),
                  subtitle: Text('Upload into $currentPathLabel'),
                  onTap: () {
                    Navigator.of(context).pop();
                    unawaited(
                      _pickAndUploadFiles(
                        fileType: FileType.any,
                        targetFolderId: _activeFolderId,
                      ),
                    );
                  },
                ),
                if (IosPhotoLibrary.supported)
                  ListTile(
                    leading: const Icon(Icons.photo_library_outlined),
                    title: const Text('Photos'),
                    subtitle: Text(
                      'Choose photos to upload into $currentPathLabel',
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      unawaited(_pickAndUploadPhotos());
                    },
                  ),
                if (_passphraseRequired && !_activeStorageUsesMemberEnvelopes)
                  ListTile(
                    leading: const Icon(Icons.enhanced_encryption_outlined),
                    title: const Text('Secure files'),
                    subtitle: Text(
                      'Upload locked, sharded files into $currentPathLabel',
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      unawaited(
                        _pickAndUploadFiles(
                          fileType: FileType.any,
                          targetFolderId: _activeFolderId,
                          secureUpload: true,
                        ),
                      );
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.drive_folder_upload_outlined),
                  title: const Text('Folder'),
                  subtitle: Text(
                    'Upload a folder into $currentPathLabel and keep its structure.',
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    unawaited(
                      _pickAndUploadFolder(targetFolderId: _activeFolderId),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.drive_folder_upload_outlined),
                  title: const Text('Import from cloud'),
                  subtitle: const Text(
                    'Connect Google Drive, OneDrive, Dropbox, or iCloud.',
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    unawaited(_showDriveMigrationOverlay());
                  },
                ),
              ],
            ),
          );
        },
      );
    } finally {
      if (mounted) {
        setState(() {
          _openingUploadSheet = false;
        });
      }
    }
  }

  Future<void> _pickAndUploadPhotos() => _runUploadIntent(() async {
    final targetFolderId = _activeFolderId;
    List<IosPhotoExport> photos = [];
    try {
      photos = await IosPhotoLibrary.pick();
      if (!mounted || photos.isEmpty || _sessionInvalidated) return;
      await _handlePreparedUpload(
        photos
            .map(
              (photo) => _PreparedUploadFile(
                file: XFile(photo.path, name: photo.name),
                displayName: photo.name,
              ),
            )
            .toList(growable: false),
        targetFolderId: targetFolderId,
      );
    } catch (error) {
      if (mounted) {
        _showMessage(
          'Could not upload the selected photos. Check your connection and device storage, then try again.',
        );
      }
    } finally {
      for (final photo in photos) {
        try {
          await IosPhotoLibrary.release(photo);
        } catch (_) {
          // Native expiry also removes exports after interrupted cleanup.
        }
      }
    }
  });

  Future<void> _runUploadIntent(Future<void> Function() action) async {
    if (!_transferController.tryStartUploadIntent()) {
      _showMessage(
        'Please wait for the current upload or encryption unlock to finish.',
      );
      return;
    }
    try {
      await action();
    } finally {
      _transferController.finishUploadIntent();
    }
  }

  Future<void> _pickAndUploadFiles({
    required FileType fileType,
    _FolderSummary? targetFolder,
    String? targetFolderId,
    bool secureUpload = false,
  }) => _runUploadIntent(
    () => _pickAndUploadFilesWithinIntent(
      fileType: fileType,
      targetFolder: targetFolder,
      targetFolderId: targetFolderId,
      secureUpload: secureUpload,
    ),
  );

  Future<void> _pickAndUploadFilesWithinIntent({
    required FileType fileType,
    _FolderSummary? targetFolder,
    String? targetFolderId,
    bool secureUpload = false,
  }) async {
    if (kIsWeb) {
      // Open the native chooser while this call still has the browser's user
      // activation. Awaiting an unlock first causes Safari/WebKit to block the
      // chooser, especially for image/photo selections. Picking retains only
      // local File handles; no bytes are read until encryption is ready.
      final preparedFiles = await _collectWebUploadItems(fileType: fileType);
      if (preparedFiles.isEmpty) {
        _showMessage('No files selected.');
        return;
      }
      if (!await _ensureWebUploadEncryptionReady(secureUpload: secureUpload)) {
        return;
      }

      await _handlePreparedUpload(
        preparedFiles,
        targetFolder: targetFolder,
        targetFolderId: targetFolderId,
        secureUpload: secureUpload,
      );
      return;
    }

    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: false,
        withReadStream: true,
        type: fileType,
        allowCompression: false,
      );
    } on Exception catch (_) {
      if (kDebugMode) {
        debugPrint('The file picker was unavailable.');
      }
      _showMessage('We couldn\'t open the file picker. Please try again.');
      return;
    }

    if (result == null || result.files.isEmpty) {
      _showMessage('No files selected.');
      return;
    }

    final preparedFiles = <_PreparedUploadFile>[];
    for (final file in result.files) {
      if (kIsWeb && file.bytes != null) {
        final bytes = file.bytes!;
        preparedFiles.add(
          _PreparedUploadFile(
            file: XFile.fromData(bytes, name: file.name, length: bytes.length),
            sizeBytes: bytes.length,
          ),
        );
      } else if (kIsWeb && file.readStream != null) {
        final stream = file.readStream!;
        preparedFiles.add(
          _PreparedUploadFile(
            file: XFile.fromData(
              Uint8List(0),
              name: file.name,
              length: file.size,
            ),
            sizeBytes: file.size,
            readStreamFactory: () => stream,
            displayName: file.name,
          ),
        );
      } else if (file.path != null) {
        preparedFiles.add(
          _PreparedUploadFile(file: XFile(file.path!, name: file.name)),
        );
      }
    }

    await _handlePreparedUpload(
      preparedFiles,
      targetFolder: targetFolder,
      targetFolderId: targetFolderId,
      secureUpload: secureUpload,
    );
  }

  Future<bool> _ensureWebUploadEncryptionReady({
    required bool secureUpload,
  }) async {
    if (!kIsWeb) {
      return true;
    }

    final key = secureUpload && !_activeStorageUsesMemberEnvelopes
        ? await _ensureSecureEncryptionKey(interactive: true)
        : await _requireUploadEncryptionKey(interactive: true);
    return mounted && key != null;
  }

  Future<int> _preparedUploadLength(_PreparedUploadFile preparedFile) async {
    final bytes = preparedFile.bytes;
    if (bytes != null) {
      return bytes.length;
    }
    final knownSize = preparedFile.sizeBytes;
    if (knownSize != null) {
      return knownSize;
    }
    if (preparedFile.readStreamFactory != null) {
      return 0;
    }
    if (kIsWeb) {
      return (await preparedFile.file.readAsBytes()).length;
    }
    return preparedFile.file.length();
  }

  Stream<List<int>> _preparedUploadReadStream(
    _PreparedUploadFile preparedFile, {
    required int size,
  }) {
    final bytes = preparedFile.bytes;
    if (bytes != null) {
      return Stream<List<int>>.value(bytes);
    }
    final readStreamFactory = preparedFile.readStreamFactory;
    if (readStreamFactory != null) {
      return readStreamFactory();
    }
    if (kIsWeb) {
      return preparedFile.file.openRead(0, size);
    }
    return preparedFile.file.openRead();
  }

  Future<Uint8List?> _capturePreparedImageUploadSource(
    _PreparedUploadFile preparedFile, {
    required int expectedLength,
  }) async {
    final bytes = preparedFile.bytes;
    if (bytes != null) {
      if (!ImageThumbnailPolicy.allowsSourceBytes(bytes.length) ||
          bytes.length != expectedLength) {
        return null;
      }
      return bytes;
    }

    final boundedReadStreamFactory = preparedFile.boundedReadStreamFactory;
    if (boundedReadStreamFactory != null) {
      return captureBoundedImageUploadSource(
        expectedLength: expectedLength,
        sourceLength: () async => expectedLength,
        openRead: boundedReadStreamFactory,
      );
    }

    // A generic stream factory cannot promise a bounded read. File-backed
    // sources can, while an unbounded custom source uploads without a preview.
    if (preparedFile.readStreamFactory != null) {
      return null;
    }
    return captureBoundedImageUploadSource(
      expectedLength: expectedLength,
      sourceLength: preparedFile.file.length,
      openRead: (endExclusive) => preparedFile.file.openRead(0, endExclusive),
    );
  }

  Future<void> _pickAndUploadFolder({
    _FolderSummary? targetFolder,
    String? targetFolderId,
  }) => _runUploadIntent(
    () => _pickAndUploadFolderWithinIntent(
      targetFolder: targetFolder,
      targetFolderId: targetFolderId,
    ),
  );

  Future<void> _pickAndUploadFolderWithinIntent({
    _FolderSummary? targetFolder,
    String? targetFolderId,
  }) async {
    if (kIsWeb) {
      // Keep directory selection inside the originating click. Encryption is
      // still required before the selected local files are opened or read.
      final preparedFiles = await _collectWebFolderUploadItems();
      if (preparedFiles.isEmpty) {
        _showMessage('No files were found in that folder.');
        return;
      }
      if (!await _ensureWebUploadEncryptionReady(secureUpload: false)) {
        return;
      }

      await _handlePreparedUpload(
        preparedFiles,
        targetFolder: targetFolder,
        targetFolderId: targetFolderId,
      );
      return;
    }

    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      _showMessage(
        'Folder uploads are not available on this device yet. '
        'Choose individual files or photos to upload.',
      );
      return;
    }
    String? selectedPath;
    try {
      selectedPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select a folder to upload',
      );
    } on Exception catch (_) {
      if (kDebugMode) {
        debugPrint('The folder picker was unavailable.');
      }
      _showMessage('We couldn\'t open the folder picker. Please try again.');
      return;
    }

    if (selectedPath == null || selectedPath.trim().isEmpty) {
      _showMessage('No folder selected.');
      return;
    }

    final preparedFiles = await _collectFolderUploadItems(selectedPath);
    if (preparedFiles.isEmpty) {
      _showMessage('No files were found in that folder.');
      return;
    }

    await _handlePreparedUpload(
      preparedFiles,
      targetFolder: targetFolder,
      targetFolderId: targetFolderId,
    );
  }

  Future<List<_PreparedUploadFile>> _collectWebUploadItems({
    required FileType fileType,
  }) async {
    final picked = await web_folder_picker.pickWebUploadFiles(
      accept: _webAcceptForFileType(fileType),
    );
    if (picked.isEmpty) {
      return const <_PreparedUploadFile>[];
    }

    final preparedFiles = <_PreparedUploadFile>[];
    for (final file in picked) {
      final fileName = _sanitizeFileName(file.name.trim());
      if (fileName.isEmpty) {
        continue;
      }
      preparedFiles.add(
        _PreparedUploadFile(
          file: XFile.fromData(
            Uint8List(0),
            name: fileName,
            mimeType: file.mimeType,
            length: file.sizeBytes,
          ),
          sizeBytes: file.sizeBytes,
          readStreamFactory: () => file.openRead(),
          boundedReadStreamFactory: (endExclusive) =>
              file.openRead(0, endExclusive),
          displayName: fileName,
          mimeType: file.mimeType,
        ),
      );
    }
    return preparedFiles;
  }

  String _webAcceptForFileType(FileType fileType) {
    switch (fileType) {
      case FileType.audio:
        return 'audio/*';
      case FileType.image:
        return 'image/*';
      case FileType.video:
        return 'video/*';
      case FileType.media:
        return 'image/*,video/*';
      case FileType.any:
      case FileType.custom:
        return '';
    }
  }

  Future<List<_PreparedUploadFile>> _collectWebFolderUploadItems() async {
    final picked = await web_folder_picker.pickWebFolderUploadFiles();
    if (picked.isEmpty) {
      return const <_PreparedUploadFile>[];
    }

    final preparedFiles = <_PreparedUploadFile>[];
    for (final file in picked) {
      final relativeSegments = file.relativePath
          .split(RegExp(r'[\\/]+'))
          .where((segment) => segment.trim().isNotEmpty)
          .toList(growable: false);
      final fileName = relativeSegments.isNotEmpty
          ? relativeSegments.last.trim()
          : file.name.trim();
      if (fileName.isEmpty) {
        continue;
      }
      final folderSegments = relativeSegments.length <= 1
          ? const <String>[]
          : relativeSegments
                .take(relativeSegments.length - 1)
                .map(_sanitizePathSegment)
                .where((segment) => segment.isNotEmpty)
                .toList(growable: false);
      preparedFiles.add(
        _PreparedUploadFile(
          file: XFile.fromData(
            Uint8List(0),
            name: fileName,
            mimeType: file.mimeType,
            length: file.sizeBytes,
          ),
          relativeFolderSegments: folderSegments,
          sizeBytes: file.sizeBytes,
          readStreamFactory: () => file.openRead(),
          boundedReadStreamFactory: (endExclusive) =>
              file.openRead(0, endExclusive),
          mimeType: file.mimeType,
        ),
      );
    }

    preparedFiles.sort((a, b) {
      final aPath = <String>[
        ...a.relativeFolderSegments,
        a.file.name,
      ].join('/');
      final bPath = <String>[
        ...b.relativeFolderSegments,
        b.file.name,
      ].join('/');
      return aPath.toLowerCase().compareTo(bPath.toLowerCase());
    });
    return preparedFiles;
  }

  Future<List<_PreparedUploadFile>> _collectFolderUploadItems(
    String rootPath,
  ) async {
    if (kIsWeb) {
      return const <_PreparedUploadFile>[];
    }

    final directory = Directory(rootPath);
    if (!await directory.exists()) {
      return const <_PreparedUploadFile>[];
    }

    final rootNameCandidate = p.basename(rootPath).trim();
    final rootName = _sanitizePathSegment(
      rootNameCandidate.isEmpty ? 'Folder' : rootNameCandidate,
    );
    final preparedFiles = <_PreparedUploadFile>[];

    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) {
        continue;
      }
      final relativePath = p.relative(entity.path, from: rootPath);
      final relativeSegments = relativePath
          .split(Platform.pathSeparator)
          .where((segment) => segment.trim().isNotEmpty)
          .toList(growable: false);
      if (relativeSegments.isEmpty) {
        continue;
      }

      final parentSegments = relativeSegments.length <= 1
          ? const <String>[]
          : relativeSegments
                .take(relativeSegments.length - 1)
                .map(_sanitizePathSegment)
                .where((segment) => segment.isNotEmpty)
                .toList(growable: false);
      final fileName = relativeSegments.last.trim();
      if (fileName.isEmpty) {
        continue;
      }

      preparedFiles.add(
        _PreparedUploadFile(
          file: XFile(entity.path, name: fileName),
          relativeFolderSegments: <String>[
            if (rootName.isNotEmpty) rootName,
            ...parentSegments,
          ],
        ),
      );
    }

    preparedFiles.sort((a, b) {
      final aPath = <String>[
        ...a.relativeFolderSegments,
        a.file.name,
      ].join('/');
      final bPath = <String>[
        ...b.relativeFolderSegments,
        b.file.name,
      ].join('/');
      return aPath.toLowerCase().compareTo(bPath.toLowerCase());
    });
    return preparedFiles;
  }

  Future<List<_PreparedUploadFile>> _expandDroppedUploadItems(
    List<XFile> items,
  ) async {
    if (items.isEmpty) {
      return const <_PreparedUploadFile>[];
    }
    if (kIsWeb) {
      final preparedFiles = <_PreparedUploadFile>[];
      for (final file in items) {
        final size = await file.length();
        preparedFiles.add(
          _PreparedUploadFile(
            file: file,
            sizeBytes: size,
            readStreamFactory: file.openRead,
            boundedReadStreamFactory: (endExclusive) =>
                file.openRead(0, endExclusive),
            mimeType: file.mimeType,
          ),
        );
      }
      return preparedFiles;
    }

    final preparedFiles = <_PreparedUploadFile>[];
    for (final item in items) {
      final path = item.path;
      if (path.isEmpty) {
        preparedFiles.add(_PreparedUploadFile(file: item));
        continue;
      }

      final entityType = await FileSystemEntity.type(path, followLinks: false);
      if (entityType == FileSystemEntityType.directory) {
        preparedFiles.addAll(await _collectFolderUploadItems(path));
        continue;
      }

      preparedFiles.add(_PreparedUploadFile(file: item));
    }
    return preparedFiles;
  }

  void _requestForegroundUploadCancel() {
    if (!_isUploading || _transferController.foregroundUploadId == null) {
      return;
    }
    _transferController.requestCancel();
    if (UploadCoordinator.enabled) UploadCoordinator.instance.cancelAll();
    _updateTransfer(
      _transferController.foregroundUploadId!,
      'Canceling upload after the current file...',
    );
    _showMessage('Upload cancel requested. The current file may finish.');
  }

  _DriveFile? _existingFileNamed(String name, String? folderId) {
    final normalizedName = name.trim().toLowerCase();
    final normalizedFolderId = _normalizeFolderId(folderId);
    for (final file in _files) {
      if (!file.isActive || !_fileMatchesActiveStorageSpace(file)) continue;
      if (file.name.trim().toLowerCase() != normalizedName) continue;
      if (_normalizeFolderId(_resolvedFolderKeyForFile(file)) ==
          normalizedFolderId) {
        return file;
      }
      if (normalizedFolderId == null &&
          _resolvedFolderKeyForFile(file) == 'root') {
        return file;
      }
    }
    return null;
  }

  Future<_UploadCollisionChoice> _promptUploadCollision(
    _DriveFile existing,
  ) async {
    if (!mounted) return _UploadCollisionChoice.cancel;
    return await showDialog<_UploadCollisionChoice>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('A file with this name already exists'),
            content: Text(
              'Keep both files, or replace "${existing.name}" while retaining its encrypted object as a restorable version?',
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, _UploadCollisionChoice.cancel),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, _UploadCollisionChoice.keepBoth),
                child: const Text('Keep both'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(
                  context,
                  _UploadCollisionChoice.replaceAsVersion,
                ),
                child: const Text('Replace safely'),
              ),
            ],
          ),
        ) ??
        _UploadCollisionChoice.cancel;
  }

  Future<void> _handlePreparedUpload(
    List<_PreparedUploadFile> files, {
    _FolderSummary? targetFolder,
    String? targetFolderId,
    bool secureUpload = false,
    bool batchAdmitted = false,
  }) async {
    if (files.isEmpty) return;
    if (!_ensureWorkspaceMutationReady()) return;
    if (!_ensureStorageWritesAvailable()) return;
    final hasExplicitTarget = targetFolder != null || targetFolderId != null;
    final rawTargetId = targetFolder?.id ?? targetFolderId;
    final effectiveFolderId = hasExplicitTarget
        ? _normalizeFolderId(rawTargetId)
        : _normalizeFolderId(_activeFolderId);
    String resumeContextFor(_PreparedUploadFile file) => uploadResumeContext(
      uid: widget.user.uid,
      storageScope: _activeStorageScope,
      groupId: _activeStorageGroupId,
      folderId: effectiveFolderId,
      relativeFolders: file.relativeFolderSegments.map(_sanitizePathSegment)
          .where((segment) => segment.isNotEmpty).toList(growable: false),
      secure: secureUpload,
    );
    final uploadTargetLabel = _workspacePathLabelForFolder(
      effectiveFolderId,
      fallbackLabel:
          targetFolder?.displayName ??
          (hasExplicitTarget ? null : _activeFolderLabel),
    );
    _logRuntime('upload', 'Starting an encrypted foreground upload.');

    var totalUploadSize = 0;
    for (final file in files) {
      totalUploadSize += await _preparedUploadLength(file);
    }

    // Check storage limit before starting a batch upload.
    if (!UploadCoordinator.enabled && _storageHasLimit && _storageLimitBytes != null) {
      if (!_ensureStorageCapacityForBytes(
        totalUploadSize,
        actionLabel: 'Upload',
      )) {
        return;
      }
    }

    final storageReady = await _ensureStorageConfigured();

    if (!mounted) {
      return;
    }

    if (!storageReady) {
      _logRuntime(
        'upload',
        'Upload aborted because storage is not configured yet.',
      );
      return;
    }

    final authenticated = await _ensureAuthenticated(interactive: true);
    if (!authenticated) {
      _logRuntime('upload', 'Upload aborted because authentication failed.');
      return;
    }
    final recoveryEntries = UploadCoordinator.enabled && !_activeStorageUsesMemberEnvelopes
        ? selectUploadRecoveryEntries(files.map((file) => UploadRecoverySelection(
            source: kIsWeb ? file.resolvedName : file.file.path,
            context: resumeContextFor(file), secure: secureUpload, browser: kIsWeb,
          )).toList(), _transferJournal?.pendingEntries ?? const <TransferJournalEntry>[])
        : <int, TransferJournalEntry>{};
    if (UploadCoordinator.enabled && !batchAdmitted) {
      final api = _storageService.uploadSessionApi;
      if (api == null) {
        _showMessage('Sign in again to prepare your upload.');
        return;
      }
      final algorithm = EncryptionService.instance.fileContentAlgorithm;
      final encryptedBytes = totalUploadSize + files.length *
        (algorithm.nonceLength + algorithm.macAlgorithm.macLength);
      final batchId = UploadCoordinator.instance.newId();
      final resumeSessionIds = !secureUpload
        ? recoveryEntries.values
          .where((entry) => entry.uploadCheckpoint?['sessionId'] is String)
          .map((entry) => entry.uploadCheckpoint!['sessionId'] as String).toSet().toList()
        : <String>[];
      final resumeGroupIds = secureUpload
        ? recoveryEntries.values
          .map((entry) => sha256.convert(utf8.encode('${widget.user.uid}\u0000${entry.objectKey}')).toString())
          .toSet().toList()
        : <String>[];
      while (mounted) {
        try {
          await api.call('prepare', {'batchId': batchId, 'encryptedBytes': encryptedBytes,
            if (resumeGroupIds.isNotEmpty) 'resumeGroupIds': resumeGroupIds,
            if (resumeSessionIds.isNotEmpty) 'resumeSessionIds': resumeSessionIds});
          break;
        } on UploadCapacityDecision catch (decision) {
          if (!mounted) return;
          final action = await showUploadCapacityDialog(context, decision);
          if (action != UploadCapacityAction.upgrade) {
            if (action == UploadCapacityAction.manageStorage && mounted) {
              setState(() => _workspaceDestination = 0);
            }
            return;
          }
          await _manageSubscription();
          if (!mounted) return;
          // Prepare reads the latest server entitlement, including purchases
          // completed on another device. The original file handles stay alive.
        } catch (_) {
          if (mounted) _showMessage('Could not check available space. Please retry.');
          return;
        }
      }
      if (!mounted) return;
      try {
        await UploadCoordinator.instance.inBatch(batchId, () => _handlePreparedUpload(
          files, targetFolder: targetFolder, targetFolderId: targetFolderId,
          secureUpload: secureUpload, batchAdmitted: true));
      } finally {
        try { await api.call('releaseBatch', {'batchId': batchId}); }
        catch (_) { /* The server expires unused reservations. */ }
      }
      return;
    }
    final provisionedForBrowserUpload =
        await _refreshWasabiBrowserUploadProvisioning();
    if (!provisionedForBrowserUpload) {
      _logRuntime(
        'upload',
        'Upload aborted because browser storage provisioning refresh failed.',
      );
      if (mounted) {
        _showMessage(
          'Storage permissions could not be refreshed. Try signing in again.',
        );
      }
      return;
    }
    await _ensureWasabiBrowserUploadCors();
    final twoFactorReady = await _ensureTwoFactorSession(interactive: true);
    if (!twoFactorReady) {
      _logRuntime(
        'upload',
        'Upload aborted because the security session was not verified.',
      );
      if (mounted) {
        _showMessage(
          'Security verification is required before uploading files.',
        );
      }
      return;
    }
    if (!mounted) {
      return;
    }

    BusinessEncryptionRecipientSet? businessRecipientSet;
    if (_activeStorageUsesMemberEnvelopes) {
      if (secureUpload) {
        _showMessage(
          'Shared Business spaces already use per-member encryption. '
          'Use Secure files in a private space.',
        );
        return;
      }
      final accountKeyString = await _requireUploadEncryptionKey(
        interactive: true,
      );
      if (accountKeyString == null) {
        return;
      }
      final accountProtectionKey = SecretKey(base64Decode(accountKeyString));
      try {
        final identity = await _ensureBusinessEncryptionIdentity(
          accountProtectionKey: accountProtectionKey,
        );
        businessRecipientSet = await _businessEncryptionRegistry.listRecipients(
          storageScope: _activeStorageScope,
          groupId: _activeStorageGroupId,
        );
        final currentRecipient = businessRecipientSet.recipients
            .cast<BusinessEncryptionRecipient?>()
            .firstWhere(
              (recipient) => recipient?.uid == widget.user.uid,
              orElse: () => null,
            );
        if (!businessRecipientSet.isComplete ||
            currentRecipient == null ||
            currentRecipient.keyId != identity.keyId) {
          final missingCount = businessRecipientSet.missingUids.length;
          _showMessage(
            missingCount == 0
                ? 'Business encryption is still synchronizing. Try again in a moment.'
                : '$missingCount authorized member${missingCount == 1 ? '' : 's'} '
                      '${missingCount == 1 ? 'needs' : 'need'} to open the '
                      'Business workspace once before shared uploads can begin.',
          );
          return;
        }
      } on BusinessEncryptionRegistryException catch (error) {
        _showMessage(error.message);
        return;
      } on BusinessEncryptionException catch (error) {
        _showMessage(error.message);
        return;
      }
    }

    setState(() {
      _isUploading = true;
    });

    _showMessage('Uploading ${files.length} item(s) to $uploadTargetLabel...');

    final successes = <String>[];
    final failures = <String>[];
    String? firstFailureReason;
    var canceledCount = 0;
    var previewRetryCount = 0;
    var finalizationRetryCount = 0;
    var permissionDeniedDuringUpload = false;

    final transferId = 'upload:${DateTime.now().millisecondsSinceEpoch}';
    var completedUploadFiles = 0;
    var uploadedBytes = 0;
    var lastProgressUpdate = DateTime.fromMillisecondsSinceEpoch(0);
    _startForegroundUploadProgress(
      transferId: transferId,
      totalFiles: files.length,
      totalBytes: totalUploadSize,
    );
    _beginTransfer(transferId, 'Uploading files...');

    void publishUploadProgress({
      int? completedFiles,
      int? transferredBytes,
      bool force = false,
    }) {
      final now = DateTime.now();
      if (!force &&
          now.difference(lastProgressUpdate) <
              const Duration(milliseconds: 180)) {
        return;
      }
      lastProgressUpdate = now;
      _updateForegroundUploadProgress(
        completedFiles: completedFiles,
        transferredBytes: transferredBytes,
      );
    }

    void markUploadItemProcessed(int size) {
      completedUploadFiles += 1;
      uploadedBytes = min(totalUploadSize, uploadedBytes + max(0, size));
      publishUploadProgress(
        completedFiles: completedUploadFiles,
        transferredBytes: uploadedBytes,
        force: true,
      );
    }

    Stream<List<int>> trackUploadStream(
      Stream<List<int>> input, {
      required int baseBytes,
      required int fileSize,
    }) async* {
      var fileBytes = 0;
      await for (final chunk in input) {
        if (_transferController.cancelRequested) {
          throw const _UploadCanceledException();
        }
        fileBytes += chunk.length;
        publishUploadProgress(
          completedFiles: completedUploadFiles,
          transferredBytes: min(totalUploadSize, baseBytes + fileBytes),
        );
        yield chunk;
      }
      publishUploadProgress(
        completedFiles: completedUploadFiles,
        transferredBytes: min(totalUploadSize, baseBytes + fileSize),
        force: true,
      );
    }

    final ensuredFolderPaths = <String, String?>{};
    try {
      final preparation = UploadPreparationGate();
      Future<void> uploadItem(int uploadIndex) async {
        final releasePreparation = await preparation.acquire();
        try {
        if (_transferController.cancelRequested) {
          canceledCount = files.length - uploadIndex;
          return;
        }

        final preparedFile = files[uploadIndex];
        final file = preparedFile.file;
        final displayName = preparedFile.resolvedName.isNotEmpty
            ? preparedFile.resolvedName
            : 'Untitled';
        final path = file.path;
        _updateTransfer(
          transferId,
          'Uploading ${uploadIndex + 1}/${files.length}: $displayName',
        );

        if (!kIsWeb && path.isEmpty) {
          _logRuntime('upload', 'Skipped an unavailable local upload source.');
          failures.add(displayName);
          markUploadItemProcessed(0);
          return;
        }

        final size = await _preparedUploadLength(preparedFile);
        final sanitized = _sanitizeFileName(displayName);
        final normalizedRelativeFolderSegments = preparedFile
            .relativeFolderSegments
            .map(_sanitizePathSegment)
            .where((segment) => segment.isNotEmpty)
            .toList(growable: false);
        final resolvedFolderId = await _ensureFolderPath(
          parentId: effectiveFolderId,
          pathSegments: normalizedRelativeFolderSegments,
          colorHex:
              targetFolder?.colorHex ??
              _findFolderById(effectiveFolderId ?? '')?.colorHex ??
              '#E8F0FE',
          createdFolderIds: ensuredFolderPaths,
        );
        String? supersedesFileId;
        final existingFile = _existingFileNamed(sanitized, resolvedFolderId);
        if (existingFile != null) {
          final collisionChoice = await _promptUploadCollision(existingFile);
          if (collisionChoice == _UploadCollisionChoice.cancel) {
            markUploadItemProcessed(size);
            return;
          }
          if (collisionChoice == _UploadCollisionChoice.replaceAsVersion) {
            supersedesFileId = existingFile.id;
          }
        }
        final resumableEntry = recoveryEntries[uploadIndex];
        final objectKey = resumableEntry?.objectKey ?? _buildObjectKey(
          '',
          folderId: resolvedFolderId,
          securedObjectKey: true,
        );
        _ensureOwnsObjectKey(objectKey);
        late final SecretKey secretKey;
        late final String resolvedName;
        Map<String, dynamic>? sharedKeyEnvelopes;
        if (businessRecipientSet != null) {
          final material = await _businessEncryptionService
              .createFileEncryptionMaterial(
                objectKey: objectKey,
                recipients: businessRecipientSet.recipients,
              );
          secretKey = material.fileKey;
          resolvedName = await EncryptionService.instance.encryptFileName(
            sanitized,
            secretKey,
          );
          sharedKeyEnvelopes = <String, dynamic>{
            for (final entry in material.envelopes.entries)
              entry.key: entry.value.toMap(),
          };
        } else {
          final encryptionKeyString = secureUpload
              ? await _ensureSecureEncryptionKey(interactive: true)
              : await _requireUploadEncryptionKey(interactive: true);
          if (encryptionKeyString == null) {
            if (secureUpload) {
              _showMessage('Unlock secure mode before secure upload.');
            }
            failures.add(displayName);
            markUploadItemProcessed(size);
            return;
          }
          secretKey = SecretKey(base64Decode(encryptionKeyString));
          resolvedName = await _encryptFileName(
            sanitized,
            encryptionKey: encryptionKeyString,
          );
        }
        final journalTransferId = resumableEntry?.id ?? '$transferId:item:$uploadIndex';
        final transferJournal = _transferJournal;
        if (resumableEntry == null) {
          await transferJournal?.begin(
          id: journalTransferId,
          kind: TransferJournalKind.upload,
          label: displayName,
          objectKey: objectKey,
          localPath: kIsWeb || path.isEmpty ? null : path,
          resumeContext: resumeContextFor(preparedFile),
          totalBytes: size,
        );
        }
        final contentType = _contentTypeForName(
          sanitized,
          fallbackMimeType: preparedFile.resolvedMimeType,
        );

        bool uploadedThumbnail = false;
        Uint8List? generatedThumbnailBytes;
        int? shardCount;
        final shouldGenerateThumbnail =
            contentType != null && contentType.startsWith('image/');
        final imageUploadSource = shouldGenerateThumbnail
            ? await _capturePreparedImageUploadSource(
                preparedFile,
                expectedLength: size,
              )
            : null;
        Stream<List<int>> readSource() => imageUploadSource == null
          ? _preparedUploadReadStream(preparedFile, size: size)
          : Stream<List<int>>.value(imageUploadSource);
        final sourceSnapshot = UploadCoordinator.enabled
          ? await UploadSourceSnapshot.capture(readSource()) : null;
        final stream = trackUploadStream(
          sourceSnapshot?.verify(readSource()) ?? readSource(),
          baseBytes: uploadedBytes,
          fileSize: size,
        );
        final sourceFingerprint = sourceSnapshot?.fingerprint;
        releasePreparation();
        var usageRecorded = false;
        var objectUploaded = false;
        _logRuntime('upload', 'Uploading an encrypted source item.');

        if (_transferController.cancelRequested) {
          await transferJournal?.cancel(journalTransferId);
          canceledCount = files.length - uploadIndex;
          return;
        }

        try {
          _ensureSessionActive();
          if (_transferController.cancelRequested) {
            throw const _UploadCanceledException();
          }
          await _applyBandwidthLimit(size);
          _addPendingBytes(size);
          generatedThumbnailBytes =
              await uploadSourceThenOptionalDerivative<Uint8List>(
                uploadSource: () async {
                  shardCount = secureUpload
                      ? await _uploadSecureShardedObject(
                          objectKey: objectKey,
                          stream: stream,
                          length: size,
                          encryptionKey: secretKey,
                          transferId: journalTransferId,
                          checkpointSink: transferJournal,
                          sourceFingerprint: sourceFingerprint,
                        )
                      : await (() async {
                          await _storageService.upload(
                            objectKey: objectKey,
                            stream: stream,
                            length: size,
                            contentType: contentType,
                            encryptionKey: secretKey,
                            transferId: journalTransferId,
                            checkpointSink: transferJournal,
                            sourceFingerprint: sourceFingerprint,
                          );
                          return null;
                        })();
                },
                afterSourceUpload: () async {
                  objectUploaded = true;
                  _updateTransfer(
                    transferId,
                    shouldGenerateThumbnail
                        ? 'Finalizing ${uploadIndex + 1}/${files.length}: '
                              'protecting image preview and metadata...'
                        : 'Finalizing ${uploadIndex + 1}/${files.length}: '
                              'protecting file metadata...',
                  );
                  await transferJournal?.updateProgress(
                    journalTransferId,
                    transferredBytes: size,
                  );
                },
                uploadDerivative: shouldGenerateThumbnail
                    ? () async {
                        final thumbnailBytes = imageUploadSource == null
                            ? null
                            : await generateBoundedImageThumbnail(
                                imageUploadSource,
                              );
                        if (thumbnailBytes != null) {
                          final thumbnailKey = _thumbnailObjectKeyFor(
                            objectKey,
                          );
                          await UploadCoordinator.instance.withoutBatch(() => _storageService.upload(
                            objectKey: thumbnailKey,
                            stream: Stream.value(thumbnailBytes),
                            length: thumbnailBytes.length,
                            contentType: imageThumbnailContentType,
                            encryptionKey: secretKey,
                          ));
                        }
                        return thumbnailBytes;
                      }
                    : null,
                derivativeTimeout: imageThumbnailDerivativeTimeout,
                onDerivativeError: (error, _) {
                  BackgroundBackupRunner.logFailure(
                    'upload',
                    'optional_image_preview',
                    error,
                  );
                },
              );
          uploadedThumbnail = generatedThumbnailBytes != null;

          final recordedAt = DateTime.now().toUtc();
          await _recordUploadedFile(
            journalTransferId: journalTransferId,
            objectKey: objectKey,
            size: size,
            folderId: resolvedFolderId,
            folderName: null,
            folderColorHex: null,
            encryptionMode: secureUpload ? 'secured' : 'standard',
            storageLayout: secureUpload ? 'sharded' : 'single',
            shardCount: shardCount,
            shardSizeBytes: secureUpload ? _secureShardSizeBytes : null,
            shardScheme: secureUpload
                ? _secureShardSchemePassphraseHmacV1
                : null,
            contentEncryption: secureUpload ? 'secure' : 'standard',
            secureContentEncoding: secureUpload
                ? _secureContentEncodingWholeFileV1
                : null,
            secureRefreshedAt: secureUpload ? recordedAt : null,
            secureRefreshDueAt: secureUpload
                ? recordedAt.add(_secureRefreshInterval)
                : null,
            uploadedAt: recordedAt,
            pathSegments: normalizedRelativeFolderSegments,
            encryptedName: resolvedName,
            displayName: displayName,
            contentType: contentType,
            hasThumbnail: uploadedThumbnail,
            supersedesFileId: supersedesFileId,
            sharedKeyEnvelopes: sharedKeyEnvelopes,
          );
          usageRecorded = true;
          await transferJournal?.complete(journalTransferId);
          if (generatedThumbnailBytes != null) {
            _thumbnailCache[objectKey] = generatedThumbnailBytes;
          }

          successes.add(displayName);
          if (shouldGenerateThumbnail && generatedThumbnailBytes == null) {
            previewRetryCount += 1;
          }
          _logRuntime('upload', 'Encrypted source upload completed.');
        } catch (error) {
          if (error is _UploadCanceledException || error is UploadFailure && error.code == 'canceled') {
            await transferJournal?.cancel(journalTransferId);
            canceledCount = files.length - uploadIndex;
            return;
          }
          var metadataQueuedForRetry = false;
          if (objectUploaded) {
            await transferJournal?.metadataCommitFailed(
              journalTransferId,
              error,
            );
            metadataQueuedForRetry =
                transferJournal?.pendingEntries.any(
                  (entry) =>
                      entry.id == journalTransferId && entry.canRetryMetadata,
                ) ??
                false;
            if (metadataQueuedForRetry) {
              finalizationRetryCount += 1;
            }
          } else {
            await transferJournal?.fail(journalTransferId, error);
          }
          if (error is _SessionExpiredException) {
            _handleSessionExpired(error);
            if (!metadataQueuedForRetry) {
              failures.add(displayName);
            }
            return;
          }
          if (_isAuthorizationError(error)) {
            _notifyUploadAuthorizationIssue();
          }
          if (!metadataQueuedForRetry) {
            firstFailureReason ??= _uploadFailureReason(error);
          }
          BackgroundBackupRunner.logFailure(
            'upload',
            metadataQueuedForRetry
                ? 'private_metadata_finalization'
                : 'encrypted_source',
            error,
          );
          if (error is FirebaseException && error.code == 'permission-denied') {
            permissionDeniedDuringUpload = true;
          }
          if (!metadataQueuedForRetry) {
            failures.add(displayName);
          }
        } finally {
          _removePendingBytes(size);
          markUploadItemProcessed(size);
          if (usageRecorded) {
            _applyConfirmedUploadedBytes(size, objectKey: objectKey);
          }
        }
        } finally { releasePreparation(); }
      }
      var nextUploadIndex = 0;
      final workerCount = UploadCoordinator.enabled
        ? (secureUpload ? 1 : UploadCoordinator.instance.scheduler.mobile ? 2 : 4) : 1;
      await Future.wait(List.generate(min(workerCount, files.length), (_) async {
        while (nextUploadIndex < files.length && !_transferController.cancelRequested) {
          final index = nextUploadIndex++;
          await uploadItem(index);
        }
      }));
    } catch (error) {
      firstFailureReason ??= _uploadFailureReason(error);
      failures.add('upload');
      if (error is _SessionExpiredException) {
        _handleSessionExpired(error);
      } else if (_isAuthorizationError(error)) {
        _notifyUploadAuthorizationIssue();
      }
      BackgroundBackupRunner.logFailure('upload', 'foreground_batch', error);
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _clearForegroundUploadProgress();
        });
      } else {
        _isUploading = false;
        _clearForegroundUploadProgress();
      }
      _endTransfer(transferId);
    }

    if (!mounted) {
      return;
    }

    final outcomeMessages = <String>[];
    if (successes.isNotEmpty) {
      outcomeMessages.add(
        encryptedUploadCompletionMessage(
          uploadedCount: successes.length,
          previewRetryCount: previewRetryCount,
        ),
      );
    }
    if (failures.isNotEmpty) {
      final reason = firstFailureReason;
      outcomeMessages.add(
        reason == null || reason.isEmpty
            ? 'Failed to upload ${failures.length} item(s).'
            : 'Failed to upload ${failures.length} item(s): $reason',
      );
    }
    if (finalizationRetryCount > 0) {
      outcomeMessages.add(
        encryptedUploadFinalizationPendingMessage(
          pendingCount: finalizationRetryCount,
        ),
      );
      unawaited(_recoverPendingUploadMetadata());
    }
    if (canceledCount > 0) {
      outcomeMessages.add('Canceled $canceledCount queued upload(s).');
    }
    if (permissionDeniedDuringUpload) {
      outcomeMessages.add(
        'Upload permissions were denied. Check your account access or sign in again.',
      );
    }
    if (outcomeMessages.isNotEmpty) {
      _showMessage(outcomeMessages.join(' '));
    }
    _logRuntime('upload', 'Encrypted foreground upload processing finished.');
  }

  Future<void> _showDriveMigrationOverlay() async {
    if (_isUploading) {
      _showMessage('Please wait for the current upload to finish.');
      return;
    }

    final storageReady = await _ensureStorageConfigured();
    if (!mounted) {
      return;
    }

    if (!storageReady) {
      return;
    }

    final providers = <CloudDriveProvider>[
      GoogleDriveMigrationProvider(),
      OneDriveMigrationProvider(),
      DropboxMigrationProvider(),
      ICloudDriveMigrationProvider(),
    ];

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return DriveMigrationOverlay(
          providers: providers,
          onImport: (provider, files) => _importRemoteFiles(provider, files),
        );
      },
    );
  }

  Future<void> _importRemoteFiles(
    CloudDriveProvider provider,
    List<RemoteFileEntry> files,
  ) => _runUploadIntent(() => _importRemoteFilesWithinIntent(provider, files));

  Future<void> _importRemoteFilesWithinIntent(
    CloudDriveProvider provider,
    List<RemoteFileEntry> files,
  ) async {
    if (files.isEmpty) {
      return;
    }

    final knownBytes = files.fold<int>(
      0,
      (total, file) => total + max(0, file.sizeBytes),
    );
    if (!UploadCoordinator.enabled && knownBytes > 0 &&
        !_ensureStorageCapacityForBytes(knownBytes, actionLabel: 'Import')) {
      return;
    }

    final preparedFiles = <_PreparedUploadFile>[];
    var failureCount = 0;
    final transferId =
        'migration-prepare:${DateTime.now().millisecondsSinceEpoch}';
    _beginTransfer(
      transferId,
      'Preparing import from ${provider.displayName}...',
    );
    _showMessage(
      'Downloading ${files.length} item(s) from ${provider.displayName}...',
    );

    try {
      for (var index = 0; index < files.length; index += 1) {
        final remoteFile = files[index];
        final displayName = remoteFile.name.trim().isEmpty
            ? 'Untitled'
            : remoteFile.name.trim();
        _updateTransfer(
          transferId,
          'Preparing ${index + 1}/${files.length}: $displayName',
        );
        try {
          _ensureSessionActive();
          if (UploadCoordinator.enabled && provider.supportsStreaming(remoteFile)) {
            // Unknown-size exports are counted without retaining plaintext.
            // Admission then precedes fingerprint/ciphertext reads; verified
            // source blocks reject a changed export on subsequent reads.
            final sourceLength = provider.streamingLength(remoteFile) ??
                await provider.openRead(remoteFile).fold<int>(0, (total, chunk) {
                    _ensureSessionActive();
                    return total + chunk.length;
                  });
            // The opaque stable identity allows verified native reselection.
            final sourceId = sha256.convert(utf8.encode('${provider.id}\u0000${remoteFile.id}')).toString();
            preparedFiles.add(_PreparedUploadFile(
              file: XFile('remote-import/$sourceId'),
              relativeFolderSegments: <String>[
                _sanitizePathSegment(provider.displayName),
                ...remoteFile.parentPathSegments.map(_sanitizePathSegment),
              ].where((segment) => segment.isNotEmpty).toList(growable: false),
              sizeBytes: sourceLength,
              displayName: _sanitizeFileName(displayName),
              mimeType: provider.streamingMimeType(remoteFile),
              readStreamFactory: () => provider.openRead(remoteFile),
            ));
            continue;
          }
          final payload = await provider.download(remoteFile);
          final bytes = payload.bytes;
          final payloadSize = payload.sizeBytes > 0
              ? payload.sizeBytes
              : bytes.length;
          if (payloadSize <= 0 || bytes.isEmpty) {
            throw StateError('Downloaded file was empty.');
          }
          final sanitizedName = _sanitizeFileName(
            payload.fileName?.trim().isNotEmpty == true
                ? payload.fileName!
                : displayName,
          );
          final resolvedName = sanitizedName.isEmpty
              ? _sanitizeFileName(displayName)
              : sanitizedName;
          final relativeSegments = <String>[
            _sanitizePathSegment(provider.displayName),
            ...remoteFile.parentPathSegments.map(_sanitizePathSegment),
          ].where((segment) => segment.isNotEmpty).toList(growable: false);
          preparedFiles.add(
            _PreparedUploadFile(
              file: XFile.fromData(
                bytes,
                name: resolvedName,
                mimeType: payload.mimeType,
                length: payloadSize,
              ),
              relativeFolderSegments: relativeSegments,
              sizeBytes: payloadSize,
              displayName: resolvedName,
              mimeType: payload.mimeType,
              bytes: bytes,
            ),
          );
          _logRuntime('migration', 'Prepared one provider item for upload.');
        } catch (error) {
          failureCount += 1;
          BackgroundBackupRunner.logFailure(
            'migration',
            'provider_download',
            error,
          );
        }
      }
    } finally {
      _endTransfer(transferId);
    }

    if (!mounted) {
      return;
    }
    if (failureCount > 0) {
      _showMessage(
        'Could not prepare $failureCount item(s) from ${provider.displayName}.',
      );
    }
    if (preparedFiles.isEmpty) {
      _showMessage(
        'No files were ready to import from ${provider.displayName}.',
      );
      return;
    }

    await _handlePreparedUpload(preparedFiles);
  }

  Future<String?> _requireUploadEncryptionKey({
    required bool interactive,
  }) async {
    await _restoreStandardEncryptionKeyIfAvailable();
    await _restoreLoginPassphraseIfAvailable();

    var key =
        _cachedEncryptionKey ??
        await _ensureEncryptionKey(interactive: interactive);

    if (key == null && interactive) {
      await _ensureAuthenticated(interactive: false);
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await _restoreLoginPassphraseIfAvailable();
      key =
          _cachedEncryptionKey ??
          await _ensureEncryptionKey(interactive: false);
    }

    if (key == null && interactive && mounted) {
      _showMessage(
        _lastEncryptionSetupError ??
            'Basic device encryption needs your current login session. Sign in again, then retry the upload.',
      );
    }

    return key;
  }

  Future<bool> _restoreStandardEncryptionKeyIfAvailable() async {
    if (_cachedEncryptionKey != null) {
      return true;
    }

    final salt = _encryptionSalt;
    if (salt == null || salt.isEmpty) {
      return false;
    }

    final restoredKey = await LoginPasswordVault.instance
        .restoreStandardEncryptionKey(
          expectedEmail: widget.user.email,
          expectedSalt: salt,
        );
    if (restoredKey == null || restoredKey.isEmpty) {
      return false;
    }

    if (mounted) {
      setState(() {
        _cachedEncryptionKey = restoredKey;
      });
    } else {
      _cachedEncryptionKey = restoredKey;
    }
    return true;
  }

  Future<bool> _validateRecoveryMaterial(
    StandardEncryptionRecoveryMaterial material,
  ) async {
    if (material.accountUid != widget.user.uid ||
        material.environmentId != widget.auth.app.options.projectId ||
        material.standardKey.length != 32) {
      return false;
    }
    final currentSalt = _encryptionSalt;
    if (currentSalt != null &&
        (currentSalt.length != material.encryptionSalt.length ||
            !listEquals(currentSalt, material.encryptionSalt))) {
      return false;
    }

    final key = SecretKey(material.standardKey);
    final keyString = base64Encode(material.standardKey);
    final file = _firstStandardEncryptedFileNeedingKey();
    if (file != null) {
      final decrypted = await _decryptFileDisplayName(
        file,
        encryptionKey: keyString,
      );
      return decrypted != null && decrypted.trim().isNotEmpty;
    }
    final folder = _firstStandardEncryptedFolderNeedingKey();
    if (folder != null) {
      final decrypted = await _metadataEncryptionService.decryptLabel(
        encryptedLabel: folder.encryptedName!,
        key: key,
      );
      return decrypted != null && decrypted.trim().isNotEmpty;
    }

    try {
      final identity =
          _businessEncryptionIdentity ??
          await _businessEncryptionRegistry.getIdentity();
      if (identity != null) {
        await _businessEncryptionService.validateIdentity(
          identity: identity,
          accountProtectionKey: key,
        );
      }
    } catch (_) {
      return false;
    }
    return true;
  }

  Future<void> _applyRecoveryMaterial(
    StandardEncryptionRecoveryMaterial material,
  ) async {
    final keyString = base64Encode(material.standardKey);
    if (mounted) {
      setState(() {
        _encryptionSalt = Uint8List.fromList(material.encryptionSalt);
        _cachedEncryptionKey = keyString;
        _sessionPassphrase = null;
        _lastEncryptionSetupError = null;
      });
    } else {
      _encryptionSalt = Uint8List.fromList(material.encryptionSalt);
      _cachedEncryptionKey = keyString;
      _sessionPassphrase = null;
      _lastEncryptionSetupError = null;
    }
    await _retryFileDecryption();
  }

  bool _fileNeedsStandardNameDecryption(_DriveFile file) {
    return requiresStandardWorkspaceKeyForLabel(
      isSecured: file.isSecured,
      hasEncryptedLabel: file.encryptedName?.trim().isNotEmpty == true,
      hasEmbeddedEncryptedLabel:
          _extractEncryptedObjectKeyName(file.objectKey) != null,
      hasMemberKeyEnvelopes: file.sharedKeyEnvelopes.isNotEmpty,
    );
  }

  bool _fileNeedsSecureNameDecryption(_DriveFile file) {
    return file.isSecured &&
        file.sharedKeyEnvelopes.isEmpty &&
        _fileNeedsLocalNameDecryption(file);
  }

  bool get _activeStandardEncryptionNeedsUnlock {
    if (_cachedEncryptionKey != null || _encryptionSalt == null) {
      return false;
    }
    return _files.any(
          (file) =>
              _fileMatchesActiveStorageSpace(file) &&
              _fileNeedsStandardNameDecryption(file),
        ) ||
        _folders.any(
          (folder) =>
              _folderMatchesActiveStorageSpace(folder) &&
              _folderNeedsStandardNameDecryption(folder),
        );
  }

  _DriveFile? _firstStandardEncryptedFileNeedingKey() {
    for (final file in _files) {
      if (_fileNeedsStandardNameDecryption(file)) {
        return file;
      }
    }
    return null;
  }

  _DriveFolder? _firstStandardEncryptedFolderNeedingKey() {
    for (final folder in _folders) {
      if (_folderNeedsStandardNameDecryption(folder)) {
        return folder;
      }
    }
    return null;
  }

  Future<bool> _runStandardEncryptionUnlockPrompt({
    bool showSuccessMessage = true,
  }) async {
    final active = _activeStandardUnlockPrompt;
    if (active != null) {
      return active;
    }
    final prompt = _unlockStandardEncryptionWithPassword(
      showSuccessMessage: showSuccessMessage,
    );
    _activeStandardUnlockPrompt = prompt;
    try {
      return await prompt;
    } finally {
      if (identical(_activeStandardUnlockPrompt, prompt)) {
        _activeStandardUnlockPrompt = null;
      }
    }
  }

  Future<bool> _unlockStandardEncryptionWithPassword({
    bool showSuccessMessage = true,
  }) async {
    if (!mounted) {
      return false;
    }

    final salt = _encryptionSalt;
    if (salt == null || salt.isEmpty) {
      return false;
    }

    final password = await _collectStandardEncryptionPassword();
    if (password == null || password.isEmpty) {
      return false;
    }

    try {
      await _verifyCurrentLoginPassword(password);
      final key = await EncryptionService.instance.deriveKey(
        password: password,
        salt: salt,
      );
      final keyString = base64Encode(await key.extractBytes());

      final validationTarget = _firstStandardEncryptedFileNeedingKey();
      if (validationTarget != null) {
        final decryptedName = await _decryptFileDisplayName(
          validationTarget,
          encryptionKey: keyString,
        );
        if (decryptedName == null || decryptedName.isEmpty) {
          if (mounted) {
            _showMessage(
              'The current account password did not unlock these older encrypted files. Use Account Security > Restore from kit.',
            );
          }
          return false;
        }
      } else {
        final folderValidationTarget =
            _firstStandardEncryptedFolderNeedingKey();
        if (folderValidationTarget != null) {
          final decryptedName = await _metadataEncryptionService.decryptLabel(
            encryptedLabel: folderValidationTarget.encryptedName!,
            key: key,
          );
          if (decryptedName == null || decryptedName.trim().isEmpty) {
            if (mounted) {
              _showMessage(
                'The current account password did not unlock these older encrypted folders. Use Account Security > Restore from kit.',
              );
            }
            return false;
          }
        }
      }

      LoginPasswordVault.instance.store(
        email: widget.user.email,
        password: password,
      );
      LoginPasswordVault.instance.storeStandardEncryptionKey(
        email: widget.user.email,
        key: keyString,
        salt: salt,
      );

      if (mounted) {
        setState(() {
          _sessionPassphrase = password;
          _cachedEncryptionKey = keyString;
        });
      } else {
        _sessionPassphrase = password;
        _cachedEncryptionKey = keyString;
      }

      await _retryFileDecryption();
      if (showSuccessMessage && mounted) {
        _showMessage('Encryption unlocked on this device.');
      }
      return true;
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        _showMessage(
          userFacingCloudErrorMessage(
            operation: UserFacingCloudOperation.accountVerification,
            code: error.code,
          ),
        );
      }
      return false;
    } catch (_) {
      if (kDebugMode) {
        debugPrint(
          'Standard encryption unlock stopped at a protected failure boundary.',
        );
      }
      if (mounted) {
        _showMessage('Could not unlock encryption on this device.');
      }
      return false;
    }
  }

  Future<bool> _setupStandardEncryptionWithPassword({
    bool showSuccessMessage = true,
  }) async {
    if (!mounted) {
      return false;
    }

    final password = await _collectStandardEncryptionPassword();
    if (password == null || password.isEmpty) {
      return false;
    }

    try {
      await _verifyCurrentLoginPassword(password);
      final result = await _persistRemoteEncryptionPassword(password);
      final keyString = base64Encode(await result.key.extractBytes());
      LoginPasswordVault.instance.store(
        email: widget.user.email,
        password: password,
      );
      LoginPasswordVault.instance.storeStandardEncryptionKey(
        email: widget.user.email,
        key: keyString,
        salt: result.salt,
      );

      if (mounted) {
        setState(() {
          _encryptionSalt = result.salt;
          _sessionPassphrase = password;
          _cachedEncryptionKey = keyString;
          _lastEncryptionSetupError = null;
        });
      } else {
        _encryptionSalt = result.salt;
        _sessionPassphrase = password;
        _cachedEncryptionKey = keyString;
        _lastEncryptionSetupError = null;
      }

      if (showSuccessMessage && mounted) {
        _showMessage('Encryption is ready on this device.');
      }
      return true;
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        _showMessage(
          userFacingCloudErrorMessage(
            operation: UserFacingCloudOperation.accountVerification,
            code: error.code,
          ),
        );
      }
      return false;
    } on EncryptionPasswordException catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Standard encryption setup failed safely.');
      }
      unawaited(
        AppErrorReporter.instance.recordError(
          StateError('standard_encryption_setup_failed'),
          stackTrace,
          reason: error.message,
        ),
      );
      _lastEncryptionSetupError = error.message;
      if (mounted) {
        _showMessage(error.message);
      }
      return false;
    } catch (_, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          'Standard encryption setup stopped at a protected failure boundary.',
        );
      }
      unawaited(
        AppErrorReporter.instance.recordError(
          StateError('standard_encryption_setup_unexpected'),
          stackTrace,
          reason: 'standard_encryption_setup_unexpected',
        ),
      );
      _lastEncryptionSetupError = 'Could not set up encryption on this device.';
      if (mounted) {
        _showMessage(_lastEncryptionSetupError!);
      }
      return false;
    }
  }

  Future<void> _verifyCurrentLoginPassword(String password) async {
    final currentUser = widget.auth.currentUser;
    final email = widget.user.email?.trim();
    if (currentUser == null ||
        currentUser.uid != widget.user.uid ||
        email == null ||
        email.isEmpty) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'No signed-in user is available for password verification.',
      );
    }

    final credential = EmailAuthProvider.credential(
      email: email,
      password: password,
    );
    await currentUser.reauthenticateWithCredential(credential);
    await currentUser.reload();
    await _refreshUserIdToken();
  }

  Future<void> _restoreLoginPassphraseIfAvailable() async {
    if (_sessionPassphrase != null && _cachedEncryptionKey != null) {
      return;
    }

    final activeRestore = _activePassphraseRestore;
    if (activeRestore != null) {
      await activeRestore;
      return;
    }

    final future = _restoreLoginPassphraseIfAvailableImpl();
    _activePassphraseRestore = future;
    try {
      await future;
    } finally {
      if (identical(_activePassphraseRestore, future)) {
        _activePassphraseRestore = null;
      }
    }
  }

  Future<void> _restoreLoginPassphraseIfAvailableImpl() async {
    await _restoreStandardEncryptionKeyIfAvailable();

    final expectedEmail = widget.user.email;
    final password = expectedEmail == null || expectedEmail.trim().isEmpty
        ? await LoginPasswordVault.instance.restore()
        : await LoginPasswordVault.instance.restore(
            expectedEmail: expectedEmail,
          );
    if (password == null || password.isEmpty) {
      return;
    }

    final existingPassphrase = _sessionPassphrase;
    final existingKey = _cachedEncryptionKey;
    if (existingPassphrase == password && existingKey != null) {
      return;
    }

    final salt = _encryptionSalt;
    String? derivedKeyString;
    final shouldDeriveKey = salt != null && existingKey == null;
    if (shouldDeriveKey) {
      final key = await EncryptionService.instance.deriveKey(
        password: password,
        salt: salt,
      );
      derivedKeyString = base64Encode(await key.extractBytes());
      LoginPasswordVault.instance.storeStandardEncryptionKey(
        email: expectedEmail,
        key: derivedKeyString,
        salt: salt,
      );
    }

    final needsSessionUpdate = existingPassphrase == null;
    final needsKeyUpdate = derivedKeyString != null && existingKey == null;
    if (!needsSessionUpdate && !needsKeyUpdate) {
      return;
    }

    if (mounted) {
      setState(() {
        _sessionPassphrase ??= password;
        if (derivedKeyString != null && _cachedEncryptionKey == null) {
          _cachedEncryptionKey = derivedKeyString;
        }
      });

      if (needsKeyUpdate) {
        unawaited(_retryFileDecryption());
      }
    } else {
      _sessionPassphrase ??= password;
      if (derivedKeyString != null && _cachedEncryptionKey == null) {
        _cachedEncryptionKey = derivedKeyString;
      }
    }
  }

  Future<String?> _ensureEncryptionKey({required bool interactive}) async {
    if (await _restoreStandardEncryptionKeyIfAvailable()) {
      return _cachedEncryptionKey;
    }
    await _restoreLoginPassphraseIfAvailable();

    while (true) {
      final cached = _cachedEncryptionKey;
      if (cached != null) {
        return cached;
      }

      var salt = _encryptionSalt;
      var passphrase = _sessionPassphrase;
      if (passphrase == null) {
        await _restoreLoginPassphraseIfAvailable();
        passphrase = _sessionPassphrase;
      }
      if (passphrase == null && interactive) {
        final unlocked = salt == null
            ? await _setupStandardEncryptionWithPassword()
            : await _runStandardEncryptionUnlockPrompt();
        if (unlocked) {
          continue;
        }
        passphrase = _sessionPassphrase;
      }
      if (passphrase == null) {
        return null;
      }

      if (salt == null) {
        // Attempt to fetch from Firestore first to avoid race conditions where profile isn't loaded yet
        try {
          final doc = await widget.firestore
              .collection('users')
              .doc(widget.user.uid)
              .get();
          final rawSalt = doc.data()?['encryptionSalt'];
          if (rawSalt is String) {
            final parsed = base64Decode(rawSalt);
            if (mounted) {
              setState(() {
                _encryptionSalt = parsed;
              });
            } else {
              _encryptionSalt = parsed;
            }
            continue; // Retry loop with loaded salt
          }
        } catch (_) {
          if (kDebugMode) {
            debugPrint('[ENCRYPTION] Encryption parameters were unavailable.');
          }
        }

        if (!interactive) {
          // Never auto-generate salt in non-interactive mode (e.g. background list loading).
          // This prevents overwriting existing server-side configuration due to load delays.
          return null;
        }

        if (kDebugMode) {
          debugPrint(
            '[ENCRYPTION] Missing salt, generating new cryptographic parameters...',
          );
        }
        try {
          _lastEncryptionSetupError = null;
          final result = await _persistRemoteEncryptionPassword(passphrase);
          if (mounted) {
            final keyBytes = await result.key.extractBytes();
            final keyString = base64Encode(keyBytes);
            LoginPasswordVault.instance.storeStandardEncryptionKey(
              email: widget.user.email,
              key: keyString,
              salt: result.salt,
            );
            setState(() {
              _encryptionSalt = result.salt;
              _sessionPassphrase = passphrase;
              _cachedEncryptionKey = keyString;
            });
            return keyString;
          }
          // If unmounted, we can't set state but we can return the key
          final keyBytes = await result.key.extractBytes();
          final keyString = base64Encode(keyBytes);
          LoginPasswordVault.instance.storeStandardEncryptionKey(
            email: widget.user.email,
            key: keyString,
            salt: result.salt,
          );
          return keyString;
        } catch (error) {
          if (kDebugMode) {
            debugPrint('[ENCRYPTION] Encryption bootstrap failed safely.');
          }
          _lastEncryptionSetupError = error is EncryptionPasswordException
              ? error.message
              : 'Failed to set up device encryption for this account.';
          return null;
        }
      }

      try {
        final key = await EncryptionService.instance.deriveKey(
          password: passphrase,
          salt: salt,
        );
        final keyBytes = await key.extractBytes();
        final keyString = base64Encode(keyBytes);

        _sessionPassphrase = passphrase;
        _cachedEncryptionKey = keyString;
        _lastEncryptionSetupError = null;
        LoginPasswordVault.instance.storeStandardEncryptionKey(
          email: widget.user.email,
          key: keyString,
          salt: salt,
        );
        return keyString;
      } catch (_) {
        if (kDebugMode) {
          debugPrint('Encryption-key derivation failed safely.');
        }
        return null;
      }
    }
  }

  Future<String?> _ensureSecureEncryptionKey({
    required bool interactive,
  }) async {
    while (true) {
      final cached = _cachedSecureEncryptionKey;
      if (cached != null) {
        return cached;
      }

      var salt = _secureEncryptionSalt;
      var passphrase = _secureSessionPassphrase;

      if (passphrase == null) {
        if (!interactive || !mounted) {
          return null;
        }
        passphrase = await _collectEncryptionKey(
          forcePrompt: true,
          isRotation: false,
          title: 'Unlock secure mode',
          description:
              'Enter your secure mode passphrase. It stays on this device.',
          submitLabel: 'Unlock',
        );
        if (passphrase == null) {
          return null;
        }
      }

      if (salt == null) {
        try {
          final doc = await widget.firestore
              .collection('users')
              .doc(widget.user.uid)
              .get();
          final rawSalt = doc.data()?['secureEncryptionSalt'];
          if (rawSalt is String && rawSalt.trim().isNotEmpty) {
            final parsed = Uint8List.fromList(base64Decode(rawSalt.trim()));
            if (mounted) {
              setState(() {
                _secureEncryptionSalt = parsed;
              });
            } else {
              _secureEncryptionSalt = parsed;
            }
            continue;
          }
        } catch (_) {
          if (kDebugMode) {
            debugPrint('[ENCRYPTION] Secure parameters were unavailable.');
          }
        }

        if (!interactive) {
          return null;
        }

        try {
          final result = await _persistRemoteSecurePassphrase(passphrase);
          final keyBytes = await result.key.extractBytes();
          final keyString = base64Encode(keyBytes);
          if (mounted) {
            setState(() {
              _secureEncryptionSalt = result.salt;
              _secureSessionPassphrase = passphrase;
              _cachedSecureEncryptionKey = keyString;
            });
          } else {
            _secureEncryptionSalt = result.salt;
            _secureSessionPassphrase = passphrase;
            _cachedSecureEncryptionKey = keyString;
          }
          return keyString;
        } catch (_) {
          if (kDebugMode) {
            debugPrint('[ENCRYPTION] Secure mode setup was unavailable.');
          }
          return null;
        }
      }

      try {
        final key = await EncryptionService.instance.deriveKey(
          password: passphrase,
          salt: salt,
        );
        final keyBytes = await key.extractBytes();
        final keyString = base64Encode(keyBytes);

        _secureSessionPassphrase = passphrase;
        _cachedSecureEncryptionKey = keyString;
        return keyString;
      } catch (_) {
        if (kDebugMode) {
          debugPrint('Secure key derivation was unavailable.');
        }
        return null;
      }
    }
  }

  Future<String> _encryptFileName(
    String name, {
    required String encryptionKey,
  }) async {
    final secretKey = SecretKey(base64Decode(encryptionKey));
    return EncryptionService.instance.encryptFileName(name, secretKey);
  }

  Future<String?> _decryptFileName(
    String encryptedName, {
    required String encryptionKey,
  }) async {
    final secretKey = SecretKey(base64Decode(encryptionKey));
    return EncryptionService.instance.decryptFileName(encryptedName, secretKey);
  }

  Future<String> _computeFileSha256Base64(File file, {int? lengthHint}) async {
    if (lengthHint != null && lengthHint >= 0 && lengthHint <= 1024 * 1024) {
      final bytes = await file.readAsBytes();
      return base64Encode(sha256.convert(bytes).bytes);
    }
    return base64Encode((await sha256.bind(file.openRead()).first).bytes);
  }

  ({Stream<List<int>> stream, Future<String> hashFuture})
  _createHashingUploadStream(File file) {
    final hashCompleter = Completer<String>();
    final byteSink = sha256.startChunkedConversion(
      ChunkedConversionSink<Digest>.withCallback((digests) {
        if (!hashCompleter.isCompleted) {
          final digest = digests.single;
          hashCompleter.complete(base64Encode(digest.bytes));
        }
      }),
    );

    final stream = file.openRead().transform(
      StreamTransformer<List<int>, List<int>>.fromHandlers(
        handleData: (chunk, sink) {
          byteSink.add(chunk);
          sink.add(chunk);
        },
        handleError: (error, stackTrace, sink) {
          if (!hashCompleter.isCompleted) {
            hashCompleter.completeError(error, stackTrace);
          }
          sink.addError(error, stackTrace);
        },
        handleDone: (sink) {
          byteSink.close();
          sink.close();
        },
      ),
    );

    return (stream: stream, hashFuture: hashCompleter.future);
  }

  String _legacySecureShardObjectKey(String objectKey, int index) {
    return '$objectKey.parts/${index.toString().padLeft(6, '0')}';
  }

  Future<String> _secureShardObjectKey(
    _DriveFile file,
    int index, {
    SecretKey? encryptionKey,
  }) async {
    if (file.usesPassphraseHmacShards) {
      final key = encryptionKey;
      if (key == null) {
        throw StateError(
          'Secure shard key derivation needs an encryption key.',
        );
      }
      final token = await EncryptionService.instance.deriveSecureShardToken(
        secretKey: key,
        objectKey: file.objectKey,
        shardIndex: index,
      );
      return '${file.objectKey}.parts/$token';
    }
    return _legacySecureShardObjectKey(file.objectKey, index);
  }

  ({Stream<List<int>> stream, int length})
  _createWholeFileSecureCiphertextStream({
    required Stream<List<int>> plaintext,
    required int plainLength,
    required SecretKey encryptionKey,
    List<int>? savedNonce,
  }) {
    final algorithm = EncryptionService.instance.fileContentAlgorithm;
    final nonce = savedNonce ?? algorithm.newNonce();
    final macCompleter = Completer<Mac>();
    final encryptedStream = algorithm.encryptStream(
      plaintext,
      secretKey: encryptionKey,
      nonce: nonce,
      onMac: (mac) {
        if (!macCompleter.isCompleted) {
          macCompleter.complete(mac);
        }
      },
    );

    Stream<List<int>> protectedStream() async* {
      yield nonce;
      yield* encryptedStream;
      yield (await macCompleter.future).bytes;
    }

    return (
      stream: UploadCoordinator.enabled
        ? encryptUploadStream(plaintext, encryptionKey, nonce) : protectedStream(),
      length:
          plainLength +
          algorithm.nonceLength +
          algorithm.macAlgorithm.macLength,
    );
  }

  Future<int> _uploadSecureShardedObject({
    required String objectKey,
    required Stream<List<int>> stream,
    required int length,
    required SecretKey encryptionKey,
    required String transferId,
    required TransferJournal? checkpointSink,
    required String? sourceFingerprint,
  }) async {
    final checkpoint = UploadCoordinator.enabled && checkpointSink != null && sourceFingerprint != null
        ? await SecureUploadCheckpoint.open(sink: checkpointSink, parentId: transferId,
            objectKey: objectKey, fingerprint: sourceFingerprint,
            newNonce: EncryptionService.instance.fileContentAlgorithm.newNonce)
        : null;
    final ciphertext = _createWholeFileSecureCiphertextStream(
      plaintext: stream,
      plainLength: length,
      encryptionKey: encryptionKey,
      savedNonce: checkpoint?.nonce,
    );
    final file = _DriveFile(
      id: pendingFileIdForObjectKey(objectKey),
      name: 'Secure upload',
      objectKey: objectKey,
      size: ciphertext.length,
      isFolder: false,
      encryptionMode: 'secured',
      storageLayout: 'sharded',
      shardScheme: _secureShardSchemePassphraseHmacV1,
      secureContentEncoding: _secureContentEncodingWholeFileV1,
    );
    final buffer = BytesBuilder(copy: false);
    var shardIndex = 0;
    final pendingShards = <Future<void>>[];
    Object? shardFailure;

    Future<void> flushShard() async {
      if (shardFailure != null) throw shardFailure!;
      if (buffer.length == 0) {
        return;
      }
      final bytes = buffer.takeBytes();
      final shardKey = await _secureShardObjectKey(
        file,
        shardIndex,
        encryptionKey: encryptionKey,
      );
      _ensureOwnsObjectKey(shardKey);
      final upload = _storageService.upload(
        objectKey: shardKey,
        stream: Stream<List<int>>.value(bytes),
        length: bytes.length,
        contentType: 'application/octet-stream',
        payloadAlreadyEncrypted: true,
        transferId: checkpoint == null ? null : '$transferId:shard:$shardIndex',
        checkpointSink: checkpoint,
        sourceFingerprint: sourceFingerprint,
      );
      pendingShards.add(upload.then<void>((_) {}, onError: (Object error) {
        shardFailure ??= error;
      }));
      shardIndex += 1;
      final parallelism = UploadCoordinator.enabled ? 3 : 1;
      if (pendingShards.length >= parallelism) {
        await Future.wait(pendingShards);
        pendingShards.clear();
        if (shardFailure != null) throw shardFailure!;
      }
    }

    try {
    await for (final chunk in ciphertext.stream) {
      var offset = 0;
      while (offset < chunk.length) {
        final room = _secureShardSizeBytes - buffer.length;
        final take = min(room, chunk.length - offset);
        buffer.add(chunk.sublist(offset, offset + take));
        offset += take;
        if (buffer.length >= _secureShardSizeBytes) {
          await flushShard();
        }
      }
    }

    await flushShard();
    } finally {
    await Future.wait(pendingShards);
    }
    if (shardFailure != null) throw shardFailure!;
    return shardIndex;
  }

  Future<void> _handleShareAction(_DriveFile file) async {
    if (!_ensureStorageReadsAvailable(storageScope: file.storageScope) ||
        !_ensureStorageSharesAvailable(storageScope: file.storageScope)) {
      return;
    }
    if (file.isFolder) {
      _showMessage('Sharing folders is not supported yet.');
      return;
    }

    final activeLinkCount = _activeShareLinkCountFor(file.id);
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.share_rounded),
                title: const Text('Share file'),
                subtitle: const Text('Send a copy via email, messenger, etc.'),
                onTap: () {
                  Navigator.pop(context);
                  _shareFile(file);
                },
              ),
              ListTile(
                leading: const Icon(Icons.link_rounded),
                title: const Text('Create share link'),
                subtitle: Text(
                  activeLinkCount > 0
                      ? 'Create another encrypted link or email a new one.'
                      : 'Email an encrypted link, with an optional password.',
                ),
                onTap: () {
                  Navigator.pop(context);
                  _copyLink(file);
                },
              ),
              ListTile(
                leading: const Icon(Icons.manage_accounts_outlined),
                title: const Text('Manage share links'),
                subtitle: Text(
                  activeLinkCount > 0
                      ? '$activeLinkCount active link${activeLinkCount == 1 ? '' : 's'} owned by this account'
                      : _shareLinkIndexAvailable
                      ? 'Review previous links or create a new one.'
                      : 'Check link status, expiry, and revocation.',
                ),
                onTap: () {
                  Navigator.pop(context);
                  unawaited(_manageShareLinks(file));
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _shareFile(_DriveFile file) async {
    if (_preparingShare) return;
    _preparingShare = true;
    try {
      if (!kIsWeb &&
          !await _confirmPlaintextLocalWrite(file, action: 'Share')) {
        return;
      }

      final key = await _encryptionKeyStringForFile(file, interactive: true);
      if (file.isEncrypted && key == null) {
        _showMessage('Unlock this file before sharing.');
        return;
      }
      if (!mounted) return;
      final fileBytes = await runSharePreparation(
        context: context,
        initialStatus: 'Downloading and decrypting your file…',
        prepare: (_) => _downloadFileBytes(
          file,
          secretKey: key == null ? null : SecretKey(base64Decode(key)),
          preferProxy: kIsWeb,
        ),
      );

      if (!mounted) return;

      final box = context.findRenderObject() as RenderBox?;
      final shareOrigin = box != null
          ? (box.localToGlobal(Offset.zero) & box.size)
          : null;

      if (kIsWeb) {
        await Share.shareXFiles(
          [
            XFile.fromData(
              fileBytes,
              name: file.name,
              length: fileBytes.length,
            ),
          ],
          text: 'Sharing ${file.name}',
          sharePositionOrigin: shareOrigin,
        );
        return;
      }

      final lease = await _createTemporaryPlaintextLease(file.name);
      await lease.writeBytes(fileBytes);
      await _shareTemporaryPlaintextLease(
        lease,
        displayName: file.name,
        text: 'Sharing ${file.name}',
        sharePositionOrigin: shareOrigin,
      );
    } catch (_) {
      if (kDebugMode) {
        debugPrint('The share action was unavailable.');
      }
      _showMessage('Failed to share file.');
    } finally {
      _preparingShare = false;
    }
  }

  Future<void> _copyLink(_DriveFile file) async {
    await _createPasswordShareLink(file);
  }

  String _newShareToken() {
    return base64Url.encode(_generateRandomBytes(24)).replaceAll('=', '');
  }

  String _shareObjectKeyForToken(String token) {
    final safeToken = token.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    // A share is owned by its creator, even when its source is in a Business
    // space. Keep the encrypted derivative in the creator's Personal prefix
    // so the public backend can resolve one stable, revocable object without
    // encoding the company scope in the derivative object key.
    final creatorPersonalPrefix = _objectKeyOwnerPrefixes.first;
    return '$creatorPersonalPrefix/shared/$safeToken/payload.bin';
  }

  Uri _shareUriForToken(String token) {
    final projectId = widget.auth.app.options.projectId;
    return ReleaseRuntimeConfig.resolveWebAppBaseUri(
      projectId: projectId,
    ).resolve('share/$token');
  }

  Future<String?> _createSecureFileRequest(FileRequestDraft draft) async {
    try {
      if (!await _ensureAuthenticated(interactive: true)) return null;
      final standardKeyString = await _requireUploadEncryptionKey(
        interactive: true,
      );
      if (standardKeyString == null) return null;
      final standardKey = SecretKey(base64Decode(standardKeyString));
      final requestKeyBytes = _generateRandomBytes(32);
      final requestKey = SecretKey(requestKeyBytes);
      final encryptedEnvelope = await EncryptionService.instance.encryptData(
        requestKeyBytes,
        standardKey,
      );
      final encryptedTitleBase64 = await FileRequestMetadataEnvelope.sealTitle(
        title: draft.title,
        key: requestKey,
      );
      final created = await _secureDriveService.createFileRequest(
        encryptedTitleBase64: encryptedTitleBase64,
        encryptedKeyBase64: base64Encode(encryptedEnvelope),
        expiryDays: draft.expiryDays,
        maxFileBytes: draft.maxFileBytes,
        maxUploads: draft.maxUploads,
      );
      final base = ReleaseRuntimeConfig.resolveWebAppBaseUri(
        projectId: widget.auth.app.options.projectId,
      ).resolve('request/${created.token}');
      final fragment = Uri(
        queryParameters: <String, String>{
          'key': base64Url.encode(requestKeyBytes).replaceAll('=', ''),
        },
      ).query;
      return base.replace(fragment: fragment).toString();
    } catch (_) {
      if (kDebugMode) {
        debugPrint('Secure file-request creation was unavailable.');
      }
      _showMessage('Could not create the secure file request.');
      return null;
    }
  }

  Future<SecretKey?> _fileRequestKeyForOwner(
    String requestToken, {
    required bool interactive,
  }) async {
    final normalizedToken = requestToken.trim();
    if (normalizedToken.isEmpty) return null;
    final standardKeyString = await _requireUploadEncryptionKey(
      interactive: interactive,
    );
    if (standardKeyString == null || standardKeyString.isEmpty) return null;
    final secretSnapshot = await widget.firestore
        .collection('file_request_secrets')
        .doc(normalizedToken)
        .get();
    final envelopeBase64 =
        secretSnapshot.data()?['encryptedKeyBase64']?.toString().trim() ?? '';
    if (envelopeBase64.isEmpty) return null;
    final requestKeyBytes = await EncryptionService.instance.decryptData(
      base64Decode(envelopeBase64),
      SecretKey(base64Decode(standardKeyString)),
    );
    if (requestKeyBytes.length != 32) return null;
    return SecretKey(requestKeyBytes);
  }

  Future<String?> _resolveFileRequestTitle(
    String requestToken,
    Map<String, dynamic> data,
  ) async {
    final metadataFormat = data['metadataFormat']?.toString().trim() ?? '';
    if (metadataFormat != fileRequestTitleMetadataFormat) {
      final legacyTitle = data['title']?.toString().trim() ?? '';
      return legacyTitle.isEmpty ? null : legacyTitle;
    }
    final envelope = data['encryptedTitleBase64']?.toString().trim() ?? '';
    if (envelope.isEmpty) return null;
    try {
      final requestKey = await _fileRequestKeyForOwner(
        requestToken,
        interactive: false,
      );
      if (requestKey == null) return null;
      return FileRequestMetadataEnvelope.openTitle(
        encodedEnvelope: envelope,
        key: requestKey,
      );
    } on Object {
      return null;
    }
  }

  Future<void> _downloadRequestedUpload(
    DocumentSnapshot<Map<String, dynamic>> upload,
  ) async {
    try {
      final data = upload.data();
      if (data == null || data['uid'] != widget.user.uid) {
        throw StateError(
          'This requested upload does not belong to your account.',
        );
      }
      if (!await _ensureStorageConfigured()) return;
      final requestToken = data['requestToken']?.toString().trim() ?? '';
      final objectKey = data['objectKey']?.toString().trim() ?? '';
      if (requestToken.isEmpty || objectKey.isEmpty) {
        throw StateError('The requested upload metadata is incomplete.');
      }
      _ensureOwnsObjectKey(objectKey);
      final requestKey = await _fileRequestKeyForOwner(
        requestToken,
        interactive: true,
      );
      if (requestKey == null) {
        throw StateError('The owner key envelope is unavailable.');
      }
      final stream = await _storageService.download(
        objectKey: objectKey,
        preferProxy: kIsWeb,
      );
      final builder = BytesBuilder(copy: false);
      await for (final chunk in stream) {
        builder.add(chunk);
      }
      final plainBytes = await EncryptionService.instance.decryptData(
        builder.takeBytes(),
        requestKey,
      );
      final metadataFormat = data['metadataFormat']?.toString().trim() ?? '';
      final String fileName;
      if (metadataFormat == fileRequestUploadMetadataFormat) {
        final protectedMetadata = await FileRequestMetadataEnvelope.openUpload(
          encodedEnvelope:
              data['encryptedMetadataBase64']?.toString().trim() ?? '',
          key: requestKey,
        );
        fileName = protectedMetadata.fileName;
      } else {
        final encryptedName = data['encryptedName']?.toString().trim() ?? '';
        fileName =
            await EncryptionService.instance.decryptFileName(
              encryptedName,
              requestKey,
            ) ??
            'requested-file';
      }
      final sanitizedName = _sanitizeFileName(fileName);
      final displayName = sanitizedName.isEmpty
          ? 'requested-file'
          : sanitizedName;
      if (kIsWeb) {
        await downloadFile(plainBytes, displayName);
      } else {
        final lease = await _createTemporaryPlaintextLease(displayName);
        await lease.writeBytes(plainBytes);
        await _shareTemporaryPlaintextLease(lease, displayName: displayName);
      }
      final rawRequestPrivacyVersion = data['requestMetadataPrivacyVersion'];
      final requestPrivacyVersion = rawRequestPrivacyVersion is num
          ? rawRequestPrivacyVersion.toInt()
          : int.tryParse(rawRequestPrivacyVersion?.toString() ?? '') ?? 1;
      await upload.reference.update({
        'status': 'accepted',
        if (requestPrivacyVersion >= 2) 'createdAt': FieldValue.delete(),
        'updatedAt': FieldValue.delete(),
      });
      _showMessage('Requested file decrypted and handed off safely.');
    } on SecretBoxAuthenticationError {
      _showMessage('The requested file failed its integrity check.');
    } catch (_) {
      if (kDebugMode) {
        debugPrint('Requested-upload download was unavailable.');
      }
      _showMessage('Could not decrypt this requested upload.');
    }
  }

  Future<String?> _resolveShareSourceLabel(String sourceFileId) async {
    final file = _filesById[sourceFileId];
    if (file == null || file.isFolder) {
      return null;
    }
    final resolved = (await _maybeDecryptFileNames(<_DriveFile>[file])).first;
    if (_fileNeedsLocalNameDecryption(resolved)) {
      return null;
    }
    final label = resolved.name.trim();
    return label.isEmpty ? null : label;
  }

  Future<void> _openDataSafetyCenter() async {
    final journal = _transferJournal;
    if (journal == null) {
      _showMessage('Transfer history is still loading.');
      return;
    }
    if (_storageService.isConfigured) {
      unawaited(_cleanupInterruptedMultipartUploads());
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => DataSafetyCenterPage(
          uid: widget.user.uid,
          firestore: widget.firestore,
          service: _secureDriveService,
          createFileRequest: _createSecureFileRequest,
          downloadRequestedUpload: _downloadRequestedUpload,
          transferJournal: journal,
          recoveryPathAvailable: _hasWorkingRecoveryPath,
          verifyRestore: _verifyRestoreRead,
          retryPendingMetadata: _recoverPendingUploadMetadata,
          cleanupInterruptedTransfers: _cleanupInterruptedMultipartUploads,
          cancelInterruptedUpload: (id) async {
            _ensureSessionActive();
            final api = _storageService.uploadSessionApi;
            if (api == null) throw const UploadFailure('unavailable');
            await saved_upload.cancelInterruptedUpload(journal: journal, entryId: id, api: api);
          },
          cleanupPlaintextTemporaryFiles: _clearPlaintextTemporaryFiles,
          resolveFileRequestTitle: _resolveFileRequestTitle,
          resolveShareSourceLabel: _resolveShareSourceLabel,
          revokeAllShareLinks: _shareLinkOwnerService.revokeAll,
          decryptProtectedLabel: (encryptedLabel) async {
            final keyString = await _ensureEncryptionKey(interactive: false);
            if (keyString == null || keyString.isEmpty) {
              return null;
            }
            return _metadataEncryptionService.decryptLabel(
              encryptedLabel: encryptedLabel,
              key: SecretKey(base64Decode(keyString)),
            );
          },
        ),
      ),
    );
  }

  bool get _hasWorkingRecoveryPath {
    final files = _files.where((file) => !file.isFolder);
    final needsStandardKey = files.any(
      (file) => file.isStandardEncrypted || _fileNeedsLocalNameDecryption(file),
    );
    final needsSecureKey = files.any((file) => file.isSecured);
    return (!needsStandardKey || _cachedEncryptionKey != null) &&
        (!needsSecureKey || _cachedSecureEncryptionKey != null);
  }

  Future<void> _openBusinessOperations() async {
    if (!widget.businessMode || !mounted) return;
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => BusinessOperationsPage(
      service: BusinessOperationsService.forApp(widget.auth.app),
      resolveFileName: (fileId) async {
        final uid = widget.user.uid;
        final company = _companyId;
        final generation = _companyStorageStreamGeneration;
        void check() {
          if (!mounted || widget.auth.currentUser?.uid != uid || _companyId != company ||
              _companyStorageStreamGeneration != generation || !_hasActiveCompanyMembership) {
            throw const BusinessOperationsException();
          }
        }
        check();
        final snapshot = await widget.firestore.collection('files').doc(fileId).get(const GetOptions(source: Source.server));
        check();
        final file = _tryParseDriveFile(snapshot);
        if (!snapshot.exists || snapshot.data()?['companyId'] != company || file == null || !_canReadStorageScope(file.storageScope)) {
          throw const BusinessOperationsException();
        }
        if (!_fileNeedsLocalNameDecryption(file)) return file.name;
        final key = file.sharedKeyEnvelopes.isNotEmpty
          ? await _businessFileKeyStringForFile(file, interactive: false)
          : file.isSecured ? await _ensureSecureEncryptionKey(interactive: false)
          : await _ensureEncryptionKey(interactive: false);
        check();
        if (key == null) return null;
        final label = await _decryptFileDisplayName(file, encryptionKey: key);
        check();
        return label;
      },
      verifyFile: (fileId) async {
        await _refreshWorkspaceMutationState();
        if (!mounted) return false;
        return _verifyRestoreRead(fileId: fileId);
      },
    )));
  }

  Future<bool> _verifyRestoreRead({String? fileId}) async {
    final candidates =
        _files.where((file) => !file.isFolder && file.isActive && (fileId == null || file.id == fileId)).toList()
          ..sort((a, b) => a.size.compareTo(b.size));
    if (candidates.isEmpty) {
      _showMessage(fileId == null ? 'Upload a file before verifying restore access.' : 'The restored file is not available in the current verified file view. Refresh company access and retry.');
      return false;
    }
    if (!await _ensureStorageConfigured()) return false;
    final file = candidates.first;
    final transferId =
        'restore-verify:${file.id}:${DateTime.now().millisecondsSinceEpoch}';
    await _transferJournal?.begin(
      id: transferId,
      kind: TransferJournalKind.restore,
      label: 'Verify restore: ${file.name}',
      objectKey: file.objectKey,
      totalBytes: file.size,
    );
    try {
      final secretKey = await _secretKeyForDownload(file);
      if (file.isEncrypted && secretKey == null) {
        throw StateError('The encryption key is not available on this device.');
      }
      final evidence = await verifyRestoreSample(
        _streamFilePlaintext(file, secretKey: secretKey),
        authenticated: file.isEncrypted,
        expectedPlaintextBytes: file.plaintextSizeBytes,
        integrityTag: file.hash,
        key: secretKey,
        checkAccess: () => _checkFileDownloadAccess(file),
      );
      await _transferJournal?.complete(transferId);
      if (!evidence.verified) {
        _showMessage(
          'The sample could be read, but independent length or protected digest evidence is unavailable. Full recovery has not been verified.',
        );
        return false;
      }
      await _transferJournal?.markRestoreVerified();
      await _recordActivity(ActivityKind.restoreFailed, resolved: true);
      await _recordActivity(ActivityKind.restoreVerified);
      return true;
    } catch (error, _) {
      await _transferJournal?.fail(transferId, error);
      if (kDebugMode) {
        debugPrint('Encrypted restore verification failed safely.');
      }
      await _recordActivity(ActivityKind.restoreFailed);
      _showMessage(
        'Restore verification failed: ${_uploadFailureReason(error)}',
      );
      return false;
    }
  }

  Future<void> _cleanupInterruptedMultipartUploads() {
    final active = _interruptedTransferCleanup;
    if (active != null) return active;
    final future = () async {
      final journal = _transferJournal;
      if (journal == null || !_storageService.isConfigured) return;
      await cleanupInterruptedMultipartUploads(
        journal: journal,
        abortMultipartUpload: _storageService.cleanupInterruptedMultipartUpload,
      );
    }();
    _interruptedTransferCleanup = future;
    return future.whenComplete(() {
      if (identical(_interruptedTransferCleanup, future)) {
        _interruptedTransferCleanup = null;
      }
    });
  }

  Future<Map<String, dynamic>> _preparePendingUploadMetadata(
    Map<String, dynamic> payload,
  ) async {
    final uid = widget.user.uid;
    final companyId = _companyId;
    final permissionRevision = _companyStorageStreamGeneration;
    void checkContext() {
      if (!mounted ||
          widget.auth.currentUser?.uid != uid ||
          widget.user.uid != uid ||
          _companyId != companyId ||
          _companyStorageStreamGeneration != permissionRevision) {
        throw const RecipientTrustException(
          'Account or company access changed.',
        );
      }
    }

    checkContext();
    final scope = payload['storageScope'];
    if (scope != 'company_shared' && scope != 'group') return payload;
    if (payload['companyId'] != companyId || !_hasActiveCompanyMembership) {
      throw const RecipientTrustException(
        'Restore verified company access before retrying this upload.',
      );
    }
    final groups = (payload['groupIds'] as List?)?.whereType<String>().toList();
    final recipients = await _businessEncryptionRegistry.listRecipients(
      storageScope: scope as String,
      groupId: scope == 'group' && groups?.length == 1 ? groups!.single : null,
    );
    checkContext();
    final accountKey = _cachedEncryptionKey;
    if (!recipients.isComplete || accountKey == null || accountKey.isEmpty) {
      throw const RecipientTrustException(
        'Unlock your keys and verify all Business recipients before retrying.',
      );
    }
    final protection = SecretKey(base64Decode(accountKey));
    final identity = await _ensureBusinessEncryptionIdentity(
      accountProtectionKey: protection,
    );
    return refreshPendingBusinessEnvelopes(
      payload: payload,
      uid: uid,
      identity: identity,
      accountProtectionKey: protection,
      encryption: _businessEncryptionService,
      verifiedRecipients: recipients.recipients,
      checkContext: () {
        checkContext();
        if (_cachedEncryptionKey != accountKey) {
          throw const RecipientTrustException(
            'The encryption keys were locked.',
          );
        }
      },
    );
  }

  Future<UploadMetadataRecoveryResult> _recoverPendingUploadMetadata() {
    final active = _pendingMetadataRecovery;
    if (active != null) return active;
    final future = () async {
      final journal = _transferJournal;
      if (journal == null) {
        return const UploadMetadataRecoveryResult(
          eligible: 0,
          attempted: 0,
          recovered: 0,
          failed: 0,
        );
      }
      final eligible = journal.pendingEntries
          .where((entry) => entry.canRetryMetadata)
          .length;
      if (eligible == 0 || !await _ensureAuthenticated(interactive: false)) {
        return UploadMetadataRecoveryResult(
          eligible: eligible,
          attempted: 0,
          recovered: 0,
          failed: 0,
        );
      }
      final recoveryUid = widget.user.uid;
      final recoveryCompany = _companyId;
      final recoveryPermissions = _companyStorageStreamGeneration;
      final result = await recoverPendingUploadMetadata(
        checkContext: () {
          if (!mounted || widget.auth.currentUser?.uid != recoveryUid ||
              widget.user.uid != recoveryUid || _companyId != recoveryCompany ||
              _companyStorageStreamGeneration != recoveryPermissions) {
            throw const RecipientTrustException('Account or company access changed.');
          }
        },
        journal: journal,
        recordMetadata: _uploadMetadataService.recordUploadedFilePayload,
        prepareMetadata: _preparePendingUploadMetadata,
        stopAfterError: (error) {
          if (_isAuthorizationError(error) ||
              error is _SessionExpiredException) {
            return true;
          }
          final message = error.toString().toLowerCase();
          return message.contains('must be signed in') ||
              message.contains('unauthenticated') ||
              message.contains('session expired');
        },
      );
      if (result.recovered > 0) {
        _logRuntime('upload', 'Recovered pending upload metadata safely.');
      }
      return result;
    }();
    _pendingMetadataRecovery = future;
    return future.whenComplete(() {
      if (identical(_pendingMetadataRecovery, future)) {
        _pendingMetadataRecovery = null;
      }
    });
  }

  Future<void> _createPasswordShareLink(_DriveFile file) async {
    if (_preparingShare) return;
    _preparingShare = true;
    final shareUid = widget.user.uid;
    final shareCompany = _companyId;
    final sharePermissionGeneration = _companyStorageStreamGeneration;
    void checkContext() {
      if (!mounted || widget.auth.currentUser?.uid != shareUid ||
          widget.user.uid != shareUid || _companyId != shareCompany ||
          _companyStorageStreamGeneration != sharePermissionGeneration ||
          !_canReadStorageScope(file.storageScope) ||
          !_canShareStorageScope(file.storageScope)) {
        throw StateError('Share context changed.');
      }
    }
    try {
      if (file.isFolder) {
        _showMessage('Sharing folders is not supported yet.');
        return;
      }
      if (!isSupportedPublicShareSize(file.size)) {
        _showMessage(publicShareSizeLimitMessage);
        return;
      }
      final draft = await showDialog<ShareLinkDraft>(
        context: context,
        builder: (_) => const CreateShareLinkDialog(),
      );
      if (draft == null) return;
      checkContext();
      final storageReady = await _ensureStorageConfigured(forceRefresh: !_storageService.isConfigured);
      checkContext();
      if (!storageReady || !await _ensureAuthenticated(interactive: true)) return;
      checkContext();
      SecretKey? ownerProtectionKey;
      if (!draft.passwordProtected) {
        final standardKey = await _requireUploadEncryptionKey(interactive: true);
        checkContext();
        if (standardKey == null) return;
        ownerProtectionKey = SecretKey(base64Decode(standardKey));
      }
      final secretKey = await _secretKeyForDownload(file);
      checkContext();
      if (file.isEncrypted && secretKey == null) {
        _showMessage('Unlock this file before creating a share link.');
        return;
      }
      final token = _newShareToken();
      final expiresAt = coarseShareExpiry(now: DateTime.now(), days: draft.expiryDays);
      if (!mounted) return;
      final material = await runSharePreparation<ShareLinkKeyMaterial>(
        context: context,
        initialStatus: 'Downloading your file and preparing encryption…',
        prepare: (updateStatus) async {
          final prepared = await Future.wait<Object>([
            _downloadFileBytes(file, secretKey: secretKey, preferProxy: kIsWeb),
            ShareLinkCrypto.create(
              passwordProtected: draft.passwordProtected,
              password: draft.password,
              ownerProtectionKey: ownerProtectionKey,
            ),
          ]);
          checkContext();
          final plainBytes = prepared[0] as Uint8List;
          final material = prepared[1] as ShareLinkKeyMaterial;
          if (!isSupportedPublicShareSize(plainBytes.length)) {
            throw StateError(publicShareSizeLimitMessage);
          }
          updateStatus('Encrypting the share copy…');
          final encryptedBytes = await EncryptionService.instance.encryptData(plainBytes, material.key);
          checkContext();
          final encryptedMetadataBase64 = await ShareMetadataEnvelope.seal(fileName: file.name, contentType: file.contentType, key: material.key);
          final downloadVerifierBase64 = await deriveShareDownloadProof(shareKey: material.key, token: token);
          checkContext();
          final shareObjectKey = _shareObjectKeyForToken(token);
          _ensureOwnsObjectKey(shareObjectKey);
          updateStatus('Uploading the encrypted share copy…');
          await _storageService.upload(
            objectKey: shareObjectKey,
            stream: Stream<List<int>>.value(encryptedBytes),
            length: encryptedBytes.length,
            contentType: 'application/octet-stream',
            payloadAlreadyEncrypted: true,
          );
          checkContext();
          updateStatus('Finishing your share link…');
          await widget.firestore.collection('shared_links').doc(token).set({
            'token': token,
            'uid': shareUid,
            'sourceFileId': file.id,
            ...material.protectedRecordFields,
            'algorithm': 'aes-ctr-hmac-sha256',
            'metadataFormat': shareMetadataEnvelopeFormat,
            'encryptedMetadataBase64': encryptedMetadataBase64,
            'downloadProofFormat': shareDownloadProofFormat,
            'downloadVerifierBase64': downloadVerifierBase64,
            'expiresAt': Timestamp.fromDate(expiresAt),
            'revoked': false,
            'downloadCount': 0,
            'accessPrivacyVersion': shareAccessPrivacyVersion,
            'maxDownloads': draft.maxDownloads,
            'notifyOnAccess': draft.notifyOnFirstAccess,
          });
          checkContext();
          return material;
        },
      );
      checkContext();
      final base = _shareUriForToken(token);
      final shareUrl = material.passwordProtected ? base : await ShareLinkCrypto.completeLink(base, material.key);
      checkContext();
      final email = ShareEmailService(auth: widget.auth, ownerUid: shareUid);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ShareCreatedDialog(
          shareUrl: shareUrl,
          password: material.password,
          expiresAt: expiresAt,
          maxDownloads: draft.maxDownloads,
          recipientEmail: draft.recipientEmail,
          canAccessShare: () {
            try {
              checkContext();
              return true;
            } catch (_) {
              return false;
            }
          },
          sessionStates: widget.auth.authStateChanges().map((user) => user?.uid == shareUid),
          sendPasswordLink: ({required recipientEmail, required requestId}) async {
            checkContext();
            if (!await _ensureAuthenticated(interactive: true)) {
              throw const ShareEmailException('Sign in again before emailing this link.');
            }
            checkContext();
            await email.sendPasswordLink(
              shareToken: token,
              recipientEmail: recipientEmail,
              requestId: requestId,
              passwordProtected: material.passwordProtected,
            );
            checkContext();
          },
        ),
      );
    } catch (_) {
      if (kDebugMode) debugPrint('Encrypted share-link creation was unavailable.');
      if (mounted) _showMessage('Could not create the encrypted share link. Check your access and retry.');
    } finally {
      _preparingShare = false;
    }
  }

  Future<void> _manageShareLinks(_DriveFile file) async {
    try {
      final snapshot = await widget.firestore
          .collection('shared_links')
          .where('uid', isEqualTo: widget.user.uid)
          .where('sourceFileId', isEqualTo: file.id)
          .limit(20)
          .get();
      final docs = snapshot.docs;
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) {
          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                Text(
                  'Share links for ${file.name}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.shield_outlined),
                  title: Text('Share safety'),
                  subtitle: Text(
                    'New links have a request budget and generic safety alerts. '
                    'RonikCloud does not put the filename, recipient, or link '
                    'identifier in those alerts.',
                  ),
                ),
                if (docs.isEmpty)
                  const ListTile(
                    leading: Icon(Icons.link_off_rounded),
                    title: Text('No links yet'),
                  )
                else
                  for (final doc in docs)
                    _buildManagedShareLinkTile(sheetContext: context, doc: doc),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    unawaited(_createPasswordShareLink(file));
                  },
                  icon: const Icon(Icons.add_link_rounded),
                  label: const Text('Create another link'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _revokingAllShareLinks
                      ? null
                      : () => unawaited(
                          _revokeAllOwnedShareLinks(sheetContext: context),
                        ),
                  icon: const Icon(Icons.emergency_outlined),
                  label: const Text('Emergency: revoke every link'),
                ),
              ],
            ),
          );
        },
      );
    } catch (_) {
      if (kDebugMode) {
        debugPrint('Share-link status could not be loaded.');
      }
      _showMessage('Could not load share links.');
    }
  }

  Widget _buildManagedShareLinkTile({
    required BuildContext sheetContext,
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
  }) {
    final summary = ShareLinkOwnerSummary.fromMap(
      doc.data(),
      timestampParser: _DriveFile._parseTimestamp,
    );
    final now = DateTime.now().toUtc();
    final status = summary.statusLabel(now);
    final expires = summary.expiresAt?.toLocal();
    final theme = Theme.of(sheetContext);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                summary.requiresSecurityAttention
                    ? Icons.gpp_maybe_outlined
                    : status == 'Active'
                    ? Icons.link_rounded
                    : Icons.link_off_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ShareLinkOwnerSummary.displayReference(doc.id),
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    <String>[
                      status,
                      summary.requestCountLabel,
                      if (expires != null) 'Expires around $expires',
                      'Source access is rechecked for every request',
                      summary.proofLabel,
                      summary.alertLabel,
                      summary.budgetAlertLabel,
                      if (summary.abuseAlertLabel != null)
                        summary.abuseAlertLabel!,
                    ].join('\n'),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Share-link actions',
              onSelected: (action) {
                unawaited(
                  _handleManagedShareLinkAction(
                    action: action,
                    sheetContext: sheetContext,
                    doc: doc,
                  ),
                );
              },
              itemBuilder: (context) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                  value: 'copy',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.copy_rounded),
                    title: Text('Copy link'),
                  ),
                ),
                if (!summary.revoked)
                  const PopupMenuItem<String>(
                    value: 'revoke',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.link_off_rounded),
                      title: Text('Revoke link'),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleManagedShareLinkAction({
    required String action,
    required BuildContext sheetContext,
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
  }) async {
    if (action == 'copy') {
      final ownerUid = widget.user.uid;
      var shareUri = _shareUriForToken(doc.id);
      if (doc.data()['accessMode'] == 'link') {
        final standardKey = await _requireUploadEncryptionKey(interactive: true);
        if (standardKey == null || !mounted || widget.auth.currentUser?.uid != ownerUid) return;
        try {
          final key = await ShareLinkCrypto.openOwnerKey(
            encryptedKeyBase64: doc.data()['encryptedKeyBase64'] as String? ?? '',
            ownerProtectionKey: SecretKey(base64Decode(standardKey)),
          );
          shareUri = await ShareLinkCrypto.completeLink(shareUri, key);
        } catch (_) {
          if (mounted) _showMessage('Unlock the original account key to copy this complete link, or create a new link.');
          return;
        }
      }
      if (!mounted || widget.auth.currentUser?.uid != ownerUid) return;
      try {
        await Clipboard.setData(ClipboardData(text: shareUri.toString()));
        if (mounted) _showMessage('Share link copied.');
      } catch (_) {
        if (!mounted || widget.auth.currentUser?.uid != ownerUid) return;
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Copy share link'),
            scrollable: true,
            content: StreamBuilder<bool>(
              stream: widget.auth.authStateChanges().map((user) => user?.uid == ownerUid),
              initialData: true,
              builder: (_, snapshot) => snapshot.data == true
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Clipboard access is unavailable. Select and copy the complete link below. Share it only with your intended recipient.'),
                        const SizedBox(height: 12),
                        SelectableText(shareUri.toString()),
                      ],
                    )
                  : const Text('Your sign-in changed. Open sharing again for the current account.'),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Done'))],
          ),
        );
      }
      return;
    }
    if (action != 'revoke') {
      return;
    }

    await doc.reference.update({
      'revoked': true,
      'createdAt': FieldValue.delete(),
      'revokedAt': FieldValue.delete(),
      'updatedAt': FieldValue.delete(),
      'lastAccessAt': FieldValue.delete(),
      'firstAccessNotifiedAt': FieldValue.delete(),
      'linkLabel': FieldValue.delete(),
    });
    if (sheetContext.mounted) {
      Navigator.pop(sheetContext);
    }
    _showMessage('Share link revoked.');
  }

  Future<void> _revokeAllOwnedShareLinks({
    required BuildContext sheetContext,
  }) async {
    if (_revokingAllShareLinks) {
      return;
    }
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Revoke every share link?'),
            content: const Text(
              'This immediately closes every active share link owned by '
              'this account, across Personal and Business files. Existing '
              'downloaded copies cannot be recalled. This action cannot be '
              'undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Keep links'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.link_off_rounded),
                label: const Text('Revoke every link'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) {
      return;
    }
    if (!await _ensureAuthenticated(interactive: true) || !mounted) {
      return;
    }
    setState(() => _revokingAllShareLinks = true);
    try {
      final result = await _shareLinkOwnerService.revokeAll();
      if (!mounted) {
        return;
      }
      if (sheetContext.mounted) {
        Navigator.pop(sheetContext);
      }
      final noun = result.revokedCount == 1 ? 'link' : 'links';
      _showMessage(
        result.complete
            ? 'Revoked ${result.revokedCount} active password $noun.'
            : 'Revoked ${result.revokedCount} password $noun. More remain; run emergency revoke again.',
      );
    } on ShareOwnerException catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage(switch (error.kind) {
        ShareOwnerFailureKind.sessionExpired =>
          'Sign in again before revoking share links.',
        ShareOwnerFailureKind.temporarilyLimited =>
          'Share links were revoked recently. Refresh and retry shortly.',
        ShareOwnerFailureKind.unavailable ||
        ShareOwnerFailureKind.invalidResponse =>
          'Could not verify that every share link was revoked. Refresh and retry.',
      });
    } finally {
      if (mounted) {
        setState(() => _revokingAllShareLinks = false);
      }
    }
  }

  Future<void> _toggleOffline(_DriveFile file) async {
    final existing = _offlineFiles[file.objectKey];
    if (existing != null) {
      await _removeOfflineEntry(file.objectKey, persist: false);
      await _persistOfflineFiles();
      _showMessage('Removed ${file.name} from offline.');
      return;
    }

    if (!await _ensureOfflineReady(interactive: true)) {
      return;
    }

    await _downloadOfflineFile(file, announce: true);
  }

  bool get _hasOfflineSyncTargets {
    return _offlineFolders.isNotEmpty ||
        _offlineFiles.values.any((info) => !info.managedByFolder);
  }

  Future<bool> _ensureOfflineReady({required bool interactive}) async {
    if (!await _ensureStorageConfigured()) {
      if (interactive || !_offlineStorageWarningShown) {
        _offlineStorageWarningShown = true;
        _showMessage(
          'Secure storage is not ready yet. Please wait a moment and try again.',
        );
      }
      return false;
    }

    _offlineStorageWarningShown = false;

    if (!_passphraseRequired) {
      return true;
    }

    if (_secureSessionPassphrase != null ||
        _cachedSecureEncryptionKey != null) {
      return true;
    }

    if (!interactive) {
      if (!_offlineUnlockWarningShown) {
        _offlineUnlockWarningShown = true;
        _showMessage(
          'Unlock your encryption key in settings to sync secure folders.',
        );
      }
      return false;
    }

    final passphrase = await _collectEncryptionKey(
      isRotation: false,
      forcePrompt: true,
      title: 'Refresh secure files',
      description:
          'Enter your secure mode passphrase to refresh the activity timestamp. The passphrase stays on this device.',
      submitLabel: 'Refresh',
    );
    if (!mounted || passphrase == null) {
      return false;
    }

    setState(() {
      _secureSessionPassphrase = passphrase;
      _offlineUnlockWarningShown = false;
    });

    return true;
  }

  Future<_OfflineFileInfo?> _downloadOfflineFile(
    _DriveFile file, {
    Directory? directory,
    bool announce = false,
    bool managedByFolder = false,
    bool interactive = true,
  }) async {
    if (!_ensureStorageReadsAvailable(
      storageScope: file.storageScope,
      showFeedback: announce,
    )) {
      return null;
    }
    try {
      _ensureSessionActive();
      _ensureOwnsObjectKey(file.objectKey);
    } on _SessionExpiredException catch (error) {
      _handleSessionExpired(error);
      return null;
    }
    final targetDirectory =
        directory ?? await _ensureOfflineDirectory(interactive: interactive);
    if (targetDirectory == null) {
      return null;
    }
    final targetPath = p.join(
      targetDirectory.path,
      _offlineVault.opaqueFileName(file.objectKey),
    );
    final transferId = 'download:${file.objectKey}';
    final existingInfo = _offlineFiles[file.objectKey];

    _beginTransfer(transferId, 'Downloading ${file.name}');

    final encryptionKey = await _encryptionKeyStringForFile(
      file,
      interactive: interactive,
    );
    if (file.isEncrypted && encryptionKey == null) {
      if (announce) {
        _showMessage('Unlock this file to download it.');
      }
      _endTransfer(transferId);
      return null;
    }

    try {
      final secretKey = encryptionKey != null
          ? SecretKey(base64Decode(encryptionKey))
          : null;
      final Stream<List<int>> plaintext;
      if (file.isSharded) {
        final bytes = await _downloadFileBytes(file, secretKey: secretKey);
        plaintext = Stream<List<int>>.value(bytes);
      } else {
        plaintext = await _storageService.download(
          objectKey: file.objectKey,
          encryptionKey: secretKey,
        );
      }
      final localFile = File(targetPath);
      final protectedCopy = await _offlineVault.encryptStream(
        plaintext: plaintext,
        destination: localFile,
        objectKey: file.objectKey,
        bindingKey: secretKey,
      );
      if (!_canReadStorageScope(file.storageScope)) {
        try {
          if (await localFile.exists()) {
            await localFile.delete();
          }
        } catch (_) {
          // A later encrypted-offline cleanup retries inaccessible artifacts.
        }
        return null;
      }

      final info = _OfflineFileInfo(
        objectKey: file.objectKey,
        localPath: targetPath,
        downloadedAt: DateTime.now(),
        etag: file.etag,
        size: protectedCopy.plaintextLength,
        folderKey: _resolvedFolderKeyForFile(file),
        managedByFolder: managedByFolder,
        storageFormat: LocalOfflineVault.storageFormat,
      );
      if (mounted) {
        setState(() {
          _offlineFiles[file.objectKey] = info;
        });
      } else {
        _offlineFiles[file.objectKey] = info;
      }
      await _persistOfflineFiles();
      if (existingInfo != null && existingInfo.localPath != targetPath) {
        await _deleteOfflineLocalPath(existingInfo.localPath);
      }
      if (announce) {
        _showMessage(
          '${file.name} is encrypted on this device and ready offline.',
        );
      }
      return info;
    } catch (error) {
      if (error is _SessionExpiredException) {
        _handleSessionExpired(error);
        return null;
      }
      if (kDebugMode) {
        debugPrint('Encrypted offline download was unavailable.');
      }
      if (announce) {
        _showMessage('We couldn\'t save ${file.name} for offline use.');
      }
      return null;
    } finally {
      _endTransfer(transferId);
    }
  }

  Future<void> _removeOfflineEntry(
    String objectKey, {
    bool persist = true,
  }) async {
    final info = _offlineFiles[objectKey];
    if (info != null) {
      await _deleteOfflineLocalPath(info.localPath);
    }

    if (mounted) {
      setState(() {
        _offlineFiles.remove(objectKey);
      });
    } else {
      _offlineFiles.remove(objectKey);
    }

    if (persist) {
      await _persistOfflineFiles();
    }
  }

  Future<void> _deleteOfflineLocalPath(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final localFile = File(trimmed);
    if (!await localFile.exists()) {
      return;
    }
    try {
      await localFile.delete();
    } catch (_) {
      // The mapping is still removed. Account-scoped encryption prevents a
      // leftover vault object from being opened by another RonikCloud user.
    }
  }

  Future<_OfflineFileInfo?> _migrateLegacyOfflineEntry(
    _DriveFile file,
    _OfflineFileInfo info, {
    required bool interactive,
  }) async {
    if (info.isEncryptedVault) {
      return info;
    }
    final legacyFile = File(info.localPath);
    if (!await legacyFile.exists()) {
      await _removeOfflineEntry(file.objectKey);
      if (interactive) {
        _showMessage('Offline copy for ${file.name} is missing.');
      }
      return null;
    }

    final encryptionKey = await _encryptionKeyStringForFile(
      file,
      interactive: interactive,
    );
    if (file.isEncrypted && encryptionKey == null) {
      if (interactive) {
        _showMessage('Unlock ${file.name} to protect its old offline copy.');
      }
      return null;
    }
    final bindingKey = encryptionKey == null
        ? null
        : SecretKey(base64Decode(encryptionKey));
    final destination = File(
      p.join(
        p.dirname(legacyFile.path),
        _offlineVault.opaqueFileName(file.objectKey),
      ),
    );
    final transferId = 'offline-migration:${file.objectKey}';
    _beginTransfer(transferId, 'Protecting ${file.name}');
    try {
      final protectedCopy = await _offlineVault.encryptFile(
        source: legacyFile,
        destination: destination,
        objectKey: file.objectKey,
        bindingKey: bindingKey,
      );
      final migrated = info.copyWith(
        localPath: destination.path,
        downloadedAt: DateTime.now(),
        size: protectedCopy.plaintextLength,
        storageFormat: LocalOfflineVault.storageFormat,
      );
      if (mounted) {
        setState(() {
          _offlineFiles[file.objectKey] = migrated;
        });
      } else {
        _offlineFiles[file.objectKey] = migrated;
      }
      await _persistOfflineFiles();
      if (legacyFile.path != destination.path) {
        await _deleteOfflineLocalPath(legacyFile.path);
      }
      if (interactive) {
        _showMessage('${file.name} was upgraded to encrypted offline storage.');
      }
      return migrated;
    } on LocalOfflineVaultException catch (error) {
      if (interactive) {
        _showMessage(
          error.failure == LocalOfflineVaultFailure.keyUnavailable
              ? 'Unlock the device keychain to protect this offline copy.'
              : 'We could not upgrade the old offline copy safely.',
        );
      }
      return null;
    } finally {
      _endTransfer(transferId);
    }
  }

  void _scheduleOfflineSync() {
    if (!_hasOfflineSyncTargets || _offlineSyncScheduled) {
      return;
    }

    _offlineSyncScheduled = true;
    Future.microtask(() async {
      try {
        await _syncOfflineFolders();
      } finally {
        _offlineSyncScheduled = false;
      }
    });
  }

  Future<void> _syncOfflineFolders() async {
    if (_isSyncingOffline || !_hasOfflineSyncTargets) {
      return;
    }

    if (!await _ensureOfflineReady(interactive: false)) {
      return;
    }

    final directory = await _ensureOfflineDirectory(interactive: false);
    if (directory == null) {
      return;
    }

    _isSyncingOffline = true;
    try {
      final lookup = <String, _DriveFile>{
        for (final file in _files.where((file) => !file.isFolder))
          file.objectKey: file,
      };

      for (final config in _offlineFolders.values) {
        await _syncOfflineFolder(
          config,
          fileLookup: lookup,
          directory: directory,
        );
      }
      await _syncStandaloneOfflineFiles(lookup, directory);
    } finally {
      _isSyncingOffline = false;
    }
  }

  Future<void> _syncOfflineFolder(
    _OfflineFolderConfig config, {
    Map<String, _DriveFile>? fileLookup,
    Directory? directory,
    bool interactive = false,
  }) async {
    final lookup =
        fileLookup ??
        <String, _DriveFile>{
          for (final file in _files.where((file) => !file.isFolder))
            file.objectKey: file,
        };

    final folderFiles = <_DriveFile>[];
    for (final file in lookup.values) {
      if (!file.isFolder &&
          _resolvedFolderKeyForFile(file) == config.folderKey) {
        folderFiles.add(file);
      }
    }

    final targetDirectory =
        directory ?? await _ensureOfflineDirectory(interactive: interactive);
    if (targetDirectory == null) {
      return;
    }
    final keysToKeep = <String>{};
    var metadataChanged = false;

    for (final file in folderFiles) {
      keysToKeep.add(file.objectKey);
      var info = _offlineFiles[file.objectKey];
      if (info != null &&
          (!info.managedByFolder ||
              info.folderKey != _resolvedFolderKeyForFile(file))) {
        final updated = info.copyWith(
          folderKey: _resolvedFolderKeyForFile(file),
          managedByFolder: true,
        );
        if (mounted) {
          setState(() {
            _offlineFiles[file.objectKey] = updated;
          });
        } else {
          _offlineFiles[file.objectKey] = updated;
        }
        info = updated;
        metadataChanged = true;
      }
      if (info != null && !info.isEncryptedVault) {
        info = await _migrateLegacyOfflineEntry(
          file,
          info,
          interactive: interactive,
        );
        if (info == null) {
          continue;
        }
      }
      final localCopyPresent =
          info != null &&
          await _offlineVault.isEncryptedFile(File(info.localPath));

      final matches =
          info != null &&
          localCopyPresent &&
          info.size == file.size &&
          (file.etag == null || info.etag == null || info.etag == file.etag);
      if (matches) {
        continue;
      }

      await _downloadOfflineFile(
        file,
        directory: targetDirectory,
        managedByFolder: true,
        interactive: interactive,
      );
    }

    final staleEntries = _offlineFiles.entries.where((entry) {
      final info = entry.value;
      if (!info.managedByFolder) {
        return false;
      }
      final entryFolderKey =
          info.folderKey ??
          (() {
            final file = lookup[entry.key];
            return file == null ? null : _resolvedFolderKeyForFile(file);
          })() ??
          _folderKeyForObject(entry.key);
      if (entryFolderKey != config.folderKey) {
        return false;
      }
      return !keysToKeep.contains(entry.key);
    }).toList();

    if (staleEntries.isNotEmpty) {
      for (final entry in staleEntries) {
        await _removeOfflineEntry(entry.key, persist: false);
      }
      metadataChanged = true;
    }

    if (metadataChanged && mounted) {
      await _persistOfflineFiles();
    }
  }

  Future<void> _syncStandaloneOfflineFiles(
    Map<String, _DriveFile> fileLookup,
    Directory directory,
  ) async {
    var removedEntries = false;
    final standaloneEntries = _offlineFiles.entries
        .where((entry) => !entry.value.managedByFolder)
        .toList(growable: false);

    for (final entry in standaloneEntries) {
      final file = fileLookup[entry.key];
      if (file == null) {
        await _removeOfflineEntry(entry.key, persist: false);
        removedEntries = true;
        continue;
      }

      var info = entry.value;
      if (!info.isEncryptedVault) {
        final migrated = await _migrateLegacyOfflineEntry(
          file,
          info,
          interactive: false,
        );
        if (migrated == null) {
          continue;
        }
        info = migrated;
      }
      final localCopyPresent = await _offlineVault.isEncryptedFile(
        File(info.localPath),
      );
      final matches =
          localCopyPresent &&
          info.size == file.size &&
          (file.etag == null || info.etag == null || info.etag == file.etag);
      if (matches) {
        continue;
      }

      await _downloadOfflineFile(
        file,
        directory: directory,
        managedByFolder: false,
        interactive: false,
      );
    }

    if (removedEntries) {
      await _persistOfflineFiles();
    }
  }

  Future<void> _toggleFolderOffline(_FolderSummary summary, bool enable) async {
    final key = summary.id;
    final existing = _offlineFolders[key];

    if (!enable) {
      if (existing == null) {
        return;
      }

      if (mounted) {
        setState(() {
          _offlineFolders.remove(key);
        });
      } else {
        _offlineFolders.remove(key);
      }

      await _persistOfflineFolders();
      await _removeOfflineFolderData(key);
      _showMessage('${summary.displayName} will no longer sync offline.');
      return;
    }

    if (!await _ensureOfflineReady(interactive: true)) {
      return;
    }

    final config = _OfflineFolderConfig(
      folderKey: key,
      folderName: summary.displayName,
      addedAt: DateTime.now(),
    );

    if (mounted) {
      setState(() {
        _offlineFolders[key] = config;
      });
    } else {
      _offlineFolders[key] = config;
    }

    await _persistOfflineFolders();
    _showMessage('Preparing ${summary.displayName} for offline use...');

    final lookup = <String, _DriveFile>{
      for (final file in _files.where((file) => !file.isFolder))
        file.objectKey: file,
    };

    await _syncOfflineFolder(config, fileLookup: lookup, interactive: true);

    if (!mounted) {
      return;
    }

    final hasFiles = _files.any(
      (file) =>
          !file.isFolder && _resolvedFolderKeyForFile(file) == config.folderKey,
    );

    if (hasFiles) {
      _showMessage('${summary.displayName} is available offline.');
    } else {
      _showMessage('${summary.displayName} will sync when new files arrive.');
    }

    _scheduleOfflineSync();
  }

  Future<Directory?> _ensureOfflineDirectory({
    required bool interactive,
  }) async {
    final configuredPath = _offlineDirectoryPath?.trim();
    if (configuredPath != null && configuredPath.isNotEmpty) {
      final directory = Directory(configuredPath);
      try {
        await directory.create(recursive: true);
        await _cleanupOfflineVaultTemporaryFiles(directory);
        return directory;
      } on FileSystemException catch (_) {
        if (kDebugMode) {
          debugPrint('The configured offline directory was unavailable.');
        }
        if (interactive) {
          _showMessage(
            'We could not access $configuredPath. Choose a new folder for offline files.',
          );
        }
      } catch (_) {
        if (kDebugMode) {
          debugPrint('The configured offline directory could not be prepared.');
        }
        if (interactive) {
          _showMessage(
            'We could not access $configuredPath. Choose a new folder for offline files.',
          );
        }
      }

      await _persistOfflineDirectoryPath(null);
      if (mounted) {
        setState(() {
          _offlineDirectoryPath = null;
        });
      } else {
        _offlineDirectoryPath = null;
      }
    }

    if (!interactive) {
      if (!_offlineDirectoryWarningShown) {
        _offlineDirectoryWarningShown = true;
        _showMessage('Set up a folder for offline files before syncing.');
      }
      return null;
    }

    final directory = await _promptForOfflineDirectory();
    if (directory == null) {
      return null;
    }

    final normalizedPath = directory.path;
    if (mounted) {
      setState(() {
        _offlineDirectoryPath = normalizedPath;
        _offlineDirectoryWarningShown = false;
      });
    } else {
      _offlineDirectoryPath = normalizedPath;
      _offlineDirectoryWarningShown = false;
    }

    await _persistOfflineDirectoryPath(normalizedPath);
    return directory;
  }

  Future<Directory?> _promptForOfflineDirectory() async {
    String? selectedPath;
    try {
      selectedPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choose the encrypted offline vault folder',
      );
    } catch (_) {
      if (kDebugMode) {
        debugPrint('The offline-directory picker was unavailable.');
      }
      return await _createDefaultOfflineDirectory();
    }

    if (selectedPath == null || selectedPath.trim().isEmpty) {
      _showMessage('Select a folder for the encrypted offline vault.');
      return null;
    }

    final trimmedPath = selectedPath.trim();
    final directory = Directory(trimmedPath);
    try {
      await directory.create(recursive: true);
      await _cleanupOfflineVaultTemporaryFiles(directory);
      return directory;
    } on FileSystemException catch (_) {
      if (kDebugMode) {
        debugPrint('The selected offline directory could not be prepared.');
      }
      _showMessage(
        'We could not access the selected folder. Choose a different location.',
      );
    } catch (_) {
      if (kDebugMode) {
        debugPrint('The selected offline directory could not be prepared.');
      }
      _showMessage(
        'We could not access the selected folder. Choose a different location.',
      );
    }
    return null;
  }

  Future<Directory?> _createDefaultOfflineDirectory() async {
    try {
      final baseDir = await getApplicationSupportDirectory();
      final directory = Directory(p.join(baseDir.path, 'offline_cache'));
      await directory.create(recursive: true);
      await _cleanupOfflineVaultTemporaryFiles(directory);
      _showMessage(
        'Encrypted offline files will be kept in ${directory.path}.',
      );
      return directory;
    } catch (_) {
      if (kDebugMode) {
        debugPrint('The default offline directory could not be prepared.');
      }
      _showMessage('We could not prepare a folder for offline files.');
      return null;
    }
  }

  Future<void> _cleanupOfflineVaultTemporaryFiles(Directory directory) async {
    try {
      await _offlineVault.cleanupTemporaryFiles(directory);
    } on LocalOfflineVaultException catch (_) {
      if (kDebugMode) {
        debugPrint('Offline-vault temporary cleanup was skipped safely.');
      }
    }
  }

  Future<void> _persistOfflineDirectoryPath(String? path) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final trimmed = path?.trim();
    await _writePrivateCachePreference(
      prefs,
      baseKey: _offlineDirectoryPrefKey,
      namespace: LocalPrivateCacheCodec.offlineDirectoryNamespace,
      value: trimmed == null || trimmed.isEmpty ? null : trimmed,
    );
  }

  Future<void> _persistOfflineFiles() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final payload = _offlineFiles.values
        .map((info) => info.toJson())
        .toList(growable: false);
    await _writePrivateCachePreference(
      prefs,
      baseKey: _offlineFilesPrefKey,
      namespace: LocalPrivateCacheCodec.offlineFilesNamespace,
      value: jsonEncode(payload),
    );
  }

  Future<void> _persistOfflineFolders() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final payload = _offlineFolders.values
        .map((config) => config.toJson())
        .toList(growable: false);
    await _writePrivateCachePreference(
      prefs,
      baseKey: _offlineFoldersPrefKey,
      namespace: LocalPrivateCacheCodec.offlineFoldersNamespace,
      value: jsonEncode(payload),
    );
  }

  Future<void> _removeOfflineFolderData(String folderKey) async {
    final targets = _offlineFiles.entries
        .where((entry) {
          final info = entry.value;
          if (!info.managedByFolder) {
            return false;
          }
          final key = info.folderKey ?? _folderKeyForObject(entry.key);
          return key == folderKey;
        })
        .map((entry) => entry.key)
        .toList();

    if (targets.isEmpty) {
      return;
    }

    for (final objectKey in targets) {
      await _removeOfflineEntry(objectKey, persist: false);
    }

    await _persistOfflineFiles();
  }

  String? _folderKeyForObject(String objectKey) {
    for (final file in _files) {
      if (file.objectKey == objectKey) {
        return _resolvedFolderKeyForFile(file);
      }
    }
    return null;
  }

  Future<void> _persistBackupConfigs() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final payload = _backupFolders.values
        .map((config) => config.toJson())
        .toList(growable: false);
    await _writePrivateCachePreference(
      prefs,
      baseKey: _backupConfigsPrefKey,
      namespace: LocalPrivateCacheCodec.backupConfigsNamespace,
      value: jsonEncode(payload),
    );
  }

  Future<void> _persistBackupFingerprints() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final configKeys =
        _backupFingerprints.keys
            .where((key) => key != _backupFingerprintOrphanBucket)
            .toList()
          ..sort();

    final configs = <Map<String, dynamic>>[];
    for (final key in configKeys) {
      final entries = _backupFingerprints[key];
      if (entries == null || entries.isEmpty) {
        continue;
      }
      configs.add(<String, dynamic>{
        'path': key,
        'files': entries.values
            .map((fingerprint) => fingerprint.toJson())
            .toList(growable: false),
      });
    }

    final orphanEntries = _backupFingerprints[_backupFingerprintOrphanBucket];
    final payload = <String, dynamic>{'version': 2, 'configs': configs};

    if (orphanEntries != null && orphanEntries.isNotEmpty) {
      payload['orphans'] = orphanEntries.values
          .map((fingerprint) => fingerprint.toJson())
          .toList(growable: false);
    }

    await _writePrivateCachePreference(
      prefs,
      baseKey: _backupSignaturesPrefKey,
      namespace: LocalPrivateCacheCodec.backupFingerprintsNamespace,
      value: jsonEncode(payload),
    );
  }

  Future<void> _clearBackupFingerprintsFor(String localPath) async {
    final normalized = _normalizedLocalPath(localPath);
    final prefix = normalized.endsWith(p.separator)
        ? normalized
        : '$normalized${p.separator}';
    final bucket = _fingerprintBucket(localPath);
    if (bucket != null && bucket.isNotEmpty) {
      bucket.removeWhere(
        (path, _) => path == normalized || path.startsWith(prefix),
      );
      if (bucket.isEmpty) {
        if (normalized.isEmpty) {
          _backupFingerprints.remove(_backupFingerprintOrphanBucket);
        } else {
          _backupFingerprints.remove(normalized);
        }
      }
    }

    final orphanBucket = _backupFingerprints[_backupFingerprintOrphanBucket];
    if (orphanBucket != null && orphanBucket.isNotEmpty) {
      orphanBucket.removeWhere(
        (path, _) => path == normalized || path.startsWith(prefix),
      );
      if (orphanBucket.isEmpty) {
        _backupFingerprints.remove(_backupFingerprintOrphanBucket);
      }
    }

    await _persistBackupFingerprints();
  }

  Future<void> _updateBackupSyncTime(String localPath) async {
    final existing = _backupFolders[localPath];
    if (existing == null || !mounted) {
      return;
    }

    final updated = existing.copyWith(lastSynced: DateTime.now());
    setState(() {
      _backupFolders[localPath] = updated;
    });
    await _persistBackupConfigs();
    await _resolveBackupAttention();
  }

  String _normalizeBackupRelativePath(String relativePath) {
    final normalized = relativePath
        .split(RegExp(r'[\\/]+'))
        .where((segment) => segment.trim().isNotEmpty)
        .join('/');
    if (normalized.isEmpty) {
      return '';
    }
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  Future<String> _computeBackupPathHash(
    String relativePath, {
    required SecretKey key,
  }) {
    final normalized = _normalizeBackupRelativePath(relativePath);
    return _metadataEncryptionService.backupPathTag(
      normalizedRelativePath: normalized,
      key: key,
    );
  }

  String _backupObjectKeyName(String backupPathHash) {
    final trimmed = backupPathHash.trim();
    if (trimmed.isEmpty) {
      return 'backup-file';
    }
    return 'backup-$trimmed';
  }

  Future<String> _backupPathHashForFile(
    File file,
    String localRoot, {
    required SecretKey key,
  }) {
    final relativePath = p.relative(file.path, from: localRoot);
    return _computeBackupPathHash(relativePath, key: key);
  }

  Future<Map<String, BackupCatalogEntry>> _loadRemoteBackupCatalog(
    String folderId,
  ) async {
    if (!await _ensureAuthenticated(interactive: false)) {
      throw StateError('Backup requires an authenticated session.');
    }
    // A missing catalogue must never be treated as an empty remote backup:
    // that would bypass conflict checks. Fail visibly and allow retry.
    return await _driveRepository
        .loadBackupCatalog(ownerId: widget.user.uid, folderId: folderId)
        .timeout(const Duration(seconds: 30));
  }

  _BackupFileFingerprint? _referenceBackupFingerprint(
    _BackupFileFingerprint? localFingerprint,
    BackupCatalogEntry? remoteEntry, {
    required String localPath,
  }) {
    if (remoteEntry == null) {
      return localFingerprint;
    }
    final remoteIntegrityTag = remoteEntry.contentIntegrityTag.trim();
    final legacyRemoteHash = remoteEntry.legacyHashBase64.trim();
    if (localFingerprint == null) {
      return _BackupFileFingerprint(
        localPath: localPath,
        size: remoteEntry.size,
        modified: remoteEntry.modified,
        hash: legacyRemoteHash,
        remoteIntegrityTag: remoteIntegrityTag,
      );
    }
    if (localFingerprint.hash.isNotEmpty) {
      return localFingerprint.copyWith(remoteIntegrityTag: remoteIntegrityTag);
    }
    if (legacyRemoteHash.isEmpty) {
      return localFingerprint.copyWith(remoteIntegrityTag: remoteIntegrityTag);
    }
    if (localFingerprint.modified.toUtc().millisecondsSinceEpoch >=
            remoteEntry.modified.toUtc().millisecondsSinceEpoch &&
        localFingerprint.size == remoteEntry.size) {
      return localFingerprint.copyWith(remoteIntegrityTag: remoteIntegrityTag);
    }
    return _BackupFileFingerprint(
      localPath: localPath,
      size: remoteEntry.size,
      modified: remoteEntry.modified,
      hash: legacyRemoteHash,
      remoteIntegrityTag: remoteIntegrityTag,
    );
  }

  bool _blocksPlaintextLocalWrite(_DriveFile file) {
    return file.isSecured;
  }

  Future<void> _persistPassphraseSetting() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await _writeAccountScopedBoolPreference(
      prefs,
      'workspace_passphrase_required_v1',
      _passphraseRequired,
    );
  }

  Future<({Uint8List salt, SecretKey key})> _persistRemoteEncryptionPassword(
    String passphrase,
  ) async {
    final twoFactorReady = await _ensureTwoFactorSession(interactive: true);
    if (!twoFactorReady) {
      throw const EncryptionPasswordException(
        'Security verification is required before setting up encryption.',
      );
    }
    await _refreshUserIdToken();

    try {
      final salt = await _encryptionSetupService.ensureStandardEncryptionSalt();
      final key = await EncryptionService.instance.deriveKey(
        password: passphrase,
        salt: salt,
      );
      return (salt: salt, key: key);
    } on EncryptionSetupException {
      if (kDebugMode) {
        debugPrint(
          '[ENCRYPTION] Callable setup was unavailable; using the protected transactional fallback.',
        );
      }
      try {
        return await _persistRemoteEncryptionPasswordViaFirestore(passphrase);
      } catch (fallbackError) {
        throw EncryptionPasswordException(
          'Failed to safely load or create encryption setup. '
          'No encryption parameters were overwritten.',
          cause: fallbackError,
        );
      }
    }
  }

  Future<({Uint8List salt, SecretKey key})>
  _persistRemoteEncryptionPasswordViaFirestore(String passphrase) async {
    try {
      final userDoc = widget.firestore.collection('users').doc(widget.user.uid);
      Future<Uint8List>
      ensureSalt() => widget.firestore.runTransaction<Uint8List>((
        transaction,
      ) async {
        final snapshot = await transaction.get(userDoc);
        final rawSalt = snapshot.data()?['encryptionSalt'];
        if (rawSalt is String && rawSalt.trim().isNotEmpty) {
          final existing = Uint8List.fromList(base64Decode(rawSalt.trim()));
          if (existing.length < 16) {
            throw const EncryptionPasswordException(
              'The stored encryption parameters are invalid and were not replaced.',
            );
          }
          return existing;
        }
        final salt = _generateRandomBytes(16);
        transaction.set(userDoc, <String, dynamic>{
          if (!snapshot.exists) ...<String, dynamic>{
            'profilePrivacyVersion': accountProfilePrivacyVersion,
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          },
          'encryptionSalt': base64Encode(salt),
          'encryptionUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        return salt;
      }, timeout: const Duration(seconds: 15));
      Uint8List salt;
      try {
        salt = await ensureSalt();
      } on FirebaseException catch (error) {
        if (!_shouldRetryWithFreshAuth(error)) rethrow;
        await _refreshUserIdToken();
        salt = await ensureSalt();
      }
      final key = await EncryptionService.instance.deriveKey(
        password: passphrase,
        salt: salt,
      );
      return (salt: salt, key: key);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('The protected encryption-setup fallback failed safely.');
      }
      throw EncryptionPasswordException(
        'Unable to save encryption setup safely. No encryption parameters were changed.',
        cause: error,
      );
    }
  }

  Future<({Uint8List salt, SecretKey key})> _persistRemoteSecurePassphrase(
    String passphrase, {
    bool rotate = false,
  }) async {
    final twoFactorReady = await _ensureTwoFactorSession(interactive: true);
    if (!twoFactorReady) {
      throw const EncryptionPasswordException(
        'Security verification is required before setting up secure mode.',
      );
    }

    try {
      final userDoc = widget.firestore.collection('users').doc(widget.user.uid);
      Future<Uint8List>
      persistSalt() => widget.firestore.runTransaction<Uint8List>((
        transaction,
      ) async {
        final snapshot = await transaction.get(userDoc);
        final rawSalt = snapshot.data()?['secureEncryptionSalt'];
        if (!rotate && rawSalt is String && rawSalt.trim().isNotEmpty) {
          final existing = Uint8List.fromList(base64Decode(rawSalt.trim()));
          if (existing.length < 16) {
            throw const EncryptionPasswordException(
              'The stored secure-mode parameters are invalid and were not replaced.',
            );
          }
          return existing;
        }
        final salt = _generateRandomBytes(16);
        transaction.set(userDoc, <String, dynamic>{
          if (!snapshot.exists) ...<String, dynamic>{
            'profilePrivacyVersion': accountProfilePrivacyVersion,
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          },
          'secureEncryptionSalt': base64Encode(salt),
          'secureEncryptionUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        return salt;
      }, timeout: const Duration(seconds: 15));
      Uint8List salt;
      try {
        salt = await persistSalt();
      } on FirebaseException catch (error) {
        if (!_shouldRetryWithFreshAuth(error)) rethrow;
        final refreshedSecurity =
            await _forceTwoFactorReverificationIfEnabled();
        if (!refreshedSecurity) {
          throw EncryptionPasswordException(
            'Security verification is required before setting up secure mode.',
            cause: error,
          );
        }
        await _refreshUserIdToken();
        salt = await persistSalt();
      }
      final key = await EncryptionService.instance.deriveKey(
        password: passphrase,
        salt: salt,
      );
      return (salt: salt, key: key);
    } catch (error) {
      if (error is EncryptionPasswordException) {
        rethrow;
      }
      throw EncryptionPasswordException(
        'Unable to save secure-mode setup safely. No encryption parameters were changed.',
        cause: error,
      );
    }
  }

  Uint8List _generateRandomBytes(int length) {
    final random = Random.secure();
    final values = List<int>.generate(length, (_) => random.nextInt(256));
    return Uint8List.fromList(values);
  }

  bool _bytesEqual(Uint8List? a, Uint8List? b) {
    if (identical(a, b)) {
      return true;
    }
    if (a == null || b == null) {
      return false;
    }
    if (a.lengthInBytes != b.lengthInBytes) {
      return false;
    }
    for (var i = 0; i < a.lengthInBytes; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  Future<void> _persistDisplaySetting({bool syncRemote = true}) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final value = _storageDisplayPreferenceValue(_storageDisplay);
    await prefs.setString('workspace_storage_display_v1', value);

    if (!syncRemote) {
      return;
    }

    try {
      await widget.firestore
          .collection('users')
          .doc(widget.user.uid)
          .set({
            'storageUsageDisplay': value,
            'storageUsageDisplayUpdatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true))
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      if (kDebugMode) {
        debugPrint('The storage-display preference could not be synchronized.');
      }
    }
  }

  Future<void> _persistStorageLocationSetting() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final location = switch (_storageLocation) {
      _StorageCapacityLocation.summaryCard => 'card',
      _StorageCapacityLocation.header => 'header',
      _StorageCapacityLocation.hidden => 'hidden',
    };
    await prefs.setString('workspace_storage_location_v1', location);
  }

  Future<void> _persistTileDensitySetting() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await _writeAccountScopedStringPreference(
      prefs,
      _workspaceTileDensityPrefKey,
      _tileDensity.storageKey,
    );
  }

  Future<void> _persistFolderPlacementSetting() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await _writeAccountScopedStringPreference(
      prefs,
      _workspaceFolderPlacementPrefKey,
      _folderPlacement.storageKey,
    );
  }

  Future<void> _persistBackupScanFrequency() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await _writeAccountScopedStringPreference(
      prefs,
      _backupScanRatePrefKey,
      _backupScanFrequency.storageKey,
    );
  }

  Future<void> _persistBackgroundBackupPreference() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await _writeAccountScopedBoolPreference(
      prefs,
      _backupBackgroundEnabledPrefKey,
      _backgroundBackupEnabled,
    );
    await _writeAccountScopedBoolPreference(
      prefs,
      _backupBackgroundPreferenceSetPrefKey,
      _backgroundBackupPreferenceSet,
    );
  }

  Future<void> _setBackgroundBackupEnabled(
    bool enabled, {
    bool showFeedback = true,
    bool markConfigured = true,
  }) async {
    if (enabled && !_supportsBackgroundBackupSources) {
      if (showFeedback && mounted) {
        _showMessage(_folderBackupUnavailableMessage);
      }
      return;
    }
    final changed =
        _backgroundBackupEnabled != enabled ||
        (markConfigured && !_backgroundBackupPreferenceSet);

    if (!changed) {
      return;
    }

    setState(() {
      _backgroundBackupEnabled = enabled;
      if (markConfigured) {
        _backgroundBackupPreferenceSet = true;
      }
    });
    await _persistBackgroundBackupPreference();

    if (enabled) {
      for (final config in _backupFolders.values) {
        if (!config.enabled) {
          continue;
        }
        await _startBackupListener(config);
      }
      _updateBackupScanTimerState(forceRestart: true);
      if (BackgroundService.supportsDetachedDesktopWorker) {
        unawaited(BackgroundService.ensureDesktopWorkerRunning());
      }
    } else {
      final listenerPaths = _backupListeners.keys.toList(growable: false);
      for (final localPath in listenerPaths) {
        await _stopBackupListener(localPath);
      }
      _updateBackupScanTimerState(forceRestart: true);
    }

    if (!showFeedback || !mounted) {
      return;
    }

    _showMessage(
      enabled
          ? 'Background backup sync is enabled.'
          : 'Background backup sync is disabled.',
    );
  }

  Future<bool> _ensureBackgroundBackupPreference() async {
    if (!_supportsBackgroundBackupSources) return false;
    if (_backgroundBackupPreferenceSet) {
      return _backgroundBackupEnabled;
    }

    if (!mounted) {
      await _setBackgroundBackupEnabled(false, showFeedback: false);
      return false;
    }

    final allow = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Enable background backup sync?'),
        content: const Text(
          'Allow RonikCloud to keep selected backup folders up to date automatically. On desktop release builds, RonikCloud can continue uploading after you close the window. On mobile, the system can wake it up periodically when allowed. Web does not support closed-app folder backups. Files stay encrypted on this device before upload.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Enable'),
          ),
        ],
      ),
    );

    await _setBackgroundBackupEnabled(allow == true, showFeedback: false);
    return allow == true;
  }

  void _handleSearchChanged(String value) {
    setState(() {
      _searchQuery = value;
      if (value.trim().isNotEmpty) {
        _recentExpanded = true;
      } else {
        _recentExpanded = false;
      }
    });
  }

  void _clearSearchQuery() {
    if (_searchQuery.isEmpty) {
      return;
    }
    setState(() {
      _searchQuery = '';
      _recentExpanded = false;
    });
    _searchController.clear();
  }

  void _toggleRecentExpanded() {
    setState(() {
      _recentExpanded = !_recentExpanded;
    });
  }

  String _normalizeSearchQuery(String query) => query.trim().toLowerCase();

  List<String> _searchTokens(String query) {
    final normalized = _normalizeSearchQuery(query);
    if (normalized.isEmpty) {
      return const <String>[];
    }
    return normalized
        .split(RegExp(r'[\s/\-_.]+'))
        .where((token) => token.isNotEmpty)
        .toList();
  }

  bool _matchesSearch(
    String normalizedQuery,
    List<String> tokens,
    Iterable<String?> values,
  ) {
    if (normalizedQuery.isEmpty) {
      return true;
    }

    final normalizedValues = <String>[];
    for (final value in values) {
      if (value == null) {
        continue;
      }
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      normalizedValues.add(trimmed.toLowerCase());
    }

    if (normalizedValues.isEmpty) {
      return false;
    }

    if (normalizedValues.any((value) => value.contains(normalizedQuery))) {
      return true;
    }

    if (tokens.isEmpty) {
      return false;
    }

    for (final token in tokens) {
      final matchesToken = normalizedValues.any(
        (value) => value.contains(token),
      );
      if (!matchesToken) {
        return false;
      }
    }

    return true;
  }

  Iterable<String?> _folderSearchValues(_FolderListItem item) {
    final folder = item.folder;
    return <String?>[
      item.summary.displayName,
      item.summary.description,
      item.summary.id,
      folder?.name,
      folder?.id,
      folder?.systemKey,
      folder?.colorHex,
      if (item.summary.isRoot) 'my drive',
    ];
  }

  Iterable<String?> _fileSearchValues(_DriveFile file) {
    final extension = p.extension(file.name);
    final normalizedExtension = extension.startsWith('.')
        ? extension.substring(1)
        : extension;
    return <String?>[
      file.name,
      file.objectKey,
      file.folderName,
      file.folderLabel,
      file.contentType,
      file.hash,
      file.encryptionMode,
      if (file.isSecured) 'secure',
      ...file.pathSegments,
      if (extension.isNotEmpty) extension,
      if (normalizedExtension.isNotEmpty) normalizedExtension,
    ];
  }

  Iterable<String?> _offlineSearchValues(_OfflineEntry entry) {
    final localPath = entry.info.localPath;
    final baseName = localPath.isEmpty ? null : p.basename(localPath);
    return <String?>[
      entry.file.name,
      entry.file.folderLabel,
      entry.info.folderKey,
      localPath,
      baseName,
      ...entry.file.pathSegments,
    ];
  }

  Iterable<String?> _backupSearchValues(_BackupFolderConfig config) {
    final baseName = p.basename(config.localPath);
    return <String?>[
      config.remoteFolder,
      config.localPath,
      baseName,
      if (baseName.isNotEmpty && baseName != config.remoteFolder)
        baseName.toLowerCase(),
    ];
  }

  bool _updateStorageLocation(_StorageCapacityLocation location) {
    if (_storageLocation == location) {
      return false;
    }
    setState(() {
      _storageLocation = location;
    });
    unawaited(_persistStorageLocationSetting());
    return true;
  }

  bool _updateTileDensity(_WorkspaceTileDensity density) {
    if (_tileDensity == density) {
      return false;
    }
    setState(() {
      _tileDensity = density;
    });
    unawaited(_persistTileDensitySetting());
    _showMessage('Workspace tiles set to ${density.label.toLowerCase()}.');
    return true;
  }

  bool _updateFolderPlacement(_WorkspaceFolderPlacement placement) {
    if (_folderPlacement == placement) {
      return false;
    }
    setState(() {
      _folderPlacement = placement;
    });
    unawaited(_persistFolderPlacementSetting());
    _showMessage('Folder position set to ${placement.label.toLowerCase()}.');
    return true;
  }

  String _storageDisplayFeedbackText(_StorageDisplayMode mode) {
    return switch (mode) {
      _StorageDisplayMode.percentage =>
        'Storage usage will now display as a percentage.',
      _StorageDisplayMode.amount =>
        'Storage usage will now show used and total capacity.',
    };
  }

  _StorageDisplayMode? _parseStorageDisplayMode(String? value) {
    return switch (value?.trim().toLowerCase()) {
      'percentage' => _StorageDisplayMode.percentage,
      'amount' => _StorageDisplayMode.amount,
      'remaining' => _StorageDisplayMode.amount,
      _ => null,
    };
  }

  String _storageDisplayPreferenceValue(_StorageDisplayMode mode) {
    return switch (mode) {
      _StorageDisplayMode.percentage => 'percentage',
      _StorageDisplayMode.amount => 'amount',
    };
  }

  double _trackedUsageBytes({double? pendingBytes}) {
    final profile = _profileUsageBytes;
    final computed = _fileUsageBytes;
    final pending = pendingBytes ?? _pendingUploadBytes;
    final baseUsage = _preferredUsageBase(
      profileUsage: profile,
      computedUsage: computed,
    );
    final pendingContribution = (pending.isFinite && pending > 0)
        ? pending
        : 0.0;
    return baseUsage + pendingContribution;
  }

  double _remainingStorageBytes({double? pendingBytes}) {
    final limit = _storageLimitBytes;
    if (!_storageHasLimit || limit == null || !limit.isFinite || limit <= 0) {
      return 0.0;
    }
    return max(0.0, limit - _trackedUsageBytes(pendingBytes: pendingBytes));
  }

  bool _ensureStorageReadsAvailable({
    String? storageScope,
    bool showFeedback = true,
  }) {
    final scope = storageScope ?? _activeStorageScope;
    if (_canReadStorageScope(scope)) {
      return true;
    }
    if (showFeedback) {
      _showMessage(
        'Your current Business permissions do not allow file downloads. '
        'Refresh company access if an administrator changed them.',
      );
    }
    return false;
  }

  bool _ensureStorageSharesAvailable({
    String? storageScope,
    bool showFeedback = true,
  }) {
    final scope = storageScope ?? _activeStorageScope;
    if (_canShareStorageScope(scope)) {
      return true;
    }
    if (showFeedback) {
      _showMessage(
        'Your current Business permissions do not allow sharing from this '
        'space. Refresh company access if an administrator changed them.',
      );
    }
    return false;
  }

  bool _ensureStorageWritesAvailable({
    String? storageScope,
    bool showFeedback = true,
  }) {
    final scope = storageScope ?? _activeStorageScope;
    if (!_canWriteStorageScope(scope)) {
      if (showFeedback) {
        _showMessage(
          'Your current Business permissions do not allow changes in this '
          'space. Refresh company access if an administrator changed them.',
        );
      }
      return false;
    }
    if (!_storageInventoryStatus.blocksWrites) {
      return true;
    }
    if (showFeedback) {
      _showMessage(_storageInventoryStatus.userMessage);
    }
    return false;
  }

  bool _ensureStorageCapacityForBytes(
    int additionalBytes, {
    required String actionLabel,
    String? itemLabel,
    bool showFeedback = true,
  }) {
    final limit = _storageLimitBytes;
    if (additionalBytes <= 0 ||
        !_storageHasLimit ||
        limit == null ||
        !limit.isFinite ||
        limit <= 0) {
      return true;
    }

    final projectedUsage = _trackedUsageBytes(
      pendingBytes: _pendingUploadBytes + additionalBytes,
    );
    if (projectedUsage <= limit) {
      unawaited(_recordActivity(ActivityKind.storageFull, resolved: true));
      return true;
    }

    unawaited(_recordActivity(ActivityKind.storageFull));
    if (showFeedback) {
      final remainingLabel = _formatStorageValue(_remainingStorageBytes());
      final neededLabel = _formatStorageValue(additionalBytes.toDouble());
      final limitLabel = _formatStorageValue(limit);
      final trimmedItem = itemLabel?.trim();
      final subject = trimmedItem == null || trimmedItem.isEmpty
          ? actionLabel
          : '$actionLabel for $trimmedItem';
      _showMessage(
        '$subject blocked. This needs $neededLabel, but only $remainingLabel is left on your $limitLabel plan.',
      );
    }
    return false;
  }

  void _applyConfirmedUploadedBytes(int bytes, {String? objectKey}) {
    if (bytes <= 0) {
      return;
    }

    final existingFile = objectKey == null
        ? null
        : _knownFileByObjectKey(objectKey);
    final deltaBytes = existingFile == null ? bytes : bytes - existingFile.size;
    if (deltaBytes == 0) {
      return;
    }

    final baseline = _preferredUsageBase(
      profileUsage: _profileUsageBytes,
      computedUsage: _fileUsageBytes,
    );
    final nextComputedUsage = max(0.0, baseline + deltaBytes);
    final totals = _calculateUsageTotals(computedUsage: nextComputedUsage);

    if (!mounted) {
      _fileUsageBytes = nextComputedUsage;
      _usedBytes = totals.used;
      _totalBytes = totals.total;
      return;
    }

    setState(() {
      _fileUsageBytes = nextComputedUsage;
      _usedBytes = totals.used;
      _totalBytes = totals.total;
    });
  }

  bool _changeStorageDisplay(
    _StorageDisplayMode mode, {
    bool showFeedback = false,
  }) {
    if (_storageDisplay == mode) {
      return false;
    }
    setState(() {
      _storageDisplay = mode;
    });
    unawaited(_persistDisplaySetting());
    if (showFeedback) {
      _showMessage(_storageDisplayFeedbackText(mode));
    }
    return true;
  }

  bool _updateBackupScanFrequency(_BackupScanFrequency frequency) {
    if (_backupScanFrequency == frequency) {
      return false;
    }
    setState(() {
      _backupScanFrequency = frequency;
    });
    _updateBackupScanTimerState(forceRestart: true);
    unawaited(_persistBackupScanFrequency());
    return true;
  }

  final Map<String, String> _backupIssues = {};
  void _setBackupIssue(String path, String message) {
    if (mounted) setState(() => _backupIssues[path] = message);
    unawaited(_recordActivity(ActivityKind.backupProblem));
  }

  bool _addingBackupFolder = false;

  Future<void> _managePhotoAccess() async {
    try {
      await IosPhotoLibrary.manageAccess();
    } catch (error) {
      if (mounted) _showMessage(IosPhotoLibrary.message(error));
    }
  }

  Future<void> _addPhotoBackup() async {
    if (_addingBackupFolder || !IosPhotoLibrary.supported) return;
    _addingBackupFolder = true;
    try {
      final existing = _backupFolders[IosPhotoLibrary.sourcePath];
      if (existing != null) {
        await _managePhotoAccess();
        return;
      }
      final agreed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Back up your photos'),
          content: const Text(
            'Back up original photos you allow RonikCloud to access. Choose '
            'limited access in the next iOS screen to select photos, or full '
            'access to include new photos automatically.\n\n'
            'Images are encrypted before upload. This backs up original still '
            'images, including the still image of Live Photos; videos and Photos '
            'edits are not included. Deleting a photo on your phone will not '
            'delete its backup. iCloud photos need a download first.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (agreed != true || !mounted) return;
      final status = await IosPhotoLibrary.authorization(request: true);
      if (!mounted) return;
      if (status != 'limited' && status != 'authorized') {
        _showMessage(
          'Allow Photos access in iOS Settings to enable photo backup.',
        );
        return;
      }
      final remoteName = await _promptForRemoteFolderName(
        suggested: 'iPhone Photos',
      );
      if (!mounted || remoteName == null) return;
      await _ensureBackgroundBackupPreference();
      if (!mounted) return;
      final config = _BackupFolderConfig(
        localPath: IosPhotoLibrary.sourcePath,
        remoteFolder: remoteName,
        enabled: true,
        lastSynced: null,
        photoLibrary: true,
      );
      setState(() {
        _backupFolders[config.localPath] = config;
        _workspaceDestination = 1;
      });
      _allowBackupWork(config.localPath);
      await _persistBackupConfigs();
      await _runPhotoBackup(config, interactive: true);
      _updateBackupScanTimerState();
    } catch (error) {
      if (mounted) _showMessage(IosPhotoLibrary.message(error));
    } finally {
      _addingBackupFolder = false;
    }
  }

  Future<void> _runPhotoBackup(
    _BackupFolderConfig config, {
    required bool interactive,
  }) async {
    if (!IosPhotoLibrary.supported || _sessionInvalidated || !config.enabled) {
      return;
    }

    final configKey = _normalizedLocalPath(config.localPath);
    if (!_fullBackupInFlightConfigs.add(configKey)) return;
    _setBackupProgress(config.localPath, _BackupProgressStatus.scanning());
    try {
      if (!_ensureStorageWritesAvailable(showFeedback: interactive) ||
          !await _ensureStorageConfigured()) {
        return;
      }
      final keyString = await _requireUploadEncryptionKey(
        interactive: interactive,
      );
      if (keyString == null) {
        _setBackupIssue(
          config.localPath,
          'Unlock encryption, then retry photo backup.',
        );
        return;
      }
      final key = SecretKey(base64Decode(keyString));
      final bucket = _fingerprintBucket(config.localPath, create: true)!;
      final folderId = await _deriveBackupFolderId(config, key: key);
      final remoteCatalog = await _loadRemoteBackupCatalog(folderId);
      var scanned = 0;
      var failed = 0;
      if (mounted) setState(() => _backupIssues.remove(config.localPath));
      await for (final asset in IosPhotoLibrary.assets()) {
        if (!mounted ||
            _sessionInvalidated ||
            _isBackupCancelled(config.localPath)) {
          return;
        }
        scanned++;
        _setBackupProgress(
          config.localPath,
          _BackupProgressStatus.scanning().copyWith(scannedFiles: scanned),
        );
        final sourcePath = _normalizedLocalPath(asset.sourcePath);
        final pathTag = await _computeBackupPathHash(asset.token, key: key);
        final previous = _referenceBackupFingerprint(
          bucket[sourcePath],
          remoteCatalog[pathTag],
          localPath: sourcePath,
        );
        if (previous != null) bucket[sourcePath] = previous;
        if (previous != null && previous.modified == asset.modified) continue;
        IosPhotoExport? exported;
        try {
          exported = await IosPhotoLibrary.export(asset);
          if (!mounted ||
              _sessionInvalidated ||
              _isBackupCancelled(config.localPath)) {
            return;
          }
          final result = await _handleBackupFile(
            config,
            File(exported.path),
            photoAsset: asset,
            photoName: exported.name,
            uploadEncryptionKeyString: keyString,
            uploadSecretKey: key,
            persistFingerprint: true,
            interactiveAuth: interactive,
          );
          if (result.failed) {
            failed++;
            if (!result.shouldRetry) break;
          }
        } catch (_) {
          failed++;
        } finally {
          if (exported != null) await IosPhotoLibrary.release(exported);
        }
      }
      if (!mounted ||
          _sessionInvalidated ||
          _isBackupCancelled(config.localPath)) {
        return;
      }
      if (failed > 0) {
        _setBackupIssue(
          config.localPath,
          '$failed photo(s) could not be backed up. Retry when connected and check storage space.',
        );
      } else {
        await _persistBackupFingerprints();
        await _updateBackupSyncTime(config.localPath);
        if (interactive) {
          _showMessage(
            scanned == 0
                ? 'No accessible photos. Use Manage Photos access to choose photos.'
                : 'Photo backup is up to date for the photos you allow access to.',
          );
        }
      }
    } catch (error) {
      _setBackupIssue(config.localPath, IosPhotoLibrary.message(error));
    } finally {
      _fullBackupInFlightConfigs.remove(configKey);
      _setBackupProgress(config.localPath, null);
    }
  }

  Future<void> _addBackupFolder() async {
    if (_addingBackupFolder || !mounted) return;
    _addingBackupFolder = true;
    try {
      await _chooseAndAddBackupFolder();
    } catch (_) {
      if (mounted) {
        _showMessage(
          'We could not finish setting up this backup. Check folder access and try again.',
        );
      }
    } finally {
      _addingBackupFolder = false;
    }
  }

  Future<void> _chooseAndAddBackupFolder() async {
    if (!_supportsPersistentFolderBackups) {
      _showMessage(_folderBackupUnavailableMessage);
      return;
    }

    final grant = PersistentFolderAccess.requiresBookmark
        ? await PersistentFolderAccess.pick()
        : null;
    final selected = PersistentFolderAccess.requiresBookmark
        ? grant?.path
        : await FilePicker.platform.getDirectoryPath(
            dialogTitle: 'Select a folder to back up',
          );
    if (!mounted || _sessionInvalidated ||
        selected == null || selected.trim().isEmpty) {
      return;
    }
    final lease = await PersistentFolderAccess.acquire(
      path: selected,
      bookmark: grant?.bookmark,
    );
    try {
      if (!await Directory(selected).exists()) {
        if (mounted) {
          _showMessage('This folder is unavailable. Choose another folder.');
        }
        return;
      }
      if (!mounted || _sessionInvalidated) return;

      final remoteName = await _promptForRemoteFolderName(
        suggested: p.basename(selected),
      );
      if (!mounted || _sessionInvalidated || remoteName == null) {
        return;
      }

      final backgroundSyncEnabled = await _ensureBackgroundBackupPreference();
      if (!mounted || _sessionInvalidated) return;
      final existing = _backupFolders[selected];
      if (existing?.accessBookmark != grant?.bookmark) {
        await _stopBackupListener(selected);
        if (!mounted || _sessionInvalidated) return;
      }
      final shouldResetFingerprints =
          existing == null || existing.remoteFolder != remoteName;

      final config = _BackupFolderConfig(
        localPath: selected,
        accessBookmark: grant?.bookmark,
        remoteFolder: remoteName,
        enabled: true,
        lastSynced: null,
      );

      setState(() {
        _backupFolders[selected] = config;
        _workspaceDestination = 1;
        _searchController.clear();
        _searchQuery = '';
      });
      _allowBackupWork(selected);
      await _persistBackupConfigs();
      if (shouldResetFingerprints) {
        await _clearBackupFingerprintsFor(selected);
      }
      await _runBackupNow(config, allowInteractivePrompt: true);
      if (!mounted) return;
      if (backgroundSyncEnabled) {
        await _startBackupListener(config);
        _updateBackupScanTimerState();
        if (BackgroundService.supportsDetachedDesktopWorker) {
          unawaited(BackgroundService.ensureDesktopWorkerRunning());
        }
      } else {
        _updateBackupScanTimerState(forceRestart: true);
      }
    } finally {
      await lease.close();
    }
  }

  Future<void> _startBackupListener(_BackupFolderConfig config) async {
    if (!_canRunBackupConfig(config) ||
        config.photoLibrary ||
        !_supportsForegroundBackupWatchers ||
        _backupListeners.containsKey(config.localPath)) {
      return;
    }
    FolderAccessLease? lease;
    var retained = false;
    try {
      lease = await PersistentFolderAccess.acquire(
        path: config.localPath,
        bookmark: config.accessBookmark,
      );
      if (!mounted ||
          _sessionInvalidated ||
          _isBackupCancelled(config.localPath)) {
        return;
      }
      await _startBackupListenerWithAccess(config);
      if (!mounted ||
          _sessionInvalidated ||
          _isBackupCancelled(config.localPath)) {
        await _backupListeners.remove(config.localPath)?.cancel();
        return;
      }
      if (_backupListeners.containsKey(config.localPath)) {
        final held = _backupFolderLeases.putIfAbsent(
          config.localPath,
          () => lease!,
        );
        retained = identical(held, lease);
      }
    } on FolderAccessException catch (error) {
      _setBackupIssue(config.localPath, error.message);
    } finally {
      if (!retained) await lease?.close();
    }
  }

  Future<void> _startBackupListenerWithAccess(
    _BackupFolderConfig config,
  ) async {
    if (!_canRunBackupConfig(config) || config.photoLibrary) {
      return;
    }
    final configReference = _backupConfigDebugLabel(config);
    if (!_supportsForegroundBackupWatchers) {
      BackgroundBackupRunner.log(
        'backup',
        'event=watcher_unsupported item=$configReference '
            'platform=${defaultTargetPlatform.name}.',
      );
      return;
    }
    _allowBackupWork(config.localPath);
    if (_backupListeners.containsKey(config.localPath)) {
      return;
    }
    final directory = Directory(config.localPath);
    if (!await directory.exists()) {
      _showMessage(
        'The selected backup folder is no longer available. Choose it again.',
      );
      return;
    }
    if (!await _ensureStorageConfigured()) {
      _showMessage(
        'Secure storage is not ready yet. Please wait a moment and try again.',
      );
      return;
    }

    Stream<FileSystemEvent> events;
    if (!mounted ||
        _sessionInvalidated ||
        _isBackupCancelled(config.localPath)) {
      return;
    }
    try {
      events = directory.watch(recursive: true);
    } catch (error) {
      BackgroundBackupRunner.logFailure(
        'backup',
        'watcher_start',
        error,
        itemReference: configReference,
      );
      _showMessage(
        'We couldn\'t watch this backup folder. Check system permissions.',
      );
      return;
    }

    final subscription = events.listen(
      (event) {
        Future.microtask(() {
          final normalizedConfigPath = _normalizedLocalPath(config.localPath);
          if (event.isDirectory) {
            return;
          }

          if (event is FileSystemDeleteEvent) {
            final normalized = _normalizedLocalPath(event.path);
            if (_removeFingerprintForConfig(config.localPath, normalized)) {
              unawaited(_persistBackupFingerprints());
            }
            return;
          }

          if (event is FileSystemCreateEvent ||
              event is FileSystemModifyEvent ||
              event is FileSystemMoveEvent) {
            final path =
                event is FileSystemMoveEvent && event.destination != null
                ? event.destination!
                : event.path;
            if (_fullBackupInFlightConfigs.contains(normalizedConfigPath)) {
              _queueWatchedFileForBackup(config.localPath, path);
              return;
            }
            _queueWatchedFileForBackup(config.localPath, path);
          }
        });
      },
      onError: (Object error) {
        Future.microtask(() {
          BackgroundBackupRunner.logFailure(
            'backup',
            'watcher_event',
            error,
            itemReference: configReference,
          );
        });
      },
    );

    _backupListeners[config.localPath] = subscription;
  }

  _BackupFolderConfig? _backupConfigForLocalPath(String localPath) {
    final direct = _backupFolders[localPath];
    if (direct != null) {
      return direct;
    }

    final normalizedLocalPath = _normalizedLocalPath(localPath);
    for (final entry in _backupFolders.entries) {
      if (_normalizedLocalPath(entry.key) == normalizedLocalPath) {
        return entry.value;
      }
    }
    return null;
  }

  String _backupConfigDebugLabel(_BackupFolderConfig config) {
    return BackgroundBackupRunner.localItemDebugLabel(
      '${_normalizedLocalPath(config.localPath)}\u0000'
      '${config.remoteFolder.trim().toLowerCase()}',
    );
  }

  String _backupFileDebugLabel(File file) {
    return BackgroundBackupRunner.localItemDebugLabel(
      _normalizedLocalPath(file.path),
    );
  }

  void _cancelBackupWork(String localPath) {
    _cancelledBackupConfigs.add(_normalizedLocalPath(localPath));
  }

  void _allowBackupWork(String localPath) {
    _cancelledBackupConfigs.remove(_normalizedLocalPath(localPath));
  }

  bool _isBackupCancelled(String localPath) {
    final normalizedLocalPath = _normalizedLocalPath(localPath);
    if (_cancelledBackupConfigs.contains(normalizedLocalPath)) {
      return true;
    }

    final config = _backupConfigForLocalPath(localPath);
    return config == null || !config.enabled || !_canRunBackupConfig(config);
  }

  Future<void> _stopBackupListener(String localPath) async {
    _cancelBackupWork(localPath);
    final subscription = _backupListeners.remove(localPath);
    final normalizedConfigPath = _normalizedLocalPath(localPath);
    _backupWatchDebouncers.remove(normalizedConfigPath)?.cancel();
    _pendingBackupWatchPaths.remove(normalizedConfigPath);
    _activeBackupWatchConfigs.remove(normalizedConfigPath);
    _fullBackupInFlightConfigs.remove(normalizedConfigPath);
    try {
      await subscription?.cancel();
    } finally {
      await _backupFolderLeases.remove(localPath)?.close();
    }
  }

  void _queueWatchedFileForBackup(String configLocalPath, String filePath) {
    final normalizedConfigPath = _normalizedLocalPath(configLocalPath);
    final normalizedFilePath = _normalizedLocalPath(filePath);
    final pendingPaths = _pendingBackupWatchPaths.putIfAbsent(
      normalizedConfigPath,
      () => <String>{},
    );
    pendingPaths.add(normalizedFilePath);

    _backupWatchDebouncers.remove(normalizedConfigPath)?.cancel();
    _backupWatchDebouncers[normalizedConfigPath] = Timer(
      _backupWatchDebounceDuration,
      () {
        _backupWatchDebouncers.remove(normalizedConfigPath);
        unawaited(_flushQueuedWatchedFiles(configLocalPath));
      },
    );
  }

  Future<void> _flushQueuedWatchedFiles(String configLocalPath) async {
    final normalizedConfigPath = _normalizedLocalPath(configLocalPath);
    if (_activeBackupWatchConfigs.contains(normalizedConfigPath) ||
        _fullBackupInFlightConfigs.contains(normalizedConfigPath)) {
      return;
    }

    final config = _backupConfigForLocalPath(configLocalPath);
    if (config == null || !config.enabled) {
      _pendingBackupWatchPaths.remove(normalizedConfigPath);
      return;
    }

    _activeBackupWatchConfigs.add(normalizedConfigPath);
    try {
      while (true) {
        if (_isBackupCancelled(configLocalPath)) {
          _pendingBackupWatchPaths.remove(normalizedConfigPath);
          break;
        }

        final pendingPaths = _pendingBackupWatchPaths[normalizedConfigPath];
        if (pendingPaths == null || pendingPaths.isEmpty) {
          _pendingBackupWatchPaths.remove(normalizedConfigPath);
          break;
        }

        final batch = pendingPaths.toList(growable: false);
        pendingPaths.clear();

        for (final path in batch) {
          if (_isBackupCancelled(configLocalPath)) {
            _pendingBackupWatchPaths.remove(normalizedConfigPath);
            return;
          }
          await _processWatchedFile(config, File(path));
        }
      }
    } catch (error, stackTrace) {
      BackgroundBackupRunner.logFailure(
        'backup',
        'watched_file_flush',
        error,
        itemReference: _backupConfigDebugLabel(config),
      );
      unawaited(
        AppErrorReporter.instance.recordError(
          error,
          stackTrace,
          reason: 'backup_watched_file_flush',
        ),
      );
    } finally {
      _activeBackupWatchConfigs.remove(normalizedConfigPath);
      final hasPendingWork =
          _pendingBackupWatchPaths[normalizedConfigPath]?.isNotEmpty == true;
      if (hasPendingWork &&
          !_fullBackupInFlightConfigs.contains(normalizedConfigPath) &&
          !_isBackupCancelled(configLocalPath)) {
        unawaited(_flushQueuedWatchedFiles(configLocalPath));
      }
    }
  }

  Future<void> _processWatchedFile(
    _BackupFolderConfig config,
    File file,
  ) async {
    if (_isBackupCancelled(config.localPath)) return;
    try {
      await PersistentFolderAccess.withAccess(
        path: config.localPath,
        bookmark: config.accessBookmark,
        action: () => _processWatchedFileWithAccess(config, file),
      );
    } on FolderAccessException catch (error) {
      _setBackupIssue(config.localPath, error.message);
    }
  }

  Future<void> _processWatchedFileWithAccess(
    _BackupFolderConfig config,
    File file,
  ) async {
    if (_isBackupCancelled(config.localPath)) {
      _setBackupProgress(config.localPath, null);
      return;
    }

    final existingStatus = _backupProgress[config.localPath];
    final trackProgress = existingStatus == null || existingStatus.incremental;
    final fileLabel = _sanitizeFileName(p.basename(file.path));

    if (trackProgress) {
      _setBackupProgress(
        config.localPath,
        _BackupProgressStatus.incremental(currentFile: fileLabel),
      );
    }

    const maxAttempts = 6;
    var attempt = 0;
    _BackupFileResult result;
    while (true) {
      if (_isBackupCancelled(config.localPath)) {
        _setBackupProgress(config.localPath, null);
        return;
      }
      result = await _handleBackupFile(
        config,
        file,
        showIndicator: false,
        persistFingerprint: true,
      );

      if (!result.shouldRetry || attempt >= maxAttempts - 1) {
        break;
      }

      final delayMillis = 500 * (1 << attempt);
      await Future<void>.delayed(Duration(milliseconds: delayMillis));
      attempt++;
    }

    if (trackProgress && result.didUpload) {
      _updateBackupProgress(config.localPath, (previous) {
        final base =
            (previous ??
                    _BackupProgressStatus.incremental(currentFile: fileLabel))
                .copyWith(totalFiles: 1, scanning: false);
        return base.copyWith(
          completedFiles: 1,
          transferredBytes: base.transferredBytes + result.uploadedBytes,
          currentFile: result.fileName ?? fileLabel,
        );
      });
    }

    if (trackProgress) {
      _setBackupProgress(config.localPath, null);
    }

    if (!result.didUpload && result.shouldRetry) {
      _showMessage('We couldn\'t back up $fileLabel. We\'ll try again soon.');
    }
  }

  Future<void> _toggleBackup(_BackupFolderConfig config, bool value) async {
    if (value && !_canRunBackupConfig(config)) {
      _showMessage(_folderBackupUnavailableMessage);
      return;
    }
    if (value && !_backgroundBackupPreferenceSet) {
      await _ensureBackgroundBackupPreference();
    }

    if (value) {
      _allowBackupWork(config.localPath);
    } else {
      _cancelBackupWork(config.localPath);
    }

    final updated = config.copyWith(enabled: value);
    setState(() {
      _backupFolders[config.localPath] = updated;
    });
    await _persistBackupConfigs();

    if (value) {
      if (_backgroundBackupEnabled) {
        await _startBackupListener(updated);
        if (BackgroundService.supportsDetachedDesktopWorker) {
          unawaited(BackgroundService.ensureDesktopWorkerRunning());
        }
      }
      await _runBackupNow(updated, allowInteractivePrompt: true);
      _updateBackupScanTimerState(forceRestart: true);
      _showMessage(
        _backgroundBackupEnabled
            ? 'Backup enabled for ${updated.remoteFolder}.'
            : 'Backup enabled for ${updated.remoteFolder}. Background sync is off.',
      );
    } else {
      await _stopBackupListener(config.localPath);
      _setBackupProgress(config.localPath, null);
      _updateBackupScanTimerState(forceRestart: true);
      _showMessage('Backup paused for ${config.remoteFolder}.');
    }
  }

  Future<void> _removeBackup(_BackupFolderConfig config) async {
    _cancelBackupWork(config.localPath);
    await _stopBackupListener(config.localPath);
    final localPathKey = _normalizedLocalPath(config.localPath);
    final folderId = _backupFolderIdsByLocalPath.remove(localPathKey);
    setState(() {
      _backupFolders.remove(config.localPath);
      if (folderId != null) {
        _knownBackupFolderIds.remove(folderId);
      }
    });
    _setBackupProgress(config.localPath, null);
    _updateBackupScanTimerState();
    await _persistBackupConfigs();
    await _clearBackupFingerprintsFor(config.localPath);
    _showMessage('Removed backup for ${config.remoteFolder}.');
  }

  Future<void> _runBackupNow(
    _BackupFolderConfig config, {
    bool quiet = false,
    bool allowInteractivePrompt = false,
  }) async {
    if (!mounted || _sessionInvalidated) {
      return;
    }
    if (config.photoLibrary) {
      return _runBackupWithAccess(
        config,
        quiet: quiet,
        allowInteractivePrompt: allowInteractivePrompt,
      );
    }
    try {
      await PersistentFolderAccess.withAccess(
        path: config.localPath,
        bookmark: config.accessBookmark,
        action: () => _runBackupWithAccess(
          config,
          quiet: quiet,
          allowInteractivePrompt: allowInteractivePrompt,
        ),
      );
    } on FolderAccessException catch (error) {
      _setBackupIssue(config.localPath, error.message);
      if (!quiet && mounted) _showMessage(error.message);
    }
  }

  Future<void> _runBackupWithAccess(
    _BackupFolderConfig config, {
    bool quiet = false,
    bool allowInteractivePrompt = false,
  }) async {
    if (!_canRunBackupConfig(config)) {
      if (!quiet && mounted) {
        _showMessage(
          _folderBackupUnavailableMessage,
        );
      }
      return;
    }
    if (config.photoLibrary) {
      await _runPhotoBackup(config, interactive: allowInteractivePrompt);
      return;
    }
    if (kIsWeb) {
      if (!quiet) {
        _showMessage('Backups are only available on mobile and desktop.');
      }
      return;
    }
    if (_sessionInvalidated) {
      return;
    }
    try {
      _ensureSessionActive();
    } on _SessionExpiredException catch (error) {
      _handleSessionExpired(error);
      return;
    }
    final configReference = _backupConfigDebugLabel(config);
    final directory = Directory(config.localPath);
    if (!await directory.exists()) {
      _showMessage(
        'The selected backup folder is not accessible. Check system permissions.',
      );
      return;
    }
    final normalizedConfigPath = _normalizedLocalPath(config.localPath);
    if (!_fullBackupInFlightConfigs.add(normalizedConfigPath)) {
      return;
    }

    if (mounted) setState(() => _backupIssues.remove(config.localPath));
    _setBackupProgress(config.localPath, _BackupProgressStatus.scanning());
    try {
      bool backupCancelled() => _isBackupCancelled(config.localPath);

      if (backupCancelled()) {
        return;
      }

      BackgroundBackupRunner.log(
        'backup',
        'event=scan_start item=$configReference.',
      );
      if (!await _ensureStorageConfigured()) {
        _setBackupIssue(
          config.localPath,
          'Storage is not ready. Retry when connected.',
        );
        BackgroundBackupRunner.log(
          'backup',
          'event=scan_storage_unavailable item=$configReference.',
        );
        _showMessage(
          'Secure storage is not ready yet. Please wait a moment and try again.',
        );
        return;
      }
      if (!await _ensureAuthenticated(interactive: allowInteractivePrompt)) {
        _setBackupIssue(
          config.localPath,
          'Sign in again, then retry this backup.',
        );
        return;
      }
      final uploadEncryptionKeyString = await _requireUploadEncryptionKey(
        interactive: allowInteractivePrompt,
      );
      if (uploadEncryptionKeyString == null) {
        _setBackupIssue(
          config.localPath,
          'Unlock encryption, then retry this backup.',
        );
        return;
      }
      final uploadSecretKey = SecretKey(
        base64Decode(uploadEncryptionKeyString),
      );

      _backupAuthErrorShown = false;
      await _transferJournal?.markBackupScan(successful: false);
      final folderId = await _deriveBackupFolderId(
        config,
        key: uploadSecretKey,
      );
      final rootSegments = _normalizeRemoteFolderSegments(config.remoteFolder);
      BackgroundBackupRunner.log(
        'backup',
        'event=folder_record_prepare item=$configReference.',
      );
      await _ensureBackupFolderRecord(
        folderId: folderId,
        folderName: config.remoteFolder,
        pathSegments: rootSegments,
      );
      BackgroundBackupRunner.log(
        'backup',
        'event=folder_record_ready item=$configReference.',
      );
      BackgroundBackupRunner.log(
        'backup',
        'event=remote_catalog_load item=$configReference.',
      );
      final remoteBackupCatalog = await _loadRemoteBackupCatalog(folderId);
      BackgroundBackupRunner.log(
        'backup',
        'event=remote_catalog_loaded item=$configReference '
            'entries=${remoteBackupCatalog.length}.',
      );

      _setBackupProgress(config.localPath, _BackupProgressStatus.scanning());

      final candidates = <_BackupCandidate>[];
      final bucket = _fingerprintBucket(config.localPath, create: true)!;
      var scannedCount = 0;
      final scanUpdateClock = Stopwatch()..start();
      try {
        BackgroundBackupRunner.log(
          'backup',
          'event=scan_enumerate item=$configReference.',
        );
        await for (final entity in directory.list(
          recursive: true,
          followLinks: false,
        )) {
          if (backupCancelled()) {
            _setBackupProgress(config.localPath, null);
            BackgroundBackupRunner.log(
              'backup',
              'event=scan_cancelled item=$configReference.',
            );
            return;
          }
          if (entity is! File) {
            continue;
          }

          FileStat stat;
          try {
            stat = await entity.stat();
          } catch (error) {
            _setBackupIssue(
              config.localPath,
              'Cannot scan this folder (${BackgroundBackupRunner.errorCategory(error)}). Retry when ready.',
            );
            BackgroundBackupRunner.logFailure(
              'backup',
              'file_metadata_read',
              error,
              itemReference: _backupFileDebugLabel(entity),
            );
            continue;
          }

          scannedCount++;
          final normalizedPath = _normalizedLocalPath(entity.path);
          final fileSize = max(0, stat.size);
          final modifiedAt = stat.modified.toUtc();
          final backupPathHash = await _backupPathHashForFile(
            entity,
            config.localPath,
            key: uploadSecretKey,
          );
          final previous = _referenceBackupFingerprint(
            bucket[normalizedPath],
            remoteBackupCatalog[backupPathHash],
            localPath: normalizedPath,
          );
          if (previous != null) {
            bucket[normalizedPath] = previous;
          }
          final sameMetadata =
              previous != null &&
              previous.size == fileSize &&
              previous.modified.toUtc().millisecondsSinceEpoch ==
                  modifiedAt.millisecondsSinceEpoch;
          if (!sameMetadata) {
            candidates.add(_BackupCandidate(file: entity, stat: stat));
          }
          if (scannedCount == 1 || scanUpdateClock.elapsedMilliseconds >= 250) {
            scanUpdateClock.reset();
            final currentCount = scannedCount;
            _updateBackupProgress(config.localPath, (previous) {
              final base = (previous ?? _BackupProgressStatus.scanning())
                  .copyWith(scannedFiles: currentCount, scanning: true);
              return base;
            });
          }
        }
      } on FileSystemException catch (error) {
        _setBackupIssue(
          config.localPath,
          'Cannot read this folder. Check folder permissions and retry.',
        );
        BackgroundBackupRunner.logFailure(
          'backup',
          'scan_enumerate',
          error,
          itemReference: configReference,
        );
        _setBackupProgress(config.localPath, null);
        _showMessage(
          'We couldn\'t read this backup folder. Check system permissions.',
        );
        return;
      } catch (error) {
        BackgroundBackupRunner.logFailure(
          'backup',
          'scan_prepare',
          error,
          itemReference: configReference,
        );
        _setBackupProgress(config.localPath, null);
        _showMessage('We couldn\'t prepare ${config.remoteFolder} for backup.');
        return;
      }

      _updateBackupProgress(config.localPath, (previous) {
        final base = (previous ?? _BackupProgressStatus.scanning()).copyWith(
          scannedFiles: scannedCount,
          scanning: true,
        );
        return base;
      });
      BackgroundBackupRunner.log(
        'backup',
        'event=scan_finished item=$configReference scanned=$scannedCount '
            'pending=${candidates.length}.',
      );

      if (scannedCount == 0) {
        _setBackupProgress(config.localPath, null);
        await _transferJournal?.markBackupScan(successful: true);
        if (!quiet) {
          _showMessage('No files found in ${config.remoteFolder}.');
        }
        return;
      }

      if (candidates.isEmpty) {
        _setBackupProgress(config.localPath, null);
        await _updateBackupSyncTime(config.localPath);
        await _persistBackupFingerprints();
        await _transferJournal?.markBackupScan(successful: true);
        BackgroundBackupRunner.log(
          'backup',
          'event=scan_no_changes item=$configReference.',
        );
        if (!quiet) {
          _showMessage(
            'Backup scan finished for ${config.remoteFolder}. No new changes were detected.',
          );
        }
        return;
      }

      if (!quiet) {
        _showMessage(
          'Preparing ${candidates.length} changed item(s) in ${config.remoteFolder}...',
        );
      }

      final totalBytes = candidates.fold<int>(0, (total, candidate) {
        final size = candidate.stat.size;
        return total + (size < 0 ? 0 : size);
      });
      BackgroundBackupRunner.log(
        'backup',
        'event=comparison_prepare item=$configReference '
            'files=${candidates.length} bytes=$totalBytes.',
      );

      _setBackupProgress(
        config.localPath,
        _BackupProgressStatus.preparing(
          totalFiles: candidates.length,
          totalBytes: totalBytes,
          scannedFiles: scannedCount,
        ),
      );

      final transferId =
          'backup:$configReference:${DateTime.now().millisecondsSinceEpoch}';
      _beginTransfer(transferId, 'Backing up ${config.remoteFolder}');

      var processed = 0;
      var uploadedFiles = 0;
      var failedFiles = 0;
      var transferredBytes = 0;
      var hadError = false;
      var wasCancelled = false;
      final uploadBatchSize = _uploadBandwidthLimitBytesPerSecond == null
          ? _backupUploadBatchSize
          : 1;

      Future<({String fileLabel, _BackupFileResult result})> processCandidate(
        _BackupCandidate candidate,
      ) async {
        if (backupCancelled()) {
          return (
            fileLabel: _sanitizeFileName(p.basename(candidate.file.path)),
            result: _BackupFileResult.skipped(),
          );
        }
        final file = candidate.file;
        final fileLabel = _sanitizeFileName(p.basename(file.path));
        final fileSize = max(0, candidate.stat.size);
        var backupPathHash = await _backupPathHashForFile(
          file,
          config.localPath,
          key: uploadSecretKey,
        );
        final normalizedLocalPath = _normalizedLocalPath(file.path);
        final localReference = bucket[normalizedLocalPath];
        final remoteReference = remoteBackupCatalog[backupPathHash];
        String? precomputedHash;
        final remoteIntegrityTag =
            remoteReference?.contentIntegrityTag.trim() ?? '';
        final legacyRemoteHash = remoteReference?.legacyHashBase64.trim() ?? '';
        final previousLocalHash = localReference?.hash.trim() ?? '';
        String? localIntegrityTagForConflict;
        String? remoteIntegrityTagForConflict;

        if (remoteIntegrityTag.isNotEmpty) {
          final previousLocalIntegrityTag = previousLocalHash.isEmpty
              ? ''
              : await _metadataEncryptionService.contentIntegrityTag(
                  sha256Base64: previousLocalHash,
                  key: uploadSecretKey,
                );
          if (previousLocalIntegrityTag.isEmpty ||
              previousLocalIntegrityTag != remoteIntegrityTag) {
            precomputedHash = await _computeFileSha256Base64(
              file,
              lengthHint: fileSize,
            );
            final currentLocalIntegrityTag = await _metadataEncryptionService
                .contentIntegrityTag(
                  sha256Base64: precomputedHash,
                  key: uploadSecretKey,
                );
            if (currentLocalIntegrityTag == remoteIntegrityTag) {
              bucket[normalizedLocalPath] = _BackupFileFingerprint(
                localPath: normalizedLocalPath,
                size: fileSize,
                modified: candidate.stat.modified.toUtc(),
                hash: precomputedHash,
                remoteIntegrityTag: remoteIntegrityTag,
              );
              return (
                fileLabel: fileLabel,
                result: _BackupFileResult.skipped(),
              );
            }
            if (previousLocalHash.isNotEmpty &&
                precomputedHash == previousLocalHash) {
              bucket[normalizedLocalPath] =
                  (localReference ??
                          _BackupFileFingerprint(
                            localPath: normalizedLocalPath,
                            size: fileSize,
                            modified: candidate.stat.modified.toUtc(),
                            hash: precomputedHash,
                          ))
                      .copyWith(
                        size: fileSize,
                        modified: candidate.stat.modified.toUtc(),
                        remoteIntegrityTag: remoteIntegrityTag,
                      );
              return (
                fileLabel: fileLabel,
                result: _BackupFileResult.skipped(),
              );
            }
            localIntegrityTagForConflict = currentLocalIntegrityTag;
            remoteIntegrityTagForConflict = remoteIntegrityTag;
          }
        } else if (legacyRemoteHash.isNotEmpty &&
            previousLocalHash.isNotEmpty &&
            legacyRemoteHash != previousLocalHash) {
          precomputedHash = await _computeFileSha256Base64(
            file,
            lengthHint: fileSize,
          );
          if (precomputedHash != legacyRemoteHash &&
              precomputedHash != previousLocalHash) {
            localIntegrityTagForConflict = await _metadataEncryptionService
                .contentIntegrityTag(
                  sha256Base64: precomputedHash,
                  key: uploadSecretKey,
                );
            remoteIntegrityTagForConflict = await _metadataEncryptionService
                .contentIntegrityTag(
                  sha256Base64: legacyRemoteHash,
                  key: uploadSecretKey,
                );
          }
        }

        if (localIntegrityTagForConflict != null &&
            remoteIntegrityTagForConflict != null) {
          final conflictId = await _metadataEncryptionService.backupPathTag(
            normalizedRelativePath:
                '$backupPathHash|$localIntegrityTagForConflict|'
                '$remoteIntegrityTagForConflict',
            key: uploadSecretKey,
          );
          final localPathTag = await _metadataEncryptionService.localPathTag(
            normalizedLocalPath: normalizedLocalPath,
            key: uploadSecretKey,
          );
          final encryptedFileLabel = await _metadataEncryptionService
              .encryptLabel(label: fileLabel, key: uploadSecretKey);
          final resolution = await _secureDriveService.recordSyncConflict(
            uid: widget.user.uid,
            conflictId: conflictId,
            backupPathHash: backupPathHash,
            localPathHash: localPathTag,
            localIntegrityTag: localIntegrityTagForConflict,
            remoteIntegrityTag: remoteIntegrityTagForConflict,
            encryptedFileLabel: encryptedFileLabel,
          );
          if (resolution == null) {
            return (
              fileLabel: fileLabel,
              result: _BackupFileResult.failure(shouldRetry: false),
            );
          }
          if (resolution == 'keep_both') {
            backupPathHash = await _metadataEncryptionService.backupPathTag(
              normalizedRelativePath:
                  '$backupPathHash|conflict-copy|'
                  '$localIntegrityTagForConflict',
              key: uploadSecretKey,
            );
          } else if (resolution == 'keep_remote' || resolution == 'dismissed') {
            bucket[normalizedLocalPath] = _BackupFileFingerprint(
              localPath: normalizedLocalPath,
              size: fileSize,
              modified: candidate.stat.modified.toUtc(),
              hash: precomputedHash ?? '',
              remoteIntegrityTag: remoteIntegrityTagForConflict,
            );
            return (fileLabel: fileLabel, result: _BackupFileResult.skipped());
          }
        }
        if (!_ensureStorageCapacityForBytes(
          fileSize,
          actionLabel: 'Backup',
          itemLabel: fileLabel,
          showFeedback: allowInteractivePrompt,
        )) {
          return (
            fileLabel: fileLabel,
            result: _BackupFileResult.failure(shouldRetry: false),
          );
        }

        _addPendingBytes(fileSize);
        final result = await _handleBackupFile(
          config,
          file,
          showIndicator: allowInteractivePrompt,
          sanitizedRootSegments: rootSegments,
          ensureFolderRecord: false,
          folderId: folderId,
          persistFingerprint: false,
          precomputedStat: candidate.stat,
          skipStorageCapacityCheck: true,
          pendingBytesReserved: true,
          uploadEncryptionKeyString: uploadEncryptionKeyString,
          uploadSecretKey: uploadSecretKey,
          backupPathHash: backupPathHash,
          precomputedHash: precomputedHash,
        );
        return (fileLabel: fileLabel, result: result);
      }

      try {
        for (
          var batchStart = 0;
          batchStart < candidates.length;
          batchStart += uploadBatchSize
        ) {
          if (backupCancelled()) {
            wasCancelled = true;
            break;
          }

          final batchEnd = min(batchStart + uploadBatchSize, candidates.length);
          final batch = candidates.sublist(batchStart, batchEnd);

          for (var index = 0; index < batch.length; index++) {
            final globalIndex = batchStart + index;
            final fileLabel = _sanitizeFileName(
              p.basename(batch[index].file.path),
            );
            final shouldRefreshCurrentFile =
                globalIndex == 0 ||
                globalIndex == candidates.length - 1 ||
                globalIndex % 10 == 0;
            if (shouldRefreshCurrentFile) {
              _updateBackupProgress(config.localPath, (previous) {
                final base =
                    (previous ??
                            _BackupProgressStatus.preparing(
                              totalFiles: candidates.length,
                              totalBytes: totalBytes,
                              scannedFiles: scannedCount,
                            ))
                        .copyWith(currentFile: fileLabel);
                return base;
              });
            }
          }

          final results = await Future.wait(batch.map(processCandidate));

          if (backupCancelled()) {
            wasCancelled = true;
          }

          for (final batchResult in results) {
            final result = batchResult.result;
            final fileLabel = batchResult.fileLabel;
            processed++;
            if (result.didUpload) {
              uploadedFiles++;
              transferredBytes += result.uploadedBytes;
              if (uploadedFiles % _backupFingerprintCheckpointUploadCount ==
                  0) {
                await _persistBackupFingerprints();
              }
            }
            if (result.failed) {
              failedFiles++;
            }

            final shouldRefreshProgress =
                processed == 1 ||
                processed == candidates.length ||
                processed % 10 == 0;
            if (shouldRefreshProgress) {
              final currentLabel = result.fileName ?? fileLabel;
              final completed = processed;
              final transferred = transferredBytes;

              _updateBackupProgress(config.localPath, (previous) {
                final base =
                    (previous ??
                            _BackupProgressStatus.preparing(
                              totalFiles: candidates.length,
                              totalBytes: totalBytes,
                              scannedFiles: scannedCount,
                            ))
                        .copyWith(currentFile: currentLabel);
                return base.copyWith(
                  completedFiles: completed,
                  transferredBytes: transferred,
                );
              });
            }
          }

          if (wasCancelled) {
            break;
          }
        }
      } catch (error) {
        hadError = true;
        BackgroundBackupRunner.logFailure(
          'backup',
          'run_batch',
          error,
          itemReference: configReference,
        );
        if (!quiet) {
          _showMessage(
            'We couldn\'t finish backing up ${config.remoteFolder}.',
          );
        }
      } finally {
        _endTransfer(transferId);
      }

      _setBackupProgress(config.localPath, null);

      if (wasCancelled || backupCancelled()) {
        BackgroundBackupRunner.log(
          'backup',
          'event=run_cancelled item=$configReference.',
        );
        return;
      }

      if (hadError) {
        _setBackupIssue(
          config.localPath,
          'Backup stopped before completion. Check your connection and storage capacity, then retry.',
        );
        BackgroundBackupRunner.log(
          'backup',
          'event=run_failed item=$configReference.',
        );
        return;
      }

      if (failedFiles > 0) {
        _setBackupIssue(
          config.localPath,
          '$uploadedFiles uploaded; $failedFiles failed. Check storage capacity and connection, then retry.',
        );
        BackgroundBackupRunner.log(
          'backup',
          'event=run_partial item=$configReference uploaded=$uploadedFiles '
              'failed=$failedFiles.',
        );
        if (!quiet) {
          if (uploadedFiles > 0) {
            _showMessage(
              'Backup uploaded $uploadedFiles of ${candidates.length} files. Some files failed and will retry later.',
            );
          } else {
            _showMessage(
              'Backup could not upload files from ${config.remoteFolder}. Check encryption setup and connectivity.',
            );
          }
        }
        return;
      }

      await _updateBackupSyncTime(config.localPath);
      await _transferJournal?.markBackupScan(successful: true);
      await _persistBackupFingerprints();
      _scheduleOfflineSync();
      BackgroundBackupRunner.log(
        'backup',
        'event=run_completed item=$configReference uploaded=$uploadedFiles.',
      );
      if (!quiet) {
        if (uploadedFiles == 0) {
          _showMessage(
            'Backup scan finished for ${config.remoteFolder}. No new changes were detected.',
          );
        } else {
          _showMessage('Backup completed for ${config.remoteFolder}.');
        }
      }
    } catch (error, stackTrace) {
      _setBackupIssue(
        config.localPath,
        'Backup stopped (${BackgroundBackupRunner.errorCategory(error)}). No successful sync was recorded. Retry when ready.',
      );
      BackgroundBackupRunner.logFailure(
        'backup',
        'run_unexpected',
        error,
        itemReference: configReference,
      );
      unawaited(
        AppErrorReporter.instance.recordError(
          error,
          stackTrace,
          reason: 'backup_run_unexpected_error',
        ),
      );
      _setBackupProgress(config.localPath, null);
      if (!quiet) {
        _showMessage('We couldn\'t finish backing up ${config.remoteFolder}.');
      }
    } finally {
      _setBackupProgress(config.localPath, null);
      _fullBackupInFlightConfigs.remove(normalizedConfigPath);
      if (_pendingBackupWatchPaths[normalizedConfigPath]?.isNotEmpty == true &&
          !_isBackupCancelled(config.localPath)) {
        unawaited(_flushQueuedWatchedFiles(config.localPath));
      }
    }
  }

  Future<_BackupFileResult> _handleBackupFile(
    _BackupFolderConfig config,
    File file, {
    bool showIndicator = false,
    List<String>? sanitizedRootSegments,
    bool ensureFolderRecord = true,
    String? folderId,
    bool persistFingerprint = false,
    FileStat? precomputedStat,
    bool skipStorageCapacityCheck = false,
    bool pendingBytesReserved = false,
    String? uploadEncryptionKeyString,
    SecretKey? uploadSecretKey,
    String? backupPathHash,
    String? precomputedHash,
    IosPhotoAsset? photoAsset,
    String? photoName,
    bool interactiveAuth = true,
  }) async {
    if (!_ensureStorageWritesAvailable(showFeedback: showIndicator)) {
      return _BackupFileResult.failure(shouldRetry: false);
    }
    if (!await file.exists()) {
      return _BackupFileResult.skipped();
    }
    if (_isBackupCancelled(config.localPath)) {
      return _BackupFileResult.skipped();
    }
    final fileReference = _backupFileDebugLabel(file);

    var pendingBytesCounted = pendingBytesReserved;
    var pendingBytesReleased = false;
    var pendingBytesToRelease = pendingBytesReserved
        ? max(0, precomputedStat?.size ?? 0)
        : 0;

    try {
      if (!await _ensureAuthenticated(interactive: interactiveAuth)) {
        return _BackupFileResult.failure(shouldRetry: false);
      }

      FileStat stat;
      if (precomputedStat != null) {
        stat = precomputedStat;
      } else {
        try {
          stat = await file.stat();
        } catch (error) {
          BackgroundBackupRunner.logFailure(
            'backup',
            'file_metadata_read',
            error,
            itemReference: fileReference,
          );
          return _BackupFileResult.failure();
        }
      }

      final normalizedPath = _normalizedLocalPath(
        photoAsset?.sourcePath ?? file.path,
      );

      final fileSize = max(0, stat.size);
      if (pendingBytesCounted) {
        pendingBytesToRelease = fileSize;
      }
      final modifiedAt = photoAsset?.modified ?? stat.modified.toUtc();
      final bucket = _fingerprintBucket(config.localPath, create: true)!;
      final previous = bucket[normalizedPath];
      final sameMetadata =
          previous != null &&
          previous.size == fileSize &&
          previous.modified.toUtc().millisecondsSinceEpoch ==
              modifiedAt.millisecondsSinceEpoch;
      if (sameMetadata) {
        return _BackupFileResult.skipped();
      }

      String? preUploadHash = precomputedHash;
      if (preUploadHash != null &&
          previous != null &&
          previous.hash == preUploadHash) {
        bucket[normalizedPath] = previous.copyWith(
          size: fileSize,
          modified: modifiedAt,
        );
        if (persistFingerprint) {
          await _persistBackupFingerprints();
        }
        return _BackupFileResult.skipped();
      }
      if (previous != null &&
          preUploadHash == null &&
          previous.size == fileSize &&
          previous.hash.isNotEmpty) {
        try {
          preUploadHash = await _computeFileSha256Base64(
            file,
            lengthHint: fileSize,
          );
        } catch (error) {
          BackgroundBackupRunner.logFailure(
            'backup',
            'file_hash',
            error,
            itemReference: fileReference,
          );
          return _BackupFileResult.failure();
        }

        if (previous.hash == preUploadHash) {
          bucket[normalizedPath] = previous.copyWith(
            size: fileSize,
            modified: modifiedAt,
          );
          if (persistFingerprint) {
            await _persistBackupFingerprints();
          }
          return _BackupFileResult.skipped();
        }
      }

      final relativePath =
          photoAsset?.token ?? p.relative(file.path, from: config.localPath);
      final relativeSegments = relativePath
          .split(Platform.pathSeparator)
          .where((segment) => segment.isNotEmpty)
          .toList();
      if (relativeSegments.isEmpty) {
        return _BackupFileResult.skipped();
      }

      final originalFileName = relativeSegments.removeLast();
      final fileName = _sanitizeFileName(photoName ?? originalFileName);
      final encryptionKeyString =
          uploadEncryptionKeyString ??
          await _requireUploadEncryptionKey(interactive: showIndicator);
      if (encryptionKeyString == null) {
        return _BackupFileResult.failure(shouldRetry: false);
      }
      final secretKey =
          uploadSecretKey ?? SecretKey(base64Decode(encryptionKeyString));
      final resolvedFolderId =
          folderId ?? await _deriveBackupFolderId(config, key: secretKey);
      final displayRootSegments =
          sanitizedRootSegments ??
          _normalizeRemoteFolderSegments(config.remoteFolder);
      if (ensureFolderRecord) {
        await _ensureBackupFolderRecord(
          folderId: resolvedFolderId,
          folderName: config.remoteFolder,
          pathSegments: displayRootSegments,
        );
      }
      final normalizedRelativeFolderSegments = relativeSegments
          .map(_sanitizePathSegment)
          .where((segment) => segment.isNotEmpty)
          .toList(growable: false);
      final leafFolderId = await _ensureFolderPath(
        parentId: resolvedFolderId,
        pathSegments: normalizedRelativeFolderSegments,
        colorHex: '#E8F0FE',
        systemFolder: true,
        systemKey: 'backup',
        storageMetadataOverride: const <String, dynamic>{},
        storageSpaceIdOverride: 'personal',
      );
      final baseSegments = displayRootSegments.isEmpty
          ? <String>[_sanitizePathSegment(config.remoteFolder)]
          : List<String>.from(displayRootSegments);
      baseSegments.removeWhere((segment) => segment.trim().isEmpty);
      if (baseSegments.isEmpty) {
        baseSegments.add('backup-folder');
      }

      if (!UploadCoordinator.enabled && !skipStorageCapacityCheck &&
          !_ensureStorageCapacityForBytes(
            fileSize,
            actionLabel: 'Backup',
            itemLabel: fileName,
            showFeedback: showIndicator,
          )) {
        return _BackupFileResult.failure(shouldRetry: false);
      }
      final resolvedBackupPathHash =
          backupPathHash ??
          await _computeBackupPathHash(relativePath, key: secretKey);
      final previousRemoteVersion = _files.cast<_DriveFile?>().firstWhere(
        (candidate) =>
            candidate?.isActive == true &&
            candidate?.backupPathHash == resolvedBackupPathHash,
        orElse: () => null,
      );

      final displayEncryptedName = await _encryptFileName(
        fileName,
        encryptionKey: encryptionKeyString,
      );
      final objectKeyName = _backupObjectKeyName(resolvedBackupPathHash);

      var objectKey = _buildObjectKey(
        objectKeyName,
        securedObjectKey: true,
        objectKeyOwnerPrefix: _objectKeyOwnerPrefixes.first,
      );
      _ensureOwnsObjectKey(objectKey);
      final contentType = _contentTypeForName(fileName);
      bool uploadedThumbnail = false;
      Uint8List? generatedThumbnailBytes;
      final shouldGenerateThumbnail =
          contentType != null && contentType.startsWith('image/');
      BackgroundBackupRunner.log('backup', 'event=file_upload_start.');

      final transferId = showIndicator
          ? 'backup:${_backupConfigDebugLabel(config)}:$fileReference'
          : null;

      var journalTransferId =
          'backup-item:$resolvedBackupPathHash:${DateTime.now().millisecondsSinceEpoch}';
      final transferJournal = _transferJournal;
      UploadSourceSnapshot? sourceSnapshot;
      if (UploadCoordinator.enabled) {
        if (transferJournal == null || !transferJournal.storageAvailable) {
          throw const UploadFailure('unavailable');
        }
        sourceSnapshot = await UploadSourceSnapshot.capture(file.openRead());
        _ensureSessionActive();
        if (sourceSnapshot.length != fileSize) throw const UploadFailure('source_changed');
        final checkpoint = await openBackupUploadCheckpoint(
          journal: transferJournal, sourcePath: normalizedPath,
          folderId: leafFolderId ?? resolvedFolderId,
          fingerprint: sourceSnapshot.fingerprint, length: fileSize,
          createObjectKey: () => objectKey,
        );
        objectKey = checkpoint.objectKey!;
        _ensureOwnsObjectKey(objectKey);
        journalTransferId = checkpoint.id;
      } else {
        await transferJournal?.begin(
        id: journalTransferId,
        kind: TransferJournalKind.backup,
        label: 'Back up $fileName',
        objectKey: objectKey,
        localPath: file.path,
        totalBytes: fileSize,
      );
      }

      var usageRecorded = false;
      var objectUploaded = false;
      final imageUploadSource = shouldGenerateThumbnail
          ? await captureBoundedImageUploadSource(
              expectedLength: fileSize,
              sourceLength: file.length,
              openRead: (endExclusive) => file.openRead(0, endExclusive),
            )
          : null;
      final imageUploadHash = imageUploadSource == null
          ? null
          : base64Encode(sha256.convert(imageUploadSource).bytes);
      final hashedUpload = imageUploadSource == null
          ? _createHashingUploadStream(file)
          : null;
      try {
        if (transferId != null) {
          _beginTransfer(transferId, 'Syncing ${p.basename(file.path)}');
        }
        _ensureSessionActive();
        await _applyBandwidthLimit(fileSize);
        if (!pendingBytesCounted) {
          _addPendingBytes(fileSize);
          pendingBytesCounted = true;
          pendingBytesToRelease = fileSize;
        }
        generatedThumbnailBytes =
            await uploadSourceThenOptionalDerivative<Uint8List>(
              uploadSource: () async {
                final source = imageUploadSource == null
                    ? hashedUpload?.stream ?? file.openRead()
                    : Stream<List<int>>.value(imageUploadSource);
                await _storageService.upload(
                  objectKey: objectKey,
                  stream: sourceSnapshot?.verify(source) ?? source,
                  sourceFingerprint: sourceSnapshot?.fingerprint,
                  length: fileSize,
                  contentType: contentType,
                  encryptionKey: secretKey,
                  transferId: journalTransferId,
                  checkpointSink: transferJournal,
                );
              },
              afterSourceUpload: () async {
                objectUploaded = true;
                await transferJournal?.updateProgress(
                  journalTransferId,
                  transferredBytes: fileSize,
                );
              },
              uploadDerivative: shouldGenerateThumbnail
                  ? () async {
                      final thumbnailBytes = imageUploadSource == null
                          ? null
                          : await generateBoundedImageThumbnail(
                              imageUploadSource,
                            );
                      if (thumbnailBytes != null) {
                        final thumbnailKey = _thumbnailObjectKeyFor(objectKey);
                          await UploadCoordinator.instance.withoutBatch(() => _storageService.upload(
                          objectKey: thumbnailKey,
                          stream: Stream.value(thumbnailBytes),
                          length: thumbnailBytes.length,
                          contentType: imageThumbnailContentType,
                            encryptionKey: secretKey,
                          ));
                      }
                      return thumbnailBytes;
                    }
                  : null,
              derivativeTimeout: imageThumbnailDerivativeTimeout,
              onDerivativeError: (error, _) {
                BackgroundBackupRunner.logFailure(
                  'backup',
                  'optional_preview',
                  error,
                  itemReference: fileReference,
                );
              },
            );
        uploadedThumbnail = generatedThumbnailBytes != null;
        final resolvedHash =
            imageUploadHash ?? await hashedUpload!.hashFuture;
        final resolvedIntegrityTag = await _metadataEncryptionService
            .contentIntegrityTag(sha256Base64: resolvedHash, key: secretKey);
        final fingerprint = _BackupFileFingerprint(
          localPath: normalizedPath,
          size: fileSize,
          modified: modifiedAt,
          hash: resolvedHash,
          remoteIntegrityTag: resolvedIntegrityTag,
        );

        await _recordUploadedFile(
          journalTransferId: journalTransferId,
          objectKey: objectKey,
          size: fileSize,
          folderId: leafFolderId,
          folderName: null,
          folderColorHex: null,
          encryptionMode: 'standard',
          storageLayout: 'single',
          contentEncryption: 'standard',
          uploadedAt: DateTime.now().toUtc(),
          pathSegments: normalizedRelativeFolderSegments,
          contentIntegrityTag: resolvedIntegrityTag,
          contentIntegrityVersion:
              WorkspaceMetadataEncryptionService.contentIntegrityVersion,
          encryptedName: displayEncryptedName,
          displayName: fileName,
          contentType: contentType,
          backupPathHash: resolvedBackupPathHash,
          backupModifiedMillis: modifiedAt.millisecondsSinceEpoch,
          supersedesFileId: previousRemoteVersion?.id,
          hasThumbnail: uploadedThumbnail,
          storageMetadataOverride: const <String, dynamic>{},
        );
        usageRecorded = true;
        await transferJournal?.complete(journalTransferId);
        if (generatedThumbnailBytes != null) {
          _thumbnailCache[objectKey] = generatedThumbnailBytes;
        }
        bucket[normalizedPath] = fingerprint;
        if (persistFingerprint) {
          await _persistBackupFingerprints();
        }
        _scheduleOfflineSync();
        if (showIndicator) {
          await _updateBackupSyncTime(config.localPath);
        }
        BackgroundBackupRunner.log('backup', 'event=file_upload_completed.');
        return _BackupFileResult.success(
          uploadedBytes: fileSize,
          fileName: fileName,
        );
      } catch (error) {
        if (objectUploaded) {
          await transferJournal?.metadataCommitFailed(journalTransferId, error);
        } else {
          await transferJournal?.fail(journalTransferId, error);
        }
        if (error is _SessionExpiredException) {
          _handleSessionExpired(error);
          return _BackupFileResult.failure();
        }
        if (_isAuthorizationError(error)) {
          _notifyBackupAuthorizationIssue();
        }
        if (error is WasabiConfigurationException && showIndicator) {
          _showMessage(error.message);
        }
        BackgroundBackupRunner.logFailure(
          'backup',
          'file_upload',
          error,
          itemReference: fileReference,
        );
        final shouldRetry =
            !requiresTransferVerification(error) &&
            error is! WasabiConfigurationException &&
            error is! ArgumentError &&
            !(error is FirebaseException && error.code == 'permission-denied');
        if (showIndicator &&
            error is FirebaseException &&
            error.code == 'permission-denied') {
          _showMessage(
            'Backup permissions were denied for ${p.basename(file.path)}. Check your Drive access.',
          );
        }
        return _BackupFileResult.failure(shouldRetry: shouldRetry);
      } finally {
        if (transferId != null) {
          _endTransfer(transferId);
        }
        if (pendingBytesCounted && !pendingBytesReleased) {
          _removePendingBytes(pendingBytesToRelease);
          pendingBytesReleased = true;
        }
        if (usageRecorded) {
          _applyConfirmedUploadedBytes(fileSize, objectKey: objectKey);
        }
      }
    } finally {
      if (pendingBytesCounted &&
          !pendingBytesReleased &&
          pendingBytesToRelease > 0) {
        _removePendingBytes(pendingBytesToRelease);
      }
    }
  }

  Future<void> _ensureBackupFolderRecord({
    required String folderId,
    required String folderName,
    List<String>? pathSegments,
  }) async {
    if (!await _ensureAuthenticated(interactive: true)) {
      return;
    }

    final resolvedSegments =
        (pathSegments ?? _normalizeRemoteFolderSegments(folderName))
            .where((segment) => segment.trim().isNotEmpty)
            .toList(growable: false);
    final displayName = resolvedSegments.isNotEmpty
        ? resolvedSegments.last
        : _sanitizePathSegment(folderName);
    final fallbackName = folderName.trim().isEmpty
        ? 'Backup folder'
        : folderName.trim();

    try {
      final saved = await _saveEncryptedFolderDocument(
        folderId: folderId,
        name: displayName.isEmpty ? fallbackName : displayName,
        color: '#E8F0FE',
        parentId: null,
        systemFolder: true,
        systemKey: 'backup',
        storageMetadataOverride: const <String, dynamic>{},
        interactive: true,
        touchLastFileAt: true,
      ).timeout(const Duration(seconds: 10));
      if (saved) {
        _knownBackupFolderIds.add(folderId);
      }
    } catch (error) {
      BackgroundBackupRunner.logFailure(
        'backup',
        'folder_record_upsert',
        error,
        itemReference: BackgroundBackupRunner.localItemDebugLabel(folderId),
      );
    }
  }

  Future<void> _recordUploadedFile({
    String? journalTransferId,
    required String objectKey,
    required int size,
    String? folderId,
    String? folderName,
    String? folderColorHex,
    required String encryptionMode,
    String storageLayout = 'single',
    int? shardCount,
    int? shardSizeBytes,
    String? shardScheme,
    required String contentEncryption,
    String? secureContentEncoding,
    DateTime? secureRefreshedAt,
    DateTime? secureRefreshDueAt,
    DateTime? uploadedAt,
    List<String>? pathSegments,
    String? contentIntegrityTag,
    String? contentIntegrityVersion,
    String? encryptedName,
    String? displayName,
    String? contentType,
    String? backupPathHash,
    int? backupModifiedMillis,
    String? supersedesFileId,
    bool hasThumbnail = false,
    Map<String, dynamic>? sharedKeyEnvelopes,
    Map<String, dynamic>? storageMetadataOverride,
  }) async {
    _ensureSessionActive();
    _ensureOwnsObjectKey(objectKey);
    final timestamp = uploadedAt ?? DateTime.now().toUtc();
    final normalizedMode = () {
      final value = encryptionMode.trim().toLowerCase();
      if (value == 'secured' || value == 'standard') {
        return value;
      }
      return 'unsecured';
    }();
    final normalizedStorageLayout =
        storageLayout.trim().toLowerCase() == 'sharded' ? 'sharded' : 'single';
    final trimmedEncryptedName = encryptedName?.trim();
    final effectiveEncryptedName =
        trimmedEncryptedName == null || trimmedEncryptedName.isEmpty
        ? null
        : trimmedEncryptedName;
    final effectiveFolderId = folderId;
    final encryptsMetadata =
        normalizedMode == 'secured' || normalizedMode == 'standard';
    final effectivePathSegments = encryptsMetadata
        ? const <String>[]
        : <String>[
            for (final segment in pathSegments ?? const <String>[])
              if (segment.trim().isNotEmpty) segment.trim(),
          ];
    final effectiveFolderName = encryptsMetadata ? null : folderName;
    final effectiveFolderColorHex = encryptsMetadata ? null : folderColorHex;
    final trimmedIntegrityTag = contentIntegrityTag?.trim();
    final trimmedIntegrityVersion = contentIntegrityVersion?.trim();
    final effectiveIntegrityTag =
        normalizedMode == 'standard' &&
            trimmedIntegrityTag != null &&
            trimmedIntegrityTag.isNotEmpty
        ? trimmedIntegrityTag
        : null;
    final effectiveIntegrityVersion =
        normalizedMode == 'standard' &&
            trimmedIntegrityVersion != null &&
            trimmedIntegrityVersion.isNotEmpty
        ? trimmedIntegrityVersion
        : null;
    if ((effectiveIntegrityTag == null) !=
            (effectiveIntegrityVersion == null) ||
        (effectiveIntegrityTag != null &&
            (!effectiveIntegrityTag.startsWith(
                  WorkspaceMetadataEncryptionService.contentIntegrityTagPrefix,
                ) ||
                effectiveIntegrityVersion !=
                    WorkspaceMetadataEncryptionService
                        .contentIntegrityVersion))) {
      throw ArgumentError(
        'Content integrity metadata requires a valid keyed tag and version.',
      );
    }
    final activeStorageMetadata =
        storageMetadataOverride ?? _metadataForActiveStorageSpace();
    final storageScope =
        activeStorageMetadata['storageScope'] as String? ?? 'personal';
    final companyId = activeStorageMetadata['companyId'] as String?;
    final ownerUid =
        activeStorageMetadata['ownerUid'] as String? ?? widget.user.uid;
    final groupIds =
        (activeStorageMetadata['groupIds'] as List?)
            ?.whereType<String>()
            .toList(growable: false) ??
        const <String>[];
    final allowedUids =
        (activeStorageMetadata['allowedUids'] as List?)
            ?.whereType<String>()
            .toList(growable: false) ??
        const <String>[];
    if (normalizedMode == 'secured' && effectiveEncryptedName == null) {
      throw ArgumentError(
        'encryptedName is required when encryptionMode is secured.',
      );
    }

    // Keep quota, lifecycle, identity, and company authorization authoritative
    // on the backend on every platform. Persist only this encrypted/opaque
    // callable payload so an uploaded object can be finalized after a restart.
    final metadataPayload = _uploadMetadataService
        .buildRecordUploadedFilePayload(
          objectKey: objectKey,
          size: size,
          folderId: effectiveFolderId,
          encryptionMode: normalizedMode,
          storageLayout: normalizedStorageLayout,
          shardCount: shardCount,
          shardSizeBytes: shardSizeBytes,
          shardScheme: shardScheme,
          contentEncryption: contentEncryption,
          secureContentEncoding: secureContentEncoding,
          secureRefreshedAt: secureRefreshedAt,
          secureRefreshDueAt: secureRefreshDueAt,
          uploadedAt: timestamp,
          contentIntegrityTag: effectiveIntegrityTag,
          contentIntegrityVersion: effectiveIntegrityVersion,
          encryptedName: effectiveEncryptedName,
          backupPathHash: backupPathHash,
          backupModifiedMillis: backupModifiedMillis,
          storageScope: storageScope,
          companyId: companyId,
          ownerUid: ownerUid,
          groupIds: groupIds,
          allowedUids: allowedUids,
          sharedKeyEnvelopes: sharedKeyEnvelopes,
          supersedesFileId: supersedesFileId,
        );
    if (journalTransferId != null) {
      await _transferJournal?.stageMetadataCommit(
        journalTransferId,
        payload: metadataPayload,
      );
    }

    Future<void> attempt() =>
        _uploadMetadataService.recordUploadedFilePayload(metadataPayload);

    void updateLocalState() {
      final trimmedHash = effectiveIntegrityTag?.trim();
      final localName = () {
        final trimmedDisplay = displayName?.trim();
        if (trimmedDisplay != null && trimmedDisplay.isNotEmpty) {
          return trimmedDisplay;
        }
        final existing = _knownFileByObjectKey(objectKey);
        if (existing != null && existing.name.trim().isNotEmpty) {
          return existing.name;
        }
        final fallback = p.basename(objectKey).trim();
        return fallback.isEmpty ? 'File' : fallback;
      }();
      _upsertLocalDriveFile(
        _DriveFile(
          id: pendingFileIdForObjectKey(objectKey),
          name: localName,
          objectKey: objectKey,
          size: size,
          isFolder: false,
          contentType: contentType,
          uploadedAt: timestamp,
          pathSegments: effectivePathSegments,
          folderId: effectiveFolderId,
          folderName: effectiveFolderName,
          folderColor: effectiveFolderColorHex,
          encryptionMode: normalizedMode,
          encryptedName: effectiveEncryptedName,
          storageLayout: normalizedStorageLayout,
          shardCount: shardCount,
          shardSizeBytes: shardSizeBytes,
          shardScheme: shardScheme,
          contentEncryption: contentEncryption,
          secureContentEncoding: secureContentEncoding,
          secureRefreshedAt: secureRefreshedAt,
          secureRefreshDueAt: secureRefreshDueAt,
          hash: trimmedHash == null || trimmedHash.isEmpty ? null : trimmedHash,
          hasKnownSize: true,
          hasThumbnail: hasThumbnail,
          storageScope: storageScope,
          companyId: companyId,
          ownerUid: ownerUid,
          createdByUid: widget.user.uid,
          backupPathHash: backupPathHash,
          backupModifiedMillis: backupModifiedMillis,
          allowedUids: allowedUids,
          groupIds: groupIds,
          sharedKeyEnvelopes: sharedKeyEnvelopes,
        ),
      );
    }

    try {
      await attempt();
      updateLocalState();
    } on FirebaseException catch (error) {
      if (!_shouldRetryWithFreshAuth(error)) {
        rethrow;
      }
      final twoFactorReady =
          await _forceTwoFactorReverificationIfEnabled() ||
          await _ensureTwoFactorSession(interactive: true);
      if (!twoFactorReady) {
        throw _SessionExpiredException(
          message:
              'Security verification is required before file metadata can be saved.',
          cause: error,
        );
      }
      await _refreshUserIdToken();
      try {
        await attempt();
        updateLocalState();
      } on FirebaseException catch (retryError) {
        if (_shouldRetryWithFreshAuth(retryError)) {
          throw _SessionExpiredException(
            message:
                'Firebase rejected file metadata after refreshing authentication.',
            cause: retryError,
          );
        }
        rethrow;
      }
    }
  }

  Future<void> _refreshUserIdToken() async {
    final user = widget.auth.currentUser;
    if (user == null) {
      throw _SessionExpiredException(
        message:
            'Unable to refresh the Firebase session because no user is signed in.',
      );
    }
    try {
      await user.getIdToken(true);
    } on FirebaseAuthException catch (error) {
      if (kDebugMode) {
        debugPrint('The authenticated session could not be refreshed.');
      }
      throw _SessionExpiredException(
        message: userFacingCloudErrorMessage(
          operation: UserFacingCloudOperation.accountVerification,
          code: error.code,
        ),
        cause: error,
      );
    }
  }

  bool _shouldRetryWithFreshAuth(FirebaseException error) {
    final code = error.code.toLowerCase();
    if (code == 'permission-denied' || code == 'unauthenticated') {
      return true;
    }
    final message = error.message?.toLowerCase() ?? '';
    if (message.contains('insufficient permissions')) {
      return true;
    }
    if (message.contains('permission') && message.contains('denied')) {
      return true;
    }
    if (message.contains('auth') && message.contains('token')) {
      return true;
    }
    if (message.contains('auth') && message.contains('invalid')) {
      return true;
    }
    return false;
  }

  bool _isAuthorizationError(Object error) {
    if (error is FirebaseAuthException) {
      return true;
    }
    if (error is FirebaseException) {
      final code = error.code.toLowerCase();
      if (code == 'permission-denied' || code == 'unauthenticated') {
        return true;
      }
      final message = error.message?.toLowerCase() ?? '';
      if (message.contains('insufficient permissions')) {
        return true;
      }
      if (message.contains('permission') && message.contains('denied')) {
        return true;
      }
      if (message.contains('auth') && message.contains('token')) {
        return true;
      }
      if (message.contains('auth') && message.contains('invalid')) {
        return true;
      }
    }
    return false;
  }

  void _notifyBackupAuthorizationIssue() {
    if (_sessionInvalidated || _backupAuthErrorShown) {
      return;
    }
    _backupAuthErrorShown = true;
    _showMessage(
      'Backup could not upload files because your session expired. Please sign in again to resume backups.',
    );
  }

  void _notifyUploadAuthorizationIssue() {
    if (_sessionInvalidated) {
      return;
    }
    _showMessage(
      'Your session has expired. Please sign in again and retry the upload.',
    );
  }

  void _handleSessionExpired([Object? reason]) {
    _activeMemoryPreview?.cancel();
    if (_sessionInvalidated) {
      return;
    }
    _sessionInvalidated = true;
    if (kDebugMode && reason != null) {
      debugPrint('Signing out after the authenticated session expired.');
    }
    if (mounted) {
      _showMessage('Your session expired. Please sign in again to continue.');
    }
    LoginPasswordVault.instance.clear();
    unawaited(widget.auth.signOut());
  }

  void _ensureSessionActive() {
    if (_sessionInvalidated) {
      throw _SessionExpiredException(
        message: 'The current session is no longer valid.',
      );
    }
    final currentUser = widget.auth.currentUser;
    if (currentUser == null) {
      throw _SessionExpiredException(
        message: 'No authenticated Firebase user is available.',
      );
    }
    if (currentUser.uid != widget.user.uid) {
      throw _SessionExpiredException(
        message: 'The active Firebase user no longer matches this workspace.',
      );
    }
  }

  List<String> get _objectKeyOwnerPrefixes {
    final prefixes = <String>{};
    final storagePrefix = sanitizeStorageHomePrefix(_storageHomePrefix);
    if (storagePrefix != null) {
      prefixes.add(storagePrefix);
    }

    final uidHashPrefix = storageHomePrefixForUid(widget.user.uid);
    if (uidHashPrefix != null) {
      prefixes.add(uidHashPrefix);
    }

    final emailPrefix = sanitizeStorageHomePrefix(widget.user.email);
    if (emailPrefix != null) {
      prefixes.add(emailPrefix);
    }

    final uid = widget.user.uid.trim();
    if (uid.isNotEmpty) {
      prefixes.add(uid);
    } else if (widget.user.uid.isNotEmpty) {
      prefixes.add(widget.user.uid);
    }

    if (prefixes.isEmpty) {
      prefixes.add(widget.user.uid);
    }

    final companyId = _companyId?.trim();
    if (_canUseCompanyStorage && companyId != null && companyId.isNotEmpty) {
      if (_companyPrivateStorageAllowed) {
        final prefix = companyPrivateStoragePrefix(companyId, widget.user.uid);
        if (prefix != null) {
          prefixes.add(prefix);
        }
      }
      if (_companySharedStorageAllowed) {
        final prefix = companySharedStoragePrefix(companyId);
        if (prefix != null) {
          prefixes.add(prefix);
        }
      }
      final storageEnabledGroupIds =
          _companyGroupStorageEnabledIds ?? _companyGroupIds;
      for (final groupId in storageEnabledGroupIds) {
        final prefix = companyGroupStoragePrefix(companyId, groupId);
        if (prefix != null) {
          prefixes.add(prefix);
        }
      }
    }

    return prefixes.toList(growable: false);
  }

  String get _objectKeyOwnerPrefix {
    final activePrefix = _activeObjectKeyOwnerPrefix;
    if (activePrefix != null) {
      return activePrefix;
    }
    return _objectKeyOwnerPrefixes.first;
  }

  String? get _activeObjectKeyOwnerPrefix {
    final companyId = _companyId?.trim();
    switch (_activeStorageScope) {
      case 'company_private':
        return companyPrivateStoragePrefix(companyId, widget.user.uid);
      case 'company_shared':
        return companySharedStoragePrefix(companyId);
      case 'group':
        return companyGroupStoragePrefix(companyId, _activeStorageGroupId);
      default:
        return null;
    }
  }

  void _ensureOwnsObjectKey(String objectKey) {
    final trimmedKey = objectKey.trim();
    final ownsObject = _objectKeyOwnerPrefixes.any(
      (prefix) => trimmedKey.startsWith('$prefix/'),
    );
    if (!ownsObject) {
      throw _SessionExpiredException(
        message: 'Attempted to access storage outside of your workspace.',
        cause: StateError('Unauthorized Wasabi object key: $objectKey'),
      );
    }
  }

  Future<T> _runOnPlatformThread<T>(Future<T> Function() action) {
    final binding = WidgetsBinding.instance;
    if (binding.schedulerPhase == SchedulerPhase.idle ||
        binding.schedulerPhase == SchedulerPhase.postFrameCallbacks) {
      return action();
    }

    final completer = Completer<T>();
    binding.addPostFrameCallback((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<String?> _promptForRemoteFolderName({
    required String suggested,
  }) async {
    var name = suggested.trim();
    String? result;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Name your backup in Drive'),
          content: TextFormField(
            initialValue: suggested,
            decoration: const InputDecoration(
              labelText: 'Folder name or path',
              helperText:
                  'Use "/" to create nested folders (e.g. Photos/Trips).',
            ),
            autofocus: true,
            onChanged: (value) => name = value.trim(),
            onFieldSubmitted: (value) {
              final trimmed = value.trim();
              if (trimmed.isEmpty) {
                return;
              }
              result = trimmed;
              Navigator.of(context).pop();
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (name.isEmpty) {
                  return;
                }
                result = name;
                Navigator.of(context).pop();
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    return result;
  }

  Future<Uint8List?> _fetchThumbnail(
    _DriveFile file, {
    bool force = false,
    bool interactive = false,
  }) async {
    if (!file.supportsThumbnailPreview ||
        !_canReadStorageScope(file.storageScope)) {
      return null;
    }

    bool stillAuthorized() => _canReadStorageScope(file.storageScope);

    if (force) {
      _thumbnailRetryAfter.remove(file.objectKey);
      _thumbnailRequests.remove(file.objectKey);
    }

    final cached = _thumbnailCache[file.objectKey];
    if (cached != null && !force) {
      return cached;
    }

    final retryAfter = _thumbnailRetryAfter[file.objectKey];
    if (retryAfter != null && DateTime.now().isBefore(retryAfter)) {
      return null;
    }

    final pending = _thumbnailRequests[file.objectKey];
    if (pending != null) {
      return pending;
    }

    late final Future<Uint8List?> request;
    request = () async {
      final storageReady = await _ensureStorageConfiguredForPreview();
      if (!stillAuthorized()) {
        return null;
      }
      if (!storageReady) {
        _thumbnailRetryAfter[file.objectKey] = DateTime.now().add(
          const Duration(seconds: 5),
        );
        _logRuntime(
          'thumbnails',
          'Deferred a thumbnail load until storage is ready.',
        );
        return null;
      }

      String? keyString;
      SecretKey? secretKey;
      Future<SecretKey?> resolveSecretKey() async {
        if (!stillAuthorized()) {
          return null;
        }
        if (!file.isEncrypted) {
          return null;
        }
        if (secretKey != null) {
          return secretKey;
        }
        keyString ??= await _encryptionKeyStringForFile(
          file,
          interactive: interactive,
        );
        if (keyString == null || !stillAuthorized()) {
          return null;
        }
        secretKey = SecretKey(base64Decode(keyString!));
        return secretKey;
      }

      Future<Uint8List?> generateFromOriginal() async {
        if (!file.isImageLike || file.size > _maxInlinePreviewBytes) {
          return null;
        }
        final originalSecretKey = await resolveSecretKey();
        if (file.isEncrypted && originalSecretKey == null) {
          _thumbnailRetryAfter[file.objectKey] = DateTime.now().add(
            const Duration(minutes: 1),
          );
          return null;
        }
        final originalBytes = await _downloadFileBytes(
          file,
          secretKey: originalSecretKey,
          preferProxy: kIsWeb,
          maxBytes: _maxInlinePreviewBytes,
        );
        if (originalBytes.isEmpty || !stillAuthorized()) {
          return null;
        }
        final thumbnailBytes = await _generateThumbnailBytes(
          XFile.fromData(
            originalBytes,
            name: file.name,
            mimeType: file.contentType,
          ),
          bytes: originalBytes,
        );
        if (thumbnailBytes == null ||
            thumbnailBytes.isEmpty ||
            !stillAuthorized()) {
          return null;
        }
        _thumbnailCache[file.objectKey] = thumbnailBytes;
        _thumbnailRetryAfter.remove(file.objectKey);
        if (originalSecretKey != null) {
          unawaited(
            _storeGeneratedThumbnail(
              file,
              thumbnailBytes,
              encryptionKey: originalSecretKey,
            ),
          );
        }
        return thumbnailBytes;
      }

      try {
        final thumbnailSecretKey = await resolveSecretKey();
        if (file.isEncrypted && thumbnailSecretKey == null) {
          _thumbnailRetryAfter[file.objectKey] = DateTime.now().add(
            const Duration(minutes: 1),
          );
          return null;
        }
        for (final thumbnailKey in _thumbnailObjectKeyCandidatesFor(
          file.objectKey,
        )) {
          try {
            final stream = await _storageService.download(
              objectKey: thumbnailKey,
              encryptionKey: thumbnailSecretKey,
              preferProxy: kIsWeb,
              maxPlaintextBytes: imageThumbnailMaxStoredBytes,
            );
            final bytes = await normalizeStoredImageThumbnail(stream);
            if (bytes == null || bytes.isEmpty || !stillAuthorized()) {
              continue;
            }
            _thumbnailCache[file.objectKey] = bytes;
            _thumbnailRetryAfter.remove(file.objectKey);
            return bytes;
          } catch (_) {
            // Current and legacy preview objects are optional. Continue to
            // the next opaque candidate, then rebuild from the encrypted
            // original without disclosing provider error details.
          }
        }
        try {
          final generated = await generateFromOriginal();
          if (generated != null) {
            return generated;
          }
        } catch (error) {
          BackgroundBackupRunner.logFailure(
            'preview',
            'fallback_thumbnail_generation',
            error,
          );
        }
        if (stillAuthorized()) {
          _thumbnailRetryAfter[file.objectKey] = DateTime.now().add(
            const Duration(minutes: 5),
          );
        }
        return null;
      } catch (error) {
        BackgroundBackupRunner.logFailure(
          'preview',
          'thumbnail_resolution',
          error,
        );
        if (stillAuthorized()) {
          _thumbnailRetryAfter[file.objectKey] = DateTime.now().add(
            const Duration(minutes: 5),
          );
        }
        return null;
      } finally {
        if (identical(_thumbnailRequests[file.objectKey], request)) {
          _thumbnailRequests.remove(file.objectKey);
        }
      }
    }();

    _thumbnailRequests[file.objectKey] = request;
    return request;
  }

  Future<void> _storeGeneratedThumbnail(
    _DriveFile file,
    Uint8List thumbnailBytes, {
    required SecretKey encryptionKey,
  }) async {
    if (thumbnailBytes.isEmpty ||
        !_storageService.isConfigured ||
        !_canReadStorageScope(file.storageScope) ||
        !_canWriteStorageScope(file.storageScope)) {
      return;
    }
    try {
      final thumbnailKey = _thumbnailObjectKeyFor(file.objectKey);
      _ensureOwnsObjectKey(thumbnailKey);
      final api = UploadCoordinator.enabled
          ? _storageService.uploadSessionApi
          : null;
      final previewCommit = {
        'fileId': file.id,
        'sessionId': sha256
            .convert(utf8.encode('${widget.user.uid}\u0000$thumbnailKey'))
            .toString(),
      };
      if (api != null) {
        // Recover a lost finalization response without replacing the immutable
        // encrypted preview or charging its reservation again.
        try {
          await api.call('commitPreview', previewCommit);
          return;
        } on UploadFailure catch (error) {
          if (error.code != 'not_found' && error.code != 'incomplete_upload') {
            rethrow;
          }
        }
      }
      await _storageService.upload(
        objectKey: thumbnailKey,
        stream: Stream.value(thumbnailBytes),
        length: thumbnailBytes.length,
        contentType: imageThumbnailContentType,
        encryptionKey: encryptionKey,
      );
      if (api != null) {
        await api.call('commitPreview', previewCommit);
      }
    } catch (error) {
      BackgroundBackupRunner.logFailure(
        'preview',
        'generated_thumbnail_repair',
        error,
      );
    }
  }

  _InlineFilePreviewKind _previewKindForFile(_DriveFile file) {
    if (file.isFolder) {
      return _InlineFilePreviewKind.unsupported;
    }

    final extension = p
        .extension(file.name)
        .replaceFirst('.', '')
        .toLowerCase();
    final contentType = file.contentType?.trim().toLowerCase();
    final isImageType =
        (contentType != null && contentType.startsWith('image/')) ||
        _imagePreviewExtensions.contains(extension);
    if (isImageType) {
      return _InlineFilePreviewKind.image;
    }

    final isTextType =
        (contentType != null &&
            (contentType.startsWith('text/') ||
                contentType == 'application/json' ||
                contentType == 'application/xml' ||
                contentType == 'application/javascript' ||
                contentType == 'application/x-yaml' ||
                contentType == 'application/yaml')) ||
        _textPreviewExtensions.contains(extension);
    if (isTextType) {
      return _InlineFilePreviewKind.text;
    }

    return _InlineFilePreviewKind.unsupported;
  }

  bool _supportsInlinePreview(_DriveFile file) =>
      file.size <= _previewLimit(file) &&
      _previewKindForFile(file) != _InlineFilePreviewKind.unsupported;

  int _previewLimit(_DriveFile file) =>
      _previewKindForFile(file) == _InlineFilePreviewKind.text
      ? MemoryPreviewPolicy.textBytes
      : MemoryPreviewPolicy.imageBytes;

  void _checkFileDownloadAccess(_DriveFile file, {String? expectedKey}) {
    _ensureSessionActive();
    if (!mounted || widget.auth.currentUser?.uid != widget.user.uid ||
        !_canReadStorageScope(file.storageScope)) {
      throw const PreviewUnavailable();
    }
    _ensureOwnsObjectKey(file.objectKey);
    // Use the established source maps, not a catalogue scan for every chunk.
    final current = _fileSnapshotSources.item(WorkspaceSnapshotSource.assignedBusiness, file.id) ??
        _fileSnapshotSources.item(WorkspaceSnapshotSource.personal, file.id);
    if (current == null || current.objectKey != file.objectKey ||
        current.revision != file.revision || current.lifecycleState != file.lifecycleState ||
        current.hash != file.hash || !mapEquals(current.sharedKeyEnvelopes, file.sharedKeyEnvelopes)) {
      throw const PreviewUnavailable();
    }
    if (!file.isEncrypted) return;
    if (file.sharedKeyEnvelopes.isNotEmpty) {
      final identity = _businessEncryptionIdentity;
      final envelope = file.sharedKeyEnvelopes[widget.user.uid];
      if (identity == null || envelope is! Map) throw const PreviewUnavailable();
      final cached = _businessFileKeyCache['file:${file.id}|${identity.keyId}|${envelope['encryptedFileKeyBase64']}'];
      if (cached == null || (expectedKey != null && cached != expectedKey)) throw const PreviewUnavailable();
    } else {
      final cached = file.isSecured ? _cachedSecureEncryptionKey : _cachedEncryptionKey;
      if (cached == null || (expectedKey != null && cached != expectedKey)) throw const PreviewUnavailable();
    }
  }

  Stream<List<int>> _streamFilePlaintext(
    _DriveFile file, {
    SecretKey? secretKey,
  }) async* {
    final expectedKey = secretKey == null ? null : base64Encode(await secretKey.extractBytes());
    void check() => _checkFileDownloadAccess(file, expectedKey: expectedKey);
    check();
    if (!file.isSharded) {
      final stream = await _storageService.download(
        objectKey: file.objectKey,
        encryptionKey: secretKey,
      );
      await for (final chunk in stream) {
        check();
        yield chunk;
      }
    } else {
      if (secretKey == null) {
        throw StateError('Secure sharded file needs an encryption key.');
      }
      final count = file.shardCount ?? 0;
      if (count <= 0) {
        throw const FormatException('The secure file has no shards.');
      }
      final encryptedOrPlain = () async* {
        for (var index = 0; index < count; index++) {
          check();
          final stream = await _storageService.download(
            objectKey: await _secureShardObjectKey(
              file,
              index,
              encryptionKey: file.usesPassphraseHmacShards ? secretKey : null,
            ),
            encryptionKey: file.usesWholeFileSecureContent ? null : secretKey,
          );
          await for (final chunk in stream) {
            check();
            yield chunk;
          }
        }
      }();
      if (file.usesWholeFileSecureContent) {
        if (kIsWeb) {
          final bytes = await _downloadFileBytes(file, secretKey: secretKey);
          try {
            check();
            yield bytes;
          } finally {
            bytes.fillRange(0, bytes.length, 0);
          }
        } else {
          yield* decryptFramedDownload(
            encryptedOrPlain,
            key: secretKey,
            manager: _temporaryPlaintextLeases,
            checkAccess: check,
          );
        }
      } else {
        yield* encryptedOrPlain;
      }
    }
    check();
    _recordSuccessfulFileAccess(file);
  }

  Future<void> _downloadNativeZip(
    List<_DriveFile> files,
    String transferId,
  ) async {
    final name = _downloadBundleFileName();
    final output = await _createTemporaryPlaintextLease(name);
    NativeStreamingZip? encoder;
    var handedOff = false;
    var completed = 0;
    final usedNames = <String>{}, failures = <String>[];
    final successful = <_DriveFile>[];
    try {
      encoder = await NativeStreamingZip.create(output);
      for (var index = 0; index < files.length; index++) {
        final file = files[index];
        _updateTransfer(
          transferId,
          'Preparing ZIP ${index + 1}/${files.length}: ${file.name}',
        );
        TemporaryPlaintextLease? input;
        try {
          _ensureSessionActive();
          _ensureOwnsObjectKey(file.objectKey);
          final key = await _secretKeyForDownload(file);
          if (file.isEncrypted && key == null) {
            failures.add(file.name);
            continue;
          }
          input = await _createTemporaryPlaintextLease(file.name);
          await input.writeStream(
            _streamFilePlaintext(file, secretKey: key),
            checkAccess: () => _checkFileDownloadAccess(file),
          );
        } on _SessionExpiredException {
          rethrow;
        } catch (error) {
          await input?.release();
          failures.add(file.name);
          BackgroundBackupRunner.logFailure('download', 'zip_entry', error);
          continue;
        }
        try {
          _checkFileDownloadAccess(file);
          await encoder.add(input, _uniqueArchiveEntryName(file, usedNames));
          _checkFileDownloadAccess(file);
          successful.add(file);
          completed++;
        } finally {
          await input.release();
        }
      }
      if (completed == 0) {
        _showMessage('No selected files could be downloaded.');
        return;
      }
      _updateTransfer(transferId, 'Creating ZIP download...');
      await encoder.close();
      encoder = null;
      for (final file in successful) {
        _checkFileDownloadAccess(file);
      }
      await output.seal();
      await _shareTemporaryPlaintextLease(output, displayName: name);
      handedOff = true;
      _showMessage(
        failures.isEmpty
            ? 'Downloaded $completed files as a ZIP.'
            : 'Downloaded $completed files. ${failures.length} failed.',
      );
    } finally {
      encoder?.cancel();
      if (!handedOff) await output.release();
    }
  }

  Future<Uint8List> _downloadFileBytes(
    _DriveFile file, {
    SecretKey? secretKey,
    bool preferProxy = false,
    int? maxBytes,
    PreviewReadGuard? previewGuard,
  }) async {
    void ensureStillAuthorized() {
      previewGuard?.check();
      _ensureSessionActive();
      if (!mounted || widget.auth.currentUser?.uid != widget.user.uid) {
        throw const PreviewUnavailable();
      }
      if (!_canReadStorageScope(file.storageScope)) {
        throw _SessionExpiredException(
          message: 'Business file access changed. Refresh and try again.',
        );
      }
    }

    ensureStillAuthorized();
    if (maxBytes != null && maxBytes <= 0) {
      throw const FormatException('The local file buffer limit is invalid.');
    }
    if (file.isSharded) {
      if (secretKey == null) {
        throw StateError('Secure sharded file needs an encryption key.');
      }
      final count = file.shardCount ?? 0;
      if (previewGuard != null && count > 1024) {
        throw const PreviewUnavailable();
      }
      final bytes = await assembleSecureShards(
        shardCount: count,
        openShard: (index) async {
          ensureStillAuthorized();
          final stream = await _storageService.download(
            objectKey: await _secureShardObjectKey(
              file,
              index,
              encryptionKey: file.usesPassphraseHmacShards ? secretKey : null,
            ),
            encryptionKey: file.usesWholeFileSecureContent ? null : secretKey,
            preferProxy: preferProxy,
            maxPlaintextBytes: maxBytes == null
                ? null
                : file.usesWholeFileSecureContent
                ? maxBytes + 1024
                : maxBytes,
          );
          return previewGuard?.watch(stream) ?? stream;
        },
        decryptWholeFile: file.usesWholeFileSecureContent
            ? (bytes) =>
                  EncryptionService.instance.decryptData(bytes, secretKey)
            : null,
        maxBufferedBytes: maxBytes == null
            ? null
            : file.usesWholeFileSecureContent
            ? maxBytes + 1024
            : maxBytes,
      );
      if (maxBytes != null && bytes.length > maxBytes) {
        bytes.fillRange(0, bytes.length, 0);
        throw const FormatException(
          'The downloaded file exceeded its local buffer limit.',
        );
      }
      try {
        ensureStillAuthorized();
      } catch (_) {
        bytes.fillRange(0, bytes.length, 0);
        rethrow;
      }
      _recordSuccessfulFileAccess(file);
      return bytes;
    }
    final stream = await _storageService.download(
      objectKey: file.objectKey,
      encryptionKey: secretKey,
      preferProxy: preferProxy,
      maxPlaintextBytes: maxBytes,
    );
    final bytes = await readAuthenticatedBytes(
      stream,
      maximumBytes: maxBytes,
      checkAccess: ensureStillAuthorized,
      guard: previewGuard,
    );
    _recordSuccessfulFileAccess(file);
    return bytes;
  }

  void _recordSuccessfulFileAccess(_DriveFile file) {
    unawaited(
      _secureDriveService.recordFileAccess(fileId: file.id).catchError((
        Object error,
        StackTrace _,
      ) {
        BackgroundBackupRunner.logFailure(
          'storage',
          'coarse_file_access',
          error,
        );
      }),
    );
  }

  Future<String?> _encryptionKeyStringForFile(
    _DriveFile file, {
    required bool interactive,
  }) async {
    if (file.sharedKeyEnvelopes.isNotEmpty) {
      return _businessFileKeyStringForFile(file, interactive: interactive);
    }
    if (file.isSecured) {
      return _ensureSecureEncryptionKey(interactive: interactive);
    }
    if (file.isStandardEncrypted || _fileNeedsLocalNameDecryption(file)) {
      return _ensureEncryptionKey(interactive: interactive);
    }
    return Future<String?>.value(null);
  }

  Future<TemporaryPlaintextLease> _createTemporaryPlaintextLease(
    String fileName,
  ) {
    return _temporaryPlaintextLeases.create(
      extension: TemporaryPlaintextLeaseManager.extensionForName(fileName),
    );
  }

  Future<void> _shareTemporaryPlaintextLease(
    TemporaryPlaintextLease lease, {
    required String displayName,
    String? text,
    Rect? sharePositionOrigin,
  }) async {
    try {
      await Share.shareXFiles(
        [XFile(lease.file.path, name: displayName)],
        text: text,
        sharePositionOrigin: sharePositionOrigin,
      );
      lease.scheduleRelease(const Duration(minutes: 5));
    } catch (_) {
      await lease.release();
      rethrow;
    }
  }

  Future<void> _cleanupPlaintextTemporaryFilesOnStartup() async {
    if (kIsWeb) {
      return;
    }
    try {
      await _temporaryPlaintextLeases.cleanupStale();
      await _temporaryPlaintextLeases.cleanupLegacyOpenDirectory();
    } catch (_) {
      if (kDebugMode) {
        debugPrint('Temporary plaintext crash recovery was deferred.');
      }
    }
  }

  Future<void> _cleanupPlaintextTemporaryFilesAfterResume() async {
    try {
      await _temporaryPlaintextLeases.cleanupActive();
      await _temporaryPlaintextLeases.cleanupStale();
    } catch (_) {
      if (kDebugMode) {
        debugPrint('Temporary plaintext resume cleanup was deferred.');
      }
    }
  }

  Future<int> _clearPlaintextTemporaryFiles() async {
    if (kIsWeb) {
      return 0;
    }
    final current = await _temporaryPlaintextLeases.clearAll();
    final legacy = await _temporaryPlaintextLeases.cleanupLegacyOpenDirectory(
      removeAll: true,
    );
    return current + legacy;
  }

  Future<bool> _confirmPlaintextLocalWrite(
    _DriveFile file, {
    required String action,
  }) async {
    if (!_blocksPlaintextLocalWrite(file)) {
      return true;
    }
    if (!mounted) {
      return false;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$action secure file?'),
        content: Text(
          '$action will create a temporary decrypted copy of ${file.name} on this device. '
          'RonikCloud cleans old temp copies, but the external app may keep its own recent-file history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<bool> _openLocalPathExternally(String path) async {
    final result = await OpenFilex.open(path);
    if (result.type == ResultType.done) {
      return true;
    }

    if (!kIsWeb && Platform.isWindows) {
      final openAs = await Process.run('rundll32', [
        'shell32.dll,OpenAs_RunDLL',
        path,
      ]);
      if (openAs.exitCode == 0) {
        return true;
      }
    }

    final details = result.message.trim();
    _showMessage(
      details.isEmpty
          ? 'Could not open file.'
          : 'Could not open file: $details',
    );
    return false;
  }

  Future<void> _openDownloadedFileExternally(
    _DriveFile file, {
    SecretKey? secretKey,
    bool localWriteConfirmed = false,
  }) async {
    final confirmed =
        localWriteConfirmed ||
        await _confirmPlaintextLocalWrite(file, action: 'Open');
    if (!confirmed) {
      return;
    }

    TemporaryPlaintextLease? lease;
    try {
      lease = await _createTemporaryPlaintextLease(file.name);
      await lease.writeStream(_streamFilePlaintext(file, secretKey: secretKey),
        checkAccess: () => _checkFileDownloadAccess(file));
      if (!await _openLocalPathExternally(lease.file.path)) {
        await lease.release();
      }
    } catch (_) {
      await lease?.release();
      rethrow;
    }
  }

  Future<void> _showMemoryPreview(
    _DriveFile file, {
    required String? keyString,
    required Future<Uint8List> Function(PreviewReadGuard guard) load,
  }) async {
    if (!mounted || _activeMemoryPreview != null) return;
    if (_memoryPreviewReadInFlight) {
      _showMessage(
        'The previous preview is still closing. Try again in a moment.',
      );
      return;
    }
    final guard = PreviewReadGuard(() {
      if (!mounted ||
          _sessionInvalidated ||
          _authSessionInvalid ||
          widget.auth.currentUser?.uid != widget.user.uid ||
          !_canReadStorageScope(file.storageScope)) {
        return false;
      }
      if (keyString != null) {
        if (file.sharedKeyEnvelopes.isNotEmpty) {
          if (!_businessFileKeyCache.containsValue(keyString)) return false;
        } else if ((file.isSecured
                ? _cachedSecureEncryptionKey
                : _cachedEncryptionKey) !=
            keyString) {
          return false;
        }
      }
      // An authoritative catalogue update invalidates deleted/replaced items.
      final current = _files.where((item) => item.id == file.id).firstOrNull;
      return current != null &&
          current.objectKey == file.objectKey &&
          current.revision == file.revision &&
          current.lifecycleState == file.lifecycleState &&
          mapEquals(current.sharedKeyEnvelopes, file.sharedKeyEnvelopes);
    });
    _activeMemoryPreview = guard;
    final authChanges = widget.auth.authStateChanges().listen((user) {
      if (user?.uid != widget.user.uid) guard.cancel();
    });
    final route = MaterialPageRoute<void>(
      builder: (_) => MemoryFilePreviewPage(
        name: file.name,
        kind: _previewKindForFile(file) == _InlineFilePreviewKind.image
            ? MemoryPreviewKind.image
            : MemoryPreviewKind.text,
        guard: guard,
        load: () {
          _memoryPreviewReadInFlight = true;
          return load(guard);
        },
        onLoadFinished: () => _memoryPreviewReadInFlight = false,
      ),
    );
    try {
      await Navigator.of(context).push(route);
      guard.cancel();
      await route.completed;
    } finally {
      await authChanges.cancel();
      guard.cancel();
      if (identical(_activeMemoryPreview, guard)) _activeMemoryPreview = null;
      guard.dispose();
    }
  }

  Future<bool> _offerExternalOpen(_DriveFile file) async {
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Private preview unavailable'),
            content: const Text(
              'Private preview supports text up to 1 MiB and images up to 20 MiB. '
              'This file needs a download or another app. Continuing creates a readable copy on this device.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(kIsWeb ? 'Download file' : 'Open in another app'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _openDriveFile(_DriveFile file) async {
    if (_activeMemoryPreview != null) return;
    if (!_ensureStorageReadsAvailable(storageScope: file.storageScope)) {
      return;
    }
    if (_offlineFiles.containsKey(file.objectKey)) {
      await _openOfflineFile(file, _offlineFiles[file.objectKey]!);
      return;
    }

    _showMessage('Opening ${file.name}...');

    try {
      final storageReady = await _ensureStorageConfigured(
        forceRefresh: !_storageService.isConfigured,
      );
      if (!mounted || !storageReady) {
        return;
      }

      _ensureOwnsObjectKey(file.objectKey);

      SecretKey? secretKey;
      final keyString = await _encryptionKeyStringForFile(
        file,
        interactive: true,
      );
      if (file.isEncrypted && keyString == null) {
        _showMessage(
          file.isSecured
              ? 'Unlock secure mode to open this file.'
              : 'Sign in again to unlock standard encryption.',
        );
        return;
      }
      if (keyString != null) {
        secretKey = SecretKey(base64Decode(keyString));
      }

      if (_supportsInlinePreview(file)) {
        await _showMemoryPreview(
          file,
          keyString: keyString,
          load: (guard) => _downloadFileBytes(
            file,
            secretKey: secretKey,
            preferProxy: kIsWeb,
            maxBytes: _previewLimit(file),
            previewGuard: guard,
          ),
        );
        return;
      }

      if (!await _offerExternalOpen(file)) return;
      if (kIsWeb) {
        final bytes = await _downloadFileBytes(file, secretKey: secretKey);
        await downloadFile(bytes, file.name);
        return;
      }

      await _openDownloadedFileExternally(
        file,
        secretKey: secretKey,
        localWriteConfirmed: true,
      );
    } on _SessionExpiredException catch (error) {
      _handleSessionExpired(error);
    } on WasabiConfigurationException catch (error) {
      BackgroundBackupRunner.logFailure('preview', 'open_file', error);
      _showMessage(error.message);
    } catch (error) {
      BackgroundBackupRunner.logFailure('preview', 'open_file', error);
      _showMessage('Failed to download and open ${file.name}.');
    }
  }

  Future<void> _openOfflineFile(
    _DriveFile file,
    _OfflineFileInfo originalInfo,
  ) async {
    if (_activeMemoryPreview != null) return;
    if (!_ensureStorageReadsAvailable(storageScope: file.storageScope)) {
      return;
    }
    var info = originalInfo;
    if (!info.isEncryptedVault) {
      final migrated = await _migrateLegacyOfflineEntry(
        file,
        info,
        interactive: true,
      );
      if (migrated == null) {
        return;
      }
      info = migrated;
    }

    final encryptedFile = File(info.localPath);
    final exists = await encryptedFile.exists();
    if (!exists) {
      await _removeOfflineEntry(file.objectKey, persist: false);
      await _persistOfflineFiles();
      _showMessage('Offline copy for ${file.name} is missing.');
      return;
    }

    final encryptionKey = await _encryptionKeyStringForFile(
      file,
      interactive: true,
    );
    if (file.isEncrypted && encryptionKey == null) {
      _showMessage(
        file.isSecured
            ? 'Unlock secure mode to open this offline file.'
            : 'Sign in again to unlock this offline file.',
      );
      return;
    }
    final bindingKey = encryptionKey == null
        ? null
        : SecretKey(base64Decode(encryptionKey));

    if (_supportsInlinePreview(file)) {
      try {
        await _showMemoryPreview(
          file,
          keyString: encryptionKey,
          load: (guard) async {
            guard.check();
            final bytes = await _offlineVault.readBytes(
              source: encryptedFile,
              objectKey: file.objectKey,
              bindingKey: bindingKey,
              maximumBytes: _previewLimit(file),
              checkAccess: guard.check,
            );
            try {
              guard.check();
              _recordSuccessfulFileAccess(file);
              return bytes;
            } catch (_) {
              bytes.fillRange(0, bytes.length, 0);
              rethrow;
            }
          },
        );
        return;
      } on LocalOfflineVaultException catch (error) {
        await _handleOfflineVaultFailure(file, error);
        return;
      } catch (error) {
        BackgroundBackupRunner.logFailure(
          'preview',
          'offline_inline_preview',
          error,
        );
        return;
      }
    }

    if (!await _offerExternalOpen(file)) return;
    await _openOfflineFileExternally(
      file,
      info,
      bindingKey: bindingKey,
      localWriteConfirmed: true,
    );
  }

  Future<void> _openOfflineFileExternally(
    _DriveFile file,
    _OfflineFileInfo info, {
    required SecretKey? bindingKey,
    bool localWriteConfirmed = false,
  }) async {
    final confirmed =
        localWriteConfirmed ||
        await _confirmPlaintextLocalWrite(file, action: 'Open');
    if (!confirmed) {
      return;
    }
    final lease = await _createTemporaryPlaintextLease(file.name);
    try {
      await _offlineVault.decryptToFile(
        source: File(info.localPath),
        destination: lease.file,
        objectKey: file.objectKey,
        bindingKey: bindingKey,
      );
      await lease.seal();
      _recordSuccessfulFileAccess(file);
      if (!await _openLocalPathExternally(lease.file.path)) {
        await lease.release();
      }
    } on LocalOfflineVaultException catch (error) {
      await lease.release();
      await _handleOfflineVaultFailure(file, error);
    } catch (_) {
      await lease.release();
      rethrow;
    }
  }

  Future<void> _handleOfflineVaultFailure(
    _DriveFile file,
    LocalOfflineVaultException error,
  ) async {
    if (error.failure == LocalOfflineVaultFailure.keyUnavailable) {
      _showMessage(
        'The device keychain is locked. Unlock the device and try again.',
      );
      return;
    }
    if (error.failure == LocalOfflineVaultFailure.corruptPayload ||
        error.failure == LocalOfflineVaultFailure.unsupportedFormat) {
      await _removeOfflineEntry(file.objectKey, persist: false);
      await _persistOfflineFiles();
      _showMessage(
        'The offline copy of ${file.name} failed its integrity check and was '
        'removed. The encrypted cloud copy is unchanged.',
      );
      return;
    }
    _showMessage('We could not open the encrypted offline copy.');
  }

  Future<void> _removeOfflineFile(_DriveFile file) async {
    if (!_offlineFiles.containsKey(file.objectKey)) {
      return;
    }

    await _removeOfflineEntry(file.objectKey, persist: false);
    await _persistOfflineFiles();
    _showMessage('Removed offline copy of ${file.name}.');
  }

  Future<void> _toggleSecurityMode(
    bool value, {
    VoidCallback? onStateUpdated,
  }) async {
    if (_securityBusy || value == _passphraseRequired) {
      return;
    }

    if (mounted) {
      setState(() {
        _securityBusy = true;
      });
    } else {
      _securityBusy = true;
    }
    onStateUpdated?.call();

    await _handlePassphraseToggle(value);

    if (!mounted) {
      _securityBusy = false;
      onStateUpdated?.call();
      return;
    }

    setState(() {
      _securityBusy = false;
    });
    onStateUpdated?.call();
  }

  Future<void> _showBugReportDialog() async {
    if (!canSubmitIssueReport(_supportProfile)) {
      _showMessage(
        'Issue reporting is available with an active paid plan. You can share feature ideas and general feedback from App and support.',
      );
      return;
    }
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    final stepsController = TextEditingController();
    String? validationMessage;
    var submitting = false;

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              Future<void> submit() async {
                final title = titleController.text.trim();
                final description = descriptionController.text.trim();
                final steps = stepsController.text.trim();

                if (description.isEmpty) {
                  setDialogState(() {
                    validationMessage = 'Describe the issue before sending.';
                  });
                  return;
                }

                setDialogState(() {
                  submitting = true;
                  validationMessage = null;
                });

                try {
                  final preview = SupportReportPayload.prepare(
                    title: title, description: description, stepsToReproduce: steps,
                    platform: kIsWeb ? 'web' : defaultTargetPlatform.name,
                    buildMode: kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug'),
                  );
                  if (!await reviewSupportReport(context, preview)) {
                    if (dialogContext.mounted) setDialogState(() => submitting = false);
                    return;
                  }
                  if (!dialogContext.mounted) return;
                  _ensureSessionActive();
                  final receipt = await _secureDriveService.submitSupportReport(
                    title: title,
                    description: description,
                    stepsToReproduce: steps,
                    platform: kIsWeb ? 'web' : defaultTargetPlatform.name,
                    buildMode: kReleaseMode
                        ? 'release'
                        : (kProfileMode ? 'profile' : 'debug'),
                  );

                  if (!dialogContext.mounted) {
                    return;
                  }
                  Navigator.of(dialogContext).pop();
                  if (mounted) {
                    unawaited(_showSupportReportReceipt(receipt));
                  }
                } catch (_) {
                  if (kDebugMode) {
                    debugPrint(
                      'Privacy-filtered support report submission failed.',
                    );
                  }
                  if (dialogContext.mounted) {
                    setDialogState(() {
                      submitting = false;
                      validationMessage = userFacingClientFailureMessage(
                        UserFacingClientFailure.supportReport,
                      );
                    });
                  }
                }
              }

              return AlertDialog(
                title: const Text('Report an issue'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.privacy_tip_outlined),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Your description is readable by RonikCloud '
                                'support. Before it leaves this device, common '
                                'emails, paths, filenames, tokens, and secret-like '
                                'values are removed. No file, key, log, or automatic '
                                'diagnostic is attached.',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: titleController,
                        enabled: !submitting,
                        maxLength: 160,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Short title (optional)',
                          hintText: 'Example: Upload gets stuck',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: descriptionController,
                        enabled: !submitting,
                        minLines: 4,
                        maxLines: 6,
                        maxLength: 4000,
                        decoration: const InputDecoration(
                          labelText: 'What happened?',
                          alignLabelWithHint: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: stepsController,
                        enabled: !submitting,
                        minLines: 3,
                        maxLines: 5,
                        maxLength: 4000,
                        decoration: const InputDecoration(
                          labelText: 'Steps to reproduce',
                          alignLabelWithHint: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                      if (validationMessage != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          validationMessage!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: submitting
                        ? null
                        : () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton.icon(
                    onPressed: submitting ? null : submit,
                    icon: submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_outlined),
                    label: Text(submitting ? 'Reviewing / sending' : 'Review report'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      titleController.dispose();
      descriptionController.dispose();
      stepsController.dispose();
    }
  }

  Future<void> _showSupportReportReceipt(SupportReportReceipt receipt) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Private support report sent'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your account email and raw account ID were not copied into the '
              'report. Keep this reference if you contact support about it:',
            ),
            const SizedBox(height: 12),
            SelectableText(
              receipt.supportCode,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'The privacy-minimized report is retained for at most '
              '${receipt.retentionDays} days.',
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: receipt.supportCode));
              if (dialogContext.mounted) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('Support reference copied.')),
                );
              }
            },
            icon: const Icon(Icons.copy_outlined),
            label: const Text('Copy reference'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  String get _feedbackAccountScope =>
      '${widget.auth.app.options.projectId}:${widget.user.uid}';

  Future<void> _showProductFeedback() async {
    final sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ProductFeedbackPage(
          onSubmit: (description) async {
            await _secureDriveService.submitSupportReport(
              category: SupportReportCategory.productFeedback,
              title: 'Product feedback',
              description: description,
              stepsToReproduce: '',
              platform: kIsWeb ? 'web' : defaultTargetPlatform.name,
              buildMode: kReleaseMode
                  ? 'release'
                  : (kProfileMode ? 'profile' : 'debug'),
            );
          },
        ),
      ),
    );
    if (sent != true || !mounted) return;
    setState(() => _feedbackSubmitted = true);
    _showMessage(
      'Thanks for helping improve RonikCloud. Your feedback has been sent.',
    );
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      await FeedbackPromptPreferences(
        _feedbackAccountScope,
      ).postpone(prefs, DateTime.now());
    } catch (_) {
      // A local preference failure must not turn an accepted submission into an error.
    }
  }

  Future<void> _showSettingsSheet() async {
    final maximumSheetHeight = MediaQuery.sizeOf(context).height * 0.9;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(maxHeight: maximumSheetHeight, maxWidth: 720),
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final storageVisible =
                _storageLocation != _StorageCapacityLocation.hidden;
            final storageSubtitle = switch (_storageLocation) {
              _StorageCapacityLocation.summaryCard =>
                'Visible as a compact dashboard card.',
              _StorageCapacityLocation.header =>
                'Visible as a subtle line under the header.',
              _StorageCapacityLocation.hidden => 'Hidden from the workspace.',
            };
            return SafeArea(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 12),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 12, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Workspace settings',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close settings',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  ExpansionTile(
                    leading: const Icon(Icons.storage_outlined),
                    title: const Text('Storage'),
                    subtitle: Text(storageSubtitle),
                    children: [
                      SwitchListTile(
                        secondary: const Icon(Icons.visibility_outlined),
                        value: storageVisible,
                        title: const Text('Show storage summary'),
                        subtitle: const Text(
                          'Turn this off to hide storage usage from the workspace.',
                        ),
                        onChanged: (value) {
                          final nextLocation = value
                              ? (_storageLocation ==
                                        _StorageCapacityLocation.hidden
                                    ? _StorageCapacityLocation.header
                                    : _storageLocation)
                              : _StorageCapacityLocation.hidden;
                          final changed = _updateStorageLocation(nextLocation);
                          if (changed) {
                            setModalState(() {});
                            _showMessage(
                              value
                                  ? 'Storage summary is visible in the workspace.'
                                  : 'Storage summary hidden from the workspace.',
                            );
                          }
                        },
                      ),
                      if (storageVisible) ...[
                        ListTile(
                          leading: const Icon(Icons.space_dashboard_outlined),
                          title: const Text('Placement'),
                          subtitle: const Text(
                            'Choose where the storage summary appears.',
                          ),
                        ),
                        _RadioOptionTile<_StorageCapacityLocation>(
                          value: _StorageCapacityLocation.header,
                          groupValue: _storageLocation,
                          title: const Text('Keep it subtle in the header'),
                          onSelected: (value) {
                            final changed = _updateStorageLocation(value);
                            if (changed) {
                              setModalState(() {});
                              _showMessage(
                                'Storage summary moved to a subtle header row.',
                              );
                            }
                          },
                        ),
                        _RadioOptionTile<_StorageCapacityLocation>(
                          value: _StorageCapacityLocation.summaryCard,
                          groupValue: _storageLocation,
                          title: const Text('Show compact dashboard card'),
                          onSelected: (value) {
                            final changed = _updateStorageLocation(value);
                            if (changed) {
                              setModalState(() {});
                              _showMessage(
                                'Storage summary moved to a compact dashboard card.',
                              );
                            }
                          },
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.pie_chart_outline),
                          title: const Text('Display style'),
                          subtitle: const Text(
                            'Choose how storage is described when shown.',
                          ),
                        ),
                        _RadioOptionTile<_StorageDisplayMode>(
                          value: _StorageDisplayMode.percentage,
                          groupValue: _storageDisplay,
                          title: const Text('Show percentage used'),
                          onSelected: (value) {
                            final changed = _changeStorageDisplay(
                              value,
                              showFeedback: true,
                            );
                            if (changed) {
                              setModalState(() {});
                            }
                          },
                        ),
                        _RadioOptionTile<_StorageDisplayMode>(
                          value: _StorageDisplayMode.amount,
                          groupValue: _storageDisplay,
                          title: const Text('Show used and total capacity'),
                          onSelected: (value) {
                            final changed = _changeStorageDisplay(
                              value,
                              showFeedback: true,
                            );
                            if (changed) {
                              setModalState(() {});
                            }
                          },
                        ),
                      ],
                    ],
                  ),
                  ExpansionTile(
                    leading: const Icon(Icons.dashboard_customize_outlined),
                    title: const Text('Workspace layout'),
                    subtitle: Text(
                      'Tiles are ${_tileDensity.label.toLowerCase()}, folders ${_folderPlacement.label.toLowerCase()}.',
                    ),
                    children: [
                      const ListTile(
                        leading: Icon(Icons.view_module_outlined),
                        title: Text('Tile size'),
                      ),
                      for (final density in _WorkspaceTileDensity.values)
                        _RadioOptionTile<_WorkspaceTileDensity>(
                          value: density,
                          groupValue: _tileDensity,
                          title: Text(density.label),
                          onSelected: (value) {
                            _updateTileDensity(value);
                            setModalState(() {});
                          },
                        ),
                      const Divider(height: 1),
                      const ListTile(
                        leading: Icon(Icons.account_tree_outlined),
                        title: Text('Folder position'),
                      ),
                      for (final placement in _WorkspaceFolderPlacement.values)
                        _RadioOptionTile<_WorkspaceFolderPlacement>(
                          value: placement,
                          groupValue: _folderPlacement,
                          title: Text(placement.label),
                          subtitle: Text(placement.description),
                          onSelected: (value) {
                            _updateFolderPlacement(value);
                            setModalState(() {});
                          },
                        ),
                    ],
                  ),
                  ExpansionTile(
                    leading: const Icon(Icons.sync_outlined),
                    title: const Text('Backup sync'),
                    subtitle: Text(
                      !_supportsBackgroundBackupSources
                          ? 'Automatic folder backup is unavailable on this platform.'
                          : _backgroundBackupEnabled
                          ? 'Frequency: ${_backupScanFrequency.title}.'
                          : 'Background backup sync is off.',
                    ),
                    children: [
                      SwitchListTile(
                        secondary: const Icon(Icons.sync_alt_outlined),
                        value: _supportsBackgroundBackupSources &&
                            _backgroundBackupEnabled,
                        title: const Text('Background backup sync'),
                        subtitle: Text(
                          !_supportsPersistentFolderBackups
                              ? _folderBackupUnavailableMessage
                              : 'Keep watching selected folders and upload changes automatically when this platform allows it.',
                        ),
                        onChanged: !_supportsBackgroundBackupSources
                            ? null
                            : (value) async {
                          await _setBackgroundBackupEnabled(value);
                          setModalState(() {});
                        },
                      ),
                      ListTile(
                leading: const Icon(Icons.security_outlined),
                title: const Text('Secure your account and save recovery material'),
                subtitle: const Text('Review two-factor authentication and create a recovery kit. Keep the kit yourself; support cannot unlock your files.'),
                onTap: _openActivitySecurity,
              ),
              ListTile(
                leading: const Icon(Icons.notifications_outlined),
                title: const Text('Choose your notification preferences'),
                subtitle: const Text('Optional private alerts for problems on this device. In-app updates are always available.'),
                onTap: _openActivityCenter,
              ),
              ListTile(
                leading: Icon(_transferJournal?.lastVerifiedRestoreAt != null ? Icons.check_circle_outline : Icons.restore_outlined),
                title: const Text('Verify a first restore'),
                subtitle: const Text('After uploading a file, run Verify restore access in the Data safety center. A sample check does not verify all files.'),
                onTap: _openDataSafetyCenter,
              ),
              const BackupStartupTile(),
                      const DesktopDriveSetupTile(),
                      const LocalAccessTile(),
                      for (final option in _BackupScanFrequency.values)
                        _RadioOptionTile<_BackupScanFrequency>(
                          value: option,
                          groupValue: _backupScanFrequency,
                          title: Text(option.title),
                          subtitle: Text(option.description),
                          onSelected: (value) {
                            final changed = _updateBackupScanFrequency(value);
                            if (changed) {
                              setModalState(() {});
                              _showMessage(value.feedbackMessage);
                            }
                          },
                        ),
                    ],
                  ),
                  ExpansionTile(
                    leading: Icon(
                      _passphraseRequired
                          ? Icons.lock_outline
                          : Icons.lock_open_outlined,
                    ),
                    title: const Text('Device encryption'),
                    subtitle: Text(
                      _passphraseRequired
                          ? 'Advanced secure mode is enabled.'
                          : 'Basic protection uses your current login session.',
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Basic protection encrypts files during the active login session. Advanced secure mode uses a separate passphrase on this device, encrypts secure uploads before sharding them, and cannot recover files if the passphrase is lost.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 12),
                            ToggleButtons(
                              isSelected: <bool>[
                                !_passphraseRequired,
                                _passphraseRequired,
                              ],
                              onPressed: _securityBusy
                                  ? null
                                  : (index) async {
                                      final enableSecure = index == 1;
                                      if (enableSecure == _passphraseRequired) {
                                        return;
                                      }
                                      await _toggleSecurityMode(
                                        enableSecure,
                                        onStateUpdated: () =>
                                            setModalState(() {}),
                                      );
                                      setModalState(() {});
                                    },
                              borderRadius: const BorderRadius.all(
                                Radius.circular(8),
                              ),
                              children: const [
                                Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  child: Text('Basic'),
                                ),
                                Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  child: Text('Advanced'),
                                ),
                              ],
                            ),
                            if (_securityBusy)
                              const Padding(
                                padding: EdgeInsets.only(top: 12),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (_passphraseRequired)
                        ListTile(
                          leading: const Icon(Icons.key_outlined),
                          title: const Text('Update encryption key'),
                          subtitle: _files.any((file) => file.isSecured)
                              ? const Text(
                                  'Unavailable while secure files exist.',
                                )
                              : null,
                          onTap: () {
                            Navigator.of(context).pop();
                            unawaited(_rotatePassphrase());
                          },
                        ),
                    ],
                  ),
                  ExpansionTile(
                    leading: const Icon(Icons.speed_outlined),
                    title: const Text('Upload bandwidth'),
                    subtitle: Text(
                      _uploadBandwidthLimitBytesPerSecond == null
                          ? 'Uploads use the maximum speed available.'
                          : 'Currently limited to ${_formatBandwidthLimit(_uploadBandwidthLimitBytesPerSecond!)}.',
                    ),
                    children: [
                      for (final option in _bandwidthLimitOptions)
                        _RadioOptionTile<int>(
                          value: option.value,
                          groupValue: _selectedBandwidthOptionValue,
                          title: Text(option.label),
                          subtitle: Text(option.description),
                          onSelected: (value) async {
                            await _updateBandwidthLimit(value);
                            setModalState(() {});
                          },
                        ),
                      _RadioOptionTile<int>(
                        value: _customBandwidthOptionValue,
                        groupValue: _selectedBandwidthOptionValue,
                        title: const Text('Custom'),
                        subtitle: Text(
                          _selectedBandwidthOptionValue ==
                                  _customBandwidthOptionValue
                              ? 'Current custom limit: ${_formatBandwidthLimit(_uploadBandwidthLimitBytesPerSecond!)}.'
                              : 'Choose an exact upload limit in KB/s or MB/s.',
                        ),
                        onSelected: (_) => _showCustomBandwidthLimitDialog(
                          onUpdated: () => setModalState(() {}),
                        ),
                      ),
                    ],
                  ),
                  ExpansionTile(
                    leading: const Icon(Icons.support_agent_outlined),
                    title: const Text('App and support'),
                    subtitle: const Text(
                      'Feature ideas, issue reports, downloads, and workspace tour.',
                    ),
                    children: [
                      if (widget.businessMode) ListTile(
                        leading: const Icon(Icons.support_agent_outlined),
                        title: const Text('Business support & recovery'),
                        subtitle: const Text('Support tickets, retained file recovery, and your service agreement.'),
                        onTap: () { Navigator.pop(context); unawaited(_openBusinessOperations()); },
                      ),
                      ListTile(
                        leading: const Icon(Icons.notifications_outlined),
                        title: const Text('Activity and notifications'),
                        subtitle: const Text('Review problems, recent updates and notification preferences.'),
                        onTap: () { Navigator.pop(context); unawaited(_openActivityCenter()); },
                      ),
                      ListTile(
                        leading: const Icon(Icons.health_and_safety_outlined),
                        title: const Text('Data safety center'),
                        subtitle: const Text(
                          'Recovery, file requests, sync conflicts, and share policies.',
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          unawaited(_openDataSafetyCenter());
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.menu_book_outlined),
                        title: const Text('Documentation'),
                        subtitle: const Text(
                          'Getting started, encryption, sync, sharing, and platform guides.',
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => const UserDocumentationPage(),
                            ),
                          );
                        },
                      ),
                      ListTile(
                        leading: const Icon(
                          Icons.download_for_offline_outlined,
                        ),
                        title: const Text('Download App'),
                        subtitle: const Text('Get the desktop or mobile app.'),
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const DownloadPage(),
                            ),
                          );
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.feedback_outlined),
                        title: const Text('Share feedback'),
                        subtitle: const Text(
                          'Feature ideas and what bothers you most. Open to everyone.',
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          unawaited(_showProductFeedback());
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.bug_report_outlined),
                        title: const Text('Report an issue'),
                        subtitle: Text(
                          canSubmitIssueReport(_supportProfile)
                              ? 'Send a problem report directly from this workspace.'
                              : 'Available with an active paid plan.',
                        ),
                        enabled: canSubmitIssueReport(_supportProfile),
                        onTap: () {
                          Navigator.pop(context);
                          unawaited(_showBugReportDialog());
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.school_outlined),
                        title: const Text('Workspace tour'),
                        subtitle: const Text(
                          'Replay the quick walkthrough for the main workspace.',
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          unawaited(
                            _maybeShowWorkspaceWalkthrough(force: true),
                          );
                        },
                      ),
                    ],
                  ),
                  ExpansionTile(
                    leading: const Icon(Icons.manage_accounts_outlined),
                    title: const Text('Account'),
                    subtitle: const Text(
                      'Security, privacy, and account deletion.',
                    ),
                    children: [
                      ListTile(
                        leading: const Icon(Icons.security),
                        title: const Text('Account Security'),
                        subtitle: const Text(
                          'Two-factor authentication and other security settings.',
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => _activitySecurityPage(),
                            ),
                          );
                        },
                      ),
                      if (kIsWeb)
                        ListTile(
                          leading: const Icon(Icons.cookie_outlined),
                          title: const Text('Privacy & cookies'),
                          subtitle: const Text('Change optional analytics preferences.'),
                          onTap: () {
                            Navigator.pop(context);
                            if (!openPrivacyPreferences()) {
                              _showMessage('Cookie preferences are unavailable. Refresh the page and try again.');
                            }
                          },
                        ),
                      ExpansionTile(
                        leading: const Icon(Icons.policy_outlined),
                        title: const Text('Legal documents'),
                        subtitle: const Text(
                          'Terms, privacy, billing, retention, and subprocessors.',
                        ),
                        children: LegalDocuments.all
                            .map(
                              (document) => ListTile(
                                leading: Icon(document.icon),
                                title: Text(document.title),
                                onTap: () {
                                  Navigator.pop(context);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          LegalDocumentPage(document: document),
                                    ),
                                  );
                                },
                              ),
                            )
                            .toList(growable: false),
                      ),
                      SwitchListTile(
                        secondary: const Icon(Icons.campaign_outlined),
                        value: _productUpdatesOptIn,
                        title: const Text('Product updates'),
                        subtitle: const Text(
                          'Receive release notes, product news, and service updates.',
                        ),
                        onChanged: (value) async {
                          await _updateProductUpdatesOptIn(value);
                          setModalState(() {});
                        },
                      ),
                      ListTile(
                        leading: Icon(
                          Icons.delete_forever_outlined,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        title: Text(
                          selfServiceAccountDeletionEnabled
                              ? 'Delete account'
                              : 'Request account closure',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                        subtitle: Text(
                          selfServiceAccountDeletionEnabled
                              ? 'Permanently delete your personal account and files; limited provider, legal, security, and organization records may remain.'
                              : 'Submit a verified support request. Sign-in, access, data, and billing remain active until support confirms and performs closure.',
                        ),
                        onTap: () {
                          Navigator.of(context).pop();
                          _deleteAccount();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _deleteAccount() async {
    await _confirmAccountDeletion();
  }

  Future<void> _handlePassphraseToggle(bool value) async {
    if (value) {
      final passphrase = await _collectEncryptionKey(
        isRotation: false,
        forcePrompt: true,
      );
      if (!mounted || passphrase == null) {
        return;
      }

      ({Uint8List salt, SecretKey key}) persisted;
      try {
        persisted = await _persistRemoteSecurePassphrase(passphrase);
      } on EncryptionPasswordException catch (error) {
        if (kDebugMode) {
          debugPrint('Secure-mode setup failed safely.');
        }
        if (mounted) {
          _showMessage(error.message);
        }
        return;
      } catch (_) {
        if (kDebugMode) {
          debugPrint(
            'Secure-mode setup stopped at a protected failure boundary.',
          );
        }
        if (mounted) {
          _showMessage('We could not enable secure mode. Please try again.');
        }
        return;
      }

      final keyBytes = await persisted.key.extractBytes();
      final keyString = base64Encode(keyBytes);

      if (!mounted) {
        return;
      }

      setState(() {
        _passphraseRequired = true;
        _secureSessionPassphrase = passphrase;
        _secureEncryptionSalt = persisted.salt;
        _encryptionPasswordHash = null;
        _cachedSecureEncryptionKey = keyString;
      });
      await _persistPassphraseSetting();
      _showMessage('Secure storage enabled.');
      return;
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _passphraseRequired = false;
      _secureSessionPassphrase = null;
      _activeMemoryPreview?.cancel();
      _cachedSecureEncryptionKey = null;
    });
    await _persistPassphraseSetting();
    _showMessage('Secure storage disabled.');
  }

  Future<void> _rotatePassphrase() async {
    if (_files.any((file) => file.isSecured && !file.isFolder)) {
      _showMessage('Secure key updates are disabled while secure files exist.');
      return;
    }

    final passphrase = await _collectEncryptionKey(
      isRotation: true,
      forcePrompt: true,
    );
    if (!mounted || passphrase == null) {
      return;
    }
    ({Uint8List salt, SecretKey key}) persisted;
    try {
      persisted = await _persistRemoteSecurePassphrase(
        passphrase,
        rotate: true,
      );
    } on EncryptionPasswordException catch (error) {
      if (kDebugMode) {
        debugPrint('Secure-mode rotation failed safely.');
      }
      if (mounted) {
        _showMessage(error.message);
      }
      return;
    } catch (_) {
      if (kDebugMode) {
        debugPrint(
          'Secure-mode rotation stopped at a protected failure boundary.',
        );
      }
      if (mounted) {
        _showMessage('We could not update secure mode. Please try again.');
      }
      return;
    }

    final keyBytes = await persisted.key.extractBytes();
    final keyString = base64Encode(keyBytes);

    if (!mounted) {
      return;
    }

    setState(() {
      _passphraseRequired = true;
      _secureSessionPassphrase = passphrase;
      _secureEncryptionSalt = persisted.salt;
      _encryptionPasswordHash = null;
      _cachedSecureEncryptionKey = keyString;
    });
    await _persistPassphraseSetting();
    _showMessage('Secure storage passphrase updated.');
  }

  Future<String?> _collectEncryptionKey({
    required bool isRotation,
    required bool forcePrompt,
    String? title,
    String? description,
    String? submitLabel,
  }) async {
    return showDialog<String>(
      context: context,
      barrierDismissible: !forcePrompt,
      builder: (context) => _EncryptionPassphraseDialog(
        isRotation: isRotation,
        forcePrompt: forcePrompt,
        title: title,
        description: description,
        submitLabel: submitLabel,
      ),
    );
  }

  Future<String?> _collectStandardEncryptionPassword() async {
    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (context) => const StandardEncryptionUnlockDialog(),
    );
  }

  Future<String?> _collectAccountClosurePassword() async {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const StandardEncryptionUnlockDialog(
        title: 'Confirm account closure request',
        description:
            'Enter the password for the current RonikCloud account. This refreshes your sign-in verification before a closure request can be recorded.',
        submitLabel: 'Confirm identity',
        notice:
            'Your password is sent only to Firebase Authentication for reauthentication. It is not included in the closure request or sent to support.',
        showRecoveryGuidance: false,
      ),
    );
  }

  void _beginTransfer(String id, String label) {
    _transferController.begin(id, label);
  }

  void _updateTransfer(String id, String label) {
    _transferController.update(id, label);
  }

  void _startForegroundUploadProgress({
    required String transferId,
    required int totalFiles,
    required int totalBytes,
  }) {
    _transferController.startForegroundUpload(
      id: transferId,
      totalFiles: totalFiles,
      totalBytes: totalBytes,
    );
  }

  void _updateForegroundUploadProgress({
    int? completedFiles,
    int? transferredBytes,
  }) {
    _transferController.updateForegroundProgress(
      completedFiles: completedFiles,
      transferredBytes: transferredBytes,
    );
  }

  void _clearForegroundUploadProgress() {
    _transferController.finishForegroundUpload();
  }

  void _endTransfer(String id) {
    _transferController.end(id);
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  bool _ensureWorkspaceMutationReady() {
    if (!_canWriteActiveStorage) {
      _showMessage(
        'Your current Business permissions do not allow changes in this '
        'space. Refresh company access if an administrator changed them.',
      );
      return false;
    }
    final failure = _workspaceMutationFailure;
    if (!_refreshingWorkspaceMutationState &&
        (failure == null || !failure.requiresAuthoritativeRefresh)) {
      return true;
    }
    _showMessage(
      _refreshingWorkspaceMutationState
          ? 'Wait for the file refresh to finish before making another change.'
          : failure!.message,
    );
    return false;
  }

  void _handleWorkspaceMutationFailure(
    WorkspaceMutationAction action,
    Object error,
  ) {
    final failure = classifyWorkspaceMutationFailure(
      action: action,
      cloudCode: error is FirebaseException ? error.code : null,
    );
    if (kDebugMode) {
      debugPrint(
        'Workspace mutation failed '
        '(action=${failure.safeLogCategory}, '
        'outcome=${failure.outcome.name}).',
      );
    }
    _logRuntime(
      'workspace',
      'Workspace mutation failed with a closed recovery category.',
    );
    if (mounted && failure.requiresAuthoritativeRefresh) {
      setState(() {
        _workspaceMutationFailure = failure;
      });
    }
    _showMessage(failure.message);
  }

  Future<void> _refreshWorkspaceMutationState() async {
    if (_refreshingWorkspaceMutationState || !mounted) {
      return;
    }
    setState(() {
      _refreshingWorkspaceMutationState = true;
    });

    try {
      final ownedFiles = await widget.firestore
          .collection('files')
          .where('uid', isEqualTo: widget.user.uid)
          .get(const GetOptions(source: Source.server));
      final ownedFolders = await widget.firestore
          .collection('folders')
          .where('uid', isEqualTo: widget.user.uid)
          .get(const GetOptions(source: Source.server));

      var assignedFileDocuments =
          const <DocumentSnapshot<Map<String, dynamic>>>[];
      var assignedFolderDocuments =
          const <DocumentSnapshot<Map<String, dynamic>>>[];

      if (_canReadCompanyStorage) {
        final assignedFiles = await widget.firestore
            .collection('files')
            .where('allowedUids', arrayContains: widget.user.uid)
            .get(const GetOptions(source: Source.server));
        final assignedFolders = await widget.firestore
            .collection('folders')
            .where('allowedUids', arrayContains: widget.user.uid)
            .get(const GetOptions(source: Source.server));
        assignedFileDocuments = assignedFiles.docs;
        assignedFolderDocuments = assignedFolders.docs;
      }

      await _runOnPlatformThread(() async {
        await _applyAuthoritativeWorkspaceDocuments(
          personalFileDocuments: ownedFiles.docs,
          assignedFileDocuments: assignedFileDocuments,
          personalFolderDocuments: ownedFolders.docs,
          assignedFolderDocuments: assignedFolderDocuments,
        );
      });
      if (!mounted) {
        return;
      }
      setState(() {
        _workspaceMutationFailure = null;
      });
      _showMessage('Files and folders refreshed from the service.');
      _logRuntime('workspace', 'Authoritative workspace refresh completed.');
    } catch (_) {
      if (kDebugMode) {
        debugPrint('Authoritative workspace refresh was unavailable.');
      }
      _showMessage(
        'Files could not be refreshed. The last verified workspace remains '
        'visible; check your connection and try Refresh files again.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _refreshingWorkspaceMutationState = false;
        });
      } else {
        _refreshingWorkspaceMutationState = false;
      }
    }
  }

  Future<void> _applyAuthoritativeWorkspaceDocuments({
    required Iterable<DocumentSnapshot<Map<String, dynamic>>>
    personalFileDocuments,
    required Iterable<DocumentSnapshot<Map<String, dynamic>>>
    assignedFileDocuments,
    required Iterable<DocumentSnapshot<Map<String, dynamic>>>
    personalFolderDocuments,
    required Iterable<DocumentSnapshot<Map<String, dynamic>>>
    assignedFolderDocuments,
  }) async {
    List<_DriveFile> parseFiles(
      Iterable<DocumentSnapshot<Map<String, dynamic>>> documents,
    ) {
      final parsed = <_DriveFile>[];
      for (final document in documents) {
        final file = _tryParseDriveFile(document);
        if (file != null) {
          parsed.add(file);
        }
      }
      return parsed;
    }

    final personalFiles = parseFiles(personalFileDocuments);
    final assignedFiles = parseFiles(assignedFileDocuments);
    final visibleFiles = <_DriveFile>[
      ...personalFiles.where((file) => file.isActive),
      ...assignedFiles.where((file) => file.isActive),
    ];
    final resolvedVisibleFiles = visibleFiles.any(_fileNeedsLocalNameDecryption)
        ? await _maybeDecryptFileNames(visibleFiles)
        : visibleFiles;
    final resolvedFilesById = <String, _DriveFile>{
      for (final file in resolvedVisibleFiles) file.id: file,
    };
    _fileSnapshotSources.replace(
      WorkspaceSnapshotSource.personal,
      personalFiles.map((file) => resolvedFilesById[file.id] ?? file),
      idOf: (file) => file.id,
    );
    _fileSnapshotSources.replace(
      WorkspaceSnapshotSource.assignedBusiness,
      assignedFiles.map((file) => resolvedFilesById[file.id] ?? file),
      idOf: (file) => file.id,
    );
    _initializedFileSnapshotSources
      ..clear()
      ..add(WorkspaceSnapshotSource.personal);
    if (_canReadCompanyStorage) {
      _initializedFileSnapshotSources.add(
        WorkspaceSnapshotSource.assignedBusiness,
      );
    }
    final retainedFiles = _fileSnapshotSources.mergedItems;
    final retainedUsageBytes = retainedFiles.fold<int>(
      0,
      (total, file) => total + file.size,
    );
    final resolvedFiles =
        retainedFiles.where((file) => file.isActive).toList(growable: true)
          ..sort(_compareDriveFiles);
    final filesById = <String, _DriveFile>{
      for (final file in resolvedFiles) file.id: file,
    };

    List<_DriveFolder> parseFolders(
      Iterable<DocumentSnapshot<Map<String, dynamic>>> documents,
    ) {
      final parsed = <_DriveFolder>[];
      for (final document in documents) {
        final folder = _tryParseDriveFolder(document);
        if (folder != null) {
          parsed.add(folder);
        }
      }
      return parsed;
    }

    final personalFolders = parseFolders(personalFolderDocuments);
    final assignedFolders = parseFolders(assignedFolderDocuments);
    final parsedFolders = <_DriveFolder>[
      ...personalFolders,
      ...assignedFolders,
    ];
    final resolvedFolders = parsedFolders.any(_folderNeedsLocalNameDecryption)
        ? await _maybeDecryptFolderNames(parsedFolders)
        : parsedFolders;
    final resolvedFoldersById = <String, _DriveFolder>{
      for (final folder in resolvedFolders) folder.id: folder,
    };
    _folderSnapshotSources.replace(
      WorkspaceSnapshotSource.personal,
      personalFolders.map((folder) => resolvedFoldersById[folder.id] ?? folder),
      idOf: (folder) => folder.id,
    );
    _folderSnapshotSources.replace(
      WorkspaceSnapshotSource.assignedBusiness,
      assignedFolders.map((folder) => resolvedFoldersById[folder.id] ?? folder),
      idOf: (folder) => folder.id,
    );
    final mergedFolders = _folderSnapshotSources.mergedItems.toList()
      ..sort((a, b) {
        final aActivity = a.activity ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bActivity = b.activity ?? DateTime.fromMillisecondsSinceEpoch(0);
        final activityComparison = bActivity.compareTo(aActivity);
        return activityComparison != 0
            ? activityComparison
            : a.displayName.toLowerCase().compareTo(
                b.displayName.toLowerCase(),
              );
      });
    final folderIds = mergedFolders.map((folder) => folder.id).toSet();

    if (!mounted) {
      return;
    }
    final computedUsage = retainedUsageBytes.toDouble();
    final totals = _calculateUsageTotals(computedUsage: computedUsage);
    final activeFolderMissing =
        _normalizeFolderId(_activeFolderId) != null &&
        !folderIds.contains(_normalizeFolderId(_activeFolderId));
    setState(() {
      _files
        ..clear()
        ..addAll(resolvedFiles);
      _filesById
        ..clear()
        ..addAll(filesById);
      _folders
        ..clear()
        ..addAll(mergedFolders);
      _fileUsageBytes = computedUsage;
      _usedBytes = totals.used;
      _totalBytes = totals.total;
      _loadingFiles = false;
      _loadingFolders = false;
      _hasLoadedFileSnapshot = true;
      _hasLoadedFolderSnapshot = true;
      _knownBackupFolderIds
        ..clear()
        ..addAll(folderIds);
      if (activeFolderMissing) {
        _activeFolderId = null;
        _activeFolderLabel = null;
      }
    });
    _resolvedFileNameCache.removeWhere((id, _) => !filesById.containsKey(id));
    _resolvedFolderNameCache.removeWhere((id, _) => !folderIds.contains(id));
    _normalizeWorkspaceSelection(folders: mergedFolders);
    _scheduleCachedFilesPersist();
    _scheduleCachedFoldersPersist();
    _scheduleOfflineSync();
    _maybePromptForSecureRefresh();
  }

  String _uploadFailureReason(Object error) {
    if (error is UploadFailure) {
      return switch (error.code) {
        'source_changed' => 'The source changed. Select the same unchanged file, or start a new upload.',
        'expired' => 'This upload session expired. Start the upload again.',
        'canceled' => 'Upload canceled.',
        'unauthorized' => 'Sign in again to continue uploading.',
        _ => 'The upload was interrupted. Review saved progress before retrying.',
      };
    }
    if (error is UploadMetadataException) {
      return userFacingCloudErrorMessage(
        operation: UserFacingCloudOperation.uploadMetadata,
      );
    }
    if (error is WasabiConfigurationException) {
      return userFacingCloudErrorMessage(
        operation: UserFacingCloudOperation.storageTransfer,
      );
    }
    if (error is WasabiStorageException) {
      return userFacingCloudErrorMessage(
        operation: UserFacingCloudOperation.storageTransfer,
      );
    }
    if (error is EncryptionPasswordException) {
      return userFacingClientFailureMessage(
        UserFacingClientFailure.uploadProtection,
      );
    }
    if (error is FirebaseAuthException) {
      return userFacingCloudErrorMessage(
        operation: UserFacingCloudOperation.storageTransfer,
        code: error.code,
      );
    }
    if (error is FirebaseException) {
      return userFacingCloudErrorMessage(
        operation: UserFacingCloudOperation.storageTransfer,
        code: error.code,
      );
    }
    return userFacingCloudErrorMessage(
      operation: UserFacingCloudOperation.storageTransfer,
    );
  }

  void _setBackupProgress(String localPath, _BackupProgressStatus? status) {
    if (!mounted) {
      if (status == null) {
        _backupProgress.remove(localPath);
      } else {
        _backupProgress[localPath] = status;
      }
      return;
    }

    setState(() {
      if (status == null) {
        _backupProgress.remove(localPath);
      } else {
        _backupProgress[localPath] = status;
      }
    });
  }

  void _updateBackupProgress(
    String localPath,
    _BackupProgressStatus Function(_BackupProgressStatus?) transform,
  ) {
    final next = transform(_backupProgress[localPath]);
    _setBackupProgress(localPath, next);
  }

  void _updateBackupScanTimerState({bool forceRestart = false}) {
    if (kIsWeb) {
      return;
    }

    final shouldRun =
        _backgroundBackupEnabled &&
        _backupFolders.values.any(
          (config) => config.enabled && _canRunBackupConfig(config),
        );
    if (!shouldRun) {
      _backupScanTimer?.cancel();
      _backupScanTimer = null;
      _activeBackupScanInterval = null;
      return;
    }

    final interval = _backupScanFrequency.interval;
    final needsRestart =
        forceRestart ||
        _backupScanTimer == null ||
        _activeBackupScanInterval != interval;

    if (!needsRestart) {
      return;
    }

    _backupScanTimer?.cancel();
    _backupScanTimer = Timer.periodic(interval, (_) {
      if (!mounted) {
        _backupScanTimer?.cancel();
        _backupScanTimer = null;
        _activeBackupScanInterval = null;
        return;
      }
      _runScheduledBackupScans();
    });
    _activeBackupScanInterval = interval;

    if (mounted) {
      _runScheduledBackupScans();
    }
  }

  void _runScheduledBackupScans() {
    if (kIsWeb || !_backgroundBackupEnabled) {
      return;
    }

    final now = DateTime.now();
    for (final config in _backupFolders.values) {
      if (!config.enabled || !_canRunBackupConfig(config)) {
        continue;
      }
      final normalizedConfigPath = _normalizedLocalPath(config.localPath);
      if (_backupProgress.containsKey(config.localPath) ||
          _activeBackupWatchConfigs.contains(normalizedConfigPath) ||
          _fullBackupInFlightConfigs.contains(normalizedConfigPath)) {
        continue;
      }
      final lastSynced = config.lastSynced;
      if (lastSynced == null ||
          lastSynced.isAfter(now) ||
          now.difference(lastSynced) >= _backupResyncInterval) {
        unawaited(_runBackupNow(config, quiet: true));
      }
    }
  }

  String _sanitizeFileName(String value) {
    final sanitized = value.replaceAll(_invalidFileNamePattern, '_');
    return sanitized.trim();
  }

  String _sanitizePathSegment(String segment) {
    return sanitizeWorkspacePathSegment(segment);
  }

  List<String> _normalizeRemoteFolderSegments(String folderName) {
    return folderName
        .split(RegExp(r'[\\/]+'))
        .map((segment) => _sanitizePathSegment(segment))
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
  }

  String _normalizedLocalPath(String path) {
    final normalized = p.normalize(path);
    if (Platform.isWindows) {
      return normalized.toLowerCase();
    }
    return normalized;
  }

  Map<String, _BackupFileFingerprint>? _fingerprintBucket(
    String localPath, {
    bool create = false,
  }) {
    final normalized = _normalizedLocalPath(localPath);
    if (normalized.isEmpty && !create) {
      return null;
    }
    if (normalized.isEmpty) {
      return _backupFingerprints.putIfAbsent(
        _backupFingerprintOrphanBucket,
        () => <String, _BackupFileFingerprint>{},
      );
    }
    if (create) {
      return _backupFingerprints.putIfAbsent(
        normalized,
        () => <String, _BackupFileFingerprint>{},
      );
    }
    return _backupFingerprints[normalized];
  }

  bool _removeFingerprintForConfig(
    String localPath,
    String normalizedFilePath,
  ) {
    final normalized = _normalizedLocalPath(localPath);
    Map<String, _BackupFileFingerprint>? bucket;
    if (normalized.isEmpty) {
      bucket = _backupFingerprints[_backupFingerprintOrphanBucket];
    } else {
      bucket = _backupFingerprints[normalized];
    }
    if (bucket != null) {
      final removed = bucket.remove(normalizedFilePath) != null;
      if (removed && bucket.isEmpty) {
        if (normalized.isEmpty) {
          _backupFingerprints.remove(_backupFingerprintOrphanBucket);
        } else {
          _backupFingerprints.remove(normalized);
        }
      }
      if (removed) {
        return true;
      }
    }

    if (normalized.isEmpty) {
      return false;
    }

    final orphanBucket = _backupFingerprints[_backupFingerprintOrphanBucket];
    if (orphanBucket == null) {
      return false;
    }
    final orphanRemoved = orphanBucket.remove(normalizedFilePath) != null;
    if (orphanRemoved && orphanBucket.isEmpty) {
      _backupFingerprints.remove(_backupFingerprintOrphanBucket);
    }
    return orphanRemoved;
  }

  Future<String> _deriveBackupFolderId(
    _BackupFolderConfig config, {
    required SecretKey key,
  }) async {
    final normalizedName = _normalizeBackupRelativePath(config.remoteFolder);
    if (normalizedName.isEmpty) {
      throw const WorkspaceMetadataEncryptionException(
        'A backup folder name is required.',
      );
    }
    final folderId = await _metadataEncryptionService.deterministicFolderId(
      namespace: 'backup-root',
      storageSpaceId: 'personal',
      parentId: null,
      normalizedName: normalizedName,
      key: key,
    );
    _backupFolderIdsByLocalPath[_normalizedLocalPath(config.localPath)] =
        folderId;
    return folderId;
  }

  String _backupFolderIdForDisplay(_BackupFolderConfig config) {
    final normalizedLocalPath = _normalizedLocalPath(config.localPath);
    final resolved = _backupFolderIdsByLocalPath[normalizedLocalPath];
    if (resolved != null && resolved.isNotEmpty) {
      return resolved;
    }
    final localOnlyToken = sha256
        .convert(
          utf8.encode(
            '$normalizedLocalPath\n${config.remoteFolder.trim().toLowerCase()}',
          ),
        )
        .toString()
        .substring(0, 24);
    return 'local-backup-$localOnlyToken';
  }

  String _folderPathCacheKey(String? parentId, String name) {
    final spaceKey = _activeStorageSpace.id;
    final parentKey = _normalizeFolderId(parentId) ?? 'root';
    return '$spaceKey/$parentKey/${name.trim().toLowerCase()}';
  }

  _DriveFolder? _findChildFolder(String? parentId, String name) {
    final normalizedParentId = _normalizeFolderId(parentId);
    final normalizedName = name.trim().toLowerCase();
    for (final folder in _folders) {
      if (!_folderMatchesActiveStorageSpace(folder)) {
        continue;
      }
      if (_normalizeFolderId(folder.parentId) != normalizedParentId) {
        continue;
      }
      if (folder.displayName.toLowerCase() == normalizedName) {
        return folder;
      }
    }
    return null;
  }

  Future<_PreparedFolderEncryption?> _prepareFolderEncryption({
    required String folderId,
    required String name,
    required Map<String, dynamic> storageMetadata,
    required bool interactive,
  }) async {
    final accountKeyString = await _ensureEncryptionKey(
      interactive: interactive,
    );
    if (accountKeyString == null || accountKeyString.isEmpty) {
      if (interactive) {
        _showMessage(
          'Unlock encryption on this device before creating or renaming '
          'folders.',
        );
      }
      return null;
    }
    final accountProtectionKey = SecretKey(base64Decode(accountKeyString));
    final storageScope =
        (storageMetadata['storageScope'] as String?)?.trim() ?? 'personal';
    if (storageScope != 'company_shared' && storageScope != 'group') {
      final encryptedName = await _metadataEncryptionService.encryptLabel(
        label: name,
        key: accountProtectionKey,
      );
      return _PreparedFolderEncryption(
        encryptedName: encryptedName,
        metadataEncryption:
            WorkspaceMetadataEncryptionService.standardMetadataMode,
      );
    }

    try {
      final identity = await _ensureBusinessEncryptionIdentity(
        accountProtectionKey: accountProtectionKey,
      );
      final groupIds =
          (storageMetadata['groupIds'] as Iterable?)
              ?.whereType<String>()
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toList(growable: false) ??
          const <String>[];
      final groupId = storageScope == 'group'
          ? (groupIds.isNotEmpty ? groupIds.first : _activeStorageGroupId)
          : null;
      final recipients = await _businessEncryptionRegistry.listRecipients(
        storageScope: storageScope,
        groupId: groupId,
      );
      final currentRecipient = recipients.recipients
          .cast<BusinessEncryptionRecipient?>()
          .firstWhere(
            (recipient) => recipient?.uid == widget.user.uid,
            orElse: () => null,
          );
      if (!recipients.isComplete ||
          currentRecipient == null ||
          currentRecipient.keyId != identity.keyId) {
        if (interactive) {
          final missingCount = recipients.missingUids.length;
          _showMessage(
            missingCount == 0
                ? 'Business encryption is still synchronizing. Try again.'
                : '$missingCount authorized member'
                      '${missingCount == 1 ? "" : "s"} must open the '
                      'Business workspace before this folder can be saved.',
          );
        }
        return null;
      }
      final material = await _businessEncryptionService
          .createFileEncryptionMaterial(
            objectKey: _metadataEncryptionService.folderEncryptionContext(
              folderId,
            ),
            recipients: recipients.recipients,
          );
      final encryptedName = await _metadataEncryptionService.encryptLabel(
        label: name,
        key: material.fileKey,
      );
      return _PreparedFolderEncryption(
        encryptedName: encryptedName,
        metadataEncryption:
            WorkspaceMetadataEncryptionService.businessMetadataMode,
        businessEnvelopes: material.envelopes,
      );
    } on BusinessEncryptionRegistryException catch (error) {
      if (interactive) {
        _showMessage(error.message);
      }
      return null;
    } on BusinessEncryptionException catch (error) {
      if (interactive) {
        _showMessage(error.message);
      }
      return null;
    }
  }

  Future<bool> _saveEncryptedFolderDocument({
    required String folderId,
    required String name,
    required String color,
    required String? parentId,
    required bool systemFolder,
    String? systemKey,
    Map<String, dynamic>? storageMetadataOverride,
    bool interactive = true,
    bool touchLastFileAt = false,
  }) async {
    final storageMetadata =
        storageMetadataOverride ?? _metadataForActiveStorageSpace();
    final prepared = await _prepareFolderEncryption(
      folderId: folderId,
      name: name,
      storageMetadata: storageMetadata,
      interactive: interactive,
    );
    if (prepared == null) {
      return false;
    }
    final storageScope =
        (storageMetadata['storageScope'] as String?)?.trim() ?? 'personal';
    if (storageScope == 'company_shared' || storageScope == 'group') {
      if (systemFolder) {
        throw const WorkspaceMetadataEncryptionException(
          'Background system folders are not supported in shared Business '
          'storage.',
        );
      }
      final groupIds =
          (storageMetadata['groupIds'] as Iterable?)
              ?.whereType<String>()
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toList(growable: false) ??
          const <String>[];
      await _businessEncryptionRegistry.saveEncryptedFolder(
        folderId: folderId,
        encryptedName: prepared.encryptedName,
        storageScope: storageScope,
        color: color,
        envelopes: prepared.businessEnvelopes,
        parentId: parentId,
        groupId: storageScope == 'group'
            ? (groupIds.isNotEmpty ? groupIds.first : _activeStorageGroupId)
            : null,
      );
      return true;
    }

    final docRef = widget.firestore.collection('folders').doc(folderId);
    final payload = <String, dynamic>{
      'uid': widget.user.uid,
      'encryptedName': prepared.encryptedName,
      'metadataEncryption': prepared.metadataEncryption,
      'color': color,
      'updatedAt': FieldValue.serverTimestamp(),
      'systemFolder': systemFolder,
      ...storageMetadata,
    };
    if (parentId != null && parentId.trim().isNotEmpty) {
      payload['parentId'] = parentId.trim();
    }
    if (systemFolder) {
      payload['systemKey'] = systemKey ?? 'backup';
    }
    if (touchLastFileAt) {
      payload['lastFileAt'] = FieldValue.serverTimestamp();
    }
    await upsertEncryptedFolderDocument(docRef, payload);
    return true;
  }

  Future<String?> _ensureFolderPath({
    required String? parentId,
    required List<String> pathSegments,
    required String colorHex,
    bool systemFolder = false,
    String? systemKey,
    Map<String, String?>? createdFolderIds,
    Map<String, dynamic>? storageMetadataOverride,
    String? storageSpaceIdOverride,
  }) async {
    var currentParentId = _normalizeFolderId(parentId);
    final normalizedSegments = pathSegments
        .map(_sanitizePathSegment)
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    if (normalizedSegments.isEmpty) {
      return currentParentId;
    }
    final accountKeyString = await _ensureEncryptionKey(interactive: true);
    if (accountKeyString == null || accountKeyString.isEmpty) {
      throw const WorkspaceMetadataEncryptionException(
        'Folder metadata encryption is not unlocked on this device.',
      );
    }
    final accountKey = SecretKey(base64Decode(accountKeyString));
    final storageMetadata =
        storageMetadataOverride ?? _metadataForActiveStorageSpace();
    final storageSpaceId =
        storageSpaceIdOverride ??
        (storageMetadata['storageScope'] as String?) ??
        _activeStorageSpace.id;

    for (final segment in normalizedSegments) {
      final cacheKey = _folderPathCacheKey(currentParentId, segment);
      if (createdFolderIds != null && createdFolderIds.containsKey(cacheKey)) {
        currentParentId = createdFolderIds[cacheKey];
        continue;
      }

      final existingFolder = _findChildFolder(currentParentId, segment);
      if (existingFolder != null) {
        currentParentId = existingFolder.id;
        createdFolderIds?[cacheKey] = currentParentId;
        continue;
      }

      final folderId = await _metadataEncryptionService.deterministicFolderId(
        namespace: systemFolder ? 'system-folder' : 'folder',
        storageSpaceId: storageSpaceId,
        parentId: currentParentId,
        normalizedName: segment,
        key: accountKey,
      );
      final saved = await _saveEncryptedFolderDocument(
        folderId: folderId,
        name: segment,
        color: colorHex,
        parentId: currentParentId,
        systemFolder: systemFolder,
        systemKey: systemKey,
        storageMetadataOverride: storageMetadata,
        interactive: true,
      );
      if (!saved) {
        throw const WorkspaceMetadataEncryptionException(
          'Folder metadata could not be protected on this device.',
        );
      }
      createdFolderIds?[cacheKey] = folderId;
      if (systemFolder) {
        _knownBackupFolderIds.add(folderId);
      }
      currentParentId = folderId;
    }

    return currentParentId;
  }

  String _buildObjectKey(
    String fileName, {
    String? folderId,
    bool securedObjectKey = false,
    String? objectKeyOwnerPrefix,
  }) {
    final ownerPrefix = objectKeyOwnerPrefix ?? _objectKeyOwnerPrefix;
    final sanitizedFolder = _normalizeFolderId(folderId);
    if (securedObjectKey) {
      return BackgroundBackupRunner.opaqueObjectKey(
        ownerPrefix: ownerPrefix,
        random: _random,
      );
    }

    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    final hasFolder = sanitizedFolder != null && sanitizedFolder.isNotEmpty;
    final encodedFolder = hasFolder ? Uri.encodeComponent(sanitizedFolder) : '';
    final folderSegment = hasFolder ? 'folders/$encodedFolder/' : '';
    return '$ownerPrefix/$folderSegment${timestamp}_$fileName';
  }

  _DriveFolder? _findFolderById(String folderId) {
    for (final folder in _folders) {
      if (!_folderMatchesActiveStorageSpace(folder)) {
        continue;
      }
      if (folder.id == folderId) {
        return folder;
      }
    }
    return null;
  }

  String? _normalizedFolderNameKey(String? folderName) {
    final trimmed = folderName?.trim().toLowerCase();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  _DriveFolder? _findFolderByDisplayName(String? folderName) {
    final normalizedName = _normalizedFolderNameKey(folderName);
    if (normalizedName == null) {
      return null;
    }
    for (final folder in _folders) {
      if (!_folderMatchesActiveStorageSpace(folder)) {
        continue;
      }
      if (folder.displayName.trim().toLowerCase() == normalizedName) {
        return folder;
      }
    }
    return null;
  }

  String? _resolvedFolderIdForFile(_DriveFile file) {
    final explicitFolderId = file.folderId?.trim();
    if (explicitFolderId != null && explicitFolderId.isNotEmpty) {
      return explicitFolderId == 'root' ? null : explicitFolderId;
    }

    final objectFolderId = _normalizeFolderId(file.derivedFolderId);
    if (objectFolderId != null) {
      return objectFolderId;
    }

    return _findFolderByDisplayName(file.folderName)?.id;
  }

  String _resolvedFolderKeyForFile(_DriveFile file) {
    final resolvedFolderId = _resolvedFolderIdForFile(file);
    if (resolvedFolderId != null) {
      return resolvedFolderId;
    }

    final normalizedFolderName = _normalizedFolderNameKey(file.folderName);
    if (normalizedFolderName != null) {
      return 'name::$normalizedFolderName';
    }

    return 'root';
  }

  Set<String> _descendantFolderIds(String folderId) {
    final descendants = <String>{};
    final queue = <String>[folderId];
    while (queue.isNotEmpty) {
      final currentId = queue.removeLast();
      for (final folder in _folders) {
        if (!_folderMatchesActiveStorageSpace(folder)) {
          continue;
        }
        if (_normalizeFolderId(folder.parentId) != currentId) {
          continue;
        }
        if (descendants.add(folder.id)) {
          queue.add(folder.id);
        }
      }
    }
    return descendants;
  }

  String? _normalizeFolderId(String? folderId) {
    return normalizeWorkspaceFolderId(folderId);
  }

  List<_DriveFolder> _folderChain(String? folderId) {
    final normalizedId = _normalizeFolderId(folderId);
    if (normalizedId == null) {
      return const <_DriveFolder>[];
    }

    final chain = <_DriveFolder>[];
    final visited = <String>{};
    String? cursor = normalizedId;
    while (cursor != null && visited.add(cursor)) {
      final folder = _findFolderById(cursor);
      if (folder == null) {
        break;
      }
      chain.add(folder);
      cursor = _normalizeFolderId(folder.parentId);
    }
    return chain.reversed.toList(growable: false);
  }

  List<_WorkspacePathItem> _workspacePathItems() {
    final items = <_WorkspacePathItem>[
      _WorkspacePathItem(
        label: _activeStorageSpaceLabel,
        folderId: null,
        isRoot: true,
      ),
    ];

    final activeFolderId = _normalizeFolderId(_activeFolderId);
    if (activeFolderId == null) {
      return items;
    }

    final chain = _folderChain(activeFolderId);
    if (chain.isEmpty) {
      final fallback = _activeFolderLabel?.trim();
      if (fallback != null && fallback.isNotEmpty) {
        items.add(
          _WorkspacePathItem(label: fallback, folderId: activeFolderId),
        );
      }
      return items;
    }

    items.addAll(
      chain.map(
        (folder) =>
            _WorkspacePathItem(label: folder.displayName, folderId: folder.id),
      ),
    );
    return items;
  }

  String _workspacePathLabel() {
    return _workspacePathItems().map((item) => item.label).join(' / ');
  }

  String _workspacePathLabelForFolder(
    String? folderId, {
    String? fallbackLabel,
  }) {
    final normalizedId = _normalizeFolderId(folderId);
    if (normalizedId == null) {
      return _activeStorageSpaceLabel;
    }
    if (_activeFolderId == normalizedId) {
      return _workspacePathLabel();
    }
    final chain = _folderChain(normalizedId);
    if (chain.isNotEmpty) {
      return <String>[
        _activeStorageSpaceLabel,
        ...chain.map((folder) => folder.displayName),
      ].join(' / ');
    }
    final trimmedFallback = fallbackLabel?.trim();
    if (trimmedFallback != null && trimmedFallback.isNotEmpty) {
      return '$_activeStorageSpaceLabel / $trimmedFallback';
    }
    return _activeStorageSpaceLabel;
  }

  void _navigateToFolder(String? folderId, {String? fallbackLabel}) {
    final normalizedId = _normalizeFolderId(folderId);
    if (_activeFolderId == normalizedId &&
        (normalizedId == null || _activeFolderLabel == fallbackLabel)) {
      return;
    }
    setState(() {
      _activeFolderId = normalizedId;
      _activeFolderLabel = normalizedId == null
          ? null
          : (_findFolderById(normalizedId)?.displayName ??
                fallbackLabel?.trim() ??
                'Folder');
      _recentExpanded = false;
    });
  }

  List<_FolderListItem> _buildVisibleFolderItems({String? parentId}) {
    final normalizedParentId = _normalizeFolderId(parentId);
    final filesPerFolder = <String, int>{};
    final bytesPerFolder = <String, int>{};
    final childFoldersPerFolder = <String, int>{};
    final activeFolders = _folders
        .where(_folderMatchesActiveStorageSpace)
        .toList(growable: false);
    final activeFiles = _files
        .where(_fileMatchesActiveStorageSpace)
        .toList(growable: false);

    for (final folder in activeFolders) {
      final parentKey = _normalizeFolderId(folder.parentId);
      if (parentKey != null) {
        childFoldersPerFolder[parentKey] =
            (childFoldersPerFolder[parentKey] ?? 0) + 1;
      }
    }

    for (final file in activeFiles) {
      if (file.isFolder) {
        continue;
      }
      final key = _resolvedFolderKeyForFile(file);
      if (key == 'root') {
        continue;
      }
      filesPerFolder[key] = (filesPerFolder[key] ?? 0) + 1;
      bytesPerFolder[key] = (bytesPerFolder[key] ?? 0) + file.size;
    }

    final directFolders =
        activeFolders.where((folder) {
          return _normalizeFolderId(folder.parentId) == normalizedParentId;
        }).toList()..sort((a, b) {
          final activityA =
              a.activity ?? DateTime.fromMillisecondsSinceEpoch(0);
          final activityB =
              b.activity ?? DateTime.fromMillisecondsSinceEpoch(0);
          final activityCompare = activityB.compareTo(activityA);
          if (activityCompare != 0) {
            return activityCompare;
          }
          return a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          );
        });

    final items = <_FolderListItem>[
      for (final folder in directFolders)
        _FolderListItem(
          summary: _FolderSummary(
            id: folder.id,
            displayName: folder.displayName,
            itemCount:
                (filesPerFolder[folder.id] ?? 0) +
                (childFoldersPerFolder[folder.id] ?? 0),
            totalBytes: bytesPerFolder[folder.id] ?? 0,
            isRoot: false,
            colorHex: folder.colorHex,
            isSystem: folder.systemFolder,
          ),
          folder: folder,
        ),
    ];

    if (normalizedParentId == null) {
      final knownIds = directFolders.map((folder) => folder.id).toSet();
      final pseudoFolders = <String, _FolderAccumulator>{};
      for (final file in activeFiles) {
        if (file.isFolder) {
          continue;
        }
        final key = _resolvedFolderKeyForFile(file);
        if (key == 'root' || knownIds.contains(key)) {
          continue;
        }
        final accumulator = pseudoFolders.putIfAbsent(
          key,
          () => _FolderAccumulator(
            id: key,
            displayName: file.folderLabel,
            isRoot: false,
          ),
        );
        accumulator.itemCount += 1;
        accumulator.totalBytes += file.size;
      }

      if (_activeStorageScope == 'personal') {
        for (final config in _backupFolders.values) {
          final id = _backupFolderIdForDisplay(config);
          if (knownIds.contains(id)) {
            continue;
          }
          final friendlyName = config.remoteFolder.trim();
          final accumulator = pseudoFolders.putIfAbsent(
            id,
            () => _FolderAccumulator(
              id: id,
              displayName: friendlyName.isEmpty ? 'Backup' : friendlyName,
              isRoot: false,
              colorHex: '#E8F0FE',
              isSystem: true,
            ),
          );
          if (friendlyName.isNotEmpty) {
            accumulator.displayName = friendlyName;
          }
          accumulator.colorHex ??= '#E8F0FE';
          accumulator.isSystem = true;
        }
      }

      final sortedPseudoFolders = pseudoFolders.values.toList()
        ..sort(
          (a, b) => a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          ),
        );
      items.addAll(
        sortedPseudoFolders.map(
          (accumulator) =>
              _FolderListItem(summary: accumulator.toSummary(), folder: null),
        ),
      );
    }

    return items;
  }

  List<_DriveFile> _visibleFilesForFolder(String? folderId) {
    final normalizedFolderId = _normalizeFolderId(folderId);
    return normalizedFolderId == null
        ? _files
              .where(
                (file) =>
                    !file.isFolder && _fileMatchesActiveStorageSpace(file),
              )
              .toList(growable: false)
        : _files
              .where(
                (file) =>
                    !file.isFolder &&
                    _fileMatchesActiveStorageSpace(file) &&
                    _resolvedFolderKeyForFile(file) == normalizedFolderId,
              )
              .toList(growable: false);
  }

  List<_FolderTreeItem> _buildFolderTreeItems({String? activeFolderId}) {
    final normalizedActiveId = _normalizeFolderId(activeFolderId);
    final activeChain = _folderChain(normalizedActiveId);
    final expandedIds = <String?>{
      null,
      for (final folder in activeChain) folder.id,
    };
    final items = <_FolderTreeItem>[];
    final rootDirectFiles = _visibleFilesForFolder(null);
    final rootDirectFolders = _buildVisibleFolderItems(parentId: null);
    items.add(
      _FolderTreeItem(
        item: _FolderListItem(
          summary: _FolderSummary(
            id: 'root',
            displayName: _activeStorageSpaceLabel,
            itemCount: rootDirectFiles.length + rootDirectFolders.length,
            totalBytes: rootDirectFiles.fold<int>(
              0,
              (total, file) => total + file.size,
            ),
            isRoot: true,
          ),
        ),
        depth: 0,
        hasChildren: rootDirectFolders.isNotEmpty,
        isExpanded: expandedIds.contains(null),
        isCurrent: normalizedActiveId == null,
      ),
    );

    void addChildren(String? parentId, int depth) {
      final children = _buildVisibleFolderItems(parentId: parentId);
      for (final item in children) {
        final folderId = item.folder?.id;
        final itemId = _normalizeFolderId(
          item.summary.isRoot ? null : item.summary.id,
        );
        final childFolders = folderId == null
            ? const <_FolderListItem>[]
            : _buildVisibleFolderItems(
                parentId: folderId,
              ).where((child) => child.folder != null).toList(growable: false);
        final hasChildren = childFolders.isNotEmpty;
        final isExpanded = folderId != null && expandedIds.contains(folderId);
        items.add(
          _FolderTreeItem(
            item: item,
            depth: depth,
            hasChildren: hasChildren,
            isExpanded: isExpanded,
            isCurrent: itemId != null && itemId == normalizedActiveId,
          ),
        );
        if (isExpanded) {
          addChildren(folderId, depth + 1);
        }
      }
    }

    addChildren(null, 1);
    return items;
  }

  bool get _canCreateInCurrentFolder {
    if (!_activeStorageSpace.enabled || !_canWriteActiveStorage) {
      return false;
    }
    final currentFolderId = _normalizeFolderId(_activeFolderId);
    return currentFolderId == null || _findFolderById(currentFolderId) != null;
  }

  String get _currentFolderTitle {
    final currentFolderId = _normalizeFolderId(_activeFolderId);
    if (currentFolderId == null) {
      return _activeStorageSpaceLabel;
    }
    return _findFolderById(currentFolderId)?.displayName ??
        _activeFolderLabel ??
        'Folder';
  }

  Future<void> _renameFile(_DriveFile file) async {
    if (!_ensureWorkspaceMutationReady()) {
      return;
    }
    final controller = TextEditingController(text: file.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename file'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'New name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );

    if (newName == null || newName.isEmpty || newName == file.name) {
      return;
    }

    try {
      final updates = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (file.isEncrypted || _fileNeedsLocalNameDecryption(file)) {
        final encryptionKeyString = await _encryptionKeyStringForFile(
          file,
          interactive: true,
        );
        if (encryptionKeyString == null) {
          _showMessage('Unlock this file before renaming encrypted files.');
          return;
        }
        final sanitizedName = _sanitizeFileName(newName);
        updates['encryptedName'] = await _encryptFileName(
          sanitizedName,
          encryptionKey: encryptionKeyString,
        );
        updates['originalName'] = FieldValue.delete();
      } else {
        updates['originalName'] = newName;
      }

      // Keep object keys immutable; only update metadata.
      await widget.firestore.collection('files').doc(file.id).update(updates);
      _showMessage('File renamed to $newName');
    } catch (error) {
      _handleWorkspaceMutationFailure(
        WorkspaceMutationAction.renameFile,
        error,
      );
    }
  }

  List<_FolderListItem> _buildFolderSummaries() {
    final activeFolders = _folders
        .where(_folderMatchesActiveStorageSpace)
        .toList(growable: false);
    final activeFiles = _files
        .where(_fileMatchesActiveStorageSpace)
        .toList(growable: false);
    final Map<String, _DriveFolder> folderMap = <String, _DriveFolder>{
      for (final folder in activeFolders) folder.id: folder,
    };

    final Map<String, _FolderAccumulator> folders =
        <String, _FolderAccumulator>{
          'root': _FolderAccumulator(
            id: 'root',
            displayName: _activeStorageSpaceLabel,
            isRoot: true,
          ),
        };

    for (final folder in activeFolders) {
      if (folder.parentId != null) continue; // Skip subfolders in the root list
      final accumulator = folders.putIfAbsent(
        folder.id,
        () => _FolderAccumulator(
          id: folder.id,
          displayName: folder.displayName,
          isRoot: false,
          colorHex: folder.colorHex,
          isSystem: folder.systemFolder,
        ),
      );
      accumulator.displayName = folder.displayName;
      accumulator.colorHex = folder.colorHex;
      accumulator.isSystem = folder.systemFolder;
    }

    for (final file in activeFiles) {
      if (file.isFolder) {
        continue;
      }
      final key = _resolvedFolderKeyForFile(file);
      final folder = folderMap[key];
      final accumulator = folders.putIfAbsent(
        key,
        () => _FolderAccumulator(
          id: key,
          displayName: folder?.displayName ?? file.folderLabel,
          isRoot: key == 'root',
          colorHex: folder?.colorHex,
          isSystem: folder?.systemFolder ?? false,
        ),
      );
      accumulator.itemCount += 1;
      accumulator.totalBytes += file.size;
      if (!accumulator.isRoot) {
        final preferredName = folder?.displayName ?? file.folderLabel;
        if (preferredName.isNotEmpty) {
          accumulator.displayName = preferredName;
        }
        accumulator.colorHex ??= folder?.colorHex;
        accumulator.isSystem = folder?.systemFolder ?? accumulator.isSystem;
      }
    }

    if (_activeStorageScope == 'personal') {
      for (final config in _backupFolders.values) {
        final id = _backupFolderIdForDisplay(config);
        final friendlyName = config.remoteFolder.trim();
        final accumulator = folders.putIfAbsent(
          id,
          () => _FolderAccumulator(
            id: id,
            displayName: friendlyName.isEmpty ? 'Backup' : friendlyName,
            isRoot: false,
            colorHex: '#E8F0FE',
            isSystem: true,
          ),
        );
        if (friendlyName.isNotEmpty) {
          accumulator.displayName = friendlyName;
        }
        accumulator.colorHex ??= '#E8F0FE';
        accumulator.isSystem = true;
      }
    }

    final List<_FolderListItem> items = <_FolderListItem>[];

    final rootAccumulator = folders.remove('root');
    if (rootAccumulator != null) {
      items.add(
        _FolderListItem(summary: rootAccumulator.toSummary(), folder: null),
      );
    }

    final sorted = folders.values.toList()
      ..sort((a, b) {
        final folderA = folderMap[a.id];
        final folderB = folderMap[b.id];
        final activityA =
            folderA?.activity ?? DateTime.fromMillisecondsSinceEpoch(0);
        final activityB =
            folderB?.activity ?? DateTime.fromMillisecondsSinceEpoch(0);
        final compare = activityB.compareTo(activityA);
        if (compare != 0) {
          return compare;
        }
        return a.displayName.toLowerCase().compareTo(
          b.displayName.toLowerCase(),
        );
      });

    for (final accumulator in sorted) {
      items.add(
        _FolderListItem(
          summary: accumulator.toSummary(),
          folder: folderMap[accumulator.id],
        ),
      );
    }

    return items;
  }

  Future<void> _deleteSelectedItems() async {
    if (!_ensureWorkspaceMutationReady()) {
      return;
    }
    final selectedFiles = _selectedFiles();
    final selectedFolders = _selectedFolderItems()
        .map((item) => item.folder)
        .whereType<_DriveFolder>()
        .where((folder) => folder.canDelete)
        .toList(growable: false);
    final count = selectedFiles.length + selectedFolders.length;
    if (count == 0) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete selected items?'),
        content: Text(
          'Move $count item(s) to the recycle bin? Encrypted file objects remain recoverable for 30 days.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final deletePlan = buildWorkspaceDeleteSelectionPlan(
      folderParentIds: <String, String?>{
        for (final folder in _folders)
          folder.id: _normalizeFolderId(folder.parentId),
      },
      selectedFolderIds: selectedFolders.map((folder) => folder.id),
      selectedFileFolderIds: <String, String?>{
        for (final file in selectedFiles)
          file.id: _resolvedFolderKeyForFile(file),
      },
    );
    final selectedRootFolders = selectedFolders
        .where((folder) => deletePlan.rootFolderIds.contains(folder.id))
        .toList(growable: false);
    final standaloneSelectedFiles = selectedFiles
        .where((file) => deletePlan.standaloneFileIds.contains(file.id))
        .toList(growable: false);

    try {
      for (final folder in selectedRootFolders) {
        final removed = await _deleteFolder(
          folder,
          deleteContents: true,
          skipConfirmation: true,
          announceSuccess: false,
          failureAction: WorkspaceMutationAction.deleteItems,
        );
        if (!removed) {
          return;
        }
      }
      for (final file in standaloneSelectedFiles) {
        await _secureDriveService.moveFileToTrash(file.id);
      }
      _showMessage('Moved selected items to the recycle bin.');
      _clearSelection();
    } catch (error) {
      _handleWorkspaceMutationFailure(
        WorkspaceMutationAction.deleteItems,
        error,
      );
    }
  }

  Future<void> _moveSelectedItems() async {
    if (!_ensureWorkspaceMutationReady()) {
      return;
    }
    final selectedFiles = _selectedFiles();
    final selectedFolders = _selectedFolderItems()
        .map((item) => item.folder)
        .whereType<_DriveFolder>()
        .toList(growable: false);
    if (selectedFiles.isEmpty && selectedFolders.isEmpty) {
      return;
    }
    final selectedFolderIds = selectedFolders
        .map((folder) => folder.id)
        .toSet();

    final destinationFolderId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => FolderPicker(
        folders: _folders,
        movingFolderIds: selectedFolderIds,
        initialParentId: _activeFolderId,
      ),
    );

    if (destinationFolderId == null) {
      return;
    }

    final targetId = normalizeWorkspaceFolderId(destinationFolderId);
    final blockedTargetIds = <String>{
      ...selectedFolderIds,
      for (final folder in selectedFolders) ..._descendantFolderIds(folder.id),
    };
    if (targetId != null && blockedTargetIds.contains(targetId)) {
      _showMessage('Cannot move a folder into itself.');
      return;
    }

    _showMessage('Moving items...');

    try {
      final writes = <void Function(WriteBatch)>[];

      Object? folderIdValue(String? folderId) => folderId;
      Object optionalStringValue(String? value) {
        final trimmed = value?.trim();
        return trimmed == null || trimmed.isEmpty
            ? FieldValue.delete()
            : trimmed;
      }

      Object pathSegmentsValue(List<String> segments) => segments;

      final movePlan = buildWorkspaceMovePlan(
        folders: _folders.map(
          (folder) => WorkspaceMoveFolderSnapshot(
            id: folder.id,
            name: folder.displayName,
            parentId: folder.parentId,
            colorHex: folder.colorHex,
          ),
        ),
        files: _files.map(
          (file) => WorkspaceMoveFileSnapshot(
            id: file.id,
            resolvedFolderId: _resolvedFolderIdForFile(file),
          ),
        ),
        selectedFiles: selectedFiles.map(
          (file) => WorkspaceMoveFileSnapshot(
            id: file.id,
            isSecured: file.isEncrypted,
          ),
        ),
        selectedFolderIds: selectedFolderIds,
        destinationFolderId: targetId,
      );

      void addUpdate(
        DocumentReference<Map<String, dynamic>> docRef,
        Map<String, dynamic> payload,
      ) {
        writes.add((batch) => batch.update(docRef, payload));
      }

      Future<void> commitWrites() async {
        const chunkSize = 450;
        for (var start = 0; start < writes.length; start += chunkSize) {
          final batch = widget.firestore.batch();
          final end = min(start + chunkSize, writes.length);
          for (final write in writes.sublist(start, end)) {
            write(batch);
          }
          await batch.commit();
        }
      }

      for (final update in movePlan.selectedFileUpdates) {
        final docRef = widget.firestore.collection('files').doc(update.id);
        addUpdate(docRef, <String, dynamic>{
          'folderId': folderIdValue(update.folderId),
          'folderName': update.clearFolderDecorations
              ? FieldValue.delete()
              : optionalStringValue(update.folderName),
          'folderColor': update.clearFolderDecorations
              ? FieldValue.delete()
              : optionalStringValue(update.folderColor),
          'pathSegments': update.clearFolderDecorations
              ? FieldValue.delete()
              : pathSegmentsValue(update.pathSegments),
        });
      }

      for (final update in movePlan.folderUpdates) {
        final docRef = widget.firestore.collection('folders').doc(update.id);
        final payload = <String, dynamic>{
          'pathSegments': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        };
        if (update.hasParentIdChange) {
          payload['parentId'] = update.parentId;
        }
        addUpdate(docRef, payload);
      }

      for (final update in movePlan.descendantFileUpdates) {
        final docRef = widget.firestore.collection('files').doc(update.id);
        final file = _filesById[update.id];
        addUpdate(docRef, <String, dynamic>{
          'pathSegments': file?.isEncrypted == true
              ? FieldValue.delete()
              : pathSegmentsValue(update.pathSegments),
        });
      }

      await commitWrites();
      _showMessage(
        'Moved ${selectedFiles.length + selectedFolders.length} items.',
      );
      _clearSelection();
    } catch (error) {
      _handleWorkspaceMutationFailure(WorkspaceMutationAction.moveItems, error);
    }
  }

  Future<void> _createFolder({String? parentId}) async {
    if (!_ensureWorkspaceMutationReady()) {
      return;
    }
    final name = await _promptForFolderName(
      title: 'New folder',
      confirmLabel: 'Create',
      initialValue: 'New folder',
    );
    if (!mounted || name == null) {
      return;
    }

    final color =
        _folderAccentPalette[_random.nextInt(_folderAccentPalette.length)];
    final requestedParentId = parentId?.trim();
    final resolvedParentId = requestedParentId == 'root'
        ? null
        : (requestedParentId == null
              ? _normalizeFolderId(_activeFolderId)
              : _normalizeFolderId(requestedParentId));

    if (resolvedParentId != null && _findFolderById(resolvedParentId) == null) {
      _showMessage(
        'New folders can only be created inside My Drive or saved folders.',
      );
      return;
    }

    try {
      final folderId = widget.firestore.collection('folders').doc().id;
      final saved = await _saveEncryptedFolderDocument(
        folderId: folderId,
        name: name,
        color: color,
        parentId: resolvedParentId,
        systemFolder: false,
      );
      if (!saved) {
        return;
      }
      _showMessage('Folder "$name" created.');
    } catch (error) {
      _handleWorkspaceMutationFailure(
        WorkspaceMutationAction.createFolder,
        error,
      );
    }
  }

  Future<void> _renameFolder(_DriveFolder folder) async {
    if (!_ensureWorkspaceMutationReady()) {
      return;
    }
    final name = await _promptForFolderName(
      title: 'Rename folder',
      confirmLabel: 'Rename',
      initialValue: folder.displayName,
    );
    if (!mounted || name == null || name == folder.displayName) {
      return;
    }

    try {
      final saved = await _saveEncryptedFolderDocument(
        folderId: folder.id,
        name: name,
        color: folder.colorHex ?? '#E8F0FE',
        parentId: folder.parentId,
        systemFolder: folder.systemFolder,
        systemKey: folder.systemKey,
      );
      if (!saved) {
        return;
      }

      final filesQuery = await widget.firestore
          .collection('files')
          .where('uid', isEqualTo: widget.user.uid)
          .where('folderId', isEqualTo: folder.id)
          .get();

      for (var offset = 0; offset < filesQuery.docs.length; offset += 400) {
        final batch = widget.firestore.batch();
        final end = min(offset + 400, filesQuery.docs.length);
        for (final doc in filesQuery.docs.sublist(offset, end)) {
          final data = doc.data();
          final mode = _normalizeEncryptionMode(data['encryptionMode']);
          batch.update(
            doc.reference,
            mode == 'secured' || mode == 'standard'
                ? <String, dynamic>{
                    'folderName': FieldValue.delete(),
                    'folderColor': FieldValue.delete(),
                    'pathSegments': FieldValue.delete(),
                  }
                : <String, dynamic>{
                    'folderName': name,
                    'folderColor': folder.colorHex,
                  },
          );
        }
        await batch.commit();
      }

      _showMessage('Folder renamed to $name.');
    } catch (error) {
      _handleWorkspaceMutationFailure(
        WorkspaceMutationAction.renameFolder,
        error,
      );
    }
  }

  Future<bool> _deleteFolder(
    _DriveFolder folder, {
    required bool deleteContents,
    bool skipConfirmation = false,
    bool announceSuccess = true,
    WorkspaceMutationAction failureAction =
        WorkspaceMutationAction.removeFolder,
  }) async {
    if (!_ensureWorkspaceMutationReady()) {
      return false;
    }
    if (!folder.canDelete) {
      _showMessage('System folders cannot be removed.');
      return false;
    }

    final confirm = skipConfirmation
        ? true
        : await showDialog<bool>(
            context: context,
            builder: (context) {
              final actionText = deleteContents
                  ? 'Remove the folder and recycle its files'
                  : 'Remove the folder only';
              final detailText = deleteContents
                  ? 'Files inside remain recoverable from Data safety for 30 days.'
                  : 'Files inside will move back to My Drive.';
              return AlertDialog(
                title: Text('${folder.displayName}?'),
                content: Text('$actionText? $detailText'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: Text(deleteContents ? 'Delete' : 'Remove'),
                  ),
                ],
              );
            },
          );

    if (!mounted || confirm != true) {
      return false;
    }

    try {
      final directChildFolderIds = _folders
          .where(
            (candidate) => _normalizeFolderId(candidate.parentId) == folder.id,
          )
          .map((candidate) => candidate.id)
          .toList(growable: false);
      final descendantFolderIds = _descendantFolderIds(folder.id);
      final directFiles = _files
          .where(
            (file) =>
                !file.isFolder && _resolvedFolderKeyForFile(file) == folder.id,
          )
          .toList(growable: false);

      if (deleteContents) {
        final deletions = <Future<void>>[];
        final filesInTree = _files
            .where(
              (file) =>
                  !file.isFolder &&
                  (_resolvedFolderKeyForFile(file) == folder.id ||
                      descendantFolderIds.contains(
                        _resolvedFolderKeyForFile(file),
                      )),
            )
            .toList(growable: false);
        for (final file in filesInTree) {
          deletions.add(_secureDriveService.moveFileToTrash(file.id));
        }
        final foldersToDelete = <String>{folder.id, ...descendantFolderIds};
        for (final folderId in foldersToDelete) {
          deletions.add(
            widget.firestore.collection('folders').doc(folderId).delete(),
          );
        }
        if (deletions.isNotEmpty) {
          await Future.wait(deletions);
        }
      } else {
        final moves = <Future<void>>[];
        final parentFolderId = _normalizeFolderId(folder.parentId);
        final parentFolder = parentFolderId == null
            ? null
            : _findFolderById(parentFolderId);
        for (final file in directFiles) {
          final payload = file.isEncrypted
              ? <String, dynamic>{
                  'folderId': parentFolderId,
                  'folderName': FieldValue.delete(),
                  'folderColor': FieldValue.delete(),
                  'pathSegments': FieldValue.delete(),
                }
              : <String, dynamic>{
                  'folderId': parentFolderId,
                  'folderName': parentFolder?.displayName,
                  'folderColor': parentFolder?.colorHex,
                };
          moves.add(
            widget.firestore.collection('files').doc(file.id).update(payload),
          );
        }
        for (final childFolderId in directChildFolderIds) {
          moves.add(
            widget.firestore.collection('folders').doc(childFolderId).update(
              <String, dynamic>{'parentId': parentFolderId},
            ),
          );
        }
        if (moves.isNotEmpty) {
          await Future.wait(moves);
        }
        await widget.firestore.collection('folders').doc(folder.id).delete();
      }
      if (announceSuccess) {
        _showMessage(
          deleteContents
              ? 'Folder removed and nested files moved to the recycle bin.'
              : 'Folder removed.',
        );
      }
      return true;
    } catch (error) {
      _handleWorkspaceMutationFailure(failureAction, error);
      return false;
    }
  }

  Future<String?> _promptForFolderName({
    required String title,
    required String confirmLabel,
    String? initialValue,
  }) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return _FolderNameDialog(
          title: title,
          confirmLabel: confirmLabel,
          initialValue: initialValue,
        );
      },
    );

    final trimmed = result?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  Future<void> _showFolderContents(_FolderSummary summary) async {
    _navigateToFolder(
      summary.isRoot ? null : summary.id,
      fallbackLabel: summary.displayName,
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = widget.user.email ?? 'member';
    final name = email.split('@').first;
    final view = _projectWorkspace();
    final offlineEntries = view.offlineEntries;
    final searching = view.searching;
    final currentFolderId = view.currentFolderId;
    final currentPathItems = view.currentPathItems;
    final currentPathLabel = view.currentPathLabel;
    final allFolderItems = view.allFolderItems;
    final folderEmptyMessage = view.folderEmptyMessage;
    final filesTitle = view.filesTitle;
    final filesEmptyMessage = view.filesEmptyMessage;
    final filteredFolders = view.filteredFolders;
    final filteredFiles = view.filteredFiles;
    final filteredOfflineEntries = view.filteredOfflineEntries;
    final backupConfigs = view.backupConfigs;
    final filteredBackupConfigs = view.filteredBackupConfigs;
    final folderTreeItems = view.folderTreeItems;

    final children = <Widget>[
      if (!_feedbackSubmitted)
        ProductFeedbackPrompt(
          key: ValueKey(_feedbackAccountScope),
          accountScope: _feedbackAccountScope,
          enabled:
              !_initializing &&
              !_loadingFiles &&
              !_loadingFolders &&
              _legalAcceptanceCurrent &&
              !_legalAcceptancePromptVisible &&
              !searching &&
              currentFolderId == null,
          onOpen: () => unawaited(_showProductFeedback()),
        ),
    ];
    final quota = _storageLimitBytes;
    if (_storageHasLimit &&
        quota != null &&
        quota > 0 &&
        _trackedUsageBytes() >= quota * 0.8) {
      final nearlyFull = _trackedUsageBytes() >= quota * 0.95;
      children.add(
        Card(
          child: ListTile(
            leading: const Icon(Icons.storage_outlined),
            title: Text(
              nearlyFull
                  ? 'Your storage is nearly full'
                  : 'You have used 80% of your storage',
            ),
            subtitle: const Text(
              'Download or delete files to make room, or choose more storage. Reaching the limit does not require a payment to download your files.',
            ),
            trailing: TextButton(
              onPressed: _manageSubscription,
              child: const Text('Storage plans'),
            ),
          ),
        ),
      );
    }
    final showLoadingBanner = _initializing || _loadingFiles || _loadingFolders;
    final showSeparateStorageCard =
        _storageLocation == _StorageCapacityLocation.summaryCard;
    final legacyMetadataItemCount = _legacyMetadataItemCountForActiveSpace;

    if (!_walkthroughCheckScheduled &&
        _legalAcceptanceCurrent &&
        !_legalAcceptancePromptVisible &&
        !_initializing &&
        !_loadingFiles &&
        !_loadingFolders) {
      _walkthroughCheckScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_maybeShowWorkspaceWalkthrough());
      });
    }

    children.add(
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: showLoadingBanner
            ? const _WorkspaceLoadingBanner(
                key: ValueKey<String>('workspace-loading'),
              )
            : const SizedBox.shrink(
                key: ValueKey<String>('workspace-loading-empty'),
              ),
      ),
    );

    children.add(
      ValueListenableBuilder<bool>(
        valueListenable: paymentProcessingNotifier,
        builder: (context, processing, _) {
          if (!processing) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Card(
              color: Theme.of(context).colorScheme.tertiaryContainer,
              child: ListTile(
                leading: const CircularProgressIndicator(),
                title: const Text('Processing payment...'),
                subtitle: const Text(
                  'Your subscription is being updated. This may take a moment.',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Dismiss payment status',
                  onPressed: () => paymentProcessingNotifier.value = false,
                ),
              ),
            ),
          );
        },
      ),
    );

    if (showLoadingBanner) {
      children.add(const SizedBox(height: 16));
    }

    if (UploadCoordinator.enabled) {
      children.add(UploadTransferTray(
        onReview: _openDataSafetyCenter, onCancel: _requestForegroundUploadCancel));
    }
    children.add(WorkspaceTransferStatus(
      controller: _transferController,
      formatBytes: _formatStorageValue,
      onCancel: _requestForegroundUploadCancel,
    ));

    Widget workspaceHeader({bool accountOnly = false}) => _WorkspaceHeader(
      accountOnly: accountOnly,
      hideAccount: !accountOnly,
      name: name,
      sectionTitle: switch (_workspaceDestination) {
        1 => 'Backups',
        2 => 'Offline files',
        3 =>
          defaultTargetPlatform == TargetPlatform.macOS
              ? 'Finder'
              : 'File Explorer',
        _ => null,
      },
      email: email,
      onOpenSettings: _showSettingsSheet,
      onSignOut: () {
        LoginPasswordVault.instance.clear();
        unawaited(widget.auth.signOut());
      },
      onManageSubscription: _manageSubscription,
      onDeleteAccount: _confirmAccountDeletion,
      showAccountManagement: !widget.businessMode,
      usedBytes: _usedBytes,
      totalBytes: _totalBytes,
      hasLimit: _storageHasLimit,
      limitPending: _storageLimitPending,
      planLabel: _storagePlanLabel,
      displayMode: _storageDisplay,
      storageLocation: _storageLocation,
      searchController: _searchController,
      onSearchChanged: _handleSearchChanged,
      onSearchClear: _clearSearchQuery,
      pathItems: currentPathItems,
      onPathNavigate: _navigateToFolder,
      tileDensity: _tileDensity,
    );
    children.insert(0, workspaceHeader());
    if (widget.businessMode) { children.insert(1, Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Align(alignment: Alignment.centerLeft, child: OutlinedButton.icon(
        onPressed: _openBusinessOperations, icon: const Icon(Icons.support_agent_outlined),
        label: const Text('Business support & recovery'),
      )),
    )); }

    if (_showSetupChecklist) {
      children.add(
        Card(
          child: ExpansionTile(
            key: PageStorageKey('workspace-setup-${widget.user.uid}'),
            initiallyExpanded: false,
            title: const Text('Setup guide'),
            subtitle: Text(
              _backupFolders.isEmpty
                  ? 'Optional - expand for help getting started'
                  : '${_backupFolders.values.where((folder) => folder.lastSynced != null).length} of ${_backupFolders.length} folders have completed a sync',
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextButton.icon(
                onPressed: () => _maybeShowWorkspaceWalkthrough(force: true),
                icon: const Icon(Icons.help_outline),
                label: const Text('Replay the short tutorial'),
              ),
              ListTile(
                leading: Icon(
                  _backupFolders.isNotEmpty
                      ? Icons.check_circle_outline
                      : Icons.folder_outlined,
                ),
                title: Text(
                  !_supportsPersistentFolderBackups && !kIsWeb
                      ? 'Automatic folder backup is unavailable on this platform'
                      : kIsWeb
                      ? 'Get the desktop app for folder backups'
                      : 'Choose your first backup folder',
                ),
                subtitle: Text(
                  !_supportsPersistentFolderBackups
                      ? _folderBackupUnavailableMessage
                      : 'Only folders you select will be backed up.',
                ),
                onTap: !_supportsPersistentFolderBackups && !kIsWeb
                    ? null
                    : kIsWeb
                    ? () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const DownloadPage(),
                        ),
                      )
                    : _addBackupFolder,
              ),
              ListTile(
                leading: Icon(
                  _setupSettingsReviewed
                      ? Icons.check_circle_outline
                      : Icons.tune,
                ),
                title: const Text('Choose backup and bandwidth settings'),
                subtitle: const Text(
                  'Review background activity and sync frequency for this device.',
                ),
                onTap: () async {
                  await _showSettingsSheet();
                  if (mounted) setState(() => _setupSettingsReviewed = true);
                },
              ),
              const BackupStartupTile(),
              const DesktopDriveSetupTile(),
              if (_supportsBackgroundBackupSources && _backupFolders.isNotEmpty)
                ListTile(
                  leading: Icon(
                    _backupFolders.values.any(
                          (folder) => folder.lastSynced != null,
                        )
                        ? Icons.check_circle_outline
                        : Icons.sync_outlined,
                  ),
                  title: const Text('Backup status updates automatically'),
                  subtitle: const Text(
                    'No confirmation is needed here. Open Backups for progress and any errors.',
                  ),
                  onTap: () => setState(() => _workspaceDestination = 1),
                ),
              TextButton(
                onPressed: () async {
                  setState(() => _showSetupChecklist = false);
                  final prefs = _prefs ?? await SharedPreferences.getInstance();
                  await _writeAccountScopedBoolPreference(
                    prefs,
                    _workspaceWalkthroughCompletedPrefKey,
                    true,
                  );
                },
                child: const Text('Done for now'),
              ),
            ],
          ),
        ),
      );
    }

    final workspaceMutationFailure = _workspaceMutationFailure;
    if (workspaceMutationFailure != null &&
        workspaceMutationFailure.requiresAuthoritativeRefresh) {
      children
        ..add(const SizedBox(height: 12))
        ..add(
          WorkspaceMutationStatusNotice(
            failure: workspaceMutationFailure,
            refreshing: _refreshingWorkspaceMutationState,
            onRefresh: _refreshWorkspaceMutationState,
          ),
        );
    }

    if (_storageInventoryStatus.blocksWrites) {
      children
        ..add(const SizedBox(height: 12))
        ..add(
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: ListTile(
              leading: Icon(
                Icons.cloud_off_outlined,
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
              title: const Text('Uploads temporarily paused'),
              subtitle: Text(_storageInventoryStatus.userMessage),
              isThreeLine: true,
            ),
          ),
        );
    }

    final storageSpaces = _storageSpaces;
    if (storageSpaces.length > 1) {
      children
        ..add(const SizedBox(height: 12))
        ..add(
          _StorageSpaceSwitcher(
            spaces: storageSpaces,
            activeSpace: _activeStorageSpace,
            onSelected: _selectStorageSpace,
          ),
        );
    }

    if (_activeStorageIsBusiness &&
        (!_canReadActiveStorage || !_canWriteActiveStorage)) {
      final uploadOnly = !_canReadActiveStorage && _canWriteActiveStorage;
      final readOnly = _canReadActiveStorage && !_canWriteActiveStorage;
      children
        ..add(const SizedBox(height: 12))
        ..add(
          Card(
            color: Theme.of(context).colorScheme.tertiaryContainer,
            child: ListTile(
              leading: const Icon(Icons.policy_outlined),
              title: Text(
                uploadOnly
                    ? 'Upload-only Business access'
                    : readOnly
                    ? 'Read-only Business access'
                    : 'Business storage access restricted',
              ),
              subtitle: Text(
                uploadOnly
                    ? 'You can add files, but existing file names, previews, '
                          'and decrypted keys are not kept on this device.'
                    : readOnly
                    ? 'You can open and download assigned files, but uploads '
                          'and metadata changes are unavailable.'
                    : 'Existing Business file names, previews, and decrypted '
                          'keys were removed from this session. Ask a company '
                          'administrator to review your access.',
              ),
              isThreeLine: true,
            ),
          ),
        );
    }

    if (_activeStandardEncryptionNeedsUnlock) {
      children
        ..add(const SizedBox(height: 12))
        ..add(
          Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('Unlock encrypted workspace'),
              subtitle: const Text(
                'File and folder names stay hidden as encrypted placeholders '
                'until this device unlocks them. Your password is verified by '
                'sign-in; the derived key stays protected on this device and '
                'is never uploaded.',
              ),
              isThreeLine: true,
              onTap: _activeStandardUnlockPrompt != null
                  ? null
                  : () => unawaited(_runStandardEncryptionUnlockPrompt()),
              trailing: IconButton(
                tooltip: 'Unlock encrypted workspace',
                onPressed: _activeStandardUnlockPrompt != null
                    ? null
                    : () => unawaited(_runStandardEncryptionUnlockPrompt()),
                icon: const Icon(Icons.lock_open_outlined),
              ),
            ),
          ),
        );
    }

    if (_activeStorageUsesMemberEnvelopes) {
      children
        ..add(const SizedBox(height: 12))
        ..add(
          Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: ListTile(
              leading: const Icon(Icons.enhanced_encryption_outlined),
              title: Text(
                _activeBusinessReconciliationCanResume
                    ? 'Resume encrypted access reconciliation'
                    : _businessReconciliationCacheLocked
                    ? 'Unlock device to check encrypted progress'
                    : 'Encrypted before upload',
              ),
              subtitle: Text(
                _activeBusinessReconciliationCanResume
                    ? 'This device has authenticated encrypted progress for '
                          'this space. Resume safely; completed items are '
                          'skipped and file contents remain device-local.'
                    : _businessReconciliationCacheLocked
                    ? 'The device credential store is locked. Existing '
                          'encrypted progress is retained and will not be '
                          'replaced with readable local state.'
                    : 'Files and folder names are protected with keys wrapped '
                          'only for authorized members. Reconcile after '
                          'membership changes; removed access triggers fresh '
                          'file keys and encrypted provider objects while '
                          'plaintext stays on this device.',
              ),
              isThreeLine: _businessFileAccessStatus != null,
              onTap:
                  _refreshingBusinessFileAccess ||
                      !_canReadActiveStorage ||
                      !_canWriteActiveStorage
                  ? null
                  : () => unawaited(_refreshBusinessMemberAccess()),
              trailing: _refreshingBusinessFileAccess
                  ? IconButton(
                      tooltip: _pauseBusinessReconciliationRequested
                          ? 'Pausing after current item'
                          : 'Pause safely',
                      onPressed: _pauseBusinessReconciliationRequested
                          ? null
                          : _pauseBusinessReconciliation,
                      icon: _pauseBusinessReconciliationRequested
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.pause_circle_filled_outlined),
                    )
                  : IconButton(
                      tooltip: _activeBusinessReconciliationCanResume
                          ? 'Resume encrypted member access'
                          : 'Reconcile encrypted member access',
                      onPressed:
                          !_canReadActiveStorage || !_canWriteActiveStorage
                          ? null
                          : () => unawaited(_refreshBusinessMemberAccess()),
                      icon: Icon(
                        _activeBusinessReconciliationCanResume
                            ? Icons.play_arrow_rounded
                            : Icons.group_add_outlined,
                      ),
                    ),
            ),
          ),
        );
      if (_businessFileAccessStatus != null) {
        children
          ..add(const SizedBox(height: 6))
          ..add(
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                _businessFileAccessStatus!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          );
      }
    }

    if (!_activeStorageUsesMemberEnvelopes && legacyMetadataItemCount > 0) {
      children
        ..add(const SizedBox(height: 12))
        ..add(
          Card(
            color: Theme.of(context).colorScheme.tertiaryContainer,
            child: ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('Finish protecting folder metadata'),
              subtitle: Text(
                _metadataPrivacyStatus ??
                    '$legacyMetadataItemCount existing item'
                        '${legacyMetadataItemCount == 1 ? '' : 's'} still '
                        'need device-side label protection. Encrypt them on '
                        'this device; once an encrypted label and its recovery '
                        'metadata are saved, redundant readable copies are '
                        'removed.',
              ),
              isThreeLine: true,
              onTap: _protectingLegacyMetadata
                  ? null
                  : () => unawaited(_protectLegacyMetadataForActiveSpace()),
              trailing: _protectingLegacyMetadata
                  ? const SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      tooltip: 'Protect existing folder metadata',
                      onPressed: () =>
                          unawaited(_protectLegacyMetadataForActiveSpace()),
                      icon: const Icon(Icons.lock_reset_outlined),
                    ),
            ),
          ),
        );
    }

    if (!_activeStandardEncryptionNeedsUnlock) {
      children.add(_buildActivityStatus());
    }

    if (showSeparateStorageCard) {
      children
        ..add(const SizedBox(height: 16))
        ..add(
          _CompactStorageSummary(
            usedBytes: _usedBytes,
            totalBytes: _totalBytes,
            hasLimit: _storageHasLimit,
            limitPending: _storageLimitPending,
            displayMode: _storageDisplay,
            planLabel: _storagePlanLabel,
            emphasized: true,
          ),
        );
    }

    children.add(const SizedBox(height: 24));

    Widget buildFoldersSection({bool navigationPane = false}) {
      return _OnlineFoldersSection(
        items: filteredFolders,
        loading: _loadingFolders,
        offlineFolders: Map<String, _OfflineFolderConfig>.unmodifiable(
          _offlineFolders,
        ),
        onOpenFolder: _showFolderContents,
        onCreateFolder: () => unawaited(_createFolder()),
        onToggleOfflineFolder: _toggleFolderOffline,
        searching: searching,
        searchQuery: _searchQuery.trim(),
        hasAnyItems: allFolderItems.isNotEmpty,
        selectedFolderIds: _selectedFolderIds,
        selectionMode: _isSelectionMode,
        onToggleSelection: _toggleFolderSelection,
        createEnabled: _canCreateInCurrentFolder,
        emptyMessage: folderEmptyMessage,
        tileDensity: _tileDensity,
        navigationPane: navigationPane,
        treeItems: navigationPane ? folderTreeItems : const <_FolderTreeItem>[],
      );
    }

    Widget buildFilesSection() {
      return _RecentFilesSection(
        files: List<_DriveFile>.unmodifiable(filteredFiles),
        loading: _loadingFiles,
        offlineKeys: _offlineFiles.keys.toSet(),
        onOpenFile: _openDriveFile,
        expanded: _recentExpanded || searching,
        onToggleExpanded: _toggleRecentExpanded,
        thumbnailFetcher: _fetchThumbnail,
        activeShareLinkCountFor: _activeShareLinkCountFor,
        searching: searching,
        searchQuery: _searchQuery.trim(),
        selectedFileIds: _selectedFileIds,
        selectionMode: _isSelectionMode,
        onToggleSelection: _toggleFileSelection,
        title: filesTitle,
        emptyMessage: filesEmptyMessage,
        allowCollapse: currentFolderId == null,
        tileDensity: _tileDensity,
      );
    }

    if (_workspaceDestination == 0) {
      children.add(
        LayoutBuilder(
          builder: (context, constraints) {
            final canUsePane = constraints.maxWidth >= 760;
            final autoPane = constraints.maxWidth >= 920;
            final usePane = switch (_folderPlacement) {
              _WorkspaceFolderPlacement.auto => autoPane,
              _WorkspaceFolderPlacement.above => false,
              _WorkspaceFolderPlacement.left => canUsePane,
              _WorkspaceFolderPlacement.right => canUsePane,
            };

            if (usePane) {
              final paneWidth = (constraints.maxWidth * 0.28)
                  .clamp(260.0, 340.0)
                  .toDouble();
              final pane = SizedBox(
                width: paneWidth,
                child: buildFoldersSection(navigationPane: true),
              );
              final files = Expanded(child: buildFilesSection());
              final gap = const SizedBox(width: 20);
              final paneOnRight =
                  _folderPlacement == _WorkspaceFolderPlacement.right;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: paneOnRight ? [files, gap, pane] : [pane, gap, files],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                buildFoldersSection(),
                const SizedBox(height: 24),
                buildFilesSection(),
              ],
            );
          },
        ),
      );
    }
    final showOfflineSection = _workspaceDestination == 2;
    if (showOfflineSection) {
      children
        ..add(const SizedBox(height: 24))
        ..add(
          _OfflineFilesSection(
            entries: filteredOfflineEntries,
            onOpenFile: _openOfflineFile,
            onRemove: _removeOfflineFile,
            searching: searching,
            searchQuery: _searchQuery.trim(),
            hadEntries: offlineEntries.isNotEmpty,
          ),
        );
    }

    if (_workspaceDestination == 1 && !kIsWeb && !widget.businessMode) {
      children
        ..add(const SizedBox(height: 24))
        ..add(
          _BackupSection(
            configs: filteredBackupConfigs,
            issues: _backupIssues,
            onRetry: (config) =>
                _runBackupNow(config, allowInteractivePrompt: true),
            onAdd: _addBackupFolder,
            onAddPhotos: IosPhotoLibrary.supported ? _addPhotoBackup : null,
            onManagePhotos: IosPhotoLibrary.supported
                ? _managePhotoAccess
                : null,
            onToggle: _toggleBackup,
            onRemove: _removeBackup,
            progress: Map<String, _BackupProgressStatus>.unmodifiable(
              _backupProgress,
            ),
            searching: searching,
            searchQuery: _searchQuery.trim(),
            hadConfigs: backupConfigs.isNotEmpty,
          ),
        );
    }

    if (_workspaceDestination == 3) {
      children.add(const DesktopDriveSetupTile());
    }

    children.add(const SizedBox(height: 32));

    return DropTarget(
      onDragDone: (details) {
        if (_workspaceDestination != 0) {
          _showMessage('Open Files to upload by drag and drop.');
          return;
        }
        unawaited(
          _runUploadIntent(() async {
            if (!_ensureStorageWritesAvailable()) {
              return;
            }
            final preparedFiles = await _expandDroppedUploadItems(
              details.files,
            );
            if (preparedFiles.isEmpty) {
              _showMessage('No files found to upload.');
              return;
            }
            await _handlePreparedUpload(
              preparedFiles,
              targetFolderId: _activeFolderId,
            );
          }),
        );
      },
      onDragEntered: (details) {
        if (_workspaceDestination != 0) return;
        setState(() {
          _isDragging = true;
        });
      },
      onDragExited: (details) {
        setState(() {
          _isDragging = false;
        });
      },
      child: Scaffold(
        floatingActionButton:
            _workspaceDestination != 0 ||
                _isSelectionMode ||
                !_activeStorageSpace.enabled ||
                (widget.businessMode && !_hasActiveCompanyMembership) ||
                !_canWriteActiveStorage
            ? null
            : ListenableBuilder(
                listenable: _transferController,
                builder: (context, _) {
                  final uploadActionBusy =
                      _isUploading ||
                      _openingUploadSheet ||
                      _transferController.uploadIntentActive;
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.sizeOf(context).width < 1000 ? 80 : 0,
                    ),
                    child: FloatingActionButton.extended(
                      onPressed:
                          uploadActionBusy || _storageInventoryStatus.blocksWrites
                          ? null
                          : _showUploadSheet,
                      tooltip: _storageInventoryStatus.blocksWrites
                          ? 'Uploads temporarily paused'
                          : _isUploading
                          ? 'Uploading...'
                          : _openingUploadSheet
                          ? 'Preparing upload options...'
                          : 'Upload files',
                      icon: uploadActionBusy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.4),
                            )
                          : const Icon(Icons.cloud_upload_outlined, size: 28),
                      label: Text(
                        _isUploading
                            ? 'Uploading'
                            : _openingUploadSheet
                            ? 'Preparing'
                            : 'Upload',
                      ),
                    ),
                  );
                },
              ),
        body: SafeArea(
          child: Stack(
            children: [
              RefreshIndicator(
                onRefresh: _refresh,
                child: WorkspaceNavigationFrame(
                  nativeDriveLabel: !kIsWeb && _isDesktopPlatform
                      ? (defaultTargetPlatform == TargetPlatform.macOS
                            ? 'Finder'
                            : 'File Explorer')
                      : null,
                  account: workspaceHeader(accountOnly: true),
                  selected: _workspaceDestination,
                  backupsAvailable: !kIsWeb && !widget.businessMode,
                  onSettings: _showSettingsSheet,
                  onSelected: (destination) {
                    _clearSelection();
                    _clearSearchQuery();
                    setState(() => _workspaceDestination = destination);
                  },
                  child: Column(
                    children: [
                      Expanded(
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.only(bottom: 96),
                          children: children,
                        ),
                      ),
                      if (_isFreeStorageAccount) const WorkspaceStorageFooter(),
                    ],
                  ),
                ),
              ),
              if (_isSelectionMode)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: MediaQuery.sizeOf(context).width < 1000 ? 80 : 0,
                  child: SelectionActionBar(
                    actions: _buildSelectionActions(),
                    selectedCount:
                        _selectedFileIds.length + _selectedFolderIds.length,
                    onClear: _clearSelection,
                  ),
                ),
              if (_isDragging)
                Positioned.fill(
                  child: Container(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.2),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.cloud_upload,
                            size: 80,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Drop to Upload',
                            style: Theme.of(context).textTheme.displayMedium
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          if (currentPathItems.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              'to $currentPathLabel',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ).withAppPageTitle(
      widget.businessMode
          ? 'Business Workspace | RonikCloud'
          : switch (_workspaceDestination) {
              1 => 'Backups | RonikCloud',
              2 => 'Offline Files | RonikCloud',
              _ => 'Files | RonikCloud',
            },
    );
  }
}
