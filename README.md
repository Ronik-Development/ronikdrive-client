# RonikCloud client

RonikCloud is a **source-available client with a proprietary backend**.
This repository contains the complete Flutter client, its native platform
code, patched dependencies, assets and client tests. Source snapshots are
published for official releases; this is not the private development repository.

The client continues to connect to the existing RonikCloud service. Server
implementation, server caching, administration and deployment infrastructure
are not included. Encryption, local caching and the network behavior implemented
in the client are readable here. Public endpoints and Firebase client
configuration are connection information, not administrator credentials.

## Build and inspect

Use Flutter **3.38.1**, revision
`b45fa18946ecc2d9b4009952c636ba7e2ffbb787` (Dart 3.10.0), and the platform
toolchain required by Flutter. The patched packages under `app_/vendor/` are
required; retain the checked-in lockfile.

```sh
cd app_
flutter pub get --enforce-lockfile
flutter analyze
flutter test
dart run tool/verify_test_matrix.dart
flutter build web --release --dart-define=RONIKDRIVE_SERVICE_ENVIRONMENT=production
```

Production builds use the existing public client configuration and require a
normal service account. Do not embed administrator keys, storage master keys,
signing credentials or service-account files. Authentication, authorization,
quotas, provider registration and application-integrity checks still apply;
some independently compiled clients cannot use provider-restricted features.
Publishing source does not expand those access rules.

For a build that does not call production, use
`--dart-define=RONIKDRIVE_SERVICE_ENVIRONMENT=local`. The read-only Business
sample (`/business`) can be inspected without a backend. Other local cloud
flows require services that are not distributed in this repository. Staging
requires the operator's existing isolated tester configuration. Release builds
must explicitly select an environment; no isolation checks have been removed.

Windows/Linux desktop compilation needs the corresponding native toolchains.
Android debug builds use the standard debug identity; an unsigned release can
be compiled with `RONIKDRIVE_ALLOW_UNSIGNED_ANDROID_RELEASE=true` in the build
environment. iOS inspection builds use `flutter build ios --no-codesign` on
macOS. Installing or distributing mobile builds requires your own valid signing
setup and any required provider registrations. Official signing keys are private.

## Source for a release

Use the `v<version>+<build>` source tag, for example `v1.0.21+27`.
`source-manifest.json` lists the size, SHA-256 and Git file mode of every
published file except the manifest itself. It includes no private commit IDs,
build-machine paths, timestamps or private repository history.

```sh
python verify_source.py
```

Verification checks the source snapshot's contents. A source tag does not by
itself prove a particular store binary was built from it, and byte-for-byte
reproducible builds are not currently claimed. The backend is private; source
availability is not an independent security audit or proof of server behavior.

## License

First-party code is under [PolyForm Shield 1.0.0](LICENSE), with required
notices in [NOTICE](NOTICE). It permits noncompeting uses and restricts reuse
in competing products and services, including free competitors. Third-party
components retain their own licenses. Read [licensing](app_/LICENSING.md),
[third-party notices](app_/THIRD_PARTY_NOTICES.md), and
[brand policy](app_/TRADEMARKS.md).

Security reports and licensing questions: support@ronikcloud.com.
