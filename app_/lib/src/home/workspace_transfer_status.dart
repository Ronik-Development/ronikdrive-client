import 'package:flutter/material.dart';

import 'workspace_transfer_controller.dart';

/// Subscribes only the transfer presentation, not the workspace listing.
class WorkspaceTransferStatus extends StatelessWidget {
  const WorkspaceTransferStatus({
    super.key,
    required this.controller,
    required this.formatBytes,
    required this.onCancel,
  });
  final WorkspaceTransferController controller;
  final String Function(double) formatBytes;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final snapshot = controller.snapshot;
      if (snapshot.messages.isEmpty) return const SizedBox.shrink();
      return Column(
        children: [
          _TransferStatusCard(
            messages: snapshot.messages,
            progress: snapshot.progress,
            progressLabel: snapshot.hasForegroundUpload
                ? '${snapshot.completedFiles.clamp(0, snapshot.totalFiles)}/${snapshot.totalFiles} finalized, '
                      '${formatBytes(snapshot.transferredBytes.toDouble())} of '
                      '${formatBytes(snapshot.totalBytes.toDouble())} processed'
                : null,
            onCancel: snapshot.hasForegroundUpload && !snapshot.cancelRequested
                ? onCancel
                : null,
            cancelTooltip: 'Cancel remaining uploads',
          ),
          const SizedBox(height: 16),
        ],
      );
    },
  );
}

class _TransferStatusCard extends StatelessWidget {
  const _TransferStatusCard({
    required this.messages,
    this.progress,
    this.progressLabel,
    this.onCancel,
    this.cancelTooltip,
  });

  final List<String> messages;
  final double? progress;
  final String? progressLabel;
  final VoidCallback? onCancel;
  final String? cancelTooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = messages.take(3).toList();
    final extra = messages.length - preview.length;
    final primaryDetail = preview.isEmpty
        ? 'Syncing the latest changes...'
        : preview.join('  -  ');
    final detailText = extra > 0
        ? '$primaryDetail  -  +$extra more'
        : primaryDetail;
    final baseColor =
        theme.textTheme.bodySmall?.color ?? theme.colorScheme.onSurface;
    final subtleStyle = theme.textTheme.bodySmall?.copyWith(
      color: baseColor.withValues(alpha: 0.7),
    );
    final progressValue = progress?.clamp(0.0, 1.0).toDouble();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Transfers in progress',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(detailText, style: theme.textTheme.bodySmall),
                  if (progressLabel != null || progressValue != null) ...[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: SizedBox(
                        height: 7,
                        child: LinearProgressIndicator(value: progressValue),
                      ),
                    ),
                    if (progressLabel != null) ...[
                      const SizedBox(height: 6),
                      Text(progressLabel!, style: subtleStyle),
                    ],
                  ],
                  const SizedBox(height: 4),
                  Text(
                    onCancel == null
                        ? 'Keep the app open until everything finishes syncing.'
                        : 'Cancel stops queued files after the current file.',
                    style: subtleStyle,
                  ),
                ],
              ),
            ),
            if (onCancel != null) ...[
              const SizedBox(width: 12),
              IconButton(
                tooltip: cancelTooltip ?? 'Cancel transfer',
                onPressed: onCancel,
                icon: const Icon(Icons.stop_circle_outlined),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
