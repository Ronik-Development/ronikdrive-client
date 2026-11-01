import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Unbranded desktop window controls stay at the top-right.
class DesktopWindowFrame extends StatefulWidget {
  const DesktopWindowFrame({super.key, required this.child});
  final Widget child;
  @override
  State<DesktopWindowFrame> createState() => _DesktopWindowFrameState();
}

class _DesktopWindowFrameState extends State<DesktopWindowFrame> {
  static const channel = MethodChannel('ronikcloud/window');
  bool get enabled =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  @override
  void initState() {
    super.initState();
    if (enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => command('configure'));
    }
  }

  Future<void> command(String method) async {
    try {
      await channel.invokeMethod<void>(method);
    } on MissingPluginException {
      /* Widget tests and non-runner previews. */
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!enabled) return widget.child;
    return Overlay.wrap(
      child: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: SizedBox(
              height: 32,
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 12, right: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: Image.asset(
                        'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_128.png',
                        width: 24,
                        height: 24,
                        semanticLabel: 'RonikCloud',
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (_) => command('drag'),
                      onDoubleTap: () => command('maximize'),
                      child: const Tooltip(
                        message:
                            'Drag to move window; double-click to maximize',
                        child: SizedBox.expand(),
                      ),
                    ),
                  ),
                  IconButton(
                    constraints: const BoxConstraints.tightFor(width: 44, height: 32),
                    padding: EdgeInsets.zero,
                    tooltip: 'Minimize window',
                    onPressed: () => command('minimize'),
                    icon: const Icon(Icons.minimize, size: 18),
                  ),
                  IconButton(
                    constraints: const BoxConstraints.tightFor(width: 44, height: 32),
                    padding: EdgeInsets.zero,
                    tooltip: 'Maximize or restore window',
                    onPressed: () => command('maximize'),
                    icon: const Icon(Icons.crop_square, size: 18),
                  ),
                  IconButton(
                    constraints: const BoxConstraints.tightFor(width: 44, height: 32),
                    padding: EdgeInsets.zero,
                    tooltip: 'Close window',
                    onPressed: () => command('close'),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
            ),
          ),
          Expanded(child: widget.child),
        ],
      ),
    );
  }
}
