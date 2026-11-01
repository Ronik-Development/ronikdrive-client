# Client verification

From `app_`, run `flutter analyze`, `flutter test`, and
`dart run tool/verify_test_matrix.dart` using the SDK pinned in the root README.
These checks do not need private server code or signing keys. Golden tests
include platform-specific baselines where provided.

Live integration tests are opt-in and require the corresponding operator
environment. The standalone repository does not ship Firestore rules, indexes,
server emulators, or credentials. Tests gated on live/emulator configuration
remain disabled by default; a skipped integration test is not evidence that
the live service passed.

Before an official release, use authorized staging accounts to verify login,
encrypted upload/download, sharing, and billing handoff. This source snapshot
does not certify that those live acceptance steps have been completed.
