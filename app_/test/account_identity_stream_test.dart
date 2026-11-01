import 'dart:async';
import 'package:cloud_storage/src/authentication/account_identity_stream.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'binds before publishing, deduplicates and rechecks on resume',
    () async {
      String? current = 'alice';
      final changes = StreamController<String?>();
      final resume = StreamController<void>();
      final order = <String>[];
      final subscription = accountIdentityStream<String>(
        current: () => current,
        identity: (user) => user,
        changes: changes.stream,
        rechecks: resume.stream,
        bindAccount: (id) => order.add('bind:$id'),
      ).listen((user) => order.add('view:$user'));
      await Future<void>.delayed(Duration.zero);
      changes.add('alice');
      await Future<void>.delayed(Duration.zero);
      expect(order, ['bind:alice', 'view:alice']);
      current = 'bob';
      changes.add('alice'); // Stale payload must not revive Alice.
      await Future<void>.delayed(Duration.zero);
      expect(order.skip(2), ['bind:bob', 'view:bob']);
      current = null;
      resume.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(order.skip(4), ['bind:null', 'view:null']);
      await subscription.cancel();
      expect(changes.hasListener, isFalse);
      expect(resume.hasListener, isFalse);
      await changes.close();
      await resume.close();
    },
  );

  test(
    'errors unbind transfers; the next event can restore the same account',
    () async {
      final changes = StreamController<String?>();
      final resume = StreamController<void>();
      final bound = <String?>[];
      var errors = 0;
      final subscription = accountIdentityStream<String>(
        current: () => 'alice',
        identity: (user) => user,
        changes: changes.stream,
        rechecks: resume.stream,
        bindAccount: bound.add,
      ).listen((_) {}, onError: (Object _) => errors++);
      changes.addError(StateError('synthetic'));
      await Future<void>.delayed(Duration.zero);
      expect(bound, ['alice', null]);
      expect(errors, 1);
      changes.add('alice');
      await Future<void>.delayed(Duration.zero);
      expect(bound, ['alice', null, 'alice']);
      await subscription.cancel();
      await changes.close();
      await resume.close();
    },
  );
}
