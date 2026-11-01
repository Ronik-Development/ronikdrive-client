# Generated Firestore wire bindings

These files are generated from Google's Firestore v1 schemas. They provide wire
messages and the gRPC client/service definitions; they are not an Admin SDK.
The application supplies Firebase user-token metadata, with normal server rules.

`source-manifest.json` records the exact schema commit, source-file hashes and
compiler archive hash. Current inputs:

- googleapis commit `e7513c828b8db536fa12fc5493d541f323aedf90`.
- Schema archive SHA-256 `20001401f3698f67b896ffb2262eadf5645806f7a35a4cf347b5cc31568a7ecf`.
- Protobuf compiler 33.0, official Windows archive SHA-256
  `3742cd49c8b6bd78b6760540367eb0ff62fa70a1032e15dafe131bfaf296986a`.
- Dart `protoc_plugin` 25.1.0, Pub archive SHA-256
  `e6df1acfca57523537da0ce629bf02d5f8378364f18f8a45bd914abd53e48403`.

Regenerate using the project's pinned Dart SDK and an isolated Pub cache. Verify
the immutable archives before running the compiler. Starting with
`google/firestore/v1/firestore.proto`, include the transitive imports listed in
the manifest. Run protoc with `--dart_out=grpc:<this directory>` and the schema
source directory as `--proto_path`. Generate the non-`google/protobuf/` inputs;
well-known types come from the locked official `protobuf` runtime package.
Keep the generated files unmodified and inspect/compile the result before use.
The current generation contains 55 Dart files from 25 input schema files.

The source and generator license notices are preserved alongside this file.
Native Linux runtime support remains disabled pending adapter integration and
acceptance; generated bindings alone do not enable the platform.
