import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'share_email_service.dart';

class ShareLinkDraft {
  const ShareLinkDraft({
    required this.passwordProtected,
    this.password,
    this.recipientEmail,
    required this.expiryDays,
    required this.maxDownloads,
    required this.notifyOnFirstAccess,
  });
  final bool passwordProtected;
  final String? password;
  final String? recipientEmail;
  final int expiryDays;
  final int maxDownloads;
  final bool notifyOnFirstAccess;
}

class CreateShareLinkDialog extends StatefulWidget {
  const CreateShareLinkDialog({super.key});
  @override
  State<CreateShareLinkDialog> createState() => _CreateShareLinkDialogState();
}

class _CreateShareLinkDialogState extends State<CreateShareLinkDialog> {
  final _form = GlobalKey<FormState>();
  final _recipient = TextEditingController();
  final _password = TextEditingController();
  bool _protected = true;
  bool _showPassword = false;
  bool _notify = true;
  int _expiry = 7;
  int _budget = 10;

  @override
  void dispose() {
    _recipient.dispose();
    _password.dispose();
    super.dispose();
  }

  void _create() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(
      context,
      ShareLinkDraft(
        passwordProtected: _protected,
        password: _protected && _password.text.trim().isNotEmpty
            ? _password.text.trim()
            : null,
        recipientEmail: _recipient.text.trim().isEmpty
            ? null
            : _recipient.text.trim(),
        expiryDays: _expiry,
        maxDownloads: _budget,
        notifyOnFirstAccess: _notify,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Share an encrypted file'),
    scrollable: true,
    content: SizedBox(
      width: 440,
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Share an encrypted copy up to 20 MiB. Your original stays private.',
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('share-recipient-email'),
              controller: _recipient,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              enableSuggestions: false,
              maxLength: 254,
              decoration: const InputDecoration(
                labelText: 'Recipient email (optional)',
                helperText: 'Leave blank to copy and share the link yourself.',
                border: OutlineInputBorder(),
              ),
              validator: (value) =>
                  value!.trim().isEmpty ||
                      isValidShareRecipientEmail(value.trim())
                  ? null
                  : 'Enter one valid email address.',
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Require a password'),
              subtitle: const Text(
                'Recommended. Send the password through a separate channel.',
              ),
              value: _protected,
              onChanged: (value) => setState(() => _protected = value),
            ),
            if (_protected) ...[
              TextFormField(
                key: const Key('share-custom-password'),
                controller: _password,
                obscureText: !_showPassword,
                autocorrect: false,
                enableSuggestions: false,
                maxLength: 128,
                decoration: InputDecoration(
                  labelText: 'Choose a password (optional)',
                  helperText:
                      'Leave blank for a strong generated password. Your own must have at least 12 characters.',
                  helperMaxLines: 4,
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                    tooltip: _showPassword ? 'Hide password' : 'Show password',
                    icon: Icon(
                      _showPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                ),
                validator: (value) =>
                    !_protected ||
                        value!.trim().isEmpty ||
                        value.trim().length >= 12
                    ? null
                    : 'Use at least 12 characters.',
              ),
              const Text(
                'RonikCloud emails only the link. It never receives or emails this password.',
              ),
            ] else
              const Text(
                'Anyone with the complete link can decrypt the shared copy. Email opens in your own email app, where you review it and press Send. The private key stays out of RonikCloud’s email service.',
              ),
            const SizedBox(height: 18),
            DropdownButtonFormField<int>(
              initialValue: _expiry,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Link expires',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 1, child: Text('In 1 day')),
                DropdownMenuItem(value: 7, child: Text('In 7 days')),
                DropdownMenuItem(value: 30, child: Text('In 30 days')),
              ],
              onChanged: (value) => setState(() => _expiry = value!),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: _budget,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Encrypted download request budget',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final count in [1, 5, 10, 25, 100])
                  DropdownMenuItem(
                    value: count,
                    child: Text('$count requests'),
                  ),
              ],
              onChanged: (value) => setState(() => _budget = value!),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _notify,
              onChanged: (value) => setState(() => _notify = value!),
              title: const Text('Alert me on first access'),
              subtitle: const Text(
                'A generic account event contains no recipient or file label.',
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const Text(
              'Revoking the link, recycling the source, or losing source sharing/download permission stops future downloads. Copies already downloaded remain with their recipient.',
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _create, child: const Text('Create share link')),
    ],
  );
}

typedef SendProtectedShareEmail =
    Future<void> Function({
      required String recipientEmail,
      required String requestId,
    });

class ShareCreatedDialog extends StatefulWidget {
  const ShareCreatedDialog({
    super.key,
    required this.shareUrl,
    required this.password,
    required this.expiresAt,
    required this.maxDownloads,
    this.recipientEmail,
    required this.sendPasswordLink,
    this.emailOpener,
    this.copyText,
    this.canAccessShare,
    this.sessionStates,
  });
  final Uri shareUrl;
  final String? password;
  final DateTime expiresAt;
  final int maxDownloads;
  final String? recipientEmail;
  final SendProtectedShareEmail sendPasswordLink;
  final Future<bool> Function(Uri)? emailOpener;
  final Future<void> Function(String)? copyText;
  final bool Function()? canAccessShare;
  final Stream<bool>? sessionStates;
  @override
  State<ShareCreatedDialog> createState() => _ShareCreatedDialogState();
}

class _ShareCreatedDialogState extends State<ShareCreatedDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _recipient = TextEditingController(
    text: widget.recipientEmail ?? '',
  );
  final _requestId = newShareEmailRequestId();
  bool _busy = false;
  bool _attempted = false;
  bool _accepted = false;
  String? _message;
  bool _sessionExpired = false;
  StreamSubscription<bool>? _sessionSubscription;

  bool get _canAccess {
    try {
      return !_sessionExpired && (widget.canAccessShare?.call() ?? true);
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _sessionSubscription = widget.sessionStates?.listen(
      (valid) {
        if (!valid && mounted) setState(() => _sessionExpired = true);
      },
      onError: (Object _) {
        if (mounted) setState(() => _sessionExpired = true);
      },
    );
  }

  @override
  void dispose() {
    unawaited(_sessionSubscription?.cancel());
    _recipient.dispose();
    super.dispose();
  }

  Future<void> _copy(String value) async {
    if (!_canAccess) {
      setState(() => _sessionExpired = true);
      return;
    }
    try {
      await (widget.copyText?.call(value) ??
          Clipboard.setData(ClipboardData(text: value)));
      if (mounted) {
        setState(
          () =>
              _message = 'Copied. Share it only with your intended recipient.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Clipboard access is unavailable. Select and copy the value manually.',
        );
      }
    }
  }

  Future<void> _send() async {
    if (!_canAccess) {
      setState(() => _sessionExpired = true);
      return;
    }
    if (_busy || _accepted || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _message = null;
      _attempted = true;
    });
    try {
      if (widget.password != null) {
        await widget.sendPasswordLink(
          recipientEmail: _recipient.text.trim(),
          requestId: _requestId,
        );
        if (!mounted) return;
        if (!_canAccess) {
          setState(() => _sessionExpired = true);
          return;
        }
        setState(() {
          _accepted = true;
          _message =
              'Email accepted for sending. Delivery is not confirmed. Send the password separately.';
        });
      } else {
        final mailto = shareLinkMailto(
          recipientEmail: _recipient.text.trim(),
          completeLink: widget.shareUrl,
        );
        final opened =
            await (widget.emailOpener?.call(mailto) ??
                    launchUrl(mailto, mode: LaunchMode.externalApplication))
                .timeout(const Duration(seconds: 20));
        if (!mounted) return;
        setState(
          () => _message = opened
              ? 'Your email app was opened. Review the message and press Send there.'
              : 'No email app could be opened. Copy the complete link and send it yourself, or retry.',
        );
      }
    } on ShareEmailException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = widget.password != null
              ? 'Email acceptance could not be confirmed. Wait about a minute before retrying this send, or copy the link.'
              : 'Your email app could not be opened. Copy the complete link and send it yourself, or retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Encrypted link ready'),
    scrollable: true,
    content: SizedBox(
      width: 440,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_sessionExpired)
            const Text(
              'Your sign-in or sharing access changed. Close this dialog and open sharing again.',
            )
          else ...[
            Text(
              widget.password != null
                  ? 'Email this link directly. Share the password separately.'
                  : 'Open your email app and press Send there. Anyone with the complete link can open this file.',
            ),
            const SizedBox(height: 14),
            Form(
              key: _form,
              child: TextFormField(
                controller: _recipient,
                readOnly: _attempted && widget.password != null,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                enableSuggestions: false,
                maxLength: 254,
                decoration: const InputDecoration(
                  labelText: 'Recipient email',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => isValidShareRecipientEmail(value!.trim())
                    ? null
                    : 'Enter one valid email address.',
              ),
            ),
            FilledButton.icon(
              onPressed: _busy || _accepted ? null : _send,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      widget.password != null
                          ? Icons.send_outlined
                          : Icons.email_outlined,
                    ),
              label: Text(
                _accepted
                    ? 'Email accepted'
                    : _busy
                    ? 'Please wait…'
                    : widget.password != null
                    ? (_attempted ? 'Retry email' : 'Email link')
                    : 'Open email app',
              ),
            ),
            if (_message case final message?) ...[
              const SizedBox(height: 12),
              Text(message),
            ],
            const SizedBox(height: 12),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Link and access details'),
              childrenPadding: const EdgeInsets.only(bottom: 12),
              expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SelectableText(widget.shareUrl.toString()),
                if (widget.password case final password?) ...[
                  const SizedBox(height: 12),
                  SelectableText('Password: $password'),
                ],
                const SizedBox(height: 12),
                Text('Expires around: ${widget.expiresAt.toLocal()}'),
                Text(
                  'Encrypted download request budget: ${widget.maxDownloads}',
                ),
              ],
            ),
            const Text(
              'If email fails, copy the link below. Copies already downloaded cannot be recalled.',
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy && !_sessionExpired
            ? null
            : () => Navigator.pop(context),
        child: const Text('Done'),
      ),
      if (!_sessionExpired)
        TextButton.icon(
          onPressed: () => _copy(widget.shareUrl.toString()),
          icon: const Icon(Icons.link),
          label: const Text('Copy link'),
        ),
      if (!_sessionExpired && widget.password != null)
        TextButton.icon(
          onPressed: () => _copy(widget.password!),
          icon: const Icon(Icons.copy),
          label: const Text('Copy password'),
        ),
    ],
  );
}
