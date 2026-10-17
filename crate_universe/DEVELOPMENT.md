# Developing crate_universe

## Bootstrapping

Crate Universe repository rules are backed by a binary called `cargo-bazel`.
This can be built using cargo by simply changing directories to
`@rules_rust//crate_universe` and running the following:

```shell
cargo build --bin=cargo-bazel
```

It's then recommended to export the `CARGO_BAZEL_GENERATOR_URL` environment
variable to be a `file://` url to the built binary on disk.

```shell
export CARGO_BAZEL_GENERATOR_URL=file://$(pwd)/target/debug/cargo-bazel
```

From here on, the repository rule can be run

## Using non-release rules_rust

If a project does not get `rules_rust` from a release artifact from the Github
releases page (e.g. using an archive from a commit or branch) then `cargo-bazel`
binaries will have to manually be specified for repository rules that consume it.
It's highly recommended to build `cargo-bazel` binaries yourself and host them
somewhere the project can safely access them. Without this, repository rules will
attempt to build the binary using [cargo_bootstrap_repository][cbr] as a fallback.
This is very time consuming and in no way the recommended workflow for anything
other than developing `rules_rust` directly.

[cbr]: https://bazelbuild.github.io/rules_rust/cargo.html#cargo_bootstrap_repository

## Updating vendored crates

A lot of crates are vendored into this repo, e.g. in examples and tests. To
re-vendor them all, a bash script is provided:

```sh
bazel run //crate_universe/tools:vendor
```

## Resolving without Cargo

`splicing_config(experimental_cargo_free = True)` resolves a workspace with the
extracted Cargo crates instead of the `cargo` binary: manifests are read with
`cargo_parser`, dependencies and the lockfile come from `cargo_resolver` against
the registry's sparse index over HTTP, crate archives are downloaded and unpacked
into Cargo's own `$CARGO_HOME/registry` layout, and `cfg(...)` dependencies are
decided by the recorded `rustc --print=cfg` table. The result is the same
`cargo metadata` document the rest of the generator consumes, so rendering is
unchanged, and neither the module extension nor `crates_repository` fetch the Rust
host tools for such a hub. See `src/metadata/cargo_free.rs`.

Not supported yet: git dependencies (which is why this repository's own
`crates_vendor` cannot use it while the extracted crates come from git),
`[patch]` and `[replace]`, git registries and source replacement from
`.cargo/config`, and local vendoring. `cargo_integration_test` checks the mode
against the Cargo-based path on the metadata fixtures.
