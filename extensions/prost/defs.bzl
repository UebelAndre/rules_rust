"""# rules_rust_prost

These build rules are used for building [protobufs][protobuf]/[gRPC][grpc] in [Rust][rust] with Bazel
using [Prost][prost] and [Tonic][tonic]

[rust]: http://www.rust-lang.org/
[protobuf]: https://developers.google.com/protocol-buffers/
[grpc]: https://grpc.io
[prost]: https://github.com/tokio-rs/prost
[tonic]: https://github.com/tokio-rs/tonic

## Rules

- [rust_prost_library](#rust_prost_library)
- [rust_prost_toolchain](#rust_prost_toolchain)

## Setup

```python
bazel_dep(name = "rules_rust_prost", version = "{SEE_RELEASE_NOTES}")
```

The `prost` and `tonic` rules do not specify a default toolchain in order to avoid mismatched
dependency issues. To setup the `prost` and `tonic` toolchain, please see the section
[Customizing `prost` and `tonic` Dependencies](#custom-prost-deps).

For additional information about Bazel toolchains, see [here](https://docs.bazel.build/versions/master/toolchains.html).

#### <a name="custom-prost-deps">Customizing `prost` and `tonic` Dependencies

These rules depend on the [`prost`] and [`tonic`] dependencies. To setup the necessary toolchain
for these rules, you must define a toolchain with the [`prost`], [`prost-types`], [`tonic`], [`protoc-gen-prost`], and [`protoc-gen-tonic`] crates as well as the [`protoc`] binary.

[`prost`]: https://crates.io/crates/prost
[`prost-types`]: https://crates.io/crates/prost-types
[`protoc-gen-prost`]: https://crates.io/crates/protoc-gen-prost
[`protoc-gen-tonic`]: https://crates.io/crates/protoc-gen-tonic
[`tonic`]: https://crates.io/crates/tonic
[`protoc`]: https://github.com/protocolbuffers/protobuf

To get access to these crates, declare them in a `Cargo.toml` and resolve it with the
[crate_universe](./crate_universe.md) module extension. For example:

```toml
[package]
name = "prost_deps"
version = "0.0.0"
edition = "2021"
publish = false

[lib]
path = "lib.rs"

[dependencies]
prost = "0.13"
prost-types = "0.13"
protoc-gen-prost = "0.4"
protoc-gen-tonic = "0.4"
tonic = "0.12"
```

```python
crate = use_extension("@rules_rust//crate_universe:extensions.bzl", "crate")
crate.annotation(
    crate = "protoc-gen-prost",
    gen_binaries = ["protoc-gen-prost"],
)
crate.annotation(
    crate = "protoc-gen-tonic",
    gen_binaries = ["protoc-gen-tonic"],
)
crate.from_cargo(
    name = "crates_io",
    cargo_lockfile = "//3rdparty:Cargo.lock",
    lockfile = "//3rdparty:cargo-bazel-lock.json",
    manifests = ["//3rdparty:Cargo.toml"],
)
use_repo(crate, "crates_io")
```

You can then define a toolchain with the `rust_prost_toolchain` rule which uses the crates
defined above. For example:

```python
load("@rules_rust//proto/prost:defs.bzl", "rust_prost_toolchain")
load("@rules_rust//rust:defs.bzl", "rust_library_group")

rust_library_group(
    name = "prost_runtime",
    deps = [
        "@crates_io//prost",
    ],
)

rust_library_group(
    name = "tonic_runtime",
    deps = [
        ":prost_runtime",
        "@crates_io//tonic",
    ],
)

rust_prost_toolchain(
    name = "prost_toolchain_impl",
    prost_plugin = "@crates_io//protoc-gen-prost__protoc-gen-prost",
    prost_runtime = ":prost_runtime",
    prost_types = "@crates_io//prost-types",
    proto_compiler = "@com_google_protobuf//:protoc",
    tonic_plugin = "@crates_io//protoc-gen-tonic__protoc-gen-tonic",
    tonic_runtime = ":tonic_runtime",
)

toolchain(
    name = "prost_toolchain",
    toolchain = "prost_toolchain_impl",
    toolchain_type = "@rules_rust//proto/prost:toolchain_type",
)
```

Lastly, you must register the toolchain in your `MODULE.bazel` file. For example:

```python
register_toolchains("//toolchains:prost_toolchain")
```

---
---
"""

load(
    "//private:prost.bzl",
    _rust_prost_library = "rust_prost_library",
    _rust_prost_toolchain = "rust_prost_toolchain",
)
load(
    "//private:prost_transform.bzl",
    _rust_prost_transform = "rust_prost_transform",
)

rust_prost_library = _rust_prost_library
rust_prost_toolchain = _rust_prost_toolchain
rust_prost_transform = _rust_prost_transform
