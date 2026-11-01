import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../privacy/memory_preview.dart';

/// No filesystem, WebView, Blob URL, export action or global image cache.
class MemoryFilePreviewPage extends StatefulWidget {
  const MemoryFilePreviewPage({
    super.key,
    required this.name,
    required this.kind,
    required this.guard,
    required this.load,
    this.onLoadFinished,
  });
  final String name;
  final MemoryPreviewKind kind;
  final PreviewReadGuard guard;
  final Future<Uint8List> Function() load;
  final VoidCallback? onLoadFinished;
  @override
  State<MemoryFilePreviewPage> createState() => _MemoryFilePreviewPageState();
}

class _MemoryFilePreviewPageState extends State<MemoryFilePreviewPage>
    with WidgetsBindingObserver {
  List<String>? _rows;
  ui.Image? _image;
  String? _message;
  Timer? _authorizationTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.guard.addListener(_revoked);
    _authorizationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      try {
        widget.guard.check();
      } catch (_) {
        /* guard revokes itself */
      }
    });
    unawaited(_load());
  }

  Future<void> _load() async {
    Uint8List? bytes;
    ui.Image? decoded;
    try {
      widget.guard.check();
      bytes = await widget.load();
      widget.guard.check();
      if (bytes.length > MemoryPreviewPolicy.limit(widget.kind)) {
        throw const PreviewUnavailable();
      }
      if (widget.kind == MemoryPreviewKind.text) {
        final rows = MemoryPreviewPolicy.textRows(bytes);
        widget.guard.check();
        if (mounted) setState(() => _rows = rows);
      } else {
        final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
        ui.ImageDescriptor? descriptor;
        ui.Codec? codec;
        try {
          descriptor = await ui.ImageDescriptor.encoded(buffer);
          widget.guard.check();
          final width = descriptor.width, height = descriptor.height;
          if (width <= 0 ||
              height <= 0 ||
              width > 16384 ||
              height > 16384 ||
              width * height > 40 * 1000 * 1000) {
            throw const PreviewUnavailable();
          }
          final scale = math.min(1.0, 2048 / math.max(width, height));
          codec = await descriptor.instantiateCodec(
            targetWidth: math.max(1, (width * scale).round()),
            targetHeight: math.max(1, (height * scale).round()),
          );
          decoded = (await codec.getNextFrame()).image;
          widget.guard.check();
          if (mounted) {
            setState(() => _image = decoded);
            decoded = null;
          }
        } finally {
          codec?.dispose();
          descriptor?.dispose();
          buffer.dispose();
        }
      }
    } catch (_) {
      if (mounted && widget.guard.cancelled) _revoked();
      if (mounted && !widget.guard.cancelled) {
        setState(
          () => _message =
              'This file could not be verified or displayed. Close the preview and try again.',
        );
      }
    } finally {
      bytes?.fillRange(0, bytes.length, 0);
      decoded?.dispose();
      widget.onLoadFinished?.call();
    }
  }

  void _revoked() {
    _authorizationTimer?.cancel();
    final oldImage = _image;
    _image = null;
    _rows = null;
    if (mounted) {
      setState(
        () => _message =
            'Preview closed for privacy. Return to your files to open it again.',
      );
      // RawImage's render object must release its old handle first.
      WidgetsBinding.instance.addPostFrameCallback((_) => oldImage?.dispose());
    } else {
      oldImage?.dispose();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) widget.guard.cancel();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.guard.removeListener(_revoked);
    widget.guard.cancel();
    _authorizationTimer?.cancel();
    _rows = null;
    _image?.dispose();
    _image = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.guard.cancelled ? 'Preview closed' : widget.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Text(
              'Private preview · No decrypted file is saved by RonikCloud.',
            ),
          ),
          Expanded(child: _body(context)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_message != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_message!, textAlign: TextAlign.center),
        ),
      );
    }
    if (_image != null) {
      return LayoutBuilder(
        builder: (context, constraints) => InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: RawImage(
              image: _image,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
            ),
          ),
        ),
      );
    }
    final rows = _rows;
    if (rows == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Opening private preview…'),
          ],
        ),
      );
    }
    if (rows.isEmpty) return const Center(child: Text('This file is empty.'));
    return SelectionArea(
      child: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: rows.length,
        itemBuilder: (context, index) => Text(
          rows[index].isEmpty ? ' ' : rows[index],
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontFamily: 'monospace',
            height: 1.5,
          ),
        ),
      ),
    );
  }
}
