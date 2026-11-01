import 'package:flutter/material.dart';

class StandardEncryptionUnlockDialog extends StatefulWidget {
  const StandardEncryptionUnlockDialog({
    super.key,
    this.title = 'Unlock encrypted files',
    this.description =
        'Enter the password for the current RonikCloud account to unlock encrypted file and folder names on this device.',
    this.submitLabel = 'Unlock',
    this.notice = privacyNotice,
    this.showRecoveryGuidance = true,
  });

  static const String privacyNotice =
      'Your password is checked by sign-in and kept only in memory for this '
      'app session. The derived encryption key stays in this device\'s '
      'protected storage and is never uploaded.';

  final String title;
  final String description;
  final String submitLabel;
  final String notice;
  final bool showRecoveryGuidance;

  @override
  State<StandardEncryptionUnlockDialog> createState() =>
      _StandardEncryptionUnlockDialogState();
}

class _StandardEncryptionUnlockDialogState
    extends State<StandardEncryptionUnlockDialog> {
  final TextEditingController _controller = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.clear();
    _controller.dispose();
    super.dispose();
  }

  void _cancel() {
    FocusScope.of(context).unfocus();
    _controller.clear();
    Navigator.of(context).pop();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final password = _controller.text;
    FocusScope.of(context).unfocus();
    _controller.clear();
    Navigator.of(context).pop(password);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(widget.title)),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Close',
            onPressed: _cancel,
          ),
        ],
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.description),
              const SizedBox(height: 12),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.lock_outline, size: 20),
                      const SizedBox(width: 10),
                      Expanded(child: Text(widget.notice)),
                    ],
                  ),
                ),
              ),
              if (widget.showRecoveryGuidance) ...[
                const SizedBox(height: 12),
                Text(
                  'If an older item no longer opens after a password change, '
                  'use Account Security > Restore from recovery kit.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 16),
              TextFormField(
                controller: _controller,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                autofillHints: const <String>[AutofillHints.password],
                keyboardType: TextInputType.visiblePassword,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  hintText: 'Account password',
                ),
                validator: (value) {
                  if ((value ?? '').isEmpty) {
                    return 'Enter your password.';
                  }
                  return null;
                },
                onFieldSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _cancel, child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: Text(widget.submitLabel)),
      ],
    );
  }
}
