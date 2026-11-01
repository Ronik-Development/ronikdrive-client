# Third-party materials

PolyForm Shield applies only to first-party rights. Preserve all notices and
license files in the following components, including local patches, when
redistributing source or binaries. No new restriction is imposed on rights
already granted by their original licenses.

| Material | License and notice location |
| --- | --- |
| Patched FlutterFire `firebase_auth`, `cloud_firestore` | BSD notices in `vendor/firebase_auth/LICENSE` and `vendor/cloud_firestore/LICENSE` |
| Patched `desktop_drop` | Apache-2.0, `vendor/desktop_drop/LICENSE` |
| Patched `file_picker` | MIT, `vendor/file_picker/LICENSE` |
| Generated Firestore wire definitions and Dart generator output | `lib/src/linux_cloud/firestore_wire/LICENSE.googleapis` and `LICENSE.generator`; provenance in that directory |
| Source Sans 3 fonts | SIL Open Font License, `assets/fonts/SourceSans3-OFL.txt` |
| Inter fonts | SIL Open Font License, `assets/fonts/Inter-OFL.txt` |
| Noto Sans fonts | SIL Open Font License, `licenses/Noto-OFL.txt` |
| Gradle wrapper scripts and JAR | Apache-2.0, `licenses/Apache-2.0.txt`; original script headers retained |
| Flutter-generated platform scaffolding and registered plugin declarations | Original Flutter SDK and package licenses; upstream headers retained |

Other dependencies resolved by `pubspec.lock` retain their upstream licenses.
Run `flutter pub get` to obtain them; Flutter collects package licenses into
its runtime license registry. The lockfile is dependency provenance, not a
replacement for each dependency's license. Platform SDKs and build tools are
separately obtained under their providers' terms.

Reference license sources:

- https://github.com/notofonts/noto-fonts/blob/main/LICENSE
- https://www.apache.org/licenses/LICENSE-2.0.txt
