import 'package:cloud_storage/src/shared/adaptive_choice_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final scale in [1.0, 2.0, 3.0]) {
    testWidgets('account choices remain readable at text scale $scale', (
      tester,
    ) async {
      var value = false;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 280,
                  child: AdaptiveChoiceControl<bool>(
                    labels: const {false: 'Login', true: 'Create account'},
                    selected: false,
                    onChanged: (next) => value = next,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      if (scale > 1) expect(find.byType(OutlinedButton), findsNWidgets(2));
      await tester.tap(find.text('Create account'));
      expect(value, isTrue);
    });
  }
}
