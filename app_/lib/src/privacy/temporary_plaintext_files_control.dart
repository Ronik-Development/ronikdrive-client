import 'package:flutter/material.dart';

typedef CleanupPlaintextTemporaryFiles = Future<int> Function();

class TemporaryPlaintextFilesControl extends StatefulWidget {
  const TemporaryPlaintextFilesControl({super.key, required this.onClear});

  final CleanupPlaintextTemporaryFiles onClear;

  @override
  State<TemporaryPlaintextFilesControl> createState() =>
      _TemporaryPlaintextFilesControlState();
}

class _TemporaryPlaintextFilesControlState
    extends State<TemporaryPlaintextFilesControl> {
  bool _clearing = false;

  Future<void> _clear() async {
    if (_clearing) {
      return;
    }
    setState(() {
      _clearing = true;
    });
    try {
      final removed = await widget.onClear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            removed == 0
                ? 'No RonikCloud temporary decrypted files were found.'
                : 'Cleared $removed temporary decrypted ${removed == 1 ? 'file' : 'files'}.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Some temporary files could not be cleared. RonikCloud will retry automatically.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _clearing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.delete_sweep_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Temporary decrypted files',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'When you open, share, or export a file to another app, RonikCloud creates a private, opaque handoff copy. It expires automatically, but the receiving app may retain its own copy or recent-file history.',
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _clearing ? null : _clear,
              icon: _clearing
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_outline),
              label: Text(_clearing ? 'Clearing...' : 'Clear temporary files'),
            ),
          ],
        ),
      ),
    );
  }
}
