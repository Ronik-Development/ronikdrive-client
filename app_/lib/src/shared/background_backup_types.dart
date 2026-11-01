part of 'background_backup_runner.dart';

class BackgroundBackupSummary {
  const BackgroundBackupSummary({
    this.scannedFiles = 0,
    this.uploadedFiles = 0,
    this.failedFiles = 0,
    this.skippedBecauseForegroundActive = false,
    this.backgroundDisabled = false,
    this.noEligibleConfigs = false,
    this.authRequired = false,
    this.unsupportedSecureMode = false,
    this.initializationFailed = false,
  });

  final int scannedFiles;
  final int uploadedFiles;
  final int failedFiles;
  final bool skippedBecauseForegroundActive;
  final bool backgroundDisabled;
  final bool noEligibleConfigs;
  final bool authRequired;
  final bool unsupportedSecureMode;
  final bool initializationFailed;
}

class BackgroundBackupWatchConfig {
  const BackgroundBackupWatchConfig({
    required this.localPath,
    required this.normalizedLocalPath,
    this.accessBookmark,
    this.accountScope = '',
  });

  final String localPath;
  final String normalizedLocalPath;
  final String? accessBookmark;
  final String accountScope;
}

class _BackgroundBackupSession {
  static const int _fingerprintCheckpointUploadCount = 25;
  static const int _uploadBatchSize = 3;

  _BackgroundBackupSession({
    required this.user,
    required this.auth,
    required this.firestore,
    required this.driveRepository,
    required this.uploadMetadataService,
    required this.prefs,
    required this.storageService,
    required this.secretKey,
    required this.objectKeyOwnerPrefix,
    required this.backupConfigs,
    required this.fingerprints,
  });

  final User user;
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final DriveRepository driveRepository;
  final UploadMetadataService uploadMetadataService;
  final SharedPreferences prefs;
  final WasabiStorageService storageService;
  final SecretKey secretKey;
  final WorkspaceMetadataEncryptionService metadataEncryptionService =
      WorkspaceMetadataEncryptionService();
  final String objectKeyOwnerPrefix;
  final Map<String, _BackgroundBackupConfig> backupConfigs;
  final Map<String, Map<String, _BackgroundBackupFingerprint>> fingerprints;
  Future<TransferJournal>? _journalFuture;

  Future<TransferJournal>
  get _journal => _journalFuture ??= TransferJournal.open(
    preferences: prefs,
    uid: user.uid,
    // Background jobs must not overwrite the foreground isolate's journal.
    scope:
        '${BackgroundBackupRunner._localPrivateCacheScope(auth.app)}:background-uploads',
  );

  void _requireSameAccount() {
    if (auth.currentUser?.uid != user.uid) {
      throw const UploadFailure('unauthorized');
    }
  }

  Future<void> _recoverMetadata() async {
    if (!UploadCoordinator.enabled) return;
    final journal = await _journal;
    for (final entry in journal.entries.where(
      (entry) => entry.canRetryMetadata,
    )) {
      _requireSameAccount();
      await uploadMetadataService.recordUploadedFilePayload(
        entry.metadataPayload!,
      );
      _requireSameAccount();
      await journal.complete(entry.id);
    }
  }

  static Future<_BackgroundBackupSession?> create({
    required User user,
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
    required DriveRepository driveRepository,
    required SharedPreferences prefs,
    required Map<String, _BackgroundBackupConfig> backupConfigs,
    required Map<String, Map<String, _BackgroundBackupFingerprint>>
    fingerprints,
    required _BackgroundBackupScanFrequency scanFrequency,
  }) async {
    BackgroundBackupRunner.log(
      'session',
      'Creating background backup session for ${backupConfigs.length} configured folder(s).',
    );
    final storage = await _resolveStorageService(
      user: user,
      auth: auth,
      firestore: firestore,
    );
    if (storage == null || !storage.service.isConfigured) {
      BackgroundBackupRunner.log(
        'session',
        'Background backup session creation failed because storage is unavailable.',
      );
      return null;
    }

    final salt = storage.encryptionSalt;
    if (salt == null || salt.isEmpty) {
      BackgroundBackupRunner.log(
        'session',
        'Background backup session creation failed because encryption salt is missing.',
      );
      return null;
    }

    late final SecretKey secretKey;
    final storedKey = await LoginPasswordVault.instance
        .restoreStandardEncryptionKey(
          expectedEmail: user.email,
          expectedSalt: salt,
        );
    if (storedKey != null && storedKey.isNotEmpty) {
      secretKey = SecretKey(base64Decode(storedKey));
    } else {
      final credentials = await LoginPasswordVault.instance.restoreCredentials(
        expectedEmail: user.email,
      );
      final password = credentials.password;
      if (password == null || password.isEmpty) {
        BackgroundBackupRunner.log(
          'session',
          'Background backup session creation failed because no standard encryption key is available.',
        );
        return null;
      }

      secretKey = await EncryptionService.instance.deriveKey(
        password: password,
        salt: salt,
      );
      final keyString = base64Encode(await secretKey.extractBytes());
      LoginPasswordVault.instance.storeStandardEncryptionKey(
        email: user.email,
        key: keyString,
        salt: salt,
      );
    }

    final ownerPrefixes = <String>{
      if (storage.storagePrefix != null) storage.storagePrefix!,
      if (storageHomePrefixForUid(user.uid) != null)
        storageHomePrefixForUid(user.uid)!,
      if (sanitizeStorageHomePrefix(user.email) != null)
        sanitizeStorageHomePrefix(user.email)!,
      if (user.uid.trim().isNotEmpty) user.uid.trim(),
    }.toList(growable: false);

    if (ownerPrefixes.isEmpty) {
      BackgroundBackupRunner.log(
        'session',
        'Background backup session creation failed because no storage owner prefix could be derived.',
      );
      return null;
    }

    BackgroundBackupRunner.log(
      'session',
      'Background backup session is ready.',
    );
    return _BackgroundBackupSession(
      user: user,
      auth: auth,
      firestore: firestore,
      driveRepository: driveRepository,
      uploadMetadataService: UploadMetadataService.forApp(auth.app),
      prefs: prefs,
      storageService: storage.service,
      secretKey: secretKey,
      objectKeyOwnerPrefix: ownerPrefixes.first,
      backupConfigs: backupConfigs,
      fingerprints: fingerprints,
    );
  }

  Future<_BackgroundConfigSyncResult> syncConfig(
    _BackgroundBackupConfig config,
  ) async {
    await _recoverMetadata();
    if (config.photoLibrary) return _syncPhotos(config);
    return PersistentFolderAccess.withAccess(
      path: config.localPath,
      bookmark: config.accessBookmark,
      action: () => _syncDirectoryConfig(config),
    );
  }

  Future<_BackgroundConfigSyncResult> _syncDirectoryConfig(
    _BackgroundBackupConfig config,
  ) async {
    final configLabel = BackgroundBackupRunner.localItemDebugLabel(
      '${config.localPath}\u0000${config.remoteFolder}',
    );
    final directory = Directory(config.localPath);
    if (!await directory.exists()) {
      BackgroundBackupRunner.log(
        'backup',
        'Background backup folder is missing ($configLabel).',
      );
      return const _BackgroundConfigSyncResult(failedFiles: 1);
    }
    BackgroundBackupRunner.log(
      'backup',
      'Scanning background backup folder ($configLabel).',
    );

    final normalizedConfigPath = BackgroundBackupRunner._normalizedLocalPath(
      config.localPath,
    );
    final folderId = await metadataEncryptionService.deterministicFolderId(
      namespace: 'backup-root',
      storageSpaceId: 'personal',
      parentId: null,
      normalizedName: BackgroundBackupRunner.normalizeBackupRelativePath(
        config.remoteFolder,
      ),
      key: secretKey,
    );
    await _ensureBackupFolderRecord(
      folderId: folderId,
      folderName: config.remoteFolder,
    );
    final remoteBackupCatalog = await _loadRemoteBackupCatalog(folderId);
    final bucket = fingerprints.putIfAbsent(
      normalizedConfigPath,
      () => <String, _BackgroundBackupFingerprint>{},
    );

    final candidates = <_BackgroundBackupCandidate>[];
    var scannedCount = 0;
    try {
      await for (final entity in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) {
          continue;
        }
        try {
          final stat = await entity.stat();
          scannedCount++;
          final normalizedPath = BackgroundBackupRunner._normalizedLocalPath(
            entity.path,
          );
          final fileSize = max(0, stat.size);
          final modifiedAt = stat.modified.toUtc();
          final relativePath = p.relative(entity.path, from: config.localPath);
          final backupPathHash = await metadataEncryptionService.backupPathTag(
            normalizedRelativePath:
                BackgroundBackupRunner.normalizeBackupRelativePath(
                  relativePath,
                ),
            key: secretKey,
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
            candidates.add(
              _BackgroundBackupCandidate(file: entity, stat: stat),
            );
          }
        } catch (_) {}
      }
    } catch (error) {
      BackgroundBackupRunner.logFailure(
        'backup',
        'folder_scan',
        error,
        itemReference: configLabel,
      );
      return const _BackgroundConfigSyncResult(failedFiles: 1);
    }
    BackgroundBackupRunner.log(
      'backup',
      'Background scan finished for $configLabel with '
          '$scannedCount scanned file(s) and ${candidates.length} pending upload(s).',
    );

    if (candidates.isEmpty) {
      backupConfigs[config.localPath] = config.copyWith(
        lastSynced: DateTime.now(),
      );
      return _BackgroundConfigSyncResult(scannedFiles: scannedCount);
    }

    var uploadedFiles = 0;
    var failedFiles = 0;

    Future<void> uploadCandidates() async {
      for (
        var batchStart = 0;
        batchStart < candidates.length;
        batchStart += _uploadBatchSize
      ) {
        final batchEnd = min(batchStart + _uploadBatchSize, candidates.length);
        final batch = candidates.sublist(batchStart, batchEnd);
        final results = await Future.wait(
          batch.map(
            (candidate) => _syncFile(
              config: config,
              folderId: folderId,
              bucket: bucket,
              candidate: candidate,
            ),
          ),
        );

        for (final result in results) {
          if (result == _BackgroundFileSyncResult.uploaded) {
            uploadedFiles++;
            if (uploadedFiles % _fingerprintCheckpointUploadCount == 0) {
              await persist();
            }
          } else if (result == _BackgroundFileSyncResult.failed) {
            failedFiles++;
          }
        }
      }
    }

    final sessionApi = storageService.uploadSessionApi;
    if (UploadCoordinator.enabled && sessionApi != null) {
      final journal = await _journal;
      final paths = candidates
          .map(
            (candidate) => BackgroundBackupRunner._normalizedLocalPath(
              candidate.file.path,
            ),
          )
          .toSet();
      await UploadCoordinator.instance.prepareBatch(
        resumeSessionIds: journal.pendingEntries
            .where((entry) => paths.contains(entry.localPath))
            .map((entry) => entry.uploadCheckpoint?['sessionId'])
            .whereType<String>()
            .toList(),
        encryptedBytes: candidates.fold<int>(
          0,
          (total, candidate) => total + max<int>(0, candidate.stat.size) + 48,
        ),
        api: sessionApi,
        action: uploadCandidates,
      );
    } else {
      await uploadCandidates();
    }

    backupConfigs[config.localPath] = config.copyWith(
      lastSynced: DateTime.now(),
    );
    BackgroundBackupRunner.log(
      'backup',
      'Background backup summary for $configLabel: '
          '$uploadedFiles uploaded, $failedFiles failed.',
    );
    return _BackgroundConfigSyncResult(
      scannedFiles: scannedCount,
      uploadedFiles: uploadedFiles,
      failedFiles: failedFiles,
    );
  }

  Future<_BackgroundConfigSyncResult> _syncPhotos(
    _BackgroundBackupConfig config,
  ) async {
    if (!IosPhotoLibrary.supported) {
      return const _BackgroundConfigSyncResult(failedFiles: 1);
    }
    var scanned = 0;
    var uploaded = 0;
    var failed = 0;
    var completed = true;
    final timeBudget = Stopwatch()..start();
    final bucket = fingerprints.putIfAbsent(
      BackgroundBackupRunner._normalizedLocalPath(config.localPath),
      () => <String, _BackgroundBackupFingerprint>{},
    );
    try {
      final folderId = await metadataEncryptionService.deterministicFolderId(
        namespace: 'backup-root',
        storageSpaceId: 'personal',
        parentId: null,
        normalizedName: BackgroundBackupRunner.normalizeBackupRelativePath(
          config.remoteFolder,
        ),
        key: secretKey,
      );
      await _ensureBackupFolderRecord(
        folderId: folderId,
        folderName: config.remoteFolder,
      );
      final catalog = await _loadRemoteBackupCatalog(folderId);
      await for (final asset in IosPhotoLibrary.assets()) {
        if (timeBudget.elapsed > const Duration(seconds: 20) ||
            await BackgroundBackupRunner.isForegroundAppActive()) {
          completed = false;
          break;
        }
        if (auth.currentUser?.uid != user.uid) {
          failed++;
          break;
        }
        scanned++;
        final sourcePath = BackgroundBackupRunner._normalizedLocalPath(
          asset.sourcePath,
        );
        final pathTag = await metadataEncryptionService.backupPathTag(
          normalizedRelativePath: asset.token,
          key: secretKey,
        );
        final previous = _referenceBackupFingerprint(
          bucket[sourcePath],
          catalog[pathTag],
          localPath: sourcePath,
        );
        if (previous != null) bucket[sourcePath] = previous;
        if (previous != null && previous.modified == asset.modified) continue;
        IosPhotoExport? exported;
        try {
          exported = await IosPhotoLibrary.export(asset);
          if (auth.currentUser?.uid != user.uid) {
            failed++;
            break;
          }
          final file = File(exported.path);
          final result = await _syncFile(
            config: config,
            folderId: folderId,
            bucket: bucket,
            candidate: _BackgroundBackupCandidate(
              file: file,
              stat: await file.stat(),
              photoAsset: asset,
              photoName: exported.name,
            ),
          );
          if (result == _BackgroundFileSyncResult.failed) {
            failed++;
          } else {
            if (result == _BackgroundFileSyncResult.uploaded) uploaded++;
            // iOS may end this task at any point: persist each completed item.
            await persist();
          }
        } catch (_) {
          failed++;
        } finally {
          if (exported != null) await IosPhotoLibrary.release(exported);
        }
        // Stop on failure (including quota/auth) instead of repeatedly exporting.
        if (failed > 0) break;
      }
      if (failed == 0 && completed) {
        backupConfigs[config.localPath] = config.copyWith(
          lastSynced: DateTime.now(),
        );
      }
    } catch (_) {
      failed++;
    }
    return _BackgroundConfigSyncResult(
      scannedFiles: scanned,
      uploadedFiles: uploaded,
      failedFiles: failed,
    );
  }

  Future<void> persist() async {
    final configsPayload = backupConfigs.values
        .map((config) => config.toJson())
        .toList(growable: false);
    final privateCache = LocalPrivateCachePreferences(
      preferences: prefs,
      uid: user.uid,
      scope: BackgroundBackupRunner._localPrivateCacheScope(auth.app),
    );
    await privateCache.write(
      baseKey: BackgroundBackupRunner.backupConfigsPrefKey,
      namespace: LocalPrivateCacheCodec.backupConfigsNamespace,
      value: jsonEncode(configsPayload),
    );

    final configKeys =
        fingerprints.keys
            .where(
              (key) =>
                  key != BackgroundBackupRunner.backupFingerprintOrphanBucket,
            )
            .toList()
          ..sort();

    final configs = <Map<String, dynamic>>[];
    for (final key in configKeys) {
      final entries = fingerprints[key];
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

    final orphanEntries =
        fingerprints[BackgroundBackupRunner.backupFingerprintOrphanBucket];
    final payload = <String, dynamic>{'version': 2, 'configs': configs};
    if (orphanEntries != null && orphanEntries.isNotEmpty) {
      payload['orphans'] = orphanEntries.values
          .map((fingerprint) => fingerprint.toJson())
          .toList(growable: false);
    }

    await privateCache.write(
      baseKey: BackgroundBackupRunner.backupSignaturesPrefKey,
      namespace: LocalPrivateCacheCodec.backupFingerprintsNamespace,
      value: jsonEncode(payload),
    );
  }

  Future<_BackgroundFileSyncResult> _syncFile({
    required _BackgroundBackupConfig config,
    required String folderId,
    required Map<String, _BackgroundBackupFingerprint> bucket,
    required _BackgroundBackupCandidate candidate,
  }) async {
    final file = candidate.file;
    if (!await file.exists()) {
      return _BackgroundFileSyncResult.skipped;
    }

    final stat = candidate.stat;
    final normalizedPath = BackgroundBackupRunner._normalizedLocalPath(
      candidate.photoAsset?.sourcePath ?? file.path,
    );
    final fileLabel = BackgroundBackupRunner.localItemDebugLabel(
      normalizedPath,
    );
    final fileSize = max(0, stat.size);
    final modifiedAt = candidate.photoAsset?.modified ?? stat.modified.toUtc();
    final previous = bucket[normalizedPath];
    final sameMetadata =
        previous != null &&
        previous.size == fileSize &&
        previous.modified.toUtc().millisecondsSinceEpoch ==
            modifiedAt.millisecondsSinceEpoch;
    if (sameMetadata) {
      return _BackgroundFileSyncResult.skipped;
    }

    String? preUploadHash;
    if (previous != null &&
        ((previous.size == fileSize && previous.hash.isNotEmpty) ||
            previous.remoteIntegrityTag.isNotEmpty)) {
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
          itemReference: fileLabel,
        );
        return _BackgroundFileSyncResult.failed;
      }

      final remoteIntegrityTag = previous.remoteIntegrityTag.trim();
      if (remoteIntegrityTag.isNotEmpty) {
        final currentIntegrityTag = await metadataEncryptionService
            .contentIntegrityTag(sha256Base64: preUploadHash, key: secretKey);
        if (currentIntegrityTag == remoteIntegrityTag) {
          bucket[normalizedPath] = previous.copyWith(
            size: fileSize,
            modified: modifiedAt,
            hash: preUploadHash,
            remoteIntegrityTag: remoteIntegrityTag,
          );
          return _BackgroundFileSyncResult.skipped;
        }
        final previousIntegrityTag = previous.hash.isEmpty
            ? ''
            : await metadataEncryptionService.contentIntegrityTag(
                sha256Base64: previous.hash,
                key: secretKey,
              );
        if (previousIntegrityTag.isEmpty ||
            previousIntegrityTag != remoteIntegrityTag) {
          BackgroundBackupRunner.log(
            'backup',
            'Background upload deferred because the remote encrypted file '
                'changed and needs foreground conflict review.',
          );
          return config.photoLibrary
              ? _BackgroundFileSyncResult.failed
              : _BackgroundFileSyncResult.skipped;
        }
      }

      if (previous.hash == preUploadHash) {
        bucket[normalizedPath] = previous.copyWith(
          size: fileSize,
          modified: modifiedAt,
        );
        return _BackgroundFileSyncResult.skipped;
      }
    }

    final relativePath =
        candidate.photoAsset?.token ??
        p.relative(file.path, from: config.localPath);
    final backupPathHash = await metadataEncryptionService.backupPathTag(
      normalizedRelativePath:
          BackgroundBackupRunner.normalizeBackupRelativePath(relativePath),
      key: secretKey,
    );
    final relativeSegments = relativePath
        .split(Platform.pathSeparator)
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (relativeSegments.isEmpty) {
      return _BackgroundFileSyncResult.skipped;
    }

    final originalFileName = relativeSegments.removeLast();
    final fileName = BackgroundBackupRunner.sanitizeFileName(
      candidate.photoName ?? originalFileName,
    );
    final normalizedRelativeFolderSegments = relativeSegments
        .map(BackgroundBackupRunner.sanitizePathSegment)
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    final leafFolderId = await _ensureFolderPath(
      parentId: folderId,
      pathSegments: normalizedRelativeFolderSegments,
    );
    final encryptedDisplayName = await EncryptionService.instance
        .encryptFileName(fileName, secretKey);
    var objectKey = BackgroundBackupRunner.opaqueObjectKey(
      ownerPrefix: objectKeyOwnerPrefix,
    );
    BackgroundBackupRunner.log('backup', 'event=file_upload_start.');

    final extension = p.extension(fileName).replaceFirst('.', '').toLowerCase();
    final contentType = extension.isNotEmpty
        ? BackgroundBackupRunner._contentTypeByExtension[extension]
        : null;

    TransferJournal? journal;
    String? transferId;
    try {
      UploadSourceSnapshot? sourceSnapshot;
      if (UploadCoordinator.enabled) {
        _requireSameAccount();
        journal = await _journal;
        if (!journal.storageAvailable) throw const UploadFailure('unavailable');
        sourceSnapshot = await UploadSourceSnapshot.capture(file.openRead());
        if (sourceSnapshot.length != fileSize) {
          throw const UploadFailure('source_changed');
        }
        final entry = await openBackupUploadCheckpoint(
          journal: journal,
          sourcePath: normalizedPath,
          folderId: leafFolderId,
          fingerprint: sourceSnapshot.fingerprint,
          length: fileSize,
          createObjectKey: () => objectKey,
        );
        objectKey = entry.objectKey!;
        transferId = entry.id;
      }
      final shouldGenerateThumbnail =
          contentType != null && contentType.startsWith('image/');
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
      await uploadSourceThenOptionalDerivative<Uint8List>(
        uploadSource: () async {
          final source = imageUploadSource == null
              ? hashedUpload?.stream ?? file.openRead()
              : Stream<List<int>>.value(imageUploadSource);
          await storageService.upload(
            transferId: transferId,
            checkpointSink: journal,
            sourceFingerprint: sourceSnapshot?.fingerprint,
            objectKey: objectKey,
            stream: sourceSnapshot?.verify(source) ?? source,
            length: fileSize,
            contentType: contentType,
            encryptionKey: secretKey,
          );
        },
        uploadDerivative: shouldGenerateThumbnail
            ? () async {
                final thumbnailBytes = imageUploadSource == null
                    ? null
                    : await generateBoundedImageThumbnail(imageUploadSource);
                if (thumbnailBytes == null) {
                  return null;
                }
                final thumbnailKey = BackgroundBackupRunner.thumbnailObjectKey(
                  ownerPrefix: objectKeyOwnerPrefix,
                  objectKey: objectKey,
                );
                await UploadCoordinator.instance.withoutBatch(
                  () => storageService.upload(
                    objectKey: thumbnailKey,
                    stream: Stream<List<int>>.value(thumbnailBytes),
                    length: thumbnailBytes.length,
                    contentType: imageThumbnailContentType,
                    encryptionKey: secretKey,
                  ),
                );
                return thumbnailBytes;
              }
            : null,
        onDerivativeError: (error, _) {
          BackgroundBackupRunner.logFailure(
            'backup',
            'optional_preview',
            error,
            itemReference: fileLabel,
          );
        },
        derivativeTimeout: imageThumbnailDerivativeTimeout,
      );
      final resolvedHash = imageUploadHash ?? await hashedUpload!.hashFuture;
      final resolvedIntegrityTag = await metadataEncryptionService
          .contentIntegrityTag(sha256Base64: resolvedHash, key: secretKey);
      final fingerprint = _BackgroundBackupFingerprint(
        localPath: normalizedPath,
        size: fileSize,
        modified: modifiedAt,
        hash: resolvedHash,
        remoteIntegrityTag: resolvedIntegrityTag,
      );

      await _upsertFileRecord(
        journal: journal,
        transferId: transferId,
        objectKey: objectKey,
        size: fileSize,
        folderId: leafFolderId,
        contentIntegrityTag: resolvedIntegrityTag,
        contentIntegrityVersion:
            WorkspaceMetadataEncryptionService.contentIntegrityVersion,
        encryptedName: encryptedDisplayName,
        backupPathHash: backupPathHash,
        backupModifiedMillis: modifiedAt.millisecondsSinceEpoch,
      );

      bucket[normalizedPath] = fingerprint;
      BackgroundBackupRunner.log('backup', 'event=file_upload_completed.');
      return _BackgroundFileSyncResult.uploaded;
    } catch (error) {
      if (journal != null &&
          transferId != null &&
          !journal.entries.any(
            (entry) => entry.id == transferId && entry.canRetryMetadata,
          )) {
        await journal.fail(transferId, error);
      }
      BackgroundBackupRunner.logFailure(
        'backup',
        'file_upload',
        error,
        itemReference: fileLabel,
      );
      return _BackgroundFileSyncResult.failed;
    }
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

  Future<Map<String, BackupCatalogEntry>> _loadRemoteBackupCatalog(
    String folderId,
  ) async {
    Future<Map<String, BackupCatalogEntry>> loadCatalog() {
      return driveRepository.loadBackupCatalog(
        ownerId: user.uid,
        folderId: folderId,
      );
    }

    try {
      return await loadCatalog();
    } on FirebaseException catch (error) {
      if (error.code != 'permission-denied' &&
          error.code != 'unauthenticated' &&
          error.code != 'unavailable') {
        BackgroundBackupRunner.logFailure(
          'backup',
          'remote_catalog_load',
          error,
          itemReference: BackgroundBackupRunner.localItemDebugLabel(folderId),
        );
        return const <String, BackupCatalogEntry>{};
      }

      try {
        await user.getIdToken(true);
        return await loadCatalog();
      } catch (retryError) {
        BackgroundBackupRunner.logFailure(
          'backup',
          'remote_catalog_retry',
          retryError,
          itemReference: BackgroundBackupRunner.localItemDebugLabel(folderId),
        );
        return const <String, BackupCatalogEntry>{};
      }
    } catch (error) {
      BackgroundBackupRunner.logFailure(
        'backup',
        'remote_catalog_load',
        error,
        itemReference: BackgroundBackupRunner.localItemDebugLabel(folderId),
      );
      return const <String, BackupCatalogEntry>{};
    }
  }

  _BackgroundBackupFingerprint? _referenceBackupFingerprint(
    _BackgroundBackupFingerprint? localFingerprint,
    BackupCatalogEntry? remoteEntry, {
    required String localPath,
  }) {
    if (remoteEntry == null) {
      return localFingerprint;
    }
    final remoteIntegrityTag = remoteEntry.contentIntegrityTag.trim();
    final legacyRemoteHash = remoteEntry.legacyHashBase64.trim();
    if (localFingerprint == null) {
      return _BackgroundBackupFingerprint(
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
    return _BackgroundBackupFingerprint(
      localPath: localPath,
      size: remoteEntry.size,
      modified: remoteEntry.modified,
      hash: legacyRemoteHash,
      remoteIntegrityTag: remoteIntegrityTag,
    );
  }

  Future<void> _upsertFileRecord({
    TransferJournal? journal,
    String? transferId,
    required String objectKey,
    required int size,
    required String folderId,
    required String contentIntegrityTag,
    required String contentIntegrityVersion,
    required String encryptedName,
    String? backupPathHash,
    int? backupModifiedMillis,
  }) async {
    final payload = uploadMetadataService.buildRecordUploadedFilePayload(
      objectKey: objectKey,
      size: size,
      folderId: folderId,
      encryptionMode: 'standard',
      storageLayout: 'single',
      contentEncryption: 'standard',
      uploadedAt: DateTime.now().toUtc(),
      contentIntegrityTag: contentIntegrityTag,
      contentIntegrityVersion: contentIntegrityVersion,
      encryptedName: encryptedName,
      backupPathHash: backupPathHash,
      backupModifiedMillis: backupModifiedMillis,
    );
    if (journal != null && transferId != null) {
      await journal.stageMetadataCommit(transferId, payload: payload);
    }
    Future<void> writeRecord() async {
      _requireSameAccount();
      await uploadMetadataService.recordUploadedFilePayload(payload);
      _requireSameAccount();
      if (journal != null && transferId != null) {
        await journal.complete(transferId);
      }
    }

    try {
      await writeRecord();
    } on FirebaseException catch (error) {
      if (error.code != 'permission-denied' &&
          error.code != 'unauthenticated') {
        rethrow;
      }
      await user.getIdToken(true);
      await writeRecord();
    }
  }

  Future<void> _ensureBackupFolderRecord({
    required String folderId,
    required String folderName,
  }) async {
    final docRef = firestore.collection('folders').doc(folderId);
    final resolvedSegments =
        BackgroundBackupRunner.normalizeRemoteFolderSegments(
          folderName,
        ).where((segment) => segment.trim().isNotEmpty).toList(growable: false);
    final displayName = resolvedSegments.isNotEmpty
        ? resolvedSegments.last
        : BackgroundBackupRunner.sanitizePathSegment(folderName);
    final fallbackName = folderName.trim().isEmpty
        ? 'Backup folder'
        : folderName.trim();
    final encryptedName = await metadataEncryptionService.encryptLabel(
      label: displayName.isEmpty ? fallbackName : displayName,
      key: secretKey,
    );

    final payload = <String, dynamic>{
      'uid': user.uid,
      'encryptedName': encryptedName,
      'metadataEncryption':
          WorkspaceMetadataEncryptionService.standardMetadataMode,
      'systemFolder': true,
      'systemKey': 'backup',
      'color': '#E8F0FE',
      'updatedAt': FieldValue.serverTimestamp(),
      'lastFileAt': FieldValue.serverTimestamp(),
    };
    try {
      await _upsertFolderDocument(docRef, payload);
    } catch (error) {
      BackgroundBackupRunner.logFailure(
        'backup',
        'folder_record_upsert',
        error,
        itemReference: BackgroundBackupRunner.localItemDebugLabel(docRef.id),
      );
    }
  }

  Future<String> _ensureFolderPath({
    required String parentId,
    required List<String> pathSegments,
  }) async {
    var currentParentId = parentId;
    final normalizedSegments = pathSegments
        .map(BackgroundBackupRunner.sanitizePathSegment)
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    if (normalizedSegments.isEmpty) {
      return currentParentId;
    }

    for (final segment in normalizedSegments) {
      final folderId = await metadataEncryptionService.deterministicFolderId(
        namespace: 'system-folder',
        storageSpaceId: 'personal',
        parentId: currentParentId,
        normalizedName: segment,
        key: secretKey,
      );
      final docRef = firestore.collection('folders').doc(folderId);
      final encryptedName = await metadataEncryptionService.encryptLabel(
        label: segment,
        key: secretKey,
      );
      final payload = <String, dynamic>{
        'uid': user.uid,
        'encryptedName': encryptedName,
        'metadataEncryption':
            WorkspaceMetadataEncryptionService.standardMetadataMode,
        'parentId': currentParentId,
        'systemFolder': true,
        'systemKey': 'backup',
        'color': '#E8F0FE',
        'updatedAt': FieldValue.serverTimestamp(),
      };
      await _upsertFolderDocument(docRef, payload);
      currentParentId = folderId;
    }

    return currentParentId;
  }

  Future<void> _upsertFolderDocument(
    DocumentReference<Map<String, dynamic>> docRef,
    Map<String, dynamic> payload,
  ) => upsertEncryptedFolderDocument(docRef, payload);

  static Future<_ResolvedBackgroundStorage?> _resolveStorageService({
    required User user,
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
  }) async {
    BackgroundBackupRunner.log(
      'storage',
      'Resolving Wasabi storage for the background backup worker.',
    );
    const profileSnapshotTimeout = Duration(seconds: 8);
    Future<DocumentSnapshot<Map<String, dynamic>>?>
    loadProfileSnapshot() async {
      try {
        return await firestore
            .collection('users')
            .doc(user.uid)
            .get()
            .timeout(profileSnapshotTimeout);
      } catch (_) {
        if (kDebugMode) {
          debugPrint('Background backup could not read secure-storage state.');
        }
        return null;
      }
    }

    var profileSnapshot = await loadProfileSnapshot();
    var storagePrefix = _resolveStoragePrefixFromData(profileSnapshot?.data());
    var encryptionSalt = _extractEncryptionSalt(profileSnapshot?.data());
    var provisioned = _buildWasabiServiceFromData(
      profileSnapshot?.data(),
      user: user,
      auth: auth,
    );

    if (provisioned == null || !provisioned.isConfigured) {
      BackgroundBackupRunner.log(
        'storage',
        'Background backup could not find usable Firestore credentials; requesting provisioning repair.',
      );
      try {
        final normalized = await WasabiProvisioningService.forApp(
          auth.app,
        ).ensureProvisioned(user: auth.currentUser ?? user);
        storagePrefix ??= _resolveStoragePrefixFromData(normalized);
        encryptionSalt ??= _extractEncryptionSalt(normalized);
        final repaired = _buildWasabiServiceFromData(
          normalized,
          user: user,
          auth: auth,
        );
        if (repaired != null && repaired.isConfigured) {
          provisioned = repaired;
          BackgroundBackupRunner.log(
            'storage',
            'Background backup received a usable Wasabi configuration from provisioning repair.',
          );
        }
      } on WasabiProvisioningException {
        if (kDebugMode) {
          debugPrint('Background backup secure-storage repair was not ready.');
        }
      } catch (_) {
        if (kDebugMode) {
          debugPrint(
            'Background backup secure-storage repair was unavailable.',
          );
        }
      }
    }

    if (encryptionSalt == null || encryptionSalt.isEmpty) {
      try {
        profileSnapshot = await loadProfileSnapshot();
        storagePrefix ??= _resolveStoragePrefixFromData(
          profileSnapshot?.data(),
        );
        encryptionSalt = _extractEncryptionSalt(profileSnapshot?.data());
        provisioned ??= _buildWasabiServiceFromData(
          profileSnapshot?.data(),
          user: user,
          auth: auth,
        );
      } catch (_) {
        if (kDebugMode) {
          debugPrint('Background backup could not refresh encryption setup.');
        }
      }
    }

    final environment = WasabiStorageService.fromEnvironment();
    final resolvedService = (provisioned != null && provisioned.isConfigured)
        ? provisioned
        : (environment.isConfigured ? environment : null);
    if (resolvedService == null || !resolvedService.isConfigured) {
      BackgroundBackupRunner.log(
        'storage',
        'Background backup could not resolve a usable Wasabi configuration.',
      );
    } else {
      BackgroundBackupRunner.log(
        'storage',
        'Background backup resolved a usable Wasabi configuration.',
      );
    }
    if (resolvedService == null ||
        !resolvedService.isConfigured ||
        encryptionSalt == null ||
        encryptionSalt.isEmpty) {
      return null;
    }

    return _ResolvedBackgroundStorage(
      service: resolvedService,
      storagePrefix: storagePrefix,
      encryptionSalt: encryptionSalt,
    );
  }

  static WasabiStorageService? _buildWasabiServiceFromData(
    Map<String, dynamic>? data, {
    required User user,
    required FirebaseAuth auth,
  }) {
    final credentialMode = _firstNonEmptyField(data, const <String>[
      'credentialMode',
    ])?.toLowerCase();
    final bucketName = _firstNonEmptyField(data, const <String>[
      'bucketName',
      'wasabiBucketName',
      'bucket',
    ]);
    if (credentialMode != 'server_managed') {
      return null;
    }

    final region =
        _firstNonEmptyField(data, const <String>['region', 'wasabiRegion']) ??
        'us-east-1';
    final endpoint = WasabiStorageService.resolveEndpointForRegion(
      endpointUrl: _firstNonEmptyField(data, const <String>[
        'endpointUrl',
        'wasabiEndpointUrl',
        'wasabiS3Endpoint',
        'endpoint',
      ]),
      region: region,
    );
    final signingRegion =
        _firstNonEmptyField(data, const <String>[
          'signingRegion',
          'wasabiSigningRegion',
        ]) ??
        'us-east-1';
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
        idTokenProvider: accountBoundTokenProvider(auth: auth, uid: user.uid),
        authorizedObjectUri: ReleaseRuntimeConfig.resolveCheckoutApiBaseUri()
            .resolve('storage/wasabi/authorize-object'),
        serverManagedPrefixes: serverManagedScopes,
      );
    } catch (error) {
      BackgroundBackupRunner.logFailure(
        'storage',
        'storage_service_build',
        error,
      );
      return null;
    }
  }

  static String? _resolveStoragePrefixFromData(Map<String, dynamic>? data) {
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
    return sanitizeStorageHomePrefix(
      _firstNonEmptyField(data, const <String>['email']),
    );
  }

  static List<int>? _extractEncryptionSalt(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) {
      return null;
    }

    final rawSalt = data['encryptionSalt'] ?? data['salt'];
    if (rawSalt is String) {
      final trimmed = rawSalt.trim();
      if (trimmed.isEmpty) {
        return null;
      }
      try {
        return base64Decode(trimmed);
      } catch (_) {
        return null;
      }
    }

    if (rawSalt is List<int>) {
      return rawSalt;
    }
    if (rawSalt is Uint8List) {
      return rawSalt;
    }
    if (rawSalt is List) {
      return rawSalt.whereType<num>().map((value) => value.toInt()).toList();
    }
    return null;
  }

  static String? _firstNonEmptyField(
    Map<String, dynamic>? data,
    List<String> keys,
  ) {
    if (data == null || data.isEmpty) {
      return null;
    }
    for (final key in keys) {
      final value = data[key];
      if (value is! String) {
        continue;
      }
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return null;
  }
}

class _ResolvedBackgroundStorage {
  const _ResolvedBackgroundStorage({
    required this.service,
    required this.encryptionSalt,
    this.storagePrefix,
  });

  final WasabiStorageService service;
  final List<int>? encryptionSalt;
  final String? storagePrefix;
}

class _BackgroundBackupConfig {
  const _BackgroundBackupConfig({
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

  _BackgroundBackupConfig copyWith({bool? enabled, DateTime? lastSynced}) {
    return _BackgroundBackupConfig(
      localPath: localPath,
      photoLibrary: photoLibrary,
      accessBookmark: accessBookmark,
      remoteFolder: remoteFolder,
      enabled: enabled ?? this.enabled,
      lastSynced: lastSynced ?? this.lastSynced,
    );
  }

  factory _BackgroundBackupConfig.fromJson(Map<String, dynamic> json) {
    return _BackgroundBackupConfig(
      localPath: json['localPath'] as String? ?? '',
      photoLibrary: json['photoLibrary'] == true,
      accessBookmark: json['accessBookmark'] as String?,
      remoteFolder: json['remoteFolder'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? false,
      lastSynced: json['lastSynced'] == null
          ? null
          : DateTime.tryParse(json['lastSynced'] as String) ?? DateTime.now(),
    );
  }
}

class _BackgroundBackupCandidate {
  const _BackgroundBackupCandidate({
    required this.file,
    required this.stat,
    this.photoAsset,
    this.photoName,
  });

  final File file;
  final FileStat stat;
  final IosPhotoAsset? photoAsset;
  final String? photoName;
}

class _BackgroundBackupFingerprint {
  const _BackgroundBackupFingerprint({
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

  _BackgroundBackupFingerprint copyWith({
    String? localPath,
    int? size,
    DateTime? modified,
    String? hash,
    String? remoteIntegrityTag,
  }) {
    return _BackgroundBackupFingerprint(
      localPath: localPath ?? this.localPath,
      size: size ?? this.size,
      modified: modified ?? this.modified,
      hash: hash ?? this.hash,
      remoteIntegrityTag: remoteIntegrityTag ?? this.remoteIntegrityTag,
    );
  }

  factory _BackgroundBackupFingerprint.fromJson(Map<String, dynamic> json) {
    final rawSize = json['size'];
    var size = 0;
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

    DateTime? modified;
    final modifiedIso = json['modified'] as String?;
    if (modifiedIso != null && modifiedIso.isNotEmpty) {
      modified = DateTime.tryParse(modifiedIso)?.toUtc();
    }
    final rawMillis = json['modifiedMillis'];
    if (modified == null && rawMillis is int) {
      modified = DateTime.fromMillisecondsSinceEpoch(rawMillis, isUtc: true);
    }
    if (modified == null && rawMillis is double) {
      modified = DateTime.fromMillisecondsSinceEpoch(
        rawMillis.round(),
        isUtc: true,
      );
    }

    return _BackgroundBackupFingerprint(
      localPath: json['localPath'] as String? ?? '',
      size: size,
      modified: modified ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      hash: (json['hash'] as String? ?? '').trim(),
      remoteIntegrityTag: (json['remoteIntegrityTag'] as String? ?? '').trim(),
    );
  }
}

class _BackgroundConfigSyncResult {
  const _BackgroundConfigSyncResult({
    this.scannedFiles = 0,
    this.uploadedFiles = 0,
    this.failedFiles = 0,
  });

  final int scannedFiles;
  final int uploadedFiles;
  final int failedFiles;
}

enum _BackgroundFileSyncResult { uploaded, skipped, failed }

enum _BackgroundBackupScanFrequency {
  rapid('rapid', Duration(minutes: 1)),
  standard('standard', Duration(minutes: 2)),
  relaxed('relaxed', Duration(minutes: 5));

  const _BackgroundBackupScanFrequency(this.storageKey, this.interval);

  final String storageKey;
  final Duration interval;

  static _BackgroundBackupScanFrequency fromStorageKey(String? key) {
    for (final option in _BackgroundBackupScanFrequency.values) {
      if (option.storageKey == key) {
        return option;
      }
    }
    return _BackgroundBackupScanFrequency.standard;
  }
}
