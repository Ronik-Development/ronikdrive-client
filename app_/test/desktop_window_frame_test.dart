import 'package:cloud_storage/src/shared/desktop_window_frame.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('window actions stay above content and reach the native runner', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('ronikcloud/window'),
      (call) async {
        calls.add(call.method);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('ronikcloud/window'),
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => DesktopWindowFrame(child: child!),
        home: const Scaffold(body: Text('Search')),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, contains('configure'));
    expect(
      tester.getTopLeft(find.byTooltip('Close window')).dy,
      lessThan(tester.getTopLeft(find.text('Search')).dy),
    );
    for (final action in [
      ('Minimize window', 'minimize'),
      ('Maximize or restore window', 'maximize'),
      ('Close window', 'close'),
    ]) {
      await tester.tap(find.byTooltip(action.$1));
      expect(calls.last, action.$2);
    }
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });
}
