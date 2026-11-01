# Vendored Flutter Dependencies

This directory contains vendored and patched Flutter packages required by RonikCloud. These packages are configured in [`app_/pubspec.yaml`](../pubspec.yaml) under `dependency_overrides`.

## Inventory

| Package | Upstream Version | Reason for Vendoring | Primary Focus Area |
| --- | --- | --- | --- |
| `cloud_firestore` | `^5.4.4` | Int64 codec safety on Flutter Web, JS interop patching, and transaction boundary compatibility. | Web & Cross-platform |
| `firebase_auth` | `^5.3.1` | Auth credential serialization, Web WASM/JS interop compatibility, and device token isolation. | Auth & Web |
| `desktop_drop` | `^0.7.0` | Custom desktop platform channel handling for drag-and-drop file transfers on Windows, macOS, and Linux. | Desktop (Windows, macOS, Linux) |
| `file_picker` | `^8.0.3` | Large file stream slicing (1 MiB blobs on Web) and native folder picker boundary fixes without memory ballooning. | Web & Desktop |

## Governance Rules

1. **Do not modify without characterization tests**: Any internal patch to a vendored package must be accompanied by unit tests in `app_/test/`.
2. **Track upstream changes**: When upgrading Flutter or Firebase SDKs, check whether upstream has resolved the issue before updating the vendored copy.
3. **Keep changes minimal**: Only change what is strictly necessary for security, performance, or platform stability. Document all modifications in [`PATCH_NOTES.md`](./PATCH_NOTES.md).
