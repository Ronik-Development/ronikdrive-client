import 'dart:math';

import 'package:flutter/foundation.dart';

class WorkspaceTransferSnapshot {
  const WorkspaceTransferSnapshot({
    required this.messages,
    required this.uploadIntentActive,
    required this.foregroundUploadId,
    required this.cancelRequested,
    required this.totalFiles,
    required this.completedFiles,
    required this.totalBytes,
    required this.transferredBytes,
  });

  final List<String> messages;
  final bool uploadIntentActive;
  final String? foregroundUploadId;
  final bool cancelRequested;
  final int totalFiles;
  final int completedFiles;
  final int totalBytes;
  final int transferredBytes;

  bool get hasForegroundUpload => foregroundUploadId != null;

  double? get progress {
    if (!hasForegroundUpload) {
      return null;
    }
    if (totalFiles > 0 && completedFiles >= totalFiles) {
      return 1;
    }
    if (totalBytes <= 0) {
      return null;
    }
    // Uploading the encrypted bytes is most of the work, but an object is not
    // complete until its encrypted preview (when applicable) and authoritative
    // metadata are finalized. Keeping a small visible remainder prevents the
    // UI from claiming 100% while that required work is still in flight.
    final transferredProgress = (transferredBytes / totalBytes).clamp(0.0, 1.0);
    final finalizedProgress = totalFiles <= 0
        ? 0.0
        : (completedFiles / totalFiles).clamp(0.0, 1.0);
    return (transferredProgress * 0.95 + finalizedProgress * 0.05).clamp(
      0.0,
      0.999,
    );
  }
}

class WorkspaceTransferController extends ChangeNotifier {
  final Map<String, String> _activeTransfers = <String, String>{};
  bool _uploadIntentActive = false;
  String? _foregroundUploadId;
  bool _cancelRequested = false;
  int _totalFiles = 0;
  int _completedFiles = 0;
  int _totalBytes = 0;
  int _transferredBytes = 0;

  WorkspaceTransferSnapshot? _snapshot;

  void _changed() {
    _snapshot = null;
    notifyListeners();
  }

  WorkspaceTransferSnapshot get snapshot =>
      _snapshot ??= WorkspaceTransferSnapshot(
        messages: List<String>.unmodifiable(_activeTransfers.values),
        uploadIntentActive: _uploadIntentActive,
        foregroundUploadId: _foregroundUploadId,
        cancelRequested: _cancelRequested,
        totalFiles: _totalFiles,
        completedFiles: _completedFiles,
        totalBytes: _totalBytes,
        transferredBytes: _transferredBytes,
      );

  bool get cancelRequested => _cancelRequested;
  String? get foregroundUploadId => _foregroundUploadId;
  bool get uploadIntentActive => _uploadIntentActive;

  /// Reserves the complete foreground-upload lifecycle before a picker opens.
  ///
  /// The reservation covers local selection, encryption unlock, Business
  /// recipient checks, encrypted transfer, and metadata finalization. This is
  /// intentionally earlier than [startForegroundUpload]: two browser file
  /// selections must never wait on one shared unlock and then both resume.
  bool tryStartUploadIntent() {
    if (_uploadIntentActive || _foregroundUploadId != null) {
      return false;
    }
    _uploadIntentActive = true;
    _changed();
    return true;
  }

  void finishUploadIntent() {
    if (!_uploadIntentActive) {
      return;
    }
    _uploadIntentActive = false;
    _changed();
  }

  void begin(String id, String label) {
    if (_activeTransfers[id] == label) return;
    _activeTransfers[id] = label;
    _changed();
  }

  void update(String id, String label) {
    if (!_activeTransfers.containsKey(id) || _activeTransfers[id] == label) {
      return;
    }
    _activeTransfers[id] = label;
    _changed();
  }

  void end(String id) {
    if (_activeTransfers.remove(id) != null) _changed();
  }

  void startForegroundUpload({
    required String id,
    required int totalFiles,
    required int totalBytes,
  }) {
    _foregroundUploadId = id;
    _cancelRequested = false;
    _totalFiles = max(0, totalFiles);
    _completedFiles = 0;
    _totalBytes = max(0, totalBytes);
    _transferredBytes = 0;
    _changed();
  }

  void updateForegroundProgress({int? completedFiles, int? transferredBytes}) {
    final nextFiles = (completedFiles ?? _completedFiles)
        .clamp(0, max(0, _totalFiles))
        .toInt();
    final nextBytes = (transferredBytes ?? _transferredBytes)
        .clamp(0, max(0, _totalBytes))
        .toInt();
    if (nextFiles == _completedFiles && nextBytes == _transferredBytes) return;
    _completedFiles = nextFiles;
    _transferredBytes = nextBytes;
    _changed();
  }

  void requestCancel() {
    if (_foregroundUploadId == null || _cancelRequested) return;
    _cancelRequested = true;
    _changed();
  }

  void finishForegroundUpload() {
    _foregroundUploadId = null;
    _cancelRequested = false;
    _totalFiles = 0;
    _completedFiles = 0;
    _totalBytes = 0;
    _transferredBytes = 0;
    _changed();
  }
}
