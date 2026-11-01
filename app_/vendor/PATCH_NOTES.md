# Vendored Package Patch Notes & Upgrade Runbook

This document details the modifications applied to the vendored packages in [`app_/vendor/`](./) and outlines the upgrade procedure when bumping Flutter or Firebase dependencies.

---

## 1. `cloud_firestore` (`vendor/cloud_firestore`)

- **Root Cause / Divergence**:
  - In standard `cloud_firestore_web`, large 64-bit integer values (e.g. file sizes in bytes, quota counters, timestamp milliseconds $> 2^{31}$) can trigger runtime exceptions when encoded through the standard JS interop codec.
  - Custom serializers and transaction boundaries are patched to safely handle int64 conversions and boundary validation on Flutter Web without crashing Dart2JS/WASM runtime.
- **Upgrade Instructions**:
  1. Check if upstream `cloud_firestore` / `cloud_firestore_web` has added native int64 BigInt support.
  2. Test Firestore read/write operations for file metadata $> 4\text{ GB}$ using `npm run test:contracts` and `flutter test test/upload_metadata_service_test.dart`.
  3. Re-apply Web codec compatibility patches if necessary.

---

## 2. `firebase_auth` (`vendor/firebase_auth`)

- **Root Cause / Divergence**:
  - Pinned credential serialization and device token lifecycle handlers for cross-platform security (Web, Desktop, Mobile).
  - Ensures session tokens are isolated in memory and credential caches are cleared properly on signout across desktop platforms.
- **Upgrade Instructions**:
  1. Fetch latest upstream `firebase_auth`.
  2. Verify that `login_password_vault.dart` and `account_closure_request_service.dart` tests continue to pass.
  3. Ensure no unauthenticated token leakage occurs during desktop initialization.

---

## 3. `desktop_drop` (`vendor/desktop_drop`)

- **Root Cause / Divergence**:
  - Tailored desktop window event handling for Windows (Win32 drop target COM interface), macOS (NSDraggingDestination), and Linux (GTK / X11 drop).
  - Prevents UI freezes when dropping large directories and ensures correct native file path resolution without leaking file handles.
- **Upgrade Instructions**:
  1. Verify window channel registrations on Windows and macOS.
  2. Run `flutter test test/widget_test.dart` and manual desktop drag-and-drop verification.

---

## 4. `file_picker` (`vendor/file_picker`)

- **Root Cause / Divergence**:
  - Stream-based 1 MiB chunk reading on Flutter Web to prevent the browser from loading whole multi-gigabyte files into Dart heap memory prior to client-side encryption.
  - Native file path streaming and directory traversal safeguards.
- **Upgrade Instructions**:
  1. Check upstream `file_picker` web implementation for stream support (`File.slice()`).
  2. Run `flutter test test/web_upload_stream_policy_test.dart`.
