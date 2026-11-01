import 'dart:async';

/// Account transitions are bound before consumers see them. Read current state
/// instead of queued event payloads, which may belong to an old session.
Stream<T?> accountIdentityStream<T>({
  required T? Function() current,
  required String Function(T) identity,
  required Stream<T?> changes,
  required Stream<void> rechecks,
  required void Function(String?) bindAccount,
}) => Stream<T?>.multi((controller) {
  var active = true;
  var initialized = false;
  String? lastId;
  void publish() {
    if (!active) return;
    final user = current();
    final id = user == null ? null : identity(user);
    if (initialized && id == lastId) return;
    initialized = true;
    lastId = id;
    bindAccount(id);
    controller.add(user);
  }

  publish();
  final auth = changes.listen(
    (_) => publish(),
    onError: (Object error, StackTrace stack) {
      if (!active) return;
      initialized = false;
      bindAccount(null);
      controller.addError(error, stack);
    },
  );
  final resume = rechecks.listen((_) => publish());
  controller.onCancel = () async {
    active = false;
    await Future.wait([auth.cancel(), resume.cancel()]);
  };
});
