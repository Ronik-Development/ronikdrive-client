import 'package:flutter/material.dart';
import 'support_report_privacy.dart';

Future<bool> reviewSupportReport(
  BuildContext context,
  SupportReportPayload report,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Review your report'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This text will be readable by support and linked to your account. Automatic filtering cannot recognize every sensitive detail; review it before sending. No files, keys or logs are attached.',
                ),
                const SizedBox(height: 16),
                if (report.title != null) ...[
                  Text(
                    report.title!,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                ],
                SelectableText(report.description),
                if (report.stepsToReproduce != null) ...[
                  const SizedBox(height: 16),
                  const Text('Steps to reproduce'),
                  SelectableText(report.stepsToReproduce!),
                ],
                const SizedBox(height: 16),
                Text(
                  'Platform: ${report.platform} · Build: ${report.buildMode}',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Back to editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send report'),
          ),
        ],
      ),
    ) ??
    false;
