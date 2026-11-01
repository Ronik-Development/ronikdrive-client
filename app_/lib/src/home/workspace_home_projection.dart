part of 'workspace_home_page.dart';

// All values stay in this account's widget lifetime; no plaintext persistence.
typedef _WorkspaceProjection = ({
  List<_OfflineEntry> offlineEntries,
  bool searching,
  String? currentFolderId,
  List<_WorkspacePathItem> currentPathItems,
  String currentPathLabel,
  List<_FolderListItem> allFolderItems,
  String folderEmptyMessage,
  String filesTitle,
  String filesEmptyMessage,
  List<_FolderListItem> filteredFolders,
  List<_DriveFile> filteredFiles,
  List<_OfflineEntry> filteredOfflineEntries,
  List<_BackupFolderConfig> backupConfigs,
  List<_BackupFolderConfig> filteredBackupConfigs,
  List<_FolderTreeItem> folderTreeItems,
});

extension _WorkspaceProjectionBuilder on _WorkspaceHomePageState {
  _WorkspaceProjection _projectWorkspace() => _viewCache.resolve(
    (
      widget.user.uid,
      _files.revision,
      _folders.revision,
      _offlineFiles.revision,
      _backupFolders.revision,
      _backupFolderIdsByLocalPath.revision,
      _activeStorageScope,
      _activeStorageGroupId,
      _companyId,
      _activeStorageSpaceLabel,
      _activeStorageSpace.enabled,
      _canReadCompanyStorage,
      _canWriteActiveStorage,
      _activeFolderId,
      _activeFolderLabel,
      _searchQuery,
      _cachedEncryptionKey != null,
      _cachedSecureEncryptionKey != null,
      _businessEncryptionIdentity != null,
    ),
    () {
      final offlineEntries = _files
          .where(
            (file) =>
                _fileMatchesActiveStorageSpace(file) &&
                _canReadStorageScope(file.storageScope) &&
                _offlineFiles.containsKey(file.objectKey),
          )
          .map(
            (file) =>
                _OfflineEntry(file: file, info: _offlineFiles[file.objectKey]!),
          )
          .toList();
      final normalizedQuery = _normalizeSearchQuery(_searchQuery);
      final searchTokens = _searchTokens(_searchQuery);
      final searching = normalizedQuery.isNotEmpty;
      final currentFolderId = _normalizeFolderId(_activeFolderId);
      final currentPathItems = _workspacePathItems();
      final currentPathLabel = _workspacePathLabel();
      final suppressBusinessListing =
          _activeStorageIsBusiness && !_canReadActiveStorage;
      final allFolderItems = searching && !suppressBusinessListing
          ? _buildFolderSummaries()
          : const <_FolderListItem>[];
      final visibleFolderItems = searching || suppressBusinessListing
          ? const <_FolderListItem>[]
          : _buildVisibleFolderItems(parentId: currentFolderId);
      final visibleFiles = searching || suppressBusinessListing
          ? const <_DriveFile>[]
          : _visibleFilesForFolder(currentFolderId);
      final folderEmptyMessage =
          _activeStorageIsBusiness && !_canReadActiveStorage
          ? 'Existing Business folders are hidden because your current role '
                'does not allow downloads.'
          : currentFolderId == null
          ? 'Create a folder to start organizing $_activeStorageSpaceLabel.'
          : (_canCreateInCurrentFolder
                ? 'No subfolders in $_currentFolderTitle yet.'
                : 'This path does not support new subfolders yet.');
      final filesTitle = currentFolderId == null
          ? 'Recent files'
          : 'Files in $_currentFolderTitle';
      final filesEmptyMessage =
          _activeStorageIsBusiness && !_canReadActiveStorage
          ? 'Existing Business files, names, and previews are not retained on '
                'this device without download permission.'
          : currentFolderId == null
          ? 'Upload a non-critical copy, then download it to verify your files. Save a recovery kit in Account Security and keep another backup.'
          : 'No files in $_currentFolderTitle yet. Upload one to place it here.';

      bool matchesFolder(_FolderListItem item) => _matchesSearch(
        normalizedQuery,
        searchTokens,
        _folderSearchValues(item),
      );
      bool matchesFile(_DriveFile file) => _matchesSearch(
        normalizedQuery,
        searchTokens,
        _fileSearchValues(file),
      );
      bool matchesOffline(_OfflineEntry entry) => _matchesSearch(
        normalizedQuery,
        searchTokens,
        _offlineSearchValues(entry),
      );
      bool matchesBackup(_BackupFolderConfig config) => _matchesSearch(
        normalizedQuery,
        searchTokens,
        _backupSearchValues(config),
      );

      final filteredFolders = searching
          ? allFolderItems.where(matchesFolder).toList(growable: false)
          : visibleFolderItems;
      final filteredFiles = searching
          ? suppressBusinessListing
                ? const <_DriveFile>[]
                : _files
                      .where(
                        (file) =>
                            !file.isFolder &&
                            _fileMatchesActiveStorageSpace(file) &&
                            matchesFile(file),
                      )
                      .toList(growable: false)
          : visibleFiles;
      final filteredOfflineEntries = searching
          ? offlineEntries.where(matchesOffline).toList()
          : offlineEntries;
      final backupConfigs = _backupFolders.values.toList()
        ..sort((a, b) => a.remoteFolder.compareTo(b.remoteFolder));
      final filteredBackupConfigs = searching
          ? backupConfigs.where(matchesBackup).toList()
          : backupConfigs;
      final folderTreeItems = searching
          ? const <_FolderTreeItem>[]
          : _buildFolderTreeItems(activeFolderId: currentFolderId);

      return (
        offlineEntries: offlineEntries,
        searching: searching,
        currentFolderId: currentFolderId,
        currentPathItems: currentPathItems,
        currentPathLabel: currentPathLabel,
        allFolderItems: allFolderItems,
        folderEmptyMessage: folderEmptyMessage,
        filesTitle: filesTitle,
        filesEmptyMessage: filesEmptyMessage,
        filteredFolders: filteredFolders,
        filteredFiles: filteredFiles,
        filteredOfflineEntries: filteredOfflineEntries,
        backupConfigs: backupConfigs,
        filteredBackupConfigs: filteredBackupConfigs,
        folderTreeItems: folderTreeItems,
      );
    },
  );
}
